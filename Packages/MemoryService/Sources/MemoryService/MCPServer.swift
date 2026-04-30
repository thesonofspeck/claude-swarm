import Foundation

/// Minimal MCP-style stdio JSON-RPC server. Implements just enough of the
/// Model Context Protocol surface for `tools/list` and `tools/call` against
/// our memory tool set. Replace with a fuller MCP package once available.
public final class MCPServer {
    private let store: MemoryStore
    private let inputHandle: FileHandle
    private let outputHandle: FileHandle
    private let outputLock = NSLock()

    public init(
        store: MemoryStore,
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput
    ) {
        self.store = store
        self.inputHandle = input
        self.outputHandle = output
    }

    public func run() async {
        // MCP framing is line-delimited JSON when running over stdio in
        // simple mode; for HTTP+SSE servers a different transport is used.
        // We use line-delimited JSON-RPC 2.0 here.
        for await line in inputHandle.bytes.lines {
            await handle(line: line)
        }
    }

    private func handle(line: String) async {
        guard let data = line.data(using: .utf8) else { return }
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let id = message["id"]
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            send(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "claude-swarm-memory", "version": "0.1.0"]
            ])
        case "tools/list":
            send(id: id, result: ["tools": Self.toolDescriptors])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let result = try await dispatch(tool: name, arguments: args)
                send(id: id, result: ["content": [["type": "text", "text": result]]])
            } catch {
                send(id: id, error: ["code": -32000, "message": "\(error)"])
            }
        case "ping":
            send(id: id, result: [String: Any]())
        default:
            if id != nil {
                send(id: id, error: ["code": -32601, "message": "Method not found: \(method)"])
            }
        }
    }

    private func dispatch(tool: String, arguments: [String: Any]) async throws -> String {
        switch tool {
        case "memory_write":
            let ns = MemoryNamespace.parse(arguments["namespace"] as? String)
            let key = arguments["key"] as? String
            guard let content = arguments["content"] as? String else {
                throw MCPError.invalidArgument("content")
            }
            let tags = (arguments["tags"] as? [String]) ?? []
            let entry = try await store.write(
                MemoryEntry(namespace: ns, key: key, content: content, tags: tags)
            )
            return #"{"id":"\#(entry.id)"}"#

        case "memory_search":
            guard let q = arguments["query"] as? String else {
                throw MCPError.invalidArgument("query")
            }
            let ns = (arguments["namespace"] as? String).map(MemoryNamespace.parse)
            let limit = (arguments["limit"] as? Int) ?? 20
            let hits = try await store.search(q, namespace: ns, limit: limit)
            return try jsonString(hits.map { ["id": $0.id, "namespace": $0.namespace, "key": $0.key as Any, "content": $0.content] })

        case "memory_get":
            guard let id = arguments["id"] as? String else {
                throw MCPError.invalidArgument("id")
            }
            guard let entry = try await store.get(id: id) else { return "null" }
            return try jsonString(["id": entry.id, "namespace": entry.namespace, "key": entry.key as Any, "content": entry.content])

        case "memory_list":
            let ns = (arguments["namespace"] as? String).map(MemoryNamespace.parse)
            let limit = (arguments["limit"] as? Int) ?? 100
            let entries = try await store.list(namespace: ns, limit: limit)
            return try jsonString(entries.map { ["id": $0.id, "namespace": $0.namespace, "key": $0.key as Any, "content": $0.content] })

        case "memory_delete":
            guard let id = arguments["id"] as? String else {
                throw MCPError.invalidArgument("id")
            }
            try await store.delete(id: id)
            return #"{"deleted":"\#(id)"}"#

        default:
            throw MCPError.unknownTool(tool)
        }
    }

    private func jsonString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        return String(decoding: data, as: UTF8.self)
    }

    private func send(id: Any?, result: [String: Any]) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { msg["id"] = id }
        write(msg)
    }

    private func send(id: Any?, error: [String: Any]) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "error": error]
        if let id { msg["id"] = id }
        write(msg)
    }

    private func write(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: []) else { return }
        outputLock.lock(); defer { outputLock.unlock() }
        try? outputHandle.write(contentsOf: data)
        try? outputHandle.write(contentsOf: Data([0x0a]))
    }

    private static let toolDescriptors: [[String: Any]] = [
        [
            "name": "memory_write",
            "description": "Persist a memory entry. Use namespace `project:<id>` for project-shared, `session:<id>` for private, `global` for cross-project.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "namespace": ["type": "string"],
                    "key": ["type": "string"],
                    "content": ["type": "string"],
                    "tags": ["type": "array", "items": ["type": "string"]]
                ],
                "required": ["content"]
            ]
        ],
        [
            "name": "memory_search",
            "description": "Full-text search of memory entries. Returns ranked hits with content snippets.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string"],
                    "namespace": ["type": "string"],
                    "limit": ["type": "integer"]
                ],
                "required": ["query"]
            ]
        ],
        [
            "name": "memory_get",
            "description": "Fetch a memory entry by id.",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ]
        ],
        [
            "name": "memory_list",
            "description": "List recent memory entries, optionally filtered by namespace.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "namespace": ["type": "string"],
                    "limit": ["type": "integer"]
                ]
            ]
        ],
        [
            "name": "memory_delete",
            "description": "Delete a memory entry by id.",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ]
        ]
    ]
}

public enum MCPError: Error {
    case invalidArgument(String)
    case unknownTool(String)
}
