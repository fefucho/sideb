import AppKit

/// `NSCollectionViewLayout` del mosaico de canciones: entrega los marcos de `HomeMosaicMetrics`
/// desplazados por el margen izquierdo, con los márgenes dentro del contenido desplazable.
/// No depende del tamaño del viewport, así que no se invalida al cambiar los límites.
final class HomeMosaicCollectionLayout: NSCollectionViewLayout {
    private(set) var mosaic: HomeMosaicLayout = .empty
    private(set) var leadingInset: CGFloat = 0
    private(set) var trailingInset: CGFloat = 0
    private var frames: [CGRect] = []
    private var contentSize = NSSize(width: 0, height: HomeMosaicMetrics.totalHeight)

    /// Recalcula los marcos sólo si cambia la disposición o los márgenes.
    func update(mosaic newMosaic: HomeMosaicLayout, leadingInset newLeading: CGFloat, trailingInset newTrailing: CGFloat) {
        let leading = max(0, newLeading), trailing = max(0, newTrailing)
        guard newMosaic != mosaic || leading != leadingInset || trailing != trailingInset else { return }
        mosaic = newMosaic
        leadingInset = leading
        trailingInset = trailing
        frames = newMosaic.cells.map { cell in
            HomeMosaicMetrics.frame(of: cell).offsetBy(dx: leading, dy: 0)
        }
        let width = newMosaic.columns > 0
            ? leading + HomeMosaicMetrics.contentWidth(columns: newMosaic.columns) + trailing : 0
        contentSize = NSSize(width: width, height: HomeMosaicMetrics.totalHeight)
        invalidateLayout()
    }

    func frame(forItem index: Int) -> CGRect? { frames.indices.contains(index) ? frames[index] : nil }

    override var collectionViewContentSize: NSSize { contentSize }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        frames.indices.compactMap { index in
            frames[index].intersects(rect) ? attributes(at: index) : nil
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.section == 0, frames.indices.contains(indexPath.item) else { return nil }
        return attributes(at: indexPath.item)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool { false }

    private func attributes(at index: Int) -> NSCollectionViewLayoutAttributes {
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
        attributes.frame = frames[index]
        return attributes
    }
}

/// Avance de las flechas de los carriles (mosaico y colecciones): port de `horizontalPageTarget` (HorizontalNavigation.svelte)
/// para listas virtuales con paso fijo.
enum HomeRailPaging {
    static func target(position: CGFloat, extent: CGFloat, maximum: CGFloat, direction: CGFloat,
                       stride: CGFloat = HomeMosaicMetrics.stride) -> CGFloat {
        let current = max(0, min(maximum, position))
        let width = max(1, extent)
        var target = current + direction * width
        if stride > 0, width >= stride {
            let columns = max(1, (width / stride).rounded(.down))
            target = (direction > 0
                ? ((current + 0.5) / stride).rounded(.down) + columns
                : ((current - 0.5) / stride).rounded(.up) - columns) * stride
        }
        return max(0, min(maximum, target))
    }
}
