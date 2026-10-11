import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Strong references: the controllers hold the only pointers to their windows and status item.
    private var environment: AppEnvironment?
    private var onboarding: OnboardingWindowController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let environment = AppEnvironment()
        let store = environment.store
        // Onboarding completes only once credentials are stored, so the store has nothing to ask it to show.
        let onboarding = OnboardingWindowController(store: store) {
            Task { await store.start() }
        }
        let statusItem = StatusItemController(store: store) {
            onboarding.show()
        }
        self.environment = environment
        self.onboarding = onboarding
        self.statusItem = statusItem

        // Saved credentials only come alive through start(), so it runs on every launch. Onboarding opens only
        // when the Keychain reports that no credentials exist, never when a read fails.
        Task {
            await store.start()
            if store.needsOnboarding {
                onboarding.show()
            }
        }
    }

    // Closing the onboarding window must not quit a menu bar app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
