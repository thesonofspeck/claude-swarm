import XCTest
@testable import GitKit

final class GitRunnerTests: XCTestCase {
    func testGitVersionRuns() async throws {
        let runner = GitRunner()
        let result = try await runner.run(["--version"])
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains("git version"))
    }

    func testNonZeroExitThrows() async {
        let runner = GitRunner()
        do {
            _ = try await runner.run(["this-is-not-a-real-subcommand"])
            XCTFail("Expected error")
        } catch GitError.nonZeroExit {
            // expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
