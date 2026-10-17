import AppKit
import QuartzCore
import SwiftUI
import XCTest
@testable import SideB

@MainActor final class HomeAmbientLayerTests: XCTestCase {
    func testCoreImageTreeNeverEntersTheWindowLayerHierarchy() throws {
        let view = HomeAmbientLayerNSView(fixedTime: 17)
        view.configure(palette: .neutral, smokeMask: nil, active: false, reduceMotion: true, displayScale: 2)
        view.frame.size = CGSize(width: 960, height: 640)
        view.layoutSubtreeIfNeeded()
        let presentation = try XCTUnwrap(view.layer as? CAMetalLayer)
        XCTAssertFalse(view.layerUsesCoreImageFilters)
        XCTAssertNil(view.renderLayer.superlayer)
        XCTAssertTrue(presentation.sublayers?.isEmpty ?? true)
        XCTAssertEqual(presentation.drawableSize, CGSize(width: 1920, height: 1280))
        XCTAssertEqual(view.renderLayer.bounds.size, presentation.drawableSize)
        XCTAssertEqual(view.renderLayer.sublayers?.first?.transform.m11, 2)
        XCTAssertEqual(view.renderLayer.sublayers?.first?.transform.m22, 2)
        XCTAssertNotNil(view.renderLayer.sublayers?.first?.sublayers?.first {
            $0.compositingFilter is CIFilter
        }, "Compositing filters are retained in the isolated renderer only")
        view.releaseContent()
    }

    func testActivityAndReduceMotionPauseTheNativeClockWithoutResettingIt() {
        let view = HomeAmbientLayerNSView(initialTime: 17)
        func date(_ time: Double) -> Date { Date(timeIntervalSinceReferenceDate: time) }
        func configure(active: Bool, reduced: Bool, at time: Double, palette: HomeAmbientPalette = .neutral) {
            view.configure(palette: palette, smokeMask: nil, active: active,
                reduceMotion: reduced, displayScale: 2, at: date(time))
        }
        configure(active: true, reduced: false, at: 1000)
        XCTAssertEqual(view.motionTime(at: date(1004)), 21)
        configure(active: true, reduced: false, at: 1004,
            palette: HomeAmbientPalette(left: .init(red: 0.8, green: 0.1, blue: 0.2), right: .init(red: 0.1, green: 0.3, blue: 0.8)))
        XCTAssertEqual(view.motionTime(at: date(1008)), 25)
        configure(active: false, reduced: false, at: 1008)
        XCTAssertEqual(view.motionTime(at: date(2000)), 25)
        configure(active: true, reduced: true, at: 2000)
        XCTAssertEqual(view.motionTime(at: date(2005)), 25)
        configure(active: true, reduced: false, at: 2005)
        XCTAssertEqual(view.motionTime(at: date(2010)), 30)
        configure(active: false, reduced: false, at: 2010)
        XCTAssertEqual(view.motionTime(at: date(3000)), 30)
    }

