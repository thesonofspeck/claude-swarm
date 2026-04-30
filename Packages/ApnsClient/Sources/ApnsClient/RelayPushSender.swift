import Foundation
import CryptoKit

/// Sends pushes to a company-internal relay over the VPN. The relay holds
/// the single .p8 key and forwards to APNs. Auth is HMAC-SHA256 over a
/// concatenation of the timestamp and request body, using a shared secret.
public actor RelayPushSender: PushSender {
    public enum RelayError: Error, LocalizedError {
        case notConfigured
        case http(status: Int, body: String)
        case transport(Error)

        public var errorDescription: String? {
            switch self {
            case .notConfigured: return "Push relay not configured"
            case .http(let s, let b): return "Relay HTTP \(s): \(b)"
            case .transport(let e): return "Relay transport: \(e)"
            }
        }
    }

    public let config: RelayConfig
    public let session: URLSession
    private let sharedSecret: String

    public init(config: RelayConfig, sharedSecret: String) {
        self.config = config
        self.sharedSecret = sharedSecret
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: cfg)
    }

    public func send(payload: [String: Any], to deviceToken: String, collapseId: String?) async throws {
        guard config.enabled, config.isComplete, !sharedSecret.isEmpty else {
            throw RelayError.notConfigured
        }
        guard let url = URL(string: config.url) else { throw RelayError.notConfigured }

        var body: [String: Any] = ["deviceToken": deviceToken, "payload": payload]
        if let collapseId { body["collapseId"] = collapseId }
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = Self.hmacHex(secret: sharedSecret, timestamp: timestamp, body: bodyData)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SwarmRelay \(signature)", forHTTPHeaderField: "Authorization")
        request.setValue(timestamp, forHTTPHeaderField: "X-Swarm-Timestamp")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RelayError.http(status: -1, body: "non-HTTP response")
            }
            if !(200..<300).contains(http.statusCode) {
                throw RelayError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
            }
        } catch let error as RelayError {
            throw error
        } catch {
            throw RelayError.transport(error)
        }
    }

    /// Public so the relay binary can re-use the same primitive when
    /// validating incoming requests.
    public static func hmacHex(secret: String, timestamp: String, body: Data) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        var signed = Data(timestamp.utf8)
        signed.append(0x0a)
        signed.append(body)
        let mac = HMAC<SHA256>.authenticationCode(for: signed, using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}
