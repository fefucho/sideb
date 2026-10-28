import AppKit
import SwiftUI
import SideBCore
import Testing
@testable import SideB

private struct PlayerMetadataProbe: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); view.identifier = NSUserInterfaceItemIdentifier(name); return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

@MainActor private func metadataDescendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(metadataDescendants)
}

/// Hosts actual SwiftUI text measurement, including secondary badge and Unicode.
@Test @MainActor func playerActionsFollowLongestNaturalLineWithoutConsumingTrailingSpace() throws {
    for (title, secondary) in [("Sol", "Ana"), ("Sol", "Álbum con créditos más largos 🎵"),
                               ("A long title with a featured guest and accents áéíóú", "Ana")] {
        var track = SongItemRecord(videoId: "layout", title: title, artists: secondary,
            album: "Album", duration: nil, thumbnail: nil, artistId: nil,
            albumId: nil, setVideoId: nil)
        track.contentRating = .explicit
        let metadata = VStack(alignment: .leading, spacing: 2) {
            FeaturedTrackTitle(track: track, font: .system(size: 14, weight: .semibold),
                color: .primary, scrollsOnOverflow: true) { _, _ in }
                .frame(maxWidth: .infinity)
            ContentRatedMetadata(rating: track.contentRating, fontSize: 11.5) {
                HStack(spacing: 6) {
                    TrackArtistLinks(track: track, font: .system(size: 11.5, weight: .medium),
                        color: .secondary, hoverColor: .primary) { _, _ in }
                    Text("•").font(.system(size: 10))
                    Text("Album").font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        let natural = NSHostingView(rootView: metadata.fixedSize(horizontal: true, vertical: false)).fittingSize.width
        // These are the metadata/action slots derived from 620/700/760/820pt bars.
        for available in [CGFloat(138), 218, 176, 236] {
            let root = NSHostingView(rootView: VStack(spacing: 0) {
                PlayerBarMetadataActionLayout {
                    metadata.background(PlayerMetadataProbe(name: "metadata"))
                    HStack(spacing: 4) {
                        Color.clear.frame(width: 32, height: 44)
                        VStack(spacing: 2) {
                            Color.clear.frame(width: 24, height: 22)
                            Color.clear.frame(width: 24, height: 22)
                        }
                    }
                    .frame(width: 60, height: 46)
                    .background(PlayerMetadataProbe(name: "actions"))
                }
                .background(PlayerMetadataProbe(name: "slot"))
            }.frame(width: available, height: 100))
            root.sizingOptions = []
            root.frame = CGRect(x: 0, y: 0, width: available, height: 100)
            root.layoutSubtreeIfNeeded()
            let views = metadataDescendants(root)
            let slot = try #require(views.first { $0.identifier?.rawValue == "slot" })
            #expect(abs(slot.convert(slot.bounds, to: root).height - 46) < 0.5)
            let text = try #require(views.first { $0.identifier?.rawValue == "metadata" })
            let actions = try #require(views.first { $0.identifier?.rawValue == "actions" })
            let textFrame = text.convert(text.bounds, to: root)
            let actionFrame = actions.convert(actions.bounds, to: root)
            #expect(abs(textFrame.width - min(natural, available - 70)) < 1)
            #expect(abs(actionFrame.minX - textFrame.maxX - 10) < 1)
            #expect(abs(actionFrame.width - 60) < 0.5)
            #expect(abs(actionFrame.height - 46) < 0.5)
            #expect(actionFrame.maxX <= available + 0.5)
        }
    }
}
