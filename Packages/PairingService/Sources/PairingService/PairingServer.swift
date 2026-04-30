import Foundation
import Network
import PairingProtocol

/// Local WebSocket server: a paired iPhone connects, authenticates with its
/// bearer token, then receives `ServerEvent`s and sends `ClientCommand`s.
/// Pairing flow uses the same socket — a fresh client sends `pair` first,
/// then upgrades to authenticated traffic.
public final class PairingServer: @unchecked Sendable {
    public typealias CommandHandler = @Sendable (ClientCommand, PairRecord) async -> Void

    public let port: NWEndpoint.Port
    public let bonjourName: String
    public let macName: String
    public let macId: String

    public private(set) var certThumbprint: String = ""

    private let store: PairStore
    private let invites: PairingInviteService
    private let queue = DispatchQueue(label: "com.claudeswarm.pairing.server")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: AuthenticatedConnection] = [:]
    private var commandHandler: CommandHandler?

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
        commandHandler = handler
    }

    public func start() throws {
        let identity = try PairingTLS.loadOrGenerate(macId: macId)
        certThumbprint = identity.thumbprintHex

        let tlsOptions = NWProtocolTLS.Options()
        let secIdentity = sec_identity_create(identity.secIdentity)!
        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions, secIdentity
        )
        // We pin via SHA-256 thumbprint on the iOS side, so don't require a
        // cert from clients.
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
            self?.accept(conn)
        }
        listener.start(queue: queue)
        self.listener = listener
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

    /// Broadcast an event to every authenticated connection. Returns the
    /// device ids that received it (useful for caller-side telemetry).
    @discardableResult
    public func broadcast(_ event: ServerEvent) -> [String] {
        let snapshot: [AuthenticatedConnection] = queue.sync {
            connections.values.filter { $0.record != nil }
        }
        var delivered: [String] = []
        for conn in snapshot {
            conn.send(.event(event))
            if let r = conn.record { delivered.append(r.id) }
        }
        return delivered
    }

    public func sendTo(deviceId: String, event: ServerEvent) {
        let matches: [AuthenticatedConnection] = queue.sync {
            connections.values.filter { $0.record?.id == deviceId }
        }
        for conn in matches {
            conn.send(.event(event))
        }
    }

    public func pairedDeviceIds() -> [String] {
        queue.sync { connections.values.compactMap { $0.record?.id } }
    }

    // MARK: - Connection lifecycle

    private func accept(_ raw: NWConnection) {
        let conn = AuthenticatedConnection(
            raw: raw,
            queue: queue,
            store: store,
            invites: invites,
            macName: macName,
            macId: macId,
            onCommand: { [weak self] cmd, record in
                guard let self else { return }
                Task { await self.commandHandler?(cmd, record) }
            },
            onClose: { [weak self] id in
                guard let self else { return }
                self.queue.async {
                    self.connections.removeValue(forKey: id)
                }
            }
        )
        connections[ObjectIdentifier(conn)] = conn
        conn.start()
    }
}

/// Owns one socket. Manages handshake state, frame send/receive, auth, and
/// dispatches commands.
final class AuthenticatedConnection: @unchecked Sendable {
    let raw: NWConnection
    let queue: DispatchQueue
    let store: PairStore
    let invites: PairingInviteService
    let macName: String
    let macId: String
    let onCommand: (ClientCommand, PairRecord) -> Void
    let onClose: (ObjectIdentifier) -> Void

    private(set) var record: PairRecord?

    init(
        raw: NWConnection, queue: DispatchQueue,
        store: PairStore, invites: PairingInviteService,
        macName: String, macId: String,
        onCommand: @escaping (ClientCommand, PairRecord) -> Void,
        onClose: @escaping (ObjectIdentifier) -> Void
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
                self.onClose(ObjectIdentifier(self))
                _ = error
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
            guard let record else {
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
            self.record = record
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
        self.record = record
        send(.helloOk(AuthResult(macName: macName, serverTime: Date())))
    }

    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}
