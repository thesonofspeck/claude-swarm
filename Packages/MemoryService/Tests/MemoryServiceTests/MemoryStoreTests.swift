import XCTest
@testable import MemoryService

final class MemoryStoreTests: XCTestCase {
    func testNamespaceParseAndAsString() {
        XCTAssertEqual(MemoryNamespace.parse(nil), .global)
        XCTAssertEqual(MemoryNamespace.parse("global"), .global)
        XCTAssertEqual(MemoryNamespace.parse("project:abc"), .project("abc"))
        XCTAssertEqual(MemoryNamespace.parse("session:xyz"), .session("xyz"))
        XCTAssertEqual(MemoryNamespace.global.asString, "global")
        XCTAssertEqual(MemoryNamespace.project("a").asString, "project:a")
    }

    private func makeTempStore(projectId: String = "p1") throws -> (MemoryStore, URL, URL) {
        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-memory-project-\(UUID().uuidString)")
        let global = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-memory-global-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let store = try MemoryStore(projectRoot: project, projectId: projectId, globalRoot: global)
        return (store, project, global)
    }

    func testWriteAndReadRoundTrip() async throws {
        let (store, project, global) = try makeTempStore()
        defer {
            try? FileManager.default.removeItem(at: project)
            try? FileManager.default.removeItem(at: global)
        }

        let entry = MemoryEntry(
            namespace: .project("p1"),
            key: "design/key",
            content: "decided to use frontmatter markdown",
            tags: ["arch", "fs"]
        )
        let saved = try await store.write(entry)
        let fetched = try await store.get(id: saved.id)
        XCTAssertEqual(fetched?.content, "decided to use frontmatter markdown")
        XCTAssertEqual(fetched?.tagsArray, ["arch", "fs"])
        XCTAssertEqual(fetched?.namespace, "project:p1")

        // The file should land at the documented path.
        let expected = project.appendingPathComponent(".claude/memory/project/\(saved.id).md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
    }

    func testSearchFiltersByNamespace() async throws {
        let (store, project, global) = try makeTempStore(projectId: "p1")
        defer {
            try? FileManager.default.removeItem(at: project)
            try? FileManager.default.removeItem(at: global)
        }

        _ = try await store.write(MemoryEntry(namespace: .project("p1"), content: "alpha needle"))
        _ = try await store.write(MemoryEntry(namespace: .session("s1"), content: "beta needle"))
        _ = try await store.write(MemoryEntry(namespace: .global, content: "gamma haystack"))

        let projectHits = try await store.search("needle", namespace: .project("p1"))
        XCTAssertEqual(projectHits.count, 1)
        XCTAssertTrue(projectHits.first?.content.contains("alpha") == true)

        let allHits = try await store.search("needle")
        XCTAssertEqual(allHits.count, 2)

        let globalHits = try await store.search("haystack", namespace: .global)
        XCTAssertEqual(globalHits.count, 1)
    }

    func testListSortedByUpdatedDescending() async throws {
        let (store, project, global) = try makeTempStore()
        defer {
            try? FileManager.default.removeItem(at: project)
            try? FileManager.default.removeItem(at: global)
        }

        _ = try await store.write(MemoryEntry(namespace: .project("p1"), content: "first"))
        try await Task.sleep(nanoseconds: 50_000_000)
        let second = try await store.write(MemoryEntry(namespace: .project("p1"), content: "second"))

        let entries = try await store.list(namespace: .project("p1"))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.id, second.id)
    }

    func testDelete() async throws {
        let (store, project, global) = try makeTempStore()
        defer {
            try? FileManager.default.removeItem(at: project)
            try? FileManager.default.removeItem(at: global)
        }

        let saved = try await store.write(MemoryEntry(namespace: .global, content: "to be removed"))
        try await store.delete(id: saved.id)
        let fetched = try await store.get(id: saved.id)
        XCTAssertNil(fetched)
    }

    func testProjectScopeRequiresProjectRoot() async throws {
        let global = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-memory-global-only-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: global) }
        let store = try MemoryStore(projectRoot: nil, projectId: nil, globalRoot: global)
        do {
            _ = try await store.write(MemoryEntry(namespace: .project("p1"), content: "should fail"))
            XCTFail("Expected noProjectRoot error")
        } catch MemoryStoreError.noProjectRoot {
            // expected
        }
    }

    func testSessionEntriesNestedBySessionId() async throws {
        let (store, project, global) = try makeTempStore()
        defer {
            try? FileManager.default.removeItem(at: project)
            try? FileManager.default.removeItem(at: global)
        }

        let saved = try await store.write(MemoryEntry(namespace: .session("abc-123"), content: "session note"))
        let expected = project.appendingPathComponent(".claude/memory/session/abc-123/\(saved.id).md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))

        let scoped = try await store.list(namespace: .session("abc-123"))
        XCTAssertEqual(scoped.count, 1)
    }

    func testFrontmatterRoundTrip() async throws {
        let (store, project, global) = try makeTempStore()
        defer {
            try? FileManager.default.removeItem(at: project)
            try? FileManager.default.removeItem(at: global)
        }

        let saved = try await store.write(MemoryEntry(
            namespace: .project("p1"),
            key: "k1",
            content: "body line 1\nbody line 2",
            tags: ["a", "b"]
        ))
        let url = project.appendingPathComponent(".claude/memory/project/\(saved.id).md")
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.hasPrefix("---\n"))
        XCTAssertTrue(raw.contains("key: k1"))
        XCTAssertTrue(raw.contains("tags: [a, b]"))
        XCTAssertTrue(raw.contains("body line 1"))

        let fetched = try await store.get(id: saved.id)
        XCTAssertEqual(fetched?.key, "k1")
        XCTAssertEqual(fetched?.content, "body line 1\nbody line 2")
        XCTAssertEqual(fetched?.tags, ["a", "b"])
    }
}
