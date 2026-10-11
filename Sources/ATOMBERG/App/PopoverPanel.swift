import AppKit
import SwiftUI

/// Never becomes key. The popover has no text fields, so the panel never needs keyboard focus.
@MainActor
final class PopoverPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // The glass surface draws its own shadow. The window is taller than the surface and keeps one size, so a
        // window shadow would follow a silhouette that is not the surface's.
        hasShadow = false
        acceptsMouseMovedEvents = true
        // Clear below the surface: it takes no mouse events until the pointer is over the surface itself.
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
}

private enum PopoverStyle {
    static let width: CGFloat = 320
    /// Transparent ring around the surface (left, right, bottom) that the surface's shadow is drawn in.
    static let margin: CGFloat = Metric.panelMargin
    /// The most surface height the window offers. It is clamped to what fits under the menu bar.
    static let maxSurfaceHeight: CGFloat = 760
    static let gapBelowMenuBar: CGFloat = 4
    static let screenInset: CGFloat = 8
    static let duration: TimeInterval = 0.18
    /// After a height change the surface may still cover its old size for this long (`Motion.resize` is 0.25 s).
    static let hitSettle: TimeInterval = 0.32
    static let collapsedScale: CGFloat = 0.96
    static let escapeKeyCode: UInt16 = 53
}

/// Accepts the first mouse. The panel never becomes key, so AppKit's default would swallow the first click on a control.
@MainActor
private final class PopoverHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// Places the popover under the status item, animates it in and out, and dismisses it on an outside click or Escape.
///
/// The window has one frame for as long as it is shown: tall enough for the tallest screen, clear, and pinned to the
/// menu bar. Moving between screens only changes the height of the glass surface drawn inside it (SwiftUI animates
/// `GlassPopover.height`). Resizing the window itself, animated or not, moved the whole popover by a pixel or two at
/// each step, which read as the panel shaking.
///
/// Because the window is taller than the surface, it ignores the mouse until the pointer is over the surface, so the
/// clear area below never blocks the windows behind it.
@MainActor
final class PopoverWindow {
    private let store: DeviceStore
    private let replaceCredentials: () -> Void
    private let navigator = PopoverNavigator()
    private let panel = PopoverPanel(contentRect: .zero)
    // A plain, non-flipped container keeps the top-edge pivot maths in one coordinate system.
    private let container = NSView()
    private lazy var hostingView = makeHostingView()
    private weak var anchor: NSStatusBarButton?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var mouseMonitors: [Any] = []
    /// Latest height of the surface the content reported.
    private var surfaceHeight: CGFloat = 0
    /// The height that takes the mouse. It covers the larger of the old and new size while the surface animates.
    private var hitHeight: CGFloat = 0
    private var hitSettle: Task<Void, Never>?

    private(set) var isShown = false
    var onVisibilityChange: ((Bool) -> Void)?

    init(store: DeviceStore, onReplaceCredentials: @escaping () -> Void) {
        self.store = store
        self.replaceCredentials = onReplaceCredentials

        container.wantsLayer = true
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container
    }

    func show(below button: NSStatusBarButton) {
        guard !isShown, button.window != nil else { return }
        anchor = button
        // fittingSize is zero until the hosting view has laid out once, so force a pass before measuring.
        container.layoutSubtreeIfNeeded()
        guard let frame = placedFrame() else { return }

        isShown = true
        surfaceHeight = ceil(hostingView.fittingSize.height)
        hitHeight = surfaceHeight
        panel.ignoresMouseEvents = true
        panel.setFrame(frame, display: true)
        // Activation takes focus from the user's app, deliberately: the Escape monitor below only sees
        // key events while this app is active. The panel itself never becomes key.
        NSApp.activate()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        fade(to: 1)
        animateScale(from: PopoverStyle.collapsedScale, to: 1)
        installMonitors()
        onVisibilityChange?(true)
        // The hosting view outlives each open, so the home view's .task does not run again. Refresh here.
        Task { await self.store.refreshIfStale() }
    }

