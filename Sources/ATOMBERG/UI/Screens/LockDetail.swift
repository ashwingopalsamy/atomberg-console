import SwiftUI

enum PinStage: Equatable {
    case idle
    case confirming
    case issued
}

struct LockDetail: View {
    let id: String
    let onBack: () -> Void
    @Environment(DeviceStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: PinStage = .idle
    @State private var guestPin: GuestPin?
    @State private var requesting = false
    @State private var failure: String?

    private var snapshot: DeviceSnapshot? { store.snapshots.first { $0.id == id } }
    private var reading: LockState? { DeviceFacts.lock(snapshot) }
    private var offline: Bool { store.links[id] == .offline }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: snapshot?.info.name ?? "Lock", status: headerStatus, onBack: onBack) {
                EmptyView()
            }
            VStack(alignment: .leading, spacing: 8) {
                Card {
                    Text("\(Image(systemName: "battery.75percent"))  \(batteryPhrase)  ·  \(unlocksText) unlocks")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, Metric.side)
                        .frame(height: 40)
                }
                if stage == .issued, let guestPin {
                    issued(guestPin)
                } else {
                    Card {
                        SectionLabel("Guest PIN")
                        idle
                    }
                }
            }
            if let model = snapshot.flatMap({ DeviceFacts.modelName($0.info) }) {
                UsageLine(text: model)
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .overlay(alignment: .top) {
            if stage == .confirming {
                confirmation
            }
        }
    }

    private var headerStatus: StatusText {
        if offline {
            return StatusText(glyph: .offline, text: snapshot.flatMap { DeviceFacts.lastSeenText($0) } ?? "Offline")
        }
        if let percent = reading?.batteryPercent, percent <= DeviceFacts.lowBatteryPercent {
            return StatusText(glyph: .attention, text: "Battery low")
        }
        return StatusText(glyph: .cloud, text: "Cloud")
    }

    private var batteryPhrase: String {
        reading?.batteryPercent.map { "\($0)% battery" } ?? "Battery unknown"
    }

    private var unlocksText: String {
        reading?.unlockCount.map { $0.formatted() } ?? "—"
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A one-time, 10-digit PIN set by the lock. It works for about 15 minutes and can’t be cancelled once made.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let failure {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Create guest PIN") { set(.confirming) }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
            }
        }
        .padding(.horizontal, Metric.side)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    /// The ticket takes the Guest PIN card's place, so it sits on the card's inset (groupInset).
    private func issued(_ pin: GuestPin) -> some View {
        VStack(spacing: 12) {
            PinTicket(pin: pin)
                .padding(.horizontal, Metric.groupInset)
            HStack(spacing: 8) {
                Spacer()
                CopyButton(value: pin.code)
                Button("Done", action: finish)
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
            }
            .padding(.horizontal, Metric.side)
        }
    }

    private var confirmation: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: Metric.popoverRadius, style: .continuous)
                .fill(Color.black.opacity(0.06))
            CreatePinSheet(working: requesting, onCancel: { set(.idle) }, onCreate: createPin)
                .padding(.top, Metric.detailHeader + 8)
                .padding([.horizontal, .bottom], Metric.groupInset)
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8)))
    }

    /// Cancel is disabled while the request is in flight: once the lock has made a PIN, it cannot be cancelled.
    private func createPin() {
        guard !requesting else { return }
        requesting = true
        failure = nil
        Task {
            do {
                let created = try await store.requestGuestPin(for: id)
                requesting = false
                guestPin = created
                set(.issued)
            } catch {
                requesting = false
                failure = "Couldn’t create a PIN. \(DeviceFacts.cloudErrorText(error))"
                set(.idle)
            }
        }
    }

    private func finish() {
        withAnimation(Motion.pick(Motion.sheet, reduceMotion)) {
            stage = .idle
            guestPin = nil
        }
    }

    private func set(_ next: PinStage) {
        withAnimation(Motion.pick(Motion.sheet, reduceMotion)) { stage = next }
    }
}

private struct CreatePinSheet: View {
    let working: Bool
    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Create a guest PIN?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.label)
                .lineLimit(1)
            Text("The lock sets a 10-digit PIN that works for about 15 minutes. Once it’s made, it can’t be cancelled.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(CapsuleButtonStyle(fill: true))
                    .disabled(working)
                Button(action: onCreate) {
                    HStack(spacing: 6) {
                        if working { Spinner(size: 11) }
                        Text("Create")
                    }
                }
                .buttonStyle(CapsuleButtonStyle(prominent: true, fill: true))
                .disabled(working)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Metric.groupRadius, style: .continuous).fill(Palette.window))
        .overlay(
            RoundedRectangle(cornerRadius: Metric.groupRadius, style: .continuous)
                .strokeBorder(Palette.separator, lineWidth: Metric.hairline)
        )
    }
}

private struct PinTicket: View {
    let pin: GuestPin

    var body: some View {
        let shape = TicketShape(perforationY: 64)
        VStack(spacing: 0) {
            PinDigits(code: pin.code)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
            DashedLine()
                .stroke(Palette.separator, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(height: 1)
                .padding(.horizontal, 4)
            HStack {
                Text("Valid \(DeviceFacts.clock(pin.validFrom)) to \(DeviceFacts.clock(pin.validUntil))")
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 8)
                Countdown(until: pin.validUntil)
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 36)
        }
        .padding(.horizontal, 8)
        .background(shape.fill(Palette.groupFill))
        .overlay(shape.stroke(Palette.separator, lineWidth: Metric.hairline))
    }
}

private struct TicketShape: Shape {
    var radius: CGFloat = Metric.groupRadius
    var notch: CGFloat = 6
    var perforationY: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        let y = rect.minY + perforationY - notch
        let left = Path(ellipseIn: CGRect(x: rect.minX - notch, y: y, width: notch * 2, height: notch * 2))
        let right = Path(ellipseIn: CGRect(x: rect.maxX - notch, y: y, width: notch * 2, height: notch * 2))
        return body.subtracting(left).subtracting(right)
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// SF Mono digits grouped 4-4-2, revealed left to right with a 40 ms stagger.
private struct PinDigits: View {
    let code: String
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let digits = Array(code)
        HStack(spacing: 0) {
            ForEach(digits.indices, id: \.self) { index in
                Text(String(digits[index]))
                    .font(.system(size: 26, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.label)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: (revealed || reduceMotion) ? 0 : 4)
                    .animation(reduceMotion ? Motion.reduced : Motion.reveal.delay(Double(index) * Motion.digitStagger),
                               value: revealed)
                    .padding(.trailing, index == 3 || index == 7 ? 12 : 1)
            }
        }
        .onAppear { revealed = true }
        .accessibilityElement()
        .accessibilityLabel("Guest PIN")
        .accessibilityValue(digits.map { String($0) }.joined(separator: " "))
    }
}

/// "14:12 left", counting down once a second and stopping at zero.
private struct Countdown: View {
    let until: Date
    @State private var now = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let left = max(0, Int(until.timeIntervalSince(now).rounded(.up)))
        Text(String(format: "%d:%02d left", left / 60, left % 60))
            .fontWeight(.medium)
            .foregroundStyle(Palette.label)
            .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
            .animation(Motion.numeric, value: left)
            .task(id: until) {
                repeat {
                    now = .now
                    if now >= until { break }
                    try? await Task.sleep(for: .seconds(1))
                } while !Task.isCancelled
            }
    }
}
