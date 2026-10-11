import SwiftUI

/// The first-run grid, 440 × 352: brand row at y 36, title, a two-line message, a 104pt card region, a note,
/// and a footer 20pt from the bottom. Every step uses the same heights, so the push between steps moves nothing
/// but the content.
struct StepLayout<Middle: View, Note: View, Buttons: View>: View {
    let step: Int
    let title: String
    let message: String
    @ViewBuilder var middle: Middle
    @ViewBuilder var note: Note
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                BrandMark()
                Spacer(minLength: 12)
                Text("Unofficial app · Not affiliated with Atomberg")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            .frame(height: 24)
            .padding(.top, 36)

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.label)
                .lineLimit(1)
                .frame(height: 24, alignment: .topLeading)
                .padding(.top, 16)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
                .lineLimit(2)
                .frame(height: 32, alignment: .topLeading)
                .padding(.top, 4)

            // Card's fill is inset groupInset inside its frame. Pulling the frame out by the same amount puts the
            // fill on the title's edge at x 24, and the content adds it back so the text stays at x 40.
            Card {
                middle
                    .padding(.horizontal, 16 + Metric.groupInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, -Metric.groupInset)
            .frame(height: 104)
            .padding(.top, 20)

            note
                .frame(height: 26, alignment: .topLeading)
                .padding(.top, 8)

            Spacer(minLength: 10)

            HStack(spacing: 8) {
                Text("Step \(step) of 4")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                buttons
            }
            .frame(height: 28)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A label column and a value, the two-row facts inside a card.
struct TermRow<Value: View>: View {
    let name: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.label)
                .frame(width: 120, alignment: .leading)
            value
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .frame(height: 36)
    }
}
