import AppKit
import SideBCore
import Testing
@testable import SideB

private func jamSong(_ id: String) -> SongItemRecord {
    SongItemRecord(videoId: id, title: "Song \(id)", artists: "Artist", album: nil, duration: "3:00",
        thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil, isVideo: false, isUpload: false, library: nil)
}

private func jamEntry(_ index: Int, _ status: JamQueueEntry.Status, provider: String? = "queue") -> JamQueueEntry {
    let track = JamTrack(uri: "spotify:track:\(index)", title: "Jam \(index)", artists: ["Artist"], album: nil,
                         durationMs: 183_000, isrc: nil, provider: provider)
    return JamQueueEntry(id: "spotify:track:\(index)#0", index: index, track: track,
                         song: status == .matched ? jamSong("v\(index)") : nil, status: status)
}

private func mergeEntries(_ entries: [JamQueueEntry]) -> [JamQueueMerge.Entry] { entries.map(JamQueueMerge.Entry.init) }
private func occurrences(_ entries: [JamQueueEntry]) -> [JamQueueMerge.Occurrence] {
    entries.filter { $0.status == .matched }.map { .init(id: "occ-\($0.index)", videoID: "v\($0.index)") }
}

@Suite("Jam: queue surfaces")
struct JamSurfacesTests {
    @Test("The merge keeps Jam order and puts placeholders where tracks cannot play")
    func mergeKeepsJamOrder() {
        let entries = [jamEntry(0, .matched), jamEntry(1, .unavailable), jamEntry(2, .resolving), jamEntry(3, .matched)]
        let items = JamQueueMerge.merge(entries: mergeEntries(entries), upcoming: occurrences(entries))
        #expect(items.count == 4)
        guard case .occurrence(let first, let entry0) = items[0], case .placeholder(let gone, let goneResolving) = items[1],
              case .placeholder(let wait, let waitResolving) = items[2], case .occurrence(let last, _) = items[3] else {
            Issue.record("unexpected shape \(items)"); return
        }
        #expect(first == "occ-0" && entry0?.index == 0)
        #expect(gone.index == 1 && !goneResolving)
        #expect(wait.index == 2 && waitResolving)
        #expect(last == "occ-3")
    }

