import Foundation

public struct Tool: Equatable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let binaries: [String]      // candidate binary names (`gh` etc.)
    public let brewFormula: String?    // `gh`, `git`, `claude` (cask), `python@3.12`
    public let versionFlag: [String]   // args to pass for a version probe
    public let required: Bool

    public init(
        id: String,
        displayName: String,
        binaries: [String],
        brewFormula: String?,
        versionFlag: [String] = ["--version"],
        required: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.binaries = binaries
        self.brewFormula = brewFormula
        self.versionFlag = versionFlag
        self.required = required
    }
}

public enum SwarmTools {
    public static let brew = Tool(
        id: "brew", displayName: "Homebrew",
        binaries: ["brew"],
        brewFormula: nil,                  // brew installs itself; can't auto
        versionFlag: ["--version"]
    )
    public static let git = Tool(
        id: "git", displayName: "Git",
        binaries: ["git"],
        brewFormula: "git"
    )
    public static let gh = Tool(
        id: "gh", displayName: "GitHub CLI",
        binaries: ["gh"],
        brewFormula: "gh"
    )
    public static let claude = Tool(
        id: "claude", displayName: "Claude Code",
        binaries: ["claude"],
        brewFormula: "anthropic/claude/claude",
        versionFlag: ["--version"]
    )
    public static let python = Tool(
        id: "python3", displayName: "Python 3",
        binaries: ["python3"],
        brewFormula: "python@3.12"
    )

    public static let all: [Tool] = [brew, git, claude, gh, python]
}

public struct ToolStatus: Equatable, Sendable, Identifiable {
    public let tool: Tool
    public var resolvedPath: String?    // absolute path if found
    public var version: String?         // first version-probe line
    public var error: String?

    public var id: String { tool.id }
    public var isFound: Bool { resolvedPath != nil }

    public init(tool: Tool, resolvedPath: String? = nil, version: String? = nil, error: String? = nil) {
        self.tool = tool
        self.resolvedPath = resolvedPath
        self.version = version
        self.error = error
    }
}

public actor ToolDetector {
    public static let shared = ToolDetector()

    /// Common install locations on macOS to probe before falling back to
    /// PATH (`which`). Apple Silicon and Intel Homebrew both covered.
    private let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/opt/homebrew/sbin",
        "/usr/local/sbin"
    ]

    public init() {}

    public func detect(_ tool: Tool, override: String? = nil) async -> ToolStatus {
        // Caller-supplied override path takes precedence.
        if let override, FileManager.default.isExecutableFile(atPath: override) {
            let version = await probeVersion(at: override, args: tool.versionFlag)
            return ToolStatus(tool: tool, resolvedPath: override, version: version)
        }

        for binary in tool.binaries {
            for dir in searchPaths {
                let candidate = dir + "/" + binary
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    let version = await probeVersion(at: candidate, args: tool.versionFlag)
                    return ToolStatus(tool: tool, resolvedPath: candidate, version: version)
                }
            }
            if let path = await whichBinary(binary) {
                let version = await probeVersion(at: path, args: tool.versionFlag)
                return ToolStatus(tool: tool, resolvedPath: path, version: version)
            }
        }
        return ToolStatus(tool: tool, error: "Not found")
    }

    public func detectAll(overrides: [String: String] = [:]) async -> [ToolStatus] {
        var out: [ToolStatus] = []
        for tool in SwarmTools.all {
            out.append(await detect(tool, override: overrides[tool.id]))
        }
        return out
    }

    private func whichBinary(_ name: String) async -> String? {
        let result = await runProcess("/usr/bin/env", args: ["which", name])
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func probeVersion(at path: String, args: [String]) async -> String? {
        let result = await runProcess(path, args: args)
        let combined = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.split(separator: "\n").first.map(String.init)
    }

    private func runProcess(_ executable: String, args: [String]) async -> (stdout: String, stderr: String) {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()
            } catch {
                return ("", error.localizedDescription)
            }
            process.waitUntilExit()
            let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
            let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
            return (
                String(decoding: outData, as: UTF8.self),
                String(decoding: errData, as: UTF8.self)
            )
        }.value
    }
}
