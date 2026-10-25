import Foundation

// MARK: - JSONValue
//
// A JSON value we can look inside and rebuild. The playground needs it for two
// jobs: printing the raw JSON that comes back from an API, and converting
// between our Codable structs and Firestore's REST format, which wraps every
// value in a type tag:
//
//   plain JSON:      { "photo_count": 30, "group_name": "The Axolotls" }
//   Firestore REST:  { "photo_count": { "integerValue": "30" },
//                      "group_name":  { "stringValue": "The Axolotls" } }

public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int64.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: Convenience

extension JSONValue {
    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Parses raw JSON bytes (an API response body).
    public init(data: Data) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Encodes any Codable value, then reads it back as a JSONValue.
    public init<T: Encodable>(encoding value: T, encoder: JSONEncoder = JSONCoding.makeEncoder(pretty: false)) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(value))
    }

    /// Decodes this JSON into one of our structs (dates as ISO 8601 strings).
    public func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONCoding.makeDecoder().decode(T.self, from: data)
    }

    /// Pretty-printed JSON with sorted keys. Long output is cut after `maxLines`.
    public func prettyPrinted(maxLines: Int = .max) -> String {
        guard let data = try? JSONCoding.makeEncoder(pretty: true).encode(self),
              let text = String(data: data, encoding: .utf8) else { return "<unprintable JSON>" }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else { return text }
        return lines.prefix(maxLines).joined(separator: "\n") + "\n  … \(lines.count - maxLines) more lines"
    }
}

// MARK: Literals (used for the Gemini response schemas)

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
                     ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
                     ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

// MARK: - Dates

public enum JSONCoding {
    /// Marks a Date while a struct is converted to Firestore's format, so it can
    /// be written as a `timestampValue` instead of a plain string. Firestore
    /// reserves field names shaped like __name__, so this can't collide with real data.
    static let timestampKey = "__timestamp__"

    /// Reads dates written as ISO 8601 strings, with or without fractional seconds.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseISO8601(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
            }
            return date
        }
        return decoder
    }

    /// Writes dates as ISO 8601 strings ("2026-10-20T16:00:00Z").
    public static func makeEncoder(pretty: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                                          : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatISO8601(date))
        }
        return encoder
    }

    /// Writes dates as {"__timestamp__": "..."} markers (see FirestoreValue.encode).
    static func makeFirestoreEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode([timestampKey: formatISO8601(date)])
        }
        return encoder
    }

    /// Firestore can return up to 9 fractional digits; trim to milliseconds first.
    public static func parseISO8601(_ text: String) -> Date? {
        var value = text
        if let dot = value.firstIndex(of: ".") {
            let afterDot = value.index(after: dot)
            let end = value[afterDot...].firstIndex(where: { !$0.isNumber }) ?? value.endIndex
            let digits = String(value[afterDot..<end])
            let millis = String((digits + "000").prefix(3))
            value.replaceSubrange(dot..<end, with: "." + millis)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    public static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

// MARK: - Firestore REST format

public enum FirestoreValue {
    /// Plain JSON -> Firestore typed value.
    public static func encode(_ value: JSONValue) -> JSONValue {
        switch value {
        case .null:
            return ["nullValue": .null]
        case .bool(let flag):
            return ["booleanValue": .bool(flag)]
        case .int(let number):
            return ["integerValue": .string(String(number))]   // int64 travels as a string
        case .double(let number):
            return ["doubleValue": .double(number)]
        case .string(let text):
            return ["stringValue": .string(text)]
        case .array(let items):
            return items.isEmpty ? ["arrayValue": [:]]
                                 : ["arrayValue": ["values": .array(items.map(encode))]]
        case .object(let fields):
            if fields.count == 1, case .string(let iso)? = fields[JSONCoding.timestampKey] {
                return ["timestampValue": .string(iso)]
            }
            return fields.isEmpty ? ["mapValue": [:]]
                                  : ["mapValue": ["fields": .object(fields.mapValues(encode))]]
        }
    }

    /// Firestore typed value -> plain JSON.
    public static func decode(_ value: JSONValue) -> JSONValue {
        guard case .object(let wrapper) = value, let tagged = wrapper.first else { return .null }
        let inner = tagged.value
        switch tagged.key {
        case "nullValue":
            return .null
        case "integerValue":
            if case .string(let text) = inner, let number = Int64(text) { return .int(number) }
            return inner
        case "doubleValue":
            switch inner {
            case .int(let number): return .double(Double(number))
            case .string(let text): return Double(text).map(JSONValue.double) ?? .null   // "NaN", "Infinity"
            default: return inner
            }
        case "arrayValue":
            return .array((inner["values"]?.arrayValue ?? []).map(decode))
        case "mapValue":
            return .object((inner["fields"]?.objectValue ?? [:]).mapValues(decode))
        default:
            // booleanValue, stringValue, timestampValue, bytesValue, referenceValue, geoPointValue
            return inner
        }
    }

    /// A REST document's `fields` -> plain JSON object.
    public static func decodeFields(_ fields: [String: JSONValue]) -> JSONValue {
        .object(fields.mapValues(decode))
    }

    /// Any Codable struct as Firestore REST `fields` (dates become timestampValue).
    public static func fields<T: Encodable>(encoding value: T) throws -> [String: JSONValue] {
        let plain = try JSONValue(encoding: value, encoder: JSONCoding.makeFirestoreEncoder())
        guard case .object(let fields) = plain else { return [:] }
        return fields.mapValues(encode)
    }
}

extension FirestoreDocument {
    /// This model as Firestore REST `fields` (dates become timestampValue). `id` is not included.
    public func firestoreFields() throws -> [String: JSONValue] {
        try FirestoreValue.fields(encoding: self)
    }

    /// Builds a model from REST `fields` plus the document ID.
    public static func fromFirestore(id: String, fields: [String: JSONValue]) throws -> Self {
        var model = try FirestoreValue.decodeFields(fields).decode(as: Self.self)
        model.id = id
        return model
    }
}
