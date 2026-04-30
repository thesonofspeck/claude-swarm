import Foundation

public final class TranscriptRecorder {
    private let url: URL
    private let maxBytes: UInt64
    private var handle: FileHandle?
    private var bytesWritten: UInt64 = 0
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

    public func append(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.bytesWritten + UInt64(data.count) > self.maxBytes {
                self.rotate()
            }
            try? self.handle?.write(contentsOf: data)
            self.bytesWritten += UInt64(data.count)
        }
    }

    public func close() {
        queue.async { [weak self] in
            try? self?.handle?.close()
            self?.handle = nil
        }
    }

    private func rotate() {
        try? handle?.close()
        let archive = url.deletingPathExtension().appendingPathExtension(
            "\(url.pathExtension).1"
        )
        try? FileManager.default.removeItem(at: archive)
        try? FileManager.default.moveItem(at: url, to: archive)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        bytesWritten = 0
    }
}
