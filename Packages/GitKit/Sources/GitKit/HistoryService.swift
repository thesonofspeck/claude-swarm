import Foundation

public struct CommitSummary: Equatable, Identifiable {
    public let id: String         // sha
    public let parents: [String]
    public let author: String
    public let authorEmail: String
    public let date: Date
    public let subject: String
}

public struct HistoryService: Sendable {
    public let runner: GitRunner
    public init(runner: GitRunner = GitRunner()) { self.runner = runner }

    // ISO8601DateFormatter is documented thread-safe for read-only use.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public func log(in repo: URL, ref: String = "HEAD", limit: Int = 200) async throws -> [CommitSummary] {
        // Use a unit separator and record separator to avoid quoting issues.
        let format = "%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%s%x1e"
        let result = try await runner.run(
            ["log", "--max-count=\(limit)", "--pretty=format:\(format)", ref],
            in: repo
        )
        return result.stdout
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .compactMap { record -> CommitSummary? in
                let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false)
                guard fields.count >= 6 else { return nil }
                let raw = String(fields[4])
                let date = Self.isoFractional.date(from: raw) ?? Self.iso.date(from: raw) ?? Date()
                return CommitSummary(
                    id: String(fields[0]),
                    parents: String(fields[1]).split(separator: " ").map(String.init),
                    author: String(fields[2]),
                    authorEmail: String(fields[3]),
                    date: date,
                    subject: String(fields[5])
                )
            }
    }
}

public struct DiffService: Sendable {
    public let runner: GitRunner
    public init(runner: GitRunner = GitRunner()) { self.runner = runner }

    public func workingTreeDiff(in repo: URL, against base: String? = nil) async throws -> [DiffFile] {
        var args = ["diff", "--no-color", "--unified=3"]
        if let base { args.append(base) }
        let result = try await runner.run(args, in: repo)
        return DiffParser.parse(result.stdout)
    }

    /// Per-file diff — preferred when the UI only needs to refresh one
    /// path's diff. Avoids re-parsing the whole worktree on every selection
    /// or every saved keystroke when an agent is editing.
    public func workingTreeDiff(in repo: URL, path: String) async throws -> [DiffFile] {
        let result = try await runner.run(
            ["diff", "--no-color", "--unified=3", "--", path],
            in: repo
        )
        return DiffParser.parse(result.stdout)
    }

    public func stagedDiff(in repo: URL) async throws -> [DiffFile] {
        let result = try await runner.run(["diff", "--no-color", "--cached", "--unified=3"], in: repo)
        return DiffParser.parse(result.stdout)
    }

    public func stagedDiff(in repo: URL, path: String) async throws -> [DiffFile] {
        let result = try await runner.run(
            ["diff", "--no-color", "--cached", "--unified=3", "--", path],
            in: repo
        )
        return DiffParser.parse(result.stdout)
    }

    public func commitDiff(in repo: URL, sha: String) async throws -> [DiffFile] {
        let result = try await runner.run(["show", "--no-color", "--unified=3", "--format=", sha], in: repo)
        return DiffParser.parse(result.stdout)
    }

    public func rangeDiff(in repo: URL, from: String, to: String) async throws -> [DiffFile] {
        let result = try await runner.run(["diff", "--no-color", "--unified=3", "\(from)...\(to)"], in: repo)
        return DiffParser.parse(result.stdout)
    }
}
