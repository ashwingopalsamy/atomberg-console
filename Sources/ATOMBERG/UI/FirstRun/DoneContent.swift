import SwiftUI

/// Step 4. With local control on, it listens briefly for fans before it reports what answered.
struct DoneContent: View {
    let localControl: Bool
    let onDone: () -> Void
    @Environment(DeviceStore.self) private var store
    @State private var probed = false
    @State private var fanCount = 0
    @State private var heardCount = 0

    var body: some View {
        StepLayout(
            step: 4,
            title: "You’re all set",
            message: "Find Atomberg Console in the menu bar to control your devices."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                TermRow(name: "Devices") {
                    Text("\(store.snapshots.count)")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                }
                Hairline()
                TermRow(name: "Fan control") {
                    fanControl
                }
            }
        } note: {
            EmptyView()
        } buttons: {
            Button("Done", action: onDone)
                .buttonStyle(CapsuleButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
        }
        .task { await probe() }
    }

    @ViewBuilder
    private var fanControl: some View {
        if !localControl {
            detail("Cloud only")
        } else if !probed {
            HStack(spacing: 6) {
                Spinner(size: 11)
                detail("Listening for fans…")
            }
        } else if fanCount == 0 {
            detail("No fans on this account")
        } else {
            detail("Local network · \(heardCount) of \(fanCount) \(fanCount == 1 ? "fan" : "fans") heard")
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Palette.secondary)
            .monospacedDigit()
    }

    private func probe() async {
        guard localControl else { return }
        let links = await store.probeLocalNetwork(duration: .seconds(3))
        fanCount = links.count
        heardCount = links.values.filter { $0 == .local }.count
        probed = true
    }
}
