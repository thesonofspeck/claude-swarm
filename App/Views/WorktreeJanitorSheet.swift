import SwiftUI
import AppCore
import PersistenceKit
import SessionCore

/// Surfaces what the WorktreeJanitor would clean up — orphan worktrees on
/// disk that no DB session points at, plus DB sessions whose worktrees
/// are gone — and lets the user remove them one at a time or all at
/// once. Read-only by default; nothing is mutated until the user clicks.
struct WorktreeJanitorSheet: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var inspection: WorktreeJanitor.Inspection?
    @State private var loading = true
    @State private var working: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.divider)
            content
            Divider().background(Palette.divider)
            footer
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Palette.bgBase)
        .task { await reload() }
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(Palette.cyan)
            Text("Worktree janitor")
                .font(Type.title)
                .foregroundStyle(Palette.fgBright)
            if loading {
                ProgressView().controlSize(.small)
            }
            Spacer()
            IconButton(systemImage: "arrow.clockwise", help: "Re-scan") {
                Task { await reload() }
            }
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    @ViewBuilder
    private var content: some View {
        if let inspection {
            if inspection.isClean {
                EmptyState(
                    title: "Everything's tidy",
                    systemImage: "checkmark.seal",
                    description: "No orphan worktrees on disk and no dead session rows. Nothing to clean.",
                    tint: Palette.green
                )
            } else {
                List {
                    if !inspection.orphanWorktrees.isEmpty {
                        Section("Orphan worktrees · \(inspection.orphanWorktrees.count)") {
                            ForEach(inspection.orphanWorktrees) { orphan in
                                orphanRow(orphan)
                            }
                        }
                    }
                    if !inspection.deadSessions.isEmpty {
                        Section("Dead sessions · \(inspection.deadSessions.count)") {
                            ForEach(inspection.deadSessions) { dead in
                                deadRow(dead)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Palette.bgBase)
            }
        } else if loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyState(
                title: "Couldn't inspect",
                systemImage: "exclamationmark.triangle",
                description: "The janitor couldn't list worktrees for one or more projects.",
                tint: Palette.orange
            )
        }
    }

    private func orphanRow(_ orphan: WorktreeJanitor.Inspection.OrphanWorktree) -> some View {
        HStack(spacing: Metrics.Space.md) {
            Image(systemName: "folder.badge.questionmark")
                .foregroundStyle(Palette.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(orphan.branch)
                    .font(Type.body)
                    .foregroundStyle(Palette.fgBright)
                Text(orphan.path)
                    .font(Type.monoCaption)
                    .foregroundStyle(Palette.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Project: \(orphan.project.name)")
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
            }
            Spacer()
            if working.contains(orphan.id) {
                ProgressView().controlSize(.small)
            } else {
                Button("Remove", role: .destructive) {
                    Task { await remove(orphan) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
    }

    private func deadRow(_ dead: WorktreeJanitor.Inspection.DeadSession) -> some View {
        HStack(spacing: Metrics.Space.md) {
            Image(systemName: "powerplug")
                .foregroundStyle(Palette.fgMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(dead.session.taskTitle ?? dead.session.branch)
                    .font(Type.body)
                    .foregroundStyle(Palette.fgBright)
                Text(dead.session.branch)
                    .font(Type.monoCaption)
                    .foregroundStyle(Palette.purple)
                Text("Project: \(dead.project.name) · status \(dead.session.status.rawValue)")
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
            }
            Spacer()
            if working.contains(dead.id) {
                ProgressView().controlSize(.small)
            } else {
                Button("Mark finished") {
                    Task { await markFinished(dead) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            if let inspection, !inspection.isClean {
                Button(role: .destructive) {
                    Task { await cleanAll() }
                } label: {
                    Label("Clean everything", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!working.isEmpty)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .keyboardShortcut(.defaultAction)
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        inspection = await env.worktreeJanitor.inspect()
    }

    private func remove(_ orphan: WorktreeJanitor.Inspection.OrphanWorktree) async {
        working.insert(orphan.id)
        defer { working.remove(orphan.id) }
        try? await env.worktreeJanitor.removeOrphan(orphan)
        await reload()
    }

    private func markFinished(_ dead: WorktreeJanitor.Inspection.DeadSession) async {
        working.insert(dead.id)
        defer { working.remove(dead.id) }
        try? await env.worktreeJanitor.markDead(dead)
        await reload()
    }

    private func cleanAll() async {
        guard let snapshot = inspection else { return }
        for orphan in snapshot.orphanWorktrees {
            await remove(orphan)
        }
        for dead in snapshot.deadSessions {
            await markFinished(dead)
        }
    }
}
