import Foundation
import GRDB

public final class Database: @unchecked Sendable {
    public let queue: DatabaseQueue

    public init(url: URL) throws {
        try AppDirectories.ensureExists()
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        queue = try DatabaseQueue(path: url.path, configuration: config)
        var migrator = DatabaseMigrator()
        Schema.register(&migrator)
        try migrator.migrate(queue)
    }

    public static func main() throws -> Database {
        try Database(url: AppDirectories.databaseURL)
    }
}