    func testGeometryMatchesOriginalTrajectoriesAtDifferentSizesAndPhases() {
        let times: [Double] = [0, 0.5, 17, 36, 42, 88, 1234.5, 800_000_000.25]
        for size in [CGSize(width: 960, height: 640), CGSize(width: 1321, height: 831),
                     CGSize(width: 1512, height: 949)] {
            for time in times {
                let geometry = HomeAmbientLayerGeometry(size: size, time: time)
                let origins: [(Double, Double, Double, Double, Double)] = [
                    (0.06, 0.02, 42, 0.11, 0), (0.94, 0.18, 50, 0.11, 2),
                    (0.43, 0.73, 36, 0.15, 4)
                ]
                for (index, input) in origins.enumerated() {
                    let (x, y, period, amplitude, phase) = input
                    let a = time * 2 * Double.pi / period + phase
                    XCTAssertEqual(geometry.cloudCenters[index].x,
                        (x + sin(a) * amplitude) * size.width, accuracy: 0.000001)
                    XCTAssertEqual(geometry.cloudCenters[index].y,
                        (y + cos(a * 0.8) * amplitude) * size.height, accuracy: 0.000001)
                    XCTAssertEqual(geometry.cloudRadii[index],
                        max(size.width, size.height) * [0.62, 0.58, 0.42][index], accuracy: 0.000001)
                }
                XCTAssertEqual(geometry.smokeOffsets[0].x, sin(time * 2 * .pi / 45) * size.width * 0.11, accuracy: 0.000001)
                XCTAssertEqual(geometry.smokeOffsets[0].y, cos(time * 2 * .pi / 56) * size.height * 0.06, accuracy: 0.000001)
                XCTAssertEqual(geometry.smokeOffsets[1].x, cos(time * 2 * .pi / 65 + 1) * size.width * 0.14, accuracy: 0.000001)
                XCTAssertEqual(geometry.smokeOffsets[1].y, sin(time * 2 * .pi / 78 + 2) * size.height * 0.08, accuracy: 0.000001)
                XCTAssertEqual(geometry.smokeAngles[0], sin(time * 2 * .pi / 70) * 3.5 * .pi / 180, accuracy: 0.000001)
                XCTAssertEqual(geometry.smokeAngles[1], cos(time * 2 * .pi / 88) * 4.5 * .pi / 180, accuracy: 0.000001)
                XCTAssertEqual(geometry.smokeScales, [CGSize(width: 1.5, height: 1.5), CGSize(width: -1.75, height: 1.75)])
            }
        }
    }

    func testWaveKeyframesStayBelowSubpixelErrorAndJoinAtPeriodBoundary() {
        for cosine in [false, true] {
            for period: Double in [36, 42, 50, 52.5, 56, 65, 70, 78, 88] {
                let wave = HomeAmbientWave(base: 24, amplitude: 1512 * 0.15,
                    period: period, phase: 2.3, isCosine: cosine)
                for start: Double in [0, 1234.5, 800_000_000.25] {
                    let values = wave.samples(startingAt: start)
                    XCTAssertGreaterThan(values.count, 100)
                    XCTAssertEqual(values.first!, values.last!, accuracy: 0.00001)
                    let step = period / Double(values.count - 1)
                    for index in stride(from: 0, to: values.count - 1, by: 13) {
                        let midpoint = start + (Double(index) + 0.5) * step
                        let actual = wave.value(at: midpoint)
                        let interpolated = (values[index] + values[index + 1]) / 2
                        XCTAssertLessThanOrEqual(abs(actual - interpolated), wave.maximumInterpolationError + 0.0001)
                        XCTAssertLessThan(abs(actual - interpolated) * 2, 0.01, "Error at2x must remain far below a pixel")
                    }
                }
            }
        }
    }

    func testFrozenRendererResizesWithoutTakingInputOrChangingItsPhase() {
        let view = HomeAmbientLayerNSView(initialTime: 100, fixedTime: 17)
        view.configure(palette: .neutral, smokeMask: nil, active: true, reduceMotion: false, displayScale: 2)
        let originalLayer = view.layer
        for size in [CGSize(width: 960, height: 640), CGSize(width: 1512, height: 949), CGSize(width: 1321, height: 831)] {
            view.frame.size = size
            view.layoutSubtreeIfNeeded()
            XCTAssertTrue(view.layer === originalLayer)
            XCTAssertEqual(view.layer?.bounds.size, size)
            XCTAssertEqual(view.motionTime(), 17)
            XCTAssertNil(view.hitTest(CGPoint(x: 20, y: 20)))
            XCTAssertFalse(view.acceptsFirstResponder)
            XCTAssertTrue(view.accessibilityChildren()?.isEmpty == true)
        }
        view.configure(palette: HomeAmbientPalette(left: HomeAmbientRGB(red: 0.8, green: 0.1, blue: 0.2), right: .init(red: 0.1, green: 0.3, blue: 0.8)),
            smokeMask: nil, active: false, reduceMotion: true, displayScale: 1)
        XCTAssertEqual(view.motionTime(), 17)
        XCTAssertTrue(view.layer === originalLayer)
        XCTAssertNil(view.window)
    }
}
