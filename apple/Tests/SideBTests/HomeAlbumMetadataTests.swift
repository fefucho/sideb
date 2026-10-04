import Foundation
import Testing
import SideBCore
@testable import SideB

private func metadataItem(_ id: String, subtitle: String? = nil, artists: String? = nil) -> HomeItemRecord {
    HomeItemRecord(kind: "album", id: id, title: "Item title", subtitle: subtitle, thumbnail: nil,
        duration: nil, artists: artists, artistId: nil, album: nil, albumId: nil,
        artistRuns: [], explicit: false)
}

private func metadataAlbum(_ id: String = "album", title: String = "Blonde", artist: String? = "Frank Ocean",
                           subtitle: String? = "2016", secondSubtitle: String? = nil,
                           durations: [String?]) -> AlbumDetailRecord {
    let tracks = durations.enumerated().map { index, duration in
        SongItemRecord(videoId: "track-\(index)", title: "Track \(index)", artists: "", album: nil,
            duration: duration, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil,
            isVideo: false, isUpload: false, library: nil, artistRuns: [])
    }
    return AlbumDetailRecord(browseId: id, title: title, artist: artist, artistId: nil, subtitle: subtitle,
        secondSubtitle: secondSubtitle, description: nil, thumbnail: nil, playlistId: nil,
        inLibrary: false, items: tracks, sections: [])
}

@Test func homeAlbumMetadataUsesAlbumValuesAndSpanishSummaryOrder() {
    let durations = Array(repeating: Optional("3:32"), count: 16) + ["3:28"]
    let value = HomeAlbumMetadata.make(item: metadataItem("blonde"), album: metadataAlbum(durations: durations))
    #expect(value.title == "Blonde")
    #expect(value.artist == "Frank Ocean")
    #expect(value.summary == "Álbum • 2016 • 17 canciones • 1 h")
}

@Test func homeAlbumMetadataCleansTypeAndYearOutOfArtistFallback() {
    let item = metadataItem("fallback", subtitle: "Álbum · 2016 · Travis Scott", artists: "Álbum • Travis Scott")
    let value = HomeAlbumMetadata.make(item: item, album: nil)
    #expect(value.artist == "Travis Scott")
    #expect(value.summary == "Álbum • 2016")
}

@Test func homeAlbumMetadataDoesNotInventUnavailableCountsOrDuration() {
    let value = HomeAlbumMetadata.make(item: metadataItem("unknown", subtitle: "Álbum"), album: nil)
    #expect(value.summary == "Álbum")
    #expect(value.artist == nil)
}

@Test func homeAlbumMetadataKeepsArtistNamesContainingMetadataWords() {
    let value = HomeAlbumMetadata.make(item: metadataItem("hour", artists: "The 1975 • Song Hour"), album: nil)
    #expect(value.artist == "The 1975 • Song Hour")
}

@Test func homeAlbumMetadataRejectsMalformedTrackDurations() {
    let value = HomeAlbumMetadata.make(item: metadataItem("bad"), album: metadataAlbum(durations: ["1:60", "-5"]))
    #expect(value.summary == "Álbum • 2016 • 2 canciones")
}

@Test func homeAlbumMetadataUsesProviderDurationWhenTrackDurationsAreIncomplete() {
    let album = metadataAlbum(secondSubtitle: "2 songs • 1 hour", durations: ["3:00", nil])
    let value = HomeAlbumMetadata.make(item: metadataItem("provider"), album: album)
    #expect(value.summary == "Álbum • 2016 • 2 canciones • 1 h")
}

@Test func homeAlbumMetadataPreservesProviderSummaryWithoutLoadedTrackRows() {
    let album = metadataAlbum(secondSubtitle: "17 songs • 1 hour", durations: [])
    let value = HomeAlbumMetadata.make(item: metadataItem("provider-count"), album: album)
    #expect(value.summary == "Álbum • 2016 • 17 canciones • 1 h")
}

@Test @MainActor func homeAlbumMetadataLoadsOnlyVisibleAlbumsAndResetsBySession() async {
    let model = HomeAlbumMetadataModel()
    let requested = MetadataRequestRecorder()
    let items = (0..<2).map { metadataItem("album-\($0)") }
    await model.load(items: items, sessionKey: "account-a") { id in
        await requested.record(id)
        return metadataAlbum(id, durations: ["1:00"])
    }
    #expect(await requested.ids.sorted() == ["album-0", "album-1"])
    #expect(model.details.count == 2)
    #expect(model.display(for: items[0]).summary == "Álbum • 2016 • 1 canción • 1 min")
    #expect(model.display(for: items[0], sessionKey: "account-other").title == "Item title")

    let nextItem = metadataItem("album-2")
    await model.load(items: [nextItem], sessionKey: "account-b") { id in
        await requested.record(id)
        return metadataAlbum(id, durations: ["1:00"])
    }
    #expect(model.details.keys.sorted() == ["album-2"])
}

