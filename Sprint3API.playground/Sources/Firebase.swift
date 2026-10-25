import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Firebase over plain HTTPS. Xcode playgrounds can't load the Firebase SDK, so
// these helpers call the same REST endpoints the SDK uses under the hood:
//   • Firebase Auth   identitytoolkit.googleapis.com   (anonymous sign-in)
//   • Cloud Firestore firestore.googleapis.com          (read, query, write)
//   • Cloud Storage   firebasestorage.googleapis.com    (photo upload)

public struct FirebaseConfig: Sendable {
    public var projectID: String
    public var webAPIKey: String
    /// "<project-id>.firebasestorage.app". Leave empty to skip Storage uploads
    /// (Storage needs the Blaze plan).
    public var storageBucket: String

    public init(projectID: String, webAPIKey: String, storageBucket: String) {
        self.projectID = projectID
        self.webAPIKey = webAPIKey
        self.storageBucket = storageBucket
    }

    var isFilledIn: Bool { !projectID.contains("YOUR_") && !webAPIKey.contains("YOUR_") && !projectID.isEmpty }
    public var hasStorage: Bool { !storageBucket.isEmpty && !storageBucket.contains("YOUR_") }
}

// MARK: - Errors

public enum Service: String, Sendable {
    case auth = "Firebase Auth"
    case firestore = "Firestore"
    case storage = "Cloud Storage"
    case gemini = "Gemini API"
}

/// An error from one of the APIs, with a hint for the usual setup mistakes.
public struct APIError: Error, CustomStringConvertible, Sendable {
    public var service: Service
    public var httpStatus: Int
    public var message: String

    public var description: String {
        var text = "\(service.rawValue) error \(httpStatus): \(message)"
        if let hint { text += "\n   ↳ \(hint)" }
        return text
    }

    /// Google APIs answer errors as {"error": {"code": 403, "message": "...", "status": "PERMISSION_DENIED"}}.
    static func from(data: Data, httpStatus: Int, service: Service) -> APIError {
        let body = try? JSONValue(data: data)
        let message = body?["error"]?["message"]?.stringValue
            ?? body?["error"]?.stringValue
            ?? String(data: data, encoding: .utf8)?.prefix(300).description
            ?? "no details"
        return APIError(service: service, httpStatus: httpStatus, message: message)
    }

    var hint: String? {
        let text = message.uppercased()
        switch service {
        case .auth:
            if text.contains("OPERATION_NOT_ALLOWED") || text.contains("ADMIN_ONLY_OPERATION") {
                return "Turn on Anonymous sign-in: Firebase console → Authentication → Sign-in method → Anonymous."
            }
            if text.contains("API KEY") || text.contains("API_KEY") {
                return "Check webAPIKey in Sources/Secrets.swift (Firebase console → Project settings → General → Web API Key)."
            }
            if text.contains("CONFIGURATION_NOT_FOUND") {
                return "Open Authentication in the Firebase console and click Get started first."
            }
        case .firestore:
            if httpStatus == 404 && text.contains("DOES NOT EXIST") {
                return "Create the database first: Firebase console → Firestore Database → Create database."
            }
            if httpStatus == 404 {
                return "Document not found. Run page 1 (Seed Firestore) first."
            }
            if httpStatus == 403 && (text.contains("HAS NOT BEEN USED") || text.contains("DISABLED")) {
                return "Create the Firestore database in the Firebase console, wait a minute, then run again."
            }
            if httpStatus == 403 {
                return "Firestore rules blocked the request. Paste firebase/firestore.rules into Firestore → Rules and publish."
            }
            if httpStatus == 400 && text.contains("INDEX") {
                return "This query needs an index. Open the link in the message to create it."
            }
        case .storage:
            if httpStatus == 402 || httpStatus == 404 || text.contains("BILLING") {
                return "Storage needs the Blaze plan and a bucket (Firebase console → Storage). Or set storageBucket to \"\" to skip uploads."
            }
            if httpStatus == 403 {
                return "Storage rules blocked the upload. Paste firebase/storage.rules into Storage → Rules and publish."
            }
        case .gemini:
            if text.contains("API KEY") || text.contains("API_KEY") {
                return "Check geminiAPIKey in Sources/Secrets.swift (aistudio.google.com → Get API key)."
            }
            if httpStatus == 429 {
                return "Free-tier rate limit hit. Wait a minute and run again."
            }
            if httpStatus == 404 {
                return "Model not found. Check geminiModel in Sources/Secrets.swift against the model list in AI Studio."
            }
            if httpStatus == 503 {
                return "The model is busy. Try again in a moment."
            }
        }
        return nil
    }
}

