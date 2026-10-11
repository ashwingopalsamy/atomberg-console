import Foundation
import Testing
@testable import ATOMBERG

@Suite("Command routing")
struct RoutingTests {
    private let plenty = QuotaStatus(used: 10, limit: 100, resetsAt: .distantFuture)
    private let none = QuotaStatus(used: 100, limit: 100, resetsAt: .distantFuture)

    @Test func aHeardFanIsControlledLocally() {
        #expect(Routing.route(for: .fan(.speed(4)), kind: .fan, lanPresent: true, quota: none) == .lan)
    }

    @Test func anUnheardFanUsesTheCloud() {
        #expect(Routing.route(for: .fan(.speed(4)), kind: .fan, lanPresent: false, quota: plenty) == .cloud)
    }

    @Test func withNoCallsLeftAndNoLocalRouteItSaysSo() {
        let route = Routing.route(for: .fan(.power(true)), kind: .fan, lanPresent: false, quota: none)
        guard case .unavailable = route else {
            Issue.record("expected unavailable, got \(route)")
            return
        }
    }

    @Test func purifiersNeverGoLocal() {
        #expect(Routing.route(for: .purifier(.idleSleep(true)), kind: .waterPurifier, lanPresent: true, quota: plenty) == .cloud)
    }
}
