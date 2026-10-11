import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // @Observable does not instrument computed properties, so access and mutation are reported by hand.
    // Without this, SwiftUI would never learn that the value changed.
    var localControlEnabled: Bool {
        get {
            access(keyPath: \.localControlEnabled)
            // Off until the consent step turns it on, so the macOS local network prompt never appears early.
            guard defaults.object(forKey: Key.localControlEnabled) != nil else { return false }
            return defaults.bool(forKey: Key.localControlEnabled)
        }
        set {
            withMutation(keyPath: \.localControlEnabled) {
                defaults.set(newValue, forKey: Key.localControlEnabled)
            }
        }
    }

    private enum Key {
        static let localControlEnabled = "localControlEnabled"
    }
}
