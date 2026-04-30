import Foundation
import PairingProtocol

/// Issues short-lived single-use pairing codes. Codes expire after 5 minutes
/// or after one successful use.
public actor PairingInviteService {
    public struct OutstandingInvite: Sendable {
        public let invite: PairingInvite
        public let expiresAt: Date
    }

    private(set) var outstanding: [String: OutstandingInvite] = [:]
    private let macId: String
    private let macName: String
    private let bundleId: String

    public init(macId: String, macName: String, bundleId: String = "com.claudeswarm.remote") {
        self.macId = macId
        self.macName = macName
        self.bundleId = bundleId
    }

    public func issue(
        host: String, port: UInt16,
        certThumbprint: String,
        ttl: TimeInterval = 300
    ) -> PairingInvite {
        let code = Self.makeCode()
        let invite = PairingInvite(
            host: host, port: port,
            macId: macId, macName: macName,
            pairingCode: code,
            bundleId: bundleId,
            certThumbprint: certThumbprint
        )
        outstanding[code] = OutstandingInvite(invite: invite, expiresAt: Date().addingTimeInterval(ttl))
        return invite
    }

    public func consume(code: String) -> PairingInvite? {
        sweepExpired()
        guard let entry = outstanding.removeValue(forKey: code) else { return nil }
        guard entry.expiresAt > Date() else { return nil }
        return entry.invite
    }

    private func sweepExpired() {
        let now = Date()
        outstanding = outstanding.filter { $0.value.expiresAt > now }
    }

    /// 8-char alpha code split into two readable groups. Avoids ambiguous
    /// glyphs (0/O/1/I) to make manual entry easier.
    static func makeCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        func chunk() -> String { String((0..<4).map { _ in alphabet.randomElement()! }) }
        return "\(chunk())-\(chunk())"
    }
}
