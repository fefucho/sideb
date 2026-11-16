import Foundation
import AVFoundation
import CoreAudio
import Testing
@testable import SideB

// PLAN-024: arnés de estrés del empalme contra el dispositivo de salida REAL (no corre en la suite normal).
// `SIDEB_AUDIO_STRESS=50 swift test --package-path apple --filter AudioDeviceStress`
// Tras cada ciclo comprueba que el dispositivo sigue sano con una sonda tipo `afplay` (debe terminar en ~1 s) y que no hay
// más de dos AVPlayer vivos. Con una salida virtual (eqMac) un cuelgue deja el audio del sistema inservible: si la sonda falla,
// el arnés se detiene enseguida y avisa.

private func stressTone(_ n: Int) -> Int16 { Int16((sin(2 * Double.pi * 440 * Double(n) / 44_100) * 0.2 * 32_767).rounded()) }

private func writeStressWAV(seconds: Double, offsetSamples: Int, to url: URL) throws {
    let rate = 44_100, samples = Int(Double(rate) * seconds)
    var data = Data()
    func le32(_ v: Int) { var x = UInt32(v).littleEndian; data.append(Data(bytes: &x, count: 4)) }
    func le16(_ v: Int) { var x = UInt16(v).littleEndian; data.append(Data(bytes: &x, count: 2)) }
    data.append(contentsOf: Array("RIFF".utf8)); le32(36 + samples * 2); data.append(contentsOf: Array("WAVEfmt ".utf8))
    le32(16); le16(1); le16(1); le32(rate); le32(rate * 2); le16(2); le16(16)
    data.append(contentsOf: Array("data".utf8)); le32(samples * 2)
    var pcm = [Int16](repeating: 0, count: samples)
    for n in 0..<samples { pcm[n] = stressTone(offsetSamples + n) }
    pcm.withUnsafeBytes { data.append(contentsOf: $0) }
    try data.write(to: url)
}

/// Sonda de salud: `afplay -v 0` de un sonido del sistema. Devuelve los segundos que tardó, o nil si se colgó.
private func probeOutputDevice(timeout: TimeInterval = 6) -> TimeInterval? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    process.arguments = ["-v", "0", "/System/Library/Sounds/Tink.aiff"]
    let done = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in done.signal() }
    let start = Date()
    do { try process.run() } catch { return nil }
    if done.wait(timeout: .now() + timeout) == .timedOut {
        process.terminate()
        return nil
    }
    return Date().timeIntervalSince(start)
}

