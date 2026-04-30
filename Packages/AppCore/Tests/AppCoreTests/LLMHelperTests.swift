import XCTest
@testable import AppCore

@MainActor
final class LLMHelperTests: XCTestCase {
    func testTaskDraftParser() {
        let helper = LLMHelper()
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
        let draft = helper.parseTaskDraft(raw, fallbackTitle: "fallback")
        XCTAssertEqual(draft.title, "Fix login redirect on Safari")
        XCTAssertTrue(draft.description.contains("## Outcome"))
        XCTAssertTrue(draft.description.contains("## Acceptance"))
    }

    func testTaskDraftFallsBackOnMissingTitle() {
        let helper = LLMHelper()
        let raw = "DESCRIPTION:\n## Outcome\nfoo"
        let draft = helper.parseTaskDraft(raw, fallbackTitle: "fallback")
        XCTAssertEqual(draft.title, "fallback")
    }

    func testSanitizeDiffStripsEnvFile() {
        let diff = """
        diff --git a/.env b/.env
        --- a/.env
        +++ b/.env
        @@ -1 +1 @@
        -OLD_KEY=foo
        +NEW_KEY=bar
        diff --git a/src/x.swift b/src/x.swift
        @@ -1 +1 @@
        -let hi = 1
        +let hi = 2
        """
        let cleaned = LLMHelper.sanitizeDiff(diff)
        XCTAssertTrue(cleaned.contains("[redacted: file likely contains secrets]"))
        XCTAssertFalse(cleaned.contains("NEW_KEY=bar"))
        XCTAssertTrue(cleaned.contains("let hi = 2"))
    }

    func testSanitizeDiffRedactsInlineSecrets() {
        let diff = """
        diff --git a/src/x.swift b/src/x.swift
        --- a/src/x.swift
        +++ b/src/x.swift
        @@ -1,2 +1,2 @@
        -let api_key = "abcdef1234567890"
        +let api_key = "newSecret1234567890"
         keep
        """
        let cleaned = LLMHelper.sanitizeDiff(diff)
        XCTAssertFalse(cleaned.contains("newSecret1234567890"))
        XCTAssertTrue(cleaned.contains("[redacted: looks like a secret]"))
        XCTAssertTrue(cleaned.contains("keep"))
    }

    func testPRDraftParser() {
        let helper = LLMHelper()
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
        let draft = helper.parsePRDraft(raw, fallbackTitle: "fallback")
        XCTAssertEqual(draft.title, "feat: tame the login redirect")
        XCTAssertTrue(draft.body.contains("Drop SameSite"))
    }
}
