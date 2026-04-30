import Foundation
import PersistenceKit

@MainActor
public final class ProjectListViewModel: ObservableObject {
    @Published public var projects: [Project] = []
    @Published public var sessionsByProject: [String: [Session]] = [:]
    @Published public var error: String?

    private let env: AppEnvironment

    public init(env: AppEnvironment) {
        self.env = env
        reload()
    }

    public func reload() {
        do {
            self.projects = try env.projects.all()
            for project in projects {
                sessionsByProject[project.id] = try env.sessionsRepo.forProject(project.id)
            }
        } catch {
            self.error = "\(error)"
        }
    }

    public func register(name: String, path: String, baseBranch: String, wrikeFolder: String?) {
        do {
            let project = Project(
                name: name,
                localPath: path,
                defaultBaseBranch: baseBranch,
                wrikeFolderId: wrikeFolder
            )
            try env.projects.upsert(project)
            reload()
        } catch {
            self.error = "\(error)"
        }
    }

    public func remove(projectId: String) {
        do {
            try env.projects.delete(id: projectId)
            reload()
        } catch {
            self.error = "\(error)"
        }
    }
}
