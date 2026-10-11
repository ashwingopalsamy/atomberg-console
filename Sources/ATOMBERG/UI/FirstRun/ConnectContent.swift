import SwiftUI

/// Step 1. It only collects the credentials and checks that both are present. VerifyContent proves them.
struct ConnectContent: View {
    @Binding var apiKey: String
    @Binding var refreshToken: String
    let failure: String?
    let onConnect: () -> Void
    @State private var incomplete = false

    private var ready: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        StepLayout(
            step: 1,
            title: "Connect your account",
            message: "Paste your API key and refresh token from Atomberg Home."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                field("API key") {
                    CapsuleField(text: $apiKey, secure: true, placeholder: "Required")
                }
                field("Refresh token") {
                    CapsuleField(text: $refreshToken, secure: true, placeholder: "Required")
                }
            }
        } note: {
            if let failure {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
            } else if incomplete && !ready {
                Text("Enter both the API key and the refresh token.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            } else {
                Text("\(Image(systemName: "info.circle"))  Don’t see them? Turn on Developer Mode in the Atomberg Home app.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
        } buttons: {
            // Stays enabled while the fields are empty so a press can explain what is missing.
            Button("Connect", action: connect)
                .buttonStyle(CapsuleButtonStyle(prominent: true))
                .opacity(ready ? 1 : 0.45)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Palette.label)
                .lineLimit(1)
                .frame(width: 96, alignment: .trailing)
            content()
        }
    }

    private func connect() {
        guard ready else {
            incomplete = true
            return
        }
        incomplete = false
        onConnect()
    }
}
