import Foundation
import Observation

/// Lets code outside the popover's views ask it to show a screen. The status item's right click uses it to open
/// Settings, with or without the popover already open.
@MainActor
@Observable
final class PopoverNavigator {
    struct Request: Equatable {
        let route: PopoverRoute
        /// False when the popover is not on screen yet: the screen is swapped without a transition.
        let animated: Bool
        let id = UUID()
    }

    var request: Request?
}
