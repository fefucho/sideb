import Foundation
import Testing
import SideBCore
@testable import SideB

private func playlistMetadataItem(_ id: String, subtitle: String? = nil,
                                  creator: String? = nil, creatorID: String? = nil,
                                  kind: String = "playlist") -> HomeItemRecord {
    HomeItemRecord(kind: kind, id: id, title: "Home title", subtitle: subtitle, thumbnail: nil,
        duration: nil, artists: creator, artistId: creatorID, album: nil, albumId: nil,
        artistRuns: [], explicit: false)
}

private func playlistMetadataDetail(_ id: String, title: String = "Detail title",
                                    subtitle: String? = nil, durations: [String?] = ["1:00"],
                                    continuation: String? = nil) -> PlaylistDetailRecord {
    let tracks = durations.enumerated().map { index, duration in
        SongItemRecord(videoId: "song-\(index)", title: "Song", artists: "", album: nil,
            duration: duration, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil,
            isVideo: false, isUpload: false, library: nil, artistRuns: [])
    }
    return PlaylistDetailRecord(id: id, title: title, subtitle: subtitle, thumbnail: nil,
        description: nil, items: tracks, continuation: continuation, owned: false,
        inLibrary: false, privacy: nil, collaborative: false, sort: nil, sortEditable: false)
}

@Test func homePlaylistMetadataNeverPresentsPartialPageAsCatalogTotal() {
    let item = playlistMetadataItem("partial", subtitle: "Lista de reproducción • 2026 • Creator")
    let detail = playlistMetadataDetail("partial", durations: ["3:00", "4:00"], continuation: "next")
    let value = HomePlaylistMetadata.make(item: item, playlist: detail)
    #expect(value.title == "Detail title")
    #expect(value.creator == "Creator")
    #expect(value.summary == "Lista de reproducción")
}

@Test func homePlaylistMetadataUsesExplicitProviderTotalAndDurationFromPartialPage() {
    let item = playlistMetadataItem("summary", creator: "Home creator", creatorID: "UCowner")
    let detail = playlistMetadataDetail("summary", subtitle: "Other creator • 2,000 songs • 4 hours",
                                        durations: ["1:00"], continuation: "next")
    let value = HomePlaylistMetadata.make(item: item, playlist: detail)
    #expect(value.creator == "Home creator")
    #expect(value.creatorID == "UCowner")
    #expect(value.summary == "Lista de reproducción • 2000 canciones • 4 h")
}

@Test func homePlaylistMetadataDerivesOnlyCompleteValidCatalogSummary() {
    let item = playlistMetadataItem("complete")
    let complete = playlistMetadataDetail("complete", durations: ["1:30", "2:30"])
    #expect(HomePlaylistMetadata.make(item: item, playlist: complete).summary == "Lista de reproducción • 2 canciones • 4 min")
    let incompleteDuration = playlistMetadataDetail("complete", durations: ["1:30", nil])
    #expect(HomePlaylistMetadata.make(item: item, playlist: incompleteDuration).summary == "Lista de reproducción • 2 canciones")
    let malformedDuration = playlistMetadataDetail("complete", durations: ["1:60"])
    #expect(HomePlaylistMetadata.make(item: item, playlist: malformedDuration).summary == "Lista de reproducción • 1 canción")
}

@Test func homePlaylistMetadataUsesHomeFallbackAndRealCreatorLinks() {
    var item = playlistMetadataItem("fallback", subtitle: "Lista de reproducción • DJ 42 • 2026 • 1.2M views • 30 canciones • 2 h",
                                    creatorID: "VLnot-a-channel")
    let value = HomePlaylistMetadata.make(item: item, playlist: nil)
    #expect(value.title == "Home title")
    #expect(value.creator == "DJ 42")
    #expect(value.creatorID == nil)
    #expect(value.summary == "Lista de reproducción • 30 canciones • 2 h")
    item.artistRuns = [HomeArtistRunRecord(text: "DJ 42", id: "UCdj")]
    #expect(HomePlaylistMetadata.make(item: item, playlist: nil).creatorID == "UCdj")
    let noMetadata = HomePlaylistMetadata.make(item: playlistMetadataItem("empty"), playlist: nil)
    #expect(noMetadata.summary == "Lista de reproducción")
    #expect(noMetadata.creator == nil)
    let singular = HomePlaylistMetadata.make(item: playlistMetadataItem("one", subtitle: "1 canción"), playlist: nil)
    #expect(singular.summary == "Lista de reproducción • 1 canción")
    #expect(singular.creator == nil)
}

@Test @MainActor func homePlaylistMetadataFetchesFirstPageOnceOnlyForSixUniqueVisiblePlaylists() async {
    let model = HomePlaylistMetadataModel()
    let recorder = PlaylistMetadataRecorder()
    let firstSix = (0..<6).map { playlistMetadataItem("playlist-\($0)") }
    let input = [playlistMetadataItem("album", kind: "album"), firstSix[0]]
        + firstSix + [playlistMetadataItem("outside-visible-page")]
    await model.load(items: input, sessionKey: "a") { id in
        await recorder.record(id)
        return playlistMetadataDetail(id, durations: ["1:00", "2:00"], continuation: "more-songs")
    }
    #expect(await recorder.ids.sorted() == firstSix.map(\.id).sorted())
    #expect(model.details.count == 6)
    #expect(model.display(for: firstSix[0]).summary == "Lista de reproducción")
    await model.load(items: firstSix, sessionKey: "a") { id in
        await recorder.record(id)
        return playlistMetadataDetail(id)
    }
    #expect(await recorder.ids.count == 6)
}

