import Foundation
import GRDB

public struct ActivityEvent: Codable, Identifiable, Equatable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: String
    public var timestamp: Date
    public var sessionId: String?
    public var projectId: String?
    public var kind: String       // raw HookEvent.Kind, "session.start", "pr.opened", etc.
    public var message: String?

    public static let databaseTableName = "activity"

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        sessionId: String? = nil,
        projectId: String? = nil,
        kind: String,
        message: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.projectId = projectId
        self.kind = kind
        self.message = message
    }
}

public struct ActivityLog: Sendable {
    public let db: Database
    public init(db: Database) { self.db = db }

    public func append(_ event: ActivityEvent) async throws {
        try await db.queue.write { conn in
            var e = event
            try e.save(conn)
        }
    }

    public func recent(limit: Int = 200) async throws -> [ActivityEvent] {
        try await db.queue.read { conn in
            try ActivityEvent
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(conn)
        }
    }

    public func purgeOlderThan(days: Int) async throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
            ?? Date(timeIntervalSinceNow: -Double(days) * 24 * 3600)
        try await db.queue.write { conn in
            try conn.execute(
                sql: "DELETE FROM activity WHERE timestamp < ?",
                arguments: [cutoff]
            )
        }
    }
}
