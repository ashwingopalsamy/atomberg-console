import SwiftUI
import AppKit
import Foundation

// MARK: - Primitives

struct Hairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // One device pixel: 0.5pt at 2x, 1pt at 1x. Row heights are whole points, so it lands on a pixel.
        Rectangle().fill(Palette.separator).frame(height: 1 / displayScale)
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.tertiary)
            .accessibilityHidden(true)
    }
}

/// Trailing value on a home row: 12pt secondary, tabular digits.
struct RowValue: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(Palette.secondary)
            .lineLimit(1)
    }
}

/// Fan speed on a home row: the number itself, 1–6, in a 22pt rounded square. A number reads at a glance
/// and cannot be mistaken for a signal meter.
struct SpeedBadge: View {
    let speed: Int

    var body: some View {
        Text("\(speed)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Palette.label)
            .frame(width: Metric.speedBadge, height: Metric.speedBadge)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.wellFill))
            .help("Speed \(speed) of 6")
            .accessibilityHidden(true)
    }
}

/// A status glyph on a home row's trailing edge: the transport (wifi or cloud) or a struck-through cloud for
/// offline. The tooltip carries the words; the row's VoiceOver value already does.
struct RowGlyph: View {
    let glyph: StatusGlyph
    var help = ""

    init(_ glyph: StatusGlyph, help: String = "") {
        self.glyph = glyph
        self.help = help
    }

    var body: some View {
        Image(systemName: glyph.symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.secondary)
            .frame(width: 16)
            .help(help)
            .accessibilityHidden(true)
    }
}

/// Neutral 24pt symbol well. No hue, ever. Decorative: the row it sits in names the device.
struct Well<Glyph: View>: View {
    @ViewBuilder var glyph: Glyph
    var body: some View {
        glyph
            .frame(width: Metric.well, height: Metric.well)
            .background(Circle().fill(Palette.wellFill))
            .accessibilityHidden(true)
    }
}

/// 11pt status: an optional glyph, then secondary text, on one baseline.
struct StatusLine: View {
    let status: StatusText
    init(_ status: StatusText) { self.status = status }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let glyph = status.glyph {
                Text(Image(systemName: glyph.symbol)).foregroundStyle(glyph.color)
            }
            Text(status.text).foregroundStyle(Palette.secondary)
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .lineLimit(1)
    }
}

// MARK: - Press feedback

/// Capsule push button: 28pt, 14pt side padding, scales to 0.97 in 80ms while pressed.
struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var fill = false
    func makeBody(configuration: Configuration) -> some View {
        CapsuleChrome(prominent: prominent, fill: fill, pressed: configuration.isPressed) {
            configuration.label
        }
    }
}

struct CapsuleChrome<Label: View>: View {
    var prominent = false
    var fill = false
    var pressed = false
    @ViewBuilder var label: Label
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .font(.system(size: 13, weight: prominent ? .semibold : .medium))
            .foregroundStyle(prominent ? Color.white : Palette.label)
            .lineLimit(1)
            .padding(.horizontal, Metric.buttonPadding)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: Metric.capsuleButton)
            .background(Capsule().fill(prominent ? Palette.primary : neutralFill))
            .contentShape(Capsule())
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .opacity(pressed && reduceMotion ? 0.8 : 1)
            .animation(Motion.press, value: pressed)
    }

    private var neutralFill: Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.07)
    }
}

/// 24pt circular icon button with a 28pt hit area. `filled` draws the 24pt circle at rest (header actions);
/// otherwise there is no fill until hover.
struct IconButton: View {
    let symbol: String
    let label: String
    var filled = false
    /// Glyph colour at rest; nil is secondary. A header button that is a switch uses it to show "on".
    var tint: Color? = nil
    /// Shows a spinner in place of the glyph while the action is running.
    var busy = false
    var action: () -> Void = {}
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Group {
                if busy {
                    Spinner(size: 12)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(hovering ? Palette.label : (tint ?? Palette.secondary))
                }
            }
            .frame(width: Metric.hitTarget, height: Metric.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(IconButtonStyle(hovering: hovering, filled: filled))
        .onHover { inside in
            withAnimation(reduceMotion ? nil : Motion.hover) { hovering = inside }
        }
        .help(label)
        .accessibilityLabel(label)
    }
}

