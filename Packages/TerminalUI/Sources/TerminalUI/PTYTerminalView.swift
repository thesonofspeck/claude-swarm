import SwiftUI
@preconcurrency import SwiftTerm
import SessionCore

/// SwiftUI wrapper around SwiftTerm's `LocalProcessTerminalView`. Owns the
/// PTY that runs the `claude` CLI for one session.
public struct PTYTerminalView: NSViewRepresentable {
    public let spec: SessionSpec
    public let onExit: (Int32) -> Void

    public init(spec: SessionSpec, onExit: @escaping (Int32) -> Void = { _ in }) {
        self.spec = spec
        self.onExit = onExit
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        context.coordinator.recorder = try? TranscriptRecorder(url: spec.transcriptURL)
        context.coordinator.bind(view: view, sessionId: spec.id)

        applyAtomPalette(to: view)

        var env = ProcessInfo.processInfo.environment
        for (k, v) in spec.environment { env[k] = v }
        let envArray = env.map { "\($0)=\($1)" }

        view.startProcess(
            executable: spec.claudeExecutable,
            args: spec.claudeArguments,
            environment: envArray,
            execName: nil
        )

        if let prompt = spec.initialPrompt, !prompt.isEmpty {
            // Structured Task instead of DispatchQueue.asyncAfter so
            // the seed cancels cleanly if the view is torn down before
            // the warmup finishes.
            Task { @MainActor [weak view] in
                try? await Task.sleep(for: .milliseconds(600))
                view?.send(txt: prompt + "\n")
            }
        }
        return view
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        applyAtomPalette(to: nsView)
    }

    private func applyAtomPalette(to view: LocalProcessTerminalView) {
        view.installColors(AtomTerminalPalette.currentColors())
        view.nativeBackgroundColor = AtomTerminalPalette.currentBackground()
        view.nativeForegroundColor = AtomTerminalPalette.currentForeground()
        view.caretColor = AtomTerminalPalette.currentCursor()
        view.selectedTextBackgroundColor = AtomTerminalPalette.currentSelection()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onExit: onExit)
    }

    @MainActor
    public final class Coordinator: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
        let onExit: (Int32) -> Void
        var recorder: TranscriptRecorder?
        weak var view: LocalProcessTerminalView?
        var sessionId: String?
        private var observer: NSObjectProtocol?

        init(onExit: @escaping (Int32) -> Void) {
            self.onExit = onExit
            super.init()
        }

        // Swift 6 isolated deinit: lets us touch the MainActor-isolated
        // `observer` property without crossing into a nonisolated deinit
        // (which is otherwise the default and would refuse to read a
        // non-Sendable NSObjectProtocol).
        isolated deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func bind(view: LocalProcessTerminalView, sessionId: String) {
            self.view = view
            self.sessionId = sessionId
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: Notification.Name("ClaudeSwarm.RemoteInput"),
                    object: nil,
                    queue: .main
                ) { [weak self] note in
                    // Pull only Sendable scalars out of the Notification
                    // before crossing into MainActor — the Notification
                    // value itself isn't Sendable.
                    guard let info = note.userInfo,
                          let id = info["sessionId"] as? String,
                          let text = info["text"] as? String else { return }
                    Task { @MainActor in
                        self?.handleRemoteInput(sessionId: id, text: text)
                    }
                }
            }
        }

        private func handleRemoteInput(sessionId id: String, text: String) {
            guard id == sessionId, let view else { return }
            view.send(txt: text + "\n")
        }

        public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        // The trailing two delegate methods take the base TerminalView,
        // not LocalProcessTerminalView — protocol signature in SwiftTerm.
        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        public func processTerminated(source: TerminalView, exitCode: Int32?) {
            recorder?.close()
            onExit(exitCode ?? -1)
        }
    }
}
