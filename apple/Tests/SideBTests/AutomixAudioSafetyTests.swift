import Foundation
import AVFoundation
import CoreAudio
import Testing
import SideBCore
@testable import SideB

// PLAN-024: defensas del empalme frente a salidas de audio problemáticas (dispositivos virtuales como eqMac).

private func safetyTransition(cut: Double = 100) -> AutomixTransition {
    AutomixTransition(requestID: "r", fromVideoID: "A", toVideoID: "B", kind: "mix", filePath: "/tmp/x.wav", fileDuration: 300,
                      aCut: cut, overlapStart: 8, overlapEnd: 20, bOffset: 90, bEntry: 5, handover: 14)
}

private func safetySilentWAV(seconds: Double, in directory: URL, name: String) throws -> URL {
    let rate = 44_100, samples = Int(Double(rate) * seconds)
    var data = Data()
    func le32(_ v: Int) { var x = UInt32(v).littleEndian; data.append(Data(bytes: &x, count: 4)) }
    func le16(_ v: Int) { var x = UInt16(v).littleEndian; data.append(Data(bytes: &x, count: 2)) }
    data.append(contentsOf: Array("RIFF".utf8)); le32(36 + samples * 2); data.append(contentsOf: Array("WAVEfmt ".utf8))
    le32(16); le16(1); le16(1); le32(rate); le32(rate * 2); le16(2); le16(16)
    data.append(contentsOf: Array("data".utf8)); le32(samples * 2); data.append(Data(count: samples * 2))
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    return url
}

@Suite("Automix: dispositivo de salida y modo de arranque")
struct AudioOutputDeviceTests {
    @Test("El arranque sincronizado es el camino por defecto en cualquier salida; play() sólo tras fallar, o con el interruptor para salidas no integradas")
    func startMode() {
        let builtIn = AudioOutputDevice(name: "Altavoces del MacBook Pro", uid: "BuiltInSpeakerDevice", transportType: kAudioDeviceTransportTypeBuiltIn)
        let virtual = AudioOutputDevice(name: "Altavoces del MacBook Pro (eqMac)", uid: "EQMOutputCapture", transportType: kAudioDeviceTransportTypeUSB)
        let bluetooth = AudioOutputDevice(name: "Auriculares", uid: "bt", transportType: kAudioDeviceTransportTypeBluetooth)
        let aggregate = AudioOutputDevice(name: "Agregado", uid: "agg", transportType: kAudioDeviceTransportTypeAggregate)
        for device in [builtIn, virtual, bluetooth, aggregate] as [AudioOutputDevice?] + [nil] {
            #expect(AudioSpliceStartMode.choose(device: device, forcePlain: false, preferPlainOnNonBuiltIn: false) == .hostSynced)
            #expect(AudioSpliceStartMode.choose(device: device, forcePlain: true, preferPlainOnNonBuiltIn: false) == .plain, "tras fallar el sincronizado, play()")
        }
        // Con el interruptor de seguridad, sólo la integrada usa el sincronizado.
        #expect(AudioSpliceStartMode.choose(device: builtIn, forcePlain: false, preferPlainOnNonBuiltIn: true) == .hostSynced)
        #expect(AudioSpliceStartMode.choose(device: virtual, forcePlain: false, preferPlainOnNonBuiltIn: true) == .plain)
        #expect(AudioSpliceStartMode.choose(device: bluetooth, forcePlain: false, preferPlainOnNonBuiltIn: true) == .plain)
        #expect(AudioSpliceStartMode.choose(device: aggregate, forcePlain: false, preferPlainOnNonBuiltIn: true) == .plain)
        #expect(AudioSpliceStartMode.choose(device: nil, forcePlain: false, preferPlainOnNonBuiltIn: true) == .plain)
        #expect(builtIn.isBuiltIn && !virtual.isBuiltIn)
        #expect(virtual.summary.contains("EQMOutputCapture") && virtual.summary.contains("USB"))
        #expect(AudioOutputDevice.transportName(kAudioDeviceTransportTypeVirtual) == "virtual")
        #expect(AudioSpliceStartMode.preferPlainOnNonBuiltIn == false, "apagado por defecto")
    }

    @Test("El sistema da un dispositivo de salida legible (nombre y uid no vacíos)")
    func currentDevice() throws {
        let device = try #require(AudioOutputDevice.current())
        #expect(!device.name.isEmpty && device.name != "?")
        #expect(!device.uid.isEmpty && device.uid != "?")
    }
}

@Suite("Automix: finales instantáneos seguidos")
struct PlaybackFailureGuardTests {
    @Test("Dos pistas seguidas que terminan a menos de 5 s de empezar detienen la reproducción")
    func stopsAfterTwo() {
        var guardian = PlaybackFailureGuard()
        let first = guardian.trackEnded(secondsSinceStart: 2.0, expectedDuration: 200)
        #expect(!first)
        #expect(guardian.consecutiveShortEnds == 1)
        let second = guardian.trackEnded(secondsSinceStart: 2.1, expectedDuration: 200)
        #expect(second)
        guardian.reset()
        #expect(guardian.consecutiveShortEnds == 0)
    }

