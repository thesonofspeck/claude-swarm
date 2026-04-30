import SwiftUI
import AppCore
import PersistenceKit

struct FilesTab: View {
    @EnvironmentObject var env: AppEnvironment
    let session: Session

    @State private var entries: [FileNode] = []
    @State private var selection: FileNode.ID?
    @State private var fileContents: String = ""
    @State private var loadingFile = false
    @State private var error: String?

    var body: some View {
        HSplitView {
            tree
                .frame(minWidth: 240, idealWidth: 280)
            preview
        }
        .task(id: session.id) { await loadTree() }
    }

    private var tree: some View {
        List(entries, children: \.children, selection: $selection) { node in
            HStack(spacing: 6) {
                Image(systemName: node.isDirectory ? "folder" : "doc.text")
                    .foregroundStyle(.secondary)
                Text(node.name)
                    .lineLimit(1)
            }
            .tag(Optional(node.id))
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, newValue in
            guard let id = newValue, let node = find(id, in: entries), !node.isDirectory else {
                fileContents = ""
                return
            }
            Task { await loadFile(node.url) }
        }
    }

    private var preview: some View {
        Group {
            if let error {
                ContentUnavailableView(
                    "Couldn't read file",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if loadingFile {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if fileContents.isEmpty {
                ContentUnavailableView(
                    "No file selected",
                    systemImage: "doc.text",
                    description: Text("Pick a file from the tree to preview it.")
                )
            } else {
                ScrollView {
                    Text(fileContents)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadTree() async {
        let root = URL(fileURLWithPath: session.worktreePath)
        let nodes = await Task.detached { try? FileNode.tree(at: root, depth: 6) }.value ?? []
        await MainActor.run { entries = nodes }
    }

    private func loadFile(_ url: URL) async {
        await MainActor.run { loadingFile = true; error = nil }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs[.size] as? Int ?? 0
            if size > 1_000_000 {
                await MainActor.run {
                    fileContents = ""
                    error = "File is \(size / 1024) KiB — too large to preview here. Open it in your editor."
                    loadingFile = false
                }
                return
            }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                await MainActor.run {
                    fileContents = ""
                    error = "Binary file — preview not supported."
                    loadingFile = false
                }
                return
            }
            await MainActor.run {
                fileContents = text
                loadingFile = false
            }
        } catch {
            await MainActor.run {
                self.error = "\(error.localizedDescription)"
                loadingFile = false
            }
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
        return try urls
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
