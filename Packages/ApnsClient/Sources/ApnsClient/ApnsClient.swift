import Foundation

public actor ApnsClient: PushSender {
    public enum ApnsError: Error, LocalizedError {
        case notConfigured
        case noKey
        case http(status: Int, reason: String?)
        case transport(Error)

        public var errorDescription: String? {
            switch self {
            case .notConfigured: return "APNs not configured"
            case .noKey: return "APNs .p8 key not found in Keychain"
            case .http(let s, let r): return "APNs HTTP \(s)\(r.map { ": \($0)" } ?? "")"
            case .transport(let e): return "APNs transport: \(e)"
            }
        }
    }

    public let config: ApnsConfig
    public let session: URLSession
    private let keyPem: String?
    private let jwtCache = JWTCache()

    public init(config: ApnsConfig, p8Pem: String?) {
        self.config = config
        self.keyPem = p8Pem
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: cfg)
    }

    public func send(payload: Data, to deviceToken: String, collapseId: String?) async throws {
        _ = try await send(payload: payload, to: deviceToken, priority: 10, collapseId: collapseId)
    }

    /// Send a rich notification to a single device. Caller serializes the
    /// payload to JSON `Data` first.
    @discardableResult
    public func send(payload: Data, to deviceToken: String, priority: Int = 10, collapseId: String? = nil) async throws -> Int {
        guard config.enabled, config.isComplete else { throw ApnsError.notConfigured }
        guard let pem = keyPem else { throw ApnsError.noKey }

        let token = try await jwtCache.get { [config] in
            try ApnsJWT(teamId: config.teamId, keyId: config.keyId, p8Pem: pem).token()
        }

        var url = URLComponents()
        url.scheme = "https"
        url.host = config.environment.host
        url.path = "/3/device/\(deviceToken)"
        guard let endpoint = url.url else {
            throw ApnsError.http(status: -1, reason: "bad url")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")
        request.setValue(config.bundleId, forHTTPHeaderField: "apns-topic")
        request.setValue("\(priority)", forHTTPHeaderField: "apns-priority")
        if let collapseId { request.setValue(collapseId, forHTTPHeaderField: "apns-collapse-id") }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ApnsError.http(status: -1, reason: "non-HTTP response")
            }
            if http.statusCode == 200 { return 200 }
            if http.statusCode == 410 || http.statusCode == 400 {
                // Token expired/invalid: caller should remove it from PairRecord.
                throw ApnsError.http(status: http.statusCode, reason: Self.parseReason(data))
            }
            if http.statusCode == 403 {
                await jwtCache.invalidate()
                throw ApnsError.http(status: 403, reason: Self.parseReason(data))
            }
            throw ApnsError.http(status: http.statusCode, reason: Self.parseReason(data))
        } catch let error as ApnsError {
            throw error
        } catch {
            throw ApnsError.transport(error)
        }
    }

    private static func parseReason(_ data: Data) -> String? {
        struct Body: Decodable { let reason: String? }
        return (try? JSONDecoder().decode(Body.self, from: data))?.reason
    }
}

public enum ApnsPayloads {
    /// Builds an approval-request payload that registers the
    /// `APPROVAL_REQUEST` category so iOS can show Approve / Deny actions.
    public static func approvalRequest(
        approvalId: String,
        sessionId: String,
        title: String,
        body: String,
        toolName: String?,
        argumentSummary: String?
    ) -> [String: Any] {
        var alert: [String: String] = ["title": title, "body": body]
        if let toolName, let argumentSummary {
            alert["subtitle"] = "\(toolName): \(argumentSummary)"
        }
        return [
            "aps": [
                "alert": alert,
                "sound": "default",
                "badge": 1,
                "category": "APPROVAL_REQUEST",
                "mutable-content": 1,
                "thread-id": "session-\(sessionId)"
            ],
            "approvalId": approvalId,
            "sessionId": sessionId,
            "toolName": toolName ?? "",
            "argumentSummary": argumentSummary ?? ""
        ]
    }

    /// "Session needs input" — generic prompt without an explicit tool call.
    public static func needsInput(
        sessionId: String,
        title: String,
        body: String
    ) -> [String: Any] {
        [
            "aps": [
                "alert": ["title": title, "body": body],
                "sound": "default",
                "badge": 1,
                "category": "NEEDS_INPUT",
                "thread-id": "session-\(sessionId)"
            ],
            "sessionId": sessionId
        ]
    }
}