struct IconButtonStyle: ButtonStyle {
    let hovering: Bool
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background {
            Circle()
                .fill(fill(pressed: configuration.isPressed))
                .frame(width: Metric.iconButton, height: Metric.iconButton)
        }
    }

    private func fill(pressed: Bool) -> Color {
        if pressed { return Palette.pressed }
        if hovering { return filled ? Palette.hoverStrong : Palette.hover }
        return filled ? Palette.wellFill : Color.clear
    }
}

// MARK: - Switch

/// Device switch as a ToggleStyle. The VoiceOver element is a native Toggle, so the visual
/// body is only a drawing. `phase` drives the failure spring and the pending pulse.
struct DeviceSwitchStyle: ToggleStyle {
    var tint: Color
    var phase: CommandPhase = .idle

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { EmptyView() }
            .buttonStyle(SwitchButtonStyle(isOn: configuration.isOn, tint: tint, phase: phase))
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

private struct SwitchButtonStyle: ButtonStyle {
    let isOn: Bool
    let tint: Color
    let phase: CommandPhase
    func makeBody(configuration: Configuration) -> some View {
        SwitchBody(isOn: isOn, pressed: configuration.isPressed, tint: tint, phase: phase)
    }
}

/// Track 42×20; knob 26×16, growing to 30×16 while pressed (not under Reduce Motion).
/// Spring 0.32 / 0.8. Pulses while a command is pending; springs back on failure.
struct SwitchBody: View {
    let isOn: Bool
    let pressed: Bool
    let tint: Color
    let phase: CommandPhase
    @State private var pulse = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pending: Bool {
        if case .pending = phase { return true }
        return false
    }

    private var failed: Bool {
        if case .failed = phase { return true }
        return false
    }

    var body: some View {
        let knob = pressed && !reduceMotion ? Metric.knobPressed : Metric.knob
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? tint : offTrack)
                .opacity(trackOpacity)
            Capsule()
                .fill(Color.white)
                .frame(width: knob.width, height: knob.height)
                .shadow(color: .black.opacity(0.22), radius: 1, x: 0, y: 0.5)
                .padding(2)
        }
        .frame(width: Metric.switchSize.width, height: Metric.switchSize.height)
        .padding(.vertical, (Metric.hitTarget - Metric.switchSize.height) / 2)   // 42×28 hit area
        .contentShape(Rectangle())
        .animation(reduceMotion ? Motion.reduced : (failed ? Motion.toggleFail : Motion.toggle), value: isOn)
        .animation(reduceMotion ? nil : Motion.toggle, value: pressed)
        .onChange(of: pending, initial: true) { _, isPending in
            if isPending && !reduceMotion {
                withAnimation(Motion.pendingPulse) { pulse = true }
            } else {
                withAnimation(Motion.reduced) { pulse = false }
            }
        }
    }

    private var trackOpacity: Double {
        guard pending else { return 1 }
        if reduceMotion { return 0.55 }   // steady dim instead of a pulse
        return pulse ? 0.45 : 1
    }

    private var offTrack: Color {
        scheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10)
    }
}

// MARK: - Capsule segmented control

/// Capsule track, capsule thumb inset 2pt. 24pt high. No separators.
struct CapsuleSegmented: View {
    let items: [String]
    @Binding var selection: Int
    var width: CGFloat = Metric.controlWidth
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let height = Metric.capsuleControl
        let seg = width / CGFloat(items.count)
        ZStack(alignment: .leading) {
            Capsule().fill(Palette.trackFill).frame(height: height)
            Capsule()
                .fill(thumbFill)
                .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.12), radius: 1, x: 0, y: 0.5)
                .frame(width: seg - 4, height: height - 4)
                .offset(x: seg * CGFloat(selection) + 2)
            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    Button { selection = i } label: {
                        Text(items[i])
                            .font(.system(size: 12, weight: i == selection ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(i == selection ? Palette.label : Palette.secondary)
                            .lineLimit(1)
                            .frame(width: seg, height: Metric.hitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(i == selection ? .isSelected : [])
                }
            }
        }
        .frame(width: width, height: Metric.hitTarget)
        .animation(Motion.pick(Motion.toggle, reduceMotion), value: selection)
    }

    private var thumbFill: Color {
        scheme == .dark ? Color.white.opacity(0.22) : Color.white
    }
}

