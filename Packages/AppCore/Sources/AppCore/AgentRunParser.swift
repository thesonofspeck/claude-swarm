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

    // Compile regexes once. Building NSRegularExpression on every parse
    // (six per call previously) was a measurable chunk of the cost.
    private static let boundarySubagentRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"(?i)subagent:\s*\S+"#)
    private static let agentNameTaskRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"Task\((["']?)([^"')]+)\1\)"#)
    private static let agentNameSubRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"(?i)subagent:\s*([\w-]+)"#)
    private static let promptRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"(?ims)prompt:\s*"?(.+?)"?\n"#)
    private static let resultRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"(?ims)result:\s*(.+?)(?:\n\n|$)"#)
    private static let failedRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"(?i)\b(failed|error)\b"#)
    private static let succeededRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"(?i)\b(succeeded|done|complete)\b"#)
    private static let sessionEndedRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"(?i)session\s*(ended|finished)"#)

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
        // Split once, reuse the substrings for both children and the
        // root prompt extraction.
        let blocks = splitIntoBlocks(raw)
        var children: [AgentRun] = []
        var rootPrompt: String?
        for block in blocks {
            if let run = runFromBlock(block) {
                children.append(run)
            } else if rootPrompt == nil {
                let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { rootPrompt = String(trimmed.prefix(500)) }
            }
        }
        return AgentRun(
            agent: "team-lead",
            prompt: rootPrompt,
            summary: extractRootSummary(raw),
            status: rootStatus(raw),
            startedAt: nil,
            endedAt: nil,
            children: children
        )
    }

    // MARK: - Heuristic recognizers

    /// The transcript stream punctuates each subagent invocation with a
    /// recognizable header line — we split on those. Walks substrings
    /// to avoid the previous "split → map(String.init) → join → split
    /// again" allocation chain.
    static func splitIntoBlocks(_ raw: String) -> [Substring] {
        var blocks: [Substring] = []
        var blockStart = raw.startIndex
        var lineStart = raw.startIndex
        var seenBoundary = false
        let end = raw.endIndex
        while lineStart < end {
            let lineEnd = raw[lineStart..<end].firstIndex(of: "\n") ?? end
            let line = raw[lineStart..<lineEnd]
            if isAgentBoundary(line) {
                if seenBoundary || lineStart > blockStart {
                    blocks.append(raw[blockStart..<lineStart])
                    blockStart = lineStart
                }
                seenBoundary = true
            }
            lineStart = lineEnd < end ? raw.index(after: lineEnd) : end
        }
        if blockStart < end {
            blocks.append(raw[blockStart..<end])
        }
        return blocks
    }

    static func isAgentBoundary<S: StringProtocol>(_ line: S) -> Bool {
        if line.contains("Task(") { return true }
        let s = String(line)
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return boundarySubagentRegex?.firstMatch(in: s, range: range) != nil
    }

    private static func runFromBlock(_ block: Substring) -> AgentRun? {
        let blockStr = String(block)
        guard let agent = extractAgentName(blockStr) else { return nil }
        let prompt = firstMatch(blockStr, regex: promptRegex)
        let summary = firstMatch(blockStr, regex: resultRegex)
        let status: AgentRun.Status = {
            if matches(blockStr, regex: failedRegex) { return .failed }
            if matches(blockStr, regex: succeededRegex) { return .succeeded }
            return .running
        }()
        return AgentRun(agent: agent, prompt: prompt, summary: summary, status: status)
    }

    static func extractAgentName(_ block: String) -> String? {
        if let m = firstMatch(block, regex: agentNameTaskRegex, group: 2) { return m }
        if let m = firstMatch(block, regex: agentNameSubRegex) { return m }
        return nil
    }

    private static func extractRootSummary(_ raw: String) -> String? {
        let tail = raw.suffix(800)
        let trimmed = String(tail).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rootStatus(_ raw: String) -> AgentRun.Status {
        if matches(raw, regex: sessionEndedRegex) { return .succeeded }
        return .running
    }

    private static func firstMatch(_ text: String, regex: NSRegularExpression?, group: Int = 1) -> String? {
        guard let regex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > group,
              let r = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ text: String, regex: NSRegularExpression?) -> Bool {
        guard let regex else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
