import Foundation

/// Spaces cloud attempts so consecutive starts are at least `minimumGap` apart.
/// The slot is claimed before suspending, so concurrent callers queue in arrival order.
actor RateGate {
    private let minimumGap: Duration
    private var nextStart: ContinuousClock.Instant?

    init(minimumGap: TimeInterval = Timing.cloudMinimumGap) {
        self.minimumGap = .seconds(minimumGap)
    }

    func wait() async {
        let now = ContinuousClock.now
        let start = max(now, nextStart ?? now)
        nextStart = start.advanced(by: minimumGap)
        if start > now {
            try? await Task.sleep(until: start, clock: ContinuousClock())
        }
    }
}
