import Foundation
import SwiftUI
import PersistenceKit
import WrikeKit
import GitHubKit
import os

/// Aggregator for the Welcome screen. Hydrates instantly from disk
/// (CachedTask + CachedPR), then refreshes from Wrike + `gh` in the
/// background per project on a 5-minute staleness window. Views observe
/// the `@Published` slices and rerender when each rail's data lands.
@MainActor
public final class WelcomeFeed: ObservableObject {

    public struct TaskRow: Identifiable, Equatable, Sendable {
        public let project: Project
        public let task: WrikeTask
        public var id: String { "\(project.id)/\(task.id)" }
    }

    public struct PRRow: Identifiable, Equatable, Sendable {
        public let project: Project
        public let pr: GHPullRequest
        public var id: String { "\(project.id)#\(pr.number)" }
    }

    public struct SessionRow: Identifiable, Equatable, Sendable {
        public let session: Session
        public let project: Project?
        public var id: String { session.id }
    }

    @Published public private(set) var recentSessions: [SessionRow] = []
    @Published public private(set) var tasks: [TaskRow] = []
    @Published public private(set) var prs: [PRRow] = []
    @Published public private(set) var refreshingTasks: Bool = false
    @Published public private(set) var refreshingPRs: Bool = false
    @Published public private(set) var lastRefreshedAt: Date?

    private let projects: ProjectRepository
    private let sessionsRepo: SessionRepository
    private let taskCache: TaskCacheRepository
    private let prCache: PRCacheRepository
    private let wrike: WrikeClient
    private let github: GitHubClient

    /// Per-project staleness window for background refresh.
    public var refreshInterval: TimeInterval = 5 * 60
    private var lastFetchByProject: [String: Date] = [:]

    private static let log = Logger(subsystem: "com.claudeswarm", category: "welcome-feed")

    public init(
        projects: ProjectRepository,
        sessionsRepo: SessionRepository,
        taskCache: TaskCacheRepository,
        prCache: PRCacheRepository,
        wrike: WrikeClient,
        github: GitHubClient
    ) {
        self.projects = projects
        self.sessionsRepo = sessionsRepo
        self.taskCache = taskCache
        self.prCache = prCache
        self.wrike = wrike
        self.github = github
    }

    // MARK: - Hydration + refresh

    /// Paint immediately from the on-disk caches. Cheap, sync-ish — call
    /// from `.task` on first appear so the rails aren't blank during the
    /// network round-trip.
    public func hydrateFromCache() {
        let projectsById = Dictionary(uniqueKeysWithValues: ((try? projects.all()) ?? []).map { ($0.id, $0) })

        let sessions = (try? sessionsRepo.recent(limit: 12)) ?? []
        recentSessions = sessions.map { SessionRow(session: $0, project: projectsById[$0.projectId]) }

        let cachedTasks = (try? taskCache.all()) ?? []
        tasks = cachedTasks.compactMap { ct in
            guard let project = projectsById[ct.projectId] else { return nil }
            let task = WrikeTask(
                id: ct.id,
                title: ct.title,
                descriptionText: ct.descriptionText,
                status: ct.status,
                permalink: ct.permalink,
                importance: nil,
                updatedDate: ct.fetchedAt
            )
            return TaskRow(project: project, task: task)
        }

        let cachedPRs = (try? prCache.all()) ?? []
        prs = cachedPRs.compactMap { cp in
            guard let project = projectsById.values.first(where: {
                ($0.githubOwner ?? "") == cp.owner && ($0.githubRepo ?? "") == cp.repo
            }) else { return nil }
            let pr = GHPullRequest(
                number: cp.number, title: cp.title, body: nil,
                state: GHPRState(rawValue: cp.state) ?? .open,
                url: cp.url, isDraft: nil, merged: cp.state == "merged",
                headRefName: nil, baseRefName: nil, headRefOid: cp.headSha,
                author: nil
            )
            return PRRow(project: project, pr: pr)
        }
    }

    /// Refresh every project whose cache is older than `refreshInterval`.
    /// Per-project work runs in parallel; one slow project does not block
    /// the others.
    public func refreshIfStale() async {
        let allProjects = (try? projects.all()) ?? []
        let now = Date()
        let stale = allProjects.filter { project in
            guard let last = lastFetchByProject[project.id] else { return true }
            return now.timeIntervalSince(last) > refreshInterval
        }
        await refresh(projects: stale)
    }

    public func refreshAll() async {
        let allProjects = (try? projects.all()) ?? []
        await refresh(projects: allProjects)
    }

    private func refresh(projects targets: [Project]) async {
        guard !targets.isEmpty else { return }
        refreshingTasks = true
        refreshingPRs = true
        defer {
            refreshingTasks = false
            refreshingPRs = false
            lastRefreshedAt = Date()
        }

        await withTaskGroup(of: Void.self) { group in
            for project in targets {
                if let folder = project.wrikeFolderId, !folder.isEmpty {
                    group.addTask { [weak self] in
                        await self?.refreshTasks(project: project, folder: folder)
                    }
                }
                if let owner = project.githubOwner, let repo = project.githubRepo,
                   !owner.isEmpty, !repo.isEmpty {
                    group.addTask { [weak self] in
                        await self?.refreshPRs(project: project, owner: owner, repo: repo)
                    }
                }
            }
        }
        for project in targets { lastFetchByProject[project.id] = Date() }
        // Rebuild from the freshly-updated caches.
        hydrateFromCache()
    }

    private func refreshTasks(project: Project, folder: String) async {
        do {
            let fetched = try await wrike.tasks(in: folder)
            let now = Date()
            let cached = fetched.map { task in
                CachedTask(
                    id: task.id,
                    projectId: project.id,
                    title: task.title,
                    descriptionText: task.descriptionPlainText,
                    status: task.status,
                    permalink: task.permalink,
                    fetchedAt: now
                )
            }
            try taskCache.upsert(cached, for: project.id)
        } catch {
            Self.log.debug("Wrike refresh failed for \(project.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func refreshPRs(project: Project, owner: String, repo: String) async {
        do {
            let fetched = try await github.listPullRequests(owner: owner, repo: repo, state: "open", limit: 30)
            let now = Date()
            let cached = fetched.map { pr in
                CachedPR(
                    id: "\(owner)/\(repo)#\(pr.number)",
                    sessionId: nil,
                    owner: owner,
                    repo: repo,
                    number: pr.number,
                    title: pr.title,
                    state: pr.state.rawValue.lowercased(),
                    url: pr.url,
                    headSha: pr.headRefOid ?? "",
                    checksPassing: 0,
                    checksTotal: 0,
                    reviewCount: 0,
                    fetchedAt: now
                )
            }
            try prCache.upsert(cached, owner: owner, repo: repo)
        } catch {
            Self.log.debug("PR refresh failed for \(owner, privacy: .public)/\(repo, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Filtering helpers

    public func tasks(matching query: String) -> [TaskRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return tasks }
        return tasks.filter {
            $0.task.title.lowercased().contains(needle)
                || $0.task.descriptionPlainText.lowercased().contains(needle)
                || $0.project.name.lowercased().contains(needle)
        }
    }

    public func prs(matching query: String) -> [PRRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return prs }
        return prs.filter {
            $0.pr.title.lowercased().contains(needle)
                || $0.project.name.lowercased().contains(needle)
        }
    }
}
