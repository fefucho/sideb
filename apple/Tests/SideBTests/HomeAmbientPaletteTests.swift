import XCTest
@testable import SideB

final class HomeAmbientPaletteTests: XCTestCase {
    func testDominantTintIgnoresNearBlackAndNearWhitePixels() {
        var pixels: [UInt8] = [255, 255, 255, 255, 8, 8, 8, 255]
        for _ in 0..<8 {
            pixels.append(contentsOf: [220, 40, 35, 255])
        }

        let tint = HomeAmbientPaletteSampler.dominantTint(rgba: pixels)

        XCTAssertNotNil(tint)
        XCTAssertGreaterThan(tint!.red, tint!.green)
        XCTAssertGreaterThan(tint!.red, tint!.blue)
        XCTAssertLessThan(tint!.red - tint!.green, Double(220 - 40) / 255, "The ambient tint softens the measured saturation without losing its hue.")
    }

    func testDominantTintReturnsNilWhenOnlyBlackAndWhitePixelsArePresent() {
        let pixels: [UInt8] = [
            0, 0, 0, 255,
            255, 255, 255, 255
        ]

        XCTAssertNil(HomeAmbientPaletteSampler.dominantTint(rgba: pixels))
    }

    func testSmallChromaticAreaSurvivesLargeGrayAndDarkRegions() {
        var pixels: [UInt8] = []
        for _ in 0..<900 {
            pixels.append(contentsOf: [126, 126, 126, 255])
        }
        for _ in 0..<100 {
            pixels.append(contentsOf: [7, 7, 7, 255])
        }
        for _ in 0..<24 {
            pixels.append(contentsOf: [34, 116, 218, 255])
        }

        let tint = HomeAmbientPaletteSampler.dominantTint(rgba: pixels)

        XCTAssertNotNil(tint)
        XCTAssertGreaterThan(tint!.blue, tint!.green * 1.7)
        XCTAssertGreaterThan(tint!.green, tint!.red * 1.7)
    }

    func testPaletteUsesMeasuredColorsAndNeutralFallbackOnlyWhenNoneExist() {
        let blue = HomeAmbientRGB(red: 0.14, green: 0.38, blue: 0.72)
        let amber = HomeAmbientRGB(red: 0.72, green: 0.43, blue: 0.16)

        XCTAssertEqual(HomeAmbientPalette.from([blue, amber]), HomeAmbientPalette(left: blue, right: amber))
        XCTAssertEqual(HomeAmbientPalette.from([]), .neutral)
    }

    func testDominantTintRejectsMalformedAndFullyTransparentPixels() {
        XCTAssertNil(HomeAmbientPaletteSampler.dominantTint(rgba: [12, 34, 56]))
        XCTAssertNil(HomeAmbientPaletteSampler.dominantTint(rgba: [220, 40, 35, 0]))
    }

    func testArtworkAccentSurvivesDominantEarthTone() {
        var pixels: [UInt8] = []
        for _ in 0..<900 { pixels.append(contentsOf: [144, 105, 81, 255]) }
        for _ in 0..<24 { pixels.append(contentsOf: [34, 116, 218, 255]) }

        let tints = HomeAmbientPaletteSampler.tints(rgba: pixels)

        XCTAssertLessThanOrEqual(tints.count, 3)
        XCTAssertTrue(tints.contains { $0.red > $0.green && $0.green > $0.blue })
        XCTAssertTrue(tints.contains { $0.blue > $0.green * 1.7 })
    }

    func testPaletteSeparatesHueFamiliesInsteadOfRepeatingSimilarCovers() {
        let blue = HomeAmbientRGB(red: 0.10, green: 0.30, blue: 0.80)
        let similarBlue = HomeAmbientRGB(red: 0.12, green: 0.32, blue: 0.78)
        let coral = HomeAmbientRGB(red: 0.70, green: 0.30, blue: 0.24)

        let palette = HomeAmbientPalette.from([blue, blue, similarBlue, coral])

        XCTAssertEqual(palette.left, blue)
        XCTAssertEqual(palette.right, coral)
        XCTAssertEqual(HomeAmbientPalette.from([blue]), HomeAmbientPalette(left: blue, right: blue))
    }
}
