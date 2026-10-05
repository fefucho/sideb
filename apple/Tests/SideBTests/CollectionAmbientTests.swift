import XCTest
@testable import SideB

final class CollectionAmbientTests: XCTestCase {
    func testFadeIsContinuousAndFullyClearAtTheBottom() {
        XCTAssertEqual(CollectionAmbientMotion.fadeOpacity(at: 0), 1)
        XCTAssertEqual(CollectionAmbientMotion.fadeOpacity(at: 0.28), 1, accuracy: 0.0001)
        XCTAssertEqual(CollectionAmbientMotion.fadeOpacity(at: 0.60), 1, accuracy: 0.0001)
        XCTAssertEqual(CollectionAmbientMotion.fadeOpacity(at: 0.80), 0.5, accuracy: 0.0001)
        XCTAssertEqual(CollectionAmbientMotion.fadeOpacity(at: 1), 0)
        XCTAssertEqual(CollectionAmbientMotion.fadeOpacity(at: 2), 0)
        XCTAssertEqual(CollectionAmbientMotion.fadeOpacity(at: -1), 1)

        var previousOpacity = CollectionAmbientMotion.fadeOpacity(at: 0)
        for step in 1...100 {
            let opacity = CollectionAmbientMotion.fadeOpacity(at: Double(step) / 100)
            XCTAssertLessThanOrEqual(opacity, previousOpacity)
            XCTAssertLessThanOrEqual(previousOpacity - opacity, 0.04)
            previousOpacity = opacity
        }
    }

    func testDriftStaysWithinSubtleArtworkBoundsAndRepeatsByPeriod() {
        let origin = 0.08
        let period = 132.0
        let positions = stride(from: 0.0, through: period, by: 0.25).map {
            CollectionAmbientMotion.drift(origin, time: $0, period: period)
        }

        XCTAssertEqual(positions.first!, positions.last!, accuracy: 0.0001)
        XCTAssertLessThanOrEqual((positions.max() ?? origin) - origin, 0.0271)
        XCTAssertLessThanOrEqual(origin - (positions.min() ?? origin), 0.0271)
    }
}
