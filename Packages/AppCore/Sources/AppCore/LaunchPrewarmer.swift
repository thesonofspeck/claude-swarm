import Foundation
import KeychainKit
import PersistenceKit
import GitKit
import os

private let log = Logger(subsystem: "com.claudeswarm", category: "prewarm")

/// One-shot launch-time work that improves perceived responsiveness for
/// the things the user is most likely to do first. None of this is
/// load-bearing — every call site degrades gracefully if a step fails.
public enum LaunchPrewarmer {

    /// Resolve and cache the absolute paths to every external tool the app
    /// shells out to. Validates each exists and is executable so the user
    /// gets a clear error in onboarding rather than a mid-action crash.
    /// Also pages the `claude` binary into the file cache by running
    /// `--version`, which trims ~150 ms off the first drafting call.
    @discardableResult
    public static func warmTools(
        settings: AppSettings,
        env: ProcessInfo = .processInfo
    ) async -> ToolPaths {
        let resolved = await Task.detached {
            ToolPaths(
                claude: resolve(settings.claudeExecutable, fallbacks: ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]),
                gh: settings.ghExecutable.isEmpty
                    ? resolve("gh", fallbacks: ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"])
                    : resolve(settings.ghExecutable, fallbacks: []),
                git: resolve(settings.gitExecutable, fallbacks: ["/usr/bin/git", "/opt/homebrew/bin/git"]),
                python: resolve(settings.pythonExecutable, fallbacks: ["/usr/bin/python3", "/opt/homebrew/bin/python3"])
            )
        }.value

        // Page-in: a `claude --version` is cheap and pulls the binary into
        // the buffer cache. Skip on missing exec; surface neither stdout
        // nor stderr — this is best-effort.
        if let claude = resolved.claude {
            await Task.detached {
                _ = try? runQuiet(claude, args: ["--version"])
            }.value
        }
        return resolved
    }

    /// Read each token entry once so the first user-facing action doesn't
    /// trigger a Keychain unlock prompt mid-flow. Errors are ignored —
    /// callers that need the token will retry and surface their own UI.
    public static func warmKeychain(_ keychain: Keychain) {
        for account in ["wrike", "github"] {
            _ = try? keychain.get(account: account)
        }
    }

    /// Eagerly build the GitWorkspace for the most-recent session and run
    /// `reloadAll()` so opening its tabs feels instant.
    @MainActor
    public static func warmMostRecentWorkspace(
        sessionId: String,
        in env: AppEnvironment
    ) async {
        guard let session = try? env.sessionsRepo.find(id: sessionId) else { return }
        let ws = env.gitWorkspace(for: session.worktreePath)
        await ws.reloadAll()
    }

    // MARK: - Internals

    private static func resolve(_ candidate: String, fallbacks: [String]) -> String? {
        let fm = FileManager.default
        if !candidate.isEmpty, fm.isExecutableFile(atPath: candidate) { return candidate }
        for path in fallbacks where fm.isExecutableFile(atPath: path) { return path }
        return nil
    }

    private static func runQuiet(_ exec: String, args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exec)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}

public struct ToolPaths: Sendable, Equatable {
    public let claude: String?
    public let gh: String?
    public let git: String?
    public let python: String?

    public init(claude: String? = nil, gh: String? = nil, git: String? = nil, python: String? = nil) {
        self.claude = claude
        self.gh = gh
        self.git = git
        self.python = python
    }

    public var allResolved: Bool {
        claude != nil && git != nil && python != nil
    }
}

public enum KeychainServices {
    public static let tokens = "com.claudeswarm.tokens"
}
