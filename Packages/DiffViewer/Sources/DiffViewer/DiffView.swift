import SwiftUI
import GitKit

public struct DiffView: View {
    public let files: [DiffFile]
    @State private var selectedFileIndex: Int = 0

    public init(files: [DiffFile]) {
        self.files = files
    }

    public var body: some View {
        if files.isEmpty {
            ContentUnavailableView(
                "No changes",
                systemImage: "doc.text.magnifyingglass",
                description: Text("The working tree matches the base branch.")
            )
        } else {
            HSplitView {
                fileList
                    .frame(minWidth: 220, idealWidth: 260)
                if let file = files[safe: selectedFileIndex] {
                    DiffFileView(file: file)
                } else {
                    Text("Select a file")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var fileList: some View {
        List(files.indices, id: \.self, selection: $selectedFileIndex) { idx in
            let file = files[idx]
            HStack(spacing: 8) {
                Image(systemName: file.isBinary ? "doc" : "doc.text")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.newPath ?? file.oldPath ?? "—")
                        .font(.callout)
                        .lineLimit(1)
                    let added = file.hunks.flatMap(\.lines).filter { $0.kind == .addition }.count
                    let removed = file.hunks.flatMap(\.lines).filter { $0.kind == .deletion }.count
                    HStack(spacing: 6) {
                        Text("+\(added)").foregroundStyle(.green).font(.caption2.monospacedDigit())
                        Text("-\(removed)").foregroundStyle(.red).font(.caption2.monospacedDigit())
                    }
                }
            }
            .tag(idx)
        }
        .listStyle(.sidebar)
    }
}

struct DiffFileView: View {
    let file: DiffFile

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                header
                ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
                    hunkView(hunk)
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text(file.newPath ?? file.oldPath ?? "—")
                .font(.callout.weight(.semibold))
            Spacer()
            if file.isBinary {
                Text("Binary").foregroundStyle(.secondary).font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func hunkView(_ hunk: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.unemphasizedSelectedContentBackgroundColor))

            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                lineRow(line)
            }
        }
    }

    private func lineRow(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            gutter(text: line.oldNumber.map(String.init) ?? "")
            gutter(text: line.newNumber.map(String.init) ?? "")
            Text(prefixSymbol(line.kind) + line.text)
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
            .foregroundStyle(.secondary)
    }

    private func prefixSymbol(_ kind: DiffLineKind) -> String {
        switch kind {
        case .addition: return "+ "
        case .deletion: return "- "
        case .context, .hunkHeader, .fileHeader: return "  "
        }
    }

    private func rowBackground(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: return Color.green.opacity(0.12)
        case .deletion: return Color.red.opacity(0.12)
        default: return .clear
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
