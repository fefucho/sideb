import Testing
import SideBCore
@testable import SideB

@MainActor struct ProviderSearchPageSnapshotTests {
    private func section(_ index: Int, title: String = "", principal: Bool = false) -> SearchSectionRecord {
        let card = BrowseCardRecord(kind: "song", id: "repeated", title: "Occurrence \(index)",
            subtitle: "Artist", thumbnail: nil, duration: "3:00")
        let song = SongItemRecord(videoId: "repeated", title: card.title, artists: "Artist", album: nil,
            duration: "3:00", thumbnail: nil, artistId: nil, albumId: nil,
            setVideoId: "opaque-\(index)", isVideo: false, isUpload: false, library: nil)
        return SearchSectionRecord(id: "same-provider-id", title: title,
            layout: principal ? "top" : "list", items: [card], songs: [song],
            primaryItemIndex: principal ? 0 : nil, relatedItemIndices: [],
            moreQuery: nil, moreParams: nil, moreBrowseId: nil, actions: [])
    }

    @Test func emptySectionTitlesAddNoGapsAndDuplicateOccurrencesKeepTheirPayload() {
        let sections = (0..<5_000).map { section($0) }
        let page = SearchPageRecord(chips: [], correction: nil, sections: sections, continuation: nil)
        let snapshot = ProviderSearchPageSnapshot()
        snapshot.prepare(page: page, revision: 1, expanded: [], loading: false, error: nil, loadingMore: false, localization: "es")
        #expect(snapshot.entries.count == 5_000)
        #expect(snapshot.entries.allSatisfy { $0.kind == .row && $0.height == 58 })
        #expect(Set(snapshot.entries.map(\.id)).count == 5_000)
        #expect(snapshot.sections[0].songs[0]?.setVideoId == "opaque-0")
        #expect(snapshot.sections[4_999].songs[0]?.setVideoId == "opaque-4999")
        #expect(snapshot.sections[4_999].songs[0]?.title == "Occurrence 4999")

        for _ in 0..<20 {
            snapshot.prepare(page: page, revision: 1, expanded: [], loading: false, error: nil, loadingMore: false, localization: "es")
        }
        #expect(snapshot.projectionCount == 1)
        #expect(snapshot.revision == 1)

        snapshot.prepare(page: page, revision: 1, expanded: ["0:same-provider-id"], loading: false,
            error: nil, loadingMore: true, localization: "es")
        #expect(snapshot.projectionCount == 1, "Expansion and footer state reuse prepared occurrence payloads")
    }

    @Test func principalTitleIsNotRepeatedAndRetiringPageRemovesItsContents() {
        let page = SearchPageRecord(chips: [], correction: nil,
            sections: [section(0, title: "Occurrence 0", principal: true)], continuation: nil)
        let snapshot = ProviderSearchPageSnapshot()
        snapshot.prepare(page: page, revision: 1, expanded: [], loading: false, error: nil, loadingMore: false, localization: "en")
        #expect(snapshot.entries.count == 1)
        #expect(snapshot.entries[0].kind == .principal)
        snapshot.prepare(page: nil, revision: 2, expanded: [], loading: true, error: nil, loadingMore: false, localization: "en")
        #expect(snapshot.sections.isEmpty)
        #expect(snapshot.entries.count == 1)
        #expect(snapshot.entries[0].id == AnyHashable("loading"))
        #expect(snapshot.content.count == 1)
    }

    @Test func appendPreservesPrincipalMeasurementUntilContentExpansionOrLanguageChanges() {
        let principal = section(0, title: "Occurrence 0", principal: true)
        let snapshot = ProviderSearchPageSnapshot()
        snapshot.prepare(page: SearchPageRecord(chips: [], correction: nil, sections: [principal], continuation: nil),
            revision: 1, expanded: [], loading: false, error: nil, loadingMore: false, localization: "en")
        let initial = snapshot.entries[0].measurementRevision
        snapshot.prepare(page: SearchPageRecord(chips: [], correction: nil, sections: [principal, section(1)], continuation: nil),
            revision: 2, expanded: [], loading: false, error: nil, loadingMore: false, localization: "en")
        #expect(snapshot.entries[0].measurementRevision == initial)
        snapshot.prepare(page: SearchPageRecord(chips: [], correction: nil, sections: [principal, section(1)], continuation: nil),
            revision: 2, expanded: ["0:same-provider-id"], loading: false, error: nil, loadingMore: false, localization: "en")
        #expect(snapshot.entries[0].measurementRevision != initial)
        let expanded = snapshot.entries[0].measurementRevision
        snapshot.prepare(page: SearchPageRecord(chips: [], correction: nil, sections: [principal, section(1)], continuation: nil),
            revision: 2, expanded: ["0:same-provider-id"], loading: false, error: nil, loadingMore: false, localization: "es")
        #expect(snapshot.entries[0].measurementRevision != expanded)
    }
}
