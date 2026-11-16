import Foundation
import AVFoundation
import CoreMedia

// PLAN-024: empalme con un SEGUNDO AVPlayer. La canción que suena no se toca (ni su elemento, ni su
// `forwardPlaybackEndTime`, ni una cola): el archivo de la transición se carga y se precarga en otro reproductor,
// se arranca a una hora de reloj exacta alineada con la posición de la canción y se hace un fundido de 50 ms entre
// ambos dentro de la primera parte del archivo, que es la canción tal cual. Después el reproductor del archivo
// pasa a ser el del servicio.

/// Cronología del segundo reproductor, para el diagnóstico.
struct AutomixSpliceDiagnostics: Equatable, Sendable {
    var phase = "sin empalme"
    /// Segundo del archivo en que quedó precargado.
    var prerolledFileSeconds: Double?
    var prerollDoneAt: Date?
    var prerollMilliseconds: Double?
    /// Hora de reloj (segundos del reloj de host) a la que se programó el arranque.
    var scheduledHostSeconds: Double?
    /// Cuánto faltaba (segundos) cuando se programó.
    var scheduledLeadSeconds: Double?
    var scheduledFileSeconds: Double?
    var crossfadeStartHost: Double?
    var crossfadeEndHost: Double?
    /// Diferencia medida entre los dos reproductores al final del fundido: canción − (aCut + archivo), en ms.
    /// Positivo = la canción iba por delante del archivo.
    var measuredOffsetMilliseconds: Double?
    var note: String?
}

/// Fundido lineal de ganancias (suma 1: la primera parte del archivo es idéntica a la canción).
enum AudioCrossfade {
    static let duration: TimeInterval = 0.05

    /// Progreso 0…1 del fundido en `hostSeconds` si empieza en `startSeconds`.
    static func progress(hostSeconds: Double, startSeconds: Double, duration: TimeInterval = duration) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, (hostSeconds - startSeconds) / duration))
    }

    /// (ganancia del reproductor nuevo, ganancia del viejo) a ese progreso, multiplicadas por el volumen de salida.
    static func gains(progress: Double, output: Float) -> (new: Float, old: Float) {
        let p = Float(min(1, max(0, progress)))
        return (output * p, output * (1 - p))
    }
}

@MainActor
final class AudioSpliceSwitcher {
    enum Phase: String, Sendable { case idle, prerolling, prerolled, scheduled, crossfading, done, aborted }

    let player = AVPlayer()
    let item: AVPlayerItem
    private(set) var phase: Phase = .idle
    private(set) var prerolledFileSeconds: Double?
    private(set) var diagnostics = AutomixSpliceDiagnostics()
    /// Verdadero desde que se programó el arranque: el empalme ya no admite cambiar de archivo.
    var isCommitted: Bool { phase == .scheduled || phase == .crossfading || phase == .done }

    private var timer: DispatchSourceTimer?
    private var timerQueue: DispatchQueue?
    private var generation = 0

    init(asset: AVURLAsset) {
        item = AVPlayerItem(asset: asset)
        player.volume = 0
        // Requisito de `setRate(_:time:atHostTime:)`: no esperar a minimizar los cortes.
        player.automaticallyWaitsToMinimizeStalling = false
        player.replaceCurrentItem(with: item)
        diagnostics.phase = phase.rawValue
    }

    static func hostSeconds() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    enum PrepareResult: Equatable { case ready, superseded, failed }

    /// Espera a que el elemento esté listo, se coloca en `fileSeconds` y precarga (`preroll(atRate:)`).
    /// La canción que suena ni se entera: todo ocurre en el reproductor del archivo.
    func prepare(fileSeconds: Double) async -> PrepareResult {
        guard phase != .crossfading, phase != .done else { return .superseded }
        generation += 1
        let token = generation
        phase = .prerolling
        prerolledFileSeconds = nil
        diagnostics.phase = phase.rawValue
        let started = Date()
        let ready = await waitUntilReady()
        guard token == generation else { return .superseded }
        guard ready else { return .failed }
        let time = CMTime(seconds: max(0, fileSeconds), preferredTimescale: 44_100)
        let sought = await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        guard token == generation else { return .superseded }
        guard sought else { return .failed }
        let prerolled: Bool = await withCheckedContinuation { continuation in
            player.preroll(atRate: 1.0) { continuation.resume(returning: $0) }
        }
        guard token == generation else { return .superseded }
        guard prerolled else { return .failed }
        prerolledFileSeconds = fileSeconds
        phase = .prerolled
        diagnostics.phase = phase.rawValue
        diagnostics.prerolledFileSeconds = fileSeconds
        diagnostics.prerollDoneAt = Date()
        diagnostics.prerollMilliseconds = Date().timeIntervalSince(started) * 1000
        return .ready
    }

