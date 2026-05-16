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

    /// Assemble the full argv: `kubectl` prefix when resolved to `env`,
    /// then `--context` / `--namespace`, then the caller's args.
    private func buildArgs(context: String?, namespace: String?, args: [String]) -> [String] {
        var full: [String] = []
        if executable.hasSuffix("/env") {
            full.append("kubectl")
        }
        if let context, !context.isEmpty {
            full.append(contentsOf: ["--context", context])
        }
        if let namespace, !namespace.isEmpty {
            full.append(contentsOf: ["--namespace", namespace])
        }
        full.append(contentsOf: args)
        return full
    }

    @discardableResult
    public func run(
        _ args: [String],
        context: String? = nil,
        namespace: String? = nil,
        env: [String: String]? = nil,
        timeout: TimeInterval = 30
    ) async throws -> KubectlResult {
        let fullArgs = buildArgs(context: context, namespace: namespace, args: args)

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

            // Drain both pipes on background threads so a large
            // `kubectl get -o json` can't fill a pipe and deadlock.
            let outReader = Task.detached { (try? outPipe.fileHandleForReading.readToEnd()) ?? Data() }
            let errReader = Task.detached { (try? errPipe.fileHandleForReading.readToEnd()) ?? Data() }

            // Watchdog terminates the process if it overruns its budget;
            // termination closes the pipes, which unblocks the readers.
            let watchdog = Task {
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning {
                    if Date() > deadline {
                        process.terminate()
                        return
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }

            let outData = await outReader.value
            let errData = await errReader.value
            process.waitUntilExit()
            watchdog.cancel()

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
        let resolvedArgs = buildArgs(context: context, namespace: namespace, args: args)
        let executablePath = executable

        return AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = resolvedArgs
            if let env { process.environment = env }

            let outPipe = Pipe()
            // Merge stderr into stdout — log viewers want everything.
            process.standardOutput = outPipe
            process.standardError = outPipe
            let readHandle = outPipe.fileHandleForReading

            readHandle.readabilityHandler = { handle in
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
                readHandle.readabilityHandler = nil
                continuation.finish()
            }

            continuation.onTermination = { _ in
                readHandle.readabilityHandler = nil
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                // Clear the handler so the pipe FD is released — without
                // this the readabilityHandler leaks on launch failure.
                readHandle.readabilityHandler = nil
                continuation.finish(throwing: KubectlError.launchFailed("\(error)"))
            }
        }
    }
}
