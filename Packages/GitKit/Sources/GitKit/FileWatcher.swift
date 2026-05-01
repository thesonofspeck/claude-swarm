import Foundation

/// Tiny FSEvents-style file watcher built on `DispatchSource.makeFileSystemObjectSource`.
/// Coalesces bursts of events with a debounce so callers don't get hammered.
public final class FileWatcher: @unchecked Sendable {
    private let url: URL
    private let debounce: TimeInterval
    private let onChange: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private let queue = DispatchQueue(label: "com.claudeswarm.filewatcher", qos: .utility)
    private var pendingWork: DispatchWorkItem?

    public init(url: URL, debounce: TimeInterval = 0.4, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() {
        stop()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        fd = descriptor
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete, .attrib, .link],
            queue: queue
        )
        s.setEventHandler { [weak self] in self?.coalesce() }
        s.setCancelHandler { [fd = descriptor] in close(fd) }
        s.resume()
        source = s
    }

    public func stop() {
        pendingWork?.cancel()
        pendingWork = nil
        source?.cancel()
        source = nil
        fd = -1
    }

    deinit { stop() }

    private func coalesce() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
