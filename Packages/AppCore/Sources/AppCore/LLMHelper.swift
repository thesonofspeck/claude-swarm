import Foundation
import KeychainKit
import AnthropicClient

/// Drafts UI text from sparse hints. Wraps AnthropicClient with prompts
/// tuned for the specific drafting jobs the app needs:
/// - Wrike task title + description from a one-liner
/// - PR title + body from a working-tree diff + linked task
/// - Conversational reply / status comment from current session context
@MainActor
public final class LLMHelper: ObservableObject {
    @Published public var config: AnthropicConfig

    private let configURL: URL
    private let keychain: Keychain
    private var client: AnthropicClient

    public init(config: AnthropicConfig? = nil, keychain: Keychain = Keychain()) {
        self.keychain = keychain
        let url = AppDirectories.supportRoot.appendingPathComponent("anthropic.json")
        self.configURL = url
        if let config {
            self.config = config
        } else if let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(AnthropicConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = AnthropicConfig()
        }
        self.client = AnthropicClient(config: self.config, keychain: keychain)
    }

    public func saveConfig(_ cfg: AnthropicConfig) {
        config = cfg
        client = AnthropicClient(config: cfg, keychain: keychain)
        try? JSONEncoder().encode(cfg).write(to: configURL, options: .atomic)
    }

    public func setKey(_ key: String) throws {
        try keychain.set(key, account: KeychainAccount.anthropic)
    }

    public func removeKey() {
        try? keychain.remove(account: KeychainAccount.anthropic)
    }

    public func hasKey() -> Bool {
        (try? keychain.get(account: KeychainAccount.anthropic)) != nil
    }

    public var isUsable: Bool {
        config.enabled && hasKey()
    }

    // MARK: - Drafting

    public struct WrikeTaskDraft: Sendable {
        public var title: String
        public var description: String
    }

    public func draftWrikeTask(from hint: String, projectContext: String? = nil) async throws -> WrikeTaskDraft {
        let system = """
            You draft Wrike tasks. The user gives you a one-line hint.
            Reply ONLY with this exact format:

            TITLE: <a single concise sentence, ≤ 60 chars>

            DESCRIPTION:
            ## Outcome
            <one paragraph: what "done" looks like>
            ## Steps
            - <bulleted concrete steps>
            ## Acceptance
            - <bulleted, testable>

            No prose around the format. No code fences.
            """
        var user = "Hint: \(hint)"
        if let projectContext, !projectContext.isEmpty {
            user += "\n\nProject context: \(projectContext)"
        }
        let response = try await client.complete(
            system: system,
            messages: [AnthropicMessage(role: .user, content: user)]
        )
        return parseTaskDraft(response, fallbackTitle: hint)
    }

    public struct PRDraft: Sendable {
        public var title: String
        public var body: String
    }

    public func draftPR(diff: String, taskTitle: String?, taskBody: String?) async throws -> PRDraft {
        let system = """
            You draft GitHub pull request titles and bodies. Reply ONLY in this format:

            TITLE: <≤ 70 chars, conventional-commits style if appropriate>

            BODY:
            ## Summary
            - <bullets, concrete>

            ## Test plan
            - [ ] <bullets a reviewer would tick>

            No prose around the format. No code fences around the body.
            """
        let sanitized = LLMHelper.sanitizeDiff(diff)
        var user = "Working-tree diff (truncated to 8000 chars):\n\n\(String(sanitized.prefix(8000)))"
        if let taskTitle { user += "\n\nLinked Wrike task title: \(taskTitle)" }
        if let taskBody { user += "\n\nLinked Wrike task description:\n\(String(taskBody.prefix(2000)))" }
        let response = try await client.complete(
            system: system,
            messages: [AnthropicMessage(role: .user, content: user)]
        )
        return parsePRDraft(response, fallbackTitle: taskTitle ?? "")
    }

    /// Strip diff hunks for files that almost certainly contain secrets so
    /// they don't reach Anthropic. Files matched by name are replaced with
    /// a one-line placeholder; lines matching common secret patterns
    /// (KEY=…, BEGIN PRIVATE KEY, etc.) inside other files are redacted.
    static func sanitizeDiff(_ diff: String) -> String {
        let secretFilenamePatterns = [
            "(^|/)\\.env(\\.[a-zA-Z0-9_-]+)?$",
            "(^|/)id_(rsa|ed25519|ecdsa|dsa)$",
            "\\.(pem|key|pfx|p12|p8)$",
            "(^|/)credentials(\\.json)?$",
            "(^|/)secrets?(\\.(yaml|yml|json|toml))?$"
        ]
        let secretLinePatterns = [
            "BEGIN [A-Z ]*PRIVATE KEY",
            "(?i)(api[_-]?key|secret|token|password|passwd)\\s*[=:]\\s*[\"']?[A-Za-z0-9_+/=\\-]{8,}",
            "(?i)bearer\\s+[A-Za-z0-9_\\-]{16,}"
        ]

        var output: [String] = []
        var skipFile = false
        for raw in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("diff --git") {
                skipFile = secretFilenamePatterns.contains { pattern in
                    line.range(of: pattern, options: .regularExpression) != nil
                }
                if skipFile {
                    output.append(line)
                    output.append("[redacted: file likely contains secrets]")
                } else {
                    output.append(line)
                }
                continue
            }
            if skipFile { continue }
            if (line.hasPrefix("+") || line.hasPrefix("-")),
               secretLinePatterns.contains(where: { line.range(of: $0, options: .regularExpression) != nil }) {
                output.append(String(line.first!) + " [redacted: looks like a secret]")
                continue
            }
            output.append(line)
        }
        return output.joined(separator: "\n")
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
        var user = "Hint: \(hint)"
        if let projectName { user += "\nProject: \(projectName)" }
        return try await client.complete(
            system: system,
            messages: [AnthropicMessage(role: .user, content: user)]
        )
    }

    public func draftStatusComment(diffSummary: String, sessionTitle: String?) async throws -> String {
        let system = """
            You draft a one-paragraph Wrike status comment summarising the work
            an autonomous coding agent did. Plain language, ≤ 4 sentences,
            past tense. Do not include code fences or links.
            """
        var user = "Diff summary:\n\n\(diffSummary.prefix(4000))"
        if let sessionTitle { user += "\n\nSession: \(sessionTitle)" }
        return try await client.complete(
            system: system,
            messages: [AnthropicMessage(role: .user, content: user)]
        )
    }

    // MARK: - Parsers

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
