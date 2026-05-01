import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Listens on a Unix domain socket for hook events posted by the
/// `claude-swarm-hook-notify` script. Each connection sends a single
/// JSON object terminated by newline, then closes.
///
/// Uses a `DispatchSourceRead` on the listening fd so the read loop
/// responds promptly to `stop()` — a raw blocking `accept()` doesn't
/// participate in Swift task cancellation and would hang until the next
/// connection arrived.
public final class HookSocketServer {
    public typealias Handler = @Sendable (HookEvent) -> Void

    nonisolated(unsafe) private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let socketURL: URL
    private let handler: Handler
    private let lock = NSLock()
    private var socketFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let acceptQueue = DispatchQueue(label: "com.claudeswarm.hooksocket", qos: .utility)

    public init(socketURL: URL, handler: @escaping Handler) {
        self.socketURL = socketURL
        self.handler = handler
    }

    public func start() throws {
        try? FileManager.default.removeItem(at: socketURL)
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }

        // Make accept non-blocking so the dispatch source drives reads.
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = socketURL.path
        _ = withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
            path.utf8CString.withUnsafeBufferPointer { src in
                memcpy(rawBuf.baseAddress, src.baseAddress, min(src.count, rawBuf.count - 1))
            }
        }

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { close(fd); throw POSIXError(.EADDRINUSE) }
        guard listen(fd, 64) == 0 else { close(fd); throw POSIXError(.EIO) }

        lock.lock()
        socketFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        let handler = self.handler
        source.setEventHandler { [weak self] in
            guard self != nil else { return }
            while true {
                var clientAddr = sockaddr_un()
                var len = socklen_t(MemoryLayout<sockaddr_un>.size)
                let clientFD = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(fd, $0, &len)
                    }
                }
                if clientFD < 0 { break }   // EAGAIN / no more pending
                DispatchQueue.global(qos: .utility).async {
                    Self.serveOne(clientFD: clientFD, handler: handler)
                }
            }
        }
        source.resume()
        acceptSource = source
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        acceptSource?.cancel()
        acceptSource = nil
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
            try? FileManager.default.removeItem(at: socketURL)
        }
    }

    deinit { stop() }

    private static func serveOne(clientFD: Int32, handler: @escaping Handler) {
        defer { close(clientFD) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(clientFD, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(chunk, count: n)
            if buffer.contains(0x0a) { break }
        }
        guard !buffer.isEmpty else { return }
        if let event = try? Self.decoder.decode(HookEvent.self, from: buffer) {
            handler(event)
        }
    }
}
