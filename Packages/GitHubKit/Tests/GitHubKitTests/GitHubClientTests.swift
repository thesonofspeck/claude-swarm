import XCTest
@testable import GitHubKit

final class GitHubClientTests: XCTestCase {
    func testPRDecode() throws {
        let json = """
        {
            "number": 42,
            "title": "Fix login",
            "body": "Closes WK-1",
            "state": "OPEN",
            "url": "https://github.com/o/r/pull/42",
            "isDraft": false,
            "headRefName": "feat/wk-1-login",
            "baseRefName": "main",
            "headRefOid": "abc123",
            "author": {"login": "ada"}
        }
        """
        let pr = try JSONDecoder().decode(GHPullRequest.self, from: Data(json.utf8))
        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.headRefName, "feat/wk-1-login")
        XCTAssertEqual(pr.author?.login, "ada")
    }

    func testCheckRunDecode() throws {
        let json = """
        [
            {"name":"build","state":"completed","conclusion":"success","link":"https://x/1","bucket":"pass"},
            {"name":"test","state":"in_progress","conclusion":null,"link":"https://x/2","bucket":"running"}
        ]
        """
        let runs = try JSONDecoder().decode([GHCheckRun].self, from: Data(json.utf8))
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].conclusion, "success")
        XCTAssertNil(runs[1].conclusion)
    }

    func testReposDecode() throws {
        let json = """
        [
            {"nameWithOwner":"o/r","description":"d","url":"https://x","isPrivate":false,"updatedAt":"2025-01-01T00:00:00Z"}
        ]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let repos = try decoder.decode([GHRepoSummary].self, from: Data(json.utf8))
        XCTAssertEqual(repos.first?.nameWithOwner, "o/r")
    }
}
