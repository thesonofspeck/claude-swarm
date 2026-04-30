import Foundation

public struct GitResult: Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public var ok: Bool { exitCode == 0 }
}

public enum GitError: Error, LocalizedError {
    case nonZeroExit(code: Int32, stderr: String)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .nonZeroExit(let code, let err): return "git exited \(code): \(err)"
        case .launchFailed(let msg): return "git failed to launch: \(msg)"
        }
    }
}

public struct GitRunner: Sendable {
    public let executable: String

    public init(executable: String = "/usr/bin/git") {
        self.executable = executable
    }

    @discardableResult
    public func run(
        _ args: [String],
        in directory: URL? = nil,
        env: [String: String]? = nil
    ) async throws -> GitResult {
        try await Task.detached { [executable] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            if let directory { process.currentDirectoryURL = directory }
            if let env { process.environment = env }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                throw GitError.launchFailed("\(error)")
            }
            process.waitUntilExit()

            let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
            let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
            let result = GitResult(
                stdout: String(decoding: outData, as: UTF8.self),
                stderr: String(decoding: errData, as: UTF8.self),
                exitCode: process.terminationStatus
            )
            if !result.ok {
                throw GitError.nonZeroExit(code: result.exitCode, stderr: result.stderr)
            }
            return result
        }.value
    }
}
