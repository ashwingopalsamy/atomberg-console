import SwiftUI

/// Step 2. Runs the connection once and shows its three stages. A failure stays on the row and in
/// OnboardingFlow, so Back can show the same message on step 1.
struct VerifyContent: View {
    let apiKey: String
    let refreshToken: String
    let onVerified: () -> Void
    let onFailed: (String) -> Void
    let onBack: () -> Void
    @Environment(DeviceStore.self) private var store
    @State private var current: ConnectStage?
    @State private var failure: String?
    @State private var verified = false

    private enum RowState { case pending, active, done, failed }

    private var quotaLine: String {
        let used = store.quota.map { String($0.used) } ?? "—"
        return "Used \(used) of today’s \(QuotaPolicy.dailyLimit) cloud calls."
    }

    var body: some View {
        StepLayout(
            step: 2,
            title: "Checking your account",
            message: "Signing in with your credentials, then reading your devices."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                row(.credentials, "Signing in")
                row(.devices, "Finding devices")
                row(.status, "Reading device status")
            }
        } note: {
            Text(quotaLine)
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        } buttons: {
            if failure != nil {
                Button("Back", action: onBack)
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue", action: onVerified)
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                    .opacity(verified ? 1 : 0.45)
                    .disabled(!verified)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .task { await verify() }
    }

    private func verify() async {
        do {
            try await store.connect(apiKey: apiKey, refreshToken: refreshToken) { stage in
                current = stage
            }
            verified = true
        } catch {
            let message = "Couldn’t connect. \(DeviceFacts.cloudErrorText(error))"
            failure = message
            onFailed(message)
        }
    }

    private func row(_ stage: ConnectStage, _ label: String) -> some View {
        let rowState = state(of: stage)
        return HStack(spacing: 12) {
            indicator(rowState)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(rowState == .pending ? Palette.tertiary : Palette.label)
                .lineLimit(1)
            Spacer(minLength: 8)
            if rowState == .failed, let failure {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 28)
    }

    @ViewBuilder
    private func indicator(_ state: RowState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 11))
                .foregroundStyle(Palette.tertiary)
        case .active:
            Spinner(size: 11)
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.label)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.label)
        }
    }

    private func state(of stage: ConnectStage) -> RowState {
        if verified { return .done }
        guard let current else { return .pending }
        let order = Self.order(of: stage)
        let reached = Self.order(of: current)
        if order < reached { return .done }
        if order > reached { return .pending }
        return failure == nil ? .active : .failed
    }

    private static func order(of stage: ConnectStage) -> Int {
        switch stage {
        case .credentials: return 0
        case .devices: return 1
        case .status: return 2
        }
    }
}
