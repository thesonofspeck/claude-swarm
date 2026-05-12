import SwiftUI
import AppCore
import PersistenceKit
import DiffViewer
import GitKit
import Splash

struct FilesTab: View {
    @Environment(AppEnvironment.self) private var env
    let session: Session

    @State private var entries: [FileNode] = []
    @State private var selection: FileNode.ID?
    @State private var fileContents: String = ""
    @State private var fileExtension: String = ""
    @State private var loadingFile = false
    @State private var error: String?
    @State private var quickLookURL: URL?
    @State private var editing = false
    @State private var dirty = false
    @State private var saving = false
    @State private var loadedURL: URL?
    @State private var showTree: Bool = true
    @State private var newFileSheet: Bool = false
    @State private var scrollToLine: Int? = nil
    @State private var jumpHint: String? = nil

    private var navigator: SymbolNavigator {
        SymbolNavigator(
            worktreeRoot: URL(fileURLWithPath: session.worktreePath),
            gitExecutable: env.settings.gitExecutable.isEmpty ? "/usr/bin/git" : env.settings.gitExecutable
        )
    }

    private var isSwift: Bool { fileExtension == "swift" }

    private func highlightedSwift(_ source: String) -> AttributedString? {
        let highlighter = SyntaxHighlighter(format: AttributedStringOutputFormat(theme: AtomSplashTheme.current()))
        let attr = highlighter.highlight(source)
        return try? AttributedString(attr, including: \.appKit)
    }

    var body: some View {
        HSplitView {
            if showTree {
                VStack(spacing: 0) {
                    treeToolbar
                    Divider().background(Palette.divider)
                    tree
                }
                .frame(minWidth: 240, idealWidth: 280)
            }
            VStack(spacing: 0) {
                editorToolbar
                Divider().background(Palette.divider)
                preview
            }
        }
        .task(id: session.id) {
            await loadTree()
        }
        .task(id: session.id) {
            let ws = env.gitWorkspace(for: session.worktreePath)
            for await invalidations in ws.pulse.events() {
                if invalidations.contains(.files) || invalidations.contains(.status) {
                    await loadTree()
                }
            }
        }
        .quickLookPreview($quickLookURL)
        .focusable()
        .onKeyPress(.space) {
            if let id = selection, let node = find(id, in: entries), !node.isDirectory {
                quickLookURL = (quickLookURL == nil) ? node.url : nil
                return .handled
            }
            return .ignored
        }
        .sheet(isPresented: $newFileSheet) {
            NewFileSheet(
                worktreeRoot: URL(fileURLWithPath: session.worktreePath),
                targetDirectory: currentTargetDirectory(),
                onCreate: { url in
                    Task {
                        await loadTree()
                        selection = url.path
                        await loadFile(url)
                        env.gitWorkspace(for: session.worktreePath).invalidate([.files, .status])
                    }
                }
            )
        }
    }