    @Test("Una pista que sonó con normalidad, o una acción del usuario, reinicia la cuenta; las pistas cortas de verdad no cuentan")
    func resets() {
        var guardian = PlaybackFailureGuard()
        let a = guardian.trackEnded(secondsSinceStart: 1, expectedDuration: 200)
        let b = guardian.trackEnded(secondsSinceStart: 120, expectedDuration: 200) // sonó normal: se reinicia
        let c = guardian.trackEnded(secondsSinceStart: 1, expectedDuration: 200)
        #expect(!a && !b && !c)
        guardian.reset()
        let d = guardian.trackEnded(secondsSinceStart: 1, expectedDuration: 200)
        #expect(!d)
        // Una pista de 6 s que termina a los 3 s no es un fallo de la salida.
        var short = PlaybackFailureGuard()
        let e = short.trackEnded(secondsSinceStart: 1, expectedDuration: 6)
        let f = short.trackEnded(secondsSinceStart: 1, expectedDuration: 6)
        #expect(!e && !f)
        #expect(short.consecutiveShortEnds == 0)
    }
}

@MainActor
@Suite("Automix: reproductores vivos y fin de pista sospechoso")
struct AudioSafetyServiceTests {
    private func makeService(isRendering: @escaping (AVPlayer) -> Bool = { _ in true }, media: AudioProbeBox) throws -> (AudioPlayerService, URL, () -> Void) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("automix-safety-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "AutomixSafety.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let audio = AudioPlayerService(preferences: defaults, preferencePrefix: "safety", isRendering: isRendering, measuredTime: { _ in media.seconds })
        audio.skipsSplicePrerollForTesting = true
        return (audio, directory, { audio.stop(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) })
    }

    @MainActor final class AudioProbeBox { var seconds = 0.0 }

    @Test("Armar, sustituir y desarmar muchas veces nunca deja más de dos AVPlayer vivos y todos se liberan")
    func neverMoreThanTwoPlayers() async throws {
        let box = AudioProbeBox()
        let baseline = AutomixPlayerCounter.snapshot.alive
        let createdBefore = AutomixPlayerCounter.snapshot.created
        let (audio, directory, cleanup) = try makeService(media: box)
        defer { cleanup() }
        let song = try safetySilentWAV(seconds: 2, in: directory, name: "song.wav")
        let file = try safetySilentWAV(seconds: 2, in: directory, name: "file.wav")
        audio.play(urlString: song.absoluteString, expectedDuration: 200, playbackID: UUID())
        audio.pause()
        audio.isPlaying = true
        audio.duration = 200
        box.seconds = 40
        var peak = 0
        for _ in 0..<25 {
            let plan = AudioSplice(asset: AVURLAsset(url: file), nextVideoID: "B", timeline: safetyTransition().timeline)
            #expect(audio.armSplice(plan) == .armed)
            peak = max(peak, AutomixPlayerCounter.snapshot.alive - baseline)
            #expect(audio.replaceSplice(plan) == .armed)
            peak = max(peak, AutomixPlayerCounter.snapshot.alive - baseline)
            audio.disarmSplice()
            // AVFoundation suelta sus referencias internas en el siguiente turno: se le da un instante entre ciclos.
            try await Task.sleep(for: .milliseconds(40))
        }
        try await Task.sleep(for: .milliseconds(300))
        // Servicio (1) + el del empalme (1) como mucho.
        #expect(peak <= 2, "pico de AVPlayer vivos por encima de la línea base: \(peak)")
        #expect(AutomixPlayerCounter.snapshot.alive - baseline <= 2, "tras desarmar quedan el del servicio y el de repuesto")
        #expect(AutomixPlayerCounter.snapshot.created - createdBefore <= 3, "se reutiliza el de repuesto: no se crea un AVPlayer por empalme")
        #expect(audio.spliceStage == .none)
    }

    @Test("Abortar un arranque programado suelta el elemento del segundo reproductor (no deja su canalización de audio viva)")
    func abortReleasesTheItem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("automix-abort-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try safetySilentWAV(seconds: 2, in: directory, name: "file.wav")
        let switcher = AudioSpliceSwitcher(asset: AVURLAsset(url: file))
        #expect(switcher.player.currentItem === switcher.item)
        let old = CountedPlayer()
        old.volume = 0.3
        switcher.abort(restoring: old, output: 0.8)
        #expect(switcher.player.currentItem == nil, "tras abortar el reproductor no conserva el elemento")
        #expect(old.volume == 0.8)
        switcher.dispose()
        #expect(switcher.player.currentItem == nil)
    }

