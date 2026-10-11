import Foundation
import Testing
@testable import ATOMBERG

@Suite("Quota reset phrase")
struct QuotaResetTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func phrase(zone: String, now: Date) -> String {
        // 00:00 UTC on 12 October 2026.
        let reset = Date(timeIntervalSince1970: 1_791_763_200)
        let status = QuotaStatus(used: 71, limit: 100, resetsAt: reset)
        // Recent macOS puts a narrow no-break space before AM and PM.
        return status.resetPhrase(now: now, calendar: calendar(zone), locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test func eastOfUTCItResetsTomorrowMorning() {
        // 22:18 in Kolkata on 11 October.
        let now = Date(timeIntervalSince1970: 1_791_739_080)
        #expect(phrase(zone: "Asia/Kolkata", now: now) == "tomorrow at 5:30 AM")
    }

    @Test func westOfUTCItResetsLaterToday() {
        // 09:48 in Los Angeles on 11 October.
        let now = Date(timeIntervalSince1970: 1_791_737_280)
        #expect(phrase(zone: "America/Los_Angeles", now: now) == "today at 5:00 PM")
    }

    @Test func theNextResetIsTheNextUTCMidnight() {
        let now = Date(timeIntervalSince1970: 1_791_739_080)
        let phrase = QuotaStatus.nextResetPhrase(now: now, calendar: calendar("UTC"), locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "\u{202F}", with: " ")
        #expect(phrase == "tomorrow at 12:00 AM")
    }
}
