import AppKit
import SwiftUI

/// The About window: one window, reused. It replaces the system About panel, which showed the placeholder icon and
/// the notice as a block of centred text.
@MainActor
enum AboutPanel {
    private static var window: NSWindow?

    static func show() {
        // The app is an accessory app, so it must be activated before its window can come forward.
        NSApp.activate()
        let window = window ?? makeWindow()
        Self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: AboutView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.title = "About Atomberg Console"
        let host = NSHostingView(rootView: AboutView())
        // The window is not resizable, so SwiftUI's ideal size must not resize it.
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(AboutView.size)
        window.center()
        return window
    }
}
