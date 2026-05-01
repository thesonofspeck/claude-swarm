import Foundation
import Observation
import PersistenceKit
import SessionCore

@MainActor
@Observable
public final class ProjectListViewModel {
    public private(set) var projects: [Project] = []
    public private(set) var sessionsByProject: [String: [Session]] = [:]
    public var error: String?

    private let projectsRepo: ProjectRepository
    private let sessionsRepo: SessionRepository
    private let manager: SessionManager
    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?

    public init(
        projects: ProjectRepository,
        sessions: SessionRepository,
        manager: SessionManager
    ) {
        self.projectsRepo = projects
        self.sessionsRepo = sessions
        self.manager = manager
        Task { await self.reload() }
        startPolling()
    }

    deinit {
        refreshTask?.cancel()
    }

    public func reload() async {
        do {
            let newProjects = try await projectsRepo.all()
            let newSessions = try await sessionsRepo.allByProject()
            if newProjects != projects {
                projects = newProjects
            }
            if newSessions != sessionsByProject {
                sessionsByProject = newSessions
            }
        } catch {
            self.error = "\(error)"
        }
    }

    public func register(
        name: String,
        path: String,
        baseBranch: String,
        wrikeFolder: String?,
        githubOwner: String? = nil,
        githubRepo: String? = nil
    ) async {
        do {
            let project = Project(
                name: name,
                localPath: path,
                defaultBaseBranch: baseBranch,
                wrikeFolderId: wrikeFolder,
                githubOwner: githubOwner?.isEmpty == false ? githubOwner : nil,
                githubRepo: githubRepo?.isEmpty == false ? githubRepo : nil
            )
            try await projectsRepo.upsert(project)
            try await manager.bootstrap(project: project)
            await reload()
        } catch {
            self.error = "\(error)"
        }
    }

    public func remove(projectId: String) async {
        do {
            try await projectsRepo.delete(id: projectId)
            await reload()
        } catch {
            self.error = "\(error)"
        }
    }

    public func sessions(for projectId: String) -> [Session] {
        sessionsByProject[projectId] ?? []
    }

    /// 2 seconds is fast enough that hook-driven status changes feel
    /// instant in the sidebar and slow enough that the SQLite read cost
    /// is irrelevant (the equality guard further skips re-publishes when
    /// nothing changed).
    private static let pollInterval: Duration = .seconds(2)

    private func startPolling() {
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                await self?.reload()
            }
        }
    }
}
