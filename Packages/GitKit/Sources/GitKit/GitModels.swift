import Foundation

// MARK: - Working tree state

/// What `git status --porcelain=v2 -z` says about a single path. We surface
/// the raw status codes alongside derived flags so the UI can build colored
/// pills, sort by category, and decide which actions are valid.
public struct WorkingChange: Equatable, Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case modified, added, deleted, renamed, copied, typeChange
        case untracked, ignored, unmerged
    }

    public let path: String
    public let oldPath: String?     // populated for renames/copies
    public let stagedKind: Kind?    // change in the index relative to HEAD
    public let unstagedKind: Kind?  // change in the worktree relative to the index
    public let isUnmerged: Bool

    public var id: String { path }

    public var hasStaged: Bool { stagedKind != nil && stagedKind != .untracked }
    public var hasUnstaged: Bool { unstagedKind != nil }

    /// Best single label for the path — picks the unstaged kind if any so the
    /// user sees the "louder" change in compact lists.
    public var displayKind: Kind {
        if isUnmerged { return .unmerged }
        return unstagedKind ?? stagedKind ?? .modified
    }
}

// MARK: - Branches

public struct BranchRef: Equatable, Identifiable, Sendable, Hashable {
    public let name: String           // short name e.g. "main" or "origin/main"
    public let isRemote: Bool
    public let isCurrent: Bool
    public let upstream: String?      // e.g. "origin/main"
    public let ahead: Int
    public let behind: Int
    public let lastCommitSubject: String?
    public let lastCommitDate: Date?

    public var id: String { (isRemote ? "remote:" : "local:") + name }

    public init(
        name: String,
        isRemote: Bool = false,
        isCurrent: Bool = false,
        upstream: String? = nil,
        ahead: Int = 0,
        behind: Int = 0,
        lastCommitSubject: String? = nil,
        lastCommitDate: Date? = nil
    ) {
        self.name = name
        self.isRemote = isRemote
        self.isCurrent = isCurrent
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.lastCommitSubject = lastCommitSubject
        self.lastCommitDate = lastCommitDate
    }
}

// MARK: - Stash + Tags

public struct StashEntry: Equatable, Identifiable, Sendable, Hashable {
    public let index: Int             // stash@{N}
    public let message: String
    public let branch: String?
    public let date: Date?

    public var id: Int { index }
    public var ref: String { "stash@{\(index)}" }
}

public struct TagRef: Equatable, Identifiable, Sendable, Hashable {
    public let name: String
    public let sha: String
    public let isAnnotated: Bool
    public let message: String?
    public let date: Date?

    public var id: String { name }
}

// MARK: - Remotes

public struct GitRemote: Equatable, Identifiable, Sendable, Hashable {
    public let name: String
    public let fetchURL: String
    public let pushURL: String
    public var id: String { name }
}

// MARK: - Operation telemetry

public enum GitOperationKind: String, Sendable, Hashable, CaseIterable {
    case status, fetch, pull, push, commit, amend, stage, unstage, discard
    case branchCreate, branchSwitch, branchDelete, branchRename, setUpstream
    case merge, rebase, cherryPick, revert
    case stashSave, stashApply, stashPop, stashDrop
    case tagCreate, tagDelete, tagPush
    case mergeAbort, rebaseAbort, mergeContinue, rebaseContinue

    public var label: String {
        switch self {
        case .status: return "Status"
        case .fetch: return "Fetch"
        case .pull: return "Pull"
        case .push: return "Push"
        case .commit: return "Commit"
        case .amend: return "Amend"
        case .stage: return "Stage"
        case .unstage: return "Unstage"
        case .discard: return "Discard"
        case .branchCreate: return "Create branch"
        case .branchSwitch: return "Switch branch"
        case .branchDelete: return "Delete branch"
        case .branchRename: return "Rename branch"
        case .setUpstream: return "Set upstream"
        case .merge: return "Merge"
        case .rebase: return "Rebase"
        case .cherryPick: return "Cherry-pick"
        case .revert: return "Revert"
        case .stashSave: return "Stash save"
        case .stashApply: return "Stash apply"
        case .stashPop: return "Stash pop"
        case .stashDrop: return "Stash drop"
        case .tagCreate: return "Create tag"
        case .tagDelete: return "Delete tag"
        case .tagPush: return "Push tag"
        case .mergeAbort: return "Abort merge"
        case .rebaseAbort: return "Abort rebase"
        case .mergeContinue: return "Continue merge"
        case .rebaseContinue: return "Continue rebase"
        }
    }
}

public struct GitOperationEvent: Sendable, Identifiable, Equatable {
    public enum Phase: Sendable, Equatable { case started, succeeded, failed(String) }
    public let id: UUID
    public let kind: GitOperationKind
    public let detail: String?
    public let phase: Phase
    public let at: Date

    public init(
        id: UUID = UUID(),
        kind: GitOperationKind,
        detail: String? = nil,
        phase: Phase,
        at: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.detail = detail
        self.phase = phase
        self.at = at
    }
}
