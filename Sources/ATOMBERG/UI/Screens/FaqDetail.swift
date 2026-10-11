import SwiftUI

/// Eight short answers, one open at a time. Opened from Settings.
struct FaqDetail: View {
    let onBack: () -> Void
    @State private var open: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let entries: [(question: String, answer: String)] = [
        ("Why does a command use a cloud call?",
         "Atomberg allows 100 calls a day. A fan that is heard on your Wi‑Fi is controlled directly and costs none. Otherwise a command is one call."),
        ("Why isn’t my fan found locally?",
         "The fan and this Mac must be on the same Wi‑Fi, and Local Network access must be on for this app. Tap the wifi button to look again."),
        ("What do Local and Cloud mean?",
         "Local: the command goes over your Wi‑Fi. Cloud: it goes through Atomberg’s servers and counts toward the daily limit."),
        ("Where are my credentials?",
         "In your macOS Keychain, nowhere else. They are sent only to Atomberg’s API."),
        ("What does it connect to?",
         "api.developer.atomberg-iot.com over HTTPS, and your fans on UDP ports 5625 and 5600. Nothing else. No analytics, no updater."),
        ("Why does the Keychain ask for access?",
         "macOS asks when it does not recognise the app. Choose Always Allow once."),
        ("How do I reset it?",
         "Settings → Replace Credentials. To remove everything, delete the app and the Keychain item “com.ashwin.ATOMBERG”."),
        ("Is this official?",
         "No. It is unofficial and not affiliated with Atomberg. Source-available under PolyForm Noncommercial 1.0.0."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: "FAQ", onBack: onBack) {
                EmptyView()
            }
            Card {
                ForEach(Self.entries.indices, id: \.self) { index in
                    if index > 0 { Hairline().padding(.horizontal, Metric.side) }
                    row(index)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func row(_ index: Int) -> some View {
        let isOpen = open == index
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(Self.entries[index].question)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.tertiary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .frame(height: Metric.controlRow - 12)
            if isOpen {
                Text(Self.entries[index].answer)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Metric.side)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Motion.pick(Motion.reveal, reduceMotion)) { open = isOpen ? nil : index }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOpen ? Self.entries[index].answer : "Collapsed")
    }
}
