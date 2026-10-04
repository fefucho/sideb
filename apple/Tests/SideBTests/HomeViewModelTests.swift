import Testing
import Foundation
import AppKit
import SideBCore
@testable import SideB

private actor HomeFeedStub {
    private var requests: [(String?, CheckedContinuation<(String, String?), Error>)] = []
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var continuationRequests: [(String, CheckedContinuation<(String, String?), Error>)] = []
    private var continuationCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func request(chip: String?) async throws -> (String, String?) {
        try await withCheckedThrowingContinuation { continuation in
            requests.append((chip, continuation))
            let ready = countWaiters.filter { requests.count >= $0.0 }
            countWaiters.removeAll { requests.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForCount(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((count, continuation))
        }
    }

    func succeed(_ index: Int, title: String, continuation: String? = nil) {
        requests[index].1.resume(returning: (title, continuation))
    }

    func fail(_ index: Int) {
        requests[index].1.resume(throwing: StubError.failed)
    }

    func requestContinuation(token: String) async throws -> (String, String?) {
        try await withCheckedThrowingContinuation { continuation in
            continuationRequests.append((token, continuation))
            let ready = continuationCountWaiters.filter { continuationRequests.count >= $0.0 }
            continuationCountWaiters.removeAll { continuationRequests.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForContinuationCount(_ count: Int) async {
        if continuationRequests.count >= count { return }
        await withCheckedContinuation { continuation in
            continuationCountWaiters.append((count, continuation))
        }
    }

    func succeedContinuation(_ index: Int, title: String, continuation: String?) {
        continuationRequests[index].1.resume(returning: (title, continuation))
    }

    func failContinuation(_ index: Int) {
        continuationRequests[index].1.resume(throwing: StubError.failed)
    }

    func requestedContinuationTokens() -> [String] {
        continuationRequests.map { $0.0 }
    }
}

private enum StubError: Error { case failed }

private final class HomeCoreStub: SideBCore, @unchecked Sendable {
    let feed = HomeFeedStub()

    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        super.init(unsafeFromRawPointer: pointer)
    }

    init() {
        super.init(noPointer: .init())
    }

    override func isLoggedIn() -> Bool { true }

    override func getHomePage(chipParams: String?) async throws -> HomePageRecord {
        let (title, continuation) = try await feed.request(chip: chipParams)
        return HomePageRecord(
            chips: [],
            sections: [HomeSectionRecord(
                title: title,
                format: .largeCards,
                items: [HomeItemRecord(kind: "song", id: title, title: title, subtitle: nil, thumbnail: nil,
                                       duration: nil, artists: nil, artistId: nil, album: nil, albumId: nil,
                                       artistRuns: [], explicit: false)],
                moreBrowseId: nil, moreParams: nil
            )],
            continuation: continuation
        )
    }

    override func getHomeContinuation(token: String) async throws -> HomePageRecord {
        let (title, continuation) = try await feed.requestContinuation(token: token)
        if title.isEmpty {
            return HomePageRecord(chips: [], sections: [], continuation: continuation)
        }
        return HomePageRecord(
            chips: [],
            sections: [HomeSectionRecord(
                title: title,
                format: .compactSongs,
                items: [HomeItemRecord(kind: "song", id: title, title: title, subtitle: nil, thumbnail: nil,
                                       duration: nil, artists: nil, artistId: nil, album: nil, albumId: nil,
                                       artistRuns: [], explicit: false)],
                moreBrowseId: nil, moreParams: nil
            )],
            continuation: continuation
        )
    }
}

@MainActor private func makeHomeModel() -> HomeViewModel {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sideb-home-tests-\(UUID().uuidString)", isDirectory: true)
    let preferences = UserDefaults(suiteName: "HomeFeedTests.\(UUID().uuidString)")!
    let model = HomeViewModel(cacheStore: HomeFeedCacheStore(directory: directory), preferences: preferences)
    model.prepareSession(identity: "test-account", purgePrevious: false)
    return model
}

@MainActor private func loadFilteredHome(_ model: HomeViewModel, core: HomeCoreStub) async {
    let initial = Task { await model.loadHomeFeed(core: core, chipParams: "focus") }
    await core.feed.waitForCount(1)
    await core.feed.succeed(0, title: "Focus", continuation: "token-1")
    await initial.value
}

@Test @MainActor func homeManualPaginationSkipsDuplicatePagesAndIgnoresConcurrentClicks() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()
    await loadFilteredHome(model, core: core)

    let more = Task { await model.loadMoreContent(core: core) }
    await core.feed.waitForContinuationCount(1)
    await model.loadMoreContent(core: core)
    #expect(await core.feed.requestedContinuationTokens() == ["token-1"])
    await core.feed.succeedContinuation(0, title: "Focus", continuation: "token-2")
    await core.feed.waitForContinuationCount(2)
    #expect(model.isLoadingMore)
    await core.feed.succeedContinuation(1, title: "New recommendations", continuation: nil)
    await more.value

    #expect(model.sections.map(\.title) == ["Focus", "New recommendations"])
    #expect(await core.feed.requestedContinuationTokens() == ["token-1", "token-2"])
    #expect(!model.isLoadingMore)
    #expect(model.continuationToken == nil)
    #expect(model.loadMoreMessage == "No hay más recomendaciones por ahora.")
}

@Test @MainActor func homeManualPaginationReportsFailureAndAllowsImmediateRetry() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()
    await loadFilteredHome(model, core: core)

    let failed = Task { await model.loadMoreContent(core: core) }
    await core.feed.waitForContinuationCount(1)
    await core.feed.failContinuation(0)
    await failed.value
    #expect(!model.isLoadingMore)
    #expect(model.continuationToken == "token-1")
    #expect(model.loadMoreMessage == "No se pudieron cargar más recomendaciones. Volvé a intentarlo.")

    let retry = Task { await model.loadMoreContent(core: core) }
    await core.feed.waitForContinuationCount(2)
    #expect(model.loadMoreMessage == nil)
    await core.feed.succeedContinuation(1, title: "Retry succeeded", continuation: "token-2")
    await retry.value
    #expect(model.sections.map(\.title) == ["Focus", "Retry succeeded"])
    #expect(model.continuationToken == "token-2")
    #expect(!model.isLoadingMore)
}

@Test @MainActor func homeManualPaginationCapsDuplicatePagesAndContinuesFromLatestToken() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()
    await loadFilteredHome(model, core: core)
    let revision = model.contentRevision
    let more = Task { await model.loadMoreContent(core: core) }
    for index in 0..<3 {
        await core.feed.waitForContinuationCount(index + 1)
        await core.feed.succeedContinuation(index, title: "Focus", continuation: "token-\(index + 2)")
    }
    await more.value
    #expect(await core.feed.requestedContinuationTokens() == ["token-1", "token-2", "token-3"])
    #expect(model.contentRevision == revision)
    #expect(model.continuationToken == "token-4")
    #expect(!model.isLoadingMore)
    #expect(model.loadMoreMessage != nil)

    let next = Task { await model.loadMoreContent(core: core) }
    await core.feed.waitForContinuationCount(4)
    await core.feed.succeedContinuation(3, title: "Next batch", continuation: nil)
    await next.value
    #expect(model.sections.map(\.title) == ["Focus", "Next batch"])
}

@Test @MainActor func homeManualPaginationStopsContinuationCycleAndExplainsEnd() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()
    await loadFilteredHome(model, core: core)
    let more = Task { await model.loadMoreContent(core: core) }
    await core.feed.waitForContinuationCount(1)
    await core.feed.succeedContinuation(0, title: "Focus", continuation: "token-2")
    await core.feed.waitForContinuationCount(2)
    await core.feed.succeedContinuation(1, title: "Focus", continuation: "token-1")
    await more.value
    #expect(model.sections.map(\.title) == ["Focus"])
    #expect(model.continuationToken == nil)
    #expect(!model.isLoadingMore)
    #expect(model.loadMoreMessage == "No hay más recomendaciones por ahora.")
}

