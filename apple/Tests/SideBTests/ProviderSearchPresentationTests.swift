import AppKit
import SwiftUI
import Testing
import SideBCore
@testable import SideB

@MainActor
struct ProviderSearchPresentationTests {
    private func card(_ kind: String, _ id: String, _ title: String) -> BrowseCardRecord {
        let subtitle = kind == "artist" ? nil : (kind == "song" || kind == "video" ? "Kendrick Lamar · DAMN." : "Kendrick Lamar · 2017")
        return BrowseCardRecord(kind: kind, id: id, title: title, subtitle: subtitle,
            thumbnail: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg", duration: kind == "song" ? "4:08" : nil)
    }

    private func song(_ id: String, setVideoId: String?, title: String = "DUCKWORTH.") -> SongItemRecord {
        SongItemRecord(videoId: id, title: title, artists: "Kendrick Lamar", album: "DAMN.",
            duration: "4:08", thumbnail: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg", artistId: "artist", albumId: "album",
            setVideoId: setVideoId, isVideo: false, isUpload: false, library: nil)
    }

    private func section(_ cards: [BrowseCardRecord], _ songs: [SongItemRecord] = [], primary: UInt32?, related: [UInt32] = []) -> SearchSectionRecord {
        SearchSectionRecord(id: "fixture", title: "", layout: "top", items: cards, songs: songs,
            primaryItemIndex: primary, relatedItemIndices: related,
            moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: [])
    }

    @Test func roleProjectionRequiresUniqueInRangeOccurrenceIndices() {
        let artist = card("artist", "UC1", "Kendrick Lamar")
        let songs = [card("song", "v1", "DUCKWORTH."), card("song", "v2", "Swimming Pools"), card("song", "v3", "Alright")]
        let valid = section([artist] + songs, primary: 0, related: [1, 2, 3])
        #expect(ProviderSearchProjection.roles(for: valid) == ProviderSearchSectionRoles(primaryIndex: 0, relatedIndices: [1, 2, 3]))
        #expect(ProviderSearchProjection.roles(for: section([artist] + songs, primary: 0, related: [1, 1])) == nil)
        #expect(ProviderSearchProjection.roles(for: section([artist] + songs, primary: 0, related: [0, 1])) == nil)
        #expect(ProviderSearchProjection.roles(for: section([artist], primary: 5)) == nil)
        #expect(ProviderSearchProjection.roles(for: section([artist], primary: nil)) == nil)
        #expect(ProviderSearchProjection.roles(for: section([card("podcast", "podcast", "Podcast")], primary: 0)) == nil)
        #expect(ProviderSearchProjection.roles(for: section([card("playlist", "PL1", "Mix")], primary: 0))?.primaryIndex == 0)
        #expect(ProviderSearchProjection.principalLayout(kind: "artist", hasRelated: true, width: 618) == .artistStacked)
        #expect(ProviderSearchProjection.principalLayout(kind: "artist", hasRelated: true, width: 680) == .artistRelatedBelow)
        #expect(ProviderSearchProjection.principalLayout(kind: "artist", hasRelated: true, width: 959) == .artistRelatedBelow)
        #expect(ProviderSearchProjection.principalLayout(kind: "artist", hasRelated: true, width: 960) == .artistSplit)
        #expect(ProviderSearchProjection.principalLayout(kind: "song", hasRelated: false, width: 618) == .fullStrip)
    }

    @Test func songPayloadsStayBoundToOccurrencesWhenIdsRepeat() {
        let cards = [card("song", "same", "First"), card("song", "same", "Second")]
        let first = song("same", setVideoId: "set-first")
        let second = song("same", setVideoId: "set-second")
        let page = section(cards, [first, second], primary: nil)
        #expect(ProviderSearchProjection.song(for: 0, in: page)?.setVideoId == "set-first")
        #expect(ProviderSearchProjection.song(for: 1, in: page)?.setVideoId == "set-second")
        #expect(ProviderSearchProjection.song(for: 4, in: page) == nil)
    }

    @Test func nativePrincipalFixturesFitCompactAndWideContentWidths() async throws {
        let relatedCards = [card("artist", "UC1", "Kendrick Lamar"), card("song", "v1", "DUCKWORTH."),
            card("song", "v2", "HUMBLE."), card("song", "v3", "DNA."),
            card("song", "v4", "ELEMENT."), card("song", "v5", "LOYALTY.")]
        let longArtistCards = [card("artist", "UC2", "Kendrick Lamar with a deliberately long artist display name that wraps cleanly")]
            + Array(relatedCards.dropFirst())
        let fixtures: [(String, SearchSectionRecord)] = [
            ("S01", section([card("song", "duckworth", "DUCKWORTH.")], [song("duckworth", setVideoId: "opaque-song-context")], primary: 0)),
            ("A01", section(relatedCards, [song("v1", setVideoId: "related-one", title: "DUCKWORTH."),
                song("v2", setVideoId: "related-two", title: "HUMBLE."),
                song("v3", setVideoId: "related-three", title: "DNA."), song("v4", setVideoId: "related-four", title: "ELEMENT."),
                song("v5", setVideoId: "related-five", title: "LOYALTY.")], primary: 0, related: [1, 2, 3, 4, 5])),
            ("A01-long", section(longArtistCards, [song("v1", setVideoId: "long-related-one", title: "DUCKWORTH."),
                song("v2", setVideoId: "long-related-two", title: "HUMBLE."),
                song("v3", setVideoId: "long-related-three", title: "DNA."), song("v4", setVideoId: "long-related-four", title: "ELEMENT."),
                song("v5", setVideoId: "long-related-five", title: "LOYALTY.")], primary: 0, related: [1, 2, 3, 4, 5])),
            ("B01", section([card("album", "album", "To Pimp A Butterfly")], primary: 0))
        ]
        let previousLanguage = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previousLanguage) }
        for (languageName, language) in [("es", AppLanguage.es), ("en", AppLanguage.en)] {
            AppLanguageStore.shared.setLanguage(language)
            for (name, fixture) in fixtures {
                let roles = try #require(ProviderSearchProjection.roles(for: fixture))
                let songsByIndex = ProviderSearchProjection.songsByItemIndex(in: fixture)
                let expandedStates = name == "A01" ? [false, true] : [false]
                var collapsedHeightByWidth: [CGFloat: CGFloat] = [:]
                for width in [618.0, 1098.0] {
                    for isExpanded in expandedStates {
                        let root = ProviderSearchPrincipalView(section: fixture, roles: roles, width: width,
                            isExpanded: isExpanded,
                            actions: [], onAction: { _ in },
                            row: { index in
                                if let song = songsByIndex[index] {
                                    AnyView(QuickResultSongRow(song: song, onSelect: {}).frame(minHeight: 58)
                                        .accessibilityIdentifier("related-\(index)"))
                                } else {
                                    AnyView(Text(fixture.items[index].title).lineLimit(nil).frame(minHeight: 58)
                                        .accessibilityIdentifier("related-\(index)"))
                                }
                            },
                            onToggleRelated: {}, onPlay: { _ in }, onOpen: {}, menuProvider: { nil },
                            primarySongPayload: songsByIndex[roles.primaryIndex])
                            .background(Color(red: 0.10, green: 0.10, blue: 0.12))
                            .environment(\.colorScheme, .dark)
                        let host = NSHostingView(rootView: root.frame(width: width, alignment: .leading))
                        let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: width, height: 900),
                            styleMask: .borderless, backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false
                        window.appearance = NSAppearance(named: .darkAqua)
                        window.contentView = host
                        window.orderFrontRegardless()
                        defer { window.contentView = nil; window.close() }
                        host.layoutSubtreeIfNeeded()
                        host.displayIfNeeded()
                        for _ in 0..<4 {
                            try await Task.sleep(for: .milliseconds(20))
                            host.layoutSubtreeIfNeeded()
                            host.displayIfNeeded()
                        }
                        #expect(host.fittingSize.width <= width + 1)
                        #expect(host.fittingSize.height >= 100)
                        #expect(host.fittingSize.height < 700)
                        if name == "S01" { #expect((108...116).contains(host.fittingSize.height)) }
                        if name == "A01", !isExpanded {
                            collapsedHeightByWidth[width] = host.fittingSize.height
                            // The wide split should be governed by three compact related rows,
                            // while the compact card remains bounded with its stacked contents.
                            if width >= 960 { #expect(host.fittingSize.height < 280) }
                            else { #expect(host.fittingSize.height < 460) }
                        } else if name == "A01", isExpanded,
                                  let collapsedHeight = collapsedHeightByWidth[width] {
                            #expect(host.fittingSize.height - collapsedHeight >= 116)
                        }
                        if name == "A01-long" {
                            if width >= 960 { #expect(host.fittingSize.height < 360) }
                            else { #expect(host.fittingSize.height < 500) }
                        }
                        host.setFrameSize(NSSize(width: width, height: host.fittingSize.height))
                        host.layoutSubtreeIfNeeded()
                        host.displayIfNeeded()
                        if name == "A01" && isExpanded {
                            #expect(roles.relatedIndices.count == 5)
                            #expect(Array(roles.relatedIndices.prefix(3)) == [1, 2, 3])
                        }
                        if let directoryPath = ProcessInfo.processInfo.environment["SIDEB_SEARCH_DESIGN_CAPTURE_DIR"] {
                            let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
                            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                            host.cacheDisplay(in: host.bounds, to: bitmap)
                            let png = try #require(bitmap.representation(using: .png, properties: [:]))
                            let suffix = isExpanded ? "-expanded" : ""
                            try png.write(to: directory.appendingPathComponent("\(name)-\(languageName)\(suffix)-C\(Int(width)).png"))
                        }
                        window.orderOut(nil)
                    }
                }
            }
        }
    }
}
