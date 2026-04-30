import Foundation
import KeychainKit

public struct AnthropicConfig: Codable, Equatable, Sendable {
    public var model: String
    public var maxTokens: Int
    public var enabled: Bool

    public init(
        model: String = "claude-sonnet-4-6",
        maxTokens: Int = 1024,
        enabled: Bool = false
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.enabled = enabled
    }
}

public struct AnthropicMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public actor AnthropicClient {
    public enum LLMError: Error, LocalizedError {
        case missingKey
        case http(status: Int, body: String)
        case decoding(Error)
        case transport(Error)

        public var errorDescription: String? {
            switch self {
            case .missingKey: return "No Anthropic API key configured. Add one in Settings → AI."
            case .http(let s, let b): return "Anthropic HTTP \(s): \(b)"
            case .decoding(let e): return "Anthropic decode failed: \(e)"
            case .transport(let e): return "Anthropic transport: \(e)"
            }
        }
    }

    public let config: AnthropicConfig
    public let session: URLSession
    public let keychain: Keychain
    public let baseURL: URL

    public init(
        config: AnthropicConfig = .init(),
        keychain: Keychain = Keychain(),
        baseURL: URL = URL(string: "https://api.anthropic.com/v1/")!
    ) {
        self.config = config
        self.keychain = keychain
        self.baseURL = baseURL
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: cfg)
    }

    public func setKey(_ key: String) throws {
        try keychain.set(key, account: KeychainAccount.anthropic)
    }

    public func hasKey() -> Bool {
        (try? keychain.get(account: KeychainAccount.anthropic)) != nil
    }

    /// Send a single-turn completion. `system` carries the framing prompt;
    /// `messages` is the conversation. Returns the model's text reply.
    public func complete(system: String, messages: [AnthropicMessage]) async throws -> String {
        guard let key = try? keychain.get(account: KeychainAccount.anthropic), !key.isEmpty else {
            throw LLMError.missingKey
        }
        let url = baseURL.appendingPathComponent("messages")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let payload: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "system": [
                ["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]
            ],
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.http(status: -1, body: "non-HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw LLMError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
            }
            return try Self.extractText(from: data)
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.transport(error)
        }
    }

    static func extractText(from data: Data) throws -> String {
        struct Response: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        do {
            let body = try JSONDecoder().decode(Response.self, from: data)
            return body.content.compactMap { $0.text }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw LLMError.decoding(error)
        }
    }
}
