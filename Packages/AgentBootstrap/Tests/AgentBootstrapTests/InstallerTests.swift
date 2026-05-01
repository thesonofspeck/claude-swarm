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
            notifyScriptPath: "/usr/local/bin/notify.sh",
            policyScriptPath: "/usr/local/bin/policy.sh"
        )
        try Installer().install(plan, overwrite: true)

        for name in Installer.agentNames {
            let path = temp.appendingPathComponent(".claude/agents/\(name).md")
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), "Missing agent: \(name)")
        }
        for name in BootstrapResources.bundledSkillNames {
            let path = temp.appendingPathComponent(".claude/skills/\(name).md")
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), "Missing skill: \(name)")
        }
        XCTAssertTrue(BootstrapResources.bundledSkillNames.contains("memory"),
                      "Memory skill should be bundled by default")

        let settings = temp.appendingPathComponent(".claude/settings.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settings.path))
        // Parse rather than substring-match: JSONSerialization on
        // swift-foundation escapes "/" to "\\/" in serialized output,
        // so a raw contains check would miss the path.
        let settingsData = try Data(contentsOf: settings)
        let settingsObj = try JSONSerialization.jsonObject(with: settingsData) as? [String: Any]
        let permissions = settingsObj?["permissions"] as? [String: Any]
        let allow = (permissions?["allow"] as? [String]) ?? []
        XCTAssertTrue(
            allow.contains(where: { $0.contains(".claude/memory") }),
            "Settings should grant permissions for the memory directory; got \(allow)"
        )

        let mcp = temp.appendingPathComponent(".mcp.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mcp.path))
        let mcpData = try Data(contentsOf: mcp)
        let parsedMCP = try JSONSerialization.jsonObject(with: mcpData) as? [String: Any]
        let servers = parsedMCP?["mcpServers"] as? [String: Any]
        XCTAssertEqual(servers?.count ?? 0, 0,
                       "Default project should ship with no MCP servers")
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
