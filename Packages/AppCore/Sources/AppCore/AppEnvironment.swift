import Foundation
import CryptoKit
import KeychainKit
import PersistenceKit
import GitKit
import WrikeKit
import GitHubKit
import LibraryKit
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
    public let sessionManager: SessionManager
    public let notifier: Notifier
    public let installer: Installer
    public let diff: DiffService
    public let history: HistoryService
    public let registry: RunningSessionRegistry
    public let projectList: ProjectListViewModel
    public let wrikeBridge: WrikeBridge
    public let remote: RemoteCoordinator
    public let library: LibraryStore
    public let activity: ActivityLog
    public let llm: LLMHelper

    @Published public var settings: AppSettings
    @Published public var lastError: String?

    private let hookServer: HookSocketServer
    private let settingsURL: URL
    private var backgroundTasks: [Task<Void, Never>] = []

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
        self.installer = Installer()
        self.diff = DiffService()
        self.history = HistoryService()
        self.registry = RunningSessionRegistry()
        let notifier = Notifier()
        self.notifier = notifier

        let notifyScript = try AppPaths.materializeNotifyScript()
        let policyScript = try AppPaths.materializePolicyScript()
        let manager = SessionManager(
            sessions: sessionsRepo,
            projects: projects,
            installer: installer,
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
            macId: try AppEnvironment.stableMacId(),
            macName: Host.current().localizedName ?? "Mac"
        )

        let libraryCache = AppDirectories.supportRoot.appendingPathComponent("library-cache", isDirectory: true)
        let libSource = TeamLibrarySource(cacheRoot: libraryCache)
        self.library = LibraryStore(teamSource: libSource)
        self.activity = ActivityLog(db: db)
        // Capture by reference so the helper picks up runtime changes
        // (the user can update the claude path at any time).
        self.llm = LLMHelper(
            claudeExecutable: { [weak self] in
                self?.settings.claudeExecutable ?? "/usr/local/bin/claude"
            }
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

        // Quiet hours: queue pushes during the window, drain on a timer
        // when the window opens.
        let settingsRef = { [weak self] in self?.settings ?? AppSettings() }
        self.remote.quietHoursPredicate = { settingsRef().isInQuietHours() }
        // Wake once a minute; the only thing this does outside quiet
        // hours is flush queued pushes — fast enough that latency on the
        // first push after the window ends is acceptable.
        let drainInterval: UInt64 = 60 * 1_000_000_000
        let drainTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: drainInterval)
                if Task.isCancelled { break }
                guard let self else { break }
                if !self.settings.isInQuietHours() {
                    await self.remote.drainQueuedPushes()
                }
            }
        }
        backgroundTasks.append(drainTask)

        let janitor = WorktreeJanitor(projects: projects, sessions: sessionsRepo)
        Task.detached {
            _ = await janitor.reconcile()
            let indexer = SpotlightIndexer(projects: projects, sessions: sessionsRepo)
            await indexer.reindexAll()
        }

        let activityRef = self.activity
        let server = HookSocketServer(socketURL: AppDirectories.hooksSocket) { [weak notifier, weak remoteRef] event in
            Task { @MainActor in
                guard let id = event.sessionId else { return }
                if let status = event.resultingStatus {
                    try? repoRef.setStatus(id: id, status)
                }
                let session = try? repoRef.find(id: id)
                try? activityRef.append(ActivityEvent(
                    sessionId: id,
                    projectId: session?.projectId,
                    kind: event.kind.rawValue,
                    message: event.message
                ))
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
                        // Stable id derived from sessionId + prompt so a
                        // hook firing twice (retry / reconnect) collapses
                        // into a single APNs alert.
                        let promptText = event.message ?? "Claude needs your input."
                        let approval = ApprovalRequest(
                            id: stableApprovalId(sessionId: id, prompt: promptText),
                            sessionId: id,
                            projectName: project.name,
                            taskTitle: session.taskTitle,
                            prompt: promptText,
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

    /// Build a per-project memory store backed by `<projectRoot>/.claude/memory/`
    /// plus the shared global directory. Pass `nil` for a global-only store.
    public func memoryStore(for project: Project?) throws -> MemoryStore {
        try MemoryStore(
            projectRoot: project.map { URL(fileURLWithPath: $0.localPath) },
            projectId: project?.id,
            globalRoot: AppPaths.globalMemoryRoot
        )
    }

    public func saveSettings() {
        do {
            try settings.save(to: settingsURL)
        } catch {
            lastError = "Could not save settings: \(error)"
        }
    }

    /// Stops the long-running maintenance Tasks and the hook socket
    /// server. Idempotent. Wire this into `applicationWillTerminate` for
    /// faster app shutdown; tests can call it explicitly.
    public func shutdown() {
        for task in backgroundTasks { task.cancel() }
        backgroundTasks.removeAll()
        hookServer.stop()
    }

    /// Stable per-install identifier persisted alongside other support
    /// data. Used as the macId in the wire protocol so iOS can recognise
    /// the same Mac across reboots.
    static func stableMacId() throws -> String {
        let url = AppDirectories.supportRoot.appendingPathComponent("mac-id")
        if let id = try? String(contentsOf: url, encoding: .utf8), !id.isEmpty { return id }
        let id = UUID().uuidString
        do {
            try id.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // Without a stable mac id, paired iPhones can't recognise this
            // Mac across launches — the user would have to re-pair every
            // time. Surface the failure rather than silently breaking.
            SwarmLog.bootstrap.error("Failed to persist mac id: \(String(describing: error), privacy: .public)")
            throw error
        }
        return id
    }
}

/// Hashes (sessionId + prompt) into a hex id so duplicate hook events
/// produce the same ApprovalRequest.id and get collapsed by APNs and
/// the iOS client's pendingApprovals dedup.
public func stableApprovalId(sessionId: String, prompt: String) -> String {
    let bytes = Data("\(sessionId)|\(prompt)".utf8)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
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
    public var quietHoursEnabled: Bool
    public var quietHoursStartMinute: Int   // minutes since 00:00 local time
    public var quietHoursEndMinute: Int
    public var teamLibrary: TeamLibraryConfig

    public init(
        claudeExecutable: String = "/usr/local/bin/claude",
        ghExecutable: String = "",
        gitExecutable: String = "/usr/bin/git",
        pythonExecutable: String = "/usr/bin/python3",
        defaultBaseBranch: String = "main",
        notificationSoundEnabled: Bool = true,
        hasCompletedOnboarding: Bool = false,
        quietHoursEnabled: Bool = false,
        quietHoursStartMinute: Int = 19 * 60,
        quietHoursEndMinute: Int = 8 * 60,
        teamLibrary: TeamLibraryConfig = .disabled
    ) {
        self.claudeExecutable = claudeExecutable
        self.ghExecutable = ghExecutable
        self.gitExecutable = gitExecutable
        self.pythonExecutable = pythonExecutable
        self.defaultBaseBranch = defaultBaseBranch
        self.notificationSoundEnabled = notificationSoundEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStartMinute = quietHoursStartMinute
        self.quietHoursEndMinute = quietHoursEndMinute
        self.teamLibrary = teamLibrary
    }

    public func isInQuietHours(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if quietHoursStartMinute <= quietHoursEndMinute {
            return nowMinute >= quietHoursStartMinute && nowMinute < quietHoursEndMinute
        }
        // Window crosses midnight (e.g. 19:00 → 08:00).
        return nowMinute >= quietHoursStartMinute || nowMinute < quietHoursEndMinute
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
        quietHoursEnabled = (try? c.decode(Bool.self, forKey: .quietHoursEnabled)) ?? false
        quietHoursStartMinute = (try? c.decode(Int.self, forKey: .quietHoursStartMinute)) ?? 19 * 60
        quietHoursEndMinute = (try? c.decode(Int.self, forKey: .quietHoursEndMinute)) ?? 8 * 60
        teamLibrary = (try? c.decode(TeamLibraryConfig.self, forKey: .teamLibrary)) ?? .disabled
    }

    private enum CodingKeys: String, CodingKey {
        case claudeExecutable, ghExecutable, gitExecutable, pythonExecutable
        case defaultBaseBranch, notificationSoundEnabled, hasCompletedOnboarding
        case quietHoursEnabled, quietHoursStartMinute, quietHoursEndMinute
        case teamLibrary
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
