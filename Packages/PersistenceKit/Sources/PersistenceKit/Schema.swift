import Foundation
import GRDB

public enum Schema {
    public static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1") { db in
            try db.create(table: "project") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("localPath", .text).notNull().unique()
                t.column("defaultBaseBranch", .text).notNull().defaults(to: "main")
                t.column("wrikeFolderId", .text)
                t.column("githubOwner", .text)
                t.column("githubRepo", .text)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "session") { t in
                t.column("id", .text).primaryKey()
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("taskId", .text)
                t.column("taskTitle", .text)
                t.column("branch", .text).notNull()
                t.column("worktreePath", .text).notNull()
                t.column("status", .text).notNull()
                t.column("pid", .integer)
                t.column("prNumber", .integer)
                t.column("transcriptPath", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "task_cache") { t in
                t.column("id", .text).primaryKey()
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("descriptionText", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull()
                t.column("permalink", .text)
                t.column("fetchedAt", .datetime).notNull()
            }

            try db.create(table: "pr_cache") { t in
                t.column("id", .text).primaryKey()
                t.column("sessionId", .text)
                    .references("session", onDelete: .setNull)
                t.column("owner", .text).notNull()
                t.column("repo", .text).notNull()
                t.column("number", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("state", .text).notNull()
                t.column("url", .text).notNull()
                t.column("headSha", .text).notNull()
                t.column("checksPassing", .integer).notNull().defaults(to: 0)
                t.column("checksTotal", .integer).notNull().defaults(to: 0)
                t.column("reviewCount", .integer).notNull().defaults(to: 0)
                t.column("fetchedAt", .datetime).notNull()
            }
        }
    }
}
