import SwiftUI
import AppKit
import Splash
import AtomPalette

/// Plain-text editor backed by `NSTextView`. Used for inline file
/// editing inside the diff and files tabs so users don't have to bounce
/// out to a separate IDE for quick changes.
///
/// Scope is deliberately small for a v1: monospace font, native find
/// bar, undo/redo, theming from AtomPalette, and a one-shot Splash
/// highlight on initial load for `.swift` files (live re-highlighting
/// while typing is deferred — it fights with the caret + selection on
/// every keystroke). Save is driven by the host view via the Save
/// button next to the editor; the editor itself doesn't touch disk.
///
/// Cmd+click on an identifier fires `onJumpToSymbol` so the host can
/// resolve it (we use a `git grep` for definitions in FilesTab).
public struct CodeEditorView: NSViewRepresentable {
    @Binding public var text: String
    public var fileExtension: String
    public var isEditable: Bool
    public var fontSize: CGFloat
    /// Fires when the user Cmd+clicks an identifier. Argument is the
    /// word under the cursor. Pass `nil` to disable click-to-jump.
    public var onJumpToSymbol: ((String) -> Void)?
    /// When set to a non-nil value, the editor scrolls to that 1-based
    /// line and clears the request. Bind via `@State` in the host.
    @Binding public var scrollToLine: Int?

    public init(
        text: Binding<String>,
        fileExtension: String = "",
        isEditable: Bool = true,
        fontSize: CGFloat = 13,
        onJumpToSymbol: ((String) -> Void)? = nil,
        scrollToLine: Binding<Int?> = .constant(nil)
    ) {
        self._text = text
        self.fileExtension = fileExtension
        self.isEditable = isEditable
        self.fontSize = fontSize
        self.onJumpToSymbol = onJumpToSymbol
        self._scrollToLine = scrollToLine
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = false
        scroll.borderType = .noBorder

        let textView = JumpableTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
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
        textView.minSize = .zero
        textView.maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.string = text
        applyTheme(textView)
        applyHighlightIfPossible(textView)

        scroll.documentView = textView
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? JumpableTextView else { return }
        textView.isEditable = isEditable
        textView.coordinator = context.coordinator
        context.coordinator.parent = self

        applyTheme(textView)

        // Only push text in from the binding when the host swapped to a
        // different file — avoid clobbering the caret on every keystroke
        // while the user types.
        if textView.string != text && context.coordinator.lastSeen != text {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
            context.coordinator.lastSeen = text
            applyHighlightIfPossible(textView)
        }

        if let target = scrollToLine {
            DispatchQueue.main.async {
                scrollTextView(textView, to: target)
                self.scrollToLine = nil
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Theming

    private func applyTheme(_ textView: NSTextView) {
        let isDark = (textView.effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil)
        let bg = NSColor(atomPair: AtomHex.bgBase, dark: isDark)
        let fg = NSColor(atomPair: AtomHex.fg, dark: isDark)
        let caret = NSColor(atomPair: AtomHex.purple, dark: isDark)
        let selection = NSColor(atomPair: AtomHex.bgSelection, dark: isDark)
        textView.backgroundColor = bg
        textView.drawsBackground = true
        textView.textColor = fg
        textView.insertionPointColor = caret
        textView.selectedTextAttributes = [
            .backgroundColor: selection,
            .foregroundColor: fg
        ]
        if let scroll = textView.enclosingScrollView {
            scroll.backgroundColor = bg
            scroll.drawsBackground = true
        }
    }

    private func applyHighlightIfPossible(_ textView: NSTextView) {
        guard fileExtension.lowercased() == "swift", let storage = textView.textStorage else { return }
        let highlighter = SyntaxHighlighter(format: AttributedStringOutputFormat(theme: AtomSplashTheme.current()))
        let attr = highlighter.highlight(textView.string)
        let selection = textView.selectedRanges
        storage.beginEditing()
        storage.setAttributedString(attr)
        storage.endEditing()
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.selectedRanges = selection
    }

    private func scrollTextView(_ textView: NSTextView, to line: Int) {
        guard line > 0 else { return }
        let nsString = textView.string as NSString
        var currentLine = 1
        var index = 0
        while currentLine < line && index < nsString.length {
            let next = nsString.range(of: "\n", options: [], range: NSRange(location: index, length: nsString.length - index))
            if next.location == NSNotFound { break }
            index = next.location + 1
            currentLine += 1
        }
        let lineRange = nsString.lineRange(for: NSRange(location: min(index, nsString.length), length: 0))
        textView.scrollRangeToVisible(lineRange)
        textView.selectedRange = NSRange(location: lineRange.location, length: 0)
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
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newValue
            }
        }

        func didCmdClick(at word: String) {
            parent.onJumpToSymbol?(word)
        }
    }
}

/// NSTextView subclass that converts Cmd+click on a word into a
/// `Coordinator.didCmdClick(at:)` callback. Regular clicks fall through
/// to the default behaviour.
final class JumpableTextView: NSTextView {
    weak var coordinator: CodeEditorView.Coordinator?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let coordinator {
            let point = convert(event.locationInWindow, from: nil)
            let containerPoint = NSPoint(
                x: point.x - textContainerOrigin.x,
                y: point.y - textContainerOrigin.y
            )
            guard let container = textContainer, let storage = textStorage else {
                super.mouseDown(with: event)
                return
            }
            let glyphIndex = layoutManager?.glyphIndex(for: containerPoint, in: container) ?? NSNotFound
            if glyphIndex != NSNotFound {
                let charIndex = layoutManager?.characterIndexForGlyph(at: glyphIndex) ?? NSNotFound
                if charIndex < storage.length,
                   let wordRange = wordRange(at: charIndex, in: storage.string) {
                    let word = (storage.string as NSString).substring(with: wordRange)
                    coordinator.didCmdClick(at: word)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    private func wordRange(at index: Int, in string: String) -> NSRange? {
        let ns = string as NSString
        let validChars = CharacterSet(charactersIn: "_$").union(.alphanumerics)
        var start = index
        var end = index
        while start > 0 {
            let prev = ns.substring(with: NSRange(location: start - 1, length: 1))
            if prev.unicodeScalars.allSatisfy(validChars.contains) {
                start -= 1
            } else { break }
        }
        while end < ns.length {
            let next = ns.substring(with: NSRange(location: end, length: 1))
            if next.unicodeScalars.allSatisfy(validChars.contains) {
                end += 1
            } else { break }
        }
        if end <= start { return nil }
        let range = NSRange(location: start, length: end - start)
        let word = ns.substring(with: range)
        // Reject leading-digit words (numbers) — we only want identifiers.
        guard let first = word.first, !first.isNumber else { return nil }
        return range
    }
}

private extension NSColor {
    convenience init(atomPair: AtomHex.Pair, dark: Bool) {
        let hex = dark ? atomPair.dark : atomPair.light
        let (r, g, b) = HexToRGB.rgb(hex)
        self.init(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }
}

