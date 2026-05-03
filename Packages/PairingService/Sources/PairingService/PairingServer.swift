import Foundation
import Network
import PairingProtocol

/// Local WebSocket server: a paired iPhone connects, authenticates with its
/// bearer token, then receives `ServerEvent`s and sends `ClientCommand`s.
/// Pairing flow uses the same socket — a fresh client sends `pair` first,
/// then upgrades to authenticated traffic.
///
/// All mutable state (`connections`, `commandHandler`, `certThumbprint`)
/// is fenced through `queue`. Public APIs that read state do so via
/// `queue.sync`; mutations dispatch via `queue.async`. The class is
/// `@unchecked Sendable` because Network.framework callbacks are
/// invoked on `queue` and we route everything else through it as well.
public final class PairingServer: @unchecked Sendable {
    public typealias CommandHandler = @Sendable (ClientCommand, PairRecord) async -> Void

    public let port: NWEndpoint.Port
    public let bonjourName: String
    public let macName: String
    public let macId: String

    private let store: PairStore
    private let invites: PairingInviteService
    private let queue = DispatchQueue(label: "com.claudeswarm.pairing.server")
    // All four below are queue-bound. Reads/writes outside the queue are
    // a bug.
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: AuthenticatedConnection] = [:]
    private var commandHandler: CommandHandler?
    private var _certThumbprint: String = ""

    public var certThumbprint: String { queue.sync { _certThumbprint } }

    public init(
        store: PairStore,
        invites: PairingInviteService,
        macName: String,
        macId: String,
        port: UInt16 = 7321,
        bonjourName: String = "Claude Swarm"
    ) {
        self.store = store
        self.invites = invites
        self.macName = macName
        self.macId = macId
        self.port = NWEndpoint.Port(rawValue: port) ?? 7321
        self.bonjourName = bonjourName
    }

    public func setCommandHandler(_ handler: @escaping CommandHandler) {
        queue.sync { commandHandler = handler }
    }

    public func start() throws {
        let identity = try PairingTLS.loadOrGenerate(macId: macId)
        // Stash thumbprint on the queue before the listener fires so any
        // immediate read sees the populated value.
        queue.sync { _certThumbprint = identity.thumbprintHex }

        let tlsOptions = NWProtocolTLS.Options()
        let secIdentity = sec_identity_create(identity.secIdentity)!
        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions, secIdentity
        )
        sec_protocol_options_set_peer_authentication_required(
            tlsOptions.securityProtocolOptions, false
        )

        let parameters = NWParameters(tls: tlsOptions, tcp: .init())
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        let listener = try NWListener(using: parameters, on: port)
        listener.service = NWListener.Service(
            name: bonjourName,
            type: "_claudeswarm._tcp"
        )
        listener.newConnectionHandler = { [weak self] conn in
            // Network.framework dispatches this on `queue` already; no
            // extra fence needed here, but `accept` writes `connections`
            // and must run on `queue`.
            self?.accept(conn)
        }
        listener.start(queue: queue)
        queue.sync { self.listener = listener }
    }

    public func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            for c in connections.values { c.close() }
            connections.removeAll()
        }
    }

    deinit { stop() }

    @discardableResult
    public func broadcast(_ event: ServerEvent) -> [String] {
        // Pull the live snapshot AND read each conn's record on `queue`
        // so we never witness a half-written record from another thread.
        let snapshot: [(AuthenticatedConnection, PairRecord)] = queue.sync {
            connections.values.compactMap { conn in
                conn.recordSnapshot.map { (conn, $0) }
            }
        }
        var delivered: [String] = []
        for (conn, record) in snapshot {
            conn.send(.event(event))
            delivered.append(record.id)
        }
        return delivered
    }

    public func sendTo(deviceId: String, event: ServerEvent) {
        let matches: [AuthenticatedConnection] = queue.sync {
            connections.values.filter { $0.recordSnapshot?.id == deviceId }
        }
        for conn in matches {
            conn.send(.event(event))
        }
    }

    public func pairedDeviceIds() -> [String] {
        queue.sync { connections.values.compactMap { $0.recordSnapshot?.id } }
    }

    // MARK: - Connection lifecycle (always called on `queue`)

    private func accept(_ raw: NWConnection) {
        // Snapshot the handler under the queue so the connection can
        // dispatch even if the host clears it later.
        let handlerSnapshot = commandHandler
        let conn = AuthenticatedConnection(
            raw: raw,
            queue: queue,
            store: store,
            invites: invites,
            macName: macName,
            macId: macId,
            onCommand: { [weak self] cmd, record in
                // Re-resolve under the queue so we always see the latest
                // handler, not the captured snapshot.
                guard let self else { return }
                let handler = self.queue.sync { self.commandHandler ?? handlerSnapshot }
                Task { await handler?(cmd, record) }
            },
            onClose: { [weak self] id in
                guard let self else { return }
                self.queue.async {
                    self.connections.removeValue(forKey: id)
                }
            }
        )
        connections[ObjectIdentifier(conn)] = conn
        // Only start *after* the dictionary write so onClose can never
        // fire before the entry exists.
        conn.start()
    }
}

