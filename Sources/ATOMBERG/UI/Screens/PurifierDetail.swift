import SwiftUI

/// The control that sent the last command, so only that control shows the pending pulse.
enum PurifierControl {
    case mode, sleepWindow, idleSleep
}

struct PurifierDetail: View {
    let id: String
    let onBack: () -> Void
    @Environment(DeviceStore.self) private var store
    @State private var lastControl: PurifierControl?

    private var snapshot: DeviceSnapshot? { store.snapshots.first { $0.id == id } }
    private var reading: PurifierState? { DeviceFacts.purifier(snapshot) }
    private var phase: CommandPhase { store.phases[id] ?? .idle }
    private var offline: Bool { store.links[id] == .offline }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: snapshot?.info.name ?? "Purifier", status: headerStatus, onBack: onBack) {
                EmptyView()
            }
            VStack(alignment: .leading, spacing: 8) {
                if let message = DeviceFacts.failureMessage(phase) {
                    FailureLine(message: message)
                        .transition(.opacity)
                }
                Card {
                    SectionLabel("Water quality", trailing: "TDS, ppm")
                    waterQuality
                        .padding(.horizontal, Metric.side)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                    if let reading, DeviceFacts.isFaulted(reading) {
                        Hairline().padding(.horizontal, Metric.side)
                        faultBlock(reading)
                    }
                }
                Card {
                    SectionLabel("Mode")
                    VStack(spacing: 0) {
                        ForEach(PurifierMode.allCases, id: \.self) { mode in
                            if mode == .tasteTune50to100 || mode == .vacay {
                                MenuSeparator()
                            }
                            ModeRow(title: mode.label, checked: reading?.mode == mode) {
                                select(mode)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                Card {
                    SectionLabel("Schedule")
                    SwitchRow(title: "Sleep window", subtitle: windowText) {
                        Toggle("Sleep window", isOn: Binding(get: { reading?.sleepWindowOn ?? false }, set: { setSleepWindow($0) }))
                            .toggleStyle(DeviceSwitchStyle(tint: Palette.purifierTint, phase: controlPhase(.sleepWindow)))
                            .labelsHidden()
                    }
                    Hairline().padding(.horizontal, Metric.side)
                    SwitchRow(title: "Idle sleep") {
                        Toggle("Idle sleep", isOn: Binding(get: { reading?.idleSleep ?? false }, set: { send(.idleSleep($0), .idleSleep) }))
                            .toggleStyle(DeviceSwitchStyle(tint: Palette.purifierTint, phase: controlPhase(.idleSleep)))
                            .labelsHidden()
                    }
                }
            }
            if let usage = usageText {
                UsageLine(text: usage)
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .animation(Motion.reveal, value: DeviceFacts.failureMessage(phase))
        .task { await store.refreshAnalyticsIfStale() }
    }

    @ViewBuilder
    private var waterQuality: some View {
        if let stored = reading?.storedTDS, let inlet = reading?.inputTDS {
            WaterComparison(stored: stored, inlet: inlet)
        } else {
            Text("No reading yet")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondary)
                .frame(height: 60, alignment: .leading)
        }
    }

    private func faultBlock(_ reading: PurifierState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(reading.faultDescriptions.first ?? "Filter choked")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.label)
            Text("Flow is restricted. Replace the pre-filter.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondary)
        }
        .lineLimit(1)
        .padding(.horizontal, Metric.side)
        .padding(.vertical, 12)
    }

    private var headerStatus: StatusText {
        if offline {
            return StatusText(glyph: .offline, text: snapshot.flatMap { DeviceFacts.lastSeenText($0) } ?? "Offline")
        }
        guard let reading else { return StatusText(text: "Waiting for status") }
        if DeviceFacts.isFaulted(reading) { return StatusText(glyph: .attention, text: "Needs attention") }
        return StatusText(glyph: .cloud, text: "Cloud")
    }

    private var windowText: String? {
        guard let start = reading?.sleepStartUTC, let stop = reading?.sleepStopUTC else { return nil }
        return "\(DeviceFacts.clock(utcSeconds: start)) to \(DeviceFacts.clock(utcSeconds: stop))"
    }

    private var usageText: String? {
        let analytics = snapshot?.purifierAnalytics
        let water = analytics?.waterSavedLiters.map { "\(DeviceFacts.whole($0).formatted()) L water saved" }
        let uv = analytics?.uvRuntimeHours.map { "UV lamp \(DeviceFacts.whole($0).formatted()) h" }
        let model = snapshot.flatMap { DeviceFacts.modelName($0.info) }
        let parts = [model, water, uv].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Turning the window on needs both times; without them there is nothing to send.
    private func setSleepWindow(_ on: Bool) {
        guard on else {
            send(.sleepWindowOff, .sleepWindow)
            return
        }
        guard let start = reading?.sleepStartUTC, let stop = reading?.sleepStopUTC else { return }
        send(.sleepWindow(startUTC: start, stopUTC: stop), .sleepWindow)
    }

    private func select(_ mode: PurifierMode) {
        guard reading?.mode != mode else { return }
        send(.mode(mode), .mode)
    }

    private func send(_ command: PurifierCommand, _ control: PurifierControl) {
        lastControl = control
        Task { await store.send(.purifier(command), to: id) }
    }

    private func controlPhase(_ control: PurifierControl) -> CommandPhase {
        lastControl == control ? phase : .idle
    }
}

/// Two values on one 0–300 ppm line: stored (filled) and inlet (ring), joined by the span
/// the purifier removes.
private struct WaterComparison: View {
    let stored: Double
    let inlet: Double
    var scaleMax: Double = 300
    var width: CGFloat = Metric.content

    var body: some View {
        let xs = x(stored)
        let xi = x(inlet)
        let lineY: CGFloat = 34
        let r: CGFloat = 4.5
        ZStack(alignment: .topLeading) {
            value(stored, color: Palette.label).position(x: xs, y: 12)
            value(inlet, color: Palette.secondary).position(x: xi, y: 12)
            Rectangle().fill(Palette.separator)
                .frame(width: max(0, xs - r), height: Metric.hairline)
                .position(x: max(0, xs - r) / 2, y: lineY)
            Rectangle().fill(Palette.separator)
                .frame(width: max(0, width - xi - r), height: Metric.hairline)
                .position(x: (xi + r + width) / 2, y: lineY)
            Capsule().fill(Palette.label.opacity(0.22))
                .frame(width: max(0, xi - xs - 2 * r), height: 3)
                .position(x: (xs + xi) / 2, y: lineY)
            Circle().fill(Palette.label)
                .frame(width: 2 * r, height: 2 * r)
                .position(x: xs, y: lineY)
            Circle().strokeBorder(Palette.secondary, lineWidth: 1.5)
                .frame(width: 2 * r, height: 2 * r)
                .position(x: xi, y: lineY)
            caption("Stored").position(x: xs, y: 52)
            caption("Inlet").position(x: xi, y: 52)
        }
        .frame(width: width, height: 60)
        .accessibilityElement()
        .accessibilityLabel("Water quality")
        .accessibilityValue("Stored \(DeviceFacts.whole(stored)) ppm, inlet \(DeviceFacts.whole(inlet)) ppm")
    }

    private func x(_ v: Double) -> CGFloat {
        CGFloat(min(max(v, 0), scaleMax) / scaleMax) * width
    }

    private func value(_ v: Double, color: Color) -> some View {
        Text("\(DeviceFacts.whole(v))")
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .fixedSize()
    }

    private func caption(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11))
            .foregroundStyle(Palette.secondary)
            .fixedSize()
    }
}

/// Menu-style row: checkmark in a 20pt gutter, title at x 44, capsule hover.
private struct ModeRow: View {
    let title: String
    var checked = false
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.label)
                .opacity(checked ? 1 : 0)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Palette.label)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metric.side)
        .frame(height: 28)
        .hoverHighlight()
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(checked ? [.isButton, .isSelected] : .isButton)
    }
}

private struct MenuSeparator: View {
    var body: some View {
        Hairline()
            .padding(.horizontal, Metric.side)
            .padding(.vertical, 4)
    }
}
