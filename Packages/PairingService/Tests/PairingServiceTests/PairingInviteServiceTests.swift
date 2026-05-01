import XCTest
@testable import PairingService

final class PairingInviteServiceTests: XCTestCase {
    func testIssueAndConsume() async {
        let svc = PairingInviteService(macId: "MAC", macName: "ada-mbp")
        let invite = await svc.issue(host: "10.0.0.4", port: 7321, certThumbprint: "abc")
        XCTAssertEqual(invite.macId, "MAC")
        XCTAssertEqual(invite.host, "10.0.0.4")
        let consumed = await svc.consume(code: invite.pairingCode)
        XCTAssertEqual(consumed, invite)
    }

    func testCodeIsSingleUse() async {
        let svc = PairingInviteService(macId: "MAC", macName: "ada-mbp")
        let invite = await svc.issue(host: "h", port: 1, certThumbprint: "x")
        // XCTAssert*Nil takes a non-async autoclosure, so await outside it.
        let first = await svc.consume(code: invite.pairingCode)
        XCTAssertNotNil(first)
        let second = await svc.consume(code: invite.pairingCode)
        XCTAssertNil(second)
    }

    func testCodeShape() {
        let code = PairingInviteService.makeCode()
        XCTAssertEqual(code.count, 9)
        XCTAssertEqual(code[code.index(code.startIndex, offsetBy: 4)], "-")
    }
}
