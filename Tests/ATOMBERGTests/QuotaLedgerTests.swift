import Foundation
import Testing
@testable import ATOMBERG

@Suite("Daily call ledger")
struct QuotaLedgerTests {
    private func makeLedger(limit: Int = 10, reserve: Int = 3, now: @escaping @Sendable () -> Date = { Date() }) -> QuotaLedger {
        let file = FileManager.default.temporaryDirectory.appending(path: "quota-\(UUID().uuidString).json")
        return QuotaLedger(fileURL: file, dailyLimit: limit, reserve: reserve, clock: now)
    }

    @Test func backgroundReadsStopAtTheReserve() async {
        let ledger = makeLedger()
        var granted = 0
        for _ in 0..<10 where await ledger.reserve(.background) { granted += 1 }
        #expect(granted == 7)                         // 10 − reserve of 3
        #expect(await ledger.reserve(.essential))     // the reserve is for the user's own actions
    }

    @Test func everyAttemptCounts() async {
        let ledger = makeLedger()
        _ = await ledger.reserve(.essential)
        _ = await ledger.reserve(.essential)
        #expect(await ledger.status().used == 2)
        #expect(await ledger.status().remaining == 8)
    }

    @Test func rollsOverAtUTCMidnight() async {
        let box = DateBox(Date(timeIntervalSince1970: 86_400 * 100 + 3_600))
        let ledger = makeLedger { box.value }
        _ = await ledger.reserve(.essential)
        #expect(await ledger.status().used == 1)
        box.value = Date(timeIntervalSince1970: 86_400 * 101 + 60)
        #expect(await ledger.status().used == 0)
    }
}

private final class DateBox: @unchecked Sendable {
    var value: Date
    init(_ value: Date) { self.value = value }
}