@Test @MainActor func homePlaylistMetadataLimitsRequestsAcrossOverlappingPages() async {
    let model = HomePlaylistMetadataModel()
    let probe = PlaylistMetadataProbe()
    let oldItems = [playlistMetadataItem("old-0"), playlistMetadataItem("old-1")]
    let newItems = (0..<6).map { playlistMetadataItem("new-\($0)") }
    let oldLoad = Task {
        await model.load(items: oldItems, sessionKey: "a") { id in await probe.fetch(id) }
    }
    await probe.waitForStartedCount(2)
    let newLoad = Task {
        await model.load(items: newItems, sessionKey: "a") { id in await probe.fetch(id) }
    }
    for _ in 0..<20 { await Task.yield() }
    #expect(await probe.startedIDs.count == 2)
    #expect(await probe.maximumActiveCount == 2)
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

@Test @MainActor func homePlaylistMetadataKeepsSixRecentDetailsAndCurrentHomeFallback() async {
    let model = HomePlaylistMetadataModel()
    let recorder = PlaylistMetadataRecorder()
    for index in 0..<6 {
        await model.load(items: [playlistMetadataItem("p\(index)")], sessionKey: "a") { id in
            await recorder.record(id)
            return playlistMetadataDetail(id, title: "", durations: [])
        }
    }
    let refreshedHome = playlistMetadataItem("p0", creator: "New Home creator", creatorID: "UCnew")
    await model.load(items: [refreshedHome], sessionKey: "a") { id in
        await recorder.record(id)
        return playlistMetadataDetail(id)
    }
    #expect(await recorder.ids.count == 6)
    #expect(model.display(for: refreshedHome).creator == "New Home creator")
    #expect(model.display(for: refreshedHome).creatorID == "UCnew")
    await model.load(items: [playlistMetadataItem("p6")], sessionKey: "a") { id in
        playlistMetadataDetail(id)
    }
    #expect(model.details.count == 6)
    #expect(model.details["p0"] != nil)
    #expect(model.details["p1"] == nil)
    #expect(model.details["p6"] != nil)
}

@Test @MainActor func homePlaylistMetadataFallsBackOnFailureAndAllowsRetry() async {
    enum FetchError: Error { case offline }
    let model = HomePlaylistMetadataModel()
    let item = playlistMetadataItem("retry", creator: "Home creator")
    await model.load(items: [item], sessionKey: "a") { _ in throw FetchError.offline }
    #expect(model.details.isEmpty)
    #expect(model.display(for: item).title == "Home title")
    #expect(model.display(for: item).creator == "Home creator")
    await model.load(items: [item], sessionKey: "a") { id in
        playlistMetadataDetail(id, title: "Retried")
    }
    #expect(model.display(for: item).title == "Retried")
}

@Test @MainActor func homePlaylistMetadataIgnoresCancelledAndPreviousSessionResponses() async {
    let model = HomePlaylistMetadataModel()
    let probe = PlaylistMetadataProbe()
    let oldItem = playlistMetadataItem("private-old")
    let oldLoad = Task {
        await model.load(items: [oldItem], sessionKey: "account-a") { id in await probe.fetch(id) }
    }
    await probe.waitForStartedCount(1)
    oldLoad.cancel()
    let currentItem = playlistMetadataItem("current")
    await model.load(items: [currentItem], sessionKey: "account-b") { id in
        playlistMetadataDetail(id, title: "Current")
    }
    await probe.finishOne()
    await oldLoad.value
    #expect(model.details.keys.sorted() == ["current"])
    #expect(model.display(for: oldItem).title == "Home title")
    #expect(model.display(for: currentItem, sessionKey: "account-a").title == "Home title")

    let cancelledLoad = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        await model.load(items: [oldItem], sessionKey: "account-a") { id in
            await probe.fetch(id)
        }
    }
    await cancelledLoad.value
    #expect(await probe.startedIDs == ["private-old"])
    #expect(model.details.keys.sorted() == ["current"])
}

@Test @MainActor func homePlaylistMetadataCancellationReleasesQueuedPermitsWithoutFetching() async {
    let model = HomePlaylistMetadataModel()
    let probe = PlaylistMetadataProbe()
    let oldLoad = Task {
        await model.load(items: [playlistMetadataItem("old-0"), playlistMetadataItem("old-1")], sessionKey: "a") { id in
            await probe.fetch(id)
        }
    }
    await probe.waitForStartedCount(2)
    let queuedLoad = Task {
        await model.load(items: [playlistMetadataItem("cancelled")], sessionKey: "a") { id in
            await probe.fetch(id)
        }
    }
    for _ in 0..<20 { await Task.yield() }
    queuedLoad.cancel()
    await queuedLoad.value
    await probe.finishOne()
    await probe.finishOne()
    await oldLoad.value
    await model.load(items: [playlistMetadataItem("current")], sessionKey: "a") { id in
        playlistMetadataDetail(id)
    }
    #expect(await probe.startedIDs.sorted() == ["old-0", "old-1"])
    #expect(model.details.keys.sorted() == ["current"])
}

private actor PlaylistMetadataRecorder {
    private(set) var ids: [String] = []
    func record(_ id: String) { ids.append(id) }
}

private actor PlaylistMetadataProbe {
    private var pending: [(String, CheckedContinuation<PlaylistDetailRecord, Never>)] = []
    private var startedWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var startedIDs: [String] = []
    private(set) var activeCount = 0
    private(set) var maximumActiveCount = 0

    func fetch(_ id: String) async -> PlaylistDetailRecord {
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
        let (id, continuation) = pending.removeFirst()
        activeCount -= 1
        continuation.resume(returning: playlistMetadataDetail(id))
    }
}