    @Test("An unreliable pairing never relabels rows")
    func mergeFallsBackWithoutPairing() {
        let entries = [jamEntry(0, .matched), jamEntry(1, .matched)]
        // The mirror still holds an older queue.
        let stale = [JamQueueMerge.Occurrence(id: "old", videoID: "other")]
        let items = JamQueueMerge.merge(entries: mergeEntries(entries), upcoming: stale)
        #expect(items == [.occurrence(id: "old", entry: nil)])
        // Nothing mirrored yet: the Jam list shows as placeholders still being matched.
        let none = JamQueueMerge.merge(entries: mergeEntries(entries + [jamEntry(2, .unavailable)]), upcoming: [])
        #expect(none.count == 3)
        if case .placeholder(_, let resolving) = none[0] { #expect(resolving) } else { Issue.record("expected placeholder") }
        if case .placeholder(_, let resolving) = none[2] { #expect(!resolving) } else { Issue.record("expected placeholder") }
        #expect(JamQueueMerge.merge(entries: [], upcoming: []).isEmpty)
    }

    @Test("Rows are numbered in Jam order, the playing track being 1")
    func numbering() {
        #expect(JamQueueMerge.displayNumber(forEntryIndex: 0) == 2)
        #expect(JamQueueMerge.displayNumber(forEntryIndex: 4) == 6)
    }

    @Test("The marker tells a person from a Spotify suggestion")
    func markers() {
        #expect(JamRowMarker(jamEntry(0, .matched, provider: "queue")) == .addedByPerson)
        #expect(JamRowMarker(jamEntry(0, .matched, provider: "context")) == .spotifySuggestion)
        #expect(JamRowMarker(jamEntry(0, .matched, provider: nil)) == .spotifySuggestion)
    }

    @Test("The sidebar preview is bounded and keeps unavailable rows")
    func sidebarPreview() {
        let entries = [jamEntry(0, .unavailable), jamEntry(1, .matched), jamEntry(2, .matched)]
        let rows = SidebarJamPreviewRow.preview(entries)
        #expect(rows.map(\.status) == [.unavailable, .matched])
        #expect(rows[0].duration == "3:03")
        #expect(rows[1].duration == "3:00")
        #expect(SidebarJamPreviewRow.preview(entries, limit: 0).isEmpty)
    }

    @Test("The badge overlays the artwork card and never needs more than the header offset")
    func badgePlacement() {
        let tall = JamSidebarBadgePlacement.top(width: 380, height: 700, portrait: false)
        #expect(tall >= 58 + JamSidebarBadgePlacement.inset)
        #expect(tall <= 58 + 12 + JamSidebarBadgePlacement.inset)
        #expect(JamSidebarBadgePlacement.top(width: 380, height: 700, portrait: true) == 66)
    }

    @Test("Durations read as m:ss")
    func durations() {
        #expect(JamDuration.text(milliseconds: 61_400) == "1:01")
        #expect(JamDuration.text(milliseconds: nil) == nil)
        #expect(JamDuration.text(milliseconds: 0) == nil)
    }

    @Test("The Jam entry is part of the fullscreen switcher and flips its glyph when live")
    func panelEntry() {
        #expect(FullscreenPanel.allCases.contains(.jam))
        #expect(FullscreenPanel.jam.symbol(jamLive: true) != FullscreenPanel.jam.symbol(jamLive: false))
        #expect(FullscreenPanel.queue.symbol(jamLive: true) == FullscreenPanel.queue.symbol(jamLive: false))
    }

    @Test("The header names the host")
    func header() {
        let entries: [JamQueueEntry] = []
        #expect(JamQueueContext(host: "Ana", entries: entries).title == L10n.text("jam.live.title", args: ["Ana"]))
        #expect(JamQueueContext(host: nil, entries: entries).title == L10n.text("jam.live.titleNoHost"))
    }

    @MainActor
    @Test("The queue list mirrors the Jam, hides recommendations and keeps playable identities")
    func queueRowsDuringJam() throws {
        let player = PlayerViewModel(rustCore: nil)
        let q = player.queueManager
        let entries = [jamEntry(0, .matched), jamEntry(1, .unavailable), jamEntry(2, .resolving), jamEntry(3, .matched, provider: "context")]
        q.mirrorSession(current: jamSong("now"), upcoming: entries.compactMap(\.song), title: "Spotify Jam")
        player.currentTrack = q.currentTrack
        // Recommendations must stay out even if the manager held some.
        q.appendRadioTracks([jamSong("rec1"), jamSong("rec2")])
        let view = NativeSeparatedQueueView(manager: q, revision: q.presentationRevision, player: player, router: nil,
            liked: [], playing: false, loading: false, error: nil, jam: JamQueueContext(host: "Ana", entries: entries))
        let coordinator = view.makeCoordinator()
        coordinator.buildRows()
        #expect(coordinator.rows.count == 6)
        #expect(coordinator.rows[0] == .heading("queue.now"))
        #expect(!coordinator.rows.contains(.heading("queue.recommendations")))
        #expect(coordinator.proposalIndices.isEmpty)
        #expect(!coordinator.rows.contains(.more))
        #expect(coordinator.rows[3] == .jamPending(entries[1].id))
        #expect(coordinator.rows[4] == .jamPending(entries[2].id))
        let firstID = q.occurrenceIDs[1], lastID = q.occurrenceIDs[2]
        #expect(coordinator.rows[2] == .committed(firstID))
        #expect(coordinator.rows[5] == .committed(lastID))
        #expect(coordinator.jamByOccurrence[firstID]?.isAddedByPerson == true)
        #expect(coordinator.jamByOccurrence[lastID]?.isSpotifySuggestion == true)
        #expect(coordinator.jamPlaceholders[entries[1].id]?.resolving == false)
        #expect(coordinator.jamPlaceholders[entries[2].id]?.resolving == true)
        // Placeholders offer no menu, and a drop on one lands after it.
        #expect(coordinator.menu(row: 3) == nil)
        #expect(coordinator.resolvedDropRow(3) == 5)
        #expect(coordinator.destination(3) == 2)
        #expect(coordinator.destination(6) == q.queue.count)
        // Outside a Jam the same manager keeps its normal layout.
        let plain = NativeSeparatedQueueView(manager: q, revision: q.presentationRevision, player: player, router: nil,
            liked: [], playing: false, loading: false, error: nil).makeCoordinator()
        plain.buildRows()
        #expect(plain.jamPlaceholders.isEmpty)
        #expect(!plain.rows.contains { if case .jamPending = $0 { true } else { false } })
        player.audioService.stop()
    }
}
