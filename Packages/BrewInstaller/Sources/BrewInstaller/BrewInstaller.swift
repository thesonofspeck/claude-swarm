import Foundation
import ToolDetector

public actor BrewInstaller {
    public enum InstallError: Error, LocalizedError {
        case brewNotFound
        case nonZeroExit(code: Int32, log: String)

        public var errorDescription: String? {
            switch self {
            case .brewNotFound:
                return "Homebrew isn't installed. Install it from https://brew.sh and try again."
            case .nonZeroExit(let c, let log):
                return "brew exited \(c)\n\(log)"
            }
        }
    }

    public typealias OutputHandler = @Sendable (String) -> Void

    public init() {}

    public func install(formula: String, output: OutputHandler? = nil) async throws {
        guard let brew = await ToolDetector().detect(SwarmTools.brew).resolvedPath else {
            throw InstallError.brewNotFound
        }
        try await run(brew, args: ["install", formula], output: output)
    }

    public func upgrade(formula: String, output: OutputHandler? = nil) async throws {
        guard let brew = await ToolDetector().detect(SwarmTools.brew).resolvedPath else {
            throw InstallError.brewNotFound
        }
        try await run(brew, args: ["upgrade", formula], output: output)
    }

    private func run(_ executable: String, args: [String], output: OutputHandler?) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            var combined = ""
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                if let line = String(data: data, encoding: .utf8) {
                    combined += line
                    output?(line)
                }
            }
            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: InstallError.nonZeroExit(
                        code: proc.terminationStatus,
                        log: combined
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
