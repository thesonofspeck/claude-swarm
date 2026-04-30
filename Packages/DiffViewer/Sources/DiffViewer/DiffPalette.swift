import SwiftUI
import AppKit
import AtomPalette

/// SwiftUI Color tokens for the diff renderer. Hex values come from the
/// shared AtomPalette package so the diff colours stay in sync with the
/// app's main palette.
public enum DiffPalette {
    public static let bg            = dyn(AtomHex.bgBase)
    public static let sidebar       = dyn(AtomHex.bgSidebar)
    public static let divider       = dyn(AtomHex.divider)
    public static let hunkHeaderBg  = dyn(AtomHex.bgRaised)

    public static let fg            = dyn(AtomHex.fg)
    public static let fgBright      = dyn(AtomHex.fgBright)
    public static let muted         = dyn(AtomHex.fgMuted)

    public static let added         = dyn(AtomHex.green)
    public static let removed       = dyn(AtomHex.red)

    public static let addedBg       = dyn(AtomHex.green, alpha: AtomHex.translucentAlpha)
    public static let removedBg     = dyn(AtomHex.red,   alpha: AtomHex.translucentAlpha)

    private static func dyn(_ pair: AtomHex.Pair, alpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            return NSColor(hex: isDark ? pair.dark : pair.light, alpha: alpha)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        let (r, g, b) = HexToRGB.rgb(hex)
        self.init(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(alpha))
    }
}
