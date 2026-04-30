import XCTest
@testable import AppCore

@MainActor
final class LLMHelperTests: XCTestCase {
    private func helper() -> LLMHelper {
        LLMHelper(claudeExecutable: { "/usr/local/bin/claude" })
    }

    func testTaskDraftParser() {
        let raw = """
        TITLE: Fix login redirect on Safari

        DESCRIPTION:
        ## Outcome
        Users on Safari can sign in without the redirect loop.

        ## Steps
        - Repro on Safari 17
        - Identify the cookie that's being dropped

        ## Acceptance
        - End-to-end test green on Safari 17
        """
        let draft = helper().parseTaskDraft(raw, fallbackTitle: "fallback")
        XCTAssertEqual(draft.title, "Fix login redirect on Safari")
        XCTAssertTrue(draft.description.contains("## Outcome"))
        XCTAssertTrue(draft.description.contains("## Acceptance"))
    }

    func testTaskDraftFallsBackOnMissingTitle() {
        let raw = "DESCRIPTION:\n## Outcome\nfoo"
        let draft = helper().parseTaskDraft(raw, fallbackTitle: "fallback")
        XCTAssertEqual(draft.title, "fallback")
    }

    func testPRDraftParser() {
        let raw = """
        TITLE: feat: tame the login redirect

        BODY:
        ## Summary
        - Drop SameSite=Strict for the auth cookie
        - Keep CSRF protection via Origin check

        ## Test plan
        - [ ] Sign in on Safari 17
        - [ ] CSRF E2E remains green
        """
        let draft = helper().parsePRDraft(raw, fallbackTitle: "fallback")
        XCTAssertEqual(draft.title, "feat: tame the login redirect")
        XCTAssertTrue(draft.body.contains("Drop SameSite"))
    }

    func testIsUsableFalseWhenClaudeMissing() {
        let h = LLMHelper(
            config: .init(enabled: true),
            claudeExecutable: { "/no/such/path/claude" }
        )
        XCTAssertFalse(h.isUsable)
    }
}
