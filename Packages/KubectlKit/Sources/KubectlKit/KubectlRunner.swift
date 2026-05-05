import Foundation

public struct KubectlResult: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public var ok: Bool { exitCode == 0 }
}

public enum KubectlError: Error, LocalizedError, Sendable {
    case nonZeroExit(code: Int32, stderr: String)
    case launchFailed(String)
    case decodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .nonZeroExit(let code, let err): return "kubectl exited \(code): \(err)"
        case .launchFailed(let msg): return "kubectl failed to launch: \(msg)"
        case .decodeFailed(let msg): return "kubectl JSON decode failed: \(msg)"
        }
    }
}

/// Async wrapper around the `kubectl` binary. Resolves the executable
/// from common Homebrew/system locations on first use, then reuses that
/// path. The user's existing kubeconfig (`~/.kube/config`) and any
/// `aws eks update-kubeconfig` setup are picked up automatically — we
/// don't try to re-implement EKS auth here.
public struct KubectlRunner: Sendable {
    public let executable: String

    public init(executable: String? = nil) {
        if let executable, !executable.isEmpty {
            self.executable = executable
        } else {
            self.executable = Self.resolveExecutable()
        }
    }

    private static func resolveExecutable() -> String {
        let candidates = [
            "/opt/homebrew/bin/kubectl",
            "/usr/local/bin/kubectl",
            "/usr/bin/kubectl"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/env"
    }

    @discardableResult
    public func run(
        _ args: [String],
        context: String? = nil,
        namespace: String? = nil,
        env: [String: String]? = nil,
        timeout: TimeInterval = 30
    ) async throws -> KubectlResult {
        var fullArgs: [String] = []
        if executable.hasSuffix("/env") {
            fullArgs.append("kubectl")
        }
        if let context, !context.isEmpty {
            fullArgs.append("--context")
            fullArgs.append(context)
        }
        if let namespace, !namespace.isEmpty {
            fullArgs.append("--namespace")
            fullArgs.append(namespace)
        }
        fullArgs.append(contentsOf: args)

        return try await Task.detached { [executable] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = fullArgs
            if let env { process.environment = env }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                throw KubectlError.launchFailed("\(error)")
            }

            // Cooperative timeout: terminate the process if it overruns.
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                if Date() > deadline {
                    process.terminate()
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            process.waitUntilExit()

            let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
            let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
            let result = KubectlResult(
                stdout: String(decoding: outData, as: UTF8.self),
                stderr: String(decoding: errData, as: UTF8.self),
                exitCode: process.terminationStatus
            )
            if !result.ok {
                throw KubectlError.nonZeroExit(code: result.exitCode, stderr: result.stderr)
            }
            return result
        }.value
    }

    /// Run kubectl with `-o json` and decode the stdout payload.
    public func runJSON<T: Decodable & Sendable>(
        _ args: [String],
        as type: T.Type = T.self,
        context: String? = nil,
        namespace: String? = nil,
        timeout: TimeInterval = 30
    ) async throws -> T {
        let result = try await run(args + ["-o", "json"], context: context, namespace: namespace, timeout: timeout)
        guard let data = result.stdout.data(using: .utf8) else {
            throw KubectlError.decodeFailed("empty stdout")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw KubectlError.decodeFailed("\(error)")
        }
    }

    /// Run kubectl and yield stdout chunks as bytes arrive — for
    /// `logs -f`, `port-forward`, or any long-running command. Cancel
    /// the consuming Task to terminate the subprocess.
    public func runStreaming(
        _ args: [String],
        context: String? = nil,
        namespace: String? = nil,
        env: [String: String]? = nil
    ) -> AsyncThrowingStream<String, Error> {
        var fullArgs: [String] = []
        if executable.hasSuffix("/env") {
            fullArgs.append("kubectl")
        }
        if let context, !context.isEmpty {
            fullArgs.append("--context")
            fullArgs.append(context)
        }
        if let namespace, !namespace.isEmpty {
            fullArgs.append("--namespace")
            fullArgs.append(namespace)
        }
        fullArgs.append(contentsOf: args)
        let executablePath = executable
        let resolvedArgs = fullArgs

        return AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = resolvedArgs
            if let env { process.environment = env }

            let outPipe = Pipe()
            // Merge stderr into stdout — log viewers want everything.
            process.standardOutput = outPipe
            process.standardError = outPipe

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    continuation.finish()
                    return
                }
                if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {
                    continuation.yield(chunk)
                }
            }

            process.terminationHandler = { _ in
                outPipe.fileHandleForReading.readabilityHandler = nil
                continuation.finish()
            }

            continuation.onTermination = { _ in
                outPipe.fileHandleForReading.readabilityHandler = nil
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: KubectlError.launchFailed("\(error)"))
            }
        }
    }
}