public enum DemoError: Error, CustomStringConvertible, Sendable {
    case secretsMissing(String)
    case missingResource(String)
    case seedMismatch(path: String, type: String, details: String)
    case badResponse(String)
    case notReady(String)

    public var description: String {
        switch self {
        case .notReady(let message):
            return message
        case .secretsMissing(let what):
            return "Fill in \(what) in Sources/Secrets.swift first (see README step 4)."
        case .missingResource(let name):
            return "Couldn't find \(name) in the playground's Resources folder."
        case .seedMismatch(let path, let type, let details):
            return "seed.json document \(path) doesn't match struct \(type): \(details)"
        case .badResponse(let details):
            return "Unexpected response: \(details)"
        }
    }
}

// MARK: - HTTP

enum HTTP {
    static func send(_ request: URLRequest, service: Service) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError.from(data: data, httpStatus: status, service: service)
        }
        return data
    }

    static func jsonRequest(_ url: URL, method: String, body: JSONValue? = nil, bearer: String? = nil) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        return request
    }

    static func url(_ string: String) throws -> URL {
        guard let url = URL(string: string) else { throw DemoError.badResponse("bad URL \(string)") }
        return url
    }

    /// Percent-encodes a query value, including "/" "+" "&" "=".
    static func queryEscape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

// MARK: - Auth

/// Sign In · AuthenticationSession: the signed-in user. Firebase Auth keeps
/// the session on the device; it isn't stored in Firestore. The ID token goes
/// with every Firestore and Storage request so the security rules know who is asking.
public struct AuthenticationSession: Sendable {
    public let config: FirebaseConfig
    public let userId: String
    public let provider: String           // "anonymous" here; "google.com", "apple.com" or "password" in the app
    public let expiresAt: Date
    let idToken: String

    init(config: FirebaseConfig, userId: String, provider: String = "anonymous",
         expiresAt: Date = Date().addingTimeInterval(3600), idToken: String) {
        self.config = config
        self.userId = userId
        self.provider = provider
        self.expiresAt = expiresAt
        self.idToken = idToken
    }

    /// Firebase Auth REST: POST accounts:signUp with no email/password = anonymous user.
    public static func signInAnonymously(_ config: FirebaseConfig = Secrets.firebase) async throws -> AuthenticationSession {
        guard config.isFilledIn else { throw DemoError.secretsMissing("projectID and webAPIKey") }
        let url = try HTTP.url("https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(HTTP.queryEscape(config.webAPIKey))")
        let request = try HTTP.jsonRequest(url, method: "POST", body: ["returnSecureToken": true])
        let data = try await HTTP.send(request, service: .auth)
        let response = try JSONDecoder().decode(SignUpResponse.self, from: data)
        return AuthenticationSession(config: config, userId: response.localId,
                                     expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn) ?? 3600),
                                     idToken: response.idToken)
    }
}

extension AuthenticationResult {
    /// Sign In: the signed-in session plus the profile saved at registration (nil for a new user).
    public init(session: AuthenticationSession, userProfile: UserProfile?) {
        self.init(userId: session.userId, provider: session.provider, userProfile: userProfile)
    }
}

/// Firebase Auth's sign-up response.
struct SignUpResponse: Decodable {
    let idToken: String
    let refreshToken: String
    let expiresIn: String
    let localId: String
}

// MARK: - Firestore

