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

        migrator.registerMigration("v2_activity") { db in
            try db.create(table: "activity") { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull()
                t.column("sessionId", .text)
                t.column("projectId", .text)
                t.column("kind", .text).notNull()
                t.column("message", .text)
            }
            try db.create(index: "idx_activity_timestamp", on: "activity", columns: ["timestamp"])
        }

        // v3 — back the hot-path lookups with proper indexes.
        // Sidebar polling, Welcome rails, and Inbox refresh all sort
        // sessions by updatedAt and look up cached tasks/PRs by
        // project / repo. Without these every read was a full table
        // scan on the single connection.
        migrator.registerMigration("v3_indexes") { db in
            try db.create(index: "idx_session_projectId", on: "session", columns: ["projectId"])
            try db.create(index: "idx_session_updatedAt", on: "session", columns: ["updatedAt"])
            try db.create(index: "idx_task_cache_projectId", on: "task_cache", columns: ["projectId"])
            try db.create(index: "idx_pr_cache_owner_repo", on: "pr_cache", columns: ["owner", "repo"])
        }

        // v4 — kubectl context fields on `project` for the Deploy tab.
        // Both nullable; absence hides Deploy in the detail bar.
        migrator.registerMigration("v4_kube") { db in
            try db.alter(table: "project") { t in
                t.add(column: "kubeContext", .text)
                t.add(column: "kubeNamespace", .text)
            }
        }

        // v5 — the Welcome rails and caches sort by fetchedAt; without
        // these indexes every refresh was a full scan + sort.
        migrator.registerMigration("v5_cache_indexes") { db in
            try db.create(index: "idx_task_cache_fetchedAt", on: "task_cache", columns: ["fetchedAt"])
            try db.create(index: "idx_pr_cache_fetchedAt", on: "pr_cache", columns: ["fetchedAt"])
        }
    }
}
