import Foundation
import AppKit
import SwiftTerm

/// Atom One Light + Dark 16-color ANSI palettes for the embedded terminal.
public enum AtomTerminalPalette {
    public static func currentColors() -> [SwiftTerm.Color] {
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark ? darkColors : lightColors
    }

    public static func currentBackground() -> NSColor {
        isDarkAppearance() ? hex(0x282C34) : hex(0xFAFAFA)
    }

    public static func currentForeground() -> NSColor {
        isDarkAppearance() ? hex(0xABB2BF) : hex(0x383A42)
    }

    public static func currentCursor() -> NSColor {
        isDarkAppearance() ? hex(0x61AFEF) : hex(0x4078F2)
    }

    public static func currentSelection() -> NSColor {
        isDarkAppearance() ? hex(0x3E4451, alpha: 1) : hex(0xE5E5E6, alpha: 1)
    }

    private static func isDarkAppearance() -> Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
    }

    private static let darkColors: [SwiftTerm.Color] = [
        c(0x282C34), c(0xE06C75), c(0x98C379), c(0xE5C07B),
        c(0x61AFEF), c(0xC678DD), c(0x56B6C2), c(0xABB2BF),
        c(0x5C6370), c(0xE06C75), c(0x98C379), c(0xE5C07B),
        c(0x61AFEF), c(0xC678DD), c(0x56B6C2), c(0xFFFFFF)
    ]

    private static let lightColors: [SwiftTerm.Color] = [
        c(0x383A42), c(0xE45649), c(0x50A14F), c(0xC18401),
        c(0x4078F2), c(0xA626A4), c(0x0184BC), c(0xFAFAFA),
        c(0xA0A1A7), c(0xE45649), c(0x50A14F), c(0xC18401),
        c(0x4078F2), c(0xA626A4), c(0x0184BC), c(0xFFFFFF)
    ]

    private static func c(_ hex: UInt32) -> SwiftTerm.Color {
        let r = UInt16((hex >> 16) & 0xFF) * 0x101
        let g = UInt16((hex >>  8) & 0xFF) * 0x101
        let b = UInt16( hex        & 0xFF) * 0x101
        return SwiftTerm.Color(red: r, green: g, blue: b)
    }

    private static func hex(_ hex: UInt32, alpha: Double = 1) -> NSColor {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >>  8) & 0xFF) / 255
        let b = CGFloat( hex        & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: CGFloat(alpha))
    }
}
