import Foundation

public struct GhResult: Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public var ok: Bool { exitCode == 0 }
}

public enum GhError: Error, LocalizedError {
    case notInstalled
    case notAuthenticated(String)
    case nonZeroExit(code: Int32, stderr: String)
    case decoding(Error)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "`gh` CLI is not installed or not on PATH. Install from https://cli.github.com."
        case .notAuthenticated(let msg):
            return "GitHub CLI is not authenticated: \(msg). Run `gh auth login`."
        case .nonZeroExit(let code, let stderr):
            return "gh exited \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .decoding(let err):
            return "gh output decode failed: \(err)"
        }
    }
}

/// Thin async wrapper around the `gh` CLI. All GitHub interactions in the
/// app go through here so we inherit user auth, scopes, and host config.
public struct GhRunner: Sendable {
    public let executable: String

    public init(executable: String? = nil) {
        if let executable {
            self.executable = executable
        } else if let resolved = Self.resolveExecutable() {
            self.executable = resolved
        } else {
            self.executable = "gh"
        }
    }

    private static func resolveExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    @discardableResult
    public func run(
        _ args: [String],
        in directory: URL? = nil,
        stdin: Data? = nil
    ) async throws -> GhResult {
        try await Task.detached { [executable] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            if let directory { process.currentDirectoryURL = directory }
            var env = ProcessInfo.processInfo.environment
            env["GH_PROMPT_DISABLED"] = "1"          // never block on TTY prompts
            env["NO_COLOR"] = "1"
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            let inPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = inPipe

            do {
                try process.run()
            } catch {
                throw GhError.notInstalled
            }
            if let stdin {
                try? inPipe.fileHandleForWriting.write(contentsOf: stdin)
            }
            try? inPipe.fileHandleForWriting.close()
            process.waitUntilExit()

            let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
            let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
            let result = GhResult(
                stdout: String(decoding: outData, as: UTF8.self),
                stderr: String(decoding: errData, as: UTF8.self),
                exitCode: process.terminationStatus
            )
            if !result.ok {
                let lower = result.stderr.lowercased()
                if lower.contains("authentication") || lower.contains("not logged into") {
                    throw GhError.notAuthenticated(result.stderr)
                }
                throw GhError.nonZeroExit(code: result.exitCode, stderr: result.stderr)
            }
            return result
        }.value
    }

    public func runJSON<T: Decodable>(
        _ args: [String],
        as type: T.Type = T.self,
        in directory: URL? = nil
    ) async throws -> T {
        let result = try await run(args, in: directory)
        let data = Data(result.stdout.utf8)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GhError.decoding(error)
        }
    }
}
