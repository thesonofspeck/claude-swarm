import XCTest
@testable import GitKit

final class StatusServiceTests: XCTestCase {
    func testParseOrdinaryEntries() {
        let raw = "1 .M N... 100644 100644 100644 abc def Sources/Foo.swift\u{0}1 M. N... 100644 100644 100644 abc def Sources/Bar.swift\u{0}"
        let changes = StatusService.parsePorcelainV2(raw)
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[0].path, "Sources/Foo.swift")
        XCTAssertEqual(changes[0].unstagedKind, .modified)
        XCTAssertNil(changes[0].stagedKind)
        XCTAssertEqual(changes[1].path, "Sources/Bar.swift")
        XCTAssertEqual(changes[1].stagedKind, .modified)
        XCTAssertNil(changes[1].unstagedKind)
    }

    func testParseUntrackedAndIgnored() {
        let raw = "? new.swift\u{0}! .DS_Store\u{0}"
        let changes = StatusService.parsePorcelainV2(raw)
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[0].path, "new.swift")
        XCTAssertEqual(changes[0].displayKind, .untracked)
        XCTAssertEqual(changes[1].displayKind, .ignored)
    }

    func testParseUnmergedRecord() {
        let raw = "u UU N... 100644 100644 100644 100644 abc def ghi conflicts/Foo.swift\u{0}"
        let changes = StatusService.parsePorcelainV2(raw)
        XCTAssertEqual(changes.count, 1)
        XCTAssertTrue(changes[0].isUnmerged)
        XCTAssertEqual(changes[0].path, "conflicts/Foo.swift")
    }

    func testParseRenameWithOldPath() {
        let raw = "2 R. N... 100644 100644 100644 abc def R100 New/Path.swift\u{0}Old/Path.swift\u{0}"
        let changes = StatusService.parsePorcelainV2(raw)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].path, "New/Path.swift")
        XCTAssertEqual(changes[0].oldPath, "Old/Path.swift")
        XCTAssertEqual(changes[0].stagedKind, .renamed)
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(StatusService.parsePorcelainV2("").isEmpty)
    }
}
