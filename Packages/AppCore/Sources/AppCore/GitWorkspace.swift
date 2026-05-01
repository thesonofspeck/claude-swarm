import Foundation
import Observation
import SwiftUI
import GitKit
import os

/// View-model for a single working tree's full git surface. Owns the
/// services so views don't have to wire them up, holds the live status,
/// and routes every mutation through `GitOperationCenter` so the toolbar
/// has one progress/error stream to render.
@MainActor
@Observable
public final class GitWorkspace {
    public let repo: URL
    public let center: GitOperationCenter
    public let status: StatusService
    public let branches: BranchService
    public let sync: SyncService
    public let commits: CommitService
    public let stash: StashService
    public let tags: TagService
    public let merge: MergeService
    public let history: HistoryService
    public let diff: DiffService

    /// Single coalesced invalidation source. Tabs subscribe to this and
    /// reload the slice of state they care about — instead of each tab
    /// running its own FileWatcher and re-fetching everything.
    public let pulse: WorkspacePulse

    public private(set) var changes: [WorkingChange] = []
    public private(set) var branchList: [BranchRef] = []
    public private(set) var stashes: [StashEntry] = []
    public private(set) var tagList: [TagRef] = []
    public private(set) var remotes: [GitRemote] = []
    public private(set) var currentBranch: String?
    public private(set) var ahead: Int = 0
    public private(set) var behind: Int = 0
    public private(set) var repoState: MergeService.RepoState = .clean
    public private(set) var lastError: String?
    public private(set) var busy: Bool = false

    /// Single rolling marker so the toolbar can show "Pushing…", "Done",
    /// "Failed: …" without each call site wiring its own view state.
    public private(set) var statusLine: String?

    @ObservationIgnored
    private var eventTask: Task<Void, Never>?
    @ObservationIgnored
    private var pulseTask: Task<Void, Never>?
    @ObservationIgnored
    private var fileWatcher: FileWatcher?

    private static let signpostLog = OSLog(subsystem: "com.claudeswarm", category: .pointsOfInterest)

    public init(repo: URL, runner: GitRunner = GitRunner()) {
        self.repo = repo
        self.center = GitOperationCenter(runner: runner)
        self.status = StatusService(runner: runner)
        self.branches = BranchService(runner: runner)
        self.sync = SyncService(runner: runner)
        self.commits = CommitService(runner: runner)
        self.stash = StashService(runner: runner)
        self.tags = TagService(runner: runner)
        self.merge = MergeService(runner: runner)
        self.history = HistoryService(runner: runner)
        self.diff = DiffService(runner: runner)
        self.pulse = WorkspacePulse()
        startListening()
        startWatchingFiles()
        startConsumingPulse()
    }

    deinit {
        eventTask?.cancel()
        pulseTask?.cancel()
        fileWatcher?.stop()
    }

    private func startListening() {
        let center = self.center
        eventTask = Task { [weak self] in
            for await event in await center.events() {
                await MainActor.run { self?.consume(event) }
            }
        }
    }

    private func startWatchingFiles() {
        let watcher = FileWatcher(url: repo, debounce: 0.15) { [weak self] in
            Task { @MainActor [weak self] in
                // FSEvents on the worktree root means file content changed;
                // status + history could move; branches usually don't.
                self?.pulse.ping([.status, .files, .history])
            }
        }
        watcher.start()
        fileWatcher = watcher
    }

    private func startConsumingPulse() {
        pulseTask = Task { @MainActor [weak self] in
            guard let stream = self?.pulse.events() else { return }
            for await invalidations in stream {
                await self?.handleInvalidation(invalidations)
            }
        }
    }

    private func handleInvalidation(_ kinds: Set<WorkspaceInvalidation>) async {
        // The workspace itself only owns the observed slices; views that
        // care about `.files` or `.history` subscribe directly to the pulse
        // to reload their own data. We just refresh what we hold.
        if kinds.contains(.status) { await reloadStatus() }
        if kinds.contains(.branches) { await reloadBranches() }
        if kinds.contains(.stashes) { await reloadStashes() }
        if kinds.contains(.tags) { await reloadTags() }
    }

    /// Allow callers (AppEnvironment hook handler, tabs that want to force
    /// a reload of e.g. files) to push invalidations into the pulse.
    public func invalidate(_ kinds: Set<WorkspaceInvalidation>) {
        pulse.ping(kinds)
    }

