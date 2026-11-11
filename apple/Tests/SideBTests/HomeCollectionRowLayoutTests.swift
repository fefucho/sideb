import CoreGraphics
import Testing
@testable import SideB

@Test func collectionRowMatchesWindowsExamples() {
    let cases: [(CGFloat, Int, CGFloat)] = [(900, 3, 220), (1056, 4, 220), (1360, 5, 220), (1680, 6, 220), (2560, 8, 220)]
    for (width, count, card) in cases {
        let layout = HomeCollectionRowLayout(width: width)
        #expect(layout.count == count, "count \(width)")
        #expect(layout.cardWidth == card, "card \(width)")
        #expect(layout.gap == 24)
        #expect(layout.stride == 244)

        let metrics = HomeCollectionRowLayout.metrics(forAvailableWidth: width)
        #expect(metrics.visibleColumns == count)
        #expect(metrics.cardWidth == 220)
        #expect(metrics.coverSize == 220)
        #expect(metrics.cardHeight == 341)
        #expect(metrics.gap == 24)
        #expect(metrics.stride == 244)
    }
}

@Test func collectionRowKeepsAtLeastTwoCards() {
    #expect(HomeCollectionRowLayout(width: 300).count == 2)
    #expect(HomeCollectionRowLayout(width: 56).count == 2)
    #expect(HomeCollectionRowLayout(width: 300).cardWidth == 220)
}

@Test func collectionRowCapsAtEightWhenWide() {
    let layout = HomeCollectionRowLayout(width: 2056)
    #expect(layout.count == 8)
    #expect(layout.cardWidth == 220)
    #expect(HomeCollectionRowLayout(width: 3000).count == 8)
}

@Test func collectionRowHonorsInsets() {
    // Sin margen derecho: útil = 1000 - 28 = 972, igual que ancho 1028 con márgenes por defecto.
    let open = HomeCollectionRowLayout(width: 1000, leadingInset: 28, trailingInset: 0)
    let reference = HomeCollectionRowLayout(width: 1028)
    #expect(open == reference)
    #expect(HomeCollectionRowLayout(width: 1000, trailingInset: -50) == open)
}

@Test func collectionRowHandlesZeroAndNegativeWidth() {
    for width: CGFloat in [0, -100, 20] {
        let layout = HomeCollectionRowLayout(width: width)
        #expect(layout.count == 2)
        #expect(layout.cardWidth == 220)
        #expect(layout.stride == 244)
    }
}
