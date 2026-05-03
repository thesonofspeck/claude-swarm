import XCTest
@testable import AppCore

final class AgentRunParserTests: XCTestCase {
    func testRecognizesTaskToolBoundary() {
        XCTAssertTrue(AgentRunParser.isAgentBoundary("Task(engineer)"))
        XCTAssertTrue(AgentRunParser.isAgentBoundary("Task(\"engineer\")"))
        XCTAssertTrue(AgentRunParser.isAgentBoundary("subagent: qe"))
        XCTAssertFalse(AgentRunParser.isAgentBoundary("Just a regular line"))
    }

    func testExtractsAgentNameFromTaskCall() {
        XCTAssertEqual(AgentRunParser.extractAgentName("Task(engineer)\nbody"), "engineer")
        XCTAssertEqual(AgentRunParser.extractAgentName("Task(\"qe\")\nrunning"), "qe")
        XCTAssertEqual(AgentRunParser.extractAgentName("subagent: reviewer"), "reviewer")
    }

    func testParseProducesRootWithChildren() {
        let transcript = """
        Booting team-lead.

        Task(engineer)
        prompt: write the foo
        result: implemented Foo.swift

        Task(qe)
        prompt: cover edge cases
        result: added 4 tests, all green

        Session ended cleanly.
        """
        let root = AgentRunParser.parse(raw: transcript)
        XCTAssertEqual(root.agent, "team-lead")
        XCTAssertGreaterThanOrEqual(root.children.count, 2)
        let agents = Set(root.children.map(\.agent))
        XCTAssertTrue(agents.contains("engineer"))
        XCTAssertTrue(agents.contains("qe"))
    }

    func testEmptyTranscriptReturnsPlaceholderRoot() {
        let root = AgentRunParser.parse(raw: "")
        XCTAssertEqual(root.agent, "team-lead")
        XCTAssertTrue(root.children.isEmpty)
    }
}
