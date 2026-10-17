import Foundation
import SideBCore

struct FeaturedArtistCandidate: Sendable, Codable {
    let id: String
    let name: String
    let subtitle: String?
    init(id: String, name: String, subtitle: String? = nil) { self.id = id; self.name = name; self.subtitle = subtitle }
}
struct FeaturedCredit: Identifiable, Equatable {
    var id: String { "\(range.location):\(range.length)" }
    let range: NSRange
    let name: String
    var destinationID: String?
    var provenance = "unresolved"
}
enum FeaturedArtistParser {
    static func normalize(_ name: String) -> String {
        name.precomposedStringWithCompatibilityMapping.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func clauses(_ title: String) -> [FeaturedCredit] {
        let expression = try! NSRegularExpression(pattern: #"\b(?:feat\.?|ft\.?|featuring)\s+|(?<=[(\[])\s*(?:with|con)\s+"#, options: [.caseInsensitive])
        let ending = try! NSRegularExpression(pattern: #"[)\]]|\s+-\s+(?:remaster|live|version|edit|mix)\b|\s+\((?:remaster|live|version|edit|mix)\b"#, options: [.caseInsensitive])
        let text = title as NSString
        var credits: [FeaturedCredit] = []
        for marker in expression.matches(in: title, range: NSRange(location: 0, length: text.length)) {
            let start = NSMaxRange(marker.range)
            guard !credits.contains(where: { start < NSMaxRange($0.range) }) else { continue }
            var end = ending.firstMatch(in: title, range: NSRange(location: start, length: text.length - start))?.range.location ?? text.length
            while end > start, UnicodeScalar(text.character(at: end - 1)).map({ CharacterSet.whitespacesAndNewlines.contains($0) }) == true { end -= 1 }
            if end > start { let range = NSRange(location: start, length: end - start); credits.append(FeaturedCredit(range: range, name: text.substring(with: range))) }
        }
        return credits
    }
    static func separators(_ text: String) -> [NSRange] {
        let expression = try! NSRegularExpression(pattern: #"\s*(?:,|&|/|\band\b|\by\b)\s*"#, options: [.caseInsensitive])
        return expression.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).prefix(5).map(\.range)
    }
    static func compatible(_ target: String, _ candidate: String) -> Int {
        let a = normalize(target), b = normalize(candidate)
        if a == b { return 100 }
        let aa = Array(a), bb = Array(b)
        guard aa.count >= 5, abs(aa.count - bb.count) <= 2, a.split(separator: " ").count == b.split(separator: " ").count else { return 0 }
        var row = Array(0...bb.count)
        for i in 1...aa.count {
            var previous = row[0]; row[0] = i
            for j in 1...bb.count { let old = row[j]; row[j] = min(row[j]+1, row[j-1]+1, previous + (aa[i-1] == bb[j-1] ? 0 : 1)); previous = old }
        }
        return row[bb.count] <= max(1, aa.count / 10) ? 80 : 0
    }
    static func rank(_ name: String, _ candidates: [FeaturedArtistCandidate]) -> [FeaturedArtistCandidate] {
        var seen = Set<String>()
        return candidates.enumerated().filter { !$0.element.id.isEmpty && compatible(name, $0.element.name) > 0 && seen.insert($0.element.id).inserted }
            .sorted { a,b in let aa = compatible(name,a.element.name), bb = compatible(name,b.element.name); return aa == bb ? a.offset < b.offset : aa > bb }.map(\.element)
    }
}

/// Presentation overlay: never writes inferred destinations into provider records.
@MainActor final class FeaturedArtistResolver {
    static let shared = FeaturedArtistResolver()
    typealias Search = (String) async throws -> [FeaturedArtistCandidate]
    struct Resolution: Codable, Equatable { let id: String?; let provenance: String; let time: Date; var contextualComplete:Bool? = nil }
    private var search: Search?
    private var scope = "guest"
    private var generation = 0
    var scopeRevision: Int { generation }
    private var cache: [String: Resolution] = [:]
    private var lru: [String] = []
    private var choices: [String: Resolution] = [:]
    private final class Flight {
        let id = UUID();let task:Task<Resolution,Never>;var consumers:Set<UUID> = []
        init(_ task:Task<Resolution,Never>) { self.task = task }
    }
    private var flights: [String: Flight] = [:]
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func configure(search: @escaping Search, scope: String) {
        self.search = search
        guard self.scope != scope || generation == 0 else { return }
        self.scope = scope; generation += 1
        flights.values.forEach { $0.task.cancel() }; flights.removeAll(); cache.removeAll(); lru.removeAll()
        choices = (defaults.data(forKey:"featured.choices.v1:\(scope)").flatMap { try? JSONDecoder().decode([String:Resolution].self,from:$0) } ?? [:]).filter { $0.value.id?.isEmpty == false && $0.value.provenance == "userChoice" }
        cache = (defaults.data(forKey:"featured.cache.v1:\(scope)").flatMap { try? JSONDecoder().decode([String:Resolution].self,from:$0) } ?? [:]).filter { valid($0.value) }
        lru = cache.sorted { $0.value.time < $1.value.time }.map(\.key)
        while lru.count > 500 { cache.removeValue(forKey:lru.removeFirst()) }
    }
    private func valid(_ value: Resolution) -> Bool {
        ["inferred","unresolved"].contains(value.provenance) && value.time.timeIntervalSinceNow <= 0 && -value.time.timeIntervalSinceNow < (value.id == nil ? 600 : 604800) && value.id?.isEmpty != true
    }
    private func saveCache() { if let data = try? JSONEncoder().encode(cache) { defaults.set(data,forKey:"featured.cache.v1:\(scope)") } }
    private func key(_ track: SongItemRecord, _ name: String) -> String {
        ["ytmusic",scope,track.videoId,track.title,track.artists,track.album ?? "",FeaturedArtistParser.normalize(name),"v1"].map { "\($0.utf8.count):\($0)" }.joined()
    }
    func providerID(_ track: SongItemRecord, _ name: String) -> String? {
        let normalized = FeaturedArtistParser.normalize(name)
        if let run = track.artistRuns.first(where: { $0.id?.isEmpty == false && FeaturedArtistParser.normalize($0.text) == normalized }) { return run.id }
        return FeaturedArtistParser.normalize(track.artists) == normalized ? track.artistId : nil
    }
    func choose(_ track: SongItemRecord, name: String, id: String?) {
        let key = key(track,name)
        if let id, !id.isEmpty { choices[key] = Resolution(id: id, provenance: "userChoice", time: Date()) } else { choices.removeValue(forKey: key) }
        if let data = try? JSONEncoder().encode(choices) { defaults.set(data, forKey: "featured.choices.v1:\(scope)") }
    }
    private func acquire() async { if active >= 2 { await withCheckedContinuation { waiting.append($0) } } else { active += 1 } }
    private func release() { if !waiting.isEmpty { waiting.removeFirst().resume() } else { active -= 1 } }
    func candidates(_ track: SongItemRecord, name: String) async -> [FeaturedArtistCandidate] {
        guard let search else { return [] }
        let current = generation
        await acquire(); defer { release() }
        guard !Task.isCancelled, current == generation else { return [] }
        return FeaturedArtistParser.rank(name, (try? await search(name)) ?? [])
    }
    private func query(_ text: String, target: String) async -> [FeaturedArtistCandidate] {
        guard let search else { return [] }; let current = generation
        await acquire(); defer { release() }
        guard !Task.isCancelled, current == generation else { return [] }
        return FeaturedArtistParser.rank(target, (try? await search(text)) ?? [])
    }
    private func releaseConsumer(_ token:UUID,key:String,flight:Flight) {
        flight.consumers.remove(token)
        if flight.consumers.isEmpty {
            flight.task.cancel()
            if flights[key]?.id == flight.id { flights.removeValue(forKey:key) }
        }
    }
    private func awaitFlight(_ flight:Flight,key:String) async -> Resolution {
        let token = UUID();flight.consumers.insert(token)
        defer { releaseConsumer(token,key:key,flight:flight) }
        let result = await withTaskCancellationHandler(operation:{ await flight.task.value },onCancel:{ Task { @MainActor in self.releaseConsumer(token,key:key,flight:flight) } })
        return Task.isCancelled ? Resolution(id:nil,provenance:"unresolved",time:Date()) : result
    }
    func resolve(_ track: SongItemRecord, name: String, contextual: Bool = true) async -> Resolution {
        if let id = providerID(track,name), !id.isEmpty {
            let originalKey = key(track,name)
            if choices[originalKey] != nil { choose(track,name:name,id:nil) }
            if cache.removeValue(forKey:originalKey) != nil { lru.removeAll { $0 == originalKey };saveCache() }
            return Resolution(id:id,provenance:"provider",time:Date())
        }
        let key = key(track,name)
        if let choice = choices[key] { return choice }
        let cached = cache[key],fresh = cached.map { Date().timeIntervalSince($0.time) < ($0.id == nil ? 600 : 604800) } ?? false
        if let value = cached, fresh, (value.id != nil || !contextual || value.contextualComplete == true) { touch(key); return value }
        if let flight = flights[key] {
            let current = generation,result = await awaitFlight(flight,key:key)
            if result.id != nil || !contextual || result.contextualComplete == true || Task.isCancelled || current != generation { return result }
            if flights[key]?.id == flight.id { flights.removeValue(forKey:key) }
            return await resolve(track,name:name,contextual:contextual)
        }
        let current = generation,skipExact = cached != nil && fresh && cached?.id == nil
        let task = Task { @MainActor in
            var candidates:[FeaturedArtistCandidate] = []
            if !skipExact { candidates = await self.candidates(track,name:name) }
            guard current == self.generation,!Task.isCancelled else { return Resolution(id:nil,provenance:"unresolved",time:Date()) }
            if candidates.isEmpty, contextual, !track.artists.isEmpty { candidates = await self.query("\(name) \(track.artists)", target:name) }
            let result = Resolution(id:candidates.first?.id,provenance:candidates.isEmpty ? "unresolved" : "inferred",time:Date(),contextualComplete:contextual)
            if current == self.generation, !Task.isCancelled { self.cache[key] = result; self.touch(key); while self.lru.count > 500 { self.cache.removeValue(forKey:self.lru.removeFirst()) }; self.saveCache() }
            return result
        }
        let flight = Flight(task);flights[key] = flight
        return await awaitFlight(flight,key:key)
    }
    private func touch(_ key: String) { lru.removeAll { $0 == key }; lru.append(key) }
    func title(_ track: SongItemRecord) async -> [FeaturedCredit] {
        let current = generation
        var remaining = 8
        func solve(_ credit: FeaturedCredit, depth: Int) async -> [FeaturedCredit] {
            guard !Task.isCancelled else { return [] }
            var whole = credit
            if let id = providerID(track,credit.name), !id.isEmpty { whole.destinationID = id; whole.provenance = "provider"; return [whole] }
            let text = credit.name as NSString, separators = FeaturedArtistParser.separators(credit.name)
            var known: [FeaturedCredit] = [], offset = 0
            while offset < text.length {
                let ends = ([text.length] + separators.filter { $0.location > offset }.map(\.location)).sorted(by:>)
                guard let end = ends.first(where: { providerID(track,text.substring(with:NSRange(location:offset,length:$0-offset)))?.isEmpty == false }) else { break }
                let name = text.substring(with:NSRange(location:offset,length:end-offset))
                known.append(FeaturedCredit(range:NSRange(location:credit.range.location+offset,length:end-offset),name:name,destinationID:providerID(track,name),provenance:"provider"))
                if end == text.length { offset = end; break }
                offset = NSMaxRange(separators.first { $0.location == end }!)
            }
            if offset == text.length, !known.isEmpty { return known }
            if remaining > 0 { remaining -= 1; let resolution = await resolve(track,name:credit.name,contextual:false); whole.destinationID = resolution.id; whole.provenance = resolution.provenance }
            guard !Task.isCancelled else { return [] }
            if whole.destinationID != nil || depth >= 5 { return [whole] }
            for separator in separators.reversed() where remaining > 0 {
                guard !Task.isCancelled else { return [] }
                let first = text.substring(to:separator.location), second = text.substring(from:NSMaxRange(separator))
                guard !first.isEmpty, !second.isEmpty else { continue }; remaining -= 1
                let head = await resolve(track,name:first,contextual:false)
                guard let id = head.id else { continue }
                let tail = await solve(FeaturedCredit(range:NSRange(location:credit.range.location+NSMaxRange(separator),length:text.length-NSMaxRange(separator)),name:second),depth:depth+1)
                if tail.contains(where: { $0.destinationID != nil }) { return [FeaturedCredit(range:NSRange(location:credit.range.location,length:separator.location),name:first,destinationID:id,provenance:head.provenance)] + tail }
            }
            // No compatible partition: keep compound names intact and actionable.
            return [whole]
        }
        var result: [FeaturedCredit] = []
        for credit in FeaturedArtistParser.clauses(track.title) { result += await solve(credit,depth:0); if result.count >= 6 { break } }
        return current == generation ? Array(result.prefix(6)) : []
    }
    func open(_ track: SongItemRecord, name: String, onNavigate: @escaping (String?,String) -> Void, titleOffset: Int? = nil) async {
        let current = generation
        let result: (Resolution,String)? = await withCheckedContinuation { continuation in
            var finished = false
            Task { @MainActor in
                var target = name
                if let titleOffset { let credits = await self.title(track); target = credits.first { NSLocationInRange(titleOffset,$0.range) }?.name ?? name }
                guard current == self.generation else { if !finished { finished = true; continuation.resume(returning:nil) }; return }
                let resolution = await self.resolve(track,name:target)
                guard !finished else { return }; finished = true; continuation.resume(returning:(resolution,target))
            }
            Task { @MainActor in
                try? await Task.sleep(for:.seconds(2))
                guard !finished else { return }; finished = true; continuation.resume(returning:nil)
            }
        }
        guard current == generation, !Task.isCancelled else { return }
        onNavigate(result?.0.id,result?.1 ?? name)
    }
}
