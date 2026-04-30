import Foundation

public final class TranscriptRecorder {
    private let url: URL
    private var handle: FileHandle?
    private let queue = DispatchQueue(label: "com.claudeswarm.transcript", qos: .utility)

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        self.handle = try FileHandle(forWritingTo: url)
        try handle?.seekToEnd()
    }

    public func append(_ data: Data) {
        queue.async { [weak self] in
            try? self?.handle?.write(contentsOf: data)
        }
    }

    public func close() {
        queue.async { [weak self] in
            try? self?.handle?.close()
            self?.handle = nil
        }
    }
}
