import Testing
import SwiftUI
import AppKit
@testable import SideB

@MainActor private func detailHeaderFixture(playlist: Bool) -> CollectionDetailHeaderView {
    CollectionDetailHeaderView(kind: playlist ? "PLAYLIST" : "ÁLBUM", title: "Mr. Morale & The Big Steppers",
                               thumbnail: nil, artworkSymbol: "opticaldisc",
                               credit: "Kendrick Lamar", metadata: ["2022", "19 canciones"],
                               onExpandDescription: {}, onPlay: {}, onShuffle: {}, showsSave: true, onSave: {},
                               query: .constant(""), selectedOrder: playlist ? .custom : nil,
                               canSort: { _ in true }, onSelectOrder: { _ in })
}

@Test @MainActor func sharedCollectionHeaderHasAnIntrinsicHeightAtWideAndCompactWidths() throws {
    for isPlaylist in [true, false] {
        for width: CGFloat in [600, 1100] {
            let header = detailHeaderFixture(playlist: isPlaylist)
                .frame(width: width)
                .background(Color(red: 0.08, green: 0.08, blue: 0.09))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: header)
            renderer.scale = 1
            let image = try #require(renderer.nsImage)
            #expect(abs(image.size.width - width) < 1)
            #expect(image.size.height >= 290)
            #expect(image.size.height < 650)
            if let directory = ProcessInfo.processInfo.environment["SIDEB_DETAIL_PREVIEW_DIR"] {
                // ImageRenderer omits native TextField/Menu; use AppKit for the optional visual preview.
                let host = NSHostingView(rootView: header)
                host.frame = NSRect(origin: .zero, size: image.size)
                host.appearance = NSAppearance(named: .darkAqua)
                host.layoutSubtreeIfNeeded()
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]) {
                        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(isPlaylist ? "playlist" : "album")-\(Int(width)).png"))
                    }
                }
            }
        }
    }
}
