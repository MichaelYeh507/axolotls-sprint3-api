import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Gemini API (external API)
//
// REST endpoint: POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
// We send a prompt (plus a photo for quest checks) and a response schema, and
// Gemini answers with JSON that matches the schema. Two uses in the app:
//   • Camera screen:       does this photo complete the quest?   -> QuestVerdict
//   • Create Group screen: write quests for this event            -> QuestIdeas
//
// In the iOS app, call the same model through Firebase AI Logic
// (`import FirebaseAILogic`) so the API key never ships inside the app. The
// request and response have the same shape as below.

// MARK: What we ask Gemini to return

/// Gemini's verdict on one quest photo. Saved onto the GroupPhoto as `quest_check`.
public struct QuestVerdict: Codable, Sendable {
    public var completed: Bool
    public var confidence: Double
    public var reason: String
    public var tags: [String]
}

/// Quest ideas for a new group.
public struct QuestIdeas: Codable, Sendable {
    public var quests: [QuestIdea]
}

public struct QuestIdea: Codable, Sendable {
    public var prompt: String
    public var checkable: Bool
}

// MARK: Request

public struct GenerateContentRequest: Encodable, Sendable {
    public var contents: [GeminiContent]
    public var generationConfig: GenerationConfig
}

public struct GeminiContent: Codable, Sendable {
    public var role: String?
    public var parts: [GeminiPart]?           // can be missing when a reply is blocked
}

public struct GeminiPart: Codable, Sendable {
    public var text: String?
    public var inlineData: InlineData?
    public var thought: Bool?                 // set on "thinking" parts, which we skip

    public init(text: String) { self.text = text }
    public init(jpeg: Data) { self.inlineData = InlineData(mimeType: "image/jpeg", data: jpeg.base64EncodedString()) }
}

public struct InlineData: Codable, Sendable {
    public var mimeType: String
    public var data: String                   // base64
}

public struct GenerationConfig: Encodable, Sendable {
    public var responseMimeType = "application/json"
    public var responseSchema: JSONValue
}

// MARK: Response

public struct GenerateContentResponse: Decodable, Sendable {
    public var candidates: [Candidate]?
    public var promptFeedback: PromptFeedback?
    public var usageMetadata: UsageMetadata?
    public var modelVersion: String?
    public var responseId: String?

    /// The model's text, without any thinking parts.
    public var text: String {
        let parts = candidates?.first?.content?.parts ?? []
        return parts.filter { $0.thought != true }.compactMap(\.text).joined()
    }
}

public struct Candidate: Decodable, Sendable {
    public var content: GeminiContent?
    public var finishReason: String?          // "STOP", "MAX_TOKENS", "SAFETY", ...
}

public struct PromptFeedback: Decodable, Sendable {
    public var blockReason: String?
}

public struct UsageMetadata: Decodable, Sendable {
    public var promptTokenCount: Int?
    public var candidatesTokenCount: Int?
    public var thoughtsTokenCount: Int?
    public var totalTokenCount: Int?
}

/// A decoded answer plus the raw JSON, so the playground can show both.
public struct GeminiReply<T: Sendable>: Sendable {
    public let value: T
    public let rawResponse: JSONValue         // the whole HTTP response body
    public let jsonText: String               // the JSON string Gemini wrote
    public let usage: UsageMetadata?
    public let modelVersion: String?
}

// MARK: Client

public struct GeminiClient: Sendable {
    public var apiKey: String
    public var model: String

    public init(apiKey: String = Secrets.geminiAPIKey, model: String = Secrets.geminiModel) {
        self.apiKey = apiKey
        self.model = model
    }

