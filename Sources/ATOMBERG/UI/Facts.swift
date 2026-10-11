import SwiftUI

// MARK: - Shared state and copy

/// Readings, copy and command helpers shared by the popover and the detail screens.
enum DeviceFacts {
    static func fan(_ snapshot: DeviceSnapshot?) -> FanState? {
        guard case .fan(let state)? = snapshot?.reading else { return nil }
        return state
    }

    static func purifier(_ snapshot: DeviceSnapshot?) -> PurifierState? {
        guard case .purifier(let state)? = snapshot?.reading else { return nil }
        return state
    }

    static func lock(_ snapshot: DeviceSnapshot?) -> LockState? {
        guard case .lock(let state)? = snapshot?.reading else { return nil }
        return state
    }

    static func isFaulted(_ state: PurifierState) -> Bool {
        state.filterChoked || !state.faultDescriptions.isEmpty
    }

    static func inFlight(_ phase: CommandPhase) -> Bool {
        if case .pending = phase { return true }
        return false
    }

    /// The store's message for a failed command. Nil while idle or pending.
    static func failureMessage(_ phase: CommandPhase) -> String? {
        guard case .failed(let message, _) = phase else { return nil }
        return message
    }

    /// Rounds a network value for display. The clamp keeps `Int(_:)` from trapping on a huge or negative value.
    static func whole(_ value: Double) -> Int {
        Int(min(max(value.rounded(), 0), 1_000_000))
    }

    static func lastSeen(_ snapshot: DeviceSnapshot) -> Date? {
        let reported: Date?
        switch snapshot.reading {
        case .fan(let state)?: reported = state.reportedAt
        case .purifier(let state)?: reported = state.reportedAt
        case .lock(let state)?: reported = state.reportedAt
        case nil: reported = nil
        }
        return reported ?? snapshot.lastUpdated
    }

    static func ago(since date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(Int(seconds / 60)) min ago"
        case ..<86_400: return "\(Int(seconds / 3_600)) h ago"
        default: return "\(Int(seconds / 86_400)) d ago"
        }
    }

    static func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// The purifier sends a time of day in UTC; it is shown in the user's local zone.
    static func clock(utcSeconds: UInt32) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let midnight = utc.startOfDay(for: .now)
        return clock(midnight.addingTimeInterval(TimeInterval(utcSeconds % 86_400)))
    }

    static func cloudErrorText(_ error: Error) -> String {
        if error is KeychainError { return "Allow Atomberg Console to use the Keychain, then try again." }
        guard let cloud = error as? CloudError else { return error.localizedDescription }
        switch cloud {
        case .deviceOffline: return "The device is offline."
        case .developerModeOff: return "Turn on Developer Mode in Atomberg Home."
        case .quotaExhausted, .quotaReserved: return "No cloud calls left today."
        case .invalidCredentials: return "Check your credentials."
        case .gatewayTimeout: return "The request timed out."
        case .server(_, let message): return message
        case .badRequest(let message), .notFound(let message), .unsupported(let message),
             .network(let message), .decoding(let message):
            return message
        }
    }

    /// "Renesa Halo": the registered model, tidied. The API's `series` (R1, R3, I1…) is an internal hardware code,
    /// so it is only a fallback for a device that has no model.
    static func modelName(_ info: DeviceInfo) -> String? {
        let name = info.model?
            .split(whereSeparator: { $0 == "_" || $0 == "-" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        if let name, !name.isEmpty { return name }
        return info.series.isEmpty ? nil : "Series \(info.series)"
    }

    static let lowBatteryPercent = 20
    static let lowQuotaRemaining = 20

    /// A reachable device that needs the user's action: a purifier fault, or a lock battery at or below 20%.
    static func needsAttention(_ snapshot: DeviceSnapshot, link: LinkState?) -> Bool {
        guard link != .offline else { return false }
        if let state = purifier(snapshot) { return isFaulted(state) }
        if let percent = lock(snapshot)?.batteryPercent { return percent <= lowBatteryPercent }
        return false
    }

    static func attentionText(_ snapshot: DeviceSnapshot) -> String? {
        if let state = purifier(snapshot), isFaulted(state) { return state.faultDescriptions.first ?? "Filter choked" }
        if let percent = lock(snapshot)?.batteryPercent, percent <= lowBatteryPercent { return "Battery low" }
        return nil
    }

    /// The one exception glyph a home row may carry next to its name. The transport has its own glyph.
    static func rowGlyph(for snapshot: DeviceSnapshot, link: LinkState?) -> StatusGlyph? {
        needsAttention(snapshot, link: link) ? .attention : nil
    }

    static func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case 88...: "battery.100percent"
        case 63..<88: "battery.75percent"
        case 38..<63: "battery.50percent"
        case 13..<38: "battery.25percent"
        default: "battery.0percent"
        }
    }

    static func lastSeenText(_ snapshot: DeviceSnapshot) -> String? {
        lastSeen(snapshot).map { "Last seen \(ago(since: $0))" }
    }

    /// VoiceOver wording: "1 hour ago", not "1 h ago".
    static func spokenAgo(since date: Date, now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func offlineSpoken(_ snapshot: DeviceSnapshot) -> String {
        lastSeen(snapshot).map { "Offline, last seen \(spokenAgo(since: $0))" } ?? "Offline"
    }

    /// When a running timer switches the fan off. Nil without a timer or a report time, or once passed.
    static func timerEndsAt(_ state: FanState, reportedAt: Date?, now: Date = .now) -> Date? {
        guard state.timerHours > 0, let reportedAt else { return nil }
        let remaining = state.timerHours * 60 - state.timerElapsedMinutes
        guard remaining > 0 else { return nil }
        let end = reportedAt.addingTimeInterval(TimeInterval(remaining * 60))
        return end > now ? end : nil
    }

    /// The detent's binding. A drag writes only the draft. The detent's `onCommit` sends the
    /// command and clears the draft, so nothing else may clear it.
    static func speedBinding(draft: Binding<Int?>, committed: Int) -> Binding<Int> {
        Binding(
            get: { draft.wrappedValue ?? committed },
            set: { draft.wrappedValue = $0 })
    }
}

/// Pulses a control between full and 45% opacity while its command is in flight (DESIGN §8).
/// Under Reduce Motion it holds at 55%.
struct PendingPulse: ViewModifier {
    let active: Bool
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(active ? (reduceMotion ? 0.55 : (dim ? 0.45 : 1)) : 1)
            .onChange(of: active, initial: true) { _, on in
                guard !reduceMotion else { return }
                withAnimation(on ? Motion.pendingPulse : Motion.reduced) { dim = on }
            }
    }
}
