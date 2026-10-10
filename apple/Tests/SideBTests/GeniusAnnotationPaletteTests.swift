import Foundation
import Testing
@testable import SideB

private func annotationPixels(_ rgb: [UInt8], alpha: UInt8 = 255) -> [UInt8] {
    Array(repeating: rgb + [alpha], count: 32 * 32).flatMap { $0 }
}

private func annotationPalette(_ rgb: [UInt8]) -> GeniusAnnotationPalette {
    .from(HomeAmbientPaletteSampler.tints(rgba: annotationPixels(rgb)))
}

@Test func geniusAnnotationTintsFollowArtworkAndOfferComplementaryContrast() {
    let blue = annotationPalette([35, 80, 210])
    let green = annotationPalette([50, 180, 80])
    // Golden values obtained from windows/src/lib/genius/highlight.ts with the same pixels.
    #expect(blue.artwork == HomeAmbientRGB(red: 102 / 255.0, green: 131 / 255.0, blue: 214 / 255.0))
    #expect(blue.contrast == HomeAmbientRGB(red: 161 / 255.0, green: 142 / 255.0, blue: 84 / 255.0))
    #expect(green.artwork == HomeAmbientRGB(red: 75 / 255.0, green: 157 / 255.0, blue: 94 / 255.0))
    #expect(GeniusAnnotationPalette.fallback.artwork == HomeAmbientRGB(red: 140 / 255.0, green: 140 / 255.0, blue: 147 / 255.0))
    #expect(blue.artwork != green.artwork)
    #expect(blue.artwork.hueDistance(to: blue.contrast) > 0.45)
    #expect(blue.artwork.hueDistance(to: HomeAmbientRGB(red: 35 / 255.0, green: 80 / 255.0, blue: 210 / 255.0)) < 0.01)
    #expect(blue.tint(for: .neutral) == HomeAmbientRGB(red: 1, green: 1, blue: 1))
    #expect(blue.tint(for: .neutral, active: true) == blue.artwork)
}

@Test func geniusMissingOrAchromaticArtworkUsesNeutralFallback() {
    for input in [[], [255], annotationPixels([0, 0, 0]), annotationPixels([255, 255, 255]),
                  annotationPixels([120, 120, 120]), annotationPixels([35, 80, 210], alpha: 0)] {
        #expect(GeniusAnnotationPalette.from(HomeAmbientPaletteSampler.tints(rgba: input)) == .fallback)
    }
}

@Test func geniusSelectedAnnotationKeepsWhiteLyricsReadableInEveryMode() {
    func luminance(_ rgb: [Double]) -> Double {
        let linear = rgb.map { value in
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
    let palettes = [GeniusAnnotationPalette.fallback] +
        [[240, 240, 15], [230, 30, 30], [20, 220, 30], [20, 30, 240], [220, 30, 210]].map(annotationPalette)
    for palette in palettes {
        for mode in GeniusAnnotationColorMode.allCases {
            let tint = palette.tint(for: mode, active: true)
            let background = [tint.red, tint.green, tint.blue].map { $0 * 0.48 + 48 / 255.0 * 0.52 }
            let ratio = (luminance([244 / 255.0, 244 / 255.0, 245 / 255.0]) + 0.05) /
                (luminance(background) + 0.05)
            #expect(ratio >= 4.5, "mode=\(mode), contrast=\(ratio)")
        }
    }
}
