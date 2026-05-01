import SwiftUI
import AppCore
import GitKit

/// The compact toolbar at the top of the Changes tab. Renders the current
/// branch, ahead/behind counters, fetch/pull/push buttons, and a status
/// line that mirrors `GitOperationCenter` events.
struct SyncToolbar: View {
    let workspace: GitWorkspace
    let onBranches: () -> Void
    let onStash: () -> Void
    let onTags: () -> Void

    var body: some View {
        HStack(spacing: Metrics.Space.md) {
            branchControl
            aheadBehindBadges
            Spacer()
            statusLine
            Spacer()
            actionButtons
        }
        .padding(.horizontal, Metrics.Space.md)
        .padding(.vertical, Metrics.Space.sm)
        .background(Palette.bgSidebar)
    }

    private var branchControl: some View {
        Button(action: onBranches) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(Palette.purple)
                Text(workspace.currentBranch ?? "(detached)")
                    .font(Type.body)
                    .foregroundStyle(Palette.fgBright)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(Palette.fgMuted)
            }
            .padding(.horizontal, Metrics.Space.sm)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .fill(Palette.bgRaised)
            )
        }
        .buttonStyle(.plain)
        .help("Switch branch — ⌘B")
        .keyboardShortcut("b", modifiers: .command)
    }

    @ViewBuilder
    private var aheadBehindBadges: some View {
        if workspace.ahead > 0 {
            Pill(text: "↑\(workspace.ahead)", systemImage: "arrow.up", tint: Palette.green)
        }
        if workspace.behind > 0 {
            Pill(text: "↓\(workspace.behind)", systemImage: "arrow.down", tint: Palette.orange)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if workspace.busy {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                if let line = workspace.statusLine {
                    Text(line)
                        .font(Type.caption)
                        .foregroundStyle(Palette.fgMuted)
                }
            }
        } else if let err = workspace.lastError {
            Text(err)
                .font(Type.caption)
                .foregroundStyle(Palette.red)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(err)
        } else if let line = workspace.statusLine {
            Text(line)
                .font(Type.caption)
                .foregroundStyle(Palette.fgMuted)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            IconButton(systemImage: "arrow.clockwise.icloud", help: "Fetch — ⌘⌥F") {
                Task { await workspace.fetch() }
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Menu {
                Button("Pull (fast-forward only)") { Task { await workspace.pull(strategy: .ffOnly) } }
                Button("Pull with merge") { Task { await workspace.pull(strategy: .merge) } }
                Button("Pull with rebase") { Task { await workspace.pull(strategy: .rebase) } }
            } label: {
                Image(systemName: "arrow.down.to.line")
                    .foregroundStyle(Palette.fgMuted)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30)
            .help("Pull")

            Menu {
                Button("Push") { Task { await workspace.push() } }
                Button("Push (set upstream)") { Task { await workspace.push(setUpstream: true) } }
                Divider()
                Button("Force push (with lease)") { Task { await workspace.push(safety: .withLease) } }
                Button("Force push", role: .destructive) { Task { await workspace.push(safety: .force) } }
            } label: {
                Image(systemName: "arrow.up.to.line")
                    .foregroundStyle(Palette.fgMuted)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30)
            .help("Push — ⌘⇧P")
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider().frame(height: 16)

            IconButton(systemImage: "tray.and.arrow.down", help: "Stash") { onStash() }
            IconButton(systemImage: "tag", help: "Tags") { onTags() }
        }
    }
}
