import Foundation
import MemoryService

let args = CommandLine.arguments
// Usage: swarm-memory-mcp serve --stdio
// The --stdio flag is accepted for symmetry with other MCP servers
// but is the only supported transport here.
guard args.count >= 2, args[1] == "serve" else {
    FileHandle.standardError.write(Data("Usage: swarm-memory-mcp serve [--stdio]\n".utf8))
    exit(2)
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        let store = try MemoryStore()
        let server = MCPServer(store: store)
        await server.run()
    } catch {
        FileHandle.standardError.write(Data("Failed to start memory server: \(error)\n".utf8))
        exit(1)
    }
    semaphore.signal()
}
semaphore.wait()
