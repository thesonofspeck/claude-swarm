import SwiftUI
import GitKit

public struct DiffView: View {
    public let files: [DiffFile]
    public let worktreeRoot: URL?
    public let onSaved: ((URL) -> Void)?
    @State private var selectedFileIndex: Int = 0

    public init(
        files: [DiffFile],
        worktreeRoot: URL? = nil,
        onSaved: ((URL) -> Void)? = nil
    ) {
        self.files = files
        self.worktreeRoot = worktreeRoot
        self.onSaved = onSaved
    }

    public var body: some View {
        if files.isEmpty {
            DiffEmptyView()
        } else {
            HSplitView {
                fileList
                    .frame(minWidth: 240, idealWidth: 280)
                if let file = files[safe: selectedFileIndex] {
                    DiffFileView(
                        file: file,
                        worktreeRoot: worktreeRoot,
                        onSaved: onSaved
                    )
                } else {
                    Text("Select a file")
                        .foregroundStyle(DiffPalette.muted)
                }
            }
        }
    }

    private var fileList: some View {
        List(files.indices, id: \.self, selection: $selectedFileIndex) { idx in
            let file = files[idx]
            HStack(spacing: 8) {
                Image(systemName: file.isBinary ? "doc" : "doc.text")
                    .foregroundStyle(DiffPalette.muted)
                    .imageScale(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.newPath ?? file.oldPath ?? "—")
                        .font(.callout)
                        .foregroundStyle(DiffPalette.fg)
                        .lineLimit(1)
                    let added = file.hunks.flatMap(\.lines).filter { $0.kind == .addition }.count
                    let removed = file.hunks.flatMap(\.lines).filter { $0.kind == .deletion }.count
                    HStack(spacing: 6) {
                        Text("+\(added)")
                            .foregroundStyle(DiffPalette.added)
                            .font(.caption2.monospacedDigit())
                        Text("−\(removed)")
                            .foregroundStyle(DiffPalette.removed)
                            .font(.caption2.monospacedDigit())
                    }
                }
            }
            .tag(idx)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(DiffPalette.sidebar)
    }
}

struct DiffEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(DiffPalette.added.opacity(0.10))
                    .frame(width: 96, height: 96)
                Circle()
                    .strokeBorder(DiffPalette.added.opacity(0.20), lineWidth: 1)
                    .frame(width: 124, height: 124)
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(DiffPalette.added)
            }
            VStack(spacing: 4) {
                Text("Working tree is clean")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(DiffPalette.fgBright)
                Text("No changes against the base branch.")
                    .font(.body)
                    .foregroundStyle(DiffPalette.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DiffPalette.bg)
    }
}

struct DiffFileView: View {
    let file: DiffFile
    let worktreeRoot: URL?
    let onSaved: ((URL) -> Void)?

    @State private var editing = false
    @State private var fileText: String = ""
    @State private var loadedFromURL: URL?
    @State private var dirty = false
    @State private var saving = false
    @State private var loadError: String?

    private var canEdit: Bool {
        worktreeRoot != nil
            && !file.isBinary
            && (file.newPath ?? file.oldPath) != nil
    }

    private var resolvedURL: URL? {
        guard let root = worktreeRoot, let rel = file.newPath ?? file.oldPath else { return nil }
        return root.appendingPathComponent(rel)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if editing {
                editorBody
            } else {
                diffBody
            }
        }
        .background(DiffPalette.bg)
    }

    private var diffBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
                    hunkView(hunk)
                }
            }
        }
    }

    private var editorBody: some View {
        Group {
            if let error = loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(DiffPalette.removed)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(DiffPalette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CodeEditorView(
                    text: Binding(
                        get: { fileText },
                        set: { newValue in
                            fileText = newValue
                            dirty = true
                        }
                    ),
                    fileExtension: (file.newPath ?? file.oldPath ?? "").components(separatedBy: ".").last ?? "",
                    isEditable: true
                )
            }
        }
        .task(id: resolvedURL?.path) { loadFileIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(file.newPath ?? file.oldPath ?? "—")
                .font(.callout.weight(.semibold))
                .foregroundStyle(DiffPalette.fgBright)
            Spacer()
            if file.isBinary {
                Text("Binary").foregroundStyle(DiffPalette.muted).font(.caption)
            }
            if canEdit {
                if editing {
                    if saving {
                        ProgressView().controlSize(.small)
                    }
                    Button {
                        save()
                    } label: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!dirty || saving)
                    Button {
                        cancelEdit()
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DiffPalette.sidebar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DiffPalette.divider).frame(height: 0.5)
        }
    }

    private func loadFileIfNeeded() {
        guard editing, let url = resolvedURL else { return }
        if loadedFromURL?.path == url.path && !dirty { return }
        loadError = nil
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs[.size] as? Int ?? 0
            if size > 1_000_000 {
                loadError = "File is \(size / 1024) KiB — too large to edit here. Open it in your editor."
                return
            }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                loadError = "Binary file — preview not supported."
                return
            }
            fileText = text
            loadedFromURL = url
            dirty = false
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        guard let url = resolvedURL else { return }
        saving = true
        defer { saving = false }
        do {
            try fileText.write(to: url, atomically: true, encoding: .utf8)
            dirty = false
            onSaved?(url)
        } catch {
            loadError = "Save failed: \(error.localizedDescription)"
        }
    }

    private func cancelEdit() {
        // If the user has unsaved changes, drop them — pulse-driven
        // diff refresh would clobber on next reload anyway. Confirmation
        // dialog can be added if this becomes painful in practice.
        editing = false
        dirty = false
        loadedFromURL = nil
        fileText = ""
    }

    private func hunkView(_ hunk: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(DiffPalette.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DiffPalette.hunkHeaderBg)

            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                lineRow(line)
            }
        }
    }

    private func lineRow(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            gutter(text: line.oldNumber.map(String.init) ?? "")
            gutter(text: line.newNumber.map(String.init) ?? "")
            HStack(spacing: 0) {
                Text(prefixSymbol(line.kind))
                    .foregroundStyle(prefixColor(line.kind))
                Text(line.text)
                    .foregroundStyle(DiffPalette.fg)
            }
            .font(.system(.body, design: .monospaced))
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(rowBackground(line.kind))
    }

    private func gutter(text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .frame(width: 44, alignment: .trailing)
            .padding(.horizontal, 4)
            .foregroundStyle(DiffPalette.muted)
    }

    private func prefixSymbol(_ kind: DiffLineKind) -> String {
        switch kind {
        case .addition: return "+ "
        case .deletion: return "− "
        case .context, .hunkHeader, .fileHeader: return "  "
        }
    }

    private func prefixColor(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: return DiffPalette.added
        case .deletion: return DiffPalette.removed
        default: return DiffPalette.muted
        }
    }

    private func rowBackground(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: return DiffPalette.addedBg
        case .deletion: return DiffPalette.removedBg
        default: return .clear
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
