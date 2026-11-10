import AppKit
import CoreGraphics
import SwiftUI
import Testing
import SideBCore
@testable import SideB

@Suite struct PlaybackSidebarPaletteEdgeTests {
    // Helper to calculate relative sRGB luminance (WCAG definition)
    private static func relativeLuminance(_ color: HomeAmbientRGB) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    @Test func syntheticArtworkWithRedTopAndBlueBottomYieldsReddishPrimaryAndBluishSecondary() {
        let side = 24
        // 24 rows * 24 cols. Band is ~22% -> 5 rows.
        // Top 5 rows: pure crimson/red [220, 20, 20, 255]
        // Middle rows: neutral dark grey [40, 40, 40, 255]
        // Bottom 5 rows: deep blue [20, 20, 220, 255]
        var pixels: [UInt8] = []
        for row in 0..<side {
            for _ in 0..<side {
                if row < 5 {
                    pixels.append(contentsOf: [220, 20, 20, 255])
                } else if row >= 19 {
                    pixels.append(contentsOf: [20, 20, 220, 255])
                } else {
                    pixels.append(contentsOf: [40, 40, 40, 255])
                }
            }
        }

        let palette = PlaybackSidebarPalette.from(rgba: pixels, side: side)
        #expect(palette.isChromatic)
        // Primary from top band must be dominantly red
        #expect(palette.primary.red > palette.primary.blue + 0.08)
        #expect(palette.primary.red > palette.primary.green + 0.08)
        // Secondary from bottom band must be dominantly blue
        #expect(palette.secondary.blue > palette.secondary.red + 0.04)
        #expect(palette.secondary.blue > palette.secondary.green + 0.04)
    }

    @Test func uniformCoverMatchesGlobalPalette() {
        let side = 24
        // All pixels uniform warm orange
        var uniformPixels: [UInt8] = []
        for _ in 0..<(side * side) {
            uniformPixels.append(contentsOf: [220, 100, 30, 255])
        }

        let fromBands = PlaybackSidebarPalette.from(rgba: uniformPixels, side: side)
        let globalTints = HomeAmbientPaletteSampler.tints(rgba: uniformPixels)
        let fromGlobal = PlaybackSidebarPalette.from(tints: globalTints)

        #expect(fromBands.isChromatic == fromGlobal.isChromatic)
        #expect(abs(fromBands.primary.red - fromGlobal.primary.red) < 0.001)
        #expect(abs(fromBands.primary.green - fromGlobal.primary.green) < 0.001)
        #expect(abs(fromBands.primary.blue - fromGlobal.primary.blue) < 0.001)
        #expect(abs(fromBands.secondary.red - fromGlobal.secondary.red) < 0.001)
        #expect(abs(fromBands.secondary.green - fromGlobal.secondary.green) < 0.001)
        #expect(abs(fromBands.secondary.blue - fromGlobal.secondary.blue) < 0.001)
    }

    @Test func transparentTopBandFallsBackToGlobalTint() {
        let side = 24
        // Top 5 rows: fully transparent pixels [0, 0, 0, 0]
        // Remaining rows: emerald green [34, 188, 92, 255]
        var pixels: [UInt8] = []
        for row in 0..<side {
            for _ in 0..<side {
                if row < 5 {
                    pixels.append(contentsOf: [0, 0, 0, 0])
                } else {
                    pixels.append(contentsOf: [34, 188, 92, 255])
                }
            }
        }

        let palette = PlaybackSidebarPalette.from(rgba: pixels, side: side)
        #expect(palette.isChromatic)
        // Top band was transparent, so primary fell back to global cover tint (green)
        #expect(palette.primary.green > palette.primary.red)
        #expect(palette.primary.green > palette.primary.blue)
        // Bottom band was directly green
        #expect(palette.secondary.green > palette.secondary.red)
        #expect(palette.secondary.green > palette.secondary.blue)
    }

