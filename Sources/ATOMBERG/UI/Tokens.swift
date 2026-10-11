import SwiftUI
import AppKit

// MARK: - Colour

/// Colour is scarce. A hue may appear in exactly three places:
///   1. the track of an active switch (one tint per device kind),
///   2. the attention glyph `exclamationmark.triangle.fill` (orange), for states the user must act on,
///   3. the single primary capsule button on a screen (blue; never in the home popover).
/// Everything else is label colours and neutral fills.
enum Palette {
    static let fanTint      = Color(nsColor: .systemTeal)    // fan switches
    static let purifierTint = Color(nsColor: .systemBlue)    // purifier switches
    static let attention    = Color(nsColor: .systemOrange)  // exclamationmark.triangle.fill only
    static let primary      = Color(nsColor: .systemBlue)    // the one primary button

    static let label     = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let tertiary  = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)
    static let wellFill  = Color(nsColor: .systemFill)            // 9.8%  neutral symbol wells, icon buttons
    static let trackFill = Color(nsColor: .secondarySystemFill)   // 7.8%  capsule tracks
    static let groupFill = Color(nsColor: .tertiarySystemFill)    // 4.7%  ticket
    static let window    = Color(nsColor: .windowBackgroundColor)
    static let hover     = Color.primary.opacity(0.06)            // row hover capsule
    static let level     = Color.primary.opacity(0.08)            // speed level fill
    static let hoverStrong = Color.primary.opacity(0.12)              // row hover under Increase Contrast
    static let pressed     = Color.primary.opacity(0.10)              // icon button pressed
}

/// The one glyph a status may carry. Home rows show exceptions only (`.attention`, `.cloud`, `.offline`);
/// detail headers always name their transport (`.local`, `.cloud`) or `.offline`.
enum StatusGlyph: Equatable {
    case local, cloud, attention, offline

    var symbol: String {
        switch self {
        case .local: "wifi"
        case .cloud: "cloud"
        case .attention: "exclamationmark.triangle.fill"
        case .offline: "icloud.slash"
        }
    }

    var color: Color { self == .attention ? Palette.attention : Palette.secondary }
}

struct StatusText: Equatable {
    var glyph: StatusGlyph? = nil
    var text: String
}

// MARK: - Metrics (8pt grid; 4pt half-steps only inside controls)

enum Metric {
    static let popoverWidth: CGFloat = 320
    static let popoverRadius: CGFloat = 20     // squircle (.continuous)
    static let panelMargin: CGFloat = 32       // clear ring around the surface, for its shadow
    static let groupInset: CGFloat = 8         // squircle groups sit 8pt in from the popover edge
    static let groupRadius: CGFloat = 12       // 20 − 8: concentric
    static let cardPadding: CGFloat = 4        // above and below the content of a Card
    static let windowRadius: CGFloat = 16
    static let side: CGFloat = 16              // text inset from the popover edge
    static let content: CGFloat = 288          // 320 − 2 × 16
    static let hairline: CGFloat = 0.5

    static let deviceRow: CGFloat = 36
    static let controlRow: CGFloat = 40
    static let header: CGFloat = 40            // home title line
    static let detailHeader: CGFloat = 48      // back button, title and status line
    static let controlColumn: CGFloat = 96     // x of right-hand controls, measured from the content edge (popover x 112)
    static let controlWidth: CGFloat = 192     // 288 − 96

    static let capsuleControl: CGFloat = 24    // segmented, compact detent
    static let capsuleButton: CGFloat = 28     // push buttons, text fields
    static let detent: CGFloat = 32            // speed detent, full size
    static let buttonPadding: CGFloat = 14     // capsule button horizontal padding
    static let fieldPadding: CGFloat = 12      // capsule field horizontal padding

    static let switchSize = CGSize(width: 42, height: 20)
    static let knob = CGSize(width: 26, height: 16)
    static let knobPressed = CGSize(width: 30, height: 16)

    static let well: CGFloat = 24
    static let iconButton: CGFloat = 24        // the visual circle
    static let hitTarget: CGFloat = 28         // pointer hit area of every control
    static let subtitleRow: CGFloat = 48
    static let hoverRadius: CGFloat = 10       // groupRadius − 2
    static let hoverInset: CGFloat = 10        // 2pt inside a card's 8pt edge
    static let speedBadge: CGFloat = 22
    static let maxVisibleRows = 8
    static let listViewport: CGFloat = 306     // 8 × 36 + 18
    static let edgeFade: CGFloat = 16
    static let usageLine: CGFloat = 32
    static let failureLine: CGFloat = 24
    static let focusRing: CGFloat = 3
}

// MARK: - Motion

enum Motion {
    static let toggle      = Animation.spring(response: 0.32, dampingFraction: 0.8)
    static let toggleFail  = Animation.spring(response: 0.24, dampingFraction: 0.55)
    static let detent      = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let press       = Animation.easeOut(duration: 0.08)
    static let hover       = Animation.easeOut(duration: 0.12)
    static let popover     = Animation.easeOut(duration: 0.18)
    static let sheet       = Animation.easeOut(duration: 0.22)
    static let push        = Animation.easeInOut(duration: 0.30)
    static let numeric     = Animation.snappy(duration: 0.25)
    static let reveal      = Animation.easeOut(duration: 0.20)
    /// The popover surface changing height between screens. The window never animates; only this does.
    static let resize      = Animation.easeInOut(duration: 0.25)
    static let pendingPulse = Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
    /// Under Reduce Motion every movement becomes this short cross-fade.
    static let reduced     = Animation.easeOut(duration: 0.12)

    static let rowStagger: Double = 0.06
    static let digitStagger: Double = 0.04
    // Speed 1 = 270°/s, speed 6 = 1620°/s (4.5 turns a second). The glyph repeats every 90°, so 60 fps stays
    // unambiguous up to 2700°/s; faster would only look like the blade turning backwards.
    static let bladeDegreesPerStep: Double = 270
    static let bladeEaseTime: Double = 0.5        // time constant of angular-velocity easing

    static func pick(_ animation: Animation, _ reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }
}
