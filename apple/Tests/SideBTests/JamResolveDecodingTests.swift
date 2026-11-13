import Foundation
import Testing
@testable import SideB

@Suite("Jam: plugin replies as the real plugin prints them")
struct JamResolveDecodingTests {
    @Test("A resolved line decodes into a Spotify match")
    func resolvedLine() throws {
        let line = #"{"artists":["The Weeknd"],"durationMs":200045,"requestId":"r1","title":"Blinding Lights","type":"resolved","uri":"spotify:track:6qYkmqFsXbj8CQjAdbYz07"}"#
        let event = try JSONDecoder().decode(JamEvent.self, from: Data(line.utf8))
        let resolved = try #require(JamResolved(event: event))
        #expect(resolved.uri == "spotify:track:6qYkmqFsXbj8CQjAdbYz07")
        #expect(event.requestId == "r1")
    }

    @Test("A miss decodes and yields no match")
    func missLine() throws {
        let line = #"{"artists":[],"durationMs":null,"requestId":"r2","title":null,"type":"resolved","uri":null}"#
        let event = try JSONDecoder().decode(JamEvent.self, from: Data(line.utf8))
        #expect(event.requestId == "r2")
        #expect(JamResolved(event: event) == nil)
    }
}
