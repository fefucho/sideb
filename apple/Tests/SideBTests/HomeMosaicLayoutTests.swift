import CoreGraphics
import Testing
@testable import SideB

// Vectores generados ejecutando windows/src/lib/home/mosaic.ts.
private struct MosaicVector {
    let name: String
    let ids: [String]
    let seed: UInt32
    let columns: Int
    let cells: [(Int, Int, Int, Int, Int, HomeMosaicSize)]
}

private let mosaicVectors: [MosaicVector] = [
    MosaicVector(name: "empty", ids: [], seed: 2166136261, columns: 0, cells: []),
    MosaicVector(name: "one", ids: ["a"], seed: 3826002220, columns: 2, cells: [(0, 0, 0, 2, 2, .large)]),
    MosaicVector(name: "two", ids: ["a", "b"], seed: 453313713, columns: 2, cells: [(0, 0, 0, 2, 2, .large), (1, 0, 2, 1, 1, .small)]),
    MosaicVector(name: "five", ids: ["s0", "s1", "s2", "s3", "s4"], seed: 1205948230, columns: 3, cells: [(0, 0, 0, 2, 2, .large), (1, 0, 2, 1, 1, .small), (2, 1, 2, 1, 1, .small), (3, 2, 0, 1, 1, .small), (4, 2, 1, 1, 1, .small)]),
    MosaicVector(name: "nine", ids: ["song-0", "song-1", "song-2", "song-3", "song-4", "song-5", "song-6", "song-7", "song-8"], seed: 2962246665, columns: 4, cells: [(0, 0, 0, 2, 2, .large), (1, 0, 2, 1, 1, .small), (2, 1, 2, 1, 1, .small), (3, 2, 0, 1, 1, .small), (4, 2, 1, 1, 1, .small), (5, 2, 2, 1, 1, .small), (6, 3, 0, 1, 1, .small), (7, 3, 1, 1, 1, .small), (8, 3, 2, 1, 1, .small)]),
    MosaicVector(name: "twentySeven", ids: ["video0", "video1", "video2", "video3", "video4", "video5", "video6", "video7", "video8", "video9", "video10", "video11", "video12", "video13", "video14", "video15", "video16", "video17", "video18", "video19", "video20", "video21", "video22", "video23", "video24", "video25", "video26"], seed: 4204887079, columns: 13, cells: [(0, 0, 0, 2, 2, .large), (1, 0, 2, 1, 1, .small), (2, 1, 2, 1, 1, .small), (3, 2, 2, 2, 1, .wide), (4, 2, 0, 1, 1, .small), (5, 3, 0, 1, 1, .small), (6, 2, 1, 1, 1, .small), (7, 3, 1, 1, 1, .small), (8, 4, 0, 1, 1, .small), (9, 4, 1, 1, 1, .small), (10, 4, 2, 1, 1, .small), (11, 5, 1, 2, 2, .large), (12, 5, 0, 1, 1, .small), (13, 6, 0, 1, 1, .small), (14, 7, 0, 1, 1, .small), (15, 7, 1, 1, 1, .small), (16, 7, 2, 1, 1, .small), (17, 8, 0, 1, 1, .small), (18, 8, 1, 1, 1, .small), (19, 8, 2, 1, 1, .small), (20, 9, 0, 2, 2, .large), (21, 9, 2, 1, 1, .small), (22, 10, 2, 1, 1, .small), (23, 11, 0, 1, 1, .small), (24, 11, 1, 1, 1, .small), (25, 11, 2, 1, 1, .small), (26, 12, 0, 1, 1, .small)]),
    MosaicVector(name: "realistic", ids: ["dQw4w9WgXcQ", "kJQP7kiw5Fk", "9bZkp7q19f0", "JGwWNGJdvx8", "OPf0YbXqDm0", "RgKAFK5djSk", "fJ9rUzIMcZQ", "hT_nvWreIhg", "CevxZvSJLk8", "YQHsXMglC9A", "2Vv-BfVoq4g", "lp-EO5I60KA", "pRpeEdMmmQ0", "e-ORhEE9VVg"], seed: 135056506, columns: 7, cells: [(0, 0, 0, 2, 2, .large), (1, 0, 2, 1, 1, .small), (2, 1, 2, 1, 1, .small), (3, 2, 1, 2, 1, .wide), (4, 2, 0, 1, 1, .small), (5, 3, 0, 1, 1, .small), (6, 2, 2, 1, 1, .small), (7, 3, 2, 1, 1, .small), (8, 4, 1, 2, 2, .large), (9, 4, 0, 1, 1, .small), (10, 5, 0, 1, 1, .small), (11, 6, 0, 1, 1, .small), (12, 6, 1, 1, 1, .small), (13, 6, 2, 1, 1, .small)]),
    MosaicVector(name: "unicode", ids: ["canción-ñ", "élan", "日本語", "😀emoji", "x"], seed: 2839969086, columns: 3, cells: [(0, 0, 0, 2, 2, .large), (1, 0, 2, 1, 1, .small), (2, 1, 2, 1, 1, .small), (3, 2, 0, 1, 1, .small), (4, 2, 1, 1, 1, .small)]),
]