@Test @MainActor func homeEmptyFinalContinuationReportsEndWithoutReloadingCards() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()
    await loadFilteredHome(model, core: core)
    let revision = model.contentRevision
    let more = Task { await model.loadMoreContent(core: core) }
    await core.feed.waitForContinuationCount(1)
    await core.feed.succeedContinuation(0, title: "", continuation: nil)
    await more.value
    #expect(model.sections.map(\.title) == ["Focus"])
    #expect(model.contentRevision == revision)
    #expect(model.continuationToken == nil)
    #expect(!model.isLoadingMore)
    #expect(model.loadMoreMessage == "No hay más recomendaciones por ahora.")
}

@Test @MainActor func homeCancelledManualPaginationUnlocksButtonWithoutApplyingResponse() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()
    await loadFilteredHome(model, core: core)
    let more = Task { await model.loadMoreContent(core: core) }
    await core.feed.waitForContinuationCount(1)
    more.cancel()
    await core.feed.succeedContinuation(0, title: "Cancelled", continuation: nil)
    await more.value
    #expect(model.sections.map(\.title) == ["Focus"])
    #expect(model.continuationToken == "token-1")
    #expect(!model.isLoadingMore)
    #expect(model.loadMoreMessage == nil)
}

@Test @MainActor func homeChipChangeDiscardsPendingManualContinuationAndItsStatus() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()
    await loadFilteredHome(model, core: core)
    let more = Task { await model.loadMoreContent(core: core) }
    await core.feed.waitForContinuationCount(1)
    let chip = Task { await model.loadHomeFeed(core: core, chipParams: "relax") }
    await core.feed.waitForCount(2)
    await core.feed.succeed(1, title: "Relax")
    await chip.value
    await core.feed.succeedContinuation(0, title: "Old feed", continuation: nil)
    await more.value
    #expect(model.selectedChipParams == "relax")
    #expect(model.sections.map(\.title) == ["Relax"])
    #expect(model.loadMoreMessage == nil)
    #expect(!model.isLoadingMore)
}

