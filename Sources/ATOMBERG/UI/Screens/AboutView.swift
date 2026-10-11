import SwiftUI

/// The About window's content: the icon, the name and version, two plain statements, the copyright.
/// Same type scale and neutral colours as the popover, and no marketing.
struct AboutView: View {
    static let size = CGSize(width: 320, height: 420)
    static let repository = URL(string: "https://github.com/ashwingopalsamy/atomberg-console")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: AppIconRenderer.image(size: 256))
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .padding(.top, 28)
                .accessibilityHidden(true)
            Text("Atomberg Console")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.label)
                .padding(.top, 4)
            Text(version)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Palette.secondary)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 14) {
                statement(
                    symbol: "hand.raised",
                    text: "Unofficial. Not affiliated with, endorsed by or supported by Atomberg. The name and logo belong to their owners.")
                statement(
                    symbol: "doc.text",
                    text: "Free for noncommercial use under PolyForm Noncommercial 1.0.0. Provided without warranty.")
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            Link(destination: Self.repository) {
                Label("github.com/ashwingopalsamy/atomberg-console", systemImage: "arrow.up.right.square")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.top, 20)

            Spacer(minLength: 0)

            Text("© 2026 Ashwin Gopalsamy")
                .font(.system(size: 11))
                .foregroundStyle(Palette.tertiary)
                .padding(.bottom, 20)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private func statement(symbol: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
