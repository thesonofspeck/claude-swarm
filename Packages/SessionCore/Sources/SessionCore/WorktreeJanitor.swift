import Foundation
import os
import GitKit
import PersistenceKit

private let log = Logger(subsystem: "com.claudeswarm", category: "janitor")

/// Reconciles persisted sessions with the actual on-disk worktrees at app
/// launch. After a crash or unclean exit, the DB can carry .running sessions
/// whose PTY is dead and whose worktree may or may not still exist.
public actor WorktreeJanitor {
    public struct Report: Sendable, Equatable {
        public let cleanedDeadSessions: Int
        public let removedOrphanWorktrees: Int
    }

    /// Read-only snapshot of what the next reconcile would do. Lets the
    /// UI show pending work before the user pulls the trigger.
    public struct Inspection: Sendable, Equatable {
        public struct DeadSession: Sendable, Equatable, Identifiable {
            public let session: Session
            public let project: Project
            public var id: String { session.id }
        }
        public struct OrphanWorktree: Sendable, Equatable, Identifiable {
            public let path: String
            public let branch: String
            public let project: Project
            public var id: String { path }
        }
        public let deadSessions: [DeadSession]
        public let orphanWorktrees: [OrphanWorktree]
        public var isClean: Bool { deadSessions.isEmpty && orphanWorktrees.isEmpty }
    }

    public let projects: ProjectRepository
    public let sessions: SessionRepository
    public let worktrees: WorktreeService

    public init(
        projects: ProjectRepository,
        sessions: SessionRepository,
        worktrees: WorktreeService = WorktreeService()
    ) {
        self.projects = projects
        self.sessions = sessions
        self.worktrees = worktrees
    }

    public func reconcile() async -> Report {
        var deadSessions = 0
        var orphanWorktrees = 0

        let projectList = (try? projects.all()) ?? []
        for project in projectList {
            let repoURL = URL(fileURLWithPath: project.localPath)
            let liveTrees: [Worktree]
            do {
                liveTrees = try await worktrees.list(repo: repoURL)
            } catch {
                log.warning("Janitor: list worktrees failed for \(project.name, privacy: .public): \(String(describing: error), privacy: .public)")
                continue
            }
            let livePaths = Set(liveTrees.map(\.path.standardizedFileURL.path))
            let dbSessions: [Session]
            do {
                dbSessions = try sessions.forProject(project.id)
            } catch {
                log.warning("Janitor: fetch sessions failed for \(project.name, privacy: .public): \(String(describing: error), privacy: .public)")
                continue
            }

            // Sessions whose status says running but whose worktree is gone -> mark finished.
            for session in dbSessions where session.status == .running || session.status == .starting || session.status == .waitingForInput {
                if !livePaths.contains(URL(fileURLWithPath: session.worktreePath).standardizedFileURL.path) {
                    do {
                        try sessions.setStatus(id: session.id, .finished)
                        deadSessions += 1
                    } catch {
                        log.error("Janitor: setStatus failed for session \(session.id, privacy: .public): \(String(describing: error), privacy: .public)")
                    }
                }
            }

            // Worktrees we created (under the swarm worktrees root) that no
            // longer correspond to any DB session -> clean up.
            let knownPaths = Set(dbSessions.map { URL(fileURLWithPath: $0.worktreePath).standardizedFileURL.path })
            for tree in liveTrees {
                let path = tree.path.standardizedFileURL.path
                guard path.contains(AppDirectories.worktreesRoot.path) else { continue }
                if !knownPaths.contains(path) {
                    do {
                        try await worktrees.remove(repo: repoURL, worktreePath: tree.path, force: true)
                        orphanWorktrees += 1
                    } catch {
                        log.warning("Janitor: orphan worktree removal failed at \(tree.path.path, privacy: .public): \(String(describing: error), privacy: .public)")
                    }
                }
            }
        }

        return Report(
            cleanedDeadSessions: deadSessions,
            removedOrphanWorktrees: orphanWorktrees
        )
    }

    /// Read-only counterpart to `reconcile` — used by the Worktree
    /// Janitor sheet so the user sees exactly what's about to change.
    public func inspect() async -> Inspection {
        var dead: [Inspection.DeadSession] = []
        var orphans: [Inspection.OrphanWorktree] = []

        let projectList = (try? projects.all()) ?? []
        for project in projectList {
            let repoURL = URL(fileURLWithPath: project.localPath)
            let liveTrees: [Worktree]
            do { liveTrees = try await worktrees.list(repo: repoURL) }
            catch { continue }
            let livePaths = Set(liveTrees.map(\.path.standardizedFileURL.path))

            let dbSessions: [Session]
            do { dbSessions = try sessions.forProject(project.id) }
            catch { continue }
            let knownPaths = Set(dbSessions.map { URL(fileURLWithPath: $0.worktreePath).standardizedFileURL.path })

            for session in dbSessions
                where (session.status == .running
                       || session.status == .starting
                       || session.status == .waitingForInput)
                    && !livePaths.contains(URL(fileURLWithPath: session.worktreePath).standardizedFileURL.path)
            {
                dead.append(.init(session: session, project: project))
            }

            for tree in liveTrees {
                let path = tree.path.standardizedFileURL.path
                guard path.contains(AppDirectories.worktreesRoot.path) else { continue }
                if !knownPaths.contains(path) {
                    orphans.append(.init(path: path, branch: tree.branch, project: project))
                }
            }
        }
        return Inspection(deadSessions: dead, orphanWorktrees: orphans)
    }

    /// Removes a single orphan worktree by path, using the project as the
    /// repo context. Idempotent — if the path is already gone, returns
    /// without erroring.
    public func removeOrphan(_ orphan: Inspection.OrphanWorktree) async throws {
        let repoURL = URL(fileURLWithPath: orphan.project.localPath)
        let path = URL(fileURLWithPath: orphan.path)
        guard FileManager.default.fileExists(atPath: orphan.path) else { return }
        try await worktrees.remove(repo: repoURL, worktreePath: path, force: true)
    }

    /// Marks a dead session's status as finished without touching its
    /// worktree (which we already verified is gone).
    public func markDead(_ dead: Inspection.DeadSession) throws {
        try sessions.setStatus(id: dead.session.id, .finished)
    }
}
