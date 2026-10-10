import Foundation
import SideBCore

/// Home/Browse subtitles are presentation text. An album destination does not
/// make a positional count its name. Canonical Song/Album records bypass this policy.
enum HomeSongMetadata {
    static func clean(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func parts(_ text: String?) -> [String] {
        (text ?? "").components(separatedBy: CharacterSet(charactersIn: "•·")).compactMap { clean($0) }
    }

    static func isStatistic(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).range(
            of: #"^\d[\d.,\s]*(?:k|m|b|mil|millón|millon|millones|millions?|billions?)?\s*(?:de\s+)?(?:plays?|views?|streams?|listeners?|subscribers?|reproducciones|visualizaciones|vistas|oyentes|suscriptores)$"#,
            options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isDuration(_ text: String) -> Bool {
        text.range(of: #"^\d+(?::\d{2}){1,2}$"#, options: .regularExpression) != nil
    }

    static func isDescriptor(_ text: String) -> Bool {
        ["song", "canción", "cancion", "video", "vídeo", "album", "álbum", "single", "sencillo", "ep", "playlist", "lista", "mix"].contains(text.lowercased())
    }

    static func artist(subtitle: String?, explicit: String? = nil, fallback: String? = nil) -> String {
        let credits = parts(explicit).filter { !isStatistic($0) && !isDuration($0) && !isDescriptor($0) }
        // A bullet is a legacy artist/album delimiter in SongItemRecord display.
        // Collaborators must not manufacture a fallback album when the real name is absent.
        if !credits.isEmpty { return credits.joined(separator: ", ") }
        return parts(subtitle).first { !isStatistic($0) && !isDuration($0) && !isDescriptor($0)
            && $0.range(of: #"^(?:19|20)\d{2}$"#, options: .regularExpression) == nil } ?? fallback ?? ""
    }

    static func artist(from item: HomeItemRecord) -> String {
        // Linked artist runs retain their original names and all collaborators.
        let runs = artistRuns(from: item)
        if runs.contains(where: { clean($0.id) != nil }) {
            let name = runs.reduce("") { text, run in
                let adjacentNames = text.last.map { $0.isLetter || $0.isNumber } == true
                    && run.text.first.map { $0.isLetter || $0.isNumber } == true
                return text + (adjacentNames ? ", " : "") + run.text
            }.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return artist(subtitle: item.subtitle, explicit: item.artists)
    }

    static func artistRuns(from item: HomeItemRecord) -> [HomeArtistRunRecord] {
        var groups: [[Int]] = [[]]
        for (index, run) in item.artistRuns.enumerated() {
            if ["•", "·"].contains(run.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                groups.append([])
            } else { groups[groups.count - 1].append(index) }
        }
        var rejected = Set<Int>()
        for group in groups {
            let text = group.map { item.artistRuns[$0].text }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if !group.contains(where: { clean(item.artistRuns[$0].id) != nil }),
               isStatistic(text) || isDuration(text) || isDescriptor(text) {
                rejected.formUnion(group)
            }
            for index in group {
                let run = item.artistRuns[index]
                let text = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if clean(run.id) == nil, isStatistic(text) || isDuration(text) || isDescriptor(text) {
                    rejected.insert(index)
                }
            }
        }
        var result = item.artistRuns.enumerated().filter { !rejected.contains($0.offset) }.map(\.element)
        let separators = CharacterSet(charactersIn: " •·,;&\n\t")
        while result.first.map({ clean($0.id) == nil && $0.text.trimmingCharacters(in: separators).isEmpty }) == true { result.removeFirst() }
        while result.last.map({ clean($0.id) == nil && $0.text.trimmingCharacters(in: separators).isEmpty }) == true { result.removeLast() }
        return result.map { run in
            clean(run.id) == nil && ["•", "·"].contains(run.text.trimmingCharacters(in: .whitespacesAndNewlines))
                ? HomeArtistRunRecord(text: ", ", id: nil) : run
        }
    }

    static func album(from item: HomeItemRecord) -> String? {
        if let value = clean(item.album) {
            return isStatistic(value) || isDuration(value) ? nil : value
        }
        guard clean(item.albumId) != nil else { return nil }
        var fields = parts(item.subtitle)
        while fields.first.map(isDescriptor) == true { fields.removeFirst() }
        // The first non-type field is the artist. Only eligible album text may follow.
        let artists = parts(item.artists) + item.artistRuns.filter { clean($0.id) != nil }.map(\.text)
        return fields.dropFirst().first { candidate in !isStatistic(candidate) && !isDuration(candidate) && !isDescriptor(candidate)
            && !artists.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame })
            && candidate.range(of: #"^(?:19|20)\d{2}$"#, options: .regularExpression) == nil }
    }
}

/// AlbumDetail is authoritative. Radio's SongItem can still originate from a
/// positional subtitle, so statistic-shaped radio labels require album verification.
enum PlaybackAlbumMetadata {
    static func merging(_ current: SongItemRecord, radio: SongItemRecord) -> SongItemRecord {
        guard current.videoId == radio.videoId else { return current }
        var result = current
        let currentID = HomeSongMetadata.clean(current.albumId)
        let canonicalID = HomeSongMetadata.clean(radio.albumId)
        guard currentID == nil || canonicalID == nil || currentID == canonicalID else { return current }
        // If a destination is already known, the incoming label needs that same destination.
        if HomeSongMetadata.clean(current.album) == nil,
           currentID == nil || currentID == canonicalID {
            result.albumId = currentID ?? canonicalID // Destination survives an ambiguous label.
            if let title = HomeSongMetadata.clean(radio.album),
               !HomeSongMetadata.isStatistic(title), !HomeSongMetadata.isDuration(title) {
                result.album = title
            }
        } else if currentID == nil,
                  let title = HomeSongMetadata.clean(current.album),
                  let incoming = HomeSongMetadata.clean(radio.album),
                  title.caseInsensitiveCompare(incoming) == .orderedSame {
            result.albumId = canonicalID
        }
        return result
    }

    static func merging(_ current: SongItemRecord, album: AlbumDetailRecord) -> SongItemRecord {
        guard HomeSongMetadata.clean(current.album) == nil,
              let target = HomeSongMetadata.clean(current.albumId), target == album.browseId,
              album.items.contains(where: { $0.videoId == current.videoId }),
              let title = HomeSongMetadata.clean(album.title) else { return current }
        var result = current
        result.album = title // Canonical names such as "100 Plays" are never filtered.
        return result
    }
}
