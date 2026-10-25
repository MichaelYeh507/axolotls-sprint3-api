import Foundation

// MARK: - Seed data
//
// Resources/seed.json holds sample documents for every collection, written as
// plain JSON:
//   { "referenceNow": "...", "collections": [ { "path": "users", "documents": { "u_anabella": {...} } } ] }
// Before writing, every document is decoded into its struct (so the seed can't
// drift from Models.swift) and every timestamp is moved forward so the seed's
// "now" becomes the real now.

public struct SeedFile: Decodable, Sendable {
    public var referenceNow: Date
    public var collections: [SeedCollection]

    public var documentCount: Int { collections.reduce(0) { $0 + $1.documents.count } }

    public static func load(_ name: String = "seed.json") throws -> SeedFile {
        let data = try Data(contentsOf: Resources.url(name))
        return try JSONCoding.makeDecoder().decode(SeedFile.self, from: data)
    }
}

public struct SeedCollection: Decodable, Sendable {
    public var path: String                       // "users", "groups/g_axolotls/photos", ...
    public var documents: [String: JSONValue]     // document ID -> fields
}

public struct SeedPlan: Sendable {
    public struct Row: Sendable {
        public var collection: String       // "groups/*/photos": subcollections of every group counted together
        public var model: String            // "GroupPhoto"
        public var documents: Int
        public var paths: Int               // how many actual collections, e.g. one photos/ per group
    }
    public var writes: [FirestoreWrite]
    public var summary: [Row]
    public var warnings: [String]
}

public enum Seeder {
    /// Checks every seed document against its struct and returns the Firestore writes.
    public static func plan(_ seed: SeedFile, now: Date = Date()) throws -> SeedPlan {
        let shift = now.timeIntervalSince(seed.referenceNow)
        var writes: [FirestoreWrite] = []
        var summary: [SeedPlan.Row] = []
        var warnings: [String] = []

        for collection in seed.collections {
            guard let kind = CollectionID(path: collection.path) else {
                throw DemoError.seedMismatch(path: collection.path, type: "?", details: "unknown collection name")
            }
            let modelName = String(describing: kind.modelType)
            for (documentID, json) in collection.documents.sorted(by: { $0.key < $1.key }) {
                let path = "\(collection.path)/\(documentID)"
                let checked = try check(kind.modelType, shiftDates(json, by: shift), path: path)
                if !checked.unknownKeys.isEmpty {
                    warnings.append("\(path) has fields that \(modelName) doesn't know: \(checked.unknownKeys.joined(separator: ", "))")
                }
                writes.append(.set(path: path, fields: checked.fields))
            }
            let template = collectionTemplate(collection.path)
            if let index = summary.firstIndex(where: { $0.collection == template }) {
                summary[index].documents += collection.documents.count
                summary[index].paths += 1
            } else {
                summary.append(.init(collection: template, model: modelName, documents: collection.documents.count, paths: 1))
            }
        }
        return SeedPlan(writes: writes, summary: summary, warnings: warnings)
    }

    /// "groups/g_axolotls/photos" -> "groups/*/photos"
    static func collectionTemplate(_ path: String) -> String {
        path.split(separator: "/").enumerated().map { $0.offset % 2 == 1 ? "*" : String($0.element) }.joined(separator: "/")
    }

    /// Decodes into the struct (fails on a missing or wrong-typed field), then encodes back.
    static func check<T: FirestoreDocument>(_ type: T.Type, _ json: JSONValue,
                                            path: String) throws -> (fields: [String: JSONValue], unknownKeys: [String]) {
        let model: T
        do {
            model = try json.decode(as: T.self)
        } catch {
            throw DemoError.seedMismatch(path: path, type: String(describing: T.self), details: describe(error))
        }
        let written = try JSONValue(encoding: model)
        let unknown = Set(json.objectValue.map { Array($0.keys) } ?? [])
            .subtracting(written.objectValue.map { Array($0.keys) } ?? [])
        return (try model.firestoreFields(), unknown.sorted())
    }

    /// Moves every ISO 8601 timestamp in a document by `seconds`.
    public static func shiftDates(_ value: JSONValue, by seconds: TimeInterval) -> JSONValue {
        switch value {
        case .string(let text):
            guard text.count >= 20, text.contains("T"), let date = JSONCoding.parseISO8601(text) else { return value }
            return .string(JSONCoding.formatISO8601(date.addingTimeInterval(seconds)))
        case .array(let items):
            return .array(items.map { shiftDates($0, by: seconds) })
        case .object(let fields):
            return .object(fields.mapValues { shiftDates($0, by: seconds) })
        default:
            return value
        }
    }

    static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return "\(error)" }
        switch decodingError {
        case .keyNotFound(let key, _):
            return "missing field \"\(key.stringValue)\""
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            let field = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "\(context.debugDescription) (field \"\(field)\")"
        @unknown default:
            return "\(error)"
        }
    }
}