// MARK: - Speed detent

/// Fan speed as an ordinal six-step control. The level fills up to the selected detent;
/// the capsule thumb snaps between detents with a short spring and an alignment haptic.
/// `speed` is written live during a drag, so a binding can hold a draft. `onCommit` fires once
/// per gesture on every end (release or cancel, even when the detent is unchanged) and once per
/// VoiceOver step. It never fires mid-drag.
struct SpeedDetent: View {
    @Binding var speed: Int
    var width: CGFloat
    var compact = false
    var enabled = true
    var onCommit: ((Int) -> Void)? = nil
    /// Non-nil from touch-down until SwiftUI resets it. A cancel skips onEnded, so this reset is
    /// the only signal a cancelled drag leaves behind.
    @GestureState private var gestureStart: Int? = nil
    /// Detent the thumb is on for the drag in flight. Cleared when reported, so release and
    /// cancel cannot both report one gesture.
    @State private var dragDetent: Int? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let height = compact ? Metric.capsuleControl : Metric.detent
        let seg = width / 6
        let thumbX = seg * CGFloat(speed - 1) + 2
        ZStack(alignment: .leading) {
            Capsule().fill(Palette.trackFill)
            Capsule().fill(Palette.level).frame(width: seg * CGFloat(speed))
            Capsule()
                .fill(thumbFill)
                .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.14), radius: 1, x: 0, y: 0.5)
                .frame(width: seg - 4, height: height - 4)
                .offset(x: thumbX)
            HStack(spacing: 0) {
                ForEach(1...6, id: \.self) { n in
                    Text("\(n)")
                        .font(.system(size: compact ? 11 : 12, weight: n == speed ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(numeralColor(n))
                        .frame(width: seg, height: height)
                }
            }
        }
        .frame(width: width, height: height)
        .opacity(enabled ? 1 : 0.45)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($gestureStart) { _, start, _ in
                    if start == nil, enabled { start = speed }
                }
                .onChanged { value in
                    guard enabled else { return }
                    let step = detent(atX: value.location.x)
                    // Tracked here, not read from the draft: a caller may clear the draft mid-drag.
                    dragDetent = step
                    // Touch-down on the current detent must not tick: only a change does.
                    guard step != speed else { return }
                    speed = step
                    Self.tick()
                }
                .onEnded { _ in reportDrag() }
        )
        .onChange(of: gestureStart) { _, start in
            if start == nil { reportDrag() }
        }
        // A popover closed mid-drag removes the view with no gesture callback at all.
        .onDisappear { reportDrag() }
        .animation(Motion.pick(Motion.detent, reduceMotion), value: speed)
        .accessibilityElement()
        .accessibilityLabel("Fan speed")
        .accessibilityValue("\(speed) of 6")
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            let next: Int
            switch direction {
            case .increment: next = min(6, speed + 1)
            case .decrement: next = max(1, speed - 1)
            @unknown default: return
            }
            guard next != speed else { return }
            speed = next
            // A VoiceOver step is a discrete commit; without it VoiceOver users could not set speed.
            onCommit?(next)
        }
    }

    /// The only x-to-detent mapping. The committed detent is the one the thumb last showed.
    private func detent(atX x: CGFloat) -> Int {
        min(6, max(1, Int(x / (width / 6)) + 1))
    }

    /// Reports the drag's detent once. Release, cancel and removal all land here; the first clears it.
    private func reportDrag() {
        guard let step = dragDetent else { return }
        dragDetent = nil
        onCommit?(step)
    }

    private static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    private func numeralColor(_ n: Int) -> Color {
        if n == speed { return Palette.label }
        return n < speed ? Palette.secondary : Palette.tertiary
    }

    private var thumbFill: Color {
        scheme == .dark ? Color.white.opacity(0.24) : Color.white
    }
}

