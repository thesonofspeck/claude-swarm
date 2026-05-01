import Foundation
import AgentBootstrap
import PersistenceKit

/// Drafts UI text from sparse hints by shelling out to the Claude Code
/// CLI in non-interactive mode (`claude -p`). This sidesteps API tokens
/// (the user's `claude` CLI already has whatever auth they signed in
/// with) and lets the project's bundled skills define how Wrike tasks
/// and PR descriptions should look.
@MainActor
public final class LLMHelper: ObservableObject {
    public struct Config: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var maxTimeoutSeconds: Int

        public init(enabled: Bool = false, maxTimeoutSeconds: Int = 60) {
            self.enabled = enabled
            self.maxTimeoutSeconds = maxTimeoutSeconds
        }
    }

    @Published public var config: Config

    private let configURL: URL
    private let claudeExecutableProvider: () -> String
    private let projectRootProvider: () -> URL?

    public init(
        config: Config? = nil,
        claudeExecutable: @escaping () -> String,
        projectRoot: @escaping () -> URL? = { nil }
    ) {
        let url = AppDirectories.supportRoot.appendingPathComponent("ai.json")
        self.configURL = url
        if let config {
            self.config = config
        } else if let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            self.config = decoded
        } else {
            self.config = Config()
        }
        self.claudeExecutableProvider = claudeExecutable
        self.projectRootProvider = projectRoot
    }

    public func saveConfig(_ cfg: Config) {
        config = cfg
        try? JSONEncoder().encode(cfg).write(to: configURL, options: .atomic)
    }

    public var isUsable: Bool {
        config.enabled && FileManager.default.isExecutableFile(atPath: claudeExecutableProvider())
    }

    // MARK: - Drafting

    public struct WrikeTaskDraft: Sendable {
        public var title: String
        public var description: String
    }

    public struct PRDraft: Sendable {
        public var title: String
        public var body: String
    }

    public func draftWrikeTask(from hint: String, projectContext: String? = nil) async throws -> WrikeTaskDraft {
        let skill = try loadSkill(named: "wrike-task-drafter")
        var prompt = "Hint: \(hint)"
        if let projectContext, !projectContext.isEmpty {
            prompt += "\n\nProject context: \(projectContext)"
        }
        let response = try await runClaudePrint(prompt: prompt, systemAppend: skill)
        return parseTaskDraft(response, fallbackTitle: hint)
    }

    public func draftPR(diff: String, taskTitle: String?, taskBody: String?) async throws -> PRDraft {
        let skill = try loadSkill(named: "pr-drafter")
        var prompt = "Working-tree diff (truncated to 8000 chars):\n\n\(String(diff.prefix(8000)))"
        if let taskTitle { prompt += "\n\nLinked Wrike task title: \(taskTitle)" }
        if let taskBody  { prompt += "\n\nLinked Wrike task description:\n\(String(taskBody.prefix(2000)))" }
        let response = try await runClaudePrint(prompt: prompt, systemAppend: skill)
        return parsePRDraft(response, fallbackTitle: taskTitle ?? "")
    }

    public func draftSessionPrompt(from hint: String, projectName: String?) async throws -> String {
        let system = """
            You draft initial prompts for an autonomous coding agent. Take the user's
            short hint and turn it into 2–4 short paragraphs that:
            1. State the goal in the first line.
            2. Spell out concrete acceptance criteria.
            3. Call out any non-obvious constraints.
            Don't add commentary or formatting — just the prompt.
            """
        var prompt = "Hint: \(hint)"
        if let projectName { prompt += "\nProject: \(projectName)" }
        return try await runClaudePrint(prompt: prompt, systemAppend: system)
    }

    public func draftStatusComment(diffSummary: String, sessionTitle: String?) async throws -> String {
        let system = """
            You draft a one-paragraph Wrike status comment summarising the work
            an autonomous coding agent did. Plain language, ≤ 4 sentences,
            past tense. Do not include code fences or links.
            """
        var prompt = "Diff summary:\n\n\(diffSummary.prefix(4000))"
        if let sessionTitle { prompt += "\n\nSession: \(sessionTitle)" }
        return try await runClaudePrint(prompt: prompt, systemAppend: system)
    }

    // MARK: - Skill loading

    /// Resolve the skill content for `name`, preferring the active
    /// project's `.claude/skills/<name>.md` when present so teams can
    /// override the defaults via the team library.
    private func loadSkill(named name: String) throws -> String {
        if let projectRoot = projectRootProvider() {
            let projectSkill = AgentLayout.skillFile(in: projectRoot, name: name)
            if let data = try? Data(contentsOf: projectSkill),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        let url = try BootstrapResources.skillTemplate(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Subprocess

    private func runClaudePrint(prompt: String, systemAppend: String) async throws -> String {
        let executable = claudeExecutableProvider()
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw LLMError.claudeNotFound
        }
        let timeout = config.maxTimeoutSeconds
        let cwd = projectRootProvider()
        return try await Task.detached { [executable, prompt, systemAppend, timeout, cwd] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = [
                "-p", prompt,
                "--append-system-prompt", systemAppend,
                "--output-format", "text"
            ]
            if let cwd { process.currentDirectoryURL = cwd }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                throw LLMError.transport("\(error)")
            }

            let started = Date()
            while process.isRunning {
                if Date().timeIntervalSince(started) > Double(timeout) {
                    process.terminate()
                    throw LLMError.timedOut(seconds: timeout)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled {
                    process.terminate()
                    throw CancellationError()
                }
            }

            let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
            let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
            if process.terminationStatus != 0 {
                let stderr = String(decoding: errData, as: UTF8.self)
                throw LLMError.nonZero(code: process.terminationStatus, stderr: stderr)
            }
            return String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    public enum LLMError: Error, LocalizedError {
        case claudeNotFound
        case timedOut(seconds: Int)
        case nonZero(code: Int32, stderr: String)
        case transport(String)

        public var errorDescription: String? {
            switch self {
            case .claudeNotFound:
                return "claude CLI not found at the configured path. Set it in Settings → General → Tools."
            case .timedOut(let s):
                return "claude -p timed out after \(s) seconds."
            case .nonZero(let code, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return "claude exited \(code)\(trimmed.isEmpty ? "" : ": \(trimmed)")"
            case .transport(let msg):
                return "Couldn't run claude: \(msg)"
            }
        }
    }

    // MARK: - Parsers (same shape as before)

    func parseTaskDraft(_ raw: String, fallbackTitle: String) -> WrikeTaskDraft {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        var title = fallbackTitle
        var bodyLines: [String] = []
        var inDescription = false
        for line in lines {
            let s = String(line)
            if s.hasPrefix("TITLE:") {
                title = s.dropFirst("TITLE:".count).trimmingCharacters(in: .whitespaces)
            } else if s.hasPrefix("DESCRIPTION:") {
                inDescription = true
            } else if inDescription {
                bodyLines.append(s)
            }
        }
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return WrikeTaskDraft(title: title.isEmpty ? fallbackTitle : title, description: body)
    }

    func parsePRDraft(_ raw: String, fallbackTitle: String) -> PRDraft {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        var title = fallbackTitle
        var bodyLines: [String] = []
        var inBody = false
        for line in lines {
            let s = String(line)
            if s.hasPrefix("TITLE:") {
                title = s.dropFirst("TITLE:".count).trimmingCharacters(in: .whitespaces)
            } else if s.hasPrefix("BODY:") {
                inBody = true
            } else if inBody {
                bodyLines.append(s)
            }
        }
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return PRDraft(title: title.isEmpty ? fallbackTitle : title, body: body)
    }
}
