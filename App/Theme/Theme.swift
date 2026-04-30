import SwiftUI
import AppKit
import AtomPalette

/// Atom One palette as SwiftUI Colors that resolve per system appearance.
/// Hex values come from AtomPalette so iOS, the diff viewer, the
/// terminal, and the icon generator all stay in lockstep.
public enum Palette {
    public static let bgDeep        = dyn(AtomHex.bgDeep)
    public static let bgSidebar     = dyn(AtomHex.bgSidebar)
    public static let bgBase        = dyn(AtomHex.bgBase)
    public static let bgRaised      = dyn(AtomHex.bgRaised)
    public static let bgSelection   = dyn(AtomHex.bgSelection)
    public static let divider       = dyn(AtomHex.divider)

    public static let fg            = dyn(AtomHex.fg)
    public static let fgMuted       = dyn(AtomHex.fgMuted)
    public static let fgBright      = dyn(AtomHex.fgBright)

    public static let blue          = dyn(AtomHex.blue)
    public static let purple        = dyn(AtomHex.purple)
    public static let red           = dyn(AtomHex.red)
    public static let orange        = dyn(AtomHex.orange)
    public static let yellow        = dyn(AtomHex.yellow)
    public static let green         = dyn(AtomHex.green)
    public static let cyan          = dyn(AtomHex.cyan)

    public static let addBg   = dyn(AtomHex.green, alpha: AtomHex.translucentAlpha)
    public static let delBg   = dyn(AtomHex.red,   alpha: AtomHex.translucentAlpha)
    public static let warnBg  = dyn(AtomHex.yellow, alpha: AtomHex.warningAlpha)
    public static let pillBg  = dyn(AtomHex.Pair(light: 0x000000, dark: 0xFFFFFF), alpha: AtomHex.pillAlpha)

    private static func dyn(_ pair: AtomHex.Pair, alpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            return NSColor(hex: isDark ? pair.dark : pair.light, alpha: alpha)
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
        let (r, g, b) = HexToRGB.rgb(hex)
        self.init(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(alpha))
    }
}