/// Fan speed: a 28pt label row ("Speed", live blade at the trailing edge) over the 288×32 detent. 76pt in its card.
/// The detent is the only element VoiceOver sees.
struct SpeedSection: View {
    @Binding var speed: Int
    var isOn: Bool
    var pending = false
    var onCommit: ((Int) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Speed")
                    .font(.system(size: 13))
                    .foregroundStyle(isOn ? Palette.label : Palette.secondary)
                Spacer(minLength: 8)
                FanBlade(speed: speed, running: isOn, size: 16,
                         color: isOn ? Palette.label : Palette.tertiary, fitted: true)
            }
            .frame(height: 28)
            .accessibilityHidden(true)
            SpeedDetent(speed: $speed, width: Metric.content, enabled: isOn, onCommit: onCommit)
                .modifier(PendingPulse(active: pending))
        }
        .padding(.horizontal, Metric.side)
        .padding(.bottom, 4)
    }
}

// MARK: - Slider

/// Capsule slider: 5pt track, 20×15 capsule knob, neutral fill (no hue).
struct CapsuleSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var width: CGFloat
    var label = ""
    @Environment(\.colorScheme) private var scheme

    private static let knobW: CGFloat = 20
    private static let knobH: CGFloat = 15
    /// VoiceOver steps in tens, which suits the 10–100% brightness range.
    private static let accessibleStep: Double = 10

    var body: some View {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        let cx = Self.knobW / 2 + CGFloat(fraction) * (width - Self.knobW)
        ZStack(alignment: .leading) {
            Capsule().fill(Palette.trackFill).frame(width: width, height: 5)
            Capsule().fill(Palette.secondary).frame(width: cx, height: 5)
            Capsule()
                .fill(scheme == .dark ? Color(white: 0.88) : Color.white)
                .frame(width: Self.knobW, height: Self.knobH)
                .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 0.5)
                .offset(x: cx - Self.knobW / 2)
        }
        .frame(width: width, height: Metric.hitTarget)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { g in
                let f = min(1, max(0, (g.location.x - Self.knobW / 2) / (width - Self.knobW)))
                value = (range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)).rounded()
            }
        )
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + Self.accessibleStep)
            case .decrement: value = max(range.lowerBound, value - Self.accessibleStep)
            @unknown default: break
            }
        }
    }
}

// MARK: - Fields

/// Capsule text field: 28pt, 12pt side padding, 0.5pt hairline, capsule focus ring (3pt).
/// `secure` uses a SecureField; otherwise a TextField. Both draw the same capsule.
struct CapsuleField: View {
    @Binding var text: String
    var secure = false
    var placeholder: String
    @FocusState private var hasFocus: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(text: Binding<String>, secure: Bool = false, placeholder: String) {
        _text = text
        self.secure = secure
        self.placeholder = placeholder
    }

    @ViewBuilder
    private var input: some View {
        if secure {
            SecureField(placeholder, text: $text)
                .focused($hasFocus)
        } else {
            TextField(placeholder, text: $text)
                .focused($hasFocus)
        }
    }

    var body: some View {
        input
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, Metric.fieldPadding)
            .frame(maxWidth: .infinity)
            .frame(height: Metric.capsuleButton)
            .background(Capsule().fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.14),
                                       lineWidth: Metric.hairline)
            )
            .overlay(
                Capsule()
                    .stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: Metric.focusRing)
                    .padding(-Metric.focusRing / 2)
                    .opacity(hasFocus ? 1 : 0)
            )
            .focusEffectDisabled()
            .animation(Motion.pick(Motion.hover, reduceMotion), value: hasFocus)
    }
}

// MARK: - Indicators

struct ScrollEdges: Equatable {
    var top: Bool
    var bottom: Bool
}

/// Vertical scroll view whose content fades over 16pt at an edge that has more content beyond it.
struct FadingScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var edges = ScrollEdges(top: false, bottom: true)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical) { content }
            .scrollIndicators(.automatic)
            .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                ScrollEdges(top: geometry.contentOffset.y > 0.5,
                            bottom: geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 0.5)
            } action: { _, new in
                withAnimation(reduceMotion ? nil : Motion.hover) { edges = new }
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: edges.top ? Metric.edgeFade : 0)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: edges.bottom ? Metric.edgeFade : 0)
                }
            }
    }
}

