import SwiftUI

@main
struct ATOMBERGApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Build tooling: `ATOMBERG --render-icon <file.png> [pixels] [full|tile|glyph]` writes the app icon (or one
        // layer of it) and exits before any UI starts. scripts/bundle.sh uses it to make AppIcon.icns.
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-icon"), arguments.indices.contains(flag + 1) else { return }
        let pixels = arguments.indices.contains(flag + 2) ? Int(arguments[flag + 2]) ?? 1024 : 1024
        _ = NSApplication.shared
        let layer = arguments.indices.contains(flag + 3)
            ? AppIconRenderer.Layer(rawValue: arguments[flag + 3]) ?? .full : .full
        guard let data = AppIconRenderer.pngData(pixels: pixels, layer: layer),
              (try? data.write(to: URL(fileURLWithPath: arguments[flag + 1]))) != nil else { exit(1) }
        exit(0)
    }

    var body: some Scene {
        // A menu bar app has no main window. The Settings scene only satisfies the App protocol.
        Settings { EmptyView() }
    }
}
