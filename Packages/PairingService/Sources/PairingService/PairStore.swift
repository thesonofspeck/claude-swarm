import Foundation
import KeychainKit
import PairingProtocol

/// Stores paired-device records in Keychain. One Keychain item per device,
/// scoped to the `com.claudeswarm.pairings` service.
public actor PairStore {
    public let keychain: Keychain

    public init(keychain: Keychain = Keychain(service: "com.claudeswarm.pairings")) {
        self.keychain = keychain
    }

    public func save(_ record: PairRecord) throws {
        let data = try PairCodec.encoder.encode(record)
        try keychain.set(String(decoding: data, as: UTF8.self), account: record.id)
    }

    public func find(deviceId: String) -> PairRecord? {
        guard let raw = try? keychain.get(account: deviceId),
              let data = raw.data(using: .utf8) else { return nil }
        return try? PairCodec.decoder.decode(PairRecord.self, from: data)
    }

    public func remove(deviceId: String) throws {
        try keychain.remove(account: deviceId)
    }

    public func findByBearer(_ token: String) -> PairRecord? {
        for record in all() where record.bearerToken == token {
            return record
        }
        return nil
    }

    /// Convenience for the settings UI. We don't have a SecItemCopyMatching
    /// listing API in our thin wrapper, so device ids must be tracked
    /// separately (we keep a comma-joined index account on the same service).
    public func all() -> [PairRecord] {
        guard let index = try? keychain.get(account: "__index__"), !index.isEmpty else {
            return []
        }
        return index.split(separator: ",").compactMap { id in
            find(deviceId: String(id))
        }
    }

    public func register(_ record: PairRecord) throws {
        try save(record)
        var ids = (try? keychain.get(account: "__index__"))?
            .split(separator: ",")
            .map(String.init) ?? []
        if !ids.contains(record.id) {
            ids.append(record.id)
            try keychain.set(ids.joined(separator: ","), account: "__index__")
        }
    }

    public func unregister(deviceId: String) throws {
        try? keychain.remove(account: deviceId)
        let ids = (try? keychain.get(account: "__index__"))?
            .split(separator: ",")
            .map(String.init) ?? []
        let kept = ids.filter { $0 != deviceId }
        try keychain.set(kept.joined(separator: ","), account: "__index__")
    }
}
