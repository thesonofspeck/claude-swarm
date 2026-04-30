import Foundation

/// Single source of truth for the Atom One palette (Light + Dark). Every
/// platform-specific wrapper (NSColor / UIColor / Splash / SwiftTerm)
/// reads from these values rather than redefining them.
public enum AtomHex {
    public struct Pair: Equatable, Sendable {
        public let light: UInt32
        public let dark: UInt32
        public init(light: UInt32, dark: UInt32) {
            self.light = light
            self.dark = dark
        }
    }

    // Surfaces
    public static let bgDeep      = Pair(light: 0xF5F5F5, dark: 0x181A1F)
    public static let bgSidebar   = Pair(light: 0xF0F0F0, dark: 0x21252B)
    public static let bgBase      = Pair(light: 0xFAFAFA, dark: 0x282C34)
    public static let bgRaised    = Pair(light: 0xFFFFFF, dark: 0x2C313A)
    public static let bgSelection = Pair(light: 0xE5E5E6, dark: 0x3E4451)
    public static let divider     = Pair(light: 0xDCDDE0, dark: 0x181A1F)

    // Text
    public static let fg          = Pair(light: 0x383A42, dark: 0xABB2BF)
    public static let fgMuted     = Pair(light: 0xA0A1A7, dark: 0x5C6370)
    public static let fgBright    = Pair(light: 0x202227, dark: 0xE5E5E5)

    // Syntax / accents
    public static let blue        = Pair(light: 0x4078F2, dark: 0x61AFEF)
    public static let purple      = Pair(light: 0xA626A4, dark: 0xC678DD)
    public static let red         = Pair(light: 0xE45649, dark: 0xE06C75)
    public static let orange      = Pair(light: 0x986801, dark: 0xD19A66)
    public static let yellow      = Pair(light: 0xC18401, dark: 0xE5C07B)
    public static let green       = Pair(light: 0x50A14F, dark: 0x98C379)
    public static let cyan        = Pair(light: 0x0184BC, dark: 0x56B6C2)

    /// Translucent overlays — used for diff hunk backgrounds, status pills.
    public static let translucentAlpha: Double = 0.14
    public static let warningAlpha: Double = 0.18
    public static let pillAlpha: Double = 0.06
}

public enum HexToRGB {
    public static func rgb(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >>  8) & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        return (r, g, b)
    }
}
