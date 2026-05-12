import SwiftUI
import AppKit
import Splash

/// Plain-text editor backed by `NSTextView`. Used for inline file
/// editing inside the diff and files tabs so users don't have to bounce
/// out to a separate IDE for quick changes.
///
/// Scope is deliberately small for a v1: monospace font, native find
/// bar, undo/redo, and a one-shot Splash highlight on initial load for
/// `.swift` files (live re-highlighting while typing is deferred — it
/// fights with the caret + selection on every keystroke). Save is
/// driven by the host view via the Save button next to the editor; the
/// editor itself doesn't touch disk.
public struct CodeEditorView: NSViewRepresentable {
    @Binding public var text: String
    public var fileExtension: String
    public var isEditable: Bool
    public var fontSize: CGFloat

    public init(
        text: Binding<String>,
        fileExtension: String = "",
        isEditable: Bool = true,
        fontSize: CGFloat = 13
    ) {
        self._text = text
        self.fileExtension = fileExtension
        self.isEditable = isEditable
        self.fontSize = fontSize
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }

        textView.delegate = context.coordinator
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.string = text
        applyHighlightIfPossible(textView)
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        textView.isEditable = isEditable

        // Only push text in from the binding when the host swapped to a
        // different file — avoid clobbering the caret on every keystroke
        // while the user types. Coordinator's lastSeen tracks the value
        // SwiftUI most recently observed from us.
        if textView.string != text && context.coordinator.lastSeen != text {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
            context.coordinator.lastSeen = text
            applyHighlightIfPossible(textView)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applyHighlightIfPossible(_ textView: NSTextView) {
        guard fileExtension.lowercased() == "swift", let storage = textView.textStorage else { return }
        let highlighter = SyntaxHighlighter(format: AttributedStringOutputFormat(theme: AtomSplashTheme.current()))
        let attr = highlighter.highlight(textView.string)
        // Preserve caret/selection across the storage swap.
        let selection = textView.selectedRanges
        storage.beginEditing()
        storage.setAttributedString(attr)
        storage.endEditing()
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.selectedRanges = selection
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        var lastSeen: String = ""

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newValue = textView.string
            lastSeen = newValue
            // Bounce to the next runloop tick so SwiftUI doesn't re-enter
            // updateNSView mid-edit.
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newValue
            }
        }
    }
}