    /// Map a completed git operation into the categories it could possibly
    /// have invalidated, then push them onto the pulse so subscribers
    /// reload exactly the slices that matter.
    private func invalidations(after kind: GitOperationKind) -> Set<WorkspaceInvalidation> {
        switch kind {
        case .stage, .unstage, .discard, .status:
            return [.status]
        case .commit, .amend:
            return [.status, .branches, .history]
        case .fetch:
            return [.branches]
        case .pull, .push, .merge, .rebase, .cherryPick, .revert,
             .mergeContinue, .rebaseContinue, .mergeAbort, .rebaseAbort:
            return [.status, .branches, .history]
        case .branchCreate, .branchSwitch, .branchDelete, .branchRename, .setUpstream:
            return [.branches, .status, .history]
        case .stashSave, .stashApply, .stashPop, .stashDrop:
            return [.status, .stashes]
        case .tagCreate, .tagDelete, .tagPush:
            return [.tags]
        }
    }

    private func consume(_ event: GitOperationEvent) {
        switch event.phase {
        case .started:
            busy = true
            statusLine = "\(event.kind.label)…"
            lastError = nil
        case .succeeded:
            busy = false
            statusLine = "\(event.kind.label) done"
            // Push the categories this op touched onto the pulse so every
            // tab reloads the right slice without polling.
            pulse.ping(invalidations(after: event.kind))
        case .failed(let msg):
            busy = false
            statusLine = "\(event.kind.label) failed"
            lastError = msg
        }
    }

    // MARK: - Loading

