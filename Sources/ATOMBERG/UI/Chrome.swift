import SwiftUI
import AppKit

// MARK: - Popover

/// The menu bar popover body: Liquid Glass, 320pt wide, squircle radius 20. The app hosts it
/// in a clear panel, so it draws no window background of its own. The content is pinned to the
/// top and the surface fills the panel's height, so the panel can resize without moving the content.
struct GlassPopover<Content: View>: View {
    /// The surface's height. The panel's window is never animated between screens: it jumps to the taller size
    /// first (or shrinks afterwards) and this height moves inside it, so the top edge cannot wobble.
    /// nil is the content's natural height.
    var height: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            // The panel never becomes key, so a focus ring can only be spurious.
            .focusEffectDisabled()
            .frame(width: Metric.popoverWidth)
            .frame(height: height, alignment: .top)
            .clipShape(.rect(cornerRadius: Metric.popoverRadius, style: .continuous))
            .glassEffect(.regular, in: .rect(cornerRadius: Metric.popoverRadius, style: .continuous))
            .background { SurfaceShadow() }
            // The window is wider than the surface by this ring on both sides, so the shadow has room.
            .padding(.horizontal, Metric.panelMargin)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The surface's shadow, drawn by SwiftUI so that it moves with the surface as its height animates. Only the part
/// outside the surface is drawn: the glass is translucent and must not be darkened from behind.
private struct SurfaceShadow: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metric.popoverRadius, style: .continuous)
        shape
            .fill(Color.black)
            .shadow(color: .black.opacity(0.30), radius: 16, x: 0, y: 6)
            .mask {
                Rectangle()
                    .padding(-Metric.panelMargin)
                    .overlay { shape.blendMode(.destinationOut) }
                    .compositingGroup()
            }
    }
}

// MARK: - Cards

/// A subtle group: a faint squircle behind content. The content keeps its full 320pt width, so rows keep
/// their own 16pt insets. Only the fill is inset `Metric.groupInset`, which makes its radius concentric
/// with the popover.
struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        // One container. Modifiers on a multi-view builder apply to each child separately, which
        // turned every Hairline into its own card (the v6 bands).
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.vertical, Metric.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            CardBackground()
                .padding(.horizontal, Metric.groupInset)
        }
    }
}

/// Faint continuous-corner fill (label colour at about 4.7%). No shadow; a 1pt stroke only under
/// Increase Contrast.
struct CardBackground: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metric.groupRadius, style: .continuous)
        shape.fill(Palette.groupFill)
            .overlay {
                if contrast == .increased { shape.strokeBorder(Palette.separator, lineWidth: 1) }
            }
    }
}

// MARK: - Rows and headers

struct SectionLabel: View {
    let text: String
    var trailing: String? = nil
    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, Metric.side)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

/// Home list row, 36pt: 24pt well, one-line name (+ duplicate-name suffix, + one exception glyph), then right-hand
/// columns: an optional value, an optional transport glyph (wifi, cloud, struck-through cloud), and a 42pt control
/// column that holds the switch, or a chevron. The glyph and control columns sit at the same x on every row, so the
/// symbols line up down the list. The open area is one VoiceOver button; the control stays its own element.
struct DeviceRow<Glyph: View, Value: View, Control: View>: View {
    let title: String
    var suffix: String? = nil
    var badge: StatusGlyph? = nil
    var badgeHelp = ""
    var transport: StatusGlyph? = nil
    var transportHelp = ""
    /// True: the control column holds a chevron, inside the open area, and the row has no control.
    var chevron = false
    var dimmed = false
    let accessibilityValue: String
    let onOpen: () -> Void
    @ViewBuilder var glyph: Glyph
    @ViewBuilder var value: Value
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Well { glyph }
                    .padding(.trailing, 8)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(dimmed ? Palette.secondary : Palette.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let suffix {
                        Text(suffix)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.tertiary)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                    if let badge {
                        Text(Image(systemName: badge.symbol))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(badge.color)
                            .fixedSize()
                            .help(badgeHelp)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    value
                    if let transport {
                        RowGlyph(transport, help: transportHelp)
                    }
                }
                if chevron {
                    Chevron()
                        .frame(width: Metric.switchSize.width, alignment: .trailing)
                        .padding(.leading, 8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows details")
            .accessibilityAction { onOpen() }
            if !chevron {
                control
                    .frame(width: Metric.switchSize.width, alignment: .trailing)
                    .padding(.leading, 8)
            }
        }
        .padding(.horizontal, Metric.side)
        .frame(height: Metric.deviceRow)
        .hoverHighlight()
    }
}

/// Detail header, 48pt, one line: back button, title (13 semibold) and status (11, with its glyph) on a shared
/// baseline, then the trailing control. The 24pt back circle sits 6pt from the left edge.
/// `onBack` must be wired by the caller; the default does nothing.
struct DetailHeader<Trailing: View>: View {
    let title: String
    var status: StatusText? = nil
    var onBack: () -> Void = {}
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            IconButton(symbol: "chevron.left", label: "Back", action: onBack)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let status { StatusLine(status) }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.leading, 6)
        .padding(.trailing, Metric.side)
        .frame(height: Metric.detailHeader)
    }
}

