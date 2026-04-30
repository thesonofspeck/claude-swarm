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

    private let hookServer: HookSocketServer

    public init() throws {
        try AppDirectories.ensureExists()

        self.keychain = Keychain()
        let db = try Database.main()
        self.database = db
        self.projects = ProjectRepository(db: db)
        self.sessionsRepo = SessionRepository(db: db)
        self.wrike = WrikeClient(keychain: keychain)
        self.github = GitHubClient(keychain: keychain)
        self.memory = try MemoryStore()
        self.sessionManager = SessionManager(sessions: sessionsRepo, projects: projects)
        let notifier = Notifier()
        self.notifier = notifier
        self.installer = Installer()
        self.diff = DiffService()
        self.history = HistoryService()

        let server = HookSocketServer(socketURL: AppDirectories.hooksSocket) { event in
            Task { @MainActor in
                guard event.kind == .notification, let id = event.sessionId else { return }
                notifier.sessionNeedsInput(
                    sessionId: id,
                    title: "Session needs input",
                    body: event.message ?? "",
                    isForeground: false
                )
            }
        }
        self.hookServer = server
        try server.start()
    }
}
