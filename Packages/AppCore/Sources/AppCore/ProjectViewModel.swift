import Foundation
import Observation
import Combine
import GRDB
import PersistenceKit
import SessionCore

@MainActor
@Observable
public final class ProjectListViewModel {
    public private(set) var projects: [Project] = []
    public private(set) var sessionsByProject: [String: [Session]] = [:]
    public var error: String?

    private let database: Database
    private let projectsRepo: ProjectRepository
    private let sessionsRepo: SessionRepository
    private let manager: SessionManager
    private var observationTask: Task<Void, Never>?

    public init(
        database: Database,
        projects: ProjectRepository,
        sessions: SessionRepository,
        manager: SessionManager
    ) {
        self.database = database
        self.projectsRepo = projects
        self.sessionsRepo = sessions
        self.manager = manager
        reload()
        startObserving()
    }

    deinit {
        observationTask?.cancel()
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

    public func register(
        name: String,
        path: String,
        baseBranch: String,
        wrikeFolder: String?,
        githubOwner: String? = nil,
        githubRepo: String? = nil,
        kubeContext: String? = nil,
        kubeNamespace: String? = nil
    ) async {
        do {
            let project = Project(
                name: name,
                localPath: path,
                defaultBaseBranch: baseBranch,
                wrikeFolderId: wrikeFolder,
                githubOwner: githubOwner?.isEmpty == false ? githubOwner : nil,
                githubRepo: githubRepo?.isEmpty == false ? githubRepo : nil,
                kubeContext: kubeContext?.isEmpty == false ? kubeContext : nil,
                kubeNamespace: kubeNamespace?.isEmpty == false ? kubeNamespace : nil
            )
            try projectsRepo.upsert(project)
            try await manager.bootstrap(project: project)
            reload()
        } catch {
            self.error = "\(error)"
        }
    }

    /// Update the kubectl bindings on an existing project. The Deploy
    /// tab's empty state lets the user pick a context without
    /// re-registering the whole project.
    public func updateKubeBinding(projectId: String, context: String?, namespace: String?) {
        do {
            guard var p = try projectsRepo.find(id: projectId) else { return }
            p.kubeContext = (context?.isEmpty == false) ? context : nil
            p.kubeNamespace = (namespace?.isEmpty == false) ? namespace : nil
            try projectsRepo.upsert(p)
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

    /// Watches the `session` and `project` tables via GRDB
    /// `ValueObservation` so updates from hook events / session state
    /// changes drive sidebar refreshes within milliseconds, with no
    /// polling. Replaces the previous 2s timer that scanned both
    /// tables every tick regardless of activity.
    private func startObserving() {
        let pool = database.queue
        let projectsObs = ValueObservation.tracking { db in
            try Project.order(Column("name")).fetchAll(db)
        }
        let sessionsObs = ValueObservation.tracking { db in
            try Session.order(Column("createdAt").desc).fetchAll(db)
        }

        observationTask = Task { @MainActor [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    do {
                        for try await rows in projectsObs.values(in: pool) {
                            self?.projects = rows
                        }
                    } catch {
                        self?.error = "\(error)"
                    }
                }
                group.addTask {
                    do {
                        for try await rows in sessionsObs.values(in: pool) {
                            let grouped = Dictionary(grouping: rows, by: \.projectId)
                            self?.sessionsByProject = grouped
                        }
                    } catch {
                        self?.error = "\(error)"
                    }
                }
            }
        }
    }
}