@Test @MainActor func homeDiscardsOlderChipResponse() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()

    let first = Task { await model.loadHomeFeed(core: core) }
    await core.feed.waitForCount(1)
    let second = Task { await model.loadHomeFeed(core: core, chipParams: "focus") }
    await core.feed.waitForCount(2)

    await core.feed.succeed(1, title: "Focus")
    await second.value
    await core.feed.succeed(0, title: "Old")
    await first.value

    #expect(model.selectedChipParams == "focus")
    #expect(model.sections.map(\.title) == ["Focus"])
    #expect(!model.isLoadingChip)
}

@Test @MainActor func homeResetDiscardsPendingSessionResponse() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()

    let pending = Task { await model.loadHomeFeed(core: core) }
    await core.feed.waitForCount(1)
    model.resetForAccountChange()
    await core.feed.succeed(0, title: "Previous account")
    await pending.value

    #expect(model.sections.isEmpty)
    #expect(model.featured == .empty)
    #expect(model.selectedChipParams == nil)
    #expect(!model.isLoading)
}

@Test @MainActor func homePrefetchesPrioritiesAndKeepsContinuationAfterNetworkFailure() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()
    let initial = Task { await model.loadHomeFeed(core: core) }
    await core.feed.waitForCount(1)
    await core.feed.succeed(0, title: "Listen again", continuation: "token-1")
    await initial.value

    await core.feed.waitForContinuationCount(1)
    await core.feed.succeedContinuation(0, title: "Forgotten favorites", continuation: "token-2")
    await core.feed.waitForContinuationCount(2)
    await core.feed.failContinuation(1)

    for _ in 0..<100 where model.isLoadingMore {
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.sections.map(\.title) == ["Listen again", "Forgotten favorites"])
    #expect(model.continuationToken == "token-2")
    #expect(!model.isLoadingMore)
}

