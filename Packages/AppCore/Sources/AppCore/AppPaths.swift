import Foundation
import PersistenceKit
import AgentBootstrap

/// Resolves on-disk paths for binaries and scripts the app installs into
/// project repos. We materialize bundled resources into Application Support
/// so each project's `.claude/settings.json` and `.mcp.json` can reference
/// stable absolute paths that survive app upgrades.
public enum AppPaths {
    public static func memoryBinary() -> URL {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "swarm-memory-mcp") {
            return bundled
        }
        let support = AppDirectories.binDir.appendingPathComponent("swarm-memory-mcp")
        if FileManager.default.isExecutableFile(atPath: support.path) {
            return support
        }
        return URL(fileURLWithPath: "swarm-memory-mcp")
    }

    public static func materializeNotifyScript() throws -> URL {
        try AppDirectories.ensureExists()
        let dest = AppDirectories.binDir.appendingPathComponent("notify.sh")
        let source = try BootstrapResources.notifyScript()
        let data = try Data(contentsOf: source)
        try data.write(to: dest, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: dest.path
        )
        return dest
    }
}
