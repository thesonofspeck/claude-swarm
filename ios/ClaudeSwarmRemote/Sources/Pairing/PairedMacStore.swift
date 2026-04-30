import Foundation
import PairingProtocol

/// On-device record of a Mac we paired with.
struct PairedMac: Codable, Equatable, Identifiable, Hashable {
    let macId: String
    var macName: String
    var host: String
    var port: UInt16
    var bearerToken: String
    var pairedAt: Date

    var id: String { macId }
}

/// Persists PairedMac records in Keychain (one item per macId, plus an
/// index) and the iOS device's stable id used in the pairing handshake.
final class PairedMacStore {
    private let keychain = Keychain(service: "com.claudeswarm.remote.macs")
    private let deviceIdAccount = "__device-id__"
    private let indexAccount = "__index__"

    var deviceId: String {
        if let cached = try? keychain.get(account: deviceIdAccount) { return cached }
        let new = UUID().uuidString
        try? keychain.set(new, account: deviceIdAccount)
        return new
    }

    func all() -> [PairedMac] {
        guard let index = try? keychain.get(account: indexAccount), !index.isEmpty else { return [] }
        return index.split(separator: ",").compactMap { id in
            guard let raw = try? keychain.get(account: String(id)),
                  let data = raw.data(using: .utf8) else { return nil }
            return try? PairCodec.decoder.decode(PairedMac.self, from: data)
        }
    }

    func save(_ mac: PairedMac) {
        let data = (try? PairCodec.encoder.encode(mac)) ?? Data()
        let raw = String(decoding: data, as: UTF8.self)
        try? keychain.set(raw, account: mac.macId)
        var ids = (try? keychain.get(account: indexAccount))?
            .split(separator: ",").map(String.init) ?? []
        if !ids.contains(mac.macId) {
            ids.append(mac.macId)
            try? keychain.set(ids.joined(separator: ","), account: indexAccount)
        }
    }

    func remove(macId: String) {
        try? keychain.remove(account: macId)
        let ids = (try? keychain.get(account: indexAccount))?
            .split(separator: ",").map(String.init) ?? []
        try? keychain.set(ids.filter { $0 != macId }.joined(separator: ","), account: indexAccount)
    }
}