    private func waitUntilReady() async -> Bool {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            switch item.status {
            case .readyToPlay: return true
            case .failed: return false
            default: try? await Task.sleep(for: .milliseconds(10))
            }
        }
        return false
    }

    /// Programa el arranque del archivo en `fileSeconds` a la hora de host `hostTime` y el fundido que empieza en ella.
    /// `onFinished` se llama en el hilo principal al terminar el fundido.
    func commit(fileSeconds: Double, hostTime: CMTime, old: AVPlayer, output: Float, onFinished: @escaping @MainActor () -> Void) -> Bool {
        guard phase == .prerolled, prerolledFileSeconds == fileSeconds else { return false }
        let start = hostTime.seconds
        let now = Self.hostSeconds()
        guard start - now > 0.04 else { return false }
        player.volume = 0
        player.setRate(1.0, time: CMTime(seconds: fileSeconds, preferredTimescale: 44_100), atHostTime: hostTime)
        phase = .scheduled
        diagnostics.phase = phase.rawValue
        diagnostics.scheduledHostSeconds = start
        diagnostics.scheduledLeadSeconds = start - now
        diagnostics.scheduledFileSeconds = fileSeconds
        runCrossfade(startSeconds: start, old: old, output: output, onFinished: onFinished)
        return true
    }

    private func runCrossfade(startSeconds: Double, old: AVPlayer, output: Float, onFinished: @escaping @MainActor () -> Void) {
        cancelTimer()
        let duration = AudioCrossfade.duration
        let queue = DispatchQueue(label: "sideb.automix.crossfade", qos: .userInteractive)
        timerQueue = queue
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        let delay = max(0, startSeconds - Self.hostSeconds() - 0.01)
        source.schedule(deadline: .now() + delay, repeating: .milliseconds(2), leeway: .microseconds(200))
        nonisolated(unsafe) let newPlayer = player
        nonisolated(unsafe) let oldPlayer = old
        nonisolated(unsafe) var announced = false
        source.setEventHandler { [weak self] in
            let host = AudioSpliceSwitcher.hostSeconds()
            let progress = AudioCrossfade.progress(hostSeconds: host, startSeconds: startSeconds, duration: duration)
            let gains = AudioCrossfade.gains(progress: progress, output: output)
            newPlayer.volume = gains.new
            oldPlayer.volume = gains.old
            if progress > 0, !announced {
                announced = true
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.crossfadeBegan(startSeconds: startSeconds) } }
            }
            if progress >= 1 {
                source.cancel()
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.crossfadeEnded(host: host); onFinished() } }
            }
        }
        timer = source
        source.resume()
    }

    private func crossfadeBegan(startSeconds: Double) {
        guard phase == .scheduled else { return }
        phase = .crossfading
        diagnostics.phase = phase.rawValue
        diagnostics.crossfadeStartHost = startSeconds
    }

    private func crossfadeEnded(host: Double) {
        guard phase == .scheduled || phase == .crossfading else { return }
        phase = .done
        diagnostics.phase = phase.rawValue
        diagnostics.crossfadeEndHost = host
    }

    /// Para el temporizador del fundido y espera a que termine una pasada en curso: así ninguna escritura tardía de
    /// volumen puede pisar la restauración que haga quien lo cancela.
    private func cancelTimer() {
        timer?.cancel()
        timer = nil
        timerQueue?.sync {}
        timerQueue = nil
    }

    /// Gancho de pruebas: da el archivo por precargado en ese segundo sin tocar el audio del sistema.
    func markPrerolledForTesting(fileSeconds: Double) {
        prerolledFileSeconds = fileSeconds
        phase = .prerolled
        diagnostics.phase = phase.rawValue
        diagnostics.prerolledFileSeconds = fileSeconds
    }

    func recordMeasuredOffset(milliseconds: Double) { diagnostics.measuredOffsetMilliseconds = milliseconds }
    func note(_ text: String) { diagnostics.note = text }

    /// Deshace el arranque programado y el fundido (pausa, salto, parada del tema): el archivo vuelve a callar y la
    /// canción recupera su volumen. Puede volver a precargarse con `prepare`.
    func abort(restoring old: AVPlayer, output: Float) {
        guard phase != .done else { return }
        generation += 1
        cancelTimer()
        player.pause()
        player.volume = 0
        old.volume = output
        prerolledFileSeconds = nil
        phase = .aborted
        diagnostics.phase = phase.rawValue
        diagnostics.scheduledHostSeconds = nil
        diagnostics.crossfadeStartHost = nil
        diagnostics.crossfadeEndHost = nil
    }

    /// Suelta el reproductor y el elemento (el archivo se descarta o ya no hace falta).
    func dispose() {
        generation += 1
        cancelTimer()
        player.pause()
        player.volume = 0
        player.replaceCurrentItem(with: nil)
        prerolledFileSeconds = nil
        phase = .aborted
        diagnostics.phase = "descartado"
    }
}