@Test @MainActor func homeChipChangeDiscardsPendingPriorityContinuation() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()
    let initial = Task { await model.loadHomeFeed(core: core) }
    await core.feed.waitForCount(1)
    await core.feed.succeed(0, title: "Listen again", continuation: "token-1")
    await initial.value
    await core.feed.waitForContinuationCount(1)

    let chipLoad = Task { await model.loadHomeFeed(core: core, chipParams: "focus") }
    await core.feed.waitForCount(2)
    await core.feed.succeed(1, title: "Focus", continuation: nil)
    await chipLoad.value
    await core.feed.succeedContinuation(0, title: "Forgotten favorites", continuation: "stale-token")
    try? await Task.sleep(for: .milliseconds(30))

    #expect(model.selectedChipParams == "focus")
    #expect(model.sections.map(\.title) == ["Focus"])
    #expect(!model.isLoadingMore)
}

@Test @MainActor func homePriorityPrefetchStopsAtRepeatedContinuationToken() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()
    let initial = Task { await model.loadHomeFeed(core: core) }
    await core.feed.waitForCount(1)
    await core.feed.succeed(0, title: "Listen again", continuation: "same-token")
    await initial.value
    await core.feed.waitForContinuationCount(1)
    await core.feed.succeedContinuation(0, title: "Forgotten favorites", continuation: "same-token")

    for _ in 0..<100 where model.isLoadingMore {
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.sections.map(\.title) == ["Listen again", "Forgotten favorites"])
    #expect(model.continuationToken == nil)
    #expect(!model.isLoadingMore)
}

@Test @MainActor func homeShowsCachedChipAndKeepsItOnRefreshFailure() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()

    let initial = Task { await model.loadHomeFeed(core: core) }
    await core.feed.waitForCount(1)
    await core.feed.succeed(0, title: "All", continuation: "all-next")
    await initial.value

    let focus = Task { await model.loadHomeFeed(core: core, chipParams: "focus") }
    await core.feed.waitForCount(2)
    await core.feed.succeed(1, title: "Focus", continuation: "focus-next")
    await focus.value

    let cached = Task { await model.loadHomeFeed(core: core) }
    await core.feed.waitForCount(3)
    #expect(model.sections.map(\.title) == ["All"])
    #expect(model.continuationToken == "all-next")
    await core.feed.fail(2)
    await cached.value

    #expect(model.sections.map(\.title) == ["All"])
    #expect(model.errorMessage != nil)
    #expect(!model.isLoadingChip)
}

@Test @MainActor func homeRestoresPreviousChipWhenUncachedChipFails() async {
    let core = HomeCoreStub()
    let model = makeHomeModel()

    let initial = Task { await model.loadHomeFeed(core: core) }
    await core.feed.waitForCount(1)
    await core.feed.succeed(0, title: "All", continuation: "all-next")
    await initial.value

    let failed = Task { await model.loadHomeFeed(core: core, chipParams: "unknown") }
    await core.feed.waitForCount(2)
    await core.feed.fail(1)
    await failed.value

    #expect(model.selectedChipParams == nil)
    #expect(model.sections.map(\.title) == ["All"])
    #expect(model.continuationToken == "all-next")
}

import AppKit
import SwiftUI

