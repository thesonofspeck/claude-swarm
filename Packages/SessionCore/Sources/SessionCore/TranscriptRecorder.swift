import Foundation

public final class TranscriptRecorder {
    private let url: URL
    private let maxBytes: UInt64
    private var handle: FileHandle?
    private var bytesWritten: UInt64 = 0
    private var closed = false
    private let queue = DispatchQueue(label: "com.claudeswarm.transcript", qos: .utility)

    /// Default 10 MiB cap. When exceeded, the file is renamed to `<name>.1`
    /// (overwriting any prior `.1`) and a fresh transcript is started.
    public init(url: URL, maxBytes: UInt64 = 10 * 1024 * 1024) throws {
        self.url = url
        self.maxBytes = maxBytes
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        self.handle = handle
        self.bytesWritten = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }

    deinit {
        // Ensure the file handle is released even if `close()` was never
        // called. Run synchronously on the queue so we don't race a
        // pending append().
        queue.sync {
            try? handle?.close()
            handle = nil
            closed = true
        }
    }

    public func append(_ data: Data) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            if self.bytesWritten + UInt64(data.count) > self.maxBytes {
                self.rotate()
            }
            guard let handle = self.handle else { return }
            do {
                try handle.write(contentsOf: data)
                self.bytesWritten += UInt64(data.count)
            } catch {
                // Disk full or handle invalidated — stop recording rather
                // than spam errors per write.
                try? handle.close()
                self.handle = nil
                self.closed = true
            }
        }
    }

    public func close() {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            try? self.handle?.close()
            self.handle = nil
            self.closed = true
        }
    }

    /// Always called from inside `queue` — no external lock needed.
    private func rotate() {
        try? handle?.close()
        handle = nil
        let archive = url.deletingPathExtension().appendingPathExtension(
            "\(url.pathExtension).1"
        )
        try? FileManager.default.removeItem(at: archive)
        try? FileManager.default.moveItem(at: url, to: archive)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        bytesWritten = 0
        // If we couldn't reopen, mark closed so further appends are no-ops
        // instead of trying to write to a non-existent handle.
        if handle == nil { closed = true }
    }
}
