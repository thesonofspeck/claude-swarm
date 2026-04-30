import XCTest
@testable import PairingProtocol

final class WireRoundTripTests: XCTestCase {
    func testInviteRoundTrip() throws {
        let invite = PairingInvite(
            host: "192.168.10.4", port: 7321,
            macId: "MAC-123", macName: "ada-mbp",
            pairingCode: "ABCD-1234",
            bundleId: "com.claudeswarm.remote"
        )
        let encoded = try PairCodec.encodeInvite(invite)
        let decoded = try PairCodec.decodeInvite(encoded)
        XCTAssertEqual(invite, decoded)
    }

    func testWireMessageRoundTripForEvents() throws {
        let summary = SessionSummary(
            id: "S1", projectId: "P1", projectName: "Demo",
            taskTitle: "Fix login", branch: "feat/login",
            status: .waitingForInput, needsInput: true,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let message = WireMessage.event(.sessionUpdate(summary))
        let data = try PairCodec.encodeMessage(message)
        let decoded = try PairCodec.decodeMessage(data)
        XCTAssertEqual(message, decoded)
    }

    func testApprovalRequestRoundTrip() throws {
        let req = ApprovalRequest(
            id: "A1", sessionId: "S1", projectName: "Demo",
            taskTitle: "Fix login",
            prompt: "Allow Bash(rm -rf node_modules)?",
            toolCall: ToolCallSummary(toolName: "Bash", argumentSummary: "rm -rf node_modules", isDestructive: true),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let message = WireMessage.event(.approvalRequest(req))
        let data = try PairCodec.encodeMessage(message)
        let decoded = try PairCodec.decodeMessage(data)
        XCTAssertEqual(message, decoded)
    }

    func testCommandRoundTrip() throws {
        let cmd = WireMessage.command(.approve(approvalId: "A1", response: .allow))
        let data = try PairCodec.encodeMessage(cmd)
        XCTAssertEqual(try PairCodec.decodeMessage(data), cmd)
    }
}
