import Foundation
import PersistenceKit
import AgentBootstrap

public enum AppPaths {
    /// Shared global memory directory (cross-project). Per-project memory
    /// lives under `<projectRoot>/.claude/memory/` and is owned by the project
    /// store, not the app.
    public static var globalMemoryRoot: URL {
        AppDirectories.supportRoot.appendingPathComponent("memory/global", isDirectory: true)
    }

    public static func materializeNotifyScript() throws -> URL {
        try AppDirectories.ensureExists()
        return try BootstrapResources.materializeNotifyScript(into: AppDirectories.binDir)
    }

    public static func materializePolicyScript() throws -> URL {
        try AppDirectories.ensureExists()
        return try BootstrapResources.materializePolicyScript(into: AppDirectories.binDir)
    }
}
