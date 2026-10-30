import AppKit
import Observation

private let glyphPointSize: CGFloat = 15
private let badgeDiameter: CGFloat = 6
private let badgeGap: CGFloat = 1.5

// NSObject is required: the status button sends its action through the Objective-C runtime.
@MainActor
final class StatusItemController: NSObject {
    private let store: DeviceStore
    private let statusItem: NSStatusItem
    private let popover: PopoverWindow

    init(store: DeviceStore, onReplaceCredentials: @escaping () -> Void) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = PopoverWindow(store: store, onReplaceCredentials: onReplaceCredentials)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // The right click arrives as its own event, so the action must be asked for it.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imageHugsTitle = true
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        }
        popover.onVisibilityChange = { [weak self] isShown in
            self?.statusItem.button?.highlight(isShown)
        }
        trackSnapshots()
    }

    /// A click toggles the popover. A right click (or control-click) goes straight to Settings.
    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        let rightClick = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)
        if rightClick {
            popover.show(below: button, opening: .settings)
            return
        }
        if popover.isShown {
            popover.hide()
        } else {
            popover.show(below: button)
        }
    }

    // Observation reports changes before they land, so the re-read is deferred to the next
    // main-actor turn and tracking is re-armed from there.
    private func trackSnapshots() {
        withObservationTracking {
            refreshButton()
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackSnapshots() }
        }
    }

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        let devices = store.snapshots
        let running = devices.filter { store.runningSpeed(of: $0.id) != nil }.count
        let allOffline = !devices.isEmpty && devices.allSatisfy { store.links[$0.id] == .offline }
        let attention = (store.lastError?.kind.needsAction ?? false)
            || devices.contains { DeviceFacts.needsAttention($0, link: store.links[$0.id]) }

        let name = running > 0 ? "fan.fill" : "fan"
        button.image = attention ? Self.badgedGlyph(name) : Self.glyph(name)
        let showsCount = running >= 2
        button.title = showsCount ? "\(running)" : ""
        button.imagePosition = showsCount ? .imageLeading : .imageOnly
        button.appearsDisabled = allOffline && !attention

        let summary = Self.summary(running: running, allOffline: allOffline, attention: attention)
        button.setAccessibilityLabel("Atomberg Console, \(summary)")
        button.toolTip = summary.prefix(1).uppercased() + String(summary.dropFirst())
    }

    private nonisolated static func glyph(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .regular))
        image?.isTemplate = true
        return image
    }

    /// The glyph with a 6pt dot in its top-right corner, cut out of the glyph by a 1.5pt gap. Still a template.
    /// The handler captures only the symbol name and rebuilds the glyph, so it captures nothing non-Sendable.
    private static func badgedGlyph(_ name: String) -> NSImage? {
        guard let size = glyph(name)?.size else { return nil }
        let image = NSImage(size: size, flipped: false) { rect in
            guard let base = glyph(name) else { return false }
            base.draw(in: rect)
            let dot = NSRect(x: rect.maxX - badgeDiameter, y: rect.maxY - badgeDiameter,
                             width: badgeDiameter, height: badgeDiameter)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -badgeGap, dy: -badgeGap)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func summary(running: Int, allOffline: Bool, attention: Bool) -> String {
        let state: String
        if allOffline {
            state = "all devices offline"
        } else if running == 0 {
            state = "no fans running"
        } else if running == 1 {
            state = "1 fan running"
        } else {
            state = "\(running) fans running"
        }
        return attention ? "\(state), needs attention" : state
    }
}