@Test @MainActor func homeAlbumMetadataFetchesSixVisibleAlbumsWithAtMostTwoConcurrentRequests() async {
    let model = HomeAlbumMetadataModel()
    let probe = BoundedMetadataFetch()
    let items = (0..<8).map { metadataItem("album-\($0)") }
    let firstPage = Task {
        await model.load(items: Array(items.prefix(6)), sessionKey: "account-a") { id in
            await probe.fetch(id)
        }
    }

    await probe.waitForStartedCount(2)
    #expect(await probe.activeCount == 2)
    #expect(await probe.maximumActiveCount == 2)
    for expectedCount in 3...6 {
        await probe.finishOne()
        await probe.waitForStartedCount(expectedCount)
        #expect(await probe.maximumActiveCount == 2)
    }
    await probe.finishOne()
    await probe.finishOne()
    await firstPage.value
    #expect(model.details.count == 6)

    await model.load(items: Array(items.suffix(2)), sessionKey: "account-a") { id in
        metadataAlbum(id, durations: ["1:00"])
    }
    #expect(model.details.count == 6)
    #expect(model.details["album-6"] != nil)
    #expect(model.details["album-7"] != nil)
}

@Test @MainActor func homeAlbumMetadataIgnoresResponseFromPreviousSession() async {
    let model = HomeAlbumMetadataModel()
    let pending = PendingMetadataResponse()
    let oldItem = metadataItem("old-album")
    let oldLoad = Task {
        await model.load(items: [oldItem], sessionKey: "account-a") { _ in
            await pending.waitForResponse()
        }
    }
    await pending.waitUntilRequested()

    let currentItem = metadataItem("current-album")
    await model.load(items: [currentItem], sessionKey: "account-b") { id in
        metadataAlbum(id, durations: ["2:00"])
    }
    await pending.resume(with: metadataAlbum("old-album", title: "Old", durations: ["1:00"]))
    await oldLoad.value

    #expect(model.details.keys.sorted() == ["current-album"])
    #expect(model.display(for: oldItem).title == "Item title")
}

private actor MetadataRequestRecorder {
    private(set) var ids: [String] = []
    func record(_ id: String) { ids.append(id) }
}

private actor BoundedMetadataFetch {
    private var pending: [(String, CheckedContinuation<AlbumDetailRecord, Never>)] = []
    private var startedIDs: [String] = []
    private var startedWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var activeCount = 0
    private(set) var maximumActiveCount = 0

    func fetch(_ id: String) async -> AlbumDetailRecord {
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        startedIDs.append(id)
        let ready = startedWaiters.filter { startedIDs.count >= $0.0 }
        startedWaiters.removeAll { startedIDs.count >= $0.0 }
        ready.forEach { $0.1.resume() }
        return await withCheckedContinuation { pending.append((id, $0)) }
    }

    func waitForStartedCount(_ count: Int) async {
        if startedIDs.count >= count { return }
        await withCheckedContinuation { startedWaiters.append((count, $0)) }
    }

    func finishOne() {
        guard !pending.isEmpty else { return }
        let (_, continuation) = pending.removeFirst()
        activeCount -= 1
        continuation.resume(returning: metadataAlbum(durations: ["1:00"]))
    }
}

private actor PendingMetadataResponse {
    private var response: CheckedContinuation<AlbumDetailRecord, Never>?
    private var requested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    func waitForResponse() async -> AlbumDetailRecord {
        requested = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        return await withCheckedContinuation { response = $0 }
    }

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func resume(with value: AlbumDetailRecord) {
        response?.resume(returning: value)
        response = nil
    }
}

@Test @MainActor func homeAlbumMetadataLimitsRequestsAcrossOverlappingPages() async {
    let model = HomeAlbumMetadataModel()
    let probe = BoundedMetadataFetch()
    let oldItems = [metadataItem("old-0"), metadataItem("old-1")]
    let newItems = (0..<6).map { metadataItem("new-\($0)") }
    let oldLoad = Task {
        await model.load(items: oldItems, sessionKey: "a") { id in await probe.fetch(id) }
    }
    await probe.waitForStartedCount(2)
    let newLoad = Task {
        await model.load(items: newItems, sessionKey: "a") { id in await probe.fetch(id) }
    }
    for expectedCount in 3...8 {
        await probe.finishOne()
        await probe.waitForStartedCount(expectedCount)
        #expect(await probe.maximumActiveCount == 2)
    }
    await probe.finishOne()
    await probe.finishOne()
    await oldLoad.value
    await newLoad.value
    #expect(model.details.keys.sorted() == newItems.map(\.id).sorted())
}
