import XCTest
@testable import GitKit

final class BranchServiceTests: XCTestCase {
    func testParseTrackAhead() {
        let r = BranchService.parseTrack("ahead 3")
        XCTAssertEqual(r.0, 3)
        XCTAssertEqual(r.1, 0)
    }

    func testParseTrackBehind() {
        let r = BranchService.parseTrack("behind 5")
        XCTAssertEqual(r.0, 0)
        XCTAssertEqual(r.1, 5)
    }

    func testParseTrackBoth() {
        let r = BranchService.parseTrack("ahead 3, behind 1")
        XCTAssertEqual(r.0, 3)
        XCTAssertEqual(r.1, 1)
    }

    func testParseTrackEmpty() {
        let r = BranchService.parseTrack("")
        XCTAssertEqual(r.0, 0)
        XCTAssertEqual(r.1, 0)
    }

    func testParseTrackGone() {
        // "gone" means the upstream is no longer there; treat as zero.
        let r = BranchService.parseTrack("gone")
        XCTAssertEqual(r.0, 0)
        XCTAssertEqual(r.1, 0)
    }
}
