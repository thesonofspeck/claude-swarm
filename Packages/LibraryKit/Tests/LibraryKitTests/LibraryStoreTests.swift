import XCTest
@testable import LibraryKit

final class LibraryStoreTests: XCTestCase {
    func testManifestDecodes() throws {
        let json = """
        {
          "version": 1,
          "name": "Acme",
          "description": "shared",
          "items": [
            {"id":"team-lead","kind":"agent","name":"Team Lead","description":"orchestrator","path":"agents/team-lead.md","version":"1.0.0","tags":["default"]},
            {"id":"github","kind":"mcp","name":"GitHub","description":"GitHub MCP","path":"mcp/github.json","version":"0.4.0","tags":["github"]}
          ]
        }
        """
        let m = try JSONDecoder().decode(LibraryManifest.self, from: Data(json.utf8))
        XCTAssertEqual(m.name, "Acme")
        XCTAssertEqual(m.items.count, 2)
        XCTAssertEqual(m.items[0].kind, .agent)
        XCTAssertEqual(m.items[1].kind, .mcp)
    }

    func testLockRoundTrip() throws {
        var lock = LibraryLock()
        lock.installed["agent/team-lead"] = LibraryLock.Entry(version: "1.0.0", sha256: "abc")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(lock)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LibraryLock.self, from: data)
        XCTAssertEqual(decoded.installed["agent/team-lead"]?.sha256, "abc")
    }

    func testTeamLibraryConfigCodecRoundTrip() throws {
        let configs: [TeamLibraryConfig] = [
            .disabled,
            .git(url: "git@github.com:acme/lib.git", branch: "main"),
            .git(url: "https://x", branch: nil),
            .local(path: "/Users/me/lib")
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for cfg in configs {
            let data = try encoder.encode(cfg)
            let back = try decoder.decode(TeamLibraryConfig.self, from: data)
            XCTAssertEqual(cfg, back)
        }
    }

    func testInstallMergesMcpEntry() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-lib-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        // Build a tiny team library on disk.
        let teamRoot = temp.appendingPathComponent("team")
        let mcpDir = teamRoot.appendingPathComponent("mcp")
        try FileManager.default.createDirectory(at: mcpDir, withIntermediateDirectories: true)
        let mcpEntry = #"""
        { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"] }
        """#
        try Data(mcpEntry.utf8).write(to: mcpDir.appendingPathComponent("github.json"))
        let manifest = #"""
        {
          "version": 1, "name": "test",
          "items": [
            {"id":"github","kind":"mcp","name":"GitHub","description":"x","path":"mcp/github.json","version":"1"}
          ]
        }
        """#
        try Data(manifest.utf8).write(to: teamRoot.appendingPathComponent("swarm-library.json"))

        // Pre-existing project with an unrelated MCP entry.
        let projectRoot = temp.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let existing = #"""
        {"mcpServers": {"local": {"command": "echo"}}}
        """#
        try Data(existing.utf8).write(to: projectRoot.appendingPathComponent(".mcp.json"))

        let cache = temp.appendingPathComponent("cache")
        let source = TeamLibrarySource(cacheRoot: cache)
        let store = LibraryStore(teamSource: source)
        try await store.setTeamConfig(.local(path: teamRoot.path))

        let snap = await store.snapshot(in: projectRoot)
        let row = try XCTUnwrap(snap.rows.first { $0.item.id == "github" })
        XCTAssertEqual(row.source, .team)
        XCTAssertFalse(row.installed)

        try await store.install(row.item, into: projectRoot)
        let merged = try Data(contentsOf: projectRoot.appendingPathComponent(".mcp.json"))
        let parsed = try JSONSerialization.jsonObject(with: merged) as? [String: Any]
        let servers = parsed?["mcpServers"] as? [String: Any]
        XCTAssertNotNil(servers?["local"], "Existing entry preserved")
        XCTAssertNotNil(servers?["github"], "New entry merged in")
    }
}
