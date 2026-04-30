import Foundation
import GRDB

public struct ProjectRepository {
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

public struct SessionRepository {
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
}
