import Foundation

/// Categories of workspace state that can need reloading. Using a Set lets
/// the pulse coalesce a burst of events into a single notification with a
/// union of everything that became stale.
public enum WorkspaceInvalidation: Sendable, Hashable, CaseIterable {
    /// Working-tree changes (`git status`).
    case status
    /// Refs and ahead/behind (commit, branch switch, fetch, push).
    case branches
    /// Commit graph (commit, amend, rebase, cherry-pick, revert, reset).
    case history
    /// Stash list.
    case stashes
    /// Tag list.
    case tags
    /// Tracked file tree (used by the Files browser).
    case files
}

/// Single coalesced event source that drives auto-reload across every git
/// surface in the app. It folds three signals into one stream:
///
/// 1. Filesystem changes inside the worktree (FSEvents via `FileWatcher`).
/// 2. Hook events from the agent's `PostToolUse` notifications.
/// 3. Operation completions from `GitOperationCenter`.
///
/// Events arrive at unpredictable rates — saving a file in Claude Code can
/// flood FSEvents with several writes in quick succession — so we buffer
/// invalidations and emit them on a fixed debounce window. Each subscriber
/// gets the full union of categories accumulated during the window.
@MainActor
public final class WorkspacePulse {
    public let debounce: Duration
    private var subscribers: [UUID: AsyncStream<Set<WorkspaceInvalidation>>.Continuation] = [:]
    private var pending: Set<WorkspaceInvalidation> = []
    private var flushTask: Task<Void, Never>?

    public init(debounce: Duration = .milliseconds(150)) {
        self.debounce = debounce
    }

    deinit {
        flushTask?.cancel()
    }

    /// Multicast subscription. Closes automatically when the consuming
    /// task is cancelled.
    public func events() -> AsyncStream<Set<WorkspaceInvalidation>> {
        let id = UUID()
        let (stream, cont) = AsyncStream<Set<WorkspaceInvalidation>>.makeStream()
        subscribers[id] = cont
        cont.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers.removeValue(forKey: id) }
        }
        return stream
    }

    /// Note that one or more categories became stale. The stream fires once
    /// after `debounce` with everything accumulated since the last flush.
    public func ping(_ kinds: Set<WorkspaceInvalidation>) {
        guard !kinds.isEmpty else { return }
        pending.formUnion(kinds)
        scheduleFlush()
    }

    public func ping(_ kind: WorkspaceInvalidation) {
        ping([kind])
    }

    /// Force an immediate flush. Use sparingly — only when a foreground
    /// user action makes the debounce wait visible (e.g. tapping Refresh).
    public func flushNow() {
        flushTask?.cancel()
        flushTask = nil
        emit()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        let interval = self.debounce
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            self?.emit()
        }
    }

    private func emit() {
        guard !pending.isEmpty else { return }
        let snapshot = pending
        pending.removeAll()
        for cont in subscribers.values { cont.yield(snapshot) }
    }
}
