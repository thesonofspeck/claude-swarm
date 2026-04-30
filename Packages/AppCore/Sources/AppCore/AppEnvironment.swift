import Foundation
import KeychainKit
import PersistenceKit
import GitKit
import WrikeKit
import GitHubKit
import GitKit
import SessionCore
import MemoryService
import ClaudeSwarmNotifications
import AgentBootstrap
import PairingProtocol

@MainActor
public final class AppEnvironment: ObservableObject {
    public let keychain: Keychain
    public let database: Database
    public let projects: ProjectRepository
    public let sessionsRepo: SessionRepository
    public let wrike: WrikeClient
    public let github: GitHubClient
    public let memory: MemoryStore
    public let sessionManager: SessionManager
    public let notifier: Notifier
    public let installer: Installer
    public let diff: DiffService
    public let history: HistoryService
    public let registry: RunningSessionRegistry
    public let projectList: ProjectListViewModel
    public let wrikeBridge: WrikeBridge
    public let remote: RemoteCoordinator

    @Published public var settings: AppSettings
    @Published public var lastError: String?

    private let hookServer: HookSocketServer
    private let settingsURL: URL

    public init() throws {
        try AppDirectories.ensureExists()

        self.keychain = Keychain()
        let db = try Database.main()
        self.database = db
        self.projects = ProjectRepository(db: db)
        self.sessionsRepo = SessionRepository(db: db)
        let wrikeClient = WrikeClient(keychain: keychain)
        self.wrike = wrikeClient
        self.wrikeBridge = WrikeBridge(client: wrikeClient)
        let appSettings = AppSettings.load(from: AppDirectories.settingsURL) ?? AppSettings()
        let ghRunner = GhRunner(executable: appSettings.ghExecutable.isEmpty ? nil : appSettings.ghExecutable)
        self.github = GitHubClient(runner: ghRunner)
        self.memory = try MemoryStore()
        self.installer = Installer()
        self.diff = DiffService()
        self.history = HistoryService()
        self.registry = RunningSessionRegistry()
        let notifier = Notifier()
        self.notifier = notifier

        let notifyScript = try AppPaths.materializeNotifyScript()
        let policyScript = try AppPaths.materializePolicyScript()
        let memoryBin = AppPaths.memoryBinary()
        let manager = SessionManager(
            sessions: sessionsRepo,
            projects: projects,
            installer: installer,
            memoryBinaryPath: memoryBin.path,
            notifyScriptPath: notifyScript.path,
            policyScriptPath: policyScript.path
        )
        self.sessionManager = manager
        self.projectList = ProjectListViewModel(
            projects: projects,
            sessions: sessionsRepo,
            manager: manager
        )

        self.settingsURL = AppDirectories.settingsURL
        self.settings = AppSettings.load(from: settingsURL) ?? AppSettings()

        self.remote = try RemoteCoordinator(
            macId: AppEnvironment.stableMacId(),
            macName: Host.current().localizedName ?? "Mac"
        )
        let remoteRef = self.remote
        let projectsRef = self.projects
        remote.onSendInput = { sessionId, text in
            // Hook back into the running session via the PTY's stdin —
            // requires the session to be alive in the registry. Drop if not.
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .swarmRemoteInput,
                    object: nil,
                    userInfo: ["sessionId": sessionId, "text": text]
                )
            }
        }
        remote.onApproval = { approvalId, response in
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .swarmRemoteApproval,
                    object: nil,
                    userInfo: ["approvalId": approvalId, "response": response.rawValue]
                )
            }
        }

        let registryRef = self.registry
        let repoRef = self.sessionsRepo
        let janitor = WorktreeJanitor(projects: projects, sessions: sessionsRepo)
        let memoryRef = self.memory
        Task.detached {
            _ = await janitor.reconcile()
            let indexer = SpotlightIndexer(projects: projects, sessions: sessionsRepo, memory: memoryRef)
            await indexer.reindexAll()
        }

        let server = HookSocketServer(socketURL: AppDirectories.hooksSocket) { [weak notifier, weak remoteRef] event in
            Task { @MainActor in
                guard let id = event.sessionId else { return }
                if let status = event.resultingStatus {
                    try? repoRef.setStatus(id: id, status)
                }
                if event.kind == .notification {
                    let isForeground = (registryRef.foregroundSessionId == id)
                    notifier?.sessionNeedsInput(
                        sessionId: id,
                        title: "Session needs input",
                        body: event.message ?? "",
                        isForeground: isForeground
                    )
                    if let session = try? repoRef.find(id: id),
                       let project = try? projectsRef.find(id: session.projectId),
                       let remote = remoteRef {
                        let approval = ApprovalRequest(
                            id: UUID().uuidString,
                            sessionId: id,
                            projectName: project.name,
                            taskTitle: session.taskTitle,
                            prompt: event.message ?? "Claude needs your input.",
                            toolCall: nil,
                            createdAt: Date()
                        )
                        remote.broadcastApproval(approval)
                    }
                }
                if let remote = remoteRef,
                   let session = try? repoRef.find(id: id),
                   let project = try? projectsRef.find(id: session.projectId) {
                    let payload = SessionSummary(
                        id: session.id,
                        projectId: session.projectId,
                        projectName: project.name,
                        taskTitle: session.taskTitle,
                        branch: session.branch,
                        status: SessionStatusPayload(rawValue: session.status.rawValue) ?? .running,
                        needsInput: session.status == .waitingForInput,
                        updatedAt: session.updatedAt
                    )
                    remote.broadcast(payload)
                }
            }
        }
        self.hookServer = server
        try server.start()
    }

    public func saveSettings() {
        do {
            try settings.save(to: settingsURL)
        } catch {
            lastError = "Could not save settings: \(error)"
        }
    }

    /// Stable per-install identifier persisted alongside other support
    /// data. Used as the macId in the wire protocol so iOS can recognise
    /// the same Mac across reboots.
    static func stableMacId() -> String {
        let url = AppDirectories.supportRoot.appendingPathComponent("mac-id")
        if let id = try? String(contentsOf: url, encoding: .utf8), !id.isEmpty { return id }
        let id = UUID().uuidString
        try? id.write(to: url, atomically: true, encoding: .utf8)
        return id
    }
}

