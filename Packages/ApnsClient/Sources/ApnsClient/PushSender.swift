import Foundation

/// Anything that can deliver an APNs payload to a device. Lets the app
/// swap between sending directly from the Mac (per-device .p8 key) and
/// sending through a company-internal push relay (single shared key).
///
/// Payload is pre-serialized JSON (`Data`) so the cross-actor hop stays
/// Sendable and we never re-encode the same dict twice on the way out.
public protocol PushSender: Sendable {
    func send(payload: Data, to deviceToken: String, collapseId: String?) async throws
}

public extension PushSender {
    /// Convenience for the dictionary form. Encodes once and forwards.
    func send(payload: [String: Any], to deviceToken: String, collapseId: String?) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try await send(payload: data, to: deviceToken, collapseId: collapseId)
    }
}

public enum PushBackend: String, Codable, Equatable, Sendable {
    case direct          // .p8 lives on this Mac; talk to APNs directly
    case relay           // talk to a company push-relay over the VPN
}

public struct RelayConfig: Codable, Equatable, Sendable {
    public var url: String           // https://swarm-push.internal/push
    public var sharedSecretAccount: String   // Keychain account holding the secret
    public var enabled: Bool

    public init(url: String = "", sharedSecretAccount: String = "relay-secret", enabled: Bool = false) {
        self.url = url
        self.sharedSecretAccount = sharedSecretAccount
        self.enabled = enabled
    }

    public var isComplete: Bool { !url.isEmpty }
}

public struct PushBackendConfig: Codable, Equatable, Sendable {
    public var backend: PushBackend
    public var direct: ApnsConfig
    public var relay: RelayConfig

    public init(
        backend: PushBackend = .direct,
        direct: ApnsConfig = .init(),
        relay: RelayConfig = .init()
    ) {
        self.backend = backend
        self.direct = direct
        self.relay = relay
    }
}
