import XCTest
@testable import AgentBootstrap

final class InstallerTests: XCTestCase {
    func testInstallWritesAllAgentFiles() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let plan = BootstrapPlan(
            projectURL: temp,
            projectId: "P1",
            memoryBinaryPath: "/usr/local/bin/swarm-memory-mcp",
            notifyScriptPath: "/usr/local/bin/notify.sh",
            policyScriptPath: "/usr/local/bin/policy.sh"
        )
        try Installer().install(plan, overwrite: true)

        for name in Installer.agentNames {
            let path = temp.appendingPathComponent(".claude/agents/\(name).md")
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), "Missing agent: \(name)")
        }
        let settings = temp.appendingPathComponent(".claude/settings.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settings.path))

        let mcp = temp.appendingPathComponent(".mcp.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mcp.path))

        let mcpData = try Data(contentsOf: mcp)
        let mcpStr = String(data: mcpData, encoding: .utf8)!
        XCTAssertTrue(mcpStr.contains("/usr/local/bin/swarm-memory-mcp"))
        XCTAssertTrue(mcpStr.contains("\"P1\""))
    }

    func testInstallMergesExistingSettings() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let existing = """
        {"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo"}]}]},"customField":"keep"}
        """
        try Data(existing.utf8).write(to: temp.appendingPathComponent(".claude/settings.json"))

        let plan = BootstrapPlan(
            projectURL: temp,
            projectId: "P1",
            memoryBinaryPath: "/m",
            notifyScriptPath: "/n",
            policyScriptPath: "/p"
        )
        try Installer().install(plan, overwrite: false)

        let merged = try Data(contentsOf: temp.appendingPathComponent(".claude/settings.json"))
        let parsed = try JSONSerialization.jsonObject(with: merged) as? [String: Any]
        XCTAssertEqual(parsed?["customField"] as? String, "keep")
        let hooks = parsed?["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks?["PreToolUse"], "Existing PreToolUse should be preserved")
        XCTAssertNotNil(hooks?["Notification"], "New Notification hook should be added")
        XCTAssertNotNil(hooks?["Stop"], "New Stop hook should be added")
    }
}
