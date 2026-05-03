import Foundation
import os

/// Lightweight scrape of a Claude Code session transcript into a tree of
/// agent invocations. Claude Code emits Task-tool delegations to subagents
/// in the streaming output; we recognize them by a small set of stable
/// markers (subagent name + the tool's start/finish lines) and produce a
/// hierarchy the Agent Run Explorer can render.
///
/// This is intentionally heuristic — the streaming format isn't documented
/// as stable — so the parser tolerates partial matches and falls back to
/// "Unknown agent" rather than crashing. Tests exercise the well-formed
/// happy path; mismatches degrade to flat output.
public struct AgentRun: Identifiable, Equatable, Sendable {
    public enum Status: String, Sendable, Equatable {
        case running, succeeded, failed, unknown
    }

    public let id: UUID
    public let agent: String
    public let prompt: String?
    public let summary: String?
    public let status: Status
    public let startedAt: Date?
    public let endedAt: Date?
    public let children: [AgentRun]

    public var duration: TimeInterval? {
        guard let s = startedAt, let e = endedAt else { return nil }
        return e.timeIntervalSince(s)
    }

    public init(
        id: UUID = UUID(),
        agent: String,
        prompt: String? = nil,
        summary: String? = nil,
        status: Status = .unknown,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        children: [AgentRun] = []
    ) {
        self.id = id
        self.agent = agent
        self.prompt = prompt
        self.summary = summary
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.children = children
    }
}

public enum AgentRunParser {
    private static let log = Logger(subsystem: "com.claudeswarm", category: "agent-run-parser")

    /// Parses a transcript file. Returns the root run (always team-lead in
    /// the bundled agent set, but other primary agents map to their own
    /// roots) plus discovered children. On unparseable input returns a
    /// single placeholder run summarizing the transcript size.
    public static func parse(transcriptAt url: URL) -> AgentRun {
        let raw: String
        do {
            raw = try String(contentsOf: url, encoding: .utf8)
        } catch {
            log.debug("transcript read failed: \(String(describing: error), privacy: .public)")
            return AgentRun(agent: "team-lead", summary: "Transcript unavailable")
        }
        return parse(raw: raw)
    }

    public static func parse(raw: String) -> AgentRun {
        let blocks = splitIntoBlocks(raw)
        var children: [AgentRun] = []
        for block in blocks {
            if let run = runFromBlock(block) {
                children.append(run)
            }
        }
        let root = AgentRun(
            agent: "team-lead",
            prompt: extractRootPrompt(raw),
            summary: extractRootSummary(raw),
            status: rootStatus(raw),
            startedAt: nil,
            endedAt: nil,
            children: children
        )
        return root
    }

    // MARK: - Heuristic recognizers

    /// The transcript stream punctuates each subagent invocation with a
    /// recognizable header line — we split on those.
    static func splitIntoBlocks(_ raw: String) -> [String] {
        // Pattern: a line containing "Task(<agent>)" or "→ subagent: <name>".
        // Both appear in current Claude Code output for delegations.
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [String] = []
        var current: [String] = []
        for line in lines {
            if isAgentBoundary(line), !current.isEmpty {
                blocks.append(current.joined(separator: "\n"))
                current = [line]
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current.joined(separator: "\n")) }
        return blocks
    }

    static func isAgentBoundary(_ line: String) -> Bool {
        line.contains("Task(") || line.range(of: #"(?i)subagent:\s*\S+"#, options: .regularExpression) != nil
    }

    private static func runFromBlock(_ block: String) -> AgentRun? {
        guard let agent = extractAgentName(block) else { return nil }
        let prompt = firstMatch(in: block, pattern: #"(?ims)prompt:\s*"?(.+?)"?\n"#)
        let summary = firstMatch(in: block, pattern: #"(?ims)result:\s*(.+?)(?:\n\n|$)"#)
        let status: AgentRun.Status = {
            if block.range(of: #"(?i)\b(failed|error)\b"#, options: .regularExpression) != nil { return .failed }
            if block.range(of: #"(?i)\b(succeeded|done|complete)\b"#, options: .regularExpression) != nil { return .succeeded }
            return .running
        }()
        return AgentRun(agent: agent, prompt: prompt, summary: summary, status: status)
    }

    static func extractAgentName(_ block: String) -> String? {
        if let m = firstMatch(in: block, pattern: #"Task\((["']?)([^"')]+)\1\)"#, group: 2) { return m }
        if let m = firstMatch(in: block, pattern: #"(?i)subagent:\s*([\w-]+)"#) { return m }
        return nil
    }

    private static func extractRootPrompt(_ raw: String) -> String? {
        // The seeded prompt is usually the first non-empty paragraph the
        // user provides. We grab the first ≤500 chars of the transcript
        // before the first agent boundary.
        for block in splitIntoBlocks(raw) where !isAgentBoundary(block.split(separator: "\n").first.map(String.init) ?? "") {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return String(trimmed.prefix(500))
            }
        }
        return nil
    }

    private static func extractRootSummary(_ raw: String) -> String? {
        let tail = raw.suffix(800)
        let trimmed = String(tail).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rootStatus(_ raw: String) -> AgentRun.Status {
        if raw.range(of: #"(?i)session\s*(ended|finished)"#, options: .regularExpression) != nil { return .succeeded }
        if raw.range(of: #"(?i)\bfatal\b|\berror\b"#, options: .regularExpression) != nil { return .running }
        return .running
    }

    static func firstMatch(in text: String, pattern: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > group,
              let r = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