@Test @MainActor func testHomeFeedCollectionViewMountAndLayout() async {
    let fixture = HomeBenchmarkFixture.page()
    let sections = HomePresentationFactory.sections(from: fixture.sections, chip: nil)
    let feedView = HomeFeedCollectionView(
        sections: sections,
        revision: 1,
        selectedChip: nil,
        hasMore: true,
        isLoadingMore: false,
        currentTrackID: nil,
        isPlaying: false,
        player: PlayerViewModel(),
        router: nil,
        onNavigate: { _ in },
        onLoadMore: { }
    )
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    let hosting = NSHostingView(rootView: feedView)
    hosting.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
    window.contentView = hosting
    window.displayIfNeeded()
    
    // Simulate scroll bounds change:
    if let scroll = hosting.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
        print("Found scroll view: \(scroll)")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: -20)) // overscroll top
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 3000)) // overscroll bottom
    }
    
    // Simulate teardown and recreation (like going to album and coming back):
    window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    window.displayIfNeeded()
    
    let hosting2 = NSHostingView(rootView: feedView)
    hosting2.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
    window.contentView = hosting2
    window.displayIfNeeded()
    
    #expect(true)
}

@Test @MainActor func testHomeItemViewHitboxesAndArtistHover() async {
    let itemView = HomeItemView(frame: NSRect(x: 0, y: 0, width: 330, height: 56))
    var cardClicked = false
    var artistClicked = false

    let record = HomeItemRecord(
        kind: "song",
        id: "song_123",
        title: "Super Rich Kids",
        subtitle: "Frank Ocean",
        thumbnail: "https://example.com/art.jpg",
        duration: "5:04",
        artists: "Frank Ocean",
        artistId: "artist_123",
        album: nil,
        albumId: nil,
        artistRuns: [],
        explicit: false
    )

    itemView.configure(
        record: record,
        style: .compactSong,
        currentTrackID: nil,
        isPlaying: false,
        onCard: { cardClicked = true },
        onCover: { cardClicked = true },
        onTitle: { cardClicked = true },
        onArtist: { artistClicked = true },
        onAlbum: { },
        menuProvider: { nil }
    )

    itemView.layout()

    // 1. Verificar que cardButton cubre toda la tarjeta, es transparente y no tiene texto placeholder
    #expect(itemView.cardButton.frame == NSRect(x: 0, y: 0, width: 330, height: 56))
    #expect(itemView.cardButton.isTransparent == true)
    #expect(itemView.cardButton.title.isEmpty)

    // 2. Verificar que el botón de artista no se extiende por toda la tarjeta
    let maxAvailable = 330.0 - 58.0 - 38.0 // 234.0
    #expect(itemView.artist.frame.width < 120.0)
    #expect(itemView.artist.frame.width < maxAvailable)
    #expect(itemView.artist.frame.origin.x == 58.0)

    // 3. Probar clic en la tarjeta (reproduce)
    itemView.cardButton.performClick(nil)
    #expect(cardClicked == true)
    #expect(artistClicked == false)

    // 4. Probar clic en el botón de artista
    itemView.artist.performClick(nil)
    #expect(artistClicked == true)

    // 5. Probar hover sobre área de fondo de la tarjeta (no sobre el artista)
    itemView.setHovered(true, localPoint: NSPoint(x: 10, y: 10))
    #expect(itemView.isArtistHovered == false)

    // 6. Probar hover específicamente sobre el artista (se ilumina SIN subrayado)
    let artistCenter = NSPoint(x: itemView.artist.frame.midX, y: itemView.artist.frame.midY)
    itemView.setHovered(true, localPoint: artistCenter)
    #expect(itemView.isArtistHovered == true)
    let underline = itemView.artist.attributedTitle.attribute(.underlineStyle, at: 0, effectiveRange: nil)
    #expect(underline == nil)

    // 7. Probar salida del hover
    itemView.setHovered(false, localPoint: nil)
    #expect(itemView.isArtistHovered == false)
}

