import Foundation
import SwiftUI
import GitKit

/// View-model for a single working tree's full git surface. Owns the
/// services so views don't have to wire them up, holds the live status,
/// and routes every mutation through `GitOperationCenter` so the toolbar
/// has one progress/error stream to render.
@MainActor
public final class GitWorkspace: ObservableObject {
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

    @Published public private(set) var changes: [WorkingChange] = []
    @Published public private(set) var branchList: [BranchRef] = []
    @Published public private(set) var stashes: [StashEntry] = []
    @Published public private(set) var tagList: [TagRef] = []
    @Published public private(set) var remotes: [GitRemote] = []
    @Published public private(set) var currentBranch: String?
    @Published public private(set) var ahead: Int = 0
    @Published public private(set) var behind: Int = 0
    @Published public private(set) var repoState: MergeService.RepoState = .clean
    @Published public private(set) var lastError: String?
    @Published public private(set) var busy: Bool = false

    /// Single rolling marker so the toolbar can show "Pushing…", "Done",
    /// "Failed: …" without each call site wiring its own view state.
    @Published public private(set) var statusLine: String?

    private var eventTask: Task<Void, Never>?

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
        startListening()
    }

    deinit {
        eventTask?.cancel()
    }

    private func startListening() {
        let center = self.center
        eventTask = Task { [weak self] in
            for await event in await center.events() {
                await MainActor.run { self?.consume(event) }
            }
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
        async let s: Void = reloadStatus()
        async let b: Void = reloadBranches()
        async let st: Void = reloadStashes()
        async let t: Void = reloadTags()
        async let r: Void = reloadRemotes()
        _ = await (s, b, st, t, r)
        repoState = merge.currentState(in: repo)
    }

    public func reloadStatus() async {
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

    public func reloadBranches() async {
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
