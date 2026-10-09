import Foundation
import Observation
import SideBCore

struct HomeAlbumMetadata: Equatable {
    private let originalTitle: String
    var title: String { originalTitle.isEmpty ? L10n.text("metadata.album") : originalTitle }
    let artist: String?
    let artistID: String?
    private let year: String?
    private let trackCount: Int?
    private let duration: String?

    var summary: String {
        var parts = [L10n.text("metadata.album")]
        if let year { parts.append(year) }
        if let trackCount { parts.append(L10n.songCount(trackCount)) }
        if let duration { parts.append(duration) }
        return parts.joined(separator: " • ")
    }

    static func make(item: HomeItemRecord, album: AlbumDetailRecord?) -> Self {
        let title = clean(album?.title) ?? clean(item.title) ?? ""
        let artist = clean(album?.artist)
            ?? cleanArtist(item.artists)
            ?? cleanArtist(item.artistRuns.map(\.text).joined(separator: " • "))
            ?? artistFromSubtitle(item.subtitle)
        let artistID = clean(album?.artistId)
            ?? clean(item.artistId)
            ?? item.artistRuns.first(where: { $0.id?.isEmpty == false })?.id

        let year = year(in: album?.subtitle) ?? year(in: item.subtitle)
        var trackCount: Int?
        var duration: String?
        if let album {
            let count = album.items.isEmpty ? providerTrackCount(album.secondSubtitle) : album.items.count
            trackCount = count
            duration = albumDuration(album)
        }
        return Self(originalTitle: title, artist: artist, artistID: artistID, year: year, trackCount: trackCount, duration: duration)
    }

