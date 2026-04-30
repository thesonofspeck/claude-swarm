import XCTest
@testable import AtomPalette

final class AtomPaletteTests: XCTestCase {
    func testSignatureBlueIsAtomBlue() {
        XCTAssertEqual(AtomHex.blue.light, 0x4078F2)
        XCTAssertEqual(AtomHex.blue.dark, 0x61AFEF)
    }

    func testHexToRGB() {
        let (r, g, b) = HexToRGB.rgb(0xFF8040)
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.5, accuracy: 0.01)
        XCTAssertEqual(b, 0.25, accuracy: 0.05)
    }
}
