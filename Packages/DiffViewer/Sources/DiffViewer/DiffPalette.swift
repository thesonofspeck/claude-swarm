import SwiftUI
import AppKit

/// Atom One palette for diff rendering — duplicates the App-target Theme
/// tokens we need here so the package stays self-contained.
public enum DiffPalette {
    public static let bg            = dynamic(light: 0xFAFAFA, dark: 0x282C34)
    public static let sidebar       = dynamic(light: 0xF0F0F0, dark: 0x21252B)
    public static let divider       = dynamic(light: 0xDCDDE0, dark: 0x181A1F)
    public static let hunkHeaderBg  = dynamic(light: 0xE5E5E6, dark: 0x2C313A)

    public static let fg            = dynamic(light: 0x383A42, dark: 0xABB2BF)
    public static let fgBright      = dynamic(light: 0x202227, dark: 0xE5E5E5)
    public static let muted         = dynamic(light: 0xA0A1A7, dark: 0x5C6370)

    public static let added         = dynamic(light: 0x50A14F, dark: 0x98C379)
    public static let removed       = dynamic(light: 0xE45649, dark: 0xE06C75)

    public static let addedBg       = dynamic(light: 0x50A14F, dark: 0x98C379, alpha: 0.14)
    public static let removedBg     = dynamic(light: 0xE45649, dark: 0xE06C75, alpha: 0.14)

    private static func dynamic(light lightHex: UInt32, dark darkHex: UInt32, alpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            return NSColor(hex: isDark ? darkHex : lightHex, alpha: alpha)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >>  8) & 0xFF) / 255
        let b = CGFloat( hex        & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: CGFloat(alpha))
    }
}
