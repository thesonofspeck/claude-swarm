import SwiftUI
import AppCore
import KubectlKit

/// Streaming `kubectl logs -f` viewer. Opens from the pod row in
/// DeployTab. Auto-scrolls to bottom while following; the user can
/// scroll up to break the auto-follow.
struct PodLogsSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let pod: String
    let container: String?
    let context: String?
    let namespace: String?

    @State private var lines: [LogLine] = []
    @State private var task: Task<Void, Never>?
    @State private var following: Bool = true
    @State private var error: String?
    @State private var paused: Bool = false
    @State private var pendingBuffer: String = ""

    private static let maxLines = 5_000

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Palette.divider)
            logBody
            Divider().background(Palette.divider)
            footer
        }
        .frame(width: 880, height: 620)
        .background(Palette.bgBase)
        .task { startStreaming() }
        .onDisappear { task?.cancel() }
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "terminal")
                .foregroundStyle(Palette.cyan)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(pod)
                    .font(Type.body.weight(.semibold))
                    .foregroundStyle(Palette.fgBright)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let container { Pill(text: container, systemImage: "shippingbox", tint: Palette.fgMuted) }
                    if let namespace { Pill(text: namespace, systemImage: "tag", tint: Palette.fgMuted) }
                    if paused {
                        Pill(text: "Paused", systemImage: "pause.fill", tint: Palette.orange)
                    } else if task != nil {
                        Pill(text: "Following", systemImage: "dot.radiowaves.left.and.right", tint: Palette.green)
                    }
                }
            }
            Spacer()
            Button {
                togglePause()
            } label: {
                Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.bordered)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(lines.map(\.text).joined(separator: "\n"), forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            Button(role: .destructive) {
                lines.removeAll()
                pendingBuffer = ""
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(Metrics.Space.md)
    }

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(Type.mono)
                            .foregroundStyle(Palette.fg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.horizontal, Metrics.Space.md)
                            .padding(.vertical, 1)
                    }
                    Color.clear.frame(height: 1).id("__bottom__")
                }
            }
            .background(Palette.bgBase)
            .onChange(of: lines.count) { _, _ in
                guard following else { return }
                withAnimation(.linear(duration: 0.05)) {
                    proxy.scrollTo("__bottom__", anchor: .bottom)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.red)
                    .lineLimit(2)
                    .truncationMode(.middle)
            } else {
                Text("\(lines.count) lines")
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
            }
            Spacer()
            Toggle("Auto-scroll", isOn: $following)
                .toggleStyle(.checkbox)
                .controlSize(.small)
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(Metrics.Space.md)
    }

    // MARK: - Streaming

    private func startStreaming() {
        let kubectl = env.kubectl
        let pod = self.pod
        let container = self.container
        let context = self.context
        let namespace = self.namespace
        task?.cancel()
        task = Task { @MainActor in
            do {
                let stream = kubectl.streamLogs(
                    pod: pod, container: container,
                    context: context, namespace: namespace, tail: 500
                )
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    if paused { pendingBuffer += chunk } else { append(chunk) }
                }
            } catch {
                self.error = "\(error.localizedDescription)"
            }
        }
    }

    private func append(_ chunk: String) {
        let newLines = chunk
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { LogLine(text: String($0)) }
        lines.append(contentsOf: newLines)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }

    private func togglePause() {
        paused.toggle()
        if !paused, !pendingBuffer.isEmpty {
            append(pendingBuffer)
            pendingBuffer = ""
        }
    }
}

/// One log line with a stable identity so trimming the 5k-line buffer
/// doesn't reshuffle every row's id and force a full LazyVStack rebuild.
struct LogLine: Identifiable {
    let id = UUID()
    let text: String
}
