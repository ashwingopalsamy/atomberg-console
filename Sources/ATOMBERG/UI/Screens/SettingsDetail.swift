import SwiftUI

/// The settings pane. It opens inside the popover in place of the device list, like a device's detail screen.
struct SettingsDetail: View {
    let onBack: () -> Void
    let onReplaceCredentials: () -> Void
    let onAbout: () -> Void
    let onOpenFaq: () -> Void
    @Environment(DeviceStore.self) private var store
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: "Settings", onBack: onBack) {
                EmptyView()
            }
            VStack(alignment: .leading, spacing: 8) {
                Card {
                    IconRow(symbol: "wifi.router", title: "Local Network Control") {
                        Toggle("Local Network Control", isOn: localControlBinding)
                            .toggleStyle(DeviceSwitchStyle(tint: Palette.fanTint))
                            .labelsHidden()
                    }
                    Hairline().padding(.horizontal, Metric.side)
                    IconRow(symbol: "play.circle", title: "Open at Login") {
                        Toggle("Open at Login", isOn: launchBinding)
                            .toggleStyle(DeviceSwitchStyle(tint: Palette.fanTint))
                            .labelsHidden()
                    }
                }
                Card {
                    ActionRow(symbol: "arrow.clockwise", title: "Refresh", subtitle: quotaText,
                              action: { Task { await store.refreshFromUser() } }) {
                        if store.isRefreshing { Spinner(size: 12) }
                    }
                    Hairline().padding(.horizontal, Metric.side)
                    ActionRow(symbol: "key", title: "Replace Credentials", action: onReplaceCredentials) {
                        Chevron()
                    }
                    Hairline().padding(.horizontal, Metric.side)
                    ActionRow(symbol: "questionmark.circle", title: "FAQ", action: onOpenFaq) {
                        Chevron()
                    }
                    Hairline().padding(.horizontal, Metric.side)
                    ActionRow(symbol: "info.circle", title: "About Atomberg Console", action: onAbout) {
                        Chevron()
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var quotaText: String? {
        store.quota.map { "\($0.remaining) of \($0.limit) cloud calls left\nResets \($0.resetPhrase())" }
    }

    /// The setter takes the toggle's new value. Reading the store again inside the Task would race on a double selection.
    private var localControlBinding: Binding<Bool> {
        Binding(
            get: { store.localControlEnabled },
            set: { enabled in
                Task { await store.setLocalControl(enabled) }
            })
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                // A refused registration is ignored. The toggle then re-reads the system's answer.
                try? LaunchAtLogin.setEnabled(enabled)
                launchAtLogin = LaunchAtLogin.isEnabled
            })
    }
}
