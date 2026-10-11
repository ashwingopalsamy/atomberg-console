import Dispatch
import Network

/// Reports network path changes. NWPathMonitor delivers the current path on start, which is not a change, so the first update is skipped.
final class PathWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "atomberg.lan.path")
    private let onChange: @Sendable () -> Void
    // Confined to `queue`.
    private var monitor: NWPathMonitor?
    private var hasSeenInitialPath = false

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.sync {
            guard monitor == nil else { return }
            let newMonitor = NWPathMonitor()
            newMonitor.pathUpdateHandler = { [weak self] _ in self?.pathDidUpdate() }
            hasSeenInitialPath = false
            newMonitor.start(queue: queue)
            monitor = newMonitor
        }
    }

    func stop() {
        queue.sync {
            monitor?.cancel()
            monitor = nil
        }
    }

    private func pathDidUpdate() {
        guard hasSeenInitialPath else {
            hasSeenInitialPath = true
            return
        }
        onChange()
    }
}
