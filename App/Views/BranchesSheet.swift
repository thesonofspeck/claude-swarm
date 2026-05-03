import SwiftUI
import AppCore
import GitKit

struct BranchesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var workspace: GitWorkspace
    @State private var query: String = ""
    @State private var newBranchName: String = ""
    @State private var creatingFrom: String?
    @State private var showCreate = false
    @State private var renamingBranch: BranchRef?
    @State private var renameTo: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.divider)
            list
            Divider().background(Palette.divider)
            footer
        }
        .frame(minWidth: 540, minHeight: 480)
        .background(Palette.bgBase)
        .task { await workspace.reloadBranches() }
        .sheet(isPresented: $showCreate) {
            CreateBranchSheet(
                base: creatingFrom ?? workspace.currentBranch ?? "main",
                onCreate: { name, switchAfter in
                    Task { await workspace.createBranch(name, from: creatingFrom, switchAfter: switchAfter); showCreate = false }
                },
                onCancel: { showCreate = false }
            )
        }
        .sheet(item: $renamingBranch) { branch in
            RenameBranchSheet(
                from: branch.name,
                onRename: { newName in
                    Task { await workspace.renameBranch(from: branch.name, to: newName); renamingBranch = nil }
                },
                onCancel: { renamingBranch = nil }
            )
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(Palette.purple)
            Text("Branches")
                .font(Type.title)
                .foregroundStyle(Palette.fgBright)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.fgMuted)
                TextField("Filter", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, Metrics.Space.sm)
            .padding(.vertical, 4)
            .frame(width: 220)
            .background(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .fill(Palette.bgRaised)
            )
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    private var local: [BranchRef] {
        workspace.branchList.filter { !$0.isRemote && matches($0.name) }
    }

    private var remote: [BranchRef] {
        workspace.branchList.filter { $0.isRemote && matches($0.name) }
    }

    private func matches(_ s: String) -> Bool {
        query.isEmpty || s.localizedCaseInsensitiveContains(query)
    }

    private var list: some View {
        List {
            Section("Local") {
                ForEach(local) { branch in
                    branchRow(branch)
                }
            }
            Section("Remote") {
                ForEach(remote) { branch in
                    branchRow(branch)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Palette.bgBase)
    }

    private func branchRow(_ branch: BranchRef) -> some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : (branch.isRemote ? "antenna.radiowaves.left.and.right" : "arrow.triangle.branch"))
                .foregroundStyle(branch.isCurrent ? Palette.green : (branch.isRemote ? Palette.cyan : Palette.fgMuted))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(branch.name)
                    .font(Type.body)
                    .foregroundStyle(Palette.fgBright)
                if let subject = branch.lastCommitSubject {
                    Text(subject)
                        .font(Type.caption)
                        .foregroundStyle(Palette.fgMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let upstream = branch.upstream, !branch.isRemote {
                Pill(text: upstream, systemImage: "link", tint: Palette.fgMuted)
            }
            if branch.ahead > 0 {
                Pill(text: "↑\(branch.ahead)", tint: Palette.green)
            }
            if branch.behind > 0 {
                Pill(text: "↓\(branch.behind)", tint: Palette.orange)
            }
            if let date = branch.lastCommitDate {
                Text(date.formatted(.relative(presentation: .named)))
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
                    .frame(width: 90, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
        .contextMenu { contextMenu(for: branch) }
        .onTapGesture(count: 2) {
            switchTo(branch)
        }
    }

    @ViewBuilder
    private func contextMenu(for branch: BranchRef) -> some View {
        if !branch.isCurrent {
            Button("Switch") { switchTo(branch) }
        }
        Button("New branch from here…") {
            creatingFrom = branch.name
            showCreate = true
        }
        if !branch.isRemote {
            Button("Rename…") { renamingBranch = branch }
            Divider()
            if let upstream = branch.upstream {
                Button("Unset upstream (\(upstream))") {
                    Task { try? await workspace.branches.unsetUpstream(branch: branch.name, in: workspace.repo); await workspace.reloadBranches() }
                }
            }
            Menu("Set upstream…") {
                ForEach(workspace.branchList.filter(\.isRemote)) { remote in
                    Button(remote.name) {
                        Task { await workspace.setUpstream(remote.name, for: branch.name) }
                    }
                }
            }
            Divider()
            Button("Merge into current", action: { Task { await workspace.mergeBranch(branch.name) } })
                .disabled(branch.isCurrent)
            Button("Rebase current onto…", action: { Task { await workspace.rebaseOnto(branch.name) } })
                .disabled(branch.isCurrent)
            Divider()
            Button("Delete", role: .destructive) {
                Task { await workspace.deleteBranch(branch.name) }
            }
            .disabled(branch.isCurrent)
            Button("Force delete", role: .destructive) {
                Task { await workspace.deleteBranch(branch.name, force: true) }
            }
            .disabled(branch.isCurrent)
        } else {
            Button("Push", action: { Task { await workspace.push() } })
        }
    }

    private func switchTo(_ branch: BranchRef) {
        Task {
            if branch.isRemote {
                let local = branch.name.split(separator: "/", maxSplits: 1).last.map(String.init) ?? branch.name
                await workspace.createBranch(local, from: branch.name, switchAfter: true)
            } else {
                await workspace.switchBranch(branch.name)
            }
            dismiss()
        }
    }

    private var footer: some View {
        HStack {
            Button {
                creatingFrom = nil
                showCreate = true
            } label: {
                Label("New branch", systemImage: "plus")
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }
}

private struct CreateBranchSheet: View {
    let base: String
    let onCreate: (String, Bool) -> Void
    let onCancel: () -> Void
    @State private var name: String = ""
    @State private var switchAfter = true

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Text("New branch")
                .font(Type.title)
                .foregroundStyle(Palette.fgBright)
            Text("Branching from \(base)")
                .font(Type.caption)
                .foregroundStyle(Palette.fgMuted)
            TextField("feat/short-name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
            Toggle("Switch after creating", isOn: $switchAfter)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Metrics.Space.lg)
        .frame(minWidth: 380)
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed, switchAfter)
    }
}

private struct RenameBranchSheet: View {
    let from: String
    let onRename: (String) -> Void
    let onCancel: () -> Void
    @State private var newName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Text("Rename branch")
                .font(Type.title)
                .foregroundStyle(Palette.fgBright)
            Text("Renaming \(from)")
                .font(Type.caption)
                .foregroundStyle(Palette.fgMuted)
            TextField("New name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Metrics.Space.lg)
        .frame(minWidth: 380)
        .onAppear { newName = from }
    }

    private func commit() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onRename(trimmed)
    }
}
