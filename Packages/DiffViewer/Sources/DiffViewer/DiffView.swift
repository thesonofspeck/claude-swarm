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
            DiffEmptyView()
        } else {
            HSplitView {
                fileList
                    .frame(minWidth: 240, idealWidth: 280)
                if let file = files[safe: selectedFileIndex] {
                    DiffFileView(file: file)
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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                header
                ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
                    hunkView(hunk)
                }
            }
        }
        .background(DiffPalette.bg)
    }

    private var header: some View {
        HStack {
            Text(file.newPath ?? file.oldPath ?? "—")
                .font(.callout.weight(.semibold))
                .foregroundStyle(DiffPalette.fgBright)
            Spacer()
            if file.isBinary {
                Text("Binary").foregroundStyle(DiffPalette.muted).font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DiffPalette.sidebar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DiffPalette.divider).frame(height: 0.5)
        }
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
