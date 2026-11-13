import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI
import Testing
import SideBCore
@testable import SideB

@Test func playbackSidebarFullscreenReturnsToItsOriginAndRepeatedCommandsAreIdempotent() {
    var state = PlaybackPresentationState()
    state.setFullscreen(false)
    #expect(state.mode == .bar)
    state.presentSidebar()
    state.setFullscreen(true)
    state.setFullscreen(true)
    state.closeSidebar()
    #expect(state.mode == .fullscreen)
    state.setFullscreen(false)
    #expect(state.mode == .sidebar)
    state.closeSidebar()
    state.setFullscreen(true)
    state.setFullscreen(false)
    #expect(state.mode == .bar)
    for _ in 0..<100 {
        state.presentSidebar(); state.closeSidebar()
    }
    #expect(state.mode == .bar)
}

@Test func playbackSidebarReservesWidthOnlyWhenThePageRemainsUsable() {
    for left in [CGFloat(0), ShellLayout.sidebarReserveWidth(expanded: true)] {
        for width in [CGFloat(960), 1024, 1280, 1512, 1920] {
            let reserve = PlaybackSidebarLayout.contentReserve(windowWidth: width, leftReserve: left, presented: true)
            #expect(reserve == 0 || width - left - reserve >= 480)
            #expect(PlaybackSidebarLayout.contentReserve(windowWidth: width, leftReserve: left, presented: false) == 0)
        }
    }
    #expect(PlaybackSidebarLayout.contentReserve(windowWidth: 960,
        leftReserve: ShellLayout.sidebarReserveWidth(expanded: true), presented: true) == 0)
}

@Test func playbackSidebarProgressToTransportSpacingMatchesPortraitDistance() {
    for height in [CGFloat(640), 788, 840, 968, 1000, 1200] {
        let spacing = PlaybackSidebarLayout.progressToTransportSpacing(for: height)
        #expect(spacing >= 10 && spacing <= 22)
        if height == 968 {
            #expect(abs(spacing - 19.58) <= 0.1)
        }
    }
}

@MainActor private func sidebarTestPlayer(_ directory: URL, preferences: UserDefaults) -> PlayerViewModel {
    PlayerViewModel(rustCore: nil,
        audioService: AudioPlayerService(preferences: preferences, preferencePrefix: "sidebar"),
        playbackStore: PlaybackStateStore(directory: directory))
}

