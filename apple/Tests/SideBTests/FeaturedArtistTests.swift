import Foundation
import AppKit
import Testing
import SideBCore
@testable import SideB

private struct FeaturedFixture: Decodable { let title:String; let clauses:[String]; let names:[String] }
private func featuredSong(_ title:String, videoID:String = "one", runs:[HomeArtistRunRecord] = []) -> SongItemRecord {
    SongItemRecord(videoId:videoID,title:title,artists:"Main",album:"Album",duration:nil,thumbnail:nil,artistId:"main",albumId:nil,setVideoId:nil,isVideo:false,isUpload:false,library:nil,artistRuns:runs)
}
private func featuredDefaults() -> UserDefaults { UserDefaults(suiteName:"featured-tests-\(UUID().uuidString)")! }
@Test @MainActor func featuredSharedCorpusPreservesNamesAndUnicodeRanges() async throws {
    let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let fixtures = try JSONDecoder().decode([FeaturedFixture].self,from:Data(contentsOf:root.appendingPathComponent("docs/fixtures/featured-artists.json")))
    for fixture in fixtures {
        #expect(FeaturedArtistParser.clauses(fixture.title).map(\.name) == fixture.clauses)
        var queries = 0
        let resolver = FeaturedArtistResolver(defaults:featuredDefaults())
        resolver.configure(search:{ query in queries += 1; return fixture.names.filter { FeaturedArtistParser.normalize($0) == FeaturedArtistParser.normalize(query) }.map { FeaturedArtistCandidate(id:$0,name:$0) } },scope:"test")
        let credits = await resolver.title(featuredSong(fixture.title))
        #expect(credits.map(\.name) == fixture.names)
        #expect(queries <= 8)
        for credit in credits { #expect((fixture.title as NSString).substring(with:credit.range) == credit.name) }
    }
}
@Test @MainActor func featuredProviderPartitionsAvoidSearch() async {
    var queries = 0
    let resolver = FeaturedArtistResolver(defaults:featuredDefaults())
    resolver.configure(search:{ _ in queries += 1; return [] },scope:"test")
    let song = featuredSong("Tema (feat. Earth, Wind & Fire & Kanye West)",runs:[.init(text:"Earth, Wind & Fire",id:"group"),.init(text:"Kanye West",id:"kanye")])
    let credits = await resolver.title(song)
    #expect(credits.map(\.destinationID) == ["group","kanye"])
    #expect(credits.allSatisfy { $0.provenance == "provider" })
    #expect(queries == 0)
}
@Test func featuredRankingAutomaticallySelectsHomonyms() {
    let candidates = [FeaturedArtistCandidate(id:"wrong",name:"Joe"),FeaturedArtistCandidate(id:"second",name:"Joe Fox"),FeaturedArtistCandidate(id:"first",name:"Joe Fox"),FeaturedArtistCandidate(id:"second",name:"Joe Fox")]
    #expect(FeaturedArtistParser.rank("Joe Fox",candidates).map(\.id) == ["second","first"])
    #expect(FeaturedArtistParser.rank("Earth, Wind & Fire",[.init(id:"bad",name:"Earth")]).isEmpty)
    #expect(FeaturedArtistParser.compatible("José","José") == 100)
}
@Test @MainActor func featuredCorrectionsCacheAndProviderPriority() async {
    let disk = featuredDefaults(), song = featuredSong("Title")
    var calls = 0
    let resolver = FeaturedArtistResolver(defaults:disk)
    resolver.configure(search:{ _ in calls += 1; return [.init(id:"inferred",name:"Guest")] },scope:"a")
    #expect(await resolver.resolve(song,name:"Guest").id == "inferred")
    let restored = FeaturedArtistResolver(defaults:disk)
    restored.configure(search:{ _ in calls += 1; return [.init(id:"inferred",name:"Guest")] },scope:"a")
    #expect(await restored.resolve(song,name:"Guest").id == "inferred")
    #expect(calls == 1)
    restored.choose(song,name:"Guest",id:"chosen")
    #expect(await restored.resolve(song,name:"Guest").provenance == "userChoice")
    #expect(await restored.resolve(featuredSong("Title",runs:[.init(text:"Guest",id:"real")]),name:"Guest").id == "real")
    restored.configure(search:{ _ in [] },scope:"b")
    #expect(await restored.resolve(song,name:"Guest").id == nil)
}
@Test @MainActor func featuredContextQueryDoesNotChooseMainArtist() async {
    var queries:[String] = []
    let resolver = FeaturedArtistResolver(defaults:featuredDefaults())
    resolver.configure(search:{ query in queries.append(query); return query == "Guest Main" ? [.init(id:"main",name:"Main"),.init(id:"guest",name:"Guest")] : [] },scope:"a")
    #expect(await resolver.resolve(featuredSong("Title"),name:"Guest").id == "guest")
    #expect(queries == ["Guest","Guest Main"])
}
@Test @MainActor func featuredCancelledClickCannotNavigate() async {
    let resolver = FeaturedArtistResolver(defaults:featuredDefaults())
    resolver.configure(search:{ _ in try? await Task.sleep(for:.milliseconds(100));return [.init(id:"guest",name:"Guest")] },scope:"a")
    var navigated = false
    let task = Task { await resolver.open(featuredSong("Title"),name:"Guest") { _,_ in navigated = true } }
    try? await Task.sleep(for:.milliseconds(10));task.cancel();await task.value
    #expect(!navigated)
}
@Test @MainActor func featuredFirstClickChoosesGuestAtOriginalOffset() async {
    let title = "Tema (feat. Joe Fox & Kanye West)",resolver = FeaturedArtistResolver(defaults:featuredDefaults())
    resolver.configure(search:{ query in ["Joe Fox","Kanye West"].contains(query) ? [.init(id:query,name:query)] : [] },scope:"test")
    var opened:String?
    await resolver.open(featuredSong(title),name:"Joe Fox & Kanye West",onNavigate:{ id,_ in opened = id },titleOffset:(title as NSString).range(of:"Kanye").location+2)
    #expect(opened == "Kanye West")
}
@Test @MainActor func featuredNativeTargetsFollowVisibleGlyphsAndSurviveRelayout() {
    let field = NativeTrackActionField(frame:CGRect(x:0,y:0,width:500,height:26))
    field.font = .systemFont(ofSize:14)
    field.maximumNumberOfLines = 1;field.lineBreakMode = .byTruncatingTail
    let track = featuredSong("Tema (feat. Joe Fox)",runs:[.init(text:"Joe Fox",id:"joe")])
    var navigated = 0,played = 0
    field.onActivate = { played += 1 }
    field.configureFeatured(track:track,isTitle:true) { _,_ in navigated += 1 }
    let first = field.subviews.compactMap { $0 as? NativeFeaturedArtistButton }.first
    #expect(first != nil)
    field.layout()
    #expect(field.subviews.compactMap { $0 as? NativeFeaturedArtistButton }.first === first)
    #expect(first?.frame.intersection(field.bounds) == first?.frame)
    field.frame.size.width = 30;field.layout()
    #expect(field.subviews.compactMap { $0 as? NativeFeaturedArtistButton }.isEmpty)
    #expect(played == 0 && navigated == 0)
    field.clearFeatured()
}

@Test @MainActor func featuredSharedFlightCancellationKeepsLiveConsumer() async {
    let resolver = FeaturedArtistResolver(defaults:featuredDefaults())
    var release:CheckedContinuation<[FeaturedArtistCandidate],Never>?
    var calls = 0
    resolver.configure(search:{ _ in calls += 1;return await withCheckedContinuation { release = $0 } },scope:"a")
    let first = Task { await resolver.resolve(featuredSong("Title"),name:"Guest") }
    while release == nil { await Task.yield() }
    var joined = false
    let second = Task { joined = true;return await resolver.resolve(featuredSong("Title"),name:"Guest") }
    while !joined { await Task.yield() }
    first.cancel()
    release?.resume(returning:[.init(id:"guest",name:"Guest")])
    #expect(await first.value.id == nil)
    #expect(await second.value.id == "guest")
    #expect(calls == 1)
    #expect(await resolver.resolve(featuredSong("Title"),name:"Guest").id == "guest")
}

@Test @MainActor func featuredTitleNegativeCannotSuppressContextualClickAfterRestart() async {
    let disk = featuredDefaults(),song = featuredSong("Title (feat. Guest)")
    var queries:[String] = []
    let search:FeaturedArtistResolver.Search = { query in queries.append(query);return query == "Guest Main" ? [.init(id:"guest",name:"Guest")] : [] }
    let resolver = FeaturedArtistResolver(defaults:disk);resolver.configure(search:search,scope:"a")
    _ = await resolver.title(song)
    let restored = FeaturedArtistResolver(defaults:disk);restored.configure(search:search,scope:"a")
    var opened:String?
    await restored.open(song,name:"Guest",onNavigate:{ id,_ in opened = id })
    #expect(opened == "guest")
    #expect(queries == ["Guest","Guest Main"])
}
@Test @MainActor func featuredContextualClickPromotesSimultaneousPartialFlight() async {
    let resolver = FeaturedArtistResolver(defaults:featuredDefaults()),song = featuredSong("Title (feat. Guest)")
    var queries:[String] = [],release:CheckedContinuation<[FeaturedArtistCandidate],Never>?
    resolver.configure(search:{ query in
        queries.append(query)
        if queries.count == 1 { return await withCheckedContinuation { release = $0 } }
        return query == "Guest Main" ? [.init(id:"guest",name:"Guest")] : []
    },scope:"a")
    let title = Task { await resolver.title(song) }
    while release == nil { await Task.yield() }
    var joined = false
    let click = Task { joined = true;return await resolver.resolve(song,name:"Guest") }
    while !joined { await Task.yield() }
    release?.resume(returning:[])
    _ = await title.value
    #expect(await click.value.id == "guest")
    #expect(queries == ["Guest","Guest Main"])
}

@Test @MainActor func featuredNativeCaretUsesOnlyPointerActivation() {
    #expect(NativeFeaturedArtistOverlay.usesPointerOffset(.leftMouseDown))
    #expect(NativeFeaturedArtistOverlay.usesPointerOffset(.leftMouseUp))
    #expect(!NativeFeaturedArtistOverlay.usesPointerOffset(.keyDown))
    #expect(!NativeFeaturedArtistOverlay.usesPointerOffset(.applicationDefined))
    #expect(!NativeFeaturedArtistOverlay.usesPointerOffset(nil))
}
@Test @MainActor func featuredExpiredPartialNegativeRepeatsExactLookup() async throws {
    let disk = featuredDefaults(),song = featuredSong("Title (feat. Guest)")
    let resolver = FeaturedArtistResolver(defaults:disk)
    resolver.configure(search:{ _ in [] },scope:"a")
    _ = await resolver.title(song)
    let key = "featured.cache.v1:a"
    let data = try #require(disk.data(forKey:key))
    var entries = try JSONDecoder().decode([String:FeaturedArtistResolver.Resolution].self,from:data)
    entries = entries.mapValues { .init(id:$0.id,provenance:$0.provenance,time:Date(timeIntervalSinceNow:-601),contextualComplete:$0.contextualComplete) }
    disk.set(try JSONEncoder().encode(entries),forKey:key)
    var queries:[String] = []
    let restored = FeaturedArtistResolver(defaults:disk)
    restored.configure(search:{ query in queries.append(query);return query == "Guest Main" ? [.init(id:"guest",name:"Guest")] : [] },scope:"a")
    #expect(await restored.resolve(song,name:"Guest").id == "guest")
    #expect(queries == ["Guest","Guest Main"])
}
