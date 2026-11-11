import CoreGraphics
import Foundation

/// Tamaño de una celda del mosaico del Inicio destacado.
enum HomeMosaicSize: Equatable {
    case small, wide, large
}

struct HomeMosaicCell: Equatable {
    let index: Int
    let column: Int
    let row: Int
    let columns: Int
    let rows: Int
    let size: HomeMosaicSize
}

struct HomeMosaicLayout: Equatable {
    let cells: [HomeMosaicCell]
    let columns: Int

    static let rows = 3
    static let empty = HomeMosaicLayout(cells: [], columns: 0)
}

/// Geometría en puntos del mosaico (celda 144, separación 8).
enum HomeMosaicMetrics {
    static let cellSize: CGFloat = 144
    static let spacing: CGFloat = 8
    static let stride: CGFloat = cellSize + spacing
    static let totalHeight: CGFloat = CGFloat(HomeMosaicLayout.rows) * stride - spacing

    static func frame(of cell: HomeMosaicCell) -> CGRect {
        CGRect(x: CGFloat(cell.column) * stride, y: CGFloat(cell.row) * stride,
               width: CGFloat(cell.columns) * stride - spacing,
               height: CGFloat(cell.rows) * stride - spacing)
    }

    static func contentWidth(columns: Int) -> CGFloat {
        max(0, CGFloat(columns) * stride - spacing)
    }
}

// Port exacto de windows/src/lib/home/mosaic.ts: mismas celdas para los mismos IDs.
extension HomeMosaicLayout {
    private enum Block { case t, b, w, s }

    private static func need(_ block: Block) -> Int {
        block == .w ? 5 : 3
    }

    private static func width(_ block: Block) -> Int {
        block == .s ? 1 : 2
    }

    private static let gaps: [[[Block]]] = [[], [[.s]], [[.s, .s], [.w]], [[.s, .s, .s], [.s, .w], [.w, .s]]]

    /// FNV-1a de 32 bits sobre los IDs unidos por U+001F, recorridos como unidades UTF-16 (como `charCodeAt`).
    static func seed(ids: [String]) -> UInt32 {
        var hash: UInt32 = 0x811c9dc5
        for unit in ids.joined(separator: "\u{001F}").utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 0x01000193
        }
        return hash
    }

    /// mulberry32; cada llamada devuelve un valor en [0, 1).
    private struct Mulberry32 {
        var state: UInt32

        mutating func next() -> Double {
            state = state &+ 0x6d2b79f5
            var t = state
            t = (t ^ (t >> 15)) &* (t | 1)
            t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
            return Double(t ^ (t >> 14)) / 4294967296
        }
    }

    static func make(ids: [String]) -> HomeMosaicLayout {
        make(count: ids.count, seed: seed(ids: ids))
    }

    /// Disposición por bloques sin huecos para `count` canciones.
    static func make(count: Int, seed: UInt32) -> HomeMosaicLayout {
        guard count > 0 else { return .empty }
        var random = Mulberry32(state: seed)
        var cells: [HomeMosaicCell] = []
        var next = 0
        var column = 0
        var largeIsTop = true
        var queue: [Block] = [.t]

        func cell(_ index: Int, _ column: Int, _ row: Int, _ size: HomeMosaicSize) -> HomeMosaicCell {
            HomeMosaicCell(index: index, column: column, row: row,
                           columns: size == .small ? 1 : 2, rows: size == .large ? 2 : 1, size: size)
        }
        func small(_ c: Int, _ r: Int, limit: Int) {
            if next < limit { cells.append(cell(next, c, r, .small)); next += 1 }
        }
        func emit(_ block: Block, limit: Int) {
            switch block {
            case .t, .b:
                cells.append(cell(next, column, block == .t ? 0 : 1, .large)); next += 1
                let row = block == .t ? 2 : 0
                small(column, row, limit: limit)
                small(column + 1, row, limit: limit)
            case .w:
                let wideRow = Int((random.next() * Double(HomeMosaicLayout.rows)).rounded(.down))
                cells.append(cell(next, column, wideRow, .wide)); next += 1
                for r in 0..<HomeMosaicLayout.rows where r != wideRow {
                    small(column, r, limit: limit)
                    small(column + 1, r, limit: limit)
                }
            case .s:
                for r in 0..<HomeMosaicLayout.rows { small(column, r, limit: limit) }
            }
            column += width(block)
        }

        while next < count {
            if queue.isEmpty {
                // Tras una pieza grande: 1 a 3 columnas sin large, y luego la grande opuesta.
                let options = gaps[1 + Int((random.next() * 3).rounded(.down))]
                queue = options[Int((random.next() * Double(options.count)).rounded(.down))]
                largeIsTop.toggle()
                queue.append(largeIsTop ? .t : .b)
            }
            var block = queue.removeFirst()
            let left = count - next
            if block != .t, block != .b, need(block) > left { block = .s }
            if block == .t, next == 0 { emit(.t, limit: count) }
            else if need(block) <= left { emit(block, limit: count) }
            else { emit(.s, limit: count); break }
        }
        return HomeMosaicLayout(cells: cells, columns: column)
    }
}
