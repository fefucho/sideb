import Foundation
import AVFoundation
import Testing
@testable import SideB

// PLAN-024: el empalme con un segundo AVPlayer, probado con reproductores reales y archivos locales (volumen 0).
// Dura unos segundos de reloj real a propósito: lo que se mide es la continuidad del reproductor.

private func tone(_ sample: Int) -> Int16 {
    Int16((sin(2 * Double.pi * 440 * Double(sample) / 44_100) * 0.25 * 32_767).rounded())
}

/// WAV mono de 16 bits con `tone(offsetSamples + n)`: la «canción» (offset 0) y la «transición» (offset = aCut) comparten
/// muestras, como el archivo del core comparte las de la canción hasta el solape.
private func writeTone(seconds: Double, offsetSamples: Int, to url: URL) throws {
    let rate = 44_100, samples = Int(Double(rate) * seconds)
    var data = Data()
    func le32(_ v: Int) { var x = UInt32(v).littleEndian; data.append(Data(bytes: &x, count: 4)) }
    func le16(_ v: Int) { var x = UInt16(v).littleEndian; data.append(Data(bytes: &x, count: 2)) }
    data.append(contentsOf: Array("RIFF".utf8)); le32(36 + samples * 2); data.append(contentsOf: Array("WAVEfmt ".utf8))
    le32(16); le16(1); le16(1); le32(rate); le32(rate * 2); le16(2); le16(16)
    data.append(contentsOf: Array("data".utf8)); le32(samples * 2)
    var pcm = [Int16](repeating: 0, count: samples)
    for n in 0..<samples { pcm[n] = tone(offsetSamples + n) }
    pcm.withUnsafeBytes { data.append(contentsOf: $0) }
    try data.write(to: url)
}

@MainActor
@Suite("Automix: empalme con dos reproductores reales", .serialized)
struct AutomixTwoPlayerTests {
    private struct Sample { var wall: Double; var displayed: Double; var status: AVPlayer.TimeControlStatus; var stage: AudioSpliceStage }

