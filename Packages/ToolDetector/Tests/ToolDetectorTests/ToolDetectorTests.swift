import XCTest
@testable import ToolDetector

final class ToolDetectorTests: XCTestCase {
    func testToolListIsStable() {
        XCTAssertEqual(SwarmTools.all.map(\.id), ["brew", "git", "claude", "gh", "python3"])
    }

    func testRequiredFlagDefaultsTrue() {
        XCTAssertTrue(SwarmTools.git.required)
    }

    func testDetectGitFindsSomething() async {
        let detector = ToolDetector()
        let status = await detector.detect(SwarmTools.git)
        // git ships with macOS, even Linux test runners; smoke check that
        // detection can resolve at least some path.
        XCTAssertTrue(status.isFound, "git should be findable somewhere on PATH")
    }
}
