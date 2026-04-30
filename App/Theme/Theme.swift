import SwiftUI
import AppKit

/// Atom One palette — Light when the system is in Light Appearance, Dark when
/// it's in Dark. Each `Palette` token exposes a SwiftUI `Color` whose value
/// resolves dynamically from an underlying `NSColor` so the same token works
/// in light and dark without per-view `colorScheme` checks.
public enum Palette {
    // Surfaces (back to front)
    public static let bgDeep        = dynamic(light: 0xF5F5F5, dark: 0x181A1F) // window edge / divider
    public static let bgSidebar     = dynamic(light: 0xF0F0F0, dark: 0x21252B) // sidebar / inspector
    public static let bgBase        = dynamic(light: 0xFAFAFA, dark: 0x282C34) // editor / detail
    public static let bgRaised      = dynamic(light: 0xFFFFFF, dark: 0x2C313A) // cards / hover
    public static let bgSelection   = dynamic(light: 0xE5E5E6, dark: 0x3E4451) // selected row / line
    public static let divider       = dynamic(light: 0xDCDDE0, dark: 0x181A1F)

    // Text
    public static let fg            = dynamic(light: 0x383A42, dark: 0xABB2BF) // primary
    public static let fgMuted       = dynamic(light: 0xA0A1A7, dark: 0x5C6370) // secondary / comments
    public static let fgBright      = dynamic(light: 0x202227, dark: 0xE5E5E5) // headlines

    // Syntax / accents (the ones every Atom theme is famous for)
    public static let blue          = dynamic(light: 0x4078F2, dark: 0x61AFEF) // accent / functions
    public static let purple        = dynamic(light: 0xA626A4, dark: 0xC678DD) // keywords
    public static let red           = dynamic(light: 0xE45649, dark: 0xE06C75) // errors / deletions
    public static let orange        = dynamic(light: 0x986801, dark: 0xD19A66) // numbers / constants
    public static let yellow        = dynamic(light: 0xC18401, dark: 0xE5C07B) // classes / warnings
    public static let green         = dynamic(light: 0x50A14F, dark: 0x98C379) // strings / additions
    public static let cyan          = dynamic(light: 0x0184BC, dark: 0x56B6C2) // regex / escapes

    // Translucent overlays (for diff hunks, status pills, hover backgrounds)
    public static let addBg         = dynamic(light: 0x50A14F, dark: 0x98C379, alpha: 0.14)
    public static let delBg         = dynamic(light: 0xE45649, dark: 0xE06C75, alpha: 0.14)
    public static let warnBg        = dynamic(light: 0xC18401, dark: 0xE5C07B, alpha: 0.18)
    public static let pillBg        = dynamic(light: 0x000000, dark: 0xFFFFFF, alpha: 0.06)

    private static func dynamic(light lightHex: UInt32, dark darkHex: UInt32, alpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            return NSColor(hex: isDark ? darkHex : lightHex, alpha: alpha)
        })
    }
}

/// Cross-cutting layout tokens. Use these instead of magic numbers so the
/// look stays cohesive when we want to tighten/loosen the whole UI later.
public enum Metrics {
    public enum Space {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
    }
    public enum Radius {
        public static let sm: CGFloat = 4
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 12
        public static let pill: CGFloat = 999
    }
    public enum Stroke {
        public static let hairline: CGFloat = 0.5
        public static let regular: CGFloat = 1
    }
}

public enum Motion {
    public static let quick: Animation = .easeInOut(duration: 0.18)
    public static let spring: Animation = .spring(response: 0.32, dampingFraction: 0.82)
    public static let pulse: Animation = .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
}

public enum Type {
    public static let display = Font.system(.largeTitle, design: .default).weight(.semibold)
    public static let title   = Font.system(.title2, design: .default).weight(.semibold)
    public static let heading = Font.system(.headline, design: .default)
    public static let body    = Font.system(.body, design: .default)
    public static let mono    = Font.system(.body, design: .monospaced)
    public static let caption = Font.system(.caption, design: .default)
    public static let monoCaption = Font.system(.caption, design: .monospaced)
    public static let label = Font.system(.caption2, design: .default).weight(.semibold)
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >>  8) & 0xFF) / 255
        let b = CGFloat( hex        & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: CGFloat(alpha))
    }
}
