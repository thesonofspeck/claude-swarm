import Foundation

/// Local-side filter for a flat list of `WrikeTask`s. Wrike's REST API
/// does support `?title=` and a few other server-side filters, but the
/// folder-tasks call returns a small enough page to filter in-memory and
/// keep the UI responsive (no network round-trip per keystroke).
public struct WrikeFilter: Sendable, Equatable {
    public var query: String
    public var statuses: Set<String>            // empty = all
    public var importances: Set<String>         // empty = all
    public var hideCompleted: Bool

    public init(
        query: String = "",
        statuses: Set<String> = [],
        importances: Set<String> = [],
        hideCompleted: Bool = false
    ) {
        self.query = query
        self.statuses = statuses
        self.importances = importances
        self.hideCompleted = hideCompleted
    }

    public var isEmpty: Bool {
        query.isEmpty && statuses.isEmpty && importances.isEmpty && !hideCompleted
    }

    public func apply(to tasks: [WrikeTask]) -> [WrikeTask] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tasks.filter { task in
            if hideCompleted, isCompleted(task.status) { return false }
            if !statuses.isEmpty, !statuses.contains(task.status) { return false }
            if !importances.isEmpty, let imp = task.importance, !importances.contains(imp) { return false }
            if !needle.isEmpty {
                let haystack = (task.title + " " + task.descriptionPlainText + " " + task.id).lowercased()
                if !haystack.contains(needle) { return false }
            }
            return true
        }
    }

    private func isCompleted(_ status: String) -> Bool {
        // Wrike standard statuses that count as "done" in the default workflow.
        ["Completed", "Cancelled"].contains(status)
    }
}
