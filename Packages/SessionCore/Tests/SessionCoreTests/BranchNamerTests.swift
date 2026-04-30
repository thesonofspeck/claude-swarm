import XCTest
@testable import SessionCore

final class BranchNamerTests: XCTestCase {
    func testSlugReplacesNonAlphanumeric() {
        XCTAssertEqual(BranchNamer.slug("Fix Login: 500 Error!"), "fix-login-500-error")
    }

    func testSlugCollapsesDashes() {
        XCTAssertEqual(BranchNamer.slug("a   b___c"), "a-b-c")
    }

    func testSlugTrimsLeadingTrailingDashes() {
        XCTAssertEqual(BranchNamer.slug("---hello---"), "hello")
    }

    func testSlugTruncates() {
        let long = String(repeating: "abcdefghij", count: 10)
        XCTAssertLessThanOrEqual(BranchNamer.slug(long).count, 40)
    }

    func testBranchWithTaskId() {
        XCTAssertEqual(
            BranchNamer.branch(taskId: "WK-42", title: "Add login"),
            "feat/WK-42-add-login"
        )
    }

    func testBranchWithoutTaskId() {
        XCTAssertEqual(
            BranchNamer.branch(taskId: nil, title: "Add login"),
            "feat/add-login"
        )
    }
}
