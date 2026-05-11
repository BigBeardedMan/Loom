import Foundation

/// Watches a single file for external changes via DispatchSource.
/// Fires the onChange callback on the main queue when the file is
/// written, extended, or replaced. Caller decides what to do with it.
@MainActor
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var url: URL?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit {
        let src = source
        let fd = fileDescriptor
        Task { @MainActor in
            src?.cancel()
        }
        if fd >= 0 {
            close(fd)
        }
    }

    func watch(url: URL) {
        stop()
        self.url = url

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        let callback = onChange
        let watcher = self
        src.setEventHandler {
            // .delete or .rename means the file the descriptor pointed at
            // is gone (e.g. an editor saved by rename). Reattach to the
            // path so we keep watching the logical file.
            let event = src.data
            if event.contains(.delete) || event.contains(.rename) {
                watcher.rewatch()
            }
            callback()
        }
        src.setCancelHandler { [fd] in
            close(fd)
        }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            // The cancel handler closes the fd; clear our copy so we
            // don't double-close on the next watch().
            fileDescriptor = -1
        }
    }

    private func rewatch() {
        guard let url else { return }
        // Drop the old source; reopen the path. Small race here is
        // tolerable; worst case the user gets a second .write event.
        let saved = onChange
        let next = FileWatcher(onChange: saved)
        next.watch(url: url)
        self.source = next.source
        next.source = nil
        self.fileDescriptor = next.fileDescriptor
        next.fileDescriptor = -1
    }
}
