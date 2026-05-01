import SwiftUI
import AppCore
import DiffViewer
import GitKit
import PersistenceKit

/// Local-dev workspace: staged/unstaged file list, hunk-aware diff, and a
/// commit composer. Mirrors the spirit of Xcode's source-control changes
/// pane but with our Atom palette and the kinds of guardrails (force-with-
/// lease, in-progress merge banner) you actually want when working on
/// production code.
struct ChangesTab: View {
    @EnvironmentObject var env: AppEnvironment
    let session: Session

    @StateObject private var workspace: WorkspaceHolder = .init()
    @State private var selection: String?
    @State private var fileDiff: [DiffFile] = []
    @State private var commitMessage: String = ""
    @State private var amend = false
    @State private var signOff = false
    @State private var showBranches = false
    @State private var showStash = false
    @State private var showTags = false

    var body: some View {
        Group {
            if let ws = workspace.value {
                content(ws)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: session.worktreePath) {
            workspace.value = env.gitWorkspace(for: session.worktreePath)
            if let ws = workspace.value {
                await ws.reloadAll()
                await reloadFileDiff(ws)
            }
        }
        .task(id: session.worktreePath) {
            // Subscribe to the workspace pulse for the lifetime of the
            // tab. The pulse fans in FSEvents, hook events, and completed
            // ops; we only refresh the diff when status changes (file
            // edits) so other invalidations don't trigger redundant work.
            guard let ws = workspace.value else { return }
            for await invalidations in ws.pulse.events() {
                if invalidations.contains(.status) || invalidations.contains(.files) {
                    await reloadFileDiff(ws)
                }
            }
        }
        .sheet(isPresented: $showBranches) {
            if let ws = workspace.value {
                BranchesSheet(workspace: ws)
            }
        }
        .sheet(isPresented: $showStash) {
            if let ws = workspace.value {
                StashSheet(workspace: ws)
            }
        }
        .sheet(isPresented: $showTags) {
            if let ws = workspace.value {
                TagsSheet(workspace: ws)
            }
        }
    }

    @ViewBuilder
    private func content(_ ws: GitWorkspace) -> some View {
        VStack(spacing: 0) {
            SyncToolbar(
                workspace: ws,
                onBranches: { showBranches = true },
                onStash: { showStash = true },
                onTags: { showTags = true }
            )
            if ws.repoState != .clean {
                RepoStateBanner(workspace: ws)
            }
            Divider().background(Palette.divider)
            HSplitView {
                ChangesFileList(
                    workspace: ws,
                    selection: $selection,
                    onSelect: { _ in Task { await reloadFileDiff(ws) } }
                )
                .frame(minWidth: 320, idealWidth: 360)
                ChangesDiffPane(files: fileDiff, selection: selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider().background(Palette.divider)
            CommitComposer(
                message: $commitMessage,
                amend: $amend,
                signOff: $signOff,
                hasStaged: ws.changes.contains { $0.hasStaged },
                onCommit: { await runCommit(ws) }
            )
        }
        .background(Palette.bgBase)
    }

    private func reloadFileDiff(_ ws: GitWorkspace) async {
        guard let selection else {
            fileDiff = []
            return
        }
        async let unstaged = ws.diffForFile(selection, staged: false)
        async let staged = ws.diffForFile(selection, staged: true)
        fileDiff = await unstaged + staged
    }

    private func runCommit(_ ws: GitWorkspace) async {
        let trimmed = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || amend else { return }
        let ok = await ws.commit(message: trimmed, amend: amend, signOff: signOff)
        if ok {
            commitMessage = ""
            amend = false
        }
    }
}

@MainActor
private final class WorkspaceHolder: ObservableObject {
    @Published var value: GitWorkspace?
}

// MARK: - File list

private struct ChangesFileList: View {
    @ObservedObject var workspace: GitWorkspace
    @Binding var selection: String?
    let onSelect: (String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.divider)
            if workspace.changes.isEmpty {
                EmptyState(
                    title: "Nothing changed",
                    systemImage: "checkmark.circle",
                    description: "Working tree is clean.",
                    tint: Palette.green
                )
            } else {
                List(selection: $selection) {
                    Section {
                        ForEach(staged) { row(for: $0, staged: true) }
                    } header: {
                        sectionHeader("Staged", count: staged.count, action: {
                            Task { await workspace.unstagePaths(staged.map(\.path)) }
                        }, actionLabel: "Unstage all", systemImage: "minus.circle")
                    }
                    Section {
                        ForEach(unstaged) { row(for: $0, staged: false) }
                    } header: {
                        sectionHeader("Unstaged", count: unstaged.count, action: {
                            Task { await workspace.stagePaths(unstaged.map(\.path)) }
                        }, actionLabel: "Stage all", systemImage: "plus.circle")
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Palette.bgBase)
            }
        }
        .onChange(of: selection) { _, new in onSelect(new) }
    }

    private var staged: [WorkingChange] { workspace.changes.filter(\.hasStaged) }
    private var unstaged: [WorkingChange] { workspace.changes.filter { !$0.hasStaged } }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            SectionLabel(title: "Changes")
            Spacer()
            Text("\(workspace.changes.count) file\(workspace.changes.count == 1 ? "" : "s")")
                .font(Type.caption)
                .foregroundStyle(Palette.fgMuted)
            IconButton(systemImage: "arrow.clockwise", help: "Refresh") {
                Task { await workspace.reloadStatus() }
            }
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    private func sectionHeader(
        _ title: String,
        count: Int,
        action: @escaping () -> Void,
        actionLabel: String,
        systemImage: String
    ) -> some View {
        HStack {
            Text("\(title) · \(count)")
                .font(Type.label)
                .foregroundStyle(Palette.fgMuted)
            Spacer()
            if count > 0 {
                Button(action: action) {
                    Label(actionLabel, systemImage: systemImage)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Palette.fgMuted)
                }
                .buttonStyle(.plain)
                .help(actionLabel)
            }
        }
    }

    private func row(for change: WorkingChange, staged: Bool) -> some View {
        HStack(spacing: Metrics.Space.sm) {
            kindBadge(change.displayKind)
            Text(change.path)
                .font(Type.mono)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(action: {
                Task {
                    if staged {
                        await workspace.unstagePaths([change.path])
                    } else {
                        await workspace.stagePaths([change.path])
                    }
                }
            }) {
                Image(systemName: staged ? "minus.circle" : "plus.circle")
                    .foregroundStyle(staged ? Palette.orange : Palette.green)
            }
            .buttonStyle(.plain)
            .help(staged ? "Unstage" : "Stage")
        }
        .padding(.vertical, 2)
        .tag(Optional(change.path))
        .contextMenu {
            if staged {
                Button("Unstage") {
                    Task { await workspace.unstagePaths([change.path]) }
                }
            } else {
                Button("Stage") {
                    Task { await workspace.stagePaths([change.path]) }
                }
                Button("Discard changes…", role: .destructive) {
                    Task { await workspace.discardPaths([change.path]) }
                }
            }
        }
    }

    private func kindBadge(_ kind: WorkingChange.Kind) -> some View {
        let (letter, color): (String, Color) = {
            switch kind {
            case .added: return ("A", Palette.green)
            case .deleted: return ("D", Palette.red)
            case .modified: return ("M", Palette.blue)
            case .renamed: return ("R", Palette.purple)
            case .copied: return ("C", Palette.cyan)
            case .typeChange: return ("T", Palette.orange)
            case .untracked: return ("?", Palette.fgMuted)
            case .ignored: return ("!", Palette.fgMuted)
            case .unmerged: return ("U", Palette.red)
            }
        }()
        return Text(letter)
            .font(Type.label)
            .foregroundStyle(color)
            .frame(width: 18, height: 18)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - Diff pane

private struct ChangesDiffPane: View {
    let files: [DiffFile]
    let selection: String?

    var body: some View {
        if selection == nil {
            EmptyState(
                title: "No file selected",
                systemImage: "doc.text",
                description: "Pick a changed file on the left to view its diff.",
                tint: Palette.fgMuted
            )
        } else if files.isEmpty {
            EmptyState(
                title: "No diff",
                systemImage: "doc.text",
                description: "This change has no diff (binary, deleted, or untracked).",
                tint: Palette.fgMuted
            )
        } else {
            DiffView(files: files)
        }
    }
}

// MARK: - Commit composer

private struct CommitComposer: View {
    @Binding var message: String
    @Binding var amend: Bool
    @Binding var signOff: Bool
    let hasStaged: Bool
    let onCommit: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            HStack(spacing: Metrics.Space.sm) {
                ForEach(["feat", "fix", "chore", "refactor", "test", "docs"], id: \.self) { prefix in
                    Button("\(prefix):") { insertPrefix(prefix) }
                        .buttonStyle(.plain)
                        .font(Type.label)
                        .foregroundStyle(Palette.fgMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.pillBg))
                        .help("Prefix the subject with \(prefix):")
                }
                Spacer()
                Toggle("Amend", isOn: $amend)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                Toggle("Sign-off", isOn: $signOff)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
            }
            TextEditor(text: $message)
                .font(Type.mono)
                .frame(minHeight: 88, maxHeight: 140)
                .padding(Metrics.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.Radius.md)
                        .fill(Palette.bgRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.Radius.md)
                        .stroke(Palette.divider, lineWidth: Metrics.Stroke.hairline)
                )
                .overlay(alignment: .topLeading) {
                    if message.isEmpty {
                        Text(amend ? "Amending… leave blank to keep previous message" : "Commit subject\n\nLonger description (optional)")
                            .font(Type.mono)
                            .foregroundStyle(Palette.fgMuted)
                            .padding(.horizontal, Metrics.Space.md)
                            .padding(.vertical, Metrics.Space.sm + 2)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                Text(subjectByteHint)
                    .font(Type.caption)
                    .foregroundStyle(subjectOver ? Palette.orange : Palette.fgMuted)
                Spacer()
                Button {
                    Task { await onCommit() }
                } label: {
                    Label(amend ? "Amend commit" : "Commit", systemImage: amend ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canCommit)
                .help("⌘↩")
            }
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    private var canCommit: Bool {
        if amend { return true }
        guard hasStaged else { return false }
        return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var subjectByteHint: String {
        let firstLine = message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? message
        return "\(firstLine.count)/72"
    }

    private var subjectOver: Bool {
        let firstLine = message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? message
        return firstLine.count > 72
    }

    private func insertPrefix(_ prefix: String) {
        let firstLine = message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        if firstLine.hasPrefix("\(prefix):") { return }
        let stripped = stripExistingPrefix(firstLine)
        let rest = message.dropFirst(firstLine.count)
        message = "\(prefix): \(stripped)\(rest)"
    }

    private func stripExistingPrefix(_ subject: String) -> String {
        for p in ["feat", "fix", "chore", "refactor", "test", "docs"] {
            if subject.hasPrefix("\(p): ") { return String(subject.dropFirst(p.count + 2)) }
        }
        return subject
    }
}

// MARK: - Repo-state banner

private struct RepoStateBanner: View {
    @ObservedObject var workspace: GitWorkspace

    var body: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.orange)
            Text(messageText)
                .font(Type.body)
                .foregroundStyle(Palette.fgBright)
            Spacer()
            switch workspace.repoState {
            case .mergeInProgress:
                Button("Continue merge") { Task { await workspace.continueMerge() } }
                Button("Abort", role: .destructive) { Task { await workspace.abortMerge() } }
            case .rebaseInProgress:
                Button("Continue rebase") { Task { await workspace.continueRebase() } }
                Button("Abort", role: .destructive) { Task { await workspace.abortRebase() } }
            default:
                EmptyView()
            }
        }
        .padding(Metrics.Space.md)
        .background(Palette.warnBg)
    }

    private var messageText: String {
        switch workspace.repoState {
        case .mergeInProgress: return "Merge in progress — resolve conflicts then continue or abort."
        case .rebaseInProgress: return "Rebase in progress — resolve conflicts then continue or abort."
        case .cherryPickInProgress: return "Cherry-pick in progress."
        case .revertInProgress: return "Revert in progress."
        case .bisectInProgress: return "Bisect in progress."
        case .clean: return ""
        }
    }
}