/// Owns one socket. Manages handshake state, frame send/receive, auth, and
/// dispatches commands.
///
/// All mutable state (`_record`) is fenced through the same queue the
/// owning server uses; reads through `recordSnapshot` are queue-safe.
final class AuthenticatedConnection: @unchecked Sendable {
    let raw: NWConnection
    let queue: DispatchQueue
    let store: PairStore
    let invites: PairingInviteService
    let macName: String
    let macId: String
    let onCommand: @Sendable (ClientCommand, PairRecord) -> Void
    let onClose: @Sendable (ObjectIdentifier) -> Void

    /// All `_record` mutations and reads happen on `queue`.
    private var _record: PairRecord?

    /// Read-only snapshot accessor — must be called inside `queue.sync`
    /// (the owning server already does so).
    var recordSnapshot: PairRecord? {
        dispatchPrecondition(condition: .onQueue(queue))
        return _record
    }

    init(
        raw: NWConnection, queue: DispatchQueue,
        store: PairStore, invites: PairingInviteService,
        macName: String, macId: String,
        onCommand: @escaping @Sendable (ClientCommand, PairRecord) -> Void,
        onClose: @escaping @Sendable (ObjectIdentifier) -> Void
    ) {
        self.raw = raw
        self.queue = queue
        self.store = store
        self.invites = invites
        self.macName = macName
        self.macId = macId
        self.onCommand = onCommand
        self.onClose = onClose
    }

    func start() {
        raw.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.receive()
            case .failed, .cancelled:
                guard let self else { return }
                self.onClose(ObjectIdentifier(self))
            default: break
            }
        }
        raw.start(queue: queue)
    }

    func close() {
        raw.cancel()
    }

    func send(_ message: WireMessage) {
        guard let data = try? PairCodec.encodeMessage(message) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        raw.send(content: data, contentContext: context, completion: .contentProcessed { _ in })
    }

    private func receive() {
        raw.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                _ = error
                self.onClose(ObjectIdentifier(self))
                // Do NOT re-arm — the socket is dead.
                return
            }
            if let data, let message = try? PairCodec.decodeMessage(data) {
                self.handle(message)
            }
            self.receive()
        }
    }

    private func handle(_ message: WireMessage) {
        switch message {
        case .pair(let req):
            Task { await self.handlePair(req) }
        case .hello(let req):
            Task { await self.handleHello(req) }
        case .command(let cmd):
            // `_record` is queue-bound; this callback runs on `queue`.
            dispatchPrecondition(condition: .onQueue(queue))
            guard let record = _record else {
                send(.helloError("Not authenticated"))
                return
            }
            onCommand(cmd, record)
        default:
            break
        }
    }

    private func handlePair(_ req: PairRequest) async {
        guard let invite = await invites.consume(code: req.pairingCode) else {
            send(.pairError("Pairing code expired or invalid."))
            return
        }
        _ = invite
        let token = Self.randomToken()
        let record = PairRecord(
            id: req.deviceId,
            deviceName: req.deviceName,
            bearerToken: token,
            apnsToken: req.apnsToken
        )
        do {
            try await store.register(record)
            queue.async { self._record = record }
            send(.paired(PairResult(bearerToken: token, macId: macId, macName: macName)))
        } catch {
            send(.pairError("Could not save pair record: \(error.localizedDescription)"))
        }
    }

    private func handleHello(_ req: AuthRequest) async {
        guard var record = await store.findByBearer(req.bearerToken),
              record.id == req.deviceId else {
            send(.helloError("Unknown bearer token. Re-pair this device."))
            return
        }
        record.lastSeenAt = Date()
        if let token = req.apnsToken { record.apnsToken = token }
        try? await store.save(record)
        queue.async { self._record = record }
        send(.helloOk(AuthResult(macName: macName, serverTime: Date())))
    }

    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}
