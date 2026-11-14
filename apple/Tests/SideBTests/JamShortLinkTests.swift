import Foundation
import Testing
@testable import SideB

@Suite("Jam: enlaces cortos spotify.link")
struct JamShortLinkTests {
    private let token = "5QaRAjTyChieQ3Z8fdSlqu"

    @Test("Sólo https en hosts cortos de Spotify y sin credenciales")
    func shortURLValidation() {
        #expect(JamShortLink.shortURL(from: " https://spotify.link/AbC123 ")?.host == "spotify.link")
        #expect(JamShortLink.shortURL(from: "https://spotify.app.link/x") != nil)
        #expect(JamShortLink.shortURL(from: "http://spotify.link/x") == nil)
        #expect(JamShortLink.shortURL(from: "https://evil.example/spotify.link") == nil)
        #expect(JamShortLink.shortURL(from: "https://spotify.link.evil.example/x") == nil)
        #expect(JamShortLink.shortURL(from: "https://user:pw@spotify.link/x") == nil)
        #expect(JamShortLink.shortURL(from: "https://open.spotify.com/socialsession/\(token)") == nil)
        #expect(JamShortLink.shortURL(from: token) == nil)
    }

    @Test("Las redirecciones sólo siguen a hosts de Spotify esperados")
    func redirectAllowList() {
        #expect(JamShortLink.isAllowedRedirect(URL(string: "https://spotify.app.link/x")!))
        #expect(JamShortLink.isAllowedRedirect(URL(string: "https://open.spotify.com/socialsession/\(token)")!))
        #expect(!JamShortLink.isAllowedRedirect(URL(string: "https://evil.example/")!))
        #expect(!JamShortLink.isAllowedRedirect(URL(string: "http://open.spotify.com/x")!))
        #expect(!JamShortLink.isAllowedRedirect(URL(string: "https://open.spotify.com.evil.example/x")!))
    }

    @Test("El token se toma de la URL final o del HTML; token corto o ajeno se ignora")
    func canonicalExtraction() {
        let expected = "https://open.spotify.com/socialsession/\(token)"
        #expect(JamShortLink.canonicalLink(finalURL: URL(string: "https://open.spotify.com/socialsession/\(token)?si=1"), body: nil) == expected)
        let html = "<a href=\"https://open.spotify.com/socialsession/short\">x</a> <a href=\"https://open.spotify.com/socialsession/\(token)\">"
        #expect(JamShortLink.canonicalLink(finalURL: URL(string: "https://spotify.app.link/x"), body: html) == expected)
        #expect(JamShortLink.canonicalLink(finalURL: URL(string: "https://evil.example/socialsession/\(token)"), body: "nada") == nil)
        #expect(JamShortLink.canonicalLink(finalURL: nil, body: "sin enlace") == nil)
    }

    @Test("Un resolvedor inyectado entrega el enlace canónico que entiende el parser de unión")
    func injectedResolver() async {
        struct Fake: JamShortLinkResolving {
            let out: String?
            func resolve(_ url: URL) async -> String? { out }
        }
        let url = JamShortLink.shortURL(from: "https://spotify.link/AbC123")!
        let ok = await Fake(out: JamShortLink.canonical(token: token)).resolve(url)
        #expect(await MainActor.run { JamSessionController.extractJamToken(from: ok ?? "") } == token)
        #expect(await Fake(out: nil).resolve(url) == nil)
    }
}
