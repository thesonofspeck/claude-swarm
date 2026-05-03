import SwiftUI
import AppCore
import PersistenceKit

struct TranscriptTab: View {
    let session: Session

    @State private var content: String = ""
    @State private var byteCount: Int = 0
    @State private var error: String?
    @State private var watcher: Any?     // Holds the FileWatcher to keep it alive

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.divider)
            body_
        }
        .background(Palette.bgBase)
        .task(id: session.id) { await load() }
        .onDisappear { watcher = nil }
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "text.alignleft")
                .foregroundStyle(Palette.cyan)
            Text("Transcript")
                .font(Type.heading)
                .foregroundStyle(Palette.fgBright)
            Spacer()
            Text(byteSize(byteCount))
                .font(Type.monoCaption)
                .foregroundStyle(Palette.fgMuted)
            IconButton(systemImage: "arrow.clockwise", help: "Reload") {
                Task { await load() }
            }
            IconButton(systemImage: "doc.on.doc", help: "Copy all") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(content, forType: .string)
            }
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    @ViewBuilder
    private var body_: some View {
        if let error {
            EmptyState(
                title: "Couldn't read transcript",
                systemImage: "exclamationmark.triangle",
                description: error,
                tint: Palette.orange
            )
        } else if content.isEmpty {
            EmptyState(
                title: "Empty transcript",
                systemImage: "text.alignleft",
                description: "This session hasn't produced any output yet.",
                tint: Palette.fgMuted
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(content)
                        .font(Type.mono)
                        .foregroundStyle(Palette.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Metrics.Space.md)
                        .textSelection(.enabled)
                        .id("end")
                }
                .onChange(of: content) { _, _ in
                    withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
        }
    }

    private func load() async {
        let url = URL(fileURLWithPath: session.transcriptPath)
        // Read + cap + ANSI-strip on a detached Task so multi-MB
        // transcripts don't stall the main actor.
        let result = await Task.detached { () -> (String, Int, String?) in
            do {
                let raw = try Data(contentsOf: url)
                // Cap to the last 1 MiB BEFORE running the ANSI-strip
                // regex so the regex doesn't have to walk megabytes.
                let max = 1_000_000
                let truncated: Data = raw.count > max ? raw.suffix(max) : raw
                let text = String(decoding: truncated, as: UTF8.self)
                return (ANSIStripper.strip(text), raw.count, nil)
            } catch {
                return ("", 0, error.localizedDescription)
            }
        }.value
        content = result.0
        byteCount = result.1
        error = result.2
    }

    private func byteSize(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}

enum ANSIStripper {
    /// Strip CSI-style ANSI escape sequences. Imperfect — won't handle every
    /// terminal control code — but good enough for human-readable scrollback.
    static func strip(_ s: String) -> String {
        let pattern = "\u{1B}\\[[0-9;?]*[A-Za-z]"
        return s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}
