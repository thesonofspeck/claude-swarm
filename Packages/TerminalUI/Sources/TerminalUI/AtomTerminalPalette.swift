import Foundation
import AppKit
import SwiftTerm
import AtomPalette

/// Atom One Light + Dark 16-color ANSI palettes for the embedded terminal.
/// Hex values come from the shared AtomPalette package.
public enum AtomTerminalPalette {
    public static func currentColors() -> [SwiftTerm.Color] {
        isDarkAppearance() ? darkColors : lightColors
    }

    public static func currentBackground() -> NSColor {
        ns(isDarkAppearance() ? AtomHex.bgBase.dark : AtomHex.bgBase.light)
    }

    public static func currentForeground() -> NSColor {
        ns(isDarkAppearance() ? AtomHex.fg.dark : AtomHex.fg.light)
    }

    public static func currentCursor() -> NSColor {
        ns(isDarkAppearance() ? AtomHex.blue.dark : AtomHex.blue.light)
    }

    public static func currentSelection() -> NSColor {
        ns(isDarkAppearance() ? AtomHex.bgSelection.dark : AtomHex.bgSelection.light)
    }

    private static func isDarkAppearance() -> Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
    }

    /// Standard ANSI 16: 0..7 are normal, 8..15 are bright. Maps roughly
    /// to the Atom palette: black/red/green/yellow/blue/magenta/cyan/white.
    private static let darkColors: [SwiftTerm.Color] = [
        st(AtomHex.bgBase.dark),
        st(AtomHex.red.dark),
        st(AtomHex.green.dark),
        st(AtomHex.yellow.dark),
        st(AtomHex.blue.dark),
        st(AtomHex.purple.dark),
        st(AtomHex.cyan.dark),
        st(AtomHex.fg.dark),
        st(AtomHex.fgMuted.dark),
        st(AtomHex.red.dark),
        st(AtomHex.green.dark),
        st(AtomHex.yellow.dark),
        st(AtomHex.blue.dark),
        st(AtomHex.purple.dark),
        st(AtomHex.cyan.dark),
        st(0xFFFFFF)
    ]

    private static let lightColors: [SwiftTerm.Color] = [
        st(AtomHex.fg.light),
        st(AtomHex.red.light),
        st(AtomHex.green.light),
        st(AtomHex.yellow.light),
        st(AtomHex.blue.light),
        st(AtomHex.purple.light),
        st(AtomHex.cyan.light),
        st(AtomHex.bgBase.light),
        st(AtomHex.fgMuted.light),
        st(AtomHex.red.light),
        st(AtomHex.green.light),
        st(AtomHex.yellow.light),
        st(AtomHex.blue.light),
        st(AtomHex.purple.light),
        st(AtomHex.cyan.light),
        st(0xFFFFFF)
    ]

    private static func st(_ hex: UInt32) -> SwiftTerm.Color {
        let r = UInt16((hex >> 16) & 0xFF) * 0x101
        let g = UInt16((hex >>  8) & 0xFF) * 0x101
        let b = UInt16( hex        & 0xFF) * 0x101
        return SwiftTerm.Color(red: r, green: g, blue: b)
    }

    private static func ns(_ hex: UInt32) -> NSColor {
        let (r, g, b) = HexToRGB.rgb(hex)
        return NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }
}