@MainActor
@Suite("Estrés del empalme contra el dispositivo real", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["SIDEB_AUDIO_STRESS"] != nil))
struct AudioDeviceStressTests {
    @Test("Ciclos de armar, sustituir, entrar de inmediato, pausar y parar con la salud del dispositivo comprobada")
    func cycles() async throws {
        let cycles = Int(ProcessInfo.processInfo.environment["SIDEB_AUDIO_STRESS"] ?? "") ?? 10
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sideb-stress-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let song = directory.appendingPathComponent("song.wav")
        let file = directory.appendingPathComponent("transition.wav")
        try writeStressWAV(seconds: 60, offsetSamples: 0, to: song)
        try writeStressWAV(seconds: 40, offsetSamples: 20 * 44_100, to: file)
        let timeline = AudioSpliceTimeline(cut: 20, overlapStart: 8, overlapEnd: 12, handover: 10, bOffset: 5, bEntry: 3, fileDuration: 40)

        let device = AudioOutputDevice.current()
        print("[AudioDeviceStress] salida: \(device?.summary ?? "desconocida"); ciclos \(cycles)")
        let baseline = try #require(probeOutputDevice(), "la sonda ya falla antes de empezar: el dispositivo no está sano")
        print("[AudioDeviceStress] sonda inicial \(String(format: "%.2f", baseline)) s")

        var worstProbe = baseline
        var peakAlive = 0
        for cycle in 1...cycles {
            let suite = "AudioStress.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            do {
                // SIDEB_AUDIO_STRESS_MODE=hostsynced finge una salida integrada para forzar el arranque `setRate(atHostTime:)`.
                let forced = ProcessInfo.processInfo.environment["SIDEB_AUDIO_STRESS_MODE"] == "hostsynced"
                let audio = AudioPlayerService(preferences: defaults, preferencePrefix: "stress", outputDevice: {
                    forced ? AudioOutputDevice(name: "falsa", uid: "falsa", transportType: kAudioDeviceTransportTypeBuiltIn) : AudioOutputDevice.current()
                })
                audio.volume = 0
                audio.play(urlString: song.absoluteString, expectedDuration: 60, playbackID: UUID())
                let deadline = Date().addingTimeInterval(4)
                while audio.avPlayer.timeControlStatus != .playing, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
                guard audio.avPlayer.timeControlStatus == .playing else {
                    Issue.record("ciclo \(cycle): el reproductor no arrancó (dispositivo no responde)")
                    break
                }
                switch cycle % 5 {
                case 0: // armar, sustituir (stems), entrar de inmediato (el camino del «salto al corte» del usuario)
                    _ = audio.armSplice(AudioSplice(asset: AVURLAsset(url: file), nextVideoID: "B", timeline: timeline))
                    try await Task.sleep(for: .milliseconds(150))
                    _ = audio.replaceSplice(AudioSplice(asset: AVURLAsset(url: file), nextVideoID: "B", timeline: timeline))
                    try await Task.sleep(for: .milliseconds(150))
                    _ = audio.seekIntoSplice(toSeconds: 23)
                    try await Task.sleep(for: .milliseconds(500))
                case 1: // armar y desarmar sin llegar a nada
                    _ = audio.armSplice(AudioSplice(asset: AVURLAsset(url: file), nextVideoID: "B", timeline: timeline))
                    try await Task.sleep(for: .milliseconds(200))
                    audio.disarmSplice()
                case 2: // armar y parar la canción con el segundo reproductor precargado
                    _ = audio.armSplice(AudioSplice(asset: AVURLAsset(url: file), nextVideoID: "B", timeline: timeline))
                    try await Task.sleep(for: .milliseconds(200))
                case 3: // armar, saltar a justo antes del corte y dejar que se comprometa (arranque con la salida real)
                    _ = audio.armSplice(AudioSplice(asset: AVURLAsset(url: file), nextVideoID: "B", timeline: timeline))
                    try await Task.sleep(for: .milliseconds(200))
                    _ = audio.seek(toSeconds: 18.6)
                    try await Task.sleep(for: .milliseconds(2_400))
                default: // armar, comprometer, pausar dentro de la ventana (arranque programado deshecho) y parar
                    _ = audio.armSplice(AudioSplice(asset: AVURLAsset(url: file), nextVideoID: "B", timeline: timeline))
                    try await Task.sleep(for: .milliseconds(200))
                    _ = audio.seek(toSeconds: 19.3)
                    try await Task.sleep(for: .milliseconds(500))
                    audio.pause()
                    try await Task.sleep(for: .milliseconds(200))
                }
                peakAlive = max(peakAlive, AutomixPlayerCounter.snapshot.alive)
                audio.stop()
            }
            defaults.removePersistentDomain(forName: suite)
            try await Task.sleep(for: .milliseconds(150))
            let snapshot = AutomixPlayerCounter.snapshot
            guard let elapsed = probeOutputDevice() else {
                Issue.record("ciclo \(cycle): LA SONDA SE COLGÓ — el dispositivo de salida dejó de responder. AVPlayer vivos \(snapshot.alive), creados \(snapshot.created)")
                break
            }
            worstProbe = max(worstProbe, elapsed)
            print("[AudioDeviceStress] ciclo \(cycle)/\(cycles) tipo \(cycle % 5): sonda \(String(format: "%.2f", elapsed)) s, AVPlayer vivos \(snapshot.alive) (pico \(snapshot.peak), creados \(snapshot.created))")
            #expect(snapshot.alive <= 2, "ciclo \(cycle): hay \(snapshot.alive) AVPlayer vivos tras liberar el servicio")
            #expect(elapsed < 3, "ciclo \(cycle): la sonda tardó \(elapsed) s")
        }
        print("[AudioDeviceStress] fin: peor sonda \(String(format: "%.2f", worstProbe)) s, pico de AVPlayer vivos \(peakAlive)")
    }

    @Test("Muchos reproductores precargados a la vez, sin llegar a reproducir: la salida sigue sana al soltarlos")
    func accumulatePrerolled() async throws {
        let count = Int(ProcessInfo.processInfo.environment["SIDEB_AUDIO_STRESS"] ?? "") ?? 10
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sideb-stress-acc-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("transition.wav")
        try writeStressWAV(seconds: 30, offsetSamples: 0, to: file)
        _ = try #require(probeOutputDevice(), "la sonda ya falla antes de empezar")
        var switchers: [AudioSpliceSwitcher] = []
        for n in 1...min(count, 12) {
            let switcher = AudioSpliceSwitcher(asset: AVURLAsset(url: file))
            let result = await switcher.prepare(fileSeconds: 0)
            switchers.append(switcher)
            let alive = AutomixPlayerCounter.snapshot.alive
            guard let elapsed = probeOutputDevice() else {
                Issue.record("con \(n) reproductores precargados vivos la sonda se colgó")
                break
            }
            print("[AudioDeviceStress] precargados vivos \(n): preroll \(result), sonda \(String(format: "%.2f", elapsed)) s, AVPlayer vivos \(alive)")
        }
        for switcher in switchers { switcher.dispose() }
        switchers.removeAll()
        try await Task.sleep(for: .milliseconds(300))
        let after = try #require(probeOutputDevice(), "tras soltarlos la sonda se colgó")
        print("[AudioDeviceStress] tras soltarlos: sonda \(String(format: "%.2f", after)) s, AVPlayer vivos \(AutomixPlayerCounter.snapshot.alive)")
        #expect(AutomixPlayerCounter.snapshot.alive == 0)
    }
}