    private static func providerTrackCount(_ value: String?) -> Int? {
        guard let value, let range = value.range(of: #"(?i)\b\d+\s+(?:songs?|tracks?|canciones?|pistas?)\b"#, options: .regularExpression) else { return nil }
        return Int(value[range].prefix(while: { $0.isNumber }))
    }

    private static func albumDuration(_ album: AlbumDetailRecord) -> String? {
        let durations = album.items.map { HomeCollectionMetadataFormatting.seconds(from: $0.duration) }
        if !durations.isEmpty, durations.allSatisfy({ $0 != nil }) {
            return HomeCollectionMetadataFormatting.formatDuration(durations.reduce(0) { $0 + ($1 ?? 0) })
        }
        guard let provider = album.secondSubtitle else { return nil }
        return HomeCollectionMetadataFormatting.providerDuration(provider)
    }

    private static func year(in value: String?) -> String? {
        guard let value else { return nil }
        let pattern = #"(?<!\d)(?:19|20)\d{2}(?!\d)"#
        guard let range = value.range(of: pattern, options: .regularExpression) else { return nil }
        return String(value[range])
    }

    private static func artistFromSubtitle(_ value: String?) -> String? {
        guard let value else { return nil }
        let parts = value.components(separatedBy: CharacterSet(charactersIn: "•·"))
        let remaining = parts.filter { part in
            let normalized = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !isMetadataComponent(normalized)
        }
        return cleanArtist(remaining.joined(separator: " • "))
    }

    private static func cleanArtist(_ value: String?) -> String? {
        guard let value else { return nil }
        let parts = value.components(separatedBy: CharacterSet(charactersIn: "•·"))
            .compactMap(clean)
            .filter { part in
                let normalized = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !isMetadataComponent(normalized)
            }
        return clean(parts.joined(separator: " • "))
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func isMetadataComponent(_ value: String) -> Bool {
        if value == "álbum" || value == "album" { return true }
        if value.range(of: #"^(?:19|20)\d{2}$"#, options: .regularExpression) != nil { return true }
        return value.range(of: #"^\d+\s*(?:songs?|tracks?|canciones?|pistas?|hours?|hrs?|horas?|h|minutes?|mins?|minutos?|m|seconds?|secs?|segundos?|s)$"#,
                           options: [.regularExpression, .caseInsensitive]) != nil
    }
}

@MainActor @Observable
final class HomeAlbumMetadataModel {
    private(set) var details: [String: HomeAlbumMetadata] = [:]
    private var cachedAlbums: [String: AlbumDetailRecord] = [:]
    private var lru: [String] = []
    private var sessionKey: String?
    private var generation = 0
    @ObservationIgnored private let requestLimiter = HomeCollectionMetadataRequestLimiter()

    func display(for item: HomeItemRecord, sessionKey requestedSessionKey: String? = nil) -> HomeAlbumMetadata {
        if let requestedSessionKey, requestedSessionKey != sessionKey {
            return HomeAlbumMetadata.make(item: item, album: nil)
        }
        if let details = details[item.id] { return details }
        return HomeAlbumMetadata.make(item: item, album: cachedAlbums[item.id])
    }

    func load(items: [HomeItemRecord], core: SideBCore?, sessionKey: String) async {
        await load(items: items, sessionKey: sessionKey) { id in
            guard let core else { throw MetadataLoadError.unavailable }
            return try await core.getAlbum(browseId: id)
        }
    }

    func load(items: [HomeItemRecord], sessionKey: String,
              fetch: @escaping @Sendable (String) async throws -> AlbumDetailRecord) async {
        guard !Task.isCancelled else { return }
        if self.sessionKey != sessionKey {
            self.sessionKey = sessionKey
            clearCache()
        }
        generation += 1
        let requestGeneration = generation
        var seen = Set<String>()
        let visibleIDs = items.prefix(6).filter { $0.kind == "album" }.map(\.id)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        for id in visibleIDs where cachedAlbums[id] != nil { touch(id) }
        let missing = visibleIDs.filter { cachedAlbums[$0] == nil }
        guard !missing.isEmpty else { return }

        let limiter = requestLimiter
        await withTaskGroup(of: (String, AlbumDetailRecord?).self) { group in
            var nextIndex = 0
            var activeCount = 0
            while nextIndex < min(2, missing.count) {
                let id = missing[nextIndex]
                nextIndex += 1
                group.addTask {
                    (id, try? await limiter.fetch { try await fetch(id) })
                }
                activeCount += 1
            }
            while activeCount > 0, let (id, album) = await group.next() {
                activeCount -= 1
                guard !Task.isCancelled, generation == requestGeneration else {
                    group.cancelAll()
                    return
                }
                if let album {
                    cachedAlbums[id] = album
                    touch(id)
                    if let item = items.first(where: { $0.id == id }) {
                        details[id] = HomeAlbumMetadata.make(item: item, album: album)
                    }
                }
                guard !Task.isCancelled, generation == requestGeneration else {
                    group.cancelAll()
                    return
                }
                if nextIndex < missing.count {
                    let nextID = missing[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        (nextID, try? await limiter.fetch { try await fetch(nextID) })
                    }
                    activeCount += 1
                }
            }
        }
    }

    private func touch(_ id: String) {
        lru.removeAll { $0 == id }
        lru.append(id)
        while lru.count > 6 {
            let evicted = lru.removeFirst()
            cachedAlbums.removeValue(forKey: evicted)
            details.removeValue(forKey: evicted)
        }
    }

    private func clearCache() {
        cachedAlbums.removeAll()
        details.removeAll()
        lru.removeAll()
    }

    private enum MetadataLoadError: Error { case unavailable }
}

/// Shared formatting for provider summaries, without loading additional collection pages.
enum HomeCollectionMetadataFormatting {
    static func seconds(from raw: String?) -> Int? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if isDigits(raw), let value = Int(raw) { return value }
        let components = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard (components.count == 2 || components.count == 3),
              components.allSatisfy({ isDigits(String($0)) }) else { return nil }
        var values: [Int] = []
        for component in components {
            guard let value = Int(component) else { return nil }
            values.append(value)
        }
        if components.count == 2, values[1] < 60 { return values[0] * 60 + values[1] }
        if components.count == 3, values[1] < 60, values[2] < 60 {
            return values[0] * 3600 + values[1] * 60 + values[2]
        }
        return nil
    }

    private static func isDigits(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    static func providerDuration(_ raw: String, acceptsBareSeconds: Bool = true) -> String? {
        let pattern = #"(?i)(\d+)\s*(hours?|hrs?|horas?|h)\b|(\d+)\s*(minutes?|mins?|minutos?|m)\b|(\d+)\s*(seconds?|secs?|segundos?|s)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for segment in raw.components(separatedBy: CharacterSet(charactersIn: "•·")) {
            let ns = segment as NSString
            let matches = regex.matches(in: segment, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            var remainder = segment
            var total = 0
            for match in matches.reversed() {
                remainder = (remainder as NSString).replacingCharacters(in: match.range, with: " ")
            }
            let residual = remainder.replacingOccurrences(of: #"(?i)\band\b"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,;\t\n\r"))
            guard residual.isEmpty else { continue }
            for match in matches {
                var parsed = false
                for group in stride(from: 1, through: 5, by: 2) where match.range(at: group).location != NSNotFound {
                    guard let number = Int(ns.substring(with: match.range(at: group))) else { continue }
                    let unit = ns.substring(with: match.range(at: group + 1)).lowercased()
                    if unit.hasPrefix("h") { total += number * 3600 }
                    else if unit == "m" || unit.hasPrefix("min") { total += number * 60 }
                    else { total += number }
                    parsed = true
                    break
                }
                if !parsed { total = 0; break }
            }
            if total > 0 { return formatDuration(total) }
        }
        for segment in raw.components(separatedBy: CharacterSet(charactersIn: "•·")) {
            if !acceptsBareSeconds && !segment.contains(":") { continue }
            if let value = seconds(from: segment) { return formatDuration(value) }
        }
        return nil
    }

    static func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min" }
        if minutes > 0 { return "\(minutes) min" }
        return "\(seconds) s"
    }

}