    @Test func emptyOrInvalidBufferResolvesToNeutral() {
        #expect(PlaybackSidebarPalette.from(rgba: []) == .neutral)
        #expect(PlaybackSidebarPalette.from(rgba: [120, 50, 20]) == .neutral)
        #expect(PlaybackSidebarPalette.from(rgba: [0, 0]) == .neutral)

        // All transparent buffer
        var allTransparent: [UInt8] = []
        for _ in 0..<64 { allTransparent.append(contentsOf: [100, 100, 100, 0]) }
        #expect(PlaybackSidebarPalette.from(rgba: allTransparent) == .neutral)

        // Invalid side or buffer mismatch
        #expect(PlaybackSidebarPalette.from(rgba: [120, 50, 20, 255], side: 24) == .neutral)
    }

    @Test func monochromeArtworkStaysAchromaticWithoutBlueBias() {
        let side = 24
        var greyPixels: [UInt8] = []
        for row in 0..<side {
            let shade: UInt8 = UInt8(60 + row * 4) // Vertical grey gradient without any color
            for _ in 0..<side {
                greyPixels.append(contentsOf: [shade, shade, shade, 255])
            }
        }

        let mono = PlaybackSidebarPalette.from(rgba: greyPixels, side: side)
        #expect(!mono.isChromatic)
        // Perfectly neutral without blue or warm bias
        #expect(abs(mono.primary.red - mono.primary.blue) < 0.0001)
        #expect(abs(mono.primary.red - mono.primary.green) < 0.0001)
        #expect(abs(mono.secondary.red - mono.secondary.blue) < 0.0001)
        #expect(abs(mono.secondary.red - mono.secondary.green) < 0.0001)
    }

    @Test func maximumLuminanceIsEnforcedAcrossExtremeContrastingBands() {
        let side = 24
        // Highly contrasting and luminous bands: neon yellow top, cyan bottom
        var pixels: [UInt8] = []
        for row in 0..<side {
            for _ in 0..<side {
                if row < 5 {
                    pixels.append(contentsOf: [255, 255, 0, 255]) // bright yellow
                } else if row >= 19 {
                    pixels.append(contentsOf: [0, 255, 255, 255]) // bright cyan
                } else {
                    pixels.append(contentsOf: [255, 255, 255, 255]) // white center
                }
            }
        }

        let palette = PlaybackSidebarPalette.from(rgba: pixels, side: side)
        #expect(palette.isChromatic)

        let primaryLum = Self.relativeLuminance(palette.primary)
        let secondaryLum = Self.relativeLuminance(palette.secondary)

        // Clamped to guarantee high contrast with white foreground text
        #expect(primaryLum <= 0.1101)
        #expect(secondaryLum <= 0.0651)

        // Contrast ratio against white foreground (Luminance = 1.0) must exceed WCAG AA (4.5:1)
        let whiteLum = 1.0
        let topContrast = (whiteLum + 0.05) / (primaryLum + 0.05)
        let bottomContrast = (whiteLum + 0.05) / (secondaryLum + 0.05)
        #expect(topContrast > 6.0)
        #expect(bottomContrast > 6.0)
    }

    @Test func yellowCoverPreservesWarmAmberGoldInsteadOfOlive() {
        let side = 24
        // Vibrant bright yellow cover [235, 200, 40, 255]
        var yellowPixels: [UInt8] = []
        for _ in 0..<(side * side) {
            yellowPixels.append(contentsOf: [235, 200, 40, 255])
        }

        let palette = PlaybackSidebarPalette.from(rgba: yellowPixels, side: side)
        #expect(palette.isChromatic)
        // Red must be greater than green to remain warm amber/gold, never olive green (where green >= red)
        #expect(palette.primary.red > palette.primary.green)
        #expect(palette.secondary.red > palette.secondary.green)
        // Blue must be minimal
        #expect(palette.primary.green > palette.primary.blue)
    }

    @Test func mutedEarthyCoverMaintainsSoftSubtleSaturationWithoutOversaturating() {
        let side = 24
        // Muted beige/sepia [200, 184, 153, 255] (Folklore style)
        var beigePixels: [UInt8] = []
        for _ in 0..<(side * side) {
            beigePixels.append(contentsOf: [200, 184, 153, 255])
        }

        let palette = PlaybackSidebarPalette.from(rgba: beigePixels, side: side)
        #expect(palette.isChromatic)
        // Chroma should remain gentle and subtle (< 0.20), never artificially boosted to neon (> 0.35)
        #expect(palette.primary.chroma < 0.20)
        #expect(palette.primary.chroma >= 0.05)
    }
}
