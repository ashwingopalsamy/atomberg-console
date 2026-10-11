import SwiftUI

/// Step 3. Choosing either option is the consent: local control starts LAN, and macOS prompts here.
struct LocalNetworkContent: View {
    let onChoose: (Bool) -> Void
    @Environment(DeviceStore.self) private var store
    @State private var working = false

    var body: some View {
        StepLayout(
            step: 3,
            title: "Control fans on your Wi\u{2011}Fi",
            message: "Fans answer instantly over your local network, and taps don’t use any of your \(QuotaPolicy.dailyLimit) daily cloud calls."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                TermRow(name: "Local network") {
                    Text("Instant. No cloud calls.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                }
                Hairline()
                TermRow(name: "Cloud only") {
                    Text("Slower. Each action uses a cloud call.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                }
            }
        } note: {
            Text("macOS will ask you to allow local network access.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        } buttons: {
            Button("Use cloud only") { choose(false) }
                .buttonStyle(CapsuleButtonStyle())
                .disabled(working)
            Button("Allow local network") { choose(true) }
                .buttonStyle(CapsuleButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(working)
        }
    }

    private func choose(_ localControl: Bool) {
        guard !working else { return }
        working = true
        Task {
            await store.setLocalControl(localControl)
            onChoose(localControl)
        }
    }
}
