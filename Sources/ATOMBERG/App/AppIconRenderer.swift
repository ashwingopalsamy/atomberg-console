import AppKit

/// The app's icon, drawn in code so the repository holds no binary asset: a near-black squircle with a white fan.
/// `scripts/bundle.sh` runs the binary with `--render-icon <png> [pixels]` to make `AppIcon.icns`, and the About
/// window draws the same image.
@MainActor
enum AppIconRenderer {
    /// `.full` is the icon. `.tile` and `.glyph` are its two layers, which the README banner stacks so only the
    /// blades can turn.
    enum Layer: String {
        case full, tile, glyph
    }

    static func image(size: CGFloat, layer: Layer = .full) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // The macOS icon grid: the tile is 80% of the canvas, centred, with corners of about 22.4% of its width.
            let tile = rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1)
            if layer != .glyph {
                let radius = tile.width * 0.2237
                let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
                NSGradient(colors: [NSColor(white: 0.20, alpha: 1), NSColor(white: 0.055, alpha: 1)])?
                    .draw(in: path, angle: -90)
            }
            guard layer != .tile else { return true }

            let configuration = NSImage.SymbolConfiguration(pointSize: tile.width * 0.5, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let glyph = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                let glyphSize = glyph.size
                glyph.draw(in: NSRect(
                    x: rect.midX - glyphSize.width / 2,
                    y: rect.midY - glyphSize.height / 2,
                    width: glyphSize.width,
                    height: glyphSize.height))
            }
            return true
        }
    }

    /// A square PNG of exactly `pixels` by `pixels`, independent of the display's scale.
    static func pngData(pixels: Int, layer: Layer = .full) -> Data? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else { return nil }
        NSGraphicsContext.current = context
        image(size: CGFloat(pixels), layer: layer).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        return representation.representation(using: .png, properties: [:])
    }
}