/// Small indeterminate spinner: 12 spokes stepping at 12 fps, like NSProgressIndicator.
struct Spinner: View {
    var size: CGFloat = 12

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate * 12) % 12
            spokes.rotationEffect(.degrees(Double(step) * 30))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Checking")
    }

    private var spokes: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(Palette.label)
                    .frame(width: max(1.5, size * 0.11), height: size * 0.28)
                    .offset(y: -size * 0.33)
                    .rotationEffect(.degrees(Double(i) * 30))
                    .opacity(0.15 + 0.85 * Double(i) / 11)
            }
        }
    }
}

// MARK: - Fan blade

/// Integrates angle from an angular velocity that eases toward the target, so a speed
/// change (or power off) never makes the blade jump.
final class BladeSpin {
    private var angle = 0.0
    private var velocity = 0.0
    private var last: Date?

    func advance(to date: Date, target: Double) -> Double {
        let dt = last.map { min(max(date.timeIntervalSince($0), 0), 1.0 / 15) } ?? 0
        last = date
        velocity += (target - velocity) * (1 - exp(-dt / Motion.bladeEaseTime))
        angle = (angle + velocity * dt).truncatingRemainder(dividingBy: 360)
        return angle
    }
}

struct FanBlade: View {
    var speed: Int
    var running: Bool
    var size: CGFloat
    var color: Color = Palette.secondary
    /// true: the glyph is scaled to fill a size × size square exactly, so its ink edges can be
    /// aligned to text metrics (fan speed block). false: drawn at font size `size` (wells).
    var fitted = false
    @State private var spin = BladeSpin()
    /// True while running and for 3 s after, so a stopped blade decelerates instead of freezing mid-turn.
    @State private var coasting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A paused timeline stops calling the closure, so the blade holds its last angle.
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion || (!running && !coasting))) { context in
            glyph
                .foregroundStyle(color)
                .rotationEffect(.degrees(reduceMotion ? 0 : spin.advance(
                    to: context.date,
                    target: running ? Double(speed) * Motion.bladeDegreesPerStep : 0)))
        }
        .frame(width: fitted ? size : nil, height: fitted ? size : nil)
        .accessibilityHidden(true)
        .task(id: running) {
            if running {
                coasting = true
                return
            }
            // A view that starts off never ran, so it has nothing to coast down.
            guard coasting else { return }
            // A restart cancels this task, which must not clear coasting for the new run.
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            coasting = false
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if fitted {
            Image(systemName: "fan.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "fan.fill")
                .font(.system(size: size, weight: .medium))
        }
    }
}

// MARK: - Copy button

/// "Copy" morphs to a checkmark (symbol replace) for 1.6s. A second copy restarts the timer.
/// Every copy is marked concealed so clipboard managers skip it: use only for secrets (the PIN).
struct CopyButton: View {
    let value: String
    @State private var copied = false
    @State private var revert: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            let concealed = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.ConcealedType")
            pasteboard.setString(value, forType: concealed)
            withAnimation(Motion.pick(Motion.numeric, reduceMotion)) { copied = true }
            revert?.cancel()
            revert = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                withAnimation(Motion.pick(Motion.numeric, reduceMotion)) { copied = false }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .frame(width: 14)
                Text(copied ? "Copied" : "Copy")
            }
            .frame(minWidth: 66)
        }
        .buttonStyle(CapsuleButtonStyle())
    }
}

// MARK: - Hover

/// Row hover: a rounded rect concentric with the card (radius 10, inset 2), 6% fill (12% under Increase Contrast).
struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Metric.hoverRadius, style: .continuous)
                    .fill(contrast == .increased ? Palette.hoverStrong : Palette.hover)
                    .padding(.horizontal, Metric.hoverInset)
                    .padding(.vertical, 2)
                    .opacity(hovering ? 1 : 0)
            )
            .contentShape(Rectangle())
            .onHover { inside in
                withAnimation(reduceMotion ? nil : Motion.hover) { hovering = inside }
            }
    }
}

extension View {
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}