    private var treeToolbar: some View {
        HStack(spacing: Metrics.Space.sm) {
            Text("Project")
                .font(Type.label)
                .foregroundStyle(Palette.fgMuted)
            Spacer()
            Button {
                newFileSheet = true
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(.plain)
            .help("New file…")
            Button {
                Task { await loadTree() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, Metrics.Space.md)
        .padding(.vertical, 6)
        .background(Palette.bgSidebar)
    }

    private func currentTargetDirectory() -> URL {
        let root = URL(fileURLWithPath: session.worktreePath)
        guard let id = selection, let node = find(id, in: entries) else { return root }
        return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
    }

    private var tree: some View {
        List(entries, children: \.children, selection: $selection) { node in
            HStack(spacing: 6) {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
                    .foregroundStyle(node.isDirectory ? Palette.blue : Palette.fgMuted)
                    .imageScale(.small)
                Text(node.name)
                    .font(Type.body)
                    .foregroundStyle(Palette.fg)
                    .lineLimit(1)
            }
            .tag(Optional(node.id))
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Palette.bgSidebar)
        .onChange(of: selection) { _, newValue in
            guard let id = newValue, let node = find(id, in: entries), !node.isDirectory else {
                fileContents = ""
                fileExtension = ""
                loadedURL = nil
                editing = false
                dirty = false
                return
            }
            fileExtension = node.url.pathExtension.lowercased()
            Task { await loadFile(node.url) }
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: Metrics.Space.sm) {
            Button {
                withAnimation { showTree.toggle() }
            } label: {
                Image(systemName: showTree ? "sidebar.left" : "sidebar.leading")
            }
            .buttonStyle(.plain)
            .help(showTree ? "Hide project tree" : "Show project tree")
            if let url = loadedURL {
                Image(systemName: "doc.text")
                    .foregroundStyle(Palette.fgMuted)
                    .imageScale(.small)
                Text(url.lastPathComponent)
                    .font(Type.body)
                    .foregroundStyle(Palette.fgBright)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if dirty {
                    Text("• unsaved")
                        .font(Type.caption)
                        .foregroundStyle(Palette.orange)
                }
            } else {
                Text("No file selected")
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
            }
            if let jumpHint {
                Text(jumpHint)
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
            }
            Spacer()
            if loadedURL != nil {
                if editing {
                    if saving { ProgressView().controlSize(.small) }
                    Button {
                        save()
                    } label: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!dirty || saving)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button {
                        editing = false
                        dirty = false
                        if let url = loadedURL { Task { await loadFile(url) } }
                    } label: {
                        Label("Done", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        editing = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, Metrics.Space.md)
        .padding(.vertical, 6)
        .background(Palette.bgSidebar)
    }

    private var preview: some View {
        Group {
            if let error {
                EmptyState(
                    title: "Couldn't read file",
                    systemImage: "exclamationmark.triangle",
                    description: error,
                    tint: Palette.orange
                )
            } else if loadingFile {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadedURL == nil {
                EmptyState(
                    title: "No file selected",
                    systemImage: "doc.text",
                    description: "Pick a file from the tree to preview or edit it.",
                    tint: Palette.blue
                )
            } else if editing {
                CodeEditorView(
                    text: Binding(
                        get: { fileContents },
                        set: { fileContents = $0; dirty = true }
                    ),
                    fileExtension: fileExtension,
                    isEditable: true,
                    onJumpToSymbol: { word in
                        Task { await jumpToSymbol(word) }
                    },
                    scrollToLine: $scrollToLine
                )
                .background(Palette.bgBase)
            } else {
                ScrollView {
                    if isSwift, let highlighted = highlightedSwift(fileContents) {
                        Text(highlighted)
                            .font(Type.mono)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Metrics.Space.md)
                            .textSelection(.enabled)
                    } else {
                        Text(fileContents)
                            .font(Type.mono)
                            .foregroundStyle(Palette.fg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Metrics.Space.md)
                            .textSelection(.enabled)
                    }
                }
                .background(Palette.bgBase)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func save() {
        guard let url = loadedURL else { return }
        saving = true
        defer { saving = false }
        do {
            try fileContents.write(to: url, atomically: true, encoding: .utf8)
            dirty = false
            // Trigger a workspace pulse so the diff/changes tabs refresh
            // immediately after the user saves.
            env.gitWorkspace(for: session.worktreePath).invalidate([.status, .files])
        } catch {
            self.error = "Save failed: \(error.localizedDescription)"
        }
    }

    private func loadTree() async {
        let root = URL(fileURLWithPath: session.worktreePath)
        let nodes = await Task.detached { try? FileNode.tree(at: root, depth: 6) }.value ?? []
        entries = nodes
    }

    private func jumpToSymbol(_ name: String) async {
        let matches = await navigator.definitions(of: name, limit: 5)
        guard let hit = matches.first else {
            await MainActor.run {
                jumpHint = "No definition found for \"\(name)\""
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if jumpHint?.contains(name) == true { jumpHint = nil }
                }
            }
            return
        }
        let url = URL(fileURLWithPath: session.worktreePath).appendingPathComponent(hit.path)
        // Pick the tree node so the user sees where they landed.
        selection = url.path
        fileExtension = url.pathExtension.lowercased()
        await loadFile(url)
        await MainActor.run {
            editing = true   // Cmd+click into a file → open it editable
            scrollToLine = hit.line
            if matches.count > 1 {
                jumpHint = "\(matches.count) matches — showing first"
            } else {
                jumpHint = nil
            }
        }
    }

    private func loadFile(_ url: URL) async {
        loadingFile = true; error = nil
        // If the user switched files mid-edit, drop unsaved changes —
        // an explicit confirm dialog can be added if this becomes painful.
        if loadedURL?.path != url.path {
            editing = false
            dirty = false
        }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs[.size] as? Int ?? 0
            if size > 1_000_000 {
                fileContents = ""
                loadedURL = nil
                error = "File is \(size / 1024) KiB — too large to preview here. Open it in your editor."
                loadingFile = false
                return
            }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                fileContents = ""
                loadedURL = nil
                error = "Binary file — preview not supported."
                loadingFile = false
                return
            }
            fileContents = text
            loadedURL = url
            loadingFile = false
        } catch {
            self.error = "\(error.localizedDescription)"
            loadingFile = false
        }
    }

    private func find(_ id: FileNode.ID, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.id == id { return node }
            if let children = node.children, let hit = find(id, in: children) {
                return hit
            }
        }
        return nil
    }
}

struct NewFileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let worktreeRoot: URL
    let targetDirectory: URL
    let onCreate: (URL) -> Void

    @State private var filename: String = ""
    @State private var error: String?

    private var relativeTargetDisplay: String {
        let rootPath = worktreeRoot.standardizedFileURL.path
        let targetPath = targetDirectory.standardizedFileURL.path
        if targetPath == rootPath { return "." }
        if targetPath.hasPrefix(rootPath + "/") {
            return String(targetPath.dropFirst(rootPath.count + 1))
        }
        return targetPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            HStack(spacing: Metrics.Space.sm) {
                Image(systemName: "doc.badge.plus")
                    .foregroundStyle(Palette.cyan)
                    .imageScale(.large)
                Text("New file")
                    .font(Type.heading)
                    .foregroundStyle(Palette.fgBright)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Location")
                    .font(Type.label)
                    .foregroundStyle(Palette.fgMuted)
                Text(relativeTargetDisplay)
                    .font(Type.mono)
                    .foregroundStyle(Palette.fgBright)
                    .textSelection(.enabled)
            }
            TextField("filename.ext", text: $filename, prompt: Text("e.g. NewView.swift"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { create() }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.red)
                    .font(Type.caption)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(filename.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Metrics.Space.lg)
        .frame(width: 460)
    }

    private func create() {
        let trimmed = filename.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if trimmed.contains("/") || trimmed.contains("..") {
            error = "Filename can't contain slashes or `..`. Pick a different directory in the tree to nest."
            return
        }
        let url = targetDirectory.appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: url.path) {
            error = "A file with that name already exists."
            return
        }
        do {
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "".write(to: url, atomically: true, encoding: .utf8)
            onCreate(url)
            dismiss()
        } catch {
            self.error = "Couldn't create file: \(error.localizedDescription)"
        }
    }
}

struct FileNode: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    let children: [FileNode]?

    static func tree(at root: URL, depth: Int, ignored: Set<String> = [".git", ".build", "node_modules", ".swiftpm", "DerivedData"]) throws -> [FileNode] {
        let fm = FileManager.default
        guard depth > 0 else { return [] }
        let urls = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return urls
            .filter { !ignored.contains($0.lastPathComponent) }
            .sorted { (a, b) -> Bool in
                let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if aDir != bDir { return aDir }
                return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            }
            .map { url -> FileNode in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let kids = isDir ? (try? FileNode.tree(at: url, depth: depth - 1, ignored: ignored)) : nil
                return FileNode(
                    id: url.path,
                    name: url.lastPathComponent,
                    url: url,
                    isDirectory: isDir,
                    children: kids
                )
            }
    }
}
