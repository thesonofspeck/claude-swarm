import Foundation

public struct StashService: Sendable {
    public let runner: GitRunner

    public init(runner: GitRunner = GitRunner()) {
        self.runner = runner
    }

    public func list(in repo: URL) async throws -> [StashEntry] {
        // "stash@{0}: WIP on main: abc subject"
        // We use --pretty so we can get a parseable date alongside.
        let format = "%gd%x1f%cI%x1f%s"
        let r = try await runner.run(
            ["stash", "list", "--pretty=format:\(format)"],
            in: repo
        )
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var entries: [StashEntry] = []
        for line in r.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            let ref = String(fields[0])
            let date = iso.date(from: String(fields[1]))
            let subject = String(fields[2])
            let index = parseStashIndex(ref) ?? entries.count
            let branch = parseStashBranch(subject)
            entries.append(StashEntry(index: index, message: subject, branch: branch, date: date))
        }
        return entries
    }

    private func parseStashIndex(_ ref: String) -> Int? {
        guard let openIdx = ref.firstIndex(of: "{"),
              let closeIdx = ref.firstIndex(of: "}"),
              openIdx < closeIdx else { return nil }
        let body = ref[ref.index(after: openIdx)..<closeIdx]
        return Int(body)
    }

    private func parseStashBranch(_ subject: String) -> String? {
        // "WIP on main: ..." or "On feature/x: ..."
        for marker in ["WIP on ", "On "] {
            if subject.hasPrefix(marker),
               let colon = subject.firstIndex(of: ":") {
                return String(subject[subject.index(subject.startIndex, offsetBy: marker.count)..<colon])
            }
        }
        return nil
    }

    public func save(message: String? = nil, includeUntracked: Bool = false, keepIndex: Bool = false, in repo: URL) async throws {
        var args = ["stash", "push"]
        if includeUntracked { args.append("--include-untracked") }
        if keepIndex { args.append("--keep-index") }
        if let message { args.append("-m"); args.append(message) }
        _ = try await runner.run(args, in: repo)
    }

    public func pop(index: Int = 0, in repo: URL) async throws {
        _ = try await runner.run(["stash", "pop", "stash@{\(index)}"], in: repo)
    }

    public func apply(index: Int = 0, in repo: URL) async throws {
        _ = try await runner.run(["stash", "apply", "stash@{\(index)}"], in: repo)
    }

    public func drop(index: Int = 0, in repo: URL) async throws {
        _ = try await runner.run(["stash", "drop", "stash@{\(index)}"], in: repo)
    }

    public func clear(in repo: URL) async throws {
        _ = try await runner.run(["stash", "clear"], in: repo)
    }
}
