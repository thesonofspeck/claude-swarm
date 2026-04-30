import Foundation

public enum BootstrapResources {
    public static func notifyScriptSourceURL() throws -> URL {
        guard let url = Bundle.module.url(
            forResource: "notify",
            withExtension: "sh",
            subdirectory: "Resources/Hooks"
        ) else {
            throw InstallerError.missingResource("notify.sh")
        }
        return url
    }

    public static func agentTemplate(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "md",
            subdirectory: "Resources/Agents"
        ) else {
            throw InstallerError.missingResource("\(name).md")
        }
        return url
    }

    /// Copy the bundled notify hook into `directory` if its content differs
    /// from what's already there. Skips writes (and the chmod) on every
    /// launch when nothing changed.
    @discardableResult
    public static func materializeNotifyScript(into directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = directory.appendingPathComponent("notify.sh")
        let source = try notifyScriptSourceURL()
        let bundled = try Data(contentsOf: source)

        if let existing = try? Data(contentsOf: dest), existing == bundled {
            return dest
        }

        try bundled.write(to: dest, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return dest
    }
}

public enum AgentLayout {
    public static func agentFile(in projectRoot: URL, name: String) -> URL {
        projectRoot.appendingPathComponent(".claude/agents/\(name).md")
    }

    public static func settingsFile(in projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(".claude/settings.json")
    }

    public static func mcpConfigFile(in projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(".mcp.json")
    }
}