@Test @MainActor func testHomeLargeCardsFlowMetadataAfterVisibleTitle() {
    func makeCard(_ name: String, width: CGFloat = 160, artistName: String = "Frank Ocean",
                  onArtist: @escaping () -> Void = {}) -> HomeItemView {
        let card = HomeItemView(frame: NSRect(x: 0, y: 0, width: width,
                                               height: width + HomeItemView.largeCardTextHeight))
        card.configure(
            record: HomeItemRecord(
                kind: "song", id: name, title: name, subtitle: artistName, thumbnail: nil,
                duration: nil, artists: artistName, artistId: "artist_123", album: nil,
                albumId: nil, artistRuns: [], explicit: false
            ),
            style: .largeCard, currentTrackID: nil, isPlaying: false,
            onCard: {}, onCover: {}, onTitle: {}, onArtist: onArtist, onAlbum: {}, menuProvider: { nil }
        )
        card.layout()
        return card
    }

    var artistClicked = false
    let short = makeCard("Pink + White") { artistClicked = true }
    let long = makeCard("Super Rich Kids (feat. Earl Sweatshirt)")
    func label(_ text: String, in card: HomeItemView) -> NSTextField? {
        card.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == text }
    }
    let shortTitle = label("Pink + White", in: short)
    let longTitle = label("Super Rich Kids (feat. Earl Sweatshirt)", in: long)
    let shortType = label("Canción", in: short)
    let longType = label("Canción", in: long)

    #expect(shortTitle != nil && longTitle != nil && shortType != nil && longType != nil)
    guard let shortTitle, let longTitle, let shortType, let longType else { return }
    #expect(shortTitle.frame.minY == longTitle.frame.minY)
    #expect(longTitle.frame.height > shortTitle.frame.height)
    #expect(shortType.frame.minY == shortTitle.frame.maxY + 3)
    #expect(longType.frame.minY == longTitle.frame.maxY + 3)
    #expect(shortType.frame.minY < longType.frame.minY)
    #expect(short.artist.frame.maxY < short.bounds.maxY)
    short.artist.performClick(nil)
    #expect(artistClicked)

    let narrow = makeCard("Super Rich Kids (feat. Earl Sweatshirt)", width: 140,
                          artistName: "Frank Ocean & Tyler, The Creator")
    #expect(narrow.artist.frame.maxX <= narrow.bounds.maxX)
    #expect(narrow.artist.frame.maxY <= narrow.bounds.maxY)
}

@Test @MainActor func testHomeArtworkCornersRemainIndependentFromCardMaskAfterReuseAndResize() {
    func configure(_ card: HomeItemView, kind: String, id: String, title: String) {
        card.configure(
            record: HomeItemRecord(
                kind: kind, id: id, title: title, subtitle: "Artist", thumbnail: nil,
                duration: nil, artists: "Artist", artistId: "artist_1", album: nil,
                albumId: nil, artistRuns: [], explicit: false
            ),
            style: .largeCard, currentTrackID: nil, isPlaying: false,
            onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {}, menuProvider: { nil }
        )
    }

    func artworkButton(in card: HomeItemView) -> NSButton? {
        card.subviews.compactMap { $0 as? NSButton }.first { $0.imagePosition == .imageOnly }
    }

    let card = HomeItemView(frame: NSRect(x: 0, y: 0, width: 140, height: 234))
    configure(card, kind: "album", id: "album_1", title: "808s & Heartbreak")
    card.layout()

    #expect(card.layer?.cornerRadius == 14)
    #expect(card.clipsToBounds == false)
    #expect(card.layer?.masksToBounds == false)
    guard let albumCover = artworkButton(in: card) else {
        Issue.record("No se encontró el botón de portada del álbum")
        return
    }
    #expect(albumCover.frame == NSRect(x: 0, y: 0, width: 140, height: 140))
    #expect(albumCover.layer?.masksToBounds == true)
    #expect(albumCover.layer?.cornerRadius == AppTheme.artworkCardRadius)
    #expect(card.equalizerOverlay.layer?.cornerRadius == AppTheme.artworkCardRadius)

    card.setFrameSize(NSSize(width: 120, height: 214))
    card.prepareForReuse()
    configure(card, kind: "artist", id: "artist_2", title: "Artist")
    card.layout()

    #expect(card.clipsToBounds == false)
    #expect(card.layer?.masksToBounds == false)
    guard let artistCover = artworkButton(in: card) else {
        Issue.record("No se encontró el botón de portada del artista")
        return
    }
    #expect(artistCover.frame == NSRect(x: 0, y: 0, width: 120, height: 120))
    #expect(artistCover.layer?.masksToBounds == true)
    #expect(artistCover.layer?.cornerRadius == 60)
    #expect(card.equalizerOverlay.layer?.cornerRadius == 60)
}

