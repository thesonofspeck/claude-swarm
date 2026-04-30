import Foundation

public enum WrikeTransition: Sendable, Hashable {
    case inProgress
    case inReview
    case done
}

/// Wrike custom-status IDs are workspace-specific. This actor caches the
/// workspace's statuses and resolves a semantic `WrikeTransition` to the
/// best matching custom status by name. Falls back to standard groups
/// (Active, Completed) when no name matches.
public actor WrikeStatusMapper {
    public let client: WrikeClient
    private var cached: [WrikeCustomStatus]?

    public init(client: WrikeClient) {
        self.client = client
    }

    public func resolve(_ transition: WrikeTransition) async -> WrikeCustomStatus? {
        let statuses = await loadStatuses()
        let matchers: [String]
        let group: String
        switch transition {
        case .inProgress:
            matchers = ["in progress", "progress", "doing", "started", "active", "wip"]
            group = "Active"
        case .inReview:
            matchers = ["in review", "review", "ready for review", "qa", "verify"]
            group = "Active"
        case .done:
            matchers = ["done", "completed", "complete", "merged", "shipped", "closed"]
            group = "Completed"
        }
        for matcher in matchers {
            if let hit = statuses.first(where: { $0.name.lowercased().contains(matcher) }) {
                return hit
            }
        }
        return statuses.first { $0.group == group }
    }

    public func transition(taskId: String, to transition: WrikeTransition) async throws -> Bool {
        guard let status = await resolve(transition) else { return false }
        _ = try await client.updateTaskStatus(taskId: taskId, customStatusId: status.id)
        return true
    }

    public func invalidateCache() {
        cached = nil
    }

    private func loadStatuses() async -> [WrikeCustomStatus] {
        if let cached { return cached }
        let fetched = (try? await client.customStatuses()) ?? []
        cached = fetched
        return fetched
    }
}