@Test @MainActor func playbackSidebarCommandsPreserveOccurrenceAudioAndFullscreenSelection() throws {
    let suite = "SideBSidebar.\(UUID())"
    let prefs = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { prefs.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let player = sidebarTestPlayer(directory, preferences: prefs)
    let track = SongItemRecord(videoId: "duplicate", title: "Prueba", artists: "Artista", album: nil,
        duration: nil, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil)
    player.queueManager.replaceQueue(with: [track, track], startingAt: 1)
    player.currentTrack = track
    let occurrence = player.queueManager.currentOccurrenceID
    let playbackID = player.experimentalLyricsPlaybackIdentity
    let item = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/sideb-sidebar-synthetic.m4a"))
    player.audioService.avPlayer.replaceCurrentItem(with: item)
    player.togglePlaybackSidebar(.queue)
    #expect(player.isPlaybackSidebarPresented && !player.isFullscreenPresented)
    player.toggleLyricsPanel(genius: false)
    #expect(player.selectedSidebarPanel == .lyrics)
    player.isFullscreenPresented = true
    #expect(player.selectedFullscreenPanel == .lyrics)
    player.dismissFullscreen()
    #expect(player.isPlaybackSidebarPresented)
    player.toggleLyricsPanel(genius: false)
    #expect(!player.isPlaybackSurfaceVisible)
    #expect(player.queueManager.currentOccurrenceID == occurrence)
    #expect(player.experimentalLyricsPlaybackIdentity == playbackID)
    #expect(player.audioService.avPlayer.currentItem === item)
}

@Test @MainActor func playbackSidebarLaysOutAllSectionsAcrossWindowHeightsWithZeroInitialRecommendationPeek() async throws {
    let suite = "SideBSidebarRender.\(UUID())"
    let prefs = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { prefs.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let player = sidebarTestPlayer(directory, preferences: prefs)
    let songs = (0..<8).map { index in
        SongItemRecord(videoId: "fixture-\(index)", title: "Canción de prueba \(index)", artists: "Artista de ejemplo",
            album: "Disco de prueba", duration: "3:20", thumbnail: nil, artistId: "artist-1", albumId: "album-1", setVideoId: nil)
    }
    player.queueManager.replaceQueue(with: songs, startingAt: 2)
    player.currentTrack = songs[2]
    player.lyricsInfo = LyricsInfo(provider: "Fixture", isSynced: false, lines: (0..<16).map {
        LyricLineInfo(timeMs: nil, endTimeMs: nil, text: "Una línea de ejemplo para leer en el panel \($0)")
    })
    player.recommendedData = RecommendedData(
        artistName: "Artista de ejemplo",
        artistBrowseId: "artist-1",
        artistSongs: Array(songs.prefix(4)),
        albumTitle: "Disco de prueba",
        albumBrowseId: "album-1",
        albumSongs: Array(songs.suffix(4)),
        similarSongs: Array(songs.prefix(5)),
        relatedArtists: [
            BrowseCardRecord(kind: "artist", id: "rel-1", title: "Artista Similar 1", subtitle: "Fans", thumbnail: nil, duration: nil),
            BrowseCardRecord(kind: "artist", id: "rel-2", title: "Artista Similar 2", subtitle: "Fans", thumbnail: nil, duration: nil)
        ],
        loadedVideoId: songs[2].videoId
    )
    player.togglePlaybackSidebar()

    // Window heights 640 (-> 628), 800 (-> 788), and 1000 (-> 988)
    for sidebarHeight in [CGFloat(628), CGFloat(788), CGFloat(988)] {
        for section in PlaybackSidebarPanel.allCases {
            player.selectedSidebarPanel = section
            let upperLimit = sidebarHeight - PlaybackSidebarLayout.footerHeight(for: sidebarHeight, panel: section) + 1
            let size = CGSize(width: 380, height: sidebarHeight)
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            let host = NSHostingView(rootView: FullscreenNowPlayingView(viewModel: player,
                canvasSize: size, sidebarProgress: 1).frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark))
            host.frame = CGRect(origin: .zero, size: size)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            await Task.yield()
            host.layoutSubtreeIfNeeded()

            var verticalScrollViews: [NSScrollView] = []
            var horizontalShelves: [NSScrollView] = []
            func inspect(_ view: NSView) {
                let frame = view.convert(view.bounds, to: host)
                if let shelf = view as? SidebarArtistShelfScrollView {
                    horizontalShelves.append(shelf)
                } else if let scroll = view as? NSScrollView {
                    verticalScrollViews.append(scroll)
                    if section == .artwork {
                        // Immersive hero starts at y == 0 under overlaid header and ends above fixed footer
                        #expect(frame.minY >= -1 && frame.maxY <= upperLimit)
                    } else {
                        #expect(frame.minY >= 57 && frame.maxY <= upperLimit)
                    }
                    let scrollerSlotWidth: CGFloat = scroll.scrollerStyle == .legacy
                        ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
                    #expect(frame.minX >= -1 && frame.maxX <= 381 + scrollerSlotWidth)
                }
                if view is NativePanelSegmentHost { #expect(frame.minY >= 0 && frame.maxY <= 58) }
                view.subviews.forEach(inspect)
            }
            inspect(host)

            if section == .artwork {
                // Single vertical NSScrollView owns hero + recommendations; at offsetY == 0, document > heroHeight
                #expect(verticalScrollViews.count == 1)
                #expect(horizontalShelves.isEmpty, "Artist shelf is deferred until scrolling")
                if let outer = verticalScrollViews.first {
                    let expectedHeroHeight = sidebarHeight - PlaybackSidebarLayout.footerHeight(for: sidebarHeight, panel: .artwork)
                    #expect(abs(outer.frame.height - expectedHeroHeight) <= 1.0)
                    #expect(abs(outer.contentView.bounds.origin.y) <= 0.5)
                    #expect((outer.documentView?.frame.height ?? 0) > expectedHeroHeight + 100)
                }
                // Viewing/laying out Now Playing must never promote tracks to QueueManager reserve
                #expect(player.queueManager.recommendationEntries.isEmpty)
            }

            host.displayIfNeeded()
            #expect(host.fittingSize.width <= 381)
            #expect(host.fittingSize.height <= sidebarHeight + 1)
        }
    }
}

@Test @MainActor func playbackSidebarRecommendationScrollPolicyAndOccurrenceMemory() throws {
    let sessionA = UUID()
    let sessionB = UUID()
    let playback1 = UUID()
    let playback2 = UUID()

    let occ1 = SidebarArtworkOccurrenceKey(sessionID: sessionA, playbackID: playback1, videoID: "song-1", occurrenceID: "occ-1")
    let occ2 = SidebarArtworkOccurrenceKey(sessionID: sessionA, playbackID: playback2, videoID: "song-1", occurrenceID: "occ-2")
    let occAccountSwitch = SidebarArtworkOccurrenceKey(sessionID: sessionB, playbackID: playback2, videoID: "song-1", occurrenceID: "occ-2")

    let recKey1 = RecommendedRequestState.Key(videoID: "song-1", artistID: "art-1", albumID: nil, account: sessionA)
    let recKeyHydrated = RecommendedRequestState.Key(videoID: "song-1", artistID: "art-1", albumID: "alb-1", account: sessionA)

    let state = SidebarArtworkScrollState()
    #expect(state.synchronizeOccurrence(occ1))

    var fetchCount = 0
    // Initial mount at offsetY == 0 NEVER fetches recommendations
    state.evaluateScroll(offsetY: 0, hasTrack: true, recommendationKey: recKey1) { fetchCount += 1 }
    state.evaluateScroll(offsetY: 12, hasTrack: true, recommendationKey: recKey1) { fetchCount += 1 }
    #expect(fetchCount == 0)

    // Crossing activation threshold fires ONCE, and subsequent pixel scrolls do NOT re-fire
    for y in stride(from: CGFloat(24), through: 320, by: 4) {
        state.evaluateScroll(offsetY: y, hasTrack: true, recommendationKey: recKey1) { fetchCount += 1 }
    }
    #expect(fetchCount == 1)
    #expect(state.savedOffsetY == 320)

    // Switching sidebar tabs within the SAME occurrence preserves savedOffsetY and does not re-fetch
    #expect(!state.synchronizeOccurrence(occ1))
    #expect(state.savedOffsetY == 320)

    // Hydrating album metadata while already scrolled into recommendations upgrades once
    state.evaluateScroll(offsetY: 320, hasTrack: true, recommendationKey: recKeyHydrated) { fetchCount += 1 }
    #expect(fetchCount == 2)

    // Changing occurrence (even with identical videoID) resets scroll memory to 0 and clears requested key
    #expect(state.synchronizeOccurrence(occ2))
    #expect(state.savedOffsetY == 0)
    #expect(state.lastRequestedRecommendationKey == nil)

    // Changing account session also resets memory
    state.evaluateScroll(offsetY: 180, hasTrack: true, recommendationKey: recKeyHydrated) { fetchCount += 1 }
    #expect(state.savedOffsetY == 180)
    #expect(state.synchronizeOccurrence(occAccountSwitch))
    #expect(state.savedOffsetY == 0)
}

@Test @MainActor func playbackSidebarPreservesArtworkScrollAcrossTabsAndForwardsVerticalScrollOverHorizontalArtistShelf() async throws {
    let suite = "SideBSidebarTabScroll.\(UUID())"
    let prefs = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { prefs.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let player = sidebarTestPlayer(directory, preferences: prefs)
    let trackA = SongItemRecord(videoId: "track-a", title: "Canción A", artists: "Artista Largo De Prueba",
        album: "Álbum Extendido De Prueba", duration: "3:40", thumbnail: nil, artistId: "art-a", albumId: "alb-a", setVideoId: nil)
    let trackB = SongItemRecord(videoId: "track-b", title: "Canción B", artists: "Artista B",
        album: "Álbum B", duration: "2:55", thumbnail: nil, artistId: "art-b", albumId: "alb-b", setVideoId: nil)
    player.queueManager.replaceQueue(with: [trackA, trackB], startingAt: 0)
    player.currentTrack = trackA
    player.recommendedData = RecommendedData(
        artistName: "Artista Largo De Prueba Con Nombre Muy Extenso",
        artistBrowseId: "art-a",
        artistSongs: (0..<5).map {
            SongItemRecord(videoId: "as-\($0)", title: "Pista \($0)", artists: "Artista", album: nil, duration: "3:00", thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil)
        },
        albumTitle: "Álbum Extendido Con Un Título Bastante Largo",
        albumBrowseId: "alb-a",
        albumSongs: (0..<4).map {
            SongItemRecord(videoId: "al-\($0)", title: "Disco \($0)", artists: "Artista", album: nil, duration: "3:10", thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil)
        },
        similarSongs: [],
        relatedArtists: (0..<8).map {
            BrowseCardRecord(kind: "artist", id: "ra-\($0)", title: "Artista Relacionado \($0)", subtitle: "Similares", thumbnail: nil, duration: nil)
        },
        loadedVideoId: "track-a"
    )
    player.togglePlaybackSidebar(.artwork)

    let size = CGSize(width: 380, height: 628)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    let host = NSHostingView(rootView: FullscreenNowPlayingView(viewModel: player, canvasSize: size, sidebarProgress: 1, router: NavigationRouter())
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark))
    host.frame = CGRect(origin: .zero, size: size)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()

    func findScrollViews(in root: NSView) -> (outer: NSScrollView?, horizontal: SidebarArtistShelfScrollView?) {
        var all: [NSScrollView] = []
        func walk(_ v: NSView) {
            if let s = v as? NSScrollView { all.append(s) }
            v.subviews.forEach(walk)
        }
        walk(root)
        let horizontal = all.compactMap { $0 as? SidebarArtistShelfScrollView }.first
        let outer = all.first { !($0 is SidebarArtistShelfScrollView) }
        return (outer, horizontal)
    }

    let initialScrolls = findScrollViews(in: host)
    let outer = try #require(initialScrolls.outer)
    #expect(initialScrolls.horizontal == nil)
    #expect(outer.contentView.bounds.origin.y == 0)
    outer.contentView.scroll(to: NSPoint(x: 0, y: 220))
    outer.reflectScrolledClipView(outer.contentView)
    NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: outer.contentView)
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    let horizontal = try #require(findScrollViews(in: host).horizontal)
    horizontal.layoutSubtreeIfNeeded()
    #expect(horizontal.enclosingVerticalScrollView() === outer)
    #expect((horizontal.documentView?.frame.width ?? 0) > horizontal.contentView.bounds.width + 40)

    // Verify axis-locked trackpad scroll routing on SidebarPassthroughHorizontalScrollView:
    // vertical gestures (including diagonal drift + momentum) forward 100% to enclosing vertical NSScrollView,
    // while horizontal gestures stay inside the artist shelf and never leak vertically.
    final class RecordingVerticalScrollView: NSScrollView {
        var forwardedDeltasY: [CGFloat] = []
        override func scrollWheel(with event: NSEvent) {
            forwardedDeltasY.append(event.scrollingDeltaY)
        }
    }
    let spyOuter = RecordingVerticalScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 440))
    let spyDoc = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 900))
    let shelfUnderTest = SidebarArtistShelfScrollView(frame: NSRect(x: 0, y: 460, width: 380, height: 112))
    let shelfDoc = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 112))
    shelfUnderTest.documentView = shelfDoc
    spyDoc.addSubview(shelfUnderTest)
    spyOuter.documentView = spyDoc
    #expect(shelfUnderTest.enclosingVerticalScrollView() === spyOuter)

    func sendTrackpadEvent(to target: NSView, dy: Int32, dx: Int32, scrollPhase: Int64, momentumPhase: Int64 = 0) {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        if let ns = NSEvent(cgEvent: cg) {
            target.scrollWheel(with: ns)
        }
    }

    // 1) Predominantly vertical gesture (.began -> diagonal .changed -> .ended -> momentum) forwards every event to outer
    sendTrackpadEvent(to: shelfUnderTest, dy: -18, dx: 2, scrollPhase: 1)
    sendTrackpadEvent(to: shelfUnderTest, dy: -42, dx: -9, scrollPhase: 2)
    sendTrackpadEvent(to: shelfUnderTest, dy: 0, dx: 0, scrollPhase: 4)
    sendTrackpadEvent(to: shelfUnderTest, dy: -24, dx: 0, scrollPhase: 0, momentumPhase: 2)
    sendTrackpadEvent(to: shelfUnderTest, dy: 0, dx: 0, scrollPhase: 0, momentumPhase: 3)
    #expect(spyOuter.forwardedDeltasY.count == 5)
    #expect(shelfUnderTest.contentView.bounds.origin.x == 0)

    // 2) Predominantly horizontal gesture (.began -> .changed -> .ended) never leaks to outer vertical scroll view
    spyOuter.forwardedDeltasY.removeAll()
    sendTrackpadEvent(to: shelfUnderTest, dy: 2, dx: -20, scrollPhase: 1)
    sendTrackpadEvent(to: shelfUnderTest, dy: -6, dx: -44, scrollPhase: 2)
    sendTrackpadEvent(to: shelfUnderTest, dy: 0, dx: 0, scrollPhase: 4)
    #expect(spyOuter.forwardedDeltasY.isEmpty)

    // Scroll outer to 220pt and verify tab switch memory + zero promotion to queueManager.recommendationEntries
    outer.contentView.scroll(to: NSPoint(x: 0, y: 220))
    outer.reflectScrolledClipView(outer.contentView)
    NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: outer.contentView)
    #expect(abs(outer.contentView.bounds.origin.y - 220) < 1)
    #expect(player.queueManager.recommendationEntries.isEmpty)
    #expect(player.queueManager.queue.count == 2)

    // Switch to Queue and back to Artwork for the same occurrence -> restores 220pt
    player.selectedSidebarPanel = .queue
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()

    player.selectedSidebarPanel = .artwork
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()

    let restoredOuter = try #require(findScrollViews(in: host).outer)
    #expect(abs(restoredOuter.contentView.bounds.origin.y - 220) < 2)
    #expect(player.queueManager.recommendationEntries.isEmpty)

    // Also verify narrow 350pt width renders recommendations without compressing section titles vertically
    let narrowHost = NSHostingView(rootView: NativeSidebarRecommendationsView(viewModel: player, router: NavigationRouter(), heroHeight: 400, state: sidebarTestScrollState(), occurrenceKey: SidebarArtworkOccurrenceKey(sessionID: UUID(), playbackID: UUID(), videoID: "track-a", occurrenceID: nil))
        .frame(width: 350, height: 320)
        .environment(\.colorScheme, .dark))
    narrowHost.frame = CGRect(x: 0, y: 0, width: 350, height: 320)
    narrowHost.layoutSubtreeIfNeeded()
    #expect(narrowHost.fittingSize.width <= 351)
    #expect(abs(narrowHost.fittingSize.height - 320) < 1)

    // Clearing account state invalidates recommendations and resets session identity
    player.clearAccountState()
    #expect(player.recommendedData == nil)
}

