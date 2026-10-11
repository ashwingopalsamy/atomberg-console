import SwiftUI

/// Four steps: connect, verify, local network, done. The typed fields and the last failure live here, so
/// Back from a failed verification returns with them intact. Steps change with a 300 ms push
/// (a cross-fade under Reduce Motion). The host supplies the window.
struct OnboardingFlow: View {
    let onFinish: () -> Void
    @State private var step = 1
    @State private var apiKey = ""
    @State private var refreshToken = ""
    @State private var failure: String?
    @State private var localControl = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Group {
                switch step {
                case 1:
                    ConnectContent(apiKey: $apiKey, refreshToken: $refreshToken, failure: failure) {
                        failure = nil
                        go(to: 2)
                    }
                case 2:
                    VerifyContent(
                        apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                        refreshToken: refreshToken.trimmingCharacters(in: .whitespacesAndNewlines),
                        onVerified: { go(to: 3) },
                        onFailed: { failure = $0 },
                        onBack: { go(to: 1) }
                    )
                case 3:
                    LocalNetworkContent { enabled in
                        localControl = enabled
                        go(to: 4)
                    }
                default:
                    DoneContent(localControl: localControl, onDone: onFinish)
                }
            }
            .id(step)
            .transition(reduceMotion ? .opacity : .push(from: .trailing))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.window)
        // The window is fullSizeContentView, so the top safe area is the title bar. The grid is exactly 352 pt
        // with no slack, so that inset would push the footer below the bottom edge.
        .ignoresSafeArea()
    }

    private func go(to next: Int) {
        withAnimation(Motion.pick(Motion.push, reduceMotion)) { step = next }
    }
}
