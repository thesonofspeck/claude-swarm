import Foundation
import KeychainKit
import PersistenceKit
import PairingProtocol
import PairingService
import ApnsClient
import SleepGuard
import ClaudeSwarmNotifications

/// Glues the iOS-pairing layer to the rest of the app. Owns:
/// - the local PairingServer (WebSocket)
/// - the PairStore (Keychain)
/// - the ApnsClient + ApnsConfig
/// - the SleepGuard (engages while ≥1 device is paired)
///
/// Translates session lifecycle and hook events into wire events, fans
/// them out to live WebSocket clients and to APNs, and dispatches
/// inbound commands back into the app (approvals, session input).
@MainActor
public final class RemoteCoordinator: ObservableObject {
    @Published public private(set) var pairedDevices: [PairRecord] = []
    @Published public private(set) var liveDeviceIds: Set<String> = []
    @Published public var pushConfig: PushBackendConfig
    @Published public private(set) var sleepGuardHeld: Bool = false

    public var apnsConfig: ApnsConfig {
        get { pushConfig.direct }
        set { pushConfig.direct = newValue; saveConfig() }
    }
    public var relayConfig: RelayConfig {
        get { pushConfig.relay }
        set { pushConfig.relay = newValue; saveConfig() }
    }
    public var pushBackend: PushBackend {
        get { pushConfig.backend }
        set { pushConfig.backend = newValue; saveConfig(); rebuildSender() }
    }

    public let store: PairStore
    public let invites: PairingInviteService
    public let server: PairingServer
    public let sleepGuard: SleepGuard
    public let apnsKeychain: Keychain

    /// Caller (AppEnvironment) wires these to forward commands into
    /// SessionManager / hook responder.
    public var onSendInput: ((_ sessionId: String, _ text: String) async -> Void)?
    public var onApproval: ((_ approvalId: String, _ response: ApprovalResponse) async -> Void)?

    private let macId: String
    private let macName: String
    private let configURL: URL
    private var sender: PushSender?

    public init(
        macId: String,
        macName: String,
        port: UInt16 = 7321,
        apnsKeychain: Keychain = Keychain(service: "com.claudeswarm.apns"),
        pairKeychain: Keychain = Keychain(service: "com.claudeswarm.pairings")
    ) throws {
        self.macId = macId
        self.macName = macName
        self.apnsKeychain = apnsKeychain
        self.store = PairStore(keychain: pairKeychain)
        self.invites = PairingInviteService(macId: macId, macName: macName)
        self.server = PairingServer(
            store: store,
            invites: invites,
            macName: macName,
            macId: macId,
            port: port
        )
        self.sleepGuard = SleepGuard()

        try AppDirectories.ensureExists()
        self.configURL = AppDirectories.supportRoot.appendingPathComponent("push.json")
        if let data = try? Data(contentsOf: configURL),
           let cfg = try? JSONDecoder().decode(PushBackendConfig.self, from: data) {
            self.pushConfig = cfg
        } else if let legacyData = try? Data(contentsOf: AppDirectories.supportRoot.appendingPathComponent("apns.json")),
                  let legacy = try? JSONDecoder().decode(ApnsConfig.self, from: legacyData) {
            self.pushConfig = PushBackendConfig(backend: .direct, direct: legacy, relay: .init())
        } else {
            self.pushConfig = PushBackendConfig()
        }

        rebuildSender()
        try server.start()
        Task { await self.refreshPaired() }

        server.setCommandHandler { [weak self] cmd, record in
            await self?.handle(command: cmd, from: record)
        }
    }

    deinit {
        server.stop()
    }

    // MARK: - Pairing

    public func issueInvite() async -> PairingInvite {
        await invites.issue(host: bestHostname(), port: server.port.rawValue)
    }

    public func unpair(deviceId: String) async {
        try? await store.unregister(deviceId: deviceId)
        await refreshPaired()
    }

    public func refreshPaired() async {
        let all = await store.all()
        let live = Set(server.pairedDeviceIds())
        await MainActor.run {
            self.pairedDevices = all
            self.liveDeviceIds = live
        }
        await reconcileSleepGuard()
    }

    // MARK: - APNs config + key

    public func saveApnsConfig(_ cfg: ApnsConfig) {
        pushConfig.direct = cfg
        saveConfig()
        rebuildSender()
    }

    public func saveRelayConfig(_ cfg: RelayConfig) {
        pushConfig.relay = cfg
        saveConfig()
        rebuildSender()
    }

