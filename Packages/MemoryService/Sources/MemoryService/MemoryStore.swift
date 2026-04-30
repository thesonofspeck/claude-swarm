import Foundation
import GRDB
import PersistenceKit

public enum MemoryNamespace: Equatable, Hashable, Sendable {
    case global
    case project(String)
    case session(String)

    public var asString: String {
        switch self {
        case .global: return "global"
        case .project(let id): return "project:\(id)"
        case .session(let id): return "session:\(id)"
        }
    }

    public static func parse(_ raw: String?) -> MemoryNamespace {
        guard let raw, !raw.isEmpty else { return .global }
        if raw == "global" { return .global }
        if raw.hasPrefix("project:") { return .project(String(raw.dropFirst("project:".count))) }
        if raw.hasPrefix("session:") { return .session(String(raw.dropFirst("session:".count))) }
        return .global
    }
}

public struct MemoryEntry: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: String
    public var namespace: String
    public var key: String?
    public var content: String
    public var tags: String         // JSON array as string
    public var createdAt: Date
    public var updatedAt: Date

    public static let databaseTableName = "memory"

    public init(
        id: String = UUID().uuidString,
        namespace: MemoryNamespace,
        key: String? = nil,
        content: String,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.namespace = namespace.asString
        self.key = key
        self.content = content
        self.tags = (try? String(data: JSONEncoder().encode(tags), encoding: .utf8)) ?? "[]"
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var tagsArray: [String] {
        guard let data = tags.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

public actor MemoryStore {
    public let queue: DatabaseQueue

    public init(url: URL = AppDirectories.memoryDatabaseURL) throws {
        try AppDirectories.ensureExists()
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        self.queue = try DatabaseQueue(path: url.path, configuration: config)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "memory") { t in
                t.column("id", .text).primaryKey()
                t.column("namespace", .text).notNull()
                t.column("key", .text)
                t.column("content", .text).notNull()
                t.column("tags", .text).notNull().defaults(to: "[]")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_memory_namespace", on: "memory", columns: ["namespace"])
            try db.create(virtualTable: "memory_fts", using: FTS5()) { t in
                t.tokenizer = .porter()
                t.column("content")
                t.column("namespace")
                t.column("tags")
            }
        }
        try migrator.migrate(queue)
    }

    public func write(_ entry: MemoryEntry) throws -> MemoryEntry {
        try queue.write { db in
            var e = entry
            e.updatedAt = Date()
            try e.save(db)
            try db.execute(
                sql: "INSERT INTO memory_fts(rowid, content, namespace, tags) VALUES ((SELECT rowid FROM memory WHERE id = ?), ?, ?, ?) ON CONFLICT(rowid) DO UPDATE SET content=excluded.content, namespace=excluded.namespace, tags=excluded.tags",
                arguments: [e.id, e.content, e.namespace, e.tags]
            )
            return e
        }
    }

    public func get(id: String) throws -> MemoryEntry? {
        try queue.read { db in try MemoryEntry.fetchOne(db, key: id) }
    }

    public func list(namespace: MemoryNamespace? = nil, limit: Int = 100) throws -> [MemoryEntry] {
        try queue.read { db in
            var query = MemoryEntry.order(Column("updatedAt").desc).limit(limit)
            if let ns = namespace {
                query = query.filter(Column("namespace") == ns.asString)
            }
            return try query.fetchAll(db)
        }
    }

    public func search(_ text: String, namespace: MemoryNamespace? = nil, limit: Int = 20) throws -> [MemoryEntry] {
        try queue.read { db in
            var sql = """
                SELECT m.* FROM memory m
                JOIN memory_fts f ON f.rowid = m.rowid
                WHERE memory_fts MATCH ?
                """
            var args: [DatabaseValueConvertible] = [text]
            if let ns = namespace {
                sql += " AND m.namespace = ?"
                args.append(ns.asString)
            }
            sql += " ORDER BY rank LIMIT ?"
            args.append(limit)
            return try MemoryEntry.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    public func delete(id: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM memory_fts WHERE rowid = (SELECT rowid FROM memory WHERE id = ?)", arguments: [id])
            _ = try MemoryEntry.deleteOne(db, key: id)
        }
    }
}
