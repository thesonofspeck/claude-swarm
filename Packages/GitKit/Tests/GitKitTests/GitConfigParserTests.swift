import XCTest
@testable import GitKit

final class GitConfigParserTests: XCTestCase {
    func testParseHTTPSOrigin() {
        let config = """
        [core]
            repositoryformatversion = 0
        [remote "origin"]
            url = https://github.com/acme/widgets.git
            fetch = +refs/heads/*:refs/remotes/origin/*
        """
        let remotes = GitConfigParser.parse(config)
        XCTAssertEqual(remotes.count, 1)
        XCTAssertEqual(remotes[0].name, "origin")
        XCTAssertEqual(remotes[0].owner, "acme")
        XCTAssertEqual(remotes[0].repo, "widgets")
    }

    func testParseSSHOrigin() {
        let config = """
        [remote "origin"]
            url = git@github.com:acme/widgets.git
        """
        let remote = GitConfigParser.parse(config).first
        XCTAssertEqual(remote?.owner, "acme")
        XCTAssertEqual(remote?.repo, "widgets")
    }

    func testParseMultipleRemotes() {
        let config = """
        [remote "origin"]
            url = https://github.com/acme/widgets.git
        [remote "upstream"]
            url = https://github.com/acme-upstream/widgets.git
        """
        let remotes = GitConfigParser.parse(config)
        XCTAssertEqual(remotes.map(\.name), ["origin", "upstream"])
        XCTAssertEqual(remotes[1].owner, "acme-upstream")
    }

    func testRejectsLookalikeHostname() {
        let config = """
        [remote "origin"]
            url = https://github.com.evil.com:443/acme/widgets.git
        """
        let remote = GitConfigParser.parse(config).first
        XCTAssertNil(remote?.owner)
        XCTAssertNil(remote?.repo)
    }

    func testParseNonGitHubReturnsNilOwner() {
        let config = """
        [remote "origin"]
            url = https://gitlab.com/acme/widgets.git
        """
        let remote = GitConfigParser.parse(config).first
        XCTAssertNil(remote?.owner)
        XCTAssertNil(remote?.repo)
    }
}