    @Test("Armar y cambiar de reproductor no deja esperar al activo y el tiempo mostrado es continuo")
    func gaplessSwitch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("automix-2p-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cut = 3.0
        let song = directory.appendingPathComponent("song.wav")
        let file = directory.appendingPathComponent("transition.wav")
        try writeTone(seconds: 12, offsetSamples: 0, to: song)
        try writeTone(seconds: 20, offsetSamples: Int(cut * 44_100), to: file)
        let timeline = AudioSpliceTimeline(cut: cut, overlapStart: 8, overlapEnd: 9, handover: 8.5, bOffset: 2, bEntry: 5, fileDuration: 20)

        let suite = "AutomixTwoPlayer.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let audio = AudioPlayerService(preferences: defaults, preferencePrefix: "twoplayer")
        audio.volume = 0
        defer { audio.stop() }
        var entered = 0
        audio.onSpliceEntered = { entered += 1 }

        audio.play(urlString: song.absoluteString, expectedDuration: 12, playbackID: UUID())
        let startDeadline = Date().addingTimeInterval(5)
        while audio.avPlayer.timeControlStatus != .playing, Date() < startDeadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(audio.avPlayer.timeControlStatus == .playing, "el entorno de pruebas no puede reproducir audio")
        // Arrancó de verdad: hay avance de tiempo.
        try await Task.sleep(for: .milliseconds(500))
        try #require(audio.displayedPlaybackSeconds > 0.2)

        let oldPlayer = audio.avPlayer
        let result = audio.armSplice(AudioSplice(asset: AVURLAsset(url: file), nextVideoID: "B", timeline: timeline))
        #expect(result == .armed)
        #expect(audio.spliceStage == .armed)

        var samples: [Sample] = []
        let deadline = Date().addingTimeInterval(14)
        var afterSwitch = 0
        while Date() < deadline {
            samples.append(Sample(wall: ProcessInfo.processInfo.systemUptime, displayed: audio.displayedPlaybackSeconds,
                                  status: audio.avPlayer.timeControlStatus, stage: audio.spliceStage))
            if audio.spliceStage == .inFile { afterSwitch += 1 }
            if afterSwitch > 100 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(audio.spliceStage == .inFile, "el empalme debía completarse")
        #expect(entered == 1)
        #expect(audio.avPlayer !== oldPlayer, "el reproductor del archivo pasó a ser el activo")
        #expect(oldPlayer.currentItem == nil, "el reproductor viejo se retiró")

        // 1) El reproductor activo nunca esperó a reproducir, antes, durante ni después del cambio.
        let waiting = samples.filter { $0.status == .waitingToPlayAtSpecifiedRate }
        #expect(waiting.isEmpty, "\(waiting.count) muestras con waitingToPlayAtSpecifiedRate")
        #expect(samples.allSatisfy { $0.status == .playing }, "estados vistos: \(Set(samples.map { "\($0.status.rawValue)" }))")

        // 2) El tiempo mostrado es continuo: avanza a la par del reloj, sin saltos de más de 60 ms ni paradas.
        var worst = 0.0
        var switchedSample: Int?
        for index in 1..<samples.count {
            let wall = samples[index].wall - samples[index - 1].wall
            let shown = samples[index].displayed - samples[index - 1].displayed
            worst = max(worst, abs(shown - wall))
            if samples[index].stage == .inFile, switchedSample == nil { switchedSample = index }
            #expect(shown >= -0.001, "el tiempo mostrado retrocedió en la muestra \(index)")
        }
        #expect(worst < 0.06, "salto máximo del tiempo mostrado: \(Int(worst * 1000)) ms")
        print("[AutomixTwoPlayerTests] muestras \(samples.count), mayor desvío del tiempo mostrado \(String(format: "%.1f", worst * 1000)) ms")
        let crossing = try #require(switchedSample)
        let around = samples[max(1, crossing - 3)...min(samples.count - 1, crossing + 3)]
        #expect(around.count >= 4)

        // 3) La alineación medida entre los dos reproductores es la esperada (diagnóstico).
        let diagnostics = try #require(audio.spliceDiagnostics)
        let offset = try #require(diagnostics.measuredOffsetMilliseconds)
        #expect(abs(offset) < 30, "desfase entre reproductores: \(offset) ms")
        print("[AutomixTwoPlayerTests] desfase medido \(String(format: "%.2f", offset)) ms, arranque programado con \(String(format: "%.0f", (diagnostics.scheduledLeadSeconds ?? 0) * 1000)) ms de adelanto, precarga \(String(format: "%.0f", diagnostics.prerollMilliseconds ?? 0)) ms")
        #expect(diagnostics.scheduledLeadSeconds ?? 0 > 0.04)
        #expect(diagnostics.crossfadeStartHost != nil && diagnostics.crossfadeEndHost != nil)
        #expect((diagnostics.crossfadeEndHost ?? 0) - (diagnostics.crossfadeStartHost ?? 0) >= AudioCrossfade.duration - 0.01)
    }

    // MARK: Escenarios con el reloj real

    private struct Rig {
        let audio: AudioPlayerService
        let timeline: AudioSpliceTimeline
        let file: URL
        let cleanup: () -> Void
    }

    private func makeRig(cut: Double = 3) throws -> Rig {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("automix-2p-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let song = directory.appendingPathComponent("song.wav")
        let file = directory.appendingPathComponent("transition.wav")
        try writeTone(seconds: 14, offsetSamples: 0, to: song)
        try writeTone(seconds: 20, offsetSamples: Int(cut * 44_100), to: file)
        let suite = "AutomixTwoPlayer.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let audio = AudioPlayerService(preferences: defaults, preferencePrefix: "twoplayer")
        audio.volume = 0
        audio.play(urlString: song.absoluteString, expectedDuration: 14, playbackID: UUID())
        return Rig(audio: audio,
                   timeline: AudioSpliceTimeline(cut: cut, overlapStart: 8, overlapEnd: 9, handover: 8.5, bOffset: 2, bEntry: 5, fileDuration: 20),
                   file: file,
                   cleanup: { audio.stop(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) })
    }

    private func waitUntil(_ timeout: Double, _ condition: () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test("Armar con el corte ya pasado: entra un poco más adelante, sin esperar al reproductor activo")
    func lateArm() async throws {
        let rig = try makeRig()
        defer { rig.cleanup() }
        let audio = rig.audio
        try #require(try await waitUntil(5) { audio.avPlayer.timeControlStatus == .playing })
        // La transición llega con la canción ya en 3,6 s (corte en 3,0).
        try #require(try await waitUntil(6) { audio.displayedPlaybackSeconds >= 3.6 })
        #expect(audio.armSplice(AudioSplice(asset: AVURLAsset(url: rig.file), nextVideoID: "B", timeline: rig.timeline)) == .armed)
        var waiting = 0
        var worst = 0.0
        var previous: (wall: Double, shown: Double)?
        let switched = try await waitUntil(6) {
            if audio.avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate { waiting += 1 }
            let now = (wall: ProcessInfo.processInfo.systemUptime, shown: audio.displayedPlaybackSeconds)
            if let previous { worst = max(worst, abs((now.shown - previous.shown) - (now.wall - previous.wall))) }
            previous = now
            return audio.spliceStage == .inFile
        }
        #expect(switched)
        #expect(waiting == 0)
        #expect(worst < 0.06, "salto máximo: \(Int(worst * 1000)) ms")
        let diagnostics = try #require(audio.spliceDiagnostics)
        // Entró en un punto cercano a «ahora + 0,45 s»: segundo del archivo ≈ 3,6 + 0,45 − 3,0.
        let entry = try #require(diagnostics.scheduledFileSeconds)
        #expect(entry > 0.4 && entry < 1.6, "entrada tardía en el segundo \(entry) del archivo")
        #expect(abs(try #require(diagnostics.measuredOffsetMilliseconds)) < 30)
    }

    @Test("Pausar dentro de la ventana de confirmación deshace el arranque programado; al reanudar se empalma igual")
    func pauseWithinWindow() async throws {
        let rig = try makeRig()
        defer { rig.cleanup() }
        let audio = rig.audio
        try #require(try await waitUntil(5) { audio.avPlayer.timeControlStatus == .playing })
        try #require(try await waitUntil(3) { audio.displayedPlaybackSeconds >= 0.3 })
        #expect(audio.armSplice(AudioSplice(asset: AVURLAsset(url: rig.file), nextVideoID: "B", timeline: rig.timeline)) == .armed)
        // Dentro de los 0,9 s previos al corte el arranque ya está programado.
        try #require(try await waitUntil(6) { audio.spliceDiagnostics?.phase == "scheduled" })
        audio.pause()
        #expect(audio.spliceStage == .armed, "sigue armado, sólo se deshizo el arranque")
        #expect(audio.spliceDiagnostics?.phase == "aborted" || audio.spliceDiagnostics?.phase == "prerolling" || audio.spliceDiagnostics?.phase == "prerolled")
        let frozen = audio.displayedPlaybackSeconds
        try await Task.sleep(for: .milliseconds(800))
        #expect(abs(audio.displayedPlaybackSeconds - frozen) < 0.05, "pausada: el tiempo no avanza (el archivo no debe sonar solo)")
        #expect(audio.spliceStage == .armed)
        audio.resume()
        #expect(try await waitUntil(8) { audio.spliceStage == .inFile })
        #expect(abs(audio.spliceDiagnostics?.measuredOffsetMilliseconds ?? 999) < 30)
    }
}
