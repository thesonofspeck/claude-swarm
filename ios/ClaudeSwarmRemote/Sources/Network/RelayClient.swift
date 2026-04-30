import Foundation
import Combine
import PairingProtocol

/// A single iOS↔Mac WebSocket session. Auto-reconnects with capped
/// exponential backoff. Publishes inbound `ServerEvent`s as a stream and
/// exposes a `send` for outbound `ClientCommand`s.
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
        self.session = URLSession(configuration: cfg)
    }

    func updateApnsToken(_ token: String?) {
        self.apnsToken = token
    }

    func connect() {
        guard task == nil else { return }
        state = .connecting
        guard let url = URL(string: "ws://\(mac.host):\(mac.port)/") else {
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
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.connect()
        }
    }
}
