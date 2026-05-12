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

    private var isSwift: Bool { fileExtension == "swift" }

    private func highlightedSwift(_ source: String) -> AttributedString? {
        let highlighter = SyntaxHighlighter(format: AttributedStringOutputFormat(theme: AtomSplashTheme.current()))
        let attr = highlighter.highlight(source)
        return try? AttributedString(attr, including: \.appKit)
    }

    var body: some View {
        HSplitView {
            tree
                .frame(minWidth: 240, idealWidth: 280)
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
                    isEditable: true
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