    @Test("Con la salida caída (el reproductor no reproduce) un tiempo que alcanza la duración NO termina la pista; reproduciendo sí")
    func unrenderedEndIsIgnored() async throws {
        for (rendering, expectedEnds) in [(false, 0), (true, 1)] {
            let box = AudioProbeBox()
            let (audio, directory, cleanup) = try makeService(isRendering: { _ in rendering }, media: box)
            defer { cleanup() }
            let song = try safetySilentWAV(seconds: 2, in: directory, name: "song.wav")
            var ended = 0
            audio.onTrackDidEnd = { ended += 1 }
            audio.play(urlString: song.absoluteString, expectedDuration: 100, playbackID: UUID())
            audio.pause()
            audio.isPlaying = true
            audio.duration = 100
            box.seconds = 99.9
            audio.samplePlaybackProgress()
            #expect(ended == expectedEnds, "reproduciendo=\(rendering)")
        }
    }

    @Test("Cada fin de pista deja en el diagnóstico su causa, los tiempos y el estado del reproductor")
    func endCauseIsLogged() throws {
        let box = AudioProbeBox()
        let (audio, directory, cleanup) = try makeService(media: box)
        defer { cleanup() }
        let song = try safetySilentWAV(seconds: 2, in: directory, name: "song.wav")
        audio.play(urlString: song.absoluteString, expectedDuration: 100, playbackID: UUID())
        audio.pause()
        audio.isPlaying = true
        audio.duration = 100
        let before = AutomixDiagnostics.shared.log.entries.count
        box.seconds = 99.9
        audio.samplePlaybackProgress()
        let lines = AutomixDiagnostics.shared.log.entries.suffix(max(0, AutomixDiagnostics.shared.log.entries.count - before)).map(\.message)
        let line = try #require(lines.first { $0.hasPrefix("FIN DE PISTA:") })
        #expect(line.contains("el tiempo llegó al final de la duración"))
        #expect(line.contains("duración 100.000") && line.contains("sesgo") && line.contains("empalme") && line.contains("tasa"))
    }
}

@MainActor
@Suite("Automix: la cola no se recorre sola cuando el audio no responde")
struct InstantEndsPlayerTests {
    private func track(_ id: String) -> SongItemRecord {
        SongItemRecord(videoId: id, title: "Tema \(id)", artists: "Artista", album: nil, duration: "3:30", thumbnail: nil,
                       artistId: nil, albumId: nil, setVideoId: "occ-\(id)", isVideo: false, isUpload: false, library: nil)
    }

    @Test("Dos pistas seguidas que terminan nada más empezar detienen la reproducción con el error de siempre")
    func stopsInsteadOfSkipping() throws {
        let suite = "AutomixInstant.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let audio = AudioPlayerService(preferences: defaults, preferencePrefix: "instant")
        let player = PlayerViewModel(rustCore: nil, audioService: audio)
        let songs = ["A", "B", "C", "D"].map(track)
        player.queueManager.replaceQueue(with: songs, startingAt: 0, context: .custom(title: "Cola"))
        player.currentTrack = songs[0]
        func startedAndEnded() {
            audio.duration = 200
            audio.onPlaybackStarted?(player.experimentalLyricsPlaybackIdentity)
            audio.isPlaying = true
            audio.onTrackDidEnd?()
        }
        startedAndEnded()
        #expect(player.currentTrack?.videoId == "B", "el primer final instantáneo todavía avanza")
        #expect(player.errorMessage == nil || player.errorMessage?.contains("salida de audio") == false)
        startedAndEnded()
        #expect(player.currentTrack?.videoId == "B", "el segundo detiene: no se pasa a la siguiente")
        #expect(!audio.isPlaying)
        let message = try #require(player.errorMessage)
        #expect(message.contains("varias canciones terminaron nada más empezar") || message.contains("several songs ended"))
        let log = AutomixDiagnostics.shared.log.entries.map(\.message)
        #expect(log.contains { $0.hasPrefix("REPRODUCCIÓN DETENIDA:") })
        // Una acción del usuario reinicia la cuenta: otro final instantáneo vuelve a poder avanzar.
        player.playNext()
        startedAndEnded()
        #expect(player.currentTrack?.videoId != nil)
    }

    @Test("Una pista que sonó con normalidad no cuenta como final instantáneo")
    func normalTracksAdvance() throws {
        let suite = "AutomixInstant.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let audio = AudioPlayerService(preferences: defaults, preferencePrefix: "instant")
        let player = PlayerViewModel(rustCore: nil, audioService: audio)
        let songs = ["A", "B", "C"].map(track)
        player.queueManager.replaceQueue(with: songs, startingAt: 0, context: .custom(title: "Cola"))
        player.currentTrack = songs[0]
        // Sin `onPlaybackStarted` no hay hora de arranque: se trata como una pista normal.
        audio.duration = 200
        audio.onTrackDidEnd?()
        #expect(player.currentTrack?.videoId == "B")
        audio.duration = 200
        audio.onTrackDidEnd?()
        #expect(player.currentTrack?.videoId == "C")
        #expect(audio.isPlaying == false || player.errorMessage?.contains("salida") != true)
    }
}
