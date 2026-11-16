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
    /// Cómo arrancó el archivo: «sincronizado» (hora de host) o «play()» (dispositivo no integrado o recuperación).
    var startPath: String?
    /// Dispositivo de salida predeterminado en el momento de comprometer el empalme.
    var outputDevice: String?
    /// El arranque sincronizado no avanzó y se repitió con `play()`.
    var fellBackToPlain = false
    /// Correcciones (saltos de alineación con el archivo mudo) antes del fundido en el arranque simple, y el último error medido.
    var alignCorrections: Int?
    var alignErrorMilliseconds: Double?
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

    let player: CountedPlayer
    private(set) var item: AVPlayerItem
    /// Tras un arranque sincronizado que no avanzó, se vuelve a intentar sólo con `play()`.
    var forcePlain = false
    private(set) var phase: Phase = .idle
    private(set) var prerolledFileSeconds: Double?
    private(set) var diagnostics = AutomixSpliceDiagnostics()
    /// Verdadero desde que se programó el arranque: el empalme ya no admite cambiar de archivo.
    var isCommitted: Bool { phase == .scheduled || phase == .crossfading || phase == .done }

    private var timer: DispatchSourceTimer?
    private var timerQueue: DispatchQueue?
    private var alignTask: Task<Void, Never>?
    private var generation = 0

    /// `player`: el reproductor de repuesto del servicio (se reutiliza: Side B no crea ni destruye clientes de audio en cada
    /// empalme, y nunca hay más de dos `AVPlayer` vivos).
    init(asset: AVURLAsset, player: CountedPlayer = CountedPlayer()) {
        self.player = player
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
        // Tras un `abort` el elemento se soltó del reproductor (no deja su canalización de audio viva): se vuelve a poner.
        if player.currentItem !== item { player.replaceCurrentItem(with: item) }
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
    /// `mode`: `.hostSynced` arranca con `setRate(_:time:atHostTime:)`; `.plain` llama a `play()` en el instante del fundido.
    /// `onFinished(advancing)` dice si el archivo estaba de verdad avanzando al terminar el fundido.
    func commit(fileSeconds: Double, prerolledAt: Double? = nil, hostTime: CMTime, old: AVPlayer, output: Float, mode: AudioSpliceStartMode,
                device: AudioOutputDevice?, onFinished: @escaping @MainActor (Bool) -> Void) -> Bool {
        guard phase == .prerolled, prerolledFileSeconds == (prerolledAt ?? fileSeconds) else { return false }
        let start = hostTime.seconds
        let now = Self.hostSeconds()
        guard start - now > 0.04 else { return false }
        player.volume = 0
        if mode == .hostSynced {
            player.setRate(1.0, time: CMTime(seconds: fileSeconds, preferredTimescale: 44_100), atHostTime: hostTime)
        } else {
            // Arranque simple: `plainLeadIn` antes del empalme el archivo empieza a sonar (mudo) desde donde se precargó y se
            // alinea con la canción antes del fundido. Arrancar con `play()` justo en el fundido llega tarde con salidas de
            // latencia alta (una virtual como eqMac): la canción ya se habría apagado. (Se programa tras `runCrossfade`,
            // que reinicia los temporizadores.)
        }
        lastMode = mode
        diagnostics.startPath = mode == .hostSynced ? "sincronizado (setRate atHostTime)" : "play() mudo con antelación y alineado por saltos (\(Int(AudioSpliceTimeline.plainLeadIn * 1000)) ms)"
        diagnostics.outputDevice = device?.summary ?? "desconocido"
        phase = .scheduled
        diagnostics.phase = phase.rawValue
        diagnostics.scheduledHostSeconds = start
        diagnostics.scheduledLeadSeconds = start - now
        diagnostics.scheduledFileSeconds = fileSeconds
        runCrossfade(startSeconds: start, old: old, output: output, plainStart: false, onFinished: onFinished)
        if mode == .plain { startAligning(fileSeconds: fileSeconds, switchHost: start) }
        return true
    }

    /// Alinea el archivo mudo con la canción: cada 15 ms compara dónde está con dónde debería estar a esa hora de host
    /// (`fileSeconds + (ahora − hora del empalme)`) y, si difiere más de 4 ms, salta al sitio correcto. Es mudo, no se oye.
    private func startAligning(fileSeconds: Double, switchHost: Double) {
        alignTask?.cancel()
        alignTask = Task { @MainActor [weak self] in
            var corrections = 0
            // Espera hasta `plainLeadIn` antes del empalme y arranca (mudo): el archivo se precargó `plainLeadIn` antes.
            while !Task.isCancelled, Self.hostSeconds() < switchHost - AudioSpliceTimeline.plainLeadIn - 0.004 {
                try? await Task.sleep(for: .milliseconds(4))
            }
            guard !Task.isCancelled, let started = self else { return }
            started.player.play()
            // Lo que tarda un salto en completarse (se mide y se corrige en cada vuelta): el destino se calcula para cuando
            // el salto termine, no para cuando empieza.
            var seekLatency = 0.12
            while let self, !Task.isCancelled, Self.hostSeconds() < switchHost - 0.06 {
                try? await Task.sleep(for: .milliseconds(15))
                guard !Task.isCancelled else { return }
                let host = Self.hostSeconds()
                let position = self.player.currentTime().seconds
                guard position.isFinite, self.player.rate > 0 else { continue } // aún no arrancó
                let error = position - (fileSeconds + (host - switchHost))
                self.diagnostics.alignErrorMilliseconds = error * 1000
                if abs(error) > 0.010, corrections < 10, host < switchHost - 0.08 - seekLatency {
                    corrections += 1
                    let target = fileSeconds + (host - switchHost) + seekLatency
                    _ = await self.player.seek(to: CMTime(seconds: max(0, target), preferredTimescale: 44_100), toleranceBefore: .zero, toleranceAfter: .zero)
                    seekLatency = min(0.4, max(0.02, Self.hostSeconds() - host))
                }
            }
            self?.diagnostics.alignCorrections = corrections
        }
    }

    private func runCrossfade(startSeconds: Double, old: AVPlayer, output: Float, plainStart: Bool,
                              onFinished: @escaping @MainActor (Bool) -> Void) {
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
        nonisolated(unsafe) var playCalled = false
        source.setEventHandler { [weak self] in
            let host = AudioSpliceSwitcher.hostSeconds()
            // Arranque sencillo: `play()` unos milisegundos antes del fundido (el archivo ya está precargado).
            if plainStart, !playCalled, host >= startSeconds - 0.012 {
                playCalled = true
                newPlayer.play()
            }
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
                DispatchQueue.main.async { MainActor.assumeIsolated { onFinished(self?.crossfadeEnded(host: host) ?? false) } }
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

    /// Devuelve si el archivo está avanzando de verdad (reproduciendo y con el tiempo por encima de donde arrancó).
    private func crossfadeEnded(host: Double) -> Bool {
        guard phase == .scheduled || phase == .crossfading else { return false }
        // El temporizador ya terminó: se suelta (guardaba referencias fuertes a los dos reproductores).
        timer = nil
        timerQueue = nil
        phase = .done
        diagnostics.phase = phase.rawValue
        diagnostics.crossfadeEndHost = host
        let started = diagnostics.scheduledFileSeconds ?? 0
        let now = player.currentTime().seconds
        // Avanzando = reproduciendo y cerca de lo previsto. Con el arranque sincronizado debe estar ya por encima de donde
        // arrancó; con el simple se admite hasta 300 ms de retraso (queda anotado como desfase medido).
        let advancing = player.rate > 0 && now >= (lastMode == .plain ? started - 0.3 : started + 0.01)
        AutomixDiagnostics.shared.record("player", "fin del fundido: archivo tasa \(player.rate), tiempo \(String(format: "%.3f", now)) s (previsto ≈ \(String(format: "%.3f", started + AudioCrossfade.duration)) s), "
            + "estado \(player.timeControlStatus.rawValue), correcciones \(diagnostics.alignCorrections.map(String.init) ?? "—"), último error de alineación \(diagnostics.alignErrorMilliseconds.map { String(format: "%.1f ms", $0) } ?? "—"); "
            + "avanza \(advancing ? "sí" : "NO")")
        return advancing
    }

    /// El arranque sincronizado no avanzó: se deshace y la próxima confirmación usa `play()`.
    func fallBackToPlain() {
        forcePlain = true
        diagnostics.fellBackToPlain = true
    }

    /// Para el temporizador del fundido y espera a que termine una pasada en curso: así ninguna escritura tardía de
    /// volumen puede pisar la restauración que haga quien lo cancela.
    private func cancelTimer() {
        alignTask?.cancel()
        alignTask = nil
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

    /// Cambia el archivo (stems en lugar de la rápida) **en el mismo reproductor**: no se crea otro `AVPlayer`, así que
    /// nunca hay más de dos vivos (el de la canción y éste).
    func reload(asset: AVURLAsset) {
        generation += 1
        cancelTimer()
        player.pause()
        player.volume = 0
        player.replaceCurrentItem(with: nil)
        item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        prerolledFileSeconds = nil
        phase = .idle
        diagnostics = AutomixSpliceDiagnostics(phase: phase.rawValue)
    }

    /// Cómo se arrancó la última vez (para decidir si repetir con `play()`).
    private(set) var lastMode: AudioSpliceStartMode?

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
        // Se suelta el elemento: un reproductor pausado con el elemento cargado y precargado mantiene viva su
        // canalización de audio (un cliente más del dispositivo de salida). `prepare` lo vuelve a poner.
        player.replaceCurrentItem(with: nil)
        prerolledFileSeconds = nil
        phase = .aborted
        diagnostics.phase = phase.rawValue
        diagnostics.scheduledHostSeconds = nil
        diagnostics.crossfadeStartHost = nil
        diagnostics.crossfadeEndHost = nil
    }

    /// Stops this switcher's timers without touching its player: used when the player has become the
    /// service's active one and must keep playing whatever is loaded next.
    func detach() {
        generation += 1
        cancelTimer()
        prerolledFileSeconds = nil
        phase = .done
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
