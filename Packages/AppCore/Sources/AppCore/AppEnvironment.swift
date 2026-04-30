import Foundation
import KeychainKit
import PersistenceKit
import GitKit
import WrikeKit
import GitHubKit
import SessionCore
import MemoryService
import ClaudeSwarmNotifications
import AgentBootstrap

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
        self.wrike = WrikeClient(keychain: keychain)
        self.github = GitHubClient()
        self.memory = try MemoryStore()
        self.installer = Installer()
        self.diff = DiffService()
        self.history = HistoryService()
        self.registry = RunningSessionRegistry()
        let notifier = Notifier()
        self.notifier = notifier

        let notifyScript = try AppPaths.materializeNotifyScript()
        let memoryBin = AppPaths.memoryBinary()
        let manager = SessionManager(
            sessions: sessionsRepo,
            projects: projects,
            installer: installer,
            memoryBinaryPath: memoryBin.path,
            notifyScriptPath: notifyScript.path
        )
        self.sessionManager = manager
        self.projectList = ProjectListViewModel(
            projects: projects,
            sessions: sessionsRepo,
            manager: manager
        )

        self.settingsURL = AppDirectories.settingsURL
        self.settings = AppSettings.load(from: settingsURL) ?? AppSettings()

        let registryRef = self.registry
        let repoRef = self.sessionsRepo
        let server = HookSocketServer(socketURL: AppDirectories.hooksSocket) { [weak notifier] event in
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
}

public struct AppSettings: Codable, Equatable {
    public var claudeExecutable: String
    public var defaultBaseBranch: String
    public var notificationSoundEnabled: Bool
    public var hasCompletedOnboarding: Bool

    public init(
        claudeExecutable: String = "/usr/local/bin/claude",
        defaultBaseBranch: String = "main",
        notificationSoundEnabled: Bool = true,
        hasCompletedOnboarding: Bool = false
    ) {
        self.claudeExecutable = claudeExecutable
        self.defaultBaseBranch = defaultBaseBranch
        self.notificationSoundEnabled = notificationSoundEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
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