/// One write in a batch. All writes in one `commit` succeed or fail together.
public enum FirestoreWrite: Sendable {
    /// Creates or replaces the whole document.
    case set(path: String, fields: [String: JSONValue])
    /// Changes only the fields named in `mask` on an existing document. A field
    /// in the mask with no value in `fields` is removed.
    case update(path: String, fields: [String: JSONValue], mask: [String])
    case delete(path: String)
    case increment(path: String, field: String, by: Int)
    /// Adds values to an array field, skipping ones already there.
    case arrayUnion(path: String, field: String, values: [JSONValue])
    /// Removes every copy of the values from an array field.
    case arrayRemove(path: String, field: String, values: [JSONValue])

    public static func set<T: FirestoreDocument>(_ model: T, at path: String) throws -> FirestoreWrite {
        .set(path: path, fields: try model.firestoreFields())
    }

    /// Updates only the fields of `value` named in `mask` (Firestore field names).
    public static func update<T: Encodable>(_ value: T, at path: String, mask: [String]) throws -> FirestoreWrite {
        let topLevel = Set(mask.map { String($0.split(separator: ".").first ?? "") })
        let fields = try FirestoreValue.fields(encoding: value).filter { topLevel.contains($0.key) }
        return .update(path: path, fields: fields, mask: mask)
    }

    public var path: String {
        switch self {
        case .set(let path, _), .update(let path, _, _), .delete(let path), .increment(let path, _, _),
             .arrayUnion(let path, _, _), .arrayRemove(let path, _, _):
            return path
        }
    }
}

public enum FirestoreOperator: String, Sendable {
    case equal = "EQUAL"
    case arrayContains = "ARRAY_CONTAINS"
    case lessThan = "LESS_THAN"
    case greaterThan = "GREATER_THAN"
}

/// A document exactly as the Firestore REST API returns it.
public struct FirestoreRESTDocument: Decodable, Sendable {
    public let name: String                       // projects/.../documents/groups/g_axolotls
    public let fields: [String: JSONValue]?
    public let createTime: String?
    public let updateTime: String?

    public var documentID: String { String(name.split(separator: "/").last ?? "") }
}

public struct Firestore: Sendable {
    public let session: AuthenticationSession

    public init(session: AuthenticationSession) { self.session = session }

    var documentsRoot: String { "projects/\(session.config.projectID)/databases/(default)/documents" }
    var baseURL: String { "https://firestore.googleapis.com/v1/\(documentsRoot)" }

    // MARK: Read

    /// The raw REST JSON for one document (to show what Firestore actually sends back).
    public func rawDocument(_ path: String) async throws -> JSONValue {
        let request = try HTTP.jsonRequest(HTTP.url("\(baseURL)/\(path)"), method: "GET", bearer: session.idToken)
        return try JSONValue(data: try await HTTP.send(request, service: .firestore))
    }

    /// GET one document and decode it into a model.
    public func get<T: FirestoreDocument>(_ type: T.Type, _ path: String) async throws -> T {
        let request = try HTTP.jsonRequest(HTTP.url("\(baseURL)/\(path)"), method: "GET", bearer: session.idToken)
        let document = try JSONDecoder().decode(FirestoreRESTDocument.self, from: try await HTTP.send(request, service: .firestore))
        return try T.fromFirestore(id: document.documentID, fields: document.fields ?? [:])
    }

    /// Like `get`, but returns nil when the document doesn't exist.
    public func getIfExists<T: FirestoreDocument>(_ type: T.Type, _ path: String) async throws -> T? {
        do { return try await get(type, path) }
        catch let error as APIError where error.httpStatus == 404 { return nil }
    }

    /// Every document in a collection (follows nextPageToken).
    public func list<T: FirestoreDocument>(_ type: T.Type, _ collectionPath: String) async throws -> [T] {
        var results: [T] = []
        var pageToken: String?
        repeat {
            var urlString = "\(baseURL)/\(collectionPath)?pageSize=300"
            if let pageToken { urlString += "&pageToken=\(HTTP.queryEscape(pageToken))" }
            let request = try HTTP.jsonRequest(HTTP.url(urlString), method: "GET", bearer: session.idToken)
            let page = try JSONDecoder().decode(ListResponse.self, from: try await HTTP.send(request, service: .firestore))
            for document in page.documents ?? [] {
                results.append(try T.fromFirestore(id: document.documentID, fields: document.fields ?? [:]))
            }
            pageToken = page.nextPageToken
        } while pageToken != nil
        return results
    }

