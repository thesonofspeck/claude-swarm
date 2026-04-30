import XCTest
@testable import GitKit

final class WorktreeServiceTests: XCTestCase {
    func testParseListPorcelain() {
        let svc = WorktreeService()
        let input = """
        worktree /Users/me/repo
        HEAD abc123def
        branch refs/heads/main

        worktree /Users/me/repo-feature
        HEAD def456abc
        branch refs/heads/feat/something

        """
        let trees = svc.parseList(input)
        XCTAssertEqual(trees.count, 2)
        XCTAssertEqual(trees[0].branch, "main")
        XCTAssertEqual(trees[0].head, "abc123def")
        XCTAssertEqual(trees[1].branch, "feat/something")
        XCTAssertEqual(trees[1].path.path, "/Users/me/repo-feature")
    }

    func testParseEmpty() {
        let svc = WorktreeService()
        XCTAssertEqual(svc.parseList(""), [])
    }
}