    /// Sends one prompt (and optional JPEG) and decodes Gemini's JSON answer into `T`.
    public func generate<T: Decodable & Sendable>(_ type: T.Type, prompt: String, jpeg: Data? = nil,
                                                  schema: JSONValue) async throws -> GeminiReply<T> {
        guard !apiKey.isEmpty, !apiKey.contains("YOUR_") else { throw DemoError.secretsMissing("geminiAPIKey") }

        var parts = [GeminiPart(text: prompt)]
        if let jpeg { parts.append(GeminiPart(jpeg: jpeg)) }
        let body = GenerateContentRequest(
            contents: [GeminiContent(role: "user", parts: parts)],
            generationConfig: GenerationConfig(responseSchema: schema)
        )

        let url = try HTTP.url("https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 90

        let data = try await HTTP.send(request, service: .gemini)
        let response = try JSONDecoder().decode(GenerateContentResponse.self, from: data)

        let text = Self.stripCodeFence(response.text)
        guard !text.isEmpty else {
            let reason = response.promptFeedback?.blockReason ?? response.candidates?.first?.finishReason ?? "no text"
            throw DemoError.badResponse("Gemini returned no JSON (\(reason)).")
        }
        let value = try JSONDecoder().decode(T.self, from: Data(text.utf8))
        return GeminiReply(value: value, rawResponse: try JSONValue(data: data), jsonText: text,
                           usage: response.usageMetadata, modelVersion: response.modelVersion)
    }

    /// JSON mode shouldn't add ```json fences, but strip them just in case.
    static func stripCodeFence(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed.drop(while: { $0 != "\n" }).description
            if trimmed.hasSuffix("```") { trimmed = String(trimmed.dropLast(3)) }
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - The two app features

extension GeminiClient {
    /// Camera screen: does this photo complete the quest?
    public func checkQuest(_ quest: String, jpeg: Data) async throws -> GeminiReply<QuestVerdict> {
        try await generate(QuestVerdict.self, prompt: GeminiPrompts.questCheck(quest), jpeg: jpeg,
                           schema: GeminiSchemas.questVerdict)
    }

    /// Create Group screen: write `count` quests for a new group.
    public func questIdeas(name: String, description: String, mode: GroupMode,
                           count: Int) async throws -> GeminiReply<QuestIdeas> {
        try await generate(QuestIdeas.self,
                           prompt: GeminiPrompts.questIdeas(name: name, description: description, mode: mode, count: count),
                           schema: GeminiSchemas.questIdeas)
    }
}

extension QuestCheck {
    /// The verdict as stored on a GroupPhoto (quest_check).
    public init(_ verdict: QuestVerdict, model: String, checkedAt: Date = Date()) {
        self.init(completed: verdict.completed, confidence: verdict.confidence, reason: verdict.reason,
                  tags: verdict.tags, model: model, checkedAt: checkedAt)
    }
}

public enum GeminiPrompts {
    public static func questCheck(_ quest: String) -> String {
        """
        You are the referee for a photo scavenger hunt app. Friends at the same event get short photo quests.
        Quest: "\(quest)"
        Decide whether the attached photo completes this quest.
        - Judge only what is visible. Be fair, not strict: a reasonable take on the quest counts.
        - confidence is how sure you are of your verdict, from 0 to 1.
        - reason is one short, friendly sentence the player will see. Never guess who a real person is.
        - tags are up to 5 short lowercase words for what is in the photo.
        """
    }

    public static func questIdeas(name: String, description: String, mode: GroupMode, count: Int) -> String {
        let style = mode == .party
            ? "Party quests get people interacting with each other."
            : "Travel quests point people at places, food, signs and sights."
        return """
        You write photo quests for a friend-group photo app. Write \(count) quests for this event.
        Group name: \(name)
        Description: \(description)
        Mode: \(mode.rawValue). \(style)
        - Every prompt starts with "Take a photo" and is under 70 characters.
        - Keep them kind and safe: nothing dangerous, illegal, or embarrassing for strangers.
        - checkable is true when one photo can clearly show the quest was done (like "something blue"),
          and false for subjective quests (like "the funniest face").
        """
    }
}

/// Response schemas (Gemini's OpenAPI-style schema format).
public enum GeminiSchemas {
    public static let questVerdict: JSONValue = [
        "type": "OBJECT",
        "properties": [
            "completed": ["type": "BOOLEAN", "description": "true if the photo completes the quest"],
            "confidence": ["type": "NUMBER", "description": "0 to 1"],
            "reason": ["type": "STRING", "description": "one short sentence shown to the player"],
            "tags": ["type": "ARRAY", "items": ["type": "STRING"], "description": "up to 5 lowercase words"],
        ],
        "required": ["completed", "confidence", "reason", "tags"],
    ]

    public static let questIdeas: JSONValue = [
        "type": "OBJECT",
        "properties": [
            "quests": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "prompt": ["type": "STRING"],
                        "checkable": ["type": "BOOLEAN"],
                    ],
                    "required": ["prompt", "checkable"],
                ],
            ],
        ],
        "required": ["quests"],
    ]
}
