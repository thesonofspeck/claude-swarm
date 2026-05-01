import Foundation
import Combine
import CryptoKit
import PairingProtocol

/// A single iOS↔Mac WebSocket session. Auto-reconnects with capped
/// exponential backoff. Publishes inbound `ServerEvent`s as a stream and
/// exposes a `send` for outbound `ClientCommand`s.
///
/// TLS uses self-signed certs generated on the Mac; the iOS client pins
/// on the SHA-256 thumbprint of the server cert (passed via the QR
/// invite and stored alongside the bearer token).
@MainActor
final class RelayClient: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case authenticating
        case live
        case failed(String)
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var serverTime: Date?
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var pendingApprovals: [ApprovalRequest] = []

    let mac: PairedMac
    private let deviceId: String
    private var apnsToken: String?
    private var task: URLSessionWebSocketTask?
    private var session: URLSession
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?

    let events = PassthroughSubject<ServerEvent, Never>()

    init(mac: PairedMac, deviceId: String) {
        self.mac = mac
        self.deviceId = deviceId
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 15
        let pin = CertPinDelegate(thumbprint: mac.certThumbprint)
        self.session = URLSession(configuration: cfg, delegate: pin, delegateQueue: nil)
    }

    func updateApnsToken(_ token: String?) {
        self.apnsToken = token
    }

    func connect() {
        guard task == nil else { return }
        state = .connecting
        guard let url = URL(string: "wss://\(mac.host):\(mac.port)/") else {
            state = .failed("Bad URL")
            return
        }
        let request = URLRequest(url: url, timeoutInterval: 15)
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receiveLoop(task: task)
        sendHello()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .disconnected
    }

    func send(_ command: ClientCommand) {
        guard let task else { return }
        let cmdId = UUID().uuidString
        let message: WireMessage
        switch command {
        case .sendInput(let s, let t, _):
            message = .command(.sendInput(sessionId: s, text: t, commandId: cmdId))
        default:
            message = .command(command)
        }
        guard let data = try? PairCodec.encodeMessage(message) else { return }
        task.send(.data(data)) { [weak self] error in
            if error != nil { Task { @MainActor in self?.scheduleReconnect() } }
        }
    }

    func approve(_ request: ApprovalRequest, response: ApprovalResponse) {
        send(.approve(approvalId: request.id, response: response))
        pendingApprovals.removeAll { $0.id == request.id }
    }

    func sendInput(sessionId: String, text: String) {
        send(.sendInput(sessionId: sessionId, text: text, commandId: UUID().uuidString))
    }

    func requestSnapshot() {
        send(.requestSnapshot)
    }

    // MARK: - Internals

    private func sendHello() {
        let auth = AuthRequest(
            bearerToken: mac.bearerToken,
            deviceId: deviceId,
            apnsToken: apnsToken,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        )
        let message = WireMessage.hello(auth)
        guard let data = try? PairCodec.encodeMessage(message), let task else { return }
        state = .authenticating
        task.send(.data(data)) { _ in }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receiveLoop(task: task)
                case .failure:
                    self.task = nil
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handle(_ raw: URLSessionWebSocketTask.Message) {
        let data: Data
        switch raw {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }
        guard let message = try? PairCodec.decodeMessage(data) else { return }
        switch message {
        case .helloOk(let result):
            state = .live
            serverTime = result.serverTime
            reconnectAttempts = 0
            send(.requestSnapshot)
        case .helloError(let reason):
            state = .failed(reason)
            disconnect()
        case .event(let event):
            apply(event: event)
            events.send(event)
        default:
            break
        }
    }

    private func apply(event: ServerEvent) {
        switch event {
        case .sessionsSnapshot(let list):
            sessions = list
        case .sessionUpdate(let summary):
            if let idx = sessions.firstIndex(where: { $0.id == summary.id }) {
                sessions[idx] = summary
            } else {
                sessions.insert(summary, at: 0)
            }
        case .approvalRequest(let req):
            pendingApprovals.removeAll { $0.id == req.id }
            pendingApprovals.insert(req, at: 0)
        case .approvalCancelled(let id):
            pendingApprovals.removeAll { $0.id == id }
        case .transcriptChunk:
            break
        }
    }

    private func scheduleReconnect() {
        reconnectAttempts = min(reconnectAttempts + 1, 6)
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30)
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.connect()
        }
    }
}

/// Pins the server's TLS cert by SHA-256 thumbprint. We can't validate
/// the cert via the system trust store (it's self-signed on the Mac), so
/// we explicitly compare the leaf cert's DER hash against the thumbprint
/// embedded in the QR pairing invite.
final class CertPinDelegate: NSObject, URLSessionDelegate {
    let thumbprint: String
    init(thumbprint: String) { self.thumbprint = thumbprint }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              SecTrustGetCertificateCount(trust) > 0,
              let cert = SecTrustCopyCertificateChain(trust).flatMap({ ($0 as? [SecCertificate])?.first })
                ?? SecTrustGetCertificateAtIndex(trust, 0)
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let der = SecCertificateCopyData(cert) as Data
        let actual = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        if actual == thumbprint, !thumbprint.isEmpty {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
