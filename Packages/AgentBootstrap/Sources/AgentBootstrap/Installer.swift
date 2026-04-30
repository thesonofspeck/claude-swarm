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
        let claudeDir = plan.projectURL.appendingPathComponent(".claude", isDirectory: true)
        let agentsDir = claudeDir.appendingPathComponent("agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        for name in Self.agentNames {
            let dest = agentsDir.appendingPathComponent("\(name).md")
            if !overwrite, FileManager.default.fileExists(atPath: dest.path) { continue }
            guard let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Resources/Agents") else {
                throw InstallerError.missingResource(name)
            }
            let data = try Data(contentsOf: url)
            try data.write(to: dest, options: .atomic)
        }

        try writeSettings(plan: plan, into: claudeDir, overwrite: overwrite)
        try writeMCPConfig(plan: plan, into: plan.projectURL, overwrite: overwrite)
    }

    private func writeSettings(plan: BootstrapPlan, into claudeDir: URL, overwrite: Bool) throws {
        let dest = claudeDir.appendingPathComponent("settings.json")
        guard let url = Bundle.module.url(forResource: "settings", withExtension: "json", subdirectory: "Resources/Templates") else {
            throw InstallerError.missingResource("settings.json")
        }
        var template = try String(contentsOf: url, encoding: .utf8)
        template = template.replacingOccurrences(of: "{{NOTIFY_SCRIPT}}", with: plan.notifyScriptPath)
        try mergeOrWriteJSON(template: template, dest: dest, overwrite: overwrite)
    }

    private func writeMCPConfig(plan: BootstrapPlan, into projectURL: URL, overwrite: Bool) throws {
        let dest = projectURL.appendingPathComponent(".mcp.json")
        guard let url = Bundle.module.url(forResource: "mcp", withExtension: "json", subdirectory: "Resources/Templates") else {
            throw InstallerError.missingResource("mcp.json")
        }
        var template = try String(contentsOf: url, encoding: .utf8)
        template = template
            .replacingOccurrences(of: "{{MEMORY_BIN}}", with: plan.memoryBinaryPath)
            .replacingOccurrences(of: "{{PROJECT_ID}}", with: plan.projectId)
        try mergeOrWriteJSON(template: template, dest: dest, overwrite: overwrite)
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
