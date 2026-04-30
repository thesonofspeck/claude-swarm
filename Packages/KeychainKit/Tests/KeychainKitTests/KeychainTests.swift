import XCTest
@testable import KeychainKit

final class KeychainTests: XCTestCase {
    func testRoundTrip() throws {
        let kc = Keychain(service: "com.claudeswarm.tokens.test")
        let account = "test-\(UUID().uuidString)"
        defer { try? kc.remove(account: account) }

        try kc.set("hello", account: account)
        XCTAssertEqual(try kc.get(account: account), "hello")

        try kc.set("updated", account: account)
        XCTAssertEqual(try kc.get(account: account), "updated")

        try kc.remove(account: account)
        XCTAssertThrowsError(try kc.get(account: account))
    }
}
