import SwiftUI
import AppCore
import GitKit

struct TagsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var workspace: GitWorkspace
    @State private var showCreate = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.divider)
            list
            Divider().background(Palette.divider)
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(Palette.bgBase)
        .task { await workspace.reloadTags() }
        .sheet(isPresented: $showCreate) {
            CreateTagSheet(currentSHA: nil) { name, message in
                Task { await workspace.createTag(name, message: message); showCreate = false }
            } onCancel: {
                showCreate = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "tag")
                .foregroundStyle(Palette.orange)
            Text("Tags")
                .font(Type.title)
                .foregroundStyle(Palette.fgBright)
            Spacer()
            Button {
                showCreate = true
            } label: {
                Label("New tag", systemImage: "plus")
            }
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    private var list: some View {
        Group {
            if workspace.tagList.isEmpty {
                EmptyState(
                    title: "No tags",
                    systemImage: "tag.slash",
                    description: "Tag releases or important commits — they get pushed to remotes for everyone to find.",
                    tint: Palette.fgMuted
                )
            } else {
                List(workspace.tagList) { tag in
                    HStack(spacing: Metrics.Space.sm) {
                        Image(systemName: tag.isAnnotated ? "tag.fill" : "tag")
                            .foregroundStyle(tag.isAnnotated ? Palette.orange : Palette.fgMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tag.name)
                                .font(Type.body)
                                .foregroundStyle(Palette.fgBright)
                            HStack(spacing: 6) {
                                Text(tag.sha.prefix(7))
                                    .font(Type.monoCaption)
                                    .foregroundStyle(Palette.purple)
                                if let message = tag.message {
                                    Text(message)
                                        .font(Type.caption)
                                        .foregroundStyle(Palette.fgMuted)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer()
                        if let date = tag.date {
                            Text(date.formatted(.relative(presentation: .named)))
                                .font(Type.caption)
                                .foregroundStyle(Palette.fgMuted)
                        }
                        Button("Push") { Task { await workspace.pushTag(tag.name) } }
                            .buttonStyle(.bordered)
                        Button(role: .destructive) {
                            Task { await workspace.deleteTag(tag.name) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .help("Delete")
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

private struct CreateTagSheet: View {
    let currentSHA: String?
    let onCreate: (String, String?) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var message = ""
    @State private var annotated = true

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Text("New tag")
                .font(Type.title)
                .foregroundStyle(Palette.fgBright)
            TextField("v1.2.3", text: $name)
                .textFieldStyle(.roundedBorder)
            Toggle("Annotated (with message)", isOn: $annotated)
            if annotated {
                TextField("Release notes", text: $message, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onCreate(trimmed, annotated ? message : nil)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Metrics.Space.lg)
        .frame(minWidth: 420)
    }
}