    public func saveApnsKey(pem: String) throws {
        try apnsKeychain.set(pem, account: ApnsKeyStorage.keyAccount)
        rebuildSender()
    }

    public func removeApnsKey() {
        try? apnsKeychain.remove(account: ApnsKeyStorage.keyAccount)
        rebuildSender()
    }

    public func hasApnsKey() -> Bool {
        (try? apnsKeychain.get(account: ApnsKeyStorage.keyAccount)) != nil
    }

    public func saveRelaySecret(_ secret: String) throws {
        try apnsKeychain.set(secret, account: pushConfig.relay.sharedSecretAccount)
        rebuildSender()
    }

    public func hasRelaySecret() -> Bool {
        (try? apnsKeychain.get(account: pushConfig.relay.sharedSecretAccount)) != nil
    }

    private func saveConfig() {
        try? JSONEncoder().encode(pushConfig).write(to: configURL, options: .atomic)
    }

    private func rebuildSender() {
        switch pushConfig.backend {
        case .direct:
            let pem = try? apnsKeychain.get(account: ApnsKeyStorage.keyAccount)
            sender = ApnsClient(config: pushConfig.direct, p8Pem: pem)
        case .relay:
            let secret = (try? apnsKeychain.get(account: pushConfig.relay.sharedSecretAccount)) ?? ""
            sender = RelayPushSender(config: pushConfig.relay, sharedSecret: secret)
        }
    }

    // MARK: - Fan-out

    /// Broadcast a session-update wire event to all live devices and (for
    /// transitions that warrant user attention) push to APNs.
    public func broadcast(_ summary: SessionSummary) {
        server.broadcast(.sessionUpdate(summary))
        if summary.needsInput {
            let title = "\(summary.projectName) needs input"
            let body = summary.taskTitle ?? summary.branch
            Task { await pushAll(payload: ApnsPayloads.needsInput(
                sessionId: summary.id,
                title: title, body: body
            ), collapseId: "needs-input-\(summary.id)") }
        }
    }

    public func broadcastApproval(_ request: ApprovalRequest) {
        server.broadcast(.approvalRequest(request))
        let title: String
        if let t = request.toolCall {
            title = "\(request.projectName): allow \(t.toolName)?"
        } else {
            title = "\(request.projectName) needs approval"
        }
        let body = String(request.prompt.prefix(160))
        Task {
            await pushAll(payload: ApnsPayloads.approvalRequest(
                approvalId: request.id,
                sessionId: request.sessionId,
                title: title,
                body: body,
                toolName: request.toolCall?.toolName,
                argumentSummary: request.toolCall?.argumentSummary
            ), collapseId: "approval-\(request.id)")
        }
    }

    public func sendSnapshot(_ summaries: [SessionSummary], to deviceId: String? = nil) {
        if let deviceId {
            server.sendTo(deviceId: deviceId, event: .sessionsSnapshot(summaries))
        } else {
            server.broadcast(.sessionsSnapshot(summaries))
        }
    }

    private func pushAll(payload: [String: Any], collapseId: String) async {
        guard let sender else { return }
        let backendEnabled = (pushConfig.backend == .direct && pushConfig.direct.enabled)
            || (pushConfig.backend == .relay && pushConfig.relay.enabled)
        guard backendEnabled else { return }
        let recipients = await store.all().compactMap { $0.apnsToken }
        for token in recipients {
            _ = try? await sender.send(payload: payload, to: token, collapseId: collapseId)
        }
    }

    // MARK: - Inbound commands

    private func handle(command: ClientCommand, from record: PairRecord) async {
        switch command {
        case .sendInput(let sessionId, let text, _):
            await onSendInput?(sessionId, text)
        case .approve(let approvalId, let response):
            await onApproval?(approvalId, response)
        case .requestSnapshot:
            // Caller refreshes via PairingService; coordinator stays stateless.
            break
        case .ping:
            break
        }
        _ = record
    }

    private func reconcileSleepGuard() async {
        let engaged = !pairedDevices.isEmpty
        await sleepGuard.setEngaged(engaged)
        let held = await sleepGuard.state.heldAssertion
        await MainActor.run { self.sleepGuardHeld = held }
    }

    private func bestHostname() -> String {
        // Falls back to `localhost`; the user can edit the host in the
        // pairing sheet if Bonjour-resolved hostname is unreachable on
        // their VPN.
        Host.current().localizedName ?? Host.current().name ?? "localhost"
    }
}