public extension Notification.Name {
    static let swarmRemoteInput = Notification.Name("ClaudeSwarm.RemoteInput")
    static let swarmRemoteApproval = Notification.Name("ClaudeSwarm.RemoteApproval")
}

public struct AppSettings: Codable, Equatable {
    public var claudeExecutable: String
    public var ghExecutable: String
    public var gitExecutable: String
    public var pythonExecutable: String
    public var defaultBaseBranch: String
    public var notificationSoundEnabled: Bool
    public var hasCompletedOnboarding: Bool

    public init(
        claudeExecutable: String = "/usr/local/bin/claude",
        ghExecutable: String = "",
        gitExecutable: String = "/usr/bin/git",
        pythonExecutable: String = "/usr/bin/python3",
        defaultBaseBranch: String = "main",
        notificationSoundEnabled: Bool = true,
        hasCompletedOnboarding: Bool = false
    ) {
        self.claudeExecutable = claudeExecutable
        self.ghExecutable = ghExecutable
        self.gitExecutable = gitExecutable
        self.pythonExecutable = pythonExecutable
        self.defaultBaseBranch = defaultBaseBranch
        self.notificationSoundEnabled = notificationSoundEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claudeExecutable = (try? c.decode(String.self, forKey: .claudeExecutable)) ?? "/usr/local/bin/claude"
        ghExecutable = (try? c.decode(String.self, forKey: .ghExecutable)) ?? ""
        gitExecutable = (try? c.decode(String.self, forKey: .gitExecutable)) ?? "/usr/bin/git"
        pythonExecutable = (try? c.decode(String.self, forKey: .pythonExecutable)) ?? "/usr/bin/python3"
        defaultBaseBranch = (try? c.decode(String.self, forKey: .defaultBaseBranch)) ?? "main"
        notificationSoundEnabled = (try? c.decode(Bool.self, forKey: .notificationSoundEnabled)) ?? true
        hasCompletedOnboarding = (try? c.decode(Bool.self, forKey: .hasCompletedOnboarding)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case claudeExecutable, ghExecutable, gitExecutable, pythonExecutable
        case defaultBaseBranch, notificationSoundEnabled, hasCompletedOnboarding
    }

    static func load(from url: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
