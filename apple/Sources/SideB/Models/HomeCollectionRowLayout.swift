import CoreGraphics

public struct HomeCollectionRowMetrics: Equatable {
    public let visibleColumns: Int
    public let cardWidth: CGFloat
    public let coverSize: CGFloat
    public let cardHeight: CGFloat
    public let gap: CGFloat
    public let stride: CGFloat

    public init(visibleColumns: Int, cardWidth: CGFloat, coverSize: CGFloat, cardHeight: CGFloat, gap: CGFloat, stride: CGFloat) {
        self.visibleColumns = visibleColumns
        self.cardWidth = cardWidth
        self.coverSize = coverSize
        self.cardHeight = cardHeight
        self.gap = gap
        self.stride = stride
    }
}

/// Cantidad y ancho de las tarjetas de la fila de colecciones (port de `collectionRowLayout` de Windows).
struct HomeCollectionRowLayout: Equatable {
    static let gap: CGFloat = 24
    static let fixedCardWidth: CGFloat = 220
    static let horizontalPadding: CGFloat = 56
    static let minCards = 2
    static let maxCards = 8
    static let metadataHeight: CGFloat = 121

    let count: Int
    let cardWidth: CGFloat

    var gap: CGFloat { Self.gap }
    var stride: CGFloat { cardWidth + Self.gap }

    /// Los márgenes se restan del ancho; el derecho es 0 con el reproductor lateral abierto.
    init(width: CGFloat, leadingInset: CGFloat = 28, trailingInset: CGFloat = 28) {
        let useful = max(0, width - leadingInset - max(0, trailingInset))
        let cardWidth = Self.fixedCardWidth
        let stride = cardWidth + Self.gap
        let count = min(Self.maxCards, max(Self.minCards, Int(((useful + Self.gap) / stride).rounded(.down))))
        self.count = count
        self.cardWidth = cardWidth
    }

    static func metrics(forAvailableWidth availableWidth: CGFloat, contentHeight: CGFloat = 0) -> HomeCollectionRowMetrics {
        let useful = max(0, availableWidth - horizontalPadding)
        let cardWidth = fixedCardWidth
        let stride = cardWidth + gap
        let count = min(maxCards, max(minCards, Int(((useful + gap) / stride).rounded(.down))))
        return HomeCollectionRowMetrics(
            visibleColumns: count,
            cardWidth: cardWidth,
            coverSize: cardWidth,
            cardHeight: cardWidth + metadataHeight,
            gap: gap,
            stride: stride
        )
    }
}
