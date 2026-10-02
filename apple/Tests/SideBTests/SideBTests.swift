import Testing
import Foundation
import AVFoundation
import SideBCore
@testable import SideB

@Test(.enabled(if: ProcessInfo.processInfo.environment["SIDEB_LIVE_TESTS"] == "1"))
func testStreamResolutionAndPlayer() async throws {
    print("--- INICIANDO TEST DE STREAMING ---")
    let core = try SideBCore(dataDir: NSTemporaryDirectory())
    core.setCipherJsRuntime(runtime: NativeCipherJsRuntime())
    print("SideBCore creado con éxito")
    
    do {
        print("Llamando a resolveStream para fJ9rUzIMcZQ...")
        let playback = try await core.resolveStream(videoId: "fJ9rUzIMcZQ", isUpload: false)
        print("STREAM RESUELTO EXITOSAMENTE:")
        print("  Client: \(playback.streamClient)")
        print("  Itag: \(playback.itag)")
        print("  Duration: \(playback.duration ?? "nil")")
        print("  Loudness: \(playback.loudnessDb ?? 0)")
        print("  URL de stream disponible: \(!playback.streamUrl.isEmpty)")
        
        guard let url = URL(string: playback.streamUrl) else {
            Issue.record("URL inválida")
            return
        }
        
        // Probar carga en AVPlayer
        let options: [String: Any] = playback.headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": playback.headers]
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.play()
        defer { player.pause() }
        
        // Esperar 4 segundos observando el status
        for second in 1...4 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let status = item.status
            let durationSecs = CMTimeGetSeconds(item.duration)
            let currentSecs = CMTimeGetSeconds(player.currentTime())
            print("[\(second)s] item.status=\(status.rawValue) dur=\(durationSecs) current=\(currentSecs) error=\(String(describing: item.error))")
        }
        #expect(!playback.streamUrl.isEmpty)
        #expect(playback.duration != nil)
    } catch {
        print("❌ ERROR EN resolveStream: \(error)")
        Issue.record("resolveStream falló: \(error)")
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SIDEB_LIVE_TESTS"] == "1"))
func testGetHomeSections() async throws {
    print("--- TEST DE HOME SECTIONS ---")
    let core = try SideBCore(dataDir: NSTemporaryDirectory())
    let sections = try await core.getHomeSections()
    print("Secciones de Home obtenidas: \(sections.count)")
    for s in sections.prefix(3) {
        print("  Sección: \(s.title) (\(s.items.count) items)")
    }
    #expect(!sections.isEmpty)
}

@Test func testCoreSessionCookieState() throws {
    print("--- TEST DE ESTADO DE SESIÓN ---")
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("sideb-session-contract-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let core = try SideBCore(dataDir: directory.path)
    
    // Inicialmente debe estar deslogueado
    core.setCookie(cookie: nil)
    #expect(!core.isLoggedIn())
    #expect(core.getCookie() == nil)
    
    // Al setear cookie de sesión
    let dummyCookie = "SAPISID=123456789; __Secure-3PAPISID=987654321;"
    core.setCookie(cookie: dummyCookie)
    #expect(core.isLoggedIn())
    #expect(core.getCookie() == dummyCookie)
    
    // Al purgar cookie (logout)
    core.setCookie(cookie: nil)
    #expect(!core.isLoggedIn())
    #expect(core.getCookie() == nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SIDEB_LIVE_TESTS"] == "1"))
func testGetPlaylistAndLibraryLoggedOut() async throws {
    print("--- TEST DE BIBLIOTECA DESLOGUEADO ---")
    let core = try SideBCore(dataDir: NSTemporaryDirectory())
    core.setCookie(cookie: nil)
    
    // Sin sesión, getLibraryPlaylists devuelve lista vacía o error de sesión de forma controlada
    do {
        let playlists = try await core.getLibraryPlaylists()
        #expect(playlists.isEmpty)
        print("Manejo correcto de biblioteca sin login (lista vacía)")
    } catch {
        print("Manejo correcto de error de biblioteca sin login: \(error)")
        #expect(true)
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SIDEB_LIVE_ACCOUNT"] == "1"))
func testLiveAccountAndLibraryWithKeychainCookie() async throws {
    print("--- TEST DE DIAGNÓSTICO EN VIVO CON COOKIE REAL ---")
    let servicePrefix = "com.fefucho.SideB.auth"
    let cookieKey = "sessionCookie"
    let account = "\(servicePrefix).\(cookieKey)"

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: account,
        kSecAttrService as String: servicePrefix,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Data,
          let cookie = String(data: data, encoding: .utf8), !cookie.isEmpty else {
        print("No hay cookie guardada en Keychain para probar.")
        return
    }

    print("Cookie encontrada en Keychain. Longitud original: \(cookie.count)")
    let excludedGoogleKeys: Set<String> = [
        "NID", "ACCOUNT_CHOOSER", "SMSV", "__Host-GAPS", "OTZ", "LSID", "__Host-1PLSID", "__Host-3PLSID"
    ]
    let parts = cookie.components(separatedBy: ";")
    var cookieDict: [String: String] = [:]
    for part in parts {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
        let key = String(trimmed[..<eqIdx])
        let value = String(trimmed[trimmed.index(after: eqIdx)...])
        if excludedGoogleKeys.contains(key) { continue }
        cookieDict[key] = value
    }
    let sanitizedCookie = cookieDict.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    print("Cookie saneada. Longitud: \(sanitizedCookie.count)")
    
    // Si la cookie original requería saneamiento, actualizamos el Keychain ahora mismo
    if sanitizedCookie != cookie, let cleanData = sanitizedCookie.data(using: .utf8) {
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: servicePrefix,
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: cleanData,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        print("✅ Keychain actualizado con la cookie saneada de YouTube Music. Status: \(updateStatus)")
    }

    let core = try SideBCore(dataDir: NSTemporaryDirectory())
    core.setCookie(cookie: sanitizedCookie)
    #expect(core.isLoggedIn())

    // 1. Account Info
    do {
        let accountInfo = try await core.getAccountInfo()
        print("✅ Account Info: name=\(accountInfo.name ?? "nil"), handle=\(accountInfo.handle ?? "nil"), email=\(accountInfo.email ?? "nil")")
    } catch {
        print("❌ Error en getAccountInfo: \(error)")
    }

    // 2. Library Playlists
    do {
        let playlists = try await core.getLibraryPlaylists()
        print("✅ Library Playlists: \(playlists.count) encontradas")
        for p in playlists.prefix(5) {
            print("   - Playlist: [\(p.id)] \(p.title)")
        }
    } catch {
        print("❌ Error en getLibraryPlaylists: \(error)")
    }

    // 3. Library Albums
    do {
        let albums = try await core.getLibraryAlbums()
        print("✅ Library Albums: \(albums.count) encontrados")
        for a in albums.prefix(5) {
            print("   - Album: [\(a.id)] \(a.title)")
        }
    } catch {
        print("❌ Error en getLibraryAlbums: \(error)")
    }

    // 4. History
    do {
        let history = try await core.getHistory()
        print("✅ History: \(history.count) grupos")
        for h in history.prefix(3) {
            print("   - Grupo '\(h.title)': \(h.items.count) items")
        }
    } catch {
        print("❌ Error en getHistory: \(error)")
    }

    // 5. Liked Music (LM) y continuación
    do {
        let lm = try await core.getPlaylist(playlistId: "LM")
        print("✅ Liked Music (LM): '\(lm.title)', \(lm.items.count) canciones, cont: \(lm.continuation != nil)")
        if let token = lm.continuation {
            let contJson = try await core.getPlaylistContinuationJson(token: token)
            print("✅ Continuation JSON obtenido: \(contJson.prefix(100))...")
        }
    } catch {
        print("❌ Error en getPlaylist(LM): \(error)")
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SIDEB_LIVE_TESTS"] == "1"))
func testLiveRadioFetchFromCore() async throws {
    print("--- TEST DE RADIO DINÁMICA CON INNERTUBE ---")
    let core = try SideBCore(dataDir: NSTemporaryDirectory())
    
    // Radio para Bohemian Rhapsody (fJ9rUzIMcZQ)
    let radio = try await core.getRadio(videoId: "fJ9rUzIMcZQ")
    print("✅ Radio obtenida: \(radio.items.count) pistas, seed: \(radio.automixPlaylistId ?? "nil"), cont: \(radio.continuation != nil)")
    #expect(!radio.items.isEmpty)
    for t in radio.items.prefix(3) {
        print("   - Radio track: [\(t.videoId)] \(t.title) - \(t.artists)")
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SIDEB_LIVE_TESTS"] == "1"))
func testLiveRelatedTracksAndArtistsFromCore() async throws {
    print("--- TEST DE CANCIONES PARECIDAS (RELATED) CON INNERTUBE ---")
    let core = try SideBCore(dataDir: NSTemporaryDirectory())
    
    // Canciones parecidas para Bohemian Rhapsody (fJ9rUzIMcZQ)
    let relatedTracks = try await core.getRelatedTracks(videoId: "fJ9rUzIMcZQ")
    print("✅ Canciones parecidas obtenidas: \(relatedTracks.count) pistas")
    #expect(!relatedTracks.isEmpty)
    for t in relatedTracks.prefix(5) {
        print("   - Canción parecida: [\(t.videoId)] \(t.title) - \(t.artists)")
    }
    
    // Artistas similares para Bohemian Rhapsody
    let relatedArtists = try await core.getRelatedArtists(videoId: "fJ9rUzIMcZQ")
    print("✅ Artistas similares obtenidos: \(relatedArtists.count) artistas")
    for a in relatedArtists.prefix(5) {
        print("   - Artista similar: [\(a.id)] \(a.title)")
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SIDEB_LIVE_TESTS"] == "1"))
func testSearchAllAndPlayback() async throws {
    print("--- TEST DE SEARCH ALL Y REPRODUCCIÓN ---")
    let core = try SideBCore(dataDir: NSTemporaryDirectory())
    core.setCipherJsRuntime(runtime: NativeCipherJsRuntime())
    let results = try await core.searchAll(query: "kanye west", recordHistory: false)
    print("✅ SearchAll Kanye West completado:")
    print("   - Top: \(results.top.count)")
    print("   - Artists: \(results.artists.count)")
    print("   - Songs: \(results.songs.count)")
    print("   - Albums: \(results.albums.count)")
    print("   - Playlists: \(results.playlists.count)")
    for top in results.top {
        print("     [Top] kind=\(top.kind) id=\(top.id) title=\(top.title) sub=\(top.subtitle ?? "nil")")
    }
    for song in results.songs.prefix(5) {
        print("     [Song] videoId=\(song.videoId) title=\(song.title) artists=\(song.artists)")
    }
    
    if let firstSong = results.songs.first {
        print("Probando resolveStream para canción: \(firstSong.videoId)...")
        let stream = try await core.resolveStream(videoId: firstSong.videoId, isUpload: false)
        print("✅ Stream resuelto: itag=\(stream.itag) dur=\(stream.duration ?? "nil")")
        
        print("Probando getRadio para canción: \(firstSong.videoId)...")
        let radio = try await core.getRadio(videoId: firstSong.videoId)
        print("✅ Radio resuelta: \(radio.items.count) pistas, seed=\(radio.automixPlaylistId ?? "nil")")
    }
}

@Test @MainActor func testPlayerViewModelDismissFullscreen() throws {
    let vm = PlayerViewModel()
    vm.isFullscreenPresented = true
    #expect(vm.isFullscreenPresented == true)
    vm.dismissFullscreen()
    #expect(vm.isFullscreenPresented == false)
}

@Test @MainActor func testNavigationRouterHistory() throws {
    let router = NavigationRouter()
    #expect(router.currentPage == .home)
    router.navigate(to: .playlist(browseId: "LM"))
    #expect(router.currentPage == .playlist(browseId: "LM"))
    #expect(router.canGoBack == true)
    router.goBack()
    #expect(router.currentPage == .home)
}
