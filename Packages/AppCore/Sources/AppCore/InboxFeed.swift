import Foundation
import Observation
import SwiftUI
import PersistenceKit
import GitHubKit
import os

/// Unified daily-pulse feed: hook events (sessions waiting for input,
/// stops, post-tool use), unresolved PR review threads across every
/// project, and CI failures on those PRs. Designed to answer "what
/// does the user need to do next?".
///
/// Pattern mirrors WelcomeFeed: hydrate from local stores immediately,
/// refresh in the background per project on a staleness window. Items
/// aren't persisted as a separate table — review threads + CI runs are
/// derived from `gh` per refresh and merged with the activity log.
@MainActor
@Observable
public final class InboxFeed {

    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case needsInput
        case stop
        case postToolUse
        case prReviewComment
        case ciFailure
        case other

        public var label: String {
            switch self {
            case .needsInput: return "Needs input"
            case .stop: return "Idle"
            case .postToolUse: return "Tool use"
            case .prReviewComment: return "Review comment"
            case .ciFailure: return "CI failed"
            case .other: return "Activity"
            }
        }
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public let id: String
        public let kind: Kind
        public let title: String
        public let detail: String?
        public let timestamp: Date
        /// Optional cross-references for click-to-jump.
        public let projectId: String?
        public let sessionId: String?
        public let prURL: String?
        public let unread: Bool
    }

    public private(set) var items: [Item] = []
    public private(set) var refreshing: Bool = false
    public private(set) var lastRefreshedAt: Date?

    public var refreshInterval: TimeInterval = 5 * 60
    private var lastFetchByProject: [String: Date] = [:]
    private var derivedReviewItems: [Item] = []
    private var derivedCIItems: [Item] = []

    private let projects: ProjectRepository
    private let sessionsRepo: SessionRepository
    private let activity: ActivityLog
    private let github: GitHubClient

    private static let log = Logger(subsystem: "com.claudeswarm", category: "inbox")

    public init(
        projects: ProjectRepository,
        sessionsRepo: SessionRepository,
        activity: ActivityLog,
        github: GitHubClient
    ) {
        self.projects = projects
        self.sessionsRepo = sessionsRepo
        self.activity = activity
        self.github = github
    }

    // MARK: - Hydration

    public func hydrate() {
        let activityItems = (try? activity.recent(limit: 100))?.map { ev -> Item in
            let kind: Kind = {
                switch ev.kind {
                case "Notification": return .needsInput
                case "Stop": return .stop
                case "PostToolUse": return .postToolUse
                default: return .other
                }
            }()
            return Item(
                id: "activity:\(ev.id)",
                kind: kind,
                title: titleForActivity(kind: kind, sessionId: ev.sessionId),
                detail: ev.message,
                timestamp: ev.timestamp,
                projectId: ev.projectId,
                sessionId: ev.sessionId,
                prURL: nil,
                unread: kind == .needsInput
            )
        } ?? []
        rebuild(activityItems: activityItems)
    }

    public func refreshIfStale() async {
        let allProjects = (try? projects.all()) ?? []
        let now = Date()
        let stale = allProjects.filter { p in
            guard let last = lastFetchByProject[p.id] else { return true }
            return now.timeIntervalSince(last) > refreshInterval
        }
        await refresh(projects: stale)
    }

    public func refreshAll() async {
        let allProjects = (try? projects.all()) ?? []
        await refresh(projects: allProjects)
    }

    private func refresh(projects targets: [Project]) async {
        guard !targets.isEmpty else {
            hydrate()
            return
        }
        refreshing = true
        defer {
            refreshing = false
            lastRefreshedAt = Date()
        }

        var collectedReview: [Item] = []
        var collectedCI: [Item] = []

        await withTaskGroup(of: ([Item], [Item]).self) { group in
            for project in targets {
                guard let owner = project.githubOwner, let repo = project.githubRepo,
                      !owner.isEmpty, !repo.isEmpty else { continue }
                let github = self.github
                group.addTask {
                    let prs = (try? await github.listPullRequests(owner: owner, repo: repo, state: "open", limit: 30)) ?? []
                    var rv: [Item] = []
                    var ci: [Item] = []
                    for pr in prs {
                        // Review threads
                        let threads = (try? await github.reviewThreads(owner: owner, repo: repo, number: pr.number)) ?? []
                        for thread in threads where !thread.isResolved {
                            let title = "\(project.name) #\(pr.number) — open review thread"
                            rv.append(Item(
                                id: "thread:\(owner)/\(repo)#\(pr.number):\(thread.id)",
                                kind: .prReviewComment,
                                title: title,
                                detail: pr.title,
                                timestamp: Date(),
                                projectId: project.id,
                                sessionId: nil,
                                prURL: pr.url,
                                unread: false
                            ))
                        }
                        // CI failures
                        if let runs = try? await github.workflowRuns(owner: owner, repo: repo, limit: 6) {
                            for run in runs where run.conclusion?.lowercased() == "failure" {
                                ci.append(Item(
                                    id: "run:\(owner)/\(repo):\(run.id)",
                                    kind: .ciFailure,
                                    title: "\(project.name) — \(run.displayTitle ?? "CI run") failed",
                                    detail: run.url,
                                    timestamp: run.createdAt ?? Date(),
                                    projectId: project.id,
                                    sessionId: nil,
                                    prURL: run.url,
                                    unread: false
                                ))
                            }
                        }
                    }
                    return (rv, ci)
                }
            }
            for await (rv, ci) in group {
                collectedReview.append(contentsOf: rv)
                collectedCI.append(contentsOf: ci)
            }
        }

        derivedReviewItems = collectedReview
        derivedCIItems = collectedCI
        for project in targets { lastFetchByProject[project.id] = Date() }
        hydrate()
    }

    // MARK: - Filtering

    public func filtered(_ kinds: Set<Kind>) -> [Item] {
        guard !kinds.isEmpty else { return items }
        return items.filter { kinds.contains($0.kind) }
    }

    // MARK: - Internals

    private func titleForActivity(kind: Kind, sessionId: String?) -> String {
        let suffix: String = {
            guard let sessionId,
                  let session = try? sessionsRepo.find(id: sessionId)
            else { return "" }
            return " — " + (session.taskTitle ?? session.branch)
        }()
        switch kind {
        case .needsInput: return "Session needs input" + suffix
        case .stop: return "Session idle" + suffix
        case .postToolUse: return "Tool use" + suffix
        case .other: return "Activity" + suffix
        case .prReviewComment, .ciFailure: return "PR activity" + suffix
        }
    }

    private func rebuild(activityItems: [Item]) {
        let combined = activityItems + derivedReviewItems + derivedCIItems
        items = combined.sorted { $0.timestamp > $1.timestamp }
    }
}