@Test func testHomePresentationFactorySectionOrdering() {
    let dummyItem = HomeItemRecord(
        kind: "song",
        id: "id_1",
        title: "Song",
        subtitle: "Artist",
        thumbnail: nil,
        duration: nil,
        artists: "Artist",
        artistId: nil,
        album: nil,
        albumId: nil,
        artistRuns: [],
        explicit: false
    )
    let records = [
        HomeSectionRecord(title: "Quick picks", format: .compactSongs, items: [dummyItem], moreBrowseId: nil, moreParams: nil),
        HomeSectionRecord(title: "Mixed for you", format: .largeCards, items: [dummyItem], moreBrowseId: nil, moreParams: nil),
        HomeSectionRecord(title: "Albums for you", format: .largeCards, items: [dummyItem], moreBrowseId: nil, moreParams: nil),
        HomeSectionRecord(title: "Listen again", format: .largeCards, items: [dummyItem], moreBrowseId: nil, moreParams: nil),
        HomeSectionRecord(title: "Forgotten favorites", format: .compactSongs, items: [dummyItem], moreBrowseId: nil, moreParams: nil),
        HomeSectionRecord(title: "From your library", format: .largeCards, items: [dummyItem], moreBrowseId: nil, moreParams: nil),
        HomeSectionRecord(title: "Similar artists", format: .largeCards, items: [dummyItem], moreBrowseId: nil, moreParams: nil),
    ]

    let ordered = HomePresentationFactory.sections(from: records, chip: nil)
    let titles = ordered.map(\.title)
    #expect(titles == ["Listen again", "Forgotten favorites", "Albums for you", "From your library", "Quick picks", "Mixed for you", "Similar artists"])
    #expect(ordered.first?.style == .largeCard)
    #expect(ordered.first(where: { $0.title == "Forgotten favorites" })?.style == .largeCard)
    #expect(ordered.first(where: { $0.title == "Quick picks" })?.style == .compactSong)

    let translated = HomeSectionRecord(title: "Vuelve a escucharlo", format: .compactSongs,
                                        items: [dummyItem], moreBrowseId: nil, moreParams: nil)
    #expect(HomePresentationFactory.sections(from: [translated], chip: nil).first?.id ==
            HomePresentationFactory.sections(from: [records[3]], chip: nil).first?.id)
}

