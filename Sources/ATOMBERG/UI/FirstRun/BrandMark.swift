import SwiftUI
import AppKit

/// The logo as an identifier. The mark keeps its colours; the wordmark is a label-coloured template so it
/// reads in both appearances. Both SVGs share the logo's 160×50 viewBox, so they stack exactly.
struct BrandMark: View {
    static let size = CGSize(width: 76.8, height: 24)   // 160 × 50 at 24pt high

    var body: some View {
        ZStack {
            if let mark = BrandAssets.mark {
                Image(nsImage: mark).resizable()
            }
            if let wordmark = BrandAssets.wordmark {
                Image(nsImage: wordmark)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Palette.label)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}

/// Loaded once. A missing file leaves its layer out and keeps the layout, so the window never breaks.
@MainActor
private enum BrandAssets {
    static let mark = load("atomberg-mark")
    static let wordmark = load("atomberg-wordmark")

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Brand") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
