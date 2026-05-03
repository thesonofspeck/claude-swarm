import Foundation
import GRDB

/// Thin wrapper around a GRDB `DatabasePool` so reads (sidebar refresh,
/// Welcome feed hydrate, Inbox hydrate, Spotlight reindex) run on
/// parallel WAL snapshots while writes serialize on a single writer
/// connection. The legacy single-`DatabaseQueue` configuration meant
/// every concurrent reader contended with every writer.
public final class Database: @unchecked Sendable {
    /// Public name kept as `queue` for source-compat with existing
    /// callers that use `db.queue.read { … }` / `db.queue.write { … }`.
    /// Both methods are part of the `DatabaseWriter` protocol that
    /// `DatabasePool` conforms to.
    public let queue: DatabasePool

    public init(url: URL) throws {
        try AppDirectories.ensureExists()
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        // DatabasePool enables WAL automatically. Five readers cover
        // sidebar + welcome + inbox + spotlight + ad-hoc with headroom.
        config.maximumReaderCount = 5
        queue = try DatabasePool(path: url.path, configuration: config)
        var migrator = DatabaseMigrator()
        Schema.register(&migrator)
        try migrator.migrate(queue)
    }

    public static func main() throws -> Database {
        try Database(url: AppDirectories.databaseURL)
    }
}
