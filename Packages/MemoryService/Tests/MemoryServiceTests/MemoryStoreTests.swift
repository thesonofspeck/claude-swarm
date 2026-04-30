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

    func testWriteAndReadRoundTrip() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-memory-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = try MemoryStore(url: temp)
        let entry = MemoryEntry(
            namespace: .project("p1"),
            key: "design/key",
            content: "decided to use GRDB",
            tags: ["arch", "db"]
        )
        let saved = try await store.write(entry)
        let fetched = try await store.get(id: saved.id)
        XCTAssertEqual(fetched?.content, "decided to use GRDB")
        XCTAssertEqual(fetched?.tagsArray, ["arch", "db"])
    }

    func testSearchFiltersByNamespace() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-memory-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = try MemoryStore(url: temp)
        _ = try await store.write(MemoryEntry(namespace: .project("a"), content: "alpha needle"))
        _ = try await store.write(MemoryEntry(namespace: .project("b"), content: "beta needle"))

        let aHits = try await store.search("needle", namespace: .project("a"))
        XCTAssertEqual(aHits.count, 1)
        XCTAssertTrue(aHits.first?.content.contains("alpha") == true)

        let allHits = try await store.search("needle")
        XCTAssertEqual(allHits.count, 2)
    }

    func testDelete() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-memory-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = try MemoryStore(url: temp)
        let saved = try await store.write(MemoryEntry(namespace: .global, content: "to be removed"))
        try await store.delete(id: saved.id)
        let fetched = try await store.get(id: saved.id)
        XCTAssertNil(fetched)
    }
}
