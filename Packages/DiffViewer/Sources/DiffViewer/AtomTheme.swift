import Foundation
import AppKit
import Splash
import AtomPalette

/// Atom One Light + Dark Splash themes. Hex values come from the shared
/// AtomPalette package.
public enum AtomSplashTheme {
    @MainActor
    public static func current() -> Splash.Theme {
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark ? dark() : light()
    }

    public static func dark() -> Splash.Theme {
        Theme(
            font: Font(size: 13),
            plainTextColor: ns(AtomHex.fg.dark),
            tokenColors: [
                .keyword:        ns(AtomHex.purple.dark),
                .string:         ns(AtomHex.green.dark),
                .type:           ns(AtomHex.yellow.dark),
                .call:           ns(AtomHex.blue.dark),
                .number:         ns(AtomHex.orange.dark),
                .comment:        ns(AtomHex.fgMuted.dark),
                .property:       ns(AtomHex.red.dark),
                .dotAccess:      ns(AtomHex.blue.dark),
                .preprocessing:  ns(AtomHex.purple.dark)
            ],
            backgroundColor: ns(AtomHex.bgBase.dark)
        )
    }

    public static func light() -> Splash.Theme {
        Theme(
            font: Font(size: 13),
            plainTextColor: ns(AtomHex.fg.light),
            tokenColors: [
                .keyword:        ns(AtomHex.purple.light),
                .string:         ns(AtomHex.green.light),
                .type:           ns(AtomHex.yellow.light),
                .call:           ns(AtomHex.blue.light),
                .number:         ns(AtomHex.orange.light),
                .comment:        ns(AtomHex.fgMuted.light),
                .property:       ns(AtomHex.red.light),
                .dotAccess:      ns(AtomHex.blue.light),
                .preprocessing:  ns(AtomHex.purple.light)
            ],
            backgroundColor: ns(AtomHex.bgBase.light)
        )
    }

    private static func ns(_ hex: UInt32) -> Splash.Color {
        let (r, g, b) = HexToRGB.rgb(hex)
        return NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }
}
