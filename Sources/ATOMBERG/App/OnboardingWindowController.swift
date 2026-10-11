import AppKit
import SwiftUI

/// One window serves first run and "Replace credentials…". The content is rebuilt on every show
/// so the flow always starts at its first step.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    // Matches the StepLayout grid. The window is not resizable, so this is its size for good.
    private static let contentSize = NSSize(width: 440, height: 352)

    private let store: DeviceStore
    private let onComplete: () -> Void
    private lazy var window = makeWindow()
    // Holds the flow's view state, including typed secrets, until the window closes.
    private var hostingView: NSView?

    init(store: DeviceStore, onComplete: @escaping () -> Void) {
        self.store = store
        self.onComplete = onComplete
        super.init()
    }

    func show() {
        let host = NSHostingView(rootView: makeFlow())
        // Without this, SwiftUI's ideal size can resize the window away from its fixed content size.
        host.sizingOptions = []
        hostingView = host
        window.contentView = host
        window.setContentSize(Self.contentSize)
        if let visible = NSScreen.main?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        }
        // The app is an accessory app, so it must be activated before its window can come forward.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeFlow() -> some View {
        OnboardingFlow(onFinish: { [weak self] in self?.finish() })
            .environment(store)
    }

    private func finish() {
        window.close()
    }

    // Done and the close button both end here. Completion is gated on the store, because credentials
    // only count once connect has succeeded, whichever control closed the window.
    func windowWillClose(_ notification: Notification) {
        if store.isConfigured {
            onComplete()
        }
        // Deferred: Done's action may still be on the stack, and tearing down its hosting view there is unsafe.
        Task { @MainActor [weak self] in self?.releaseContent() }
    }

    private func releaseContent() {
        // A show() that lands before this turn has already put a fresh flow in the window.
        guard !window.isVisible else { return }
        window.contentView = nil
        hostingView = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.title = "Atomberg Console"
        window.delegate = self
        return window
    }
}
