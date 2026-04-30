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
    private var refreshTimer: Timer?

    public init(
        projects: ProjectRepository,
        sessions: SessionRepository,
        manager: SessionManager
    ) {
        self.projectsRepo = projects
        self.sessionsRepo = sessions
        self.manager = manager
        reload()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    public func reload() {
        do {
            self.projects = try projectsRepo.all()
            var map: [String: [Session]] = [:]
            for project in projects {
                map[project.id] = try sessionsRepo.forProject(project.id)
            }
            self.sessionsByProject = map
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
}
