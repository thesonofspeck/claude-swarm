import Foundation
import Observation
import AgentBootstrap
import PersistenceKit

/// Drafts UI text from sparse hints by shelling out to the Claude Code
/// CLI in non-interactive mode (`claude -p`). This sidesteps API tokens
/// (the user's `claude` CLI already has whatever auth they signed in
/// with) and lets the project's bundled skills define how Wrike tasks
/// and PR descriptions should look.
@MainActor
@Observable
public final class LLMHelper {
    public struct Config: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var maxTimeoutSeconds: Int

        public init(enabled: Bool = false, maxTimeoutSeconds: Int = 60) {
            self.enabled = enabled
            self.maxTimeoutSeconds = maxTimeoutSeconds
        }
    }

    public var config: Config

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

    public enum PRReviewVerdict: String, Sendable, CaseIterable {
        case approve
        case comment
        case requestChanges = "request_changes"
    }

    public enum PRCommentSeverity: String, Sendable, CaseIterable {
        case block, major, minor, nit
    }

    public struct PRReviewComment: Sendable, Identifiable, Hashable {
        public let id: UUID
        public var file: String
        public var line: Int
        public var severity: PRCommentSeverity
        public var body: String

        public init(
            id: UUID = UUID(),
            file: String,
            line: Int,
            severity: PRCommentSeverity,
            body: String
        ) {
            self.id = id
            self.file = file
            self.line = line
            self.severity = severity
            self.body = body
        }
    }

    public struct PRReviewDraft: Sendable {
        public var verdict: PRReviewVerdict
        public var summary: String
        public var comments: [PRReviewComment]

        public init(verdict: PRReviewVerdict, summary: String, comments: [PRReviewComment]) {
            self.verdict = verdict
            self.summary = summary
            self.comments = comments
        }
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

    /// Generate a draft PR review by feeding the PR's unified diff and
    /// metadata to `claude -p` with the bundled `pr-reviewer` skill. The
    /// returned draft is *never* auto-submitted — the caller surfaces it
    /// in a HIL sheet for the user to edit and submit.
    public func reviewPR(
        diff: String,
        prTitle: String,
        prBody: String?,
        prAuthor: String?,
        baseRef: String,
        headRef: String
    ) async throws -> PRReviewDraft {
        let prompt = buildReviewPrompt(diff: diff, prTitle: prTitle, prBody: prBody, prAuthor: prAuthor, baseRef: baseRef, headRef: headRef)
        let skill = try loadSkill(named: "pr-reviewer")
        let response = try await runClaudePrint(prompt: prompt, systemAppend: skill)
        return parseReviewDraft(response)
    }

    /// Streaming variant. Yields stdout chunks as they arrive so callers
    /// can render the agent's output live; cancel the consuming task to
    /// terminate the underlying `claude -p` subprocess. The final
    /// accumulated text parses with `parseReviewDraft(_:)` once the
    /// stream finishes.
    public func streamReviewPR(
        diff: String,
        prTitle: String,
        prBody: String?,
        prAuthor: String?,
        baseRef: String,
        headRef: String
    ) throws -> AsyncThrowingStream<String, Error> {
        let prompt = buildReviewPrompt(diff: diff, prTitle: prTitle, prBody: prBody, prAuthor: prAuthor, baseRef: baseRef, headRef: headRef)
        let skill = try loadSkill(named: "pr-reviewer")
        return streamClaudePrint(prompt: prompt, systemAppend: skill)
    }

    private func buildReviewPrompt(
        diff: String,
        prTitle: String,
        prBody: String?,
        prAuthor: String?,
        baseRef: String,
        headRef: String
    ) -> String {
        var prompt = """
        PR title: \(prTitle)
        Branch: \(baseRef) ← \(headRef)
        """
        if let prAuthor, !prAuthor.isEmpty {
            prompt += "\nAuthor: \(prAuthor)"
        }
        if let prBody, !prBody.isEmpty {
            prompt += "\n\nPR description:\n\(prBody.prefix(2000))"
        }
        prompt += "\n\nUnified diff (truncated to 24000 chars):\n\n\(String(diff.prefix(24000)))"
        return prompt
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

    /// Stream the same `claude -p` invocation as `runClaudePrint`,
    /// yielding stdout chunks as they arrive. Cancel the consuming
    /// task to terminate the subprocess.
    func streamClaudePrint(prompt: String, systemAppend: String) -> AsyncThrowingStream<String, Error> {
        let executable = claudeExecutableProvider()
        let cwd = projectRootProvider()
        return AsyncThrowingStream { continuation in
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                continuation.finish(throwing: LLMError.claudeNotFound)
                return
            }
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
            let outHandle = outPipe.fileHandleForReading
            let errHandle = errPipe.fileHandleForReading
            // stderr is drained continuously into this box — without an
            // active reader a `claude` process that writes >64KB of
            // warnings to stderr blocks on write and never exits,
            // hanging the stream forever.
            let errBuffer = DataAccumulator()

            outHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {
                    continuation.yield(chunk)
                }
            }
            errHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    errBuffer.append(data)
                }
            }

            process.terminationHandler = { proc in
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    let stderr = String(decoding: errBuffer.snapshot(), as: UTF8.self)
                    continuation.finish(throwing: LLMError.nonZero(code: proc.terminationStatus, stderr: stderr))
                }
            }

            continuation.onTermination = { _ in
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                continuation.finish(throwing: LLMError.transport("\(error)"))
            }
        }
    }

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

    public enum LLMError: Error, LocalizedError, Sendable {
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

    /// Parse the strict pr-reviewer skill output into a structured draft.
    /// Tolerant of stray whitespace, optional code-fence wrappers, and a
    /// few common formatting drifts; missing pieces fall back to safe
    /// defaults (verdict=`comment`, empty summary, empty comments).
    public func parseReviewDraft(_ raw: String) -> PRReviewDraft {
        // Strip a single outer ``` … ``` fence if Claude added one.
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if text.hasSuffix("```") {
                text = String(text.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        var verdict: PRReviewVerdict = .comment
        var summaryLines: [String] = []
        var commentBlocks: [[String: String]] = []
        var current: [String: String] = [:]

        enum Section { case none, summary, comments }
        var section: Section = .none

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("VERDICT:") {
                let value = trimmed.dropFirst("VERDICT:".count).trimmingCharacters(in: .whitespaces).lowercased()
                if let v = PRReviewVerdict(rawValue: value) { verdict = v }
                section = .none
                continue
            }
            if trimmed.uppercased().hasPrefix("SUMMARY:") {
                section = .summary
                continue
            }
            if trimmed.uppercased().hasPrefix("COMMENTS:") {
                section = .comments
                continue
            }
            switch section {
            case .none:
                continue
            case .summary:
                summaryLines.append(line)
            case .comments:
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    if !current.isEmpty {
                        commentBlocks.append(current)
                        current = [:]
                    }
                    let kv = trimmed.dropFirst(2)
                    addKV(String(kv), into: &current)
                } else if trimmed.contains(":") {
                    addKV(trimmed, into: &current)
                }
            }
        }
        if !current.isEmpty { commentBlocks.append(current) }

        let summary = summaryLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let comments: [PRReviewComment] = commentBlocks.compactMap { dict in
            guard let file = dict["file"], !file.isEmpty,
                  let lineStr = dict["line"], let line = Int(lineStr),
                  let body = dict["body"], !body.isEmpty else { return nil }
            let severity = (dict["severity"].flatMap(PRCommentSeverity.init(rawValue:))) ?? .minor
            return PRReviewComment(file: file, line: line, severity: severity, body: body)
        }

        return PRReviewDraft(verdict: verdict, summary: summary, comments: comments)
    }

    private func addKV(_ s: String, into dict: inout [String: String]) {
        guard let colon = s.firstIndex(of: ":") else { return }
        let key = s[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let value = s[s.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if !key.isEmpty {
            dict[key] = value
        }
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

/// Thread-safe `Data` accumulator for subprocess pipe drains — a
/// `FileHandle.readabilityHandler` fires on a background queue, so
/// appends must be locked.
final class DataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    func snapshot() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}
