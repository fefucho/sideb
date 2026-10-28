import Foundation
import SideBCore

/// Persistimos solo datos presentables. Cookie y token de continuación nunca llegan al archivo.
struct HomeCachedPage: Codable, Sendable {
    let version: Int
    let savedAt: Date
    let chips: [Chip]
    let sections: [Section]

    struct Chip: Codable, Sendable {
        let title: String
        let params: String
        init(_ record: HomeChipRecord) { title = record.title; params = record.params }
        var record: HomeChipRecord { HomeChipRecord(title: title, params: params) }
    }

    struct ArtistRun: Codable, Sendable {
        let text: String
        let id: String?
    }

    struct Section: Codable, Sendable {
        let title: String
        let format: String
        let items: [Item]
        let moreBrowseId: String?
        let moreParams: String?
        init(_ record: HomeSectionRecord) {
            title = record.title
            switch record.format {
            case .compactSongs: format = "compactSongs"
            case .mixed: format = "mixed"
            case .largeCards: format = "largeCards"
            }
            items = record.items.map(Item.init)
            moreBrowseId = record.moreBrowseId
            moreParams = record.moreParams
        }
        var record: HomeSectionRecord {
            let recordFormat: HomeSectionFormatRecord
            switch format {
            case "compactSongs": recordFormat = .compactSongs
            case "mixed": recordFormat = .mixed
            default: recordFormat = .largeCards
            }
            return HomeSectionRecord(title: title, format: recordFormat, items: items.map(\.record), moreBrowseId: moreBrowseId, moreParams: moreParams)
        }
    }

    struct Item: Codable, Sendable {
        let kind: String
        let id: String
        let title: String
        let subtitle: String?
        let thumbnail: String?
        let duration: String?
        let artists: String?
        let artistId: String?
        let album: String?
        let albumId: String?
        let artistRuns: [ArtistRun]
        let explicit: Bool
        let contentRating: String?
        init(_ record: HomeItemRecord) {
            kind = record.kind; id = record.id; title = record.title
            subtitle = record.subtitle; thumbnail = record.thumbnail; duration = record.duration
            artists = record.artists; artistId = record.artistId; album = record.album; albumId = record.albumId
            artistRuns = record.artistRuns.map { ArtistRun(text: $0.text, id: $0.id) }
            explicit = record.explicit
            contentRating = ContentRatingMetadata.encode(record.effectiveContentRating)
        }
        var record: HomeItemRecord {
            HomeItemRecord(kind: kind, id: id, title: title, subtitle: subtitle, thumbnail: thumbnail,
                           duration: duration, artists: artists, artistId: artistId, album: album, albumId: albumId,
                           artistRuns: artistRuns.map { HomeArtistRunRecord(text: $0.text, id: $0.id) }, explicit: explicit,
                           contentRating: ContentRatingMetadata.decode(contentRating, legacyExplicit: explicit))
        }
    }

    init(_ page: HomePageRecord) {
        version = 2
        savedAt = Date()
        chips = page.chips.map(Chip.init)
        sections = page.sections.map(Section.init)
    }

    var page: HomePageRecord {
        HomePageRecord(chips: chips.map(\.record), sections: sections.map(\.record), continuation: nil)
    }
}

actor HomeFeedCacheStore {
    private let directory: URL
    private var activeTokens: [String: String] = [:]

    init(directory: URL = HomeLabConfiguration.appSupportURL.appendingPathComponent("HomeFeed", isDirectory: true)) {
        self.directory = directory
    }

    func activate(_ key: String, token: String) { activeTokens[key] = token }

    func load(for key: String, token: String) -> HomeCachedPage? {
        guard activeTokens[key] == token,
              let data = try? Data(contentsOf: fileURL(for: key)),
              let page = try? JSONDecoder().decode(HomeCachedPage.self, from: data),
              page.version == 2 else { return nil }
        return page
    }

    func save(_ page: HomeCachedPage, for key: String, token: String) {
        guard activeTokens[key] == token else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = fileURL(for: key)
            let data = try JSONEncoder().encode(page)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            #if DEBUG
            print("[HomeFeedCacheStore] No se pudo guardar el feed: \(error)")
            #endif
        }
    }

    func retire(_ key: String, token: String) {
        guard activeTokens[key] == token else { return }
        activeTokens.removeValue(forKey: key)
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent("home-\(key).json")
    }
}
