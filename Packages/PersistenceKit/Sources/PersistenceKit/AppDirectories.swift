import Foundation

public enum AppDirectories {
    public static let bundleId = "com.claudeswarm"

    public static var supportRoot: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ClaudeSwarm", isDirectory: true)
    }

    public static var databaseURL: URL {
        supportRoot.appendingPathComponent("swarm.sqlite")
    }

    public static var memoryDatabaseURL: URL {
        supportRoot.appendingPathComponent("memory.sqlite")
    }

    public static var transcriptsDir: URL {
        supportRoot.appendingPathComponent("transcripts", isDirectory: true)
    }

    public static var worktreesRoot: URL {
        supportRoot.appendingPathComponent("worktrees", isDirectory: true)
    }

    public static var hooksSocket: URL {
        supportRoot.appendingPathComponent("hooks.sock")
    }

    public static var settingsURL: URL {
        supportRoot.appendingPathComponent("settings.json")
    }

    public static var binDir: URL {
        supportRoot.appendingPathComponent("bin", isDirectory: true)
    }

    public static func ensureExists() throws {
        let fm = FileManager.default
        for url in [supportRoot, transcriptsDir, worktreesRoot, binDir] {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