    /// Refreshes everything that drives a complete view of the repo. Cheap
    /// enough (a few hundred ms on a typical repo) to call on tab open and
    /// after any mutation. Individual sections also have their own
    /// reload helpers if a single mutation only invalidates part of state.
    public func reloadAll() async {
        let signpost = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "reloadAll", signpostID: signpost)
        defer { os_signpost(.end, log: Self.signpostLog, name: "reloadAll", signpostID: signpost) }
        async let s: Void = reloadStatus()
        async let b: Void = reloadBranches()
        async let st: Void = reloadStashes()
        async let t: Void = reloadTags()
        async let r: Void = reloadRemotes()
        _ = await (s, b, st, t, r)
        repoState = merge.currentState(in: repo)
    }

    public func reloadStatus() async {
        let signpost = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "reloadStatus", signpostID: signpost)
        defer { os_signpost(.end, log: Self.signpostLog, name: "reloadStatus", signpostID: signpost) }
        do {
            let result = try await center.run(.status) { runner in
                try await StatusService(runner: runner).status(in: repo)
            }
            changes = result
        } catch {
            // Status failures are non-fatal for the UI; surface but keep
            // existing data so the view doesn't blank out.
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    // MARK: - Per-file diff

    /// Fetches just the diff for a single path. Far cheaper than re-running
    /// `git diff` for the whole worktree on every selection change — when
    /// the agent is editing one file, only that file's diff needs to refresh.
    public func diffForFile(_ path: String, staged: Bool) async -> [DiffFile] {
        let signpost = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "diffForFile", signpostID: signpost,
                    "%{public}s", path)
        defer { os_signpost(.end, log: Self.signpostLog, name: "diffForFile", signpostID: signpost) }
        do {
            if staged {
                return try await diff.stagedDiff(in: repo, path: path)
            } else {
                return try await diff.workingTreeDiff(in: repo, path: path)
            }
        } catch {
            return []
        }
    }

    public func reloadBranches() async {
        let signpost = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "reloadBranches", signpostID: signpost)
        defer { os_signpost(.end, log: Self.signpostLog, name: "reloadBranches", signpostID: signpost) }
        do {
            branchList = try await branches.list(in: repo)
            currentBranch = try await branches.current(in: repo)
            if let cur = currentBranch,
               let row = branchList.first(where: { !$0.isRemote && $0.name == cur }) {
                ahead = row.ahead
                behind = row.behind
            } else {
                ahead = 0
                behind = 0
            }
        } catch {
            lastError = "\(error)"
        }
    }

    public func reloadStashes() async {
        stashes = (try? await stash.list(in: repo)) ?? []
    }

    public func reloadTags() async {
        tagList = (try? await tags.list(in: repo)) ?? []
    }

    public func reloadRemotes() async {
        remotes = (try? await sync.remotes(in: repo)) ?? []
    }

    // MARK: - Mutations

    public func stagePaths(_ paths: [String]) async {
        await wrap(.stage) { try await self.status.stage(paths, in: self.repo) }
        await reloadStatus()
    }

    public func unstagePaths(_ paths: [String]) async {
        await wrap(.unstage) { try await self.status.unstage(paths, in: self.repo) }
        await reloadStatus()
    }

    public func discardPaths(_ paths: [String]) async {
        await wrap(.discard) { try await self.status.discardWorktree(paths, in: self.repo) }
        await reloadStatus()
    }

    public func commit(message: String, amend: Bool = false, signOff: Bool = false) async -> Bool {
        let kind: GitOperationKind = amend ? .amend : .commit
        let ok = await wrap(kind) {
            _ = try await self.commits.commit(message: message, amend: amend, signOff: signOff, in: self.repo)
        }
        if ok { await reloadStatus() }
        return ok
    }

    public func fetch() async { await wrap(.fetch) { try await self.sync.fetchAll(in: self.repo) }; await reloadBranches() }
    public func pull(strategy: SyncService.PullStrategy = .ffOnly) async {
        await wrap(.pull) { try await self.sync.pull(strategy: strategy, in: self.repo) }
        await reloadAll()
    }
    public func push(setUpstream: Bool = false, safety: SyncService.PushSafety = .standard) async {
        await wrap(.push) { try await self.sync.push(setUpstream: setUpstream, safety: safety, in: self.repo) }
        await reloadBranches()
    }

    public func switchBranch(_ name: String, create: Bool = false) async {
        await wrap(.branchSwitch) {
            try await self.branches.switchTo(name, create: create, in: self.repo)
        }
        await reloadAll()
    }

    public func createBranch(_ name: String, from base: String? = nil, switchAfter: Bool = true) async {
        await wrap(.branchCreate) {
            try await self.branches.create(name, from: base, in: self.repo)
            if switchAfter {
                try await self.branches.switchTo(name, in: self.repo)
            }
        }
        await reloadAll()
    }

    public func deleteBranch(_ name: String, force: Bool = false) async {
        await wrap(.branchDelete) {
            try await self.branches.delete(name, force: force, in: self.repo)
        }
        await reloadBranches()
    }

    public func renameBranch(from old: String, to new: String) async {
        await wrap(.branchRename) {
            try await self.branches.rename(from: old, to: new, in: self.repo)
        }
        await reloadBranches()
    }

    public func setUpstream(_ upstream: String, for branch: String) async {
        await wrap(.setUpstream) {
            try await self.branches.setUpstream(branch: branch, upstream: upstream, in: self.repo)
        }
        await reloadBranches()
    }

    // Stash
    public func saveStash(message: String? = nil, includeUntracked: Bool = true) async {
        await wrap(.stashSave) {
            try await self.stash.save(message: message, includeUntracked: includeUntracked, in: self.repo)
        }
        await reloadAll()
    }
    public func popStash(_ index: Int) async { await wrap(.stashPop) { try await self.stash.pop(index: index, in: self.repo) }; await reloadAll() }
    public func applyStash(_ index: Int) async { await wrap(.stashApply) { try await self.stash.apply(index: index, in: self.repo) }; await reloadAll() }
    public func dropStash(_ index: Int) async { await wrap(.stashDrop) { try await self.stash.drop(index: index, in: self.repo) }; await reloadStashes() }

    // Tags
    public func createTag(_ name: String, message: String? = nil, sha: String? = nil) async {
        await wrap(.tagCreate) { try await self.tags.create(name, sha: sha, message: message, in: self.repo) }
        await reloadTags()
    }
    public func deleteTag(_ name: String) async {
        await wrap(.tagDelete) { try await self.tags.delete(name, in: self.repo) }
        await reloadTags()
    }
    public func pushTag(_ name: String) async {
        await wrap(.tagPush) { try await self.tags.push(name, in: self.repo) }
    }

    // Merge / rebase / cherry-pick / revert
    public func mergeBranch(_ branch: String, ff: MergeService.FastForward = .allow) async {
        await wrap(.merge) { try await self.merge.merge(branch, ff: ff, in: self.repo) }
        await reloadAll()
    }
    public func rebaseOnto(_ branch: String) async {
        await wrap(.rebase) { try await self.merge.rebase(onto: branch, in: self.repo) }
        await reloadAll()
    }
    public func abortMerge() async { await wrap(.mergeAbort) { try await self.merge.abortMerge(in: self.repo) }; await reloadAll() }
    public func abortRebase() async { await wrap(.rebaseAbort) { try await self.merge.abortRebase(in: self.repo) }; await reloadAll() }
    public func continueMerge() async { await wrap(.mergeContinue) { try await self.merge.continueMerge(in: self.repo) }; await reloadAll() }
    public func continueRebase() async { await wrap(.rebaseContinue) { try await self.merge.continueRebase(in: self.repo) }; await reloadAll() }
    public func cherryPick(_ sha: String) async { await wrap(.cherryPick) { try await self.commits.cherryPick(sha, in: self.repo) }; await reloadAll() }
    public func revert(_ sha: String) async { await wrap(.revert) { try await self.commits.revert(sha, in: self.repo) }; await reloadAll() }

    // MARK: - Wrapper

    @discardableResult
    private func wrap(_ kind: GitOperationKind, _ body: @escaping @Sendable () async throws -> Void) async -> Bool {
        do {
            try await center.run(kind) { _ in try await body() }
            return true
        } catch {
            return false
        }
    }
}