    /// A one-filter query on a top-level collection, e.g. groups where member_ids array-contains "u_anabella".
    public func query<T: FirestoreDocument>(_ type: T.Type, collection: String, field: String,
                                            _ op: FirestoreOperator, _ value: JSONValue) async throws -> [T] {
        let body: JSONValue = [
            "structuredQuery": [
                "from": [["collectionId": .string(collection)]],
                "where": [
                    "fieldFilter": [
                        "field": ["fieldPath": .string(field)],
                        "op": .string(op.rawValue),
                        "value": FirestoreValue.encode(value),
                    ],
                ],
            ],
        ]
        let request = try HTTP.jsonRequest(HTTP.url("\(baseURL):runQuery"), method: "POST", body: body, bearer: session.idToken)
        let rows = try JSONDecoder().decode([RunQueryRow].self, from: try await HTTP.send(request, service: .firestore))
        return try rows.compactMap(\.document).map { try T.fromFirestore(id: $0.documentID, fields: $0.fields ?? [:]) }
    }

    // MARK: Write

    /// Commits writes in batches of up to 400 (Firestore allows 500 per commit).
    @discardableResult
    public func commit(_ writes: [FirestoreWrite]) async throws -> Int {
        var committed = 0
        var start = 0
        while start < writes.count {
            let batch = writes[start..<min(start + 400, writes.count)]
            let body: JSONValue = ["writes": .array(batch.map(restWrite))]
            let request = try HTTP.jsonRequest(HTTP.url("\(baseURL):commit"), method: "POST", body: body, bearer: session.idToken)
            let response = try JSONValue(data: try await HTTP.send(request, service: .firestore))
            committed += response["writeResults"]?.arrayValue?.count ?? 0
            start += batch.count
        }
        return committed
    }

    func restWrite(_ write: FirestoreWrite) -> JSONValue {
        let name = JSONValue.string("\(documentsRoot)/\(write.path)")
        func transform(_ field: String, _ change: String, _ value: JSONValue) -> JSONValue {
            ["transform": ["document": name, "fieldTransforms": [["fieldPath": .string(field), change: value]]]]
        }
        switch write {
        case .set(_, let fields):
            return ["update": ["name": name, "fields": .object(fields)]]
        case .update(_, let fields, let mask):
            return ["update": ["name": name, "fields": .object(fields)],
                    "updateMask": ["fieldPaths": .array(mask.map(JSONValue.string))],
                    "currentDocument": ["exists": true]]
        case .delete:
            return ["delete": name]
        case .increment(_, let field, let amount):
            return transform(field, "increment", ["integerValue": .string(String(amount))])
        case .arrayUnion(_, let field, let values):
            return transform(field, "appendMissingElements", ["values": .array(values.map(FirestoreValue.encode))])
        case .arrayRemove(_, let field, let values):
            return transform(field, "removeAllFromArray", ["values": .array(values.map(FirestoreValue.encode))])
        }
    }
}

struct ListResponse: Decodable {
    let documents: [FirestoreRESTDocument]?
    let nextPageToken: String?
}

struct RunQueryRow: Decodable {
    let document: FirestoreRESTDocument?
    let readTime: String?
}

// MARK: - Cloud Storage

/// Cloud Storage's answer after an upload.
public struct StorageObject: Decodable, Sendable {
    public let name: String                       // "groups/g_axolotls/photos/p_demo.jpg"
    public let bucket: String
    public let contentType: String?
    public let size: String?                      // bytes, as a string
    public let timeCreated: String?
}

extension AuthenticationSession {
    /// Uploads bytes to Cloud Storage for Firebase (same endpoint the SDKs use).
    public func upload(_ data: Data, to path: String, contentType: String = "image/jpeg") async throws -> StorageObject {
        guard config.hasStorage else { throw DemoError.secretsMissing("storageBucket") }
        let url = try HTTP.url("https://firebasestorage.googleapis.com/v0/b/\(config.storageBucket)/o?name=\(HTTP.queryEscape(path))")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Firebase \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        return try JSONDecoder().decode(StorageObject.self, from: try await HTTP.send(request, service: .storage))
    }
}
