import Foundation
import Observation
import PairingProtocol
import UIKit

/// Drives the QR-scan-and-pair flow. Caller hands us a base64 invite
/// string; we open a one-shot WebSocket, send a PairRequest, await the
/// PairResult, persist it, and return.
@MainActor
@Observable
final class PairingViewModel {
    var status: Status = .idle
    var lastError: String?

    enum Status: Equatable {
        case idle
        case connecting
        case authenticating
        case success(PairedMac)
        case failure(String)
    }

    let store: PairedMacStore
    init(store: PairedMacStore) { self.store = store }

    func pair(fromCode encoded: String, apnsToken: String?) async {
        do {
            let invite = try PairCodec.decodeInvite(encoded)
            await pair(invite: invite, apnsToken: apnsToken)
        } catch {
            status = .failure("That doesn't look like a Claude Swarm invite.")
            lastError = "\(error)"
        }
    }

    func pair(invite: PairingInvite, apnsToken: String?) async {
        status = .connecting
        guard !invite.certThumbprint.isEmpty else {
            status = .failure("Invite is missing a TLS thumbprint. Update Claude Swarm on the Mac and re-issue the QR.")
            return
        }
        guard let url = URL(string: "wss://\(invite.host):\(invite.port)/") else {
            status = .failure("Invalid host in invite.")
            return
        }
        let pin = CertPinDelegate(thumbprint: invite.certThumbprint)
        let session = URLSession(configuration: .ephemeral, delegate: pin, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        task.resume()
        let req = PairRequest(
            pairingCode: invite.pairingCode,
            deviceName: UIDevice.current.name,
            deviceId: store.deviceId,
            apnsToken: apnsToken,
            osVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        )
        guard let data = try? PairCodec.encodeMessage(.pair(req)) else {
            status = .failure("Could not encode pair request.")
            return
        }
        do {
            try await task.send(.data(data))
            status = .authenticating
            let result = try await task.receive()
            let raw: Data
            switch result {
            case .data(let d): raw = d
            case .string(let s): raw = Data(s.utf8)
            @unknown default: raw = Data()
            }
            let message = try PairCodec.decodeMessage(raw)
            switch message {
            case .paired(let result):
                let paired = PairedMac(
                    macId: result.macId,
                    macName: result.macName,
                    host: invite.host,
                    port: invite.port,
                    bearerToken: result.bearerToken,
                    certThumbprint: invite.certThumbprint,
                    pairedAt: Date()
                )
                store.save(paired)
                status = .success(paired)
            case .pairError(let reason):
                status = .failure(reason)
            default:
                status = .failure("Unexpected response from Mac.")
            }
        } catch {
            status = .failure("Could not reach Mac: \(error.localizedDescription)")
        }
        task.cancel(with: .normalClosure, reason: nil)
    }
}
