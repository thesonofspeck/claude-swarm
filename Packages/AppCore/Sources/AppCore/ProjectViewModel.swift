import Foundation
import Combine
import PersistenceKit
import SessionCore

@MainActor
public final class ProjectListViewModel: ObservableObject {
    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var sessionsByProject: [String: [Session]] = [:]
    @Published public var error: String?

    private let projectsRepo: ProjectRepository
    private let sessionsRepo: SessionRepository
    private let manager: SessionManager
    private var refreshTask: Task<Void, Never>?

    public init(
        projects: ProjectRepository,
        sessions: SessionRepository,
        manager: SessionManager
    ) {
        self.projectsRepo = projects
        self.sessionsRepo = sessions
        self.manager = manager
        reload()
        startPolling()
    }

    deinit {
        refreshTask?.cancel()
    }

    public func reload() {
        do {
            let newProjects = try projectsRepo.all()
            let newSessions = try sessionsRepo.allByProject()
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

    public func register(name: String, path: String, baseBranch: String, wrikeFolder: String?) async {
        do {
            let project = Project(
                name: name,
                localPath: path,
                defaultBaseBranch: baseBranch,
                wrikeFolderId: wrikeFolder
            )
            try projectsRepo.upsert(project)
            try await manager.bootstrap(project: project)
            reload()
        } catch {
            self.error = "\(error)"
        }
    }

    public func remove(projectId: String) {
        do {
            try projectsRepo.delete(id: projectId)
            reload()
        } catch {
            self.error = "\(error)"
        }
    }

    public func sessions(for projectId: String) -> [Session] {
        sessionsByProject[projectId] ?? []
    }

    private func startPolling() {
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                self?.reload()
            }
        }
    }
}
