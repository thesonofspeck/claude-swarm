import Foundation

public enum BootstrapResources {
    public static func notifyScriptSourceURL() throws -> URL {
        try hookScriptSourceURL(name: "notify")
    }

    public static func policyScriptSourceURL() throws -> URL {
        try hookScriptSourceURL(name: "policy")
    }

    private static func hookScriptSourceURL(name: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "sh",
            subdirectory: "Resources/Hooks"
        ) else {
            throw InstallerError.missingResource("\(name).sh")
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

    /// Bundled skill markdown by name (without the `.md` suffix). Used by
    /// the Installer to seed `.claude/skills/` and by LLMHelper to load
    /// drafting rules at runtime.
    public static func skillTemplate(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "md",
            subdirectory: "Resources/Skills"
        ) else {
            throw InstallerError.missingResource("\(name).md")
        }
        return url
    }

    public static let bundledSkillNames = ["wrike-task-drafter", "pr-drafter", "pr-reviewer", "memory"]

    /// Copy the bundled notify hook into `directory` if its content differs
    /// from what's already there. Skips writes (and the chmod) on every
    /// launch when nothing changed.
    @discardableResult
    public static func materializeNotifyScript(into directory: URL) throws -> URL {
        try materializeScript(named: "notify.sh", source: notifyScriptSourceURL, into: directory)
    }

    @discardableResult
    public static func materializePolicyScript(into directory: URL) throws -> URL {
        try materializeScript(named: "policy.sh", source: policyScriptSourceURL, into: directory)
    }

    private static func materializeScript(
        named: String,
        source: () throws -> URL,
        into directory: URL
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = directory.appendingPathComponent(named)
        let bundled = try Data(contentsOf: try source())
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

    public static func skillFile(in projectRoot: URL, name: String) -> URL {
        projectRoot.appendingPathComponent(".claude/skills/\(name).md")
    }

    public static func settingsFile(in projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(".claude/settings.json")
    }

    public static func mcpConfigFile(in projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(".mcp.json")
    }
}
