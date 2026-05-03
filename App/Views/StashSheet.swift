import SwiftUI
import AppCore
import GitKit

struct StashSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var workspace: GitWorkspace
    @State private var newMessage = ""
    @State private var includeUntracked = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.divider)
            saveBar
            Divider().background(Palette.divider)
            list
            Divider().background(Palette.divider)
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(Palette.bgBase)
        .task { await workspace.reloadStashes() }
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "tray.and.arrow.down")
                .foregroundStyle(Palette.cyan)
            Text("Stash")
                .font(Type.title)
                .foregroundStyle(Palette.fgBright)
            Spacer()
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    private var saveBar: some View {
        HStack(spacing: Metrics.Space.sm) {
            TextField("Message (optional)", text: $newMessage)
                .textFieldStyle(.roundedBorder)
            Toggle("Include untracked", isOn: $includeUntracked)
                .toggleStyle(.checkbox)
                .controlSize(.small)
            Button {
                Task {
                    await workspace.saveStash(
                        message: newMessage.isEmpty ? nil : newMessage,
                        includeUntracked: includeUntracked
                    )
                    newMessage = ""
                }
            } label: {
                Label("Save stash", systemImage: "tray.and.arrow.down.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(workspace.changes.isEmpty)
        }
        .padding(Metrics.Space.md)
    }

    private var list: some View {
        Group {
            if workspace.stashes.isEmpty {
                EmptyState(
                    title: "No stashes",
                    systemImage: "tray",
                    description: "Stash uncommitted work to switch branches without losing it.",
                    tint: Palette.fgMuted
                )
            } else {
                List(workspace.stashes) { stash in
                    HStack(spacing: Metrics.Space.sm) {
                        Text(stash.ref)
                            .font(Type.monoCaption)
                            .foregroundStyle(Palette.purple)
                            .frame(width: 90, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stash.message)
                                .font(Type.body)
                                .foregroundStyle(Palette.fgBright)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if let branch = stash.branch {
                                    Pill(text: branch, systemImage: "arrow.triangle.branch", tint: Palette.fgMuted)
                                }
                                if let date = stash.date {
                                    Text(date.formatted(.relative(presentation: .named)))
                                        .font(Type.caption)
                                        .foregroundStyle(Palette.fgMuted)
                                }
                            }
                        }
                        Spacer()
                        Button("Apply") { Task { await workspace.applyStash(stash.index) } }
                            .buttonStyle(.bordered)
                        Button("Pop") { Task { await workspace.popStash(stash.index); } }
                            .buttonStyle(.bordered)
                        Button(role: .destructive) {
                            Task { await workspace.dropStash(stash.index) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .help("Drop")
                    }
                    .padding(.vertical, 2)
                }
                .scrollContentBackground(.hidden)
                .background(Palette.bgBase)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }
}
