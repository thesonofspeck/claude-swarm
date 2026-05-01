import Foundation
import GitKit

/// How to locate a team library. `git` clones (or pulls into a cache)
/// before reading; `local` reads in place.
public enum TeamLibraryConfig: Codable, Equatable, Sendable {
    case disabled
    case git(url: String, branch: String?)
    case local(path: String)

    public var isEnabled: Bool {
        if case .disabled = self { return false }
        return true
    }

    private enum CodingKeys: String, CodingKey { case kind, url, branch, path }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? c.decode(String.self, forKey: .kind)) ?? "disabled"
        switch kind {
        case "git":
            self = .git(
                url: (try? c.decode(String.self, forKey: .url)) ?? "",
                branch: try? c.decode(String.self, forKey: .branch)
            )
        case "local":
            self = .local(path: (try? c.decode(String.self, forKey: .path)) ?? "")
        default:
            self = .disabled
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .disabled:
            try c.encode("disabled", forKey: .kind)
        case .git(let url, let branch):
            try c.encode("git", forKey: .kind)
            try c.encode(url, forKey: .url)
            try c.encode(branch, forKey: .branch)
        case .local(let path):
            try c.encode("local", forKey: .kind)
            try c.encode(path, forKey: .path)
        }
    }
}

/// Resolves the team library on disk. `git` config clones into a cache and
/// pulls on refresh; `local` returns the path directly.
public actor TeamLibrarySource {
    nonisolated(unsafe) fileprivate static let decoder = JSONDecoder()

    public enum SourceError: Error, LocalizedError {
        case notConfigured
        case cloneFailed(String)
        case missingManifest(URL)
        case decodeFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .notConfigured: return "Team library not configured."
            case .cloneFailed(let m): return "git: \(m)"
            case .missingManifest(let u): return "swarm-library.json missing at \(u.path)"
            case .decodeFailed(let e): return "Manifest decode failed: \(e)"
            }
        }
    }

    public let cacheRoot: URL
    public let runner: GitRunner

    public init(cacheRoot: URL, runner: GitRunner = GitRunner()) {
        self.cacheRoot = cacheRoot
        self.runner = runner
    }

    public func resolve(_ config: TeamLibraryConfig) async throws -> URL {
        switch config {
        case .disabled:
            throw SourceError.notConfigured
        case .local(let path):
            return URL(fileURLWithPath: path)
        case .git(let url, let branch):
            return try await ensureGitCache(url: url, branch: branch)
        }
    }

    public func loadManifest(_ config: TeamLibraryConfig) async throws -> (LibraryManifest, URL) {
        let root = try await resolve(config)
        let manifestURL = root.appendingPathComponent("swarm-library.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw SourceError.missingManifest(manifestURL)
        }
        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try Self.decoder.decode(LibraryManifest.self, from: data)
            return (manifest, root)
        } catch {
            throw SourceError.decodeFailed(error)
        }
    }

    private func ensureGitCache(url: String, branch: String?) async throws -> URL {
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let dir = cacheRoot.appendingPathComponent(slug(url))
        let exists = FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path)

        do {
            if exists {
                _ = try await runner.run(["fetch", "--depth", "1", "origin"], in: dir)
                if let branch {
                    _ = try await runner.run(["checkout", branch], in: dir)
                    _ = try await runner.run(["reset", "--hard", "origin/\(branch)"], in: dir)
                } else {
                    _ = try await runner.run(["reset", "--hard", "origin/HEAD"], in: dir)
                }
            } else {
                var args = ["clone", "--depth", "1"]
                if let branch { args.append(contentsOf: ["--branch", branch]) }
                args.append(contentsOf: [url, dir.path])
                _ = try await runner.run(args)
            }
        } catch {
            throw SourceError.cloneFailed("\(error)")
        }
        return dir
    }

    private func slug(_ url: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(url.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}
