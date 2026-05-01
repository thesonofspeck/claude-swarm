import Foundation

public struct BranchService: Sendable {
    public let runner: GitRunner

    public init(runner: GitRunner = GitRunner()) {
        self.runner = runner
    }

    public func current(in repo: URL) async throws -> String? {
        let r = try await runner.run(["rev-parse", "--abbrev-ref", "HEAD"], in: repo)
        let name = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return name == "HEAD" ? nil : name
    }

    /// Lists local + remote branches with upstream + ahead/behind metadata.
    /// Uses `for-each-ref` with a deterministic record separator so we don't
    /// have to fight quoting.
    public func list(in repo: URL) async throws -> [BranchRef] {
        let sep = "\u{1f}"
        let recSep = "\u{1e}"
        let format = [
            "%(refname)",
            "%(refname:short)",
            "%(HEAD)",
            "%(upstream:short)",
            "%(upstream:track,nobracket)",
            "%(committerdate:iso-strict)",
            "%(contents:subject)"
        ].joined(separator: sep) + recSep

        let result = try await runner.run([
            "for-each-ref",
            "--format=\(format)",
            "refs/heads", "refs/remotes"
        ], in: repo)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var out: [BranchRef] = []
        for record in result.stdout.split(separator: Character(recSep), omittingEmptySubsequences: true) {
            let fields = record.split(separator: Character(sep), omittingEmptySubsequences: false)
            guard fields.count >= 7 else { continue }
            let refname = String(fields[0])
            let short = String(fields[1])
            let isHead = fields[2] == "*"
            let upstream = fields[3].isEmpty ? nil : String(fields[3])
            let track = String(fields[4])
            let dateStr = String(fields[5])
            let subject = fields[6].isEmpty ? nil : String(fields[6])
            let isRemote = refname.hasPrefix("refs/remotes/")
            // Remote HEAD pointer is noise.
            if isRemote && short.hasSuffix("/HEAD") { continue }

            let (ahead, behind) = parseTrack(track)
            let date = iso.date(from: dateStr) ?? isoFractional.date(from: dateStr)

            out.append(BranchRef(
                name: short,
                isRemote: isRemote,
                isCurrent: isHead && !isRemote,
                upstream: upstream,
                ahead: ahead,
                behind: behind,
                lastCommitSubject: subject,
                lastCommitDate: date
            ))
        }
        out.sort { lhs, rhs in
            if lhs.isRemote != rhs.isRemote { return !lhs.isRemote }
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            return lhs.name < rhs.name
        }
        return out
    }

    static func parseTrack(_ s: String) -> (Int, Int) {
        // Examples: "ahead 3", "behind 2", "ahead 3, behind 1", "gone", ""
        var ahead = 0, behind = 0
        for piece in s.split(separator: ",") {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ahead ") {
                ahead = Int(trimmed.dropFirst("ahead ".count)) ?? 0
            } else if trimmed.hasPrefix("behind ") {
                behind = Int(trimmed.dropFirst("behind ".count)) ?? 0
            }
        }
        return (ahead, behind)
    }

    public func create(_ name: String, from base: String? = nil, in repo: URL) async throws {
        var args = ["branch", name]
        if let base { args.append(base) }
        _ = try await runner.run(args, in: repo)
    }

    public func switchTo(_ name: String, create: Bool = false, in repo: URL) async throws {
        var args = ["switch"]
        if create { args.append("-c") }
        args.append(name)
        _ = try await runner.run(args, in: repo)
    }

    public func rename(from old: String, to new: String, in repo: URL) async throws {
        _ = try await runner.run(["branch", "-m", old, new], in: repo)
    }

    public func delete(_ name: String, force: Bool = false, in repo: URL) async throws {
        _ = try await runner.run(["branch", force ? "-D" : "-d", name], in: repo)
    }

    public func deleteRemote(_ name: String, remote: String = "origin", in repo: URL) async throws {
        _ = try await runner.run(["push", remote, "--delete", name], in: repo)
    }

    public func setUpstream(branch: String, upstream: String, in repo: URL) async throws {
        _ = try await runner.run(["branch", "--set-upstream-to=\(upstream)", branch], in: repo)
    }

    public func unsetUpstream(branch: String, in repo: URL) async throws {
        _ = try await runner.run(["branch", "--unset-upstream", branch], in: repo)
    }
}
