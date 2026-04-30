import Foundation
import GitKit
import PersistenceKit

public actor SessionManager {
    public struct StartResult: Sendable {
        public let session: Session
        public let spec: SessionSpec
    }

    public let sessions: SessionRepository
    public let projects: ProjectRepository
    public let worktrees: WorktreeService
    public let transcriptsRoot: URL
    public let worktreesRoot: URL

    public init(
        sessions: SessionRepository,
        projects: ProjectRepository,
        worktrees: WorktreeService = WorktreeService(),
        transcriptsRoot: URL = AppDirectories.transcriptsDir,
        worktreesRoot: URL = AppDirectories.worktreesRoot
    ) {
        self.sessions = sessions
        self.projects = projects
        self.worktrees = worktrees
        self.transcriptsRoot = transcriptsRoot
        self.worktreesRoot = worktreesRoot
    }

    public func start(
        for project: Project,
        taskId: String?,
        taskTitle: String,
        initialPrompt: String?,
        claudeExecutable: String = "/usr/local/bin/claude"
    ) async throws -> StartResult {
        let sessionId = UUID().uuidString
        let branch = BranchNamer.branch(taskId: taskId, title: taskTitle)
        let repoSlug = sanitize(project.name)
        let worktreePath = worktreesRoot
            .appendingPathComponent(repoSlug, isDirectory: true)
            .appendingPathComponent("\(taskId ?? sessionId)-\(BranchNamer.slug(taskTitle))", isDirectory: true)

        let repoURL = URL(fileURLWithPath: project.localPath)
        let tree = try await worktrees.add(
            repo: repoURL,
            worktreePath: worktreePath,
            branch: branch,
            baseBranch: project.defaultBaseBranch
        )

        let transcriptURL = transcriptsRoot.appendingPathComponent("\(sessionId).log")

        var session = Session(
            id: sessionId,
            projectId: project.id,
            taskId: taskId,
            taskTitle: taskTitle,
            branch: tree.branch,
            worktreePath: tree.path.path,
            status: .starting,
            transcriptPath: transcriptURL.path
        )
        try sessions.upsert(session)

        let env = [
            "CLAUDE_SWARM_SESSION_ID": sessionId,
            "CLAUDE_SWARM_PROJECT_ID": project.id,
            "CLAUDE_SWARM_HOOK_SOCKET": AppDirectories.hooksSocket.path
        ]

        let spec = SessionSpec(
            id: sessionId,
            projectId: project.id,
            projectName: project.name,
            repoURL: repoURL,
            worktreeURL: tree.path,
            branch: tree.branch,
            baseBranch: project.defaultBaseBranch,
            taskId: taskId,
            taskTitle: taskTitle,
            initialPrompt: initialPrompt,
            claudeExecutable: claudeExecutable,
            environment: env,
            transcriptURL: transcriptURL
        )

        session.status = .running
        try sessions.upsert(session)
        return StartResult(session: session, spec: spec)
    }

    public func mark(sessionId: String, status: SessionStatus) throws {
        try sessions.setStatus(id: sessionId, status)
    }

    public func close(sessionId: String, deleteWorktree: Bool) async throws {
        guard let session = try sessions.find(id: sessionId) else { return }
        if deleteWorktree {
            if let project = try projects.find(id: session.projectId) {
                try await worktrees.remove(
                    repo: URL(fileURLWithPath: project.localPath),
                    worktreePath: URL(fileURLWithPath: session.worktreePath),
                    force: true
                )
            }
        }
        try sessions.setStatus(id: sessionId, .archived)
    }

    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}
