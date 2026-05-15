import Foundation
import GitKit
import PersistenceKit
import AgentBootstrap

public actor SessionManager {
    public struct StartResult: Sendable {
        public let session: Session
        public let spec: SessionSpec
    }

    public enum SessionError: Error, LocalizedError {
        case projectMissing
        case worktreeMissing(String)

        public var errorDescription: String? {
            switch self {
            case .projectMissing:
                return "The project for this session no longer exists."
            case .worktreeMissing(let path):
                return "The worktree is gone (\(path)) — nothing to resume."
            }
        }
    }

    public let sessions: SessionRepository
    public let projects: ProjectRepository
    public let worktrees: WorktreeService
    public let installer: Installer
    public let transcriptsRoot: URL
    public let worktreesRoot: URL
    public let notifyScriptPath: String
    public let policyScriptPath: String

    public init(
        sessions: SessionRepository,
        projects: ProjectRepository,
        worktrees: WorktreeService = WorktreeService(),
        installer: Installer = Installer(),
        transcriptsRoot: URL = AppDirectories.transcriptsDir,
        worktreesRoot: URL = AppDirectories.worktreesRoot,
        notifyScriptPath: String,
        policyScriptPath: String
    ) {
        self.sessions = sessions
        self.projects = projects
        self.worktrees = worktrees
        self.installer = installer
        self.transcriptsRoot = transcriptsRoot
        self.worktreesRoot = worktreesRoot
        self.notifyScriptPath = notifyScriptPath
        self.policyScriptPath = policyScriptPath
    }

    /// Bootstraps a project on registration: installs the 6 default subagents,
    /// hooks, the memory skill, and the empty `.mcp.json` into the project root.
    public func bootstrap(project: Project) throws {
        let plan = BootstrapPlan(
            projectURL: URL(fileURLWithPath: project.localPath),
            projectId: project.id,
            notifyScriptPath: notifyScriptPath,
            policyScriptPath: policyScriptPath
        )
        try installer.install(plan, overwrite: false)
    }

    public func start(
        for project: Project,
        taskId: String?,
        taskTitle: String,
        initialPrompt: String?,
        claudeExecutable: String = "/usr/local/bin/claude"
    ) async throws -> StartResult {
        try bootstrap(project: project)

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

        let promptParts: [String] = [
            "You are running as the team-lead agent for project \"\(project.name)\".",
            taskTitle.isEmpty ? nil : "Task: \(taskTitle)",
            taskId.flatMap { id in id.isEmpty ? nil : "Wrike: \(id)" },
            initialPrompt
        ].compactMap { $0 }

        let composedPrompt = promptParts.joined(separator: "\n\n")

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
            initialPrompt: composedPrompt.isEmpty ? nil : composedPrompt,
            claudeExecutable: claudeExecutable,
            // Pin the Claude Code conversation id to our session id so
            // the session row maps 1:1 to a resumable conversation.
            claudeArguments: ["--session-id", sessionId],
            environment: env,
            transcriptURL: transcriptURL
        )

        session.status = .running
        try sessions.upsert(session)
        return StartResult(session: session, spec: spec)
    }

    /// Build a spec that resumes an existing session's Claude Code
    /// conversation (`claude --resume <id>`) instead of starting a fresh
    /// one. The session id doubles as the conversation id, so resuming
    /// reattaches to the exact transcript the user left.
    public func resumeSpec(
        for session: Session,
        claudeExecutable: String = "/usr/local/bin/claude"
    ) throws -> SessionSpec {
        guard let project = try projects.find(id: session.projectId) else {
            throw SessionError.projectMissing
        }
        let worktreeURL = URL(fileURLWithPath: session.worktreePath)
        guard FileManager.default.fileExists(atPath: worktreeURL.path) else {
            throw SessionError.worktreeMissing(session.worktreePath)
        }
        let env = [
            "CLAUDE_SWARM_SESSION_ID": session.id,
            "CLAUDE_SWARM_PROJECT_ID": project.id,
            "CLAUDE_SWARM_HOOK_SOCKET": AppDirectories.hooksSocket.path
        ]
        return SessionSpec(
            id: session.id,
            projectId: project.id,
            projectName: project.name,
            repoURL: URL(fileURLWithPath: project.localPath),
            worktreeURL: worktreeURL,
            branch: session.branch,
            baseBranch: project.defaultBaseBranch,
            taskId: session.taskId,
            taskTitle: session.taskTitle,
            initialPrompt: nil,
            claudeExecutable: claudeExecutable,
            claudeArguments: ["--resume", session.id],
            environment: env,
            transcriptURL: URL(fileURLWithPath: session.transcriptPath)
        )
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