@Test func mosaicMatchesWindowsReferenceVectors() {
    for vector in mosaicVectors {
        #expect(HomeMosaicLayout.seed(ids: vector.ids) == vector.seed, "seed \(vector.name)")
        let layout = HomeMosaicLayout.make(ids: vector.ids)
        #expect(layout.columns == vector.columns, "columns \(vector.name)")
        let expected = vector.cells.map {
            HomeMosaicCell(index: $0.0, column: $0.1, row: $0.2, columns: $0.3, rows: $0.4, size: $0.5)
        }
        #expect(layout.cells == expected, "cells \(vector.name)")
    }
}

private let mosaicSeeds: [UInt32] = [0, 1, 7, 12345, 0xdeadbeef, 4294967295, HomeMosaicLayout.seed(ids: ["a", "b", "c"])]

@Test func mosaicCoversEverySongOnceInsideGridWithoutOverlapsOrHoles() {
    for count in 0...60 {
        for seed in mosaicSeeds {
            let layout = HomeMosaicLayout.make(count: count, seed: seed)
            #expect(layout.cells.map(\.index) == Array(0..<count))
            var grid = Set<[Int]>()
            for c in layout.cells {
                #expect(c.row >= 0 && c.row + c.rows <= HomeMosaicLayout.rows && c.column >= 0)
                let dims: (Int, Int) = c.size == .small ? (1, 1) : c.size == .wide ? (2, 1) : (2, 2)
                #expect(c.columns == dims.0 && c.rows == dims.1)
                for x in c.column..<(c.column + c.columns) {
                    for y in c.row..<(c.row + c.rows) {
                        #expect(grid.insert([x, y]).inserted, "overlap \(count)/\(seed)")
                    }
                }
            }
            let used = layout.cells.map { $0.column + $0.columns }.max() ?? 0
            #expect(layout.columns == used)
            if count >= 3 {
                for x in 0..<max(0, layout.columns - 1) {
                    for y in 0..<HomeMosaicLayout.rows {
                        #expect(grid.contains([x, y]), "hole \(count)/\(seed) at \(x),\(y)")
                    }
                }
            }
        }
    }
}

@Test func mosaicEmptyAndFirstSongRules() {
    #expect(HomeMosaicLayout.make(count: 0, seed: 5) == HomeMosaicLayout(cells: [], columns: 0))
    #expect(HomeMosaicLayout.make(count: -3, seed: 5) == HomeMosaicLayout(cells: [], columns: 0))
    #expect(HomeMosaicLayout.make(ids: []).cells.isEmpty)
    for count in 1...60 {
        for seed in mosaicSeeds {
            #expect(HomeMosaicLayout.make(count: count, seed: seed).cells[0].size == .large)
        }
    }
}

@Test func mosaicLargePiecesAreSpacedAndAlternate() {
    for count in 1...80 {
        for seed in mosaicSeeds {
            let larges = HomeMosaicLayout.make(count: count, seed: seed).cells.filter { $0.size == .large }
            for (i, c) in larges.enumerated() {
                #expect(c.row == (i % 2 == 0 ? 0 : 1), "alternation \(count)/\(seed)")
                if i > 0 {
                    let gap = c.column - (larges[i - 1].column + 2)
                    #expect(gap >= 1 && gap <= 3, "gap \(gap) \(count)/\(seed)")
                }
            }
        }
    }
}

@Test func mosaicIsDeterministicAndVariesWithSeed() {
    #expect(HomeMosaicLayout.make(count: 40, seed: 99) == HomeMosaicLayout.make(count: 40, seed: 99))
    var shapes = [HomeMosaicLayout]()
    for s in 0..<50 {
        let layout = HomeMosaicLayout.make(ids: Array(repeating: "x\(s)", count: 1) + (0..<39).map { "k\($0)" })
        if !shapes.contains(layout) { shapes.append(layout) }
    }
    #expect(shapes.count > 10)
}

@Test func mosaicSeedIsStableAndOrderSensitive() {
    #expect(HomeMosaicLayout.seed(ids: ["a", "b"]) == HomeMosaicLayout.seed(ids: ["a", "b"]))
    #expect(HomeMosaicLayout.seed(ids: ["a", "b"]) != HomeMosaicLayout.seed(ids: ["b", "a"]))
    #expect(HomeMosaicLayout.seed(ids: ["ab"]) != HomeMosaicLayout.seed(ids: ["a", "b"]))
    #expect(HomeMosaicLayout.seed(ids: []) == 0x811c9dc5)
}

@Test func mosaicMetricsMatchGeometry() {
    #expect(HomeMosaicMetrics.stride == 152)
    #expect(HomeMosaicMetrics.totalHeight == 448)
    let large = HomeMosaicCell(index: 0, column: 2, row: 1, columns: 2, rows: 2, size: .large)
    #expect(HomeMosaicMetrics.frame(of: large) == CGRect(x: 304, y: 152, width: 296, height: 296))
    let small = HomeMosaicCell(index: 1, column: 0, row: 0, columns: 1, rows: 1, size: .small)
    #expect(HomeMosaicMetrics.frame(of: small) == CGRect(x: 0, y: 0, width: 144, height: 144))
    #expect(HomeMosaicMetrics.contentWidth(columns: 0) == 0)
    #expect(HomeMosaicMetrics.contentWidth(columns: 3) == 448)
}
