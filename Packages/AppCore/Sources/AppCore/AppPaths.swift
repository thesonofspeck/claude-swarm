import Foundation
import PersistenceKit
import AgentBootstrap

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
        return try BootstrapResources.materializeNotifyScript(into: AppDirectories.binDir)
    }

    public static func materializePolicyScript() throws -> URL {
        try AppDirectories.ensureExists()
        return try BootstrapResources.materializePolicyScript(into: AppDirectories.binDir)
    }
}
