import Foundation

/// Counts every HTTP attempt against the daily limit. Days are UTC, stored as days since the epoch,
/// which makes the UTC midnight boundary exact.
actor QuotaLedger: QuotaAccounting {
    private struct Record: Codable, Equatable {
        var day: Int
        var used: Int
    }

    private let fileURL: URL
    private let dailyLimit: Int
    private let backgroundReserve: Int
    private let clock: @Sendable () -> Date
    private var record: Record

    init(
        fileURL: URL? = nil,
        dailyLimit: Int = QuotaPolicy.dailyLimit,
        reserve: Int = QuotaPolicy.reserve,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        let url = fileURL ?? Self.defaultFileURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.fileURL = url
        self.dailyLimit = dailyLimit
        self.backgroundReserve = reserve
        self.clock = clock
        // A corrupt file resets the count, which can undercount that day. Refusing every call
        // on a bad file would be worse for the user.
        self.record = Self.load(from: url) ?? Record(day: Self.day(of: clock()), used: 0)
    }

    func status() async -> QuotaStatus {
        let current = today()
        return QuotaStatus(
            used: current.used,
            limit: dailyLimit,
            resetsAt: Date(timeIntervalSince1970: TimeInterval(current.day + 1) * 86_400)
        )
    }

    func reserve(_ purpose: CallPurpose) async -> Bool {
        var current = today()
        if purpose == .background, current.used >= dailyLimit - backgroundReserve {
            return false
        }
        current.used += 1
        record = current
        save()
        return true
    }

    /// Rolls the record over at UTC midnight. The rollover is persisted so the file never claims
    /// yesterday's count for today.
    private func today() -> Record {
        let day = Self.day(of: clock())
        if record.day != day {
            record = Record(day: day, used: 0)
            save()
        }
        return record
    }

    /// A failed write keeps the in-memory count authoritative for this session.
    private func save() {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func day(of date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    private static func load(from url: URL) -> Record? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private static func defaultFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("ATOMBERG/quota.json")
    }
}