@Test @MainActor func testHomeItemViewEqualizerOverlayAndDirectPlay() {
    let songRecord = HomeItemRecord(
        kind: "song",
        id: "song_123",
        title: "Pink + White",
        subtitle: "Frank Ocean • Blonde",
        thumbnail: nil,
        duration: "3:04",
        artists: "Frank Ocean",
        artistId: "artist_frank",
        album: "Blonde",
        albumId: "album_blonde",
        artistRuns: [],
        explicit: false
    )

    let albumRecord = HomeItemRecord(
        kind: "album",
        id: "MPREb_blonde",
        title: "Blonde",
        subtitle: "Frank Ocean",
        thumbnail: nil,
        duration: nil,
        artists: "Frank Ocean",
        artistId: "artist_frank",
        album: nil,
        albumId: nil,
        artistRuns: [],
        explicit: false
    )

    let playlistRecord = HomeItemRecord(
        kind: "playlist",
        id: "VLPL_my_playlist",
        title: "Favoritos",
        subtitle: "Usuario",
        thumbnail: nil,
        duration: nil,
        artists: nil,
        artistId: nil,
        album: nil,
        albumId: nil,
        artistRuns: [],
        explicit: false
    )

    var songDirectPlayClicked = false
    let songCard = HomeItemView(frame: NSRect(x: 0, y: 0, width: 160, height: 254))
    songCard.configure(
        record: songRecord,
        style: .largeCard,
        currentTrackID: "song_123",
        currentAlbumBrowseId: nil,
        currentPlaylistBrowseId: nil,
        isPlaying: true,
        queueContext: .radio(seedVideoId: "song_123", title: "Radio", seedName: "Pink + White"),
        onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {},
        onDirectPlay: { songDirectPlayClicked = true },
        menuProvider: { nil }
    )
    songCard.layout()

    // 1. Verificación del overlay animado en canción activa
    #expect(!songCard.equalizerOverlay.isHidden)
    #expect(songCard.equalizerOverlay.hitTest(NSPoint(x: 20, y: 20)) == nil)

    // 2. Verificación de pausa
    songCard.updatePlayback(currentTrackID: "song_123", isPlaying: false, queueContext: .radio(seedVideoId: "song_123", title: "Radio", seedName: "Pink + White"))
    #expect(!songCard.equalizerOverlay.isHidden) // en pausa se mantiene pero congelado

    // 3. Verificación de otra canción
    songCard.updatePlayback(currentTrackID: "other_song", isPlaying: true,
                           queueContext: .radio(seedVideoId: "song_123", title: "Radio", seedName: "Pink + White"))
    #expect(!songCard.equalizerOverlay.isHidden) // la radio sigue perteneciendo a su canción origen
    songCard.updatePlayback(currentTrackID: "other_song", isPlaying: true, queueContext: nil)
    #expect(songCard.equalizerOverlay.isHidden) // cambiar de contexto retira el indicador

    // 4. Verificación de álbum activo y reproducción directa
    var albumDirectPlayClicked = false
    let albumCard = HomeItemView(frame: NSRect(x: 0, y: 0, width: 160, height: 254))
    albumCard.configure(
        record: albumRecord,
        style: .largeCard,
        currentTrackID: nil,
        currentAlbumBrowseId: "MPREb_blonde",
        currentPlaylistBrowseId: nil,
        isPlaying: true,
        queueContext: .album(browseId: "MPREb_blonde", title: "Blonde"),
        onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {},
        onDirectPlay: { albumDirectPlayClicked = true },
        menuProvider: { nil }
    )
    albumCard.layout()

    #expect(!albumCard.equalizerOverlay.isHidden)

    // Simular clic en el área táctil de play de la tarjeta del álbum
    albumCard.hovered = true
    guard let playHitBtn = albumCard.subviews.compactMap({ $0 as? HomePlayHitButton }).first else {
        Issue.record("No se encontró HomePlayHitButton en la tarjeta")
        return
    }
    playHitBtn.performClick(nil)
    #expect(albumDirectPlayClicked)

    // 5. Verificación de playlist activa con prefijo normalizado VL
    let playlistCard = HomeItemView(frame: NSRect(x: 0, y: 0, width: 160, height: 254))
    playlistCard.configure(
        record: playlistRecord,
        style: .largeCard,
        currentTrackID: nil,
        currentAlbumBrowseId: nil,
        currentPlaylistBrowseId: "PL_my_playlist",
        isPlaying: true,
        queueContext: .playlist(browseId: "PL_my_playlist", title: "Favoritos"),
        onCard: {}, onCover: {}, onTitle: {}, onArtist: {}, onAlbum: {},
        onDirectPlay: {},
        menuProvider: { nil }
    )
    playlistCard.layout()
    #expect(!playlistCard.equalizerOverlay.isHidden)

    // 6. Reciclaje y limpieza
    playlistCard.prepareForReuse()
    #expect(playlistCard.equalizerOverlay.isHidden)
}
