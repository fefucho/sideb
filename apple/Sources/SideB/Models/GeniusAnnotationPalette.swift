import AppKit

enum GeniusAnnotationColorMode: String, CaseIterable {
    case artwork, contrast, neutral

    var title: String {
        switch self {
        case .artwork: L10n.text("genius.colorArtwork")
        case .contrast: L10n.text("genius.colorContrast")
        case .neutral: L10n.text("genius.colorNeutral")
        }
    }
}

/// Matches Windows' Genius tints, including its bound for legible white lyrics.
struct GeniusAnnotationPalette: Sendable, Equatable {
    let artwork: HomeAmbientRGB
    let contrast: HomeAmbientRGB

    static let fallback: Self = {
        let grey = readable(HomeAmbientRGB(red: 190 / 255.0, green: 190 / 255.0, blue: 200 / 255.0))
        return Self(artwork: grey, contrast: grey)
    }()

    static func from(_ tints: [HomeAmbientRGB]) -> Self {
        guard let dominant = tints.first else { return .fallback }
        let maximum = max(dominant.red, dominant.green, dominant.blue)
        let chroma = dominant.chroma
        let hue: Double
        if chroma == 0 { hue = 0 }
        else if maximum == dominant.red { hue = (dominant.green - dominant.blue) / chroma / 6 }
        else if maximum == dominant.green { hue = ((dominant.blue - dominant.red) / chroma + 2) / 6 }
        else { hue = ((dominant.red - dominant.green) / chroma + 4) / 6 }
        let normalizedHue = (hue + 1).truncatingRemainder(dividingBy: 1)
        return Self(
            artwork: readable(hsl(hue: normalizedHue, saturation: 0.58, lightness: 0.62)),
            contrast: readable(hsl(hue: (normalizedHue + 0.5).truncatingRemainder(dividingBy: 1),
                                   saturation: 0.52, lightness: 0.62))
        )
    }

    func tint(for mode: GeniusAnnotationColorMode, active: Bool = false) -> HomeAmbientRGB {
        if mode == .neutral, !active { return HomeAmbientRGB(red: 1, green: 1, blue: 1) }
        return mode == .contrast ? contrast : artwork
    }

    @MainActor
    static func resolve(thumbnail: String?) async -> Self {
        guard let thumbnail,
              let url = ImageURLHelper.optimizedThumbnailURL(from: thumbnail, targetPixelSize: 32),
              let image = await ImageCache.shared.image(for: url, targetSize: CGSize(width: 32, height: 32)),
              !Task.isCancelled else { return .fallback }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return .fallback }
        return await Task.detached(priority: .utility) {
            Self.from(HomeAmbientPaletteSampler.tints(of: cgImage))
        }.value
    }

    private static func hsl(hue: Double, saturation: Double, lightness: Double) -> HomeAmbientRGB {
        let a = saturation * min(lightness, 1 - lightness)
        func component(_ n: Double) -> Double {
            let k = (n + hue * 12).truncatingRemainder(dividingBy: 12)
            return ((lightness - a * max(-1, min(k - 3, 9 - k, 1))) * 255).rounded() / 255
        }
        return HomeAmbientRGB(red: component(0), green: component(8), blue: component(4))
    }

    private static func readable(_ color: HomeAmbientRGB) -> HomeAmbientRGB {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        var r = color.red, g = color.green, b = color.blue
        while 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) > 0.28 {
            r *= 0.95; g *= 0.95; b *= 0.95
        }
        return HomeAmbientRGB(red: (r * 255).rounded() / 255,
                              green: (g * 255).rounded() / 255,
                              blue: (b * 255).rounded() / 255)
    }
}
