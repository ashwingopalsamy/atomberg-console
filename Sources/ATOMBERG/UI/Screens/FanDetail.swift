import SwiftUI

/// The control that sent the last command. The store tracks one phase per device, so only
/// that control shows the pending pulse and the others stay still.
enum FanControl {
    case power, speed, sleep, light, brightness, colour, timer
}

struct FanDetail: View {
    let id: String
    let onBack: () -> Void
    @Environment(DeviceStore.self) private var store
    @State private var lastControl: FanControl?
    @State private var speedDraft: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let timerHours = [0, 1, 2, 3, 6]

    private var snapshot: DeviceSnapshot? { store.snapshots.first { $0.id == id } }
    private var fan: FanState? { DeviceFacts.fan(snapshot) }
    private var linkState: LinkState? { store.links[id] }
    private var offline: Bool { linkState == .offline }
    private var phase: CommandPhase { store.phases[id] ?? .idle }
    /// Powered on and reachable. The blade and the detent follow this, not the stored power flag.
    private var isRunning: Bool { store.runningSpeed(of: id) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: snapshot?.info.name ?? "Fan", status: headerStatus, onBack: onBack) {
                if fan != nil, !offline {
                    Toggle("Power", isOn: Binding(get: { fan?.power ?? false }, set: { send(.power($0), .power) }))
                        .toggleStyle(DeviceSwitchStyle(tint: Palette.fanTint, phase: controlPhase(.power)))
                        .labelsHidden()
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if let message = DeviceFacts.failureMessage(phase) {
                    FailureLine(message: message)
                        .transition(.opacity)
                }
                if let state = fan {
                    VStack(alignment: .leading, spacing: 8) {
                        Card {
                            SpeedSection(speed: speedBinding(committed: state.speed), isOn: isRunning,
                                         pending: DeviceFacts.inFlight(controlPhase(.speed))) { value in
                                // Fires at every gesture end, including one that lands on the shown detent.
                                if value != state.speed { send(.speed(value), .speed) }
                                speedDraft = nil
                            }
                        }
                        Card { settings(state) }
                    }
                    .disabled(offline)
                    .opacity(offline ? 0.45 : 1)
                } else {
                    Card { waiting }
                }
            }
            if let usage = usageText {
                UsageLine(text: usage)
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .animation(Motion.reveal, value: DeviceFacts.failureMessage(phase))
        .animation(Motion.pick(Motion.popover, reduceMotion), value: fan?.light)
        .task { await store.refreshAnalyticsIfStale() }
    }

    @ViewBuilder
    private func settings(_ state: FanState) -> some View {
        SwitchRow(title: "Sleep mode") {
            Toggle("Sleep mode", isOn: Binding(get: { fan?.sleep ?? false }, set: { send(.sleep($0), .sleep) }))
                .toggleStyle(DeviceSwitchStyle(tint: Palette.fanTint, phase: controlPhase(.sleep)))
                .labelsHidden()
        }
        Hairline().padding(.horizontal, Metric.side)
        if let brightness = state.brightness {
            SwitchRow(title: "Light") {
                Toggle("Light", isOn: Binding(get: { fan?.light ?? false }, set: { send(.light($0), .light) }))
                    .toggleStyle(DeviceSwitchStyle(tint: Palette.fanTint, phase: controlPhase(.light)))
                    .labelsHidden()
            }
            if state.light {
                BrightnessRow(level: brightness, phase: controlPhase(.brightness)) {
                    send(.brightness($0), .brightness)
                }
                .transition(.opacity)
                LabeledRow(label: "Colour", subordinate: true) {
                    CapsuleSegmented(items: ["Warm", "Cool", "Daylight"], selection: colourSelection)
                        .modifier(PendingPulse(active: DeviceFacts.inFlight(controlPhase(.colour))))
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Light colour")
                }
                .transition(.opacity)
            }
            Hairline().padding(.horizontal, Metric.side)
        }
        LabeledRow(label: "Timer", subtitle: timerSubtitle(state)) {
            CapsuleSegmented(items: ["Off", "1h", "2h", "3h", "6h"], selection: timerSelection)
                .modifier(PendingPulse(active: DeviceFacts.inFlight(controlPhase(.timer))))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Timer")
        }
    }

    private func timerSubtitle(_ state: FanState) -> String? {
        guard !DeviceFacts.inFlight(controlPhase(.timer)),
              let end = DeviceFacts.timerEndsAt(state, reportedAt: state.reportedAt ?? snapshot?.lastUpdated)
        else { return nil }
        return "Off at \(DeviceFacts.clock(end))"
    }

    private var headerStatus: StatusText {
        if linkState == .offline {
            return StatusText(glyph: .offline, text: snapshot.flatMap { DeviceFacts.lastSeenText($0) } ?? "Offline")
        }
        guard fan != nil else { return StatusText(text: "Waiting for status") }
        return linkState == .local ? StatusText(glyph: .local, text: "Local") : StatusText(glyph: .cloud, text: "Cloud")
    }

    private var waiting: some View {
        HStack(spacing: 8) {
            if store.isRefreshing { Spinner(size: 12) }
            Text(store.isRefreshing ? "Waiting for the fan’s status" : "No status from the fan yet.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metric.side)
        .frame(height: Metric.controlRow)
    }

    private var usageText: String? {
        let analytics = snapshot?.fanAnalytics
        let energy = analytics?.energyKWh.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kWh used" }
        let hours = analytics?.runtimeHours.map { "\(DeviceFacts.whole($0).formatted()) h running" }
        let model = snapshot.flatMap { DeviceFacts.modelName($0.info) }
        let parts = [model, energy, hours].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func speedBinding(committed: Int) -> Binding<Int> {
        DeviceFacts.speedBinding(draft: $speedDraft, committed: committed)
    }

    private var colourSelection: Binding<Int> {
        Binding(
            get: { LightColour.allCases.firstIndex(of: fan?.colour ?? .warm) ?? 0 },
            set: { index in
                guard LightColour.allCases.indices.contains(index) else { return }
                let colour = LightColour.allCases[index]
                guard colour != fan?.colour else { return }
                send(.colour(colour), .colour)
            })
    }

    private var timerSelection: Binding<Int> {
        Binding(
            get: { FanDetail.timerHours.firstIndex(of: fan?.timerHours ?? 0) ?? 0 },
            set: { index in
                guard FanDetail.timerHours.indices.contains(index) else { return }
                let hours = FanDetail.timerHours[index]
                guard hours != fan?.timerHours else { return }
                send(.timerHours(hours), .timer)
            })
    }

    private func send(_ command: FanCommand, _ control: FanControl) {
        lastControl = control
        Task { await store.send(.fan(command), to: id) }
    }

    private func controlPhase(_ control: FanControl) -> CommandPhase {
        lastControl == control ? phase : .idle
    }
}

/// Brightness slider. It has no detent, so the command goes out when a drag ends; a VoiceOver
/// step has no drag and commits after the debounce. Only a commit clears the draft: an observer
/// that cleared it would snap the slider mid-drag or while a command settles.
private struct BrightnessRow: View {
    let level: Int
    let phase: CommandPhase
    let onCommit: (Int) -> Void
    @State private var draft: Double?
    @State private var debounce: Task<Void, Never>?
    @GestureState private var dragging = false

    var body: some View {
        let shown = draft ?? Double(level)
        LabeledRow(label: "Brightness", subordinate: true) {
            HStack(spacing: 8) {
                CapsuleSlider(value: Binding(get: { draft ?? Double(level) }, set: { edit($0) }),
                              range: 10...100,
                              width: 148,
                              label: "Brightness")
                    // CapsuleSlider has no end-of-drag callback, so the drag's end is observed here.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .updating($dragging) { _, state, _ in state = true }
                            .onEnded { _ in schedule() })
                Text("\(Int(shown))%")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    private func edit(_ value: Double) {
        draft = value
        schedule()
    }

    private func schedule() {
        let committed = level
        // A target equal to the shown level changes no state, so it would never be acknowledged.
        // While a command is unacknowledged the last value must still be sent, or the stale one wins.
        let unacknowledged = DeviceFacts.inFlight(phase)
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(300))
            // A pause mid-drag must not commit: the drag's end schedules the commit instead.
            guard !Task.isCancelled, !dragging, let value = draft else { return }
            let target = Int(value.rounded())
            if target != committed || unacknowledged { onCommit(target) }
            draft = nil
        }
    }
}
