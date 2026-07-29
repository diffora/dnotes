import Foundation

/// A dispatch-queue-backed FSEvents stream with a trailing debounce. No run loop is
/// involved, so this behaves the same in the app and in tests.
public final class FolderWatcher: @unchecked Sendable {
    private let folder: URL
    private let debounce: Int
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?

    public init(folder: URL,
                debounceMilliseconds: Int = 200,
                queue: DispatchQueue = .main,
                onChange: @escaping @Sendable () -> Void) {
        self.folder = folder
        self.debounce = debounceMilliseconds
        self.queue = queue
        self.onChange = onChange
    }

    deinit { stop() }

    public func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().schedule()
        }

        // Latency 0 — the debounce below is the one that should decide the cadence,
        // and it is the one we can test.
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [folder.path as CFString] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
                                     | kFSEventStreamCreateFlagNoDefer)
        ) else { return }

        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    public func stop() {
        pending?.cancel()
        pending = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// A `git checkout` or a cloud sync changes a batch of files at once; there is no
    /// reason to parse the folder once per event in the batch (§5.1).
    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [onChange] in onChange() }
        pending = item
        queue.asyncAfter(deadline: .now() + .milliseconds(debounce), execute: item)
    }
}
