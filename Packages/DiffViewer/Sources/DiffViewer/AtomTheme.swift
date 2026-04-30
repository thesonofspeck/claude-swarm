import Foundation
import AppKit
import Splash

/// Atom One Light + Dark Splash themes. Splash configures highlight colors
/// per token type via `Theme`; we resolve the right hex per appearance at
/// build time.
public enum AtomSplashTheme {
    public static func current() -> Splash.Theme {
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark ? dark() : light()
    }

    public static func dark() -> Splash.Theme {
        Theme(
            font: Font(size: 13),
            plainTextColor: ns(0xABB2BF),
            tokenColors: [
                .keyword:        ns(0xC678DD),
                .string:         ns(0x98C379),
                .type:           ns(0xE5C07B),
                .call:           ns(0x61AFEF),
                .number:         ns(0xD19A66),
                .comment:        ns(0x5C6370),
                .property:       ns(0xE06C75),
                .dotAccess:      ns(0x61AFEF),
                .preprocessing:  ns(0xC678DD)
            ],
            backgroundColor: ns(0x282C34)
        )
    }

    public static func light() -> Splash.Theme {
        Theme(
            font: Font(size: 13),
            plainTextColor: ns(0x383A42),
            tokenColors: [
                .keyword:        ns(0xA626A4),
                .string:         ns(0x50A14F),
                .type:           ns(0xC18401),
                .call:           ns(0x4078F2),
                .number:         ns(0x986801),
                .comment:        ns(0xA0A1A7),
                .property:       ns(0xE45649),
                .dotAccess:      ns(0x4078F2),
                .preprocessing:  ns(0xA626A4)
            ],
            backgroundColor: ns(0xFAFAFA)
        )
    }

    private static func ns(_ hex: UInt32) -> Splash.Color {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >>  8) & 0xFF) / 255
        let b = CGFloat( hex        & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