/// A settings line: 24pt glyph column, one-line title (+ optional 11pt subtitle), trailing control. 40pt, or 48pt
/// with a subtitle. Rows that act are wrapped by `ActionRow`.
struct IconRow<Control: View>: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: Control

    /// A subtitle may hold several lines, one per "\n". Each is one line of 11pt text.
    private var detailLines: [String] {
        subtitle?.split(separator: "\n").map(String.init) ?? []
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .frame(width: Metric.well)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.label)
                ForEach(detailLines.indices, id: \.self) { index in
                    Text(detailLines[index])
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, Metric.side)
        .frame(height: detailLines.isEmpty ? Metric.controlRow : Metric.subtitleRow + CGFloat(detailLines.count - 1) * 14)
    }
}

/// An `IconRow` that is one button: the whole row is the hit area and hovers like a list row.
struct ActionRow<Control: View>: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    let action: () -> Void
    @ViewBuilder var control: Control

    var body: some View {
        IconRow(symbol: symbol, title: title, subtitle: subtitle) { control }
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .hoverHighlight()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// Title (+ optional subtitle) on the left, a switch on the right. 40pt, or 48pt with a subtitle.
struct SwitchRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var caption: String? = nil       // failure caption under the row
    @ViewBuilder var control: Control
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.label)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                control
            }
            .frame(height: subtitle == nil ? Metric.controlRow : Metric.subtitleRow)
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .animation(Motion.pick(Motion.reveal, reduceMotion), value: caption)
        .padding(.horizontal, Metric.side)
    }
}

/// Label column (96pt, optional 11pt subtitle) + a control that starts at x 112. 40pt, or 48pt with a subtitle.
struct LabeledRow<Control: View>: View {
    let label: String
    var subtitle: String? = nil
    var subordinate = false
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(subordinate ? Palette.secondary : Palette.label)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondary)
                        .transition(.opacity)
                }
            }
            .lineLimit(1)
            .frame(width: Metric.controlColumn, alignment: .leading)
            control
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metric.side)
        .frame(height: subtitle == nil ? Metric.controlRow : Metric.subtitleRow)
        .animation(Motion.reduced, value: subtitle)
    }
}

// MARK: - Notices and detail footers

enum NoticeAction: Equatable {
    case tryAgain, replaceCredentials, connect, openLocalNetworkSettings, turnOffLocalControl

    var title: String {
        switch self {
        case .tryAgain: "Try again"
        case .replaceCredentials: "Replace…"
        case .connect: "Connect…"
        case .openLocalNetworkSettings: "Open Settings"
        case .turnOffLocalControl: "Turn Off"
        }
    }
}

struct Notice: Equatable {
    let symbol: String
    var attention = false
    let text: String
    var action: NoticeAction? = nil
}

/// A global state above the list: glyph centred in the 24pt glyph column, 12pt text at x 48 (≤2 lines),
/// optional secondary capsule button. Min 40pt + card padding.
struct NoticeCard: View {
    let notice: Notice
    let perform: (NoticeAction) -> Void

    var body: some View {
        Card {
            HStack(spacing: 0) {
                Image(systemName: notice.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(notice.attention ? Palette.attention : Palette.secondary)
                    .frame(width: Metric.well)
                    .padding(.trailing, 8)
                    .accessibilityHidden(true)
                Text(notice.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.label)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(notice.attention ? "Needs attention: \(notice.text)" : notice.text)
                Spacer(minLength: 8)
                if let action = notice.action {
                    Button(action.title) { perform(action) }
                        .buttonStyle(CapsuleButtonStyle())
                }
            }
            .padding(.horizontal, Metric.side)
            .padding(.vertical, 4)
            .frame(minHeight: Metric.controlRow)
        }
    }
}

/// One 11pt line on the glass under a detail screen's cards.
struct UsageLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(Palette.secondary)
            .lineLimit(1)
            .padding(.horizontal, Metric.side)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Metric.usageLine)
    }
}

/// A failed command, on the glass above a detail screen's cards.
struct FailureLine: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Image(systemName: "exclamationmark.circle"))
                .font(.system(size: 11, weight: .medium))
            Text(message)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.secondary)
        .padding(.horizontal, Metric.side)
        .frame(maxWidth: .infinity, minHeight: Metric.failureLine, alignment: .leading)
    }
}