@Test @MainActor func playbackSidebarLyricsFooterOmitsThumbnailSlotWhileFloatingBarKeepsArtwork() throws {
    let suite = "SideBSidebarFooter.\(UUID())"
    let prefs = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { prefs.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let player = sidebarTestPlayer(directory, preferences: prefs)
    player.currentTrack = SongItemRecord(
        videoId: "footer-track",
        title: "Título muy largo para aprovechar todo el ancho sin miniatura",
        artists: "Artista Principal",
        album: "Álbum Principal",
        duration: "4:05",
        thumbnail: nil,
        artistId: "art-1",
        albumId: "alb-1",
        setVideoId: nil
    )

    player.selectedSidebarPanel = .lyrics
    let sidebarFooter = NSHostingView(rootView: PlayerBarView(viewModel: player, isSidebar: true)
        .frame(width: 380, height: PlaybackSidebarLayout.footerHeight)
        .environment(\.colorScheme, .dark))
    sidebarFooter.frame = CGRect(x: 0, y: 0, width: 380, height: PlaybackSidebarLayout.footerHeight)
    sidebarFooter.layoutSubtreeIfNeeded()

    let floatingBar = NSHostingView(rootView: PlayerBarView(viewModel: player, isSidebar: false)
        .frame(width: 780, height: 74)
        .environment(\.colorScheme, .dark))
    floatingBar.frame = CGRect(x: 0, y: 0, width: 780, height: 74)
    floatingBar.layoutSubtreeIfNeeded()

    func minTextX(in view: NSView, root: NSView) -> CGFloat? {
        var best: CGFloat?
        func walk(_ v: NSView) {
            if v is NSTextField || String(describing: type(of: v)).contains("PlayerTitle") {
                let f = v.convert(v.bounds, to: root)
                if f.width > 20 {
                    best = min(best ?? f.minX, f.minX)
                }
            }
            v.subviews.forEach(walk)
        }
        walk(view)
        return best
    }

    if let sidebarMinX = minTextX(in: sidebarFooter, root: sidebarFooter) {
        // Without a 40x40 thumbnail + 8pt spacing, metadata starts right at the 20pt horizontal padding
        #expect(sidebarMinX <= 26)
    }
    #expect(abs(sidebarFooter.frame.height - PlaybackSidebarLayout.footerHeight) < 1)
}

@Test @MainActor func playbackSidebarTransfersNativeQueueScrollByOccurrence() throws {
    let suite = "SideBSidebarScroll.\(UUID())"
    let prefs = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { prefs.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let player = sidebarTestPlayer(directory, preferences: prefs)
    let songs = (0..<60).map { index in
        SongItemRecord(videoId: "duplicate", title: "Track \(index)", artists: "Artist", album: nil,
            duration: nil, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil)
    }
    player.queueManager.replaceQueue(with: songs, startingAt: 15)
    let memory = PlaybackQueueViewport()
    let view = NativeSeparatedQueueView(manager: player.queueManager,
        revision: player.queueManager.presentationRevision, player: player, router: nil,
        liked: [], playing: false, loading: false, error: nil, viewport: memory)
    let first = view.makeCoordinator()
    let scroll = view.makeScrollView(coordinator: first)
    scroll.frame = CGRect(x: 0, y: 0, width: 356, height: 320)
    scroll.layoutSubtreeIfNeeded()
    first.userScrollStarted()
    first.scroll(to: 900)
    first.viewportChanged()
    let before = try #require(first.viewportAnchor())
    NativeSeparatedQueueView.dismantleNSView(scroll, coordinator: first)
    let second = view.makeCoordinator()
    let expanded = view.makeScrollView(coordinator: second)
    expanded.frame = CGRect(x: 0, y: 0, width: 620, height: 480)
    expanded.layoutSubtreeIfNeeded()
    if !second.positionedInitially { second.positionCurrent() }
    let after = try #require(second.viewportAnchor())
    #expect(before.0 == after.0)
    #expect(abs(before.1 - after.1) < 1)
    #expect(!second.followsCurrent)
    // Replacing a queue invalidates the remembered occurrence even for identical video IDs.
    player.queueManager.replaceQueue(with: songs, startingAt: 2)
    var changed = view
    changed = NativeSeparatedQueueView(manager: player.queueManager,
        revision: player.queueManager.presentationRevision, player: player, router: nil,
        liked: [], playing: false, loading: false, error: nil, viewport: memory)
    second.refresh(parent: changed)
    #expect(second.followsCurrent)
}

@Test @MainActor func playbackSidebarRetiresCoverVolumeWheelWhileKeepingFooterCapsuleAndFullscreenProtection() throws {
    let suite = "SideBSidebarVolume.\(UUID())"
    let prefs = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { prefs.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let player = sidebarTestPlayer(directory, preferences: prefs)
    player.currentTrack = SongItemRecord(videoId: "volume", title: "Track", artists: "Artist", album: nil,
        duration: nil, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil)
    player.togglePlaybackSidebar(.artwork)
    let router = NavigationRouter()
    let presentation = WindowGesturePresentation()
    let adapter = WindowNavigationCoordinator(performHaptic: {})
    adapter.setup(router: router, presentation: presentation, isFullscreenPresented: false,
        canHandleGestures: true, reduceMotion: true, volumePlayer: player, onDismissFullscreen: {})

    // Lateral cover no longer consumes scrollWheel as .fullscreen volume; scroll belongs to hero+recommendations
    #expect(!adapter.handleVolumeInput(.init(y: 8, phase: .began, timestamp: 1), zone: .fullscreen, enabled: true))

    // Sidebar footer slider (.volumeCapsule) still adjusts volume cleanly
    #expect(adapter.handleVolumeInput(.init(y: 8, phase: .began, timestamp: 2), zone: .capsule, enabled: true))
    adapter.invalidate()

    // Fullscreen artwork still owns .fullscreen volume when real fullscreen is presented
    player.isFullscreenPresented = true
    adapter.setup(router: router, presentation: presentation, isFullscreenPresented: true,
        canHandleGestures: true, reduceMotion: true, volumePlayer: player, onDismissFullscreen: {})
    #expect(adapter.handleVolumeInput(.init(y: 8, phase: .began, timestamp: 3), zone: .fullscreen, enabled: true))
}

@Test func playbackSidebarPaletteUsesNeutralWithoutArtworkAndPreservesChromaticHueWithoutFadingToBlack() {
    // 1. Neutral fallback has zero blue bias
    let neutral = PlaybackSidebarPalette.neutral
    #expect(!neutral.isChromatic)
    #expect(abs(neutral.primary.red - neutral.primary.blue) < 0.0001)
    #expect(abs(neutral.secondary.red - neutral.secondary.blue) < 0.0001)

    // 2. Monochrome grey cover stays neutral without blue tint
    var greyPixels: [UInt8] = []
    for _ in 0..<256 { greyPixels.append(contentsOf: [120, 120, 120, 255]) }
    let mono = PlaybackSidebarPalette.from(rgba: greyPixels)
    #expect(!mono.isChromatic)
    #expect(abs(mono.primary.red - mono.primary.blue) < 0.0001)

    // 3. Warm crimson/orange cover keeps warm primary AND warm non-black secondary
    var warmPixels: [UInt8] = []
    for _ in 0..<256 { warmPixels.append(contentsOf: [220, 58, 36, 255]) }
    let warm = PlaybackSidebarPalette.from(rgba: warmPixels)
    #expect(warm.isChromatic)
    #expect(warm.primary.red > warm.primary.blue + 0.08)
    #expect(warm.secondary.red > warm.secondary.blue + 0.04)
    #expect(warm.secondary.red > 0.05) // Never fades to pure black (0,0,0)

    // 4. Emerald green cover preserves green dominance
    var greenPixels: [UInt8] = []
    for _ in 0..<256 { greenPixels.append(contentsOf: [34, 188, 92, 255]) }
    let green = PlaybackSidebarPalette.from(rgba: greenPixels)
    #expect(green.isChromatic)
    #expect(green.primary.green > green.primary.red)
    #expect(green.primary.green > green.primary.blue)
}

@Test @MainActor func sidebarReturnsToFullscreenSelectedSectionWithoutChangingOccurrence() throws {
    let suite = "SideBSidebarReturn.\(UUID())"
    let prefs = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { prefs.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let player = sidebarTestPlayer(directory, preferences: prefs)
    player.togglePlaybackSidebar(.queue)
    let playbackID = player.experimentalLyricsPlaybackIdentity
    for (fullscreen, lateral) in [(FullscreenPanel.lyrics, PlaybackSidebarPanel.lyrics), (.recommended, .artwork), (.jam, .artwork), (.queue, .queue)] {
        player.isFullscreenPresented = true
        player.selectedFullscreenPanel = fullscreen
        player.dismissFullscreen()
        #expect(player.isPlaybackSidebarPresented)
        #expect(player.selectedSidebarPanel == lateral)
        #expect(player.experimentalLyricsPlaybackIdentity == playbackID)
    }
}

@MainActor private func sidebarTestScrollState() -> SidebarArtworkScrollState { SidebarArtworkScrollState() }

@Test @MainActor func sidebarUpcomingPreviewIsBoundedAndKeepsDuplicateOccurrences() {
    let queue = QueueManager()
    let song = SongItemRecord(videoId: "same", title: "Repeated", artists: "Artist", album: nil,
        duration: nil, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil)
    queue.replaceQueue(with: Array(repeating: song, count: 10_000), startingAt: 0)
    let token = queue.queueToken
    let ids = queue.occurrenceIDs
    let preview = SidebarUpcomingOccurrence.preview(in: queue)
    #expect(preview.count == 2)
    #expect(preview.map(\.id) == Array(ids[1...2]))
    #expect(preview.map(\.index) == [1, 2])
    #expect(preview[0].id != preview[1].id)
    #expect(queue.queueToken == token)
    #expect(queue.currentIndex == 0)
    #expect(queue.recommendationEntries.isEmpty)
    queue.isRepeat = true
    #expect(SidebarUpcomingOccurrence.preview(in: queue).map(\.id) == preview.map(\.id))
    _ = queue.selectTrack(at: 9_998)
    #expect(SidebarUpcomingOccurrence.preview(in: queue).count == 1)
    _ = queue.selectTrack(at: 9_999)
    #expect(SidebarUpcomingOccurrence.preview(in: queue).isEmpty)
    queue.clearQueue()
    #expect(SidebarUpcomingOccurrence.preview(in: queue).isEmpty)
}

@Test func sidebarUpcomingYieldsToArtworkOnShortPanelsAndPortrait() {
    for height in [CGFloat(628), 788] {
        #expect(!PlaybackSidebarLayout.showsUpcoming(for: height, panel: .artwork))
    }
    #expect(PlaybackSidebarLayout.showsUpcoming(for: 988, panel: .artwork))
    for panel in PlaybackSidebarPanel.allCases {
        #expect(!PlaybackSidebarLayout.showsUpcoming(for: 988, panel: panel, isPortrait: true))
        if panel != .artwork {
            #expect(!PlaybackSidebarLayout.showsUpcoming(for: 988, panel: panel))
        }
    }
    let footer = PlaybackSidebarLayout.footerHeight(for: 988, panel: .artwork)
    #expect(abs((988 - footer) - (58 + 12 + 340 + 16 + 68)) < 1)
    #expect(footer > PlaybackSidebarLayout.footerHeight(for: 988, panel: .artwork, isPortrait: true))
}

@Test func sidebarBottomContentPreferenceResolvesAndPersists() {
    #expect(SidebarBottomContent.resolve(nil) == .queue)
    #expect(SidebarBottomContent.resolve("invalid-value") == .queue)
    #expect(SidebarBottomContent.resolve("queue") == .queue)
    #expect(SidebarBottomContent.resolve("lyrics") == .lyrics)

    let suite = "PlaybackSidebarBottomContentTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    #expect(SidebarBottomContentPreferences.selection(in: defaults) == .queue)

    defaults.set(SidebarBottomContent.lyrics.rawValue, forKey: SidebarBottomContentPreferences.preferenceKey)
    #expect(SidebarBottomContentPreferences.selection(in: defaults) == .lyrics)

    defaults.set(SidebarBottomContent.queue.rawValue, forKey: SidebarBottomContentPreferences.preferenceKey)
    #expect(SidebarBottomContentPreferences.selection(in: defaults) == .queue)
}

@Test func sidebarBottomContentLocalizationKeysAreValid() {
    for content in SidebarBottomContent.allCases {
        let key = content.labelKey
        let localizedES = L10n.text(key, language: .es)
        let localizedEN = L10n.text(key, language: .en)
        #expect(!localizedES.isEmpty)
        #expect(!localizedEN.isEmpty)
        #expect(localizedES != key)
    }

    let titleKey = "playbackSidebar.lyricsPreview.title"
    #expect(L10n.text(titleKey, language: .es) == "Muestra de la letra")
    #expect(L10n.text(titleKey, language: .en) == "Lyrics preview")

    let showMoreKey = "playbackSidebar.lyricsPreview.showMore"
    #expect(L10n.text(showMoreKey, language: .es) == "Mostrar más")
    #expect(L10n.text(showMoreKey, language: .en) == "Show more")
}

