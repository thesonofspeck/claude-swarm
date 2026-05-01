import Foundation

public struct TagService: Sendable {
    public let runner: GitRunner

    public init(runner: GitRunner = GitRunner()) {
        self.runner = runner
    }

    public func list(in repo: URL) async throws -> [TagRef] {
        let sep = "\u{1f}"
        let recSep = "\u{1e}"
        let format = [
            "%(refname:short)",
            "%(objectname)",
            "%(objecttype)",
            "%(taggerdate:iso-strict)",
            "%(creatordate:iso-strict)",
            "%(contents:subject)"
        ].joined(separator: sep) + recSep
        let r = try await runner.run(
            ["for-each-ref", "--sort=-creatordate", "--format=\(format)", "refs/tags"],
            in: repo
        )
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var out: [TagRef] = []
        for record in r.stdout.split(separator: Character(recSep), omittingEmptySubsequences: true) {
            let fields = record.split(separator: Character(sep), omittingEmptySubsequences: false)
            guard fields.count >= 6 else { continue }
            let name = String(fields[0])
            let sha = String(fields[1])
            let isAnnotated = (fields[2] == "tag")
            let date = iso.date(from: String(fields[3])) ?? iso.date(from: String(fields[4]))
            let message = fields[5].isEmpty ? nil : String(fields[5])
            out.append(TagRef(name: name, sha: sha, isAnnotated: isAnnotated, message: message, date: date))
        }
        return out
    }

    public func create(_ name: String, sha: String? = nil, message: String? = nil, in repo: URL) async throws {
        var args = ["tag"]
        if let message {
            args.append("-a")
            args.append(name)
            args.append("-m")
            args.append(message)
        } else {
            args.append(name)
        }
        if let sha { args.append(sha) }
        _ = try await runner.run(args, in: repo)
    }

    public func delete(_ name: String, in repo: URL) async throws {
        _ = try await runner.run(["tag", "-d", name], in: repo)
    }

    public func push(_ name: String, remote: String = "origin", in repo: URL) async throws {
        _ = try await runner.run(["push", remote, "refs/tags/\(name)"], in: repo)
    }

    public func pushAll(remote: String = "origin", in repo: URL) async throws {
        _ = try await runner.run(["push", remote, "--tags"], in: repo)
    }

    public func deleteRemote(_ name: String, remote: String = "origin", in repo: URL) async throws {
        _ = try await runner.run(["push", remote, "--delete", "refs/tags/\(name)"], in: repo)
    }
}
