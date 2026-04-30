import Foundation

public struct BootstrapPlan: Equatable, Sendable {
    public let projectURL: URL
    public let projectId: String
    public let memoryBinaryPath: String
    public let notifyScriptPath: String

    public init(projectURL: URL, projectId: String, memoryBinaryPath: String, notifyScriptPath: String) {
        self.projectURL = projectURL
        self.projectId = projectId
        self.memoryBinaryPath = memoryBinaryPath
        self.notifyScriptPath = notifyScriptPath
    }
}

public struct Installer {
    public init() {}

    public static let agentNames = [
        "team-lead",
        "ux-designer",
        "systems-architect",
        "engineer",
        "qe",
        "reviewer"
    ]

    public func install(_ plan: BootstrapPlan, overwrite: Bool = true) throws {
        let agentsDir = plan.projectURL.appendingPathComponent(".claude/agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        for name in Self.agentNames {
            let dest = AgentLayout.agentFile(in: plan.projectURL, name: name)
            if !overwrite, FileManager.default.fileExists(atPath: dest.path) { continue }
            let url = try BootstrapResources.agentTemplate(name)
            try Data(contentsOf: url).write(to: dest, options: .atomic)
        }

        try writeSettings(plan: plan, overwrite: overwrite)
        try writeMCPConfig(plan: plan, overwrite: overwrite)
    }

    private func writeSettings(plan: BootstrapPlan, overwrite: Bool) throws {
        guard let url = Bundle.module.url(forResource: "settings", withExtension: "json", subdirectory: "Resources/Templates") else {
            throw InstallerError.missingResource("settings.json")
        }
        let template = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "{{NOTIFY_SCRIPT}}", with: plan.notifyScriptPath)
        try mergeOrWriteJSON(
            template: template,
            dest: AgentLayout.settingsFile(in: plan.projectURL),
            overwrite: overwrite
        )
    }

    private func writeMCPConfig(plan: BootstrapPlan, overwrite: Bool) throws {
        guard let url = Bundle.module.url(forResource: "mcp", withExtension: "json", subdirectory: "Resources/Templates") else {
            throw InstallerError.missingResource("mcp.json")
        }
        let template = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "{{MEMORY_BIN}}", with: plan.memoryBinaryPath)
            .replacingOccurrences(of: "{{PROJECT_ID}}", with: plan.projectId)
        try mergeOrWriteJSON(
            template: template,
            dest: AgentLayout.mcpConfigFile(in: plan.projectURL),
            overwrite: overwrite
        )
    }

    private func mergeOrWriteJSON(template: String, dest: URL, overwrite: Bool) throws {
        let templateObj = try JSONSerialization.jsonObject(with: Data(template.utf8)) as? [String: Any] ?? [:]

        if FileManager.default.fileExists(atPath: dest.path), !overwrite {
            let existingData = try Data(contentsOf: dest)
            if var existing = try JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                Self.deepMerge(into: &existing, from: templateObj)
                let merged = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
                try merged.write(to: dest, options: .atomic)
                return
            }
        }
        let bytes = try JSONSerialization.data(withJSONObject: templateObj, options: [.prettyPrinted, .sortedKeys])
        try bytes.write(to: dest, options: .atomic)
    }

    private static func deepMerge(into target: inout [String: Any], from source: [String: Any]) {
        for (key, sourceValue) in source {
            if let targetValue = target[key] as? [String: Any], let sourceDict = sourceValue as? [String: Any] {
                var merged = targetValue
                deepMerge(into: &merged, from: sourceDict)
                target[key] = merged
            } else {
                target[key] = sourceValue
            }
        }
    }
}

public enum InstallerError: Error, LocalizedError {
    case missingResource(String)
    public var errorDescription: String? {
        switch self {
        case .missingResource(let name): return "Bundled resource not found: \(name)"
        }
    }
}
