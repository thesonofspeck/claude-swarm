import Foundation
import GRDB

public struct ProjectRepository: Sendable {
    public let db: Database
    public init(db: Database) { self.db = db }

    public func upsert(_ project: Project) throws {
        try db.queue.write { conn in
            var p = project
            try p.save(conn)
        }
    }

    public func all() throws -> [Project] {
        try db.queue.read { conn in
            try Project.order(Column("name")).fetchAll(conn)
        }
    }

    public func find(id: String) throws -> Project? {
        try db.queue.read { conn in try Project.fetchOne(conn, key: id) }
    }

    public func delete(id: String) throws {
        _ = try db.queue.write { conn in try Project.deleteOne(conn, key: id) }
    }
}

public struct SessionRepository: Sendable {
    public let db: Database
    public init(db: Database) { self.db = db }

    public func upsert(_ session: Session) throws {
        try db.queue.write { conn in
            var s = session
            s.updatedAt = Date()
            try s.save(conn)
        }
    }

    public func setStatus(id: String, _ status: SessionStatus) throws {
        try db.queue.write { conn in
            try conn.execute(
                sql: "UPDATE session SET status = ?, updatedAt = ? WHERE id = ?",
                arguments: [status.rawValue, Date(), id]
            )
        }
    }

    public func forProject(_ projectId: String) throws -> [Session] {
        try db.queue.read { conn in
            try Session
                .filter(Column("projectId") == projectId)
                .order(Column("createdAt").desc)
                .fetchAll(conn)
        }
    }

    public func allByProject() throws -> [String: [Session]] {
        try db.queue.read { conn in
            let all = try Session.order(Column("createdAt").desc).fetchAll(conn)
            return Dictionary(grouping: all, by: \.projectId)
        }
    }

    public func find(id: String) throws -> Session? {
        try db.queue.read { conn in try Session.fetchOne(conn, key: id) }
    }

    public func delete(id: String) throws {
        _ = try db.queue.write { conn in try Session.deleteOne(conn, key: id) }
    }

    /// Most recently updated sessions across every project. The Welcome
    /// view's "Pick up where you left off" rail uses this.
    public func recent(limit: Int = 12) throws -> [Session] {
        try db.queue.read { conn in
            try Session.order(Column("updatedAt").desc).limit(limit).fetchAll(conn)
        }
    }
}

public struct TaskCacheRepository: Sendable {
    public let db: Database
    public init(db: Database) { self.db = db }

    public func upsert(_ tasks: [CachedTask], for projectId: String) throws {
        try db.queue.write { conn in
            // Replace the project's slice atomically so deleted tasks vanish.
            try CachedTask.filter(Column("projectId") == projectId).deleteAll(conn)
            for task in tasks {
                var t = task
                try t.save(conn)
            }
        }
    }

    public func all() throws -> [CachedTask] {
        try db.queue.read { conn in
            try CachedTask.order(Column("fetchedAt").desc).fetchAll(conn)
        }
    }

    public func forProject(_ projectId: String) throws -> [CachedTask] {
        try db.queue.read { conn in
            try CachedTask
                .filter(Column("projectId") == projectId)
                .order(Column("fetchedAt").desc)
                .fetchAll(conn)
        }
    }
}

public struct PRCacheRepository: Sendable {
    public let db: Database
    public init(db: Database) { self.db = db }

    public func upsert(_ prs: [CachedPR], owner: String, repo: String) throws {
        try db.queue.write { conn in
            try CachedPR
                .filter(Column("owner") == owner && Column("repo") == repo)
                .deleteAll(conn)
            for pr in prs {
                var p = pr
                try p.save(conn)
            }
        }
    }

    public func all() throws -> [CachedPR] {
        try db.queue.read { conn in
            try CachedPR.order(Column("fetchedAt").desc).fetchAll(conn)
        }
    }

    public func forRepo(owner: String, repo: String) throws -> [CachedPR] {
        try db.queue.read { conn in
            try CachedPR
                .filter(Column("owner") == owner && Column("repo") == repo)
                .order(Column("number").desc)
                .fetchAll(conn)
        }
    }
}