    /// Opens the popover on a given screen, or moves it there if it is already open.
    func show(below button: NSStatusBarButton, opening route: PopoverRoute) {
        navigator.request = PopoverNavigator.Request(route: route, animated: isShown)
        guard !isShown else { return }
        // One turn later, so the screen is swapped before the surface is measured and placed.
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.show(below: button)
        }
    }

    /// `restoringFocus: false` is for hand-offs to another window of ours, which must keep focus.
    func hide(restoringFocus: Bool = true) {
        guard isShown else { return }
        isShown = false
        removeMonitors()
        hitSettle?.cancel()
        onVisibilityChange?(false)
        fade(to: 0)
        animateScale(from: 1, to: PopoverStyle.collapsedScale)
        // A show during the fade cancels the order-out, so a quick reopen never flickers.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(PopoverStyle.duration))
            guard let self, !self.isShown else { return }
            self.panel.orderOut(nil)
            // The isActive guard leaves alone an outside click that has already activated another app.
            if restoringFocus, NSApp.isActive { NSApp.deactivate() }
        }
    }

    private func makeHostingView() -> PopoverHostingView {
        let view = PopoverHostingView(
            rootView: AnyView(
                PopoverRoot(
                    onReplaceCredentials: { [weak self] in
                        self?.hide(restoringFocus: false)
                        self?.replaceCredentials()
                    },
                    onAbout: { [weak self] in
                        self?.hide(restoringFocus: false)
                        AboutPanel.show()
                    },
                    onQuit: { NSApp.terminate(nil) },
                    onHeightChange: { [weak self] height in self?.surfaceHeightChanged(to: height) }
                )
                .environment(store)
                .environment(navigator)
            )
        )
        view.sizingOptions = [.intrinsicContentSize]
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    // MARK: - Mouse

    /// Called when a screen reports its height. The window does not change; only the area that takes the mouse does.
    private func surfaceHeightChanged(to height: CGFloat) {
        guard height > 0 else { return }
        surfaceHeight = height
        hitHeight = max(hitHeight, height)
        hitSettle?.cancel()
        hitSettle = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(PopoverStyle.hitSettle))
            guard !Task.isCancelled, let self else { return }
            self.hitHeight = self.surfaceHeight
            self.updateMouseTransparency()
        }
        updateMouseTransparency()
    }

    /// The window takes the mouse only while the pointer is over the surface. Outside it, clicks and scrolls reach
    /// whatever is behind, and the global click monitor still sees them and dismisses the popover.
    private func updateMouseTransparency() {
        guard isShown else { return }
        let frame = panel.frame
        let surface = NSRect(
            x: frame.minX + PopoverStyle.margin,
            y: frame.maxY - hitHeight,
            width: PopoverStyle.width,
            height: hitHeight)
        let inside = surface.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
    }

    // MARK: - Placement

    /// Top edge just below the menu bar, centred on the status item, and kept inside the visible screen. The frame
    /// is the window for the whole time the popover is shown: the surface's room plus the shadow ring.
    private func placedFrame() -> NSRect? {
        guard let button = anchor,
              let window = button.window,
              let screen = window.screen ?? NSScreen.main
        else { return nil }
        let itemRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let bounds = screen.visibleFrame.insetBy(dx: PopoverStyle.screenInset, dy: PopoverStyle.screenInset)
        let margin = PopoverStyle.margin
        let top = itemRect.minY - PopoverStyle.gapBelowMenuBar
        let surface = min(PopoverStyle.maxSurfaceHeight, max(top - bounds.minY - margin, 0))
        let x = min(max(itemRect.midX - PopoverStyle.width / 2, bounds.minX), bounds.maxX - PopoverStyle.width)
        return NSRect(
            x: x - margin,
            y: top - surface - margin,
            width: PopoverStyle.width + 2 * margin,
            height: surface + margin)
    }

    private func installMonitors() {
        // Clicks on our own status item never reach a global monitor, so the button's action is the only toggle path.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == PopoverStyle.escapeKeyCode else { return event }
            Task { @MainActor in self?.hide() }
            return nil
        }
        // Over other apps the global monitor sees the pointer, over the surface the local one does.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            Task { @MainActor in self?.updateMouseTransparency() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            Task { @MainActor in self?.updateMouseTransparency() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func removeMonitors() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        for monitor in mouseMonitors { NSEvent.removeMonitor(monitor) }
        clickMonitor = nil
        keyMonitor = nil
        mouseMonitors = []
    }

    private func fade(to alpha: CGFloat) {
        let animated = panel.animator()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PopoverStyle.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animated.alphaValue = alpha
        }
    }

    /// Reduce Motion keeps the fade and drops the scale.
    private func animateScale(from start: CGFloat, to end: CGFloat) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = container.layer else { return }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: Self.topCentreScale(start, height: layer.bounds.height))
        animation.toValue = NSValue(caTransform3D: Self.topCentreScale(end, height: layer.bounds.height))
        animation.duration = PopoverStyle.duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "popoverScale")
    }

    /// The layer's anchor is its centre, so the top edge sits at +height/2. Move that edge to the
    /// origin, scale, then move it back.
    private static func topCentreScale(_ factor: CGFloat, height: CGFloat) -> CATransform3D {
        let lift = height / 2
        let toOrigin = CATransform3DMakeTranslation(0, -lift, 0)
        let scale = CATransform3DMakeScale(factor, factor, 1)
        let back = CATransform3DMakeTranslation(0, lift, 0)
        return CATransform3DConcat(CATransform3DConcat(toOrigin, scale), back)
    }
}
