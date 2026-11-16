import Foundation
import IOKit.ps
import SideBCore

// PLAN-024: lógica pura del Automix (DJ) del Mac. Nada aquí toca red, AVFoundation ni el core:
// se prueba sin red. La preparación real vive en `SideBCore.prepareAutomix`.

/// Transición renderizada por el core, ya validada y en tipos de Swift. Los segundos «archivo» son
/// del WAV; `aCut`, `bEntry` y `handover` se explican en `AutomixTransitionRecord`.
struct AutomixTransition: Equatable, Sendable {
    var requestID: String
    var fromVideoID: String
    var toVideoID: String
    /// "mix", "cut" o "fade".
    var kind: String
    var filePath: String
    var fileDuration: Double
    /// Segundo de la canción ACTUAL que suena en el segundo 0 del archivo.
    var aCut: Double
    var overlapStart: Double
    var overlapEnd: Double
    /// Segundo del archivo menos segundo de la canción siguiente (exacto desde `overlapEnd`).
    var bOffset: Double
    /// Primer segundo de la siguiente que está en el archivo.
    var bEntry: Double
    /// Segundo del archivo en que la UI pasa a mostrar la siguiente.
    var handover: Double
    var bpmFrom: Double
    var bpmTo: Double
    var bars: Int
    var stemsModel: Bool
    var detail: String
    /// Calidad pedida al core: "fast" o "stems".
    var quality: String
    /// El render de stems corta en el mismo sitio que el rápido. Puede ser falso: el plan de stems es propio (con voces,
    /// hasta 16 compases) y su corte y solape pueden diferir de los de la versión rápida.
    var sameCutAsFast: Bool
    /// Segundos de audio que separó el modelo en esta llamada (0 con «fast» o con una precarga).
    var separatedSeconds: Double
    /// Segundos de pared que tardó la preparación en el core, descargas incluidas.
    var elapsedSeconds: Double
    /// El core devolvió un archivo ya renderizado en vez de volver a prepararlo.
    var reused: Bool

    init(requestID: String, fromVideoID: String, toVideoID: String, kind: String, filePath: String,
         fileDuration: Double, aCut: Double, overlapStart: Double, overlapEnd: Double, bOffset: Double,
         bEntry: Double, handover: Double, bpmFrom: Double = 0, bpmTo: Double = 0, bars: Int = 0,
         stemsModel: Bool = false, detail: String = "", quality: String = "fast", sameCutAsFast: Bool = true,
         separatedSeconds: Double = 0, elapsedSeconds: Double = 0, reused: Bool = false) {
        self.requestID = requestID; self.fromVideoID = fromVideoID; self.toVideoID = toVideoID
        self.kind = kind; self.filePath = filePath; self.fileDuration = fileDuration; self.aCut = aCut
        self.overlapStart = overlapStart; self.overlapEnd = overlapEnd; self.bOffset = bOffset
        self.bEntry = bEntry; self.handover = handover; self.bpmFrom = bpmFrom; self.bpmTo = bpmTo
        self.bars = bars; self.stemsModel = stemsModel; self.detail = detail
        self.quality = quality; self.sameCutAsFast = sameCutAsFast
        self.separatedSeconds = separatedSeconds; self.elapsedSeconds = elapsedSeconds; self.reused = reused
    }

    init(record: AutomixTransitionRecord) {
        self.init(requestID: record.requestId, fromVideoID: record.fromVideoId, toVideoID: record.toVideoId,
                  kind: record.kind, filePath: record.filePath, fileDuration: record.fileDurationSeconds,
                  aCut: record.aCutSeconds, overlapStart: record.overlapStartSeconds,
                  overlapEnd: record.overlapEndSeconds, bOffset: record.bOffsetSeconds,
                  bEntry: record.bEntrySeconds, handover: record.handoverSeconds,
                  bpmFrom: record.bpmFrom, bpmTo: record.bpmTo, bars: Int(record.bars),
                  stemsModel: record.stemsModel, detail: record.detail, quality: record.quality,
                  sameCutAsFast: record.sameCutAsFast, separatedSeconds: record.separatedSeconds,
                  elapsedSeconds: record.elapsedSeconds, reused: record.reused)
    }

    /// Rechaza un registro incoherente en vez de reproducirlo: cualquier valor no finito o fuera de orden.
    var isConsistent: Bool {
        let values = [fileDuration, aCut, overlapStart, overlapEnd, bOffset, bEntry, handover]
        guard values.allSatisfy(\.isFinite), ["mix", "cut", "fade"].contains(kind), !filePath.isEmpty else { return false }
        return fileDuration > 0 && aCut >= 0 && overlapStart > 0 && overlapStart <= overlapEnd
            && overlapEnd <= fileDuration && handover >= overlapStart && handover <= fileDuration
            && bEntry >= 0 && fileDuration - bOffset > 0
    }

    /// Tempo para el distintivo: el de la canción siguiente cuando hay estimación.
    var displayBPM: Double { bpmTo > 0 ? bpmTo : bpmFrom }

    var timeline: AudioSpliceTimeline {
        AudioSpliceTimeline(cut: aCut, overlapStart: overlapStart, overlapEnd: overlapEnd, handover: handover,
                            bOffset: bOffset, bEntry: bEntry, fileDuration: fileDuration)
    }
}

/// Dónde empieza la mezcla sobre la barra de progreso de la canción que suena (PLAN-024): el segundo de la
/// canción actual `aCut + overlapStart`, donde el archivo deja de ser la canción tal cual.
struct AutomixProgressMarker: Equatable, Sendable {
    /// Segundos de la canción actual (los que muestra la barra).
    var songSeconds: Double
    /// Versión de la transición que sonará: "fast" (rápida) o "stems" (buena). La barra las distingue.
    var quality: String

    init?(transition: AutomixTransition) {
        let seconds = transition.aCut + transition.overlapStart
        guard seconds.isFinite, seconds >= 0 else { return nil }
        songSeconds = seconds
        quality = transition.quality == "stems" ? "stems" : "fast"
    }

    init(songSeconds: Double, quality: String = "fast") { self.songSeconds = songSeconds; self.quality = quality }

    /// La marca es de la versión buena (con stems).
    var isGood: Bool { quality == "stems" }

    /// Posición en la barra (0…1), o nil si no cabe: sin duración conocida o si la mezcla empezaría al final o después.
    func fraction(duration: Double) -> Double? {
        guard duration.isFinite, duration > 0, songSeconds.isFinite, songSeconds >= 0, songSeconds < duration else { return nil }
        return songSeconds / duration
    }

    /// Geometría sobre una barra de `width` puntos: la marca y el tramo teñido desde ella hasta el final.
    func layout(duration: Double, width: Double) -> (tickX: Double, segmentWidth: Double)? {
        guard width.isFinite, width > 0, let fraction = fraction(duration: duration) else { return nil }
        let x = width * fraction
        return (x, width - x)
    }
}

/// Lo que el Automix necesita saber de una canción de la cola.
struct AutomixSong: Equatable, Sendable {
    var videoID: String
    var isUpload: Bool
    var albumID: String?

    init(videoID: String, isUpload: Bool = false, albumID: String? = nil) {
        self.videoID = videoID; self.isUpload = isUpload; self.albumID = albumID
    }

    init(_ song: SongItemRecord) {
        self.init(videoID: song.videoId, isUpload: song.isUpload, albumID: song.albumId)
    }
}

/// Foto del reproductor que el coordinador evalúa cada vez.
struct AutomixContext: Equatable, Sendable {
    /// Identidad de la ocurrencia que suena (el token de reproducción del `PlayerViewModel`).
    var token: UUID
    var current: AutomixSong
    /// Siguiente tema conocido de la cola (nunca uno que aún haya que resolver o pedir a una radio).
    var next: AutomixSong?
    var jamActive: Bool
    var repeatOne: Bool
    /// El tema ya está sonando de verdad (no sólo resolviéndose o cargando).
    var hasStarted: Bool
    /// Ajuste del core: no mezclar canciones seguidas del mismo álbum.
    var skipSameAlbum: Bool = true
    /// Siguientes temas conocidos de la cola, en orden (para la precarga del core).
    var upcoming: [AutomixSong] = []
    /// Ajuste del core: cuántos temas siguientes se precargan (1 a 3).
    var lookahead: Int = 1
}

/// Identidad de un plan de preparación: **la pareja** (de → a). El `token` (la ocurrencia de reproducción que suena)
/// no forma parte de la igualdad: reiniciar o buscar en el mismo tema cambia el token pero no la pareja, y cancelar y
/// volver a pedir la misma pareja es justo el vaivén que el core evita uniendo peticiones idénticas.
struct AutomixPlanKey: Hashable, Sendable {
    var token: UUID
    var from: String
    var to: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.from == rhs.from && lhs.to == rhs.to }
    func hash(into hasher: inout Hasher) { hasher.combine(from); hasher.combine(to) }
}

enum AutomixUnavailableReason: Equatable, Sendable {
    case jam
    case repeatOne
    case noNextTrack
    case sameTrack
    case sameAlbum
    case unsupportedFormat
    case tooLong
    case tooLate
    case failed
}

enum AutomixEligibility {
    /// Motivo por el que no se prepara una transición, o `nil` si corresponde prepararla.
    static func reason(_ context: AutomixContext) -> AutomixUnavailableReason? {
        if context.jamActive { return .jam }
        if context.repeatOne { return .repeatOne }
        guard let next = context.next else { return .noNextTrack }
        if next.videoID == context.current.videoID { return .sameTrack }
        // Pistas del mismo disco suenan seguidas a propósito (discos conceptuales, en vivo): no se mezclan.
        if context.skipSameAlbum, let from = context.current.albumID, !from.isEmpty, from == next.albumID { return .sameAlbum }
        return nil
    }
}

/// Fallos del core que la interfaz distingue, a partir del prefijo estable del mensaje de `StreamError`.
enum AutomixFailure: Error, Equatable, Sendable {
    case cancelled
    case unsupportedFormat
    case tooLong
    case badID
    /// `quality: "stems"` sin el modelo en disco (empieza a bajarse): se conserva la versión rápida.
    case modelUnavailable
    case badQuality
    case noCacheDir
    case other

    init(coreMessage message: String) {
        if message.hasPrefix("automix:cancelled") { self = .cancelled }
        else if message.hasPrefix("automix:unsupported-format") { self = .unsupportedFormat }
        else if message.hasPrefix("automix:too-long") { self = .tooLong }
        else if message.hasPrefix("automix:bad-id") { self = .badID }
        else if message.hasPrefix("automix:model-unavailable") { self = .modelUnavailable }
        else if message.hasPrefix("automix:bad-quality") { self = .badQuality }
        else if message.hasPrefix("automix:no-cache-dir") { self = .noCacheDir }
        else { self = .other }
    }

    /// Etiqueta para el registro: nunca el mensaje crudo (un error de red puede traer una URL firmada).
    var logLabel: String {
        switch self {
        case .cancelled: "cancelled"
        case .unsupportedFormat: "unsupported-format"
        case .tooLong: "too-long"
        case .badID: "bad-id"
        case .modelUnavailable: "model-unavailable"
        case .badQuality: "bad-quality"
        case .noCacheDir: "no-cache-dir"
        case .other: "other"
        }
    }

    var reason: AutomixUnavailableReason? {
        switch self {
        case .cancelled: nil
        case .unsupportedFormat: .unsupportedFormat
        case .tooLong: .tooLong
        case .badID, .modelUnavailable, .badQuality, .noCacheDir, .other: .failed
        }
    }
}

/// Fallo de una preparación con el mensaje crudo del core (para el diagnóstico; se sanea antes de mostrarlo).
struct AutomixFailureReport: Error, Equatable, Sendable {
    var failure: AutomixFailure
    var message: String
}

struct AutomixRequest: Equatable, Sendable {
    var requestID: String
    var from: AutomixSong
    var to: AutomixSong
    var cacheDirectory: URL
    /// "fast" (sin modelo) o "stems".
    var quality: String = "fast"
}

// MARK: - Ajustes, capacidad y estrategia de calidad

/// Ajustes del core (`AutomixSettings`) en un tipo propio, para que la lógica no dependa de UniFFI.
struct AutomixSettingsValue: Equatable, Sendable {
    /// "auto", "fast" o "stems".
    var quality = "auto"
    /// Apagado por defecto (como en el core).
    var fastOnBattery = false
    var skipSameAlbum = true
    /// "auto", "gpu" o "cpu".
    var compute = "auto"
    var lookahead = 1
    var keepModelLoaded = false

    init() {}

    init(record: AutomixSettings) {
        quality = record.quality; fastOnBattery = record.fastOnBattery; skipSameAlbum = record.skipSameAlbum
        compute = record.compute; lookahead = Int(record.lookahead); keepModelLoaded = record.keepModelLoaded
    }

    var record: AutomixSettings {
        AutomixSettings(quality: quality, fastOnBattery: fastOnBattery, skipSameAlbum: skipSameAlbum, compute: compute,
                        lookahead: UInt8(max(1, min(3, lookahead))), keepModelLoaded: keepModelLoaded)
    }
}

struct AutomixCapabilityValue: Equatable, Sendable {
    var modelReady = false
    var modelDownloading = false
    var realtimeFactor: Double?
    var stemsRecommended = false
    var provider = ""

    init() {}

    init(record: AutomixCapability) {
        modelReady = record.modelReady; modelDownloading = record.modelDownloading
        realtimeFactor = record.realtimeFactor; stemsRecommended = record.stemsRecommended; provider = record.provider
    }
}

struct AutomixCacheUsageValue: Equatable, Sendable {
    var audioBytes: UInt64 = 0
    var stemsBytes: UInt64 = 0
    var transitionsBytes: UInt64 = 0
    var modelBytes: UInt64 = 0
    var total: UInt64 { audioBytes + stemsBytes + transitionsBytes }
}

/// Estado de energía del Mac: la batería (IOPowerSources) y el modo de bajo consumo.
struct AutomixPowerState: Equatable, Sendable {
    var onBattery = false
    var lowPower = false

    static func current(lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled) -> AutomixPowerState {
        var onBattery = false
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let type = IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue() as String? {
            onBattery = type == kIOPMBatteryPowerKey
        }
        return AutomixPowerState(onBattery: onBattery, lowPower: lowPower)
    }
}

/// Estrategia de calidad (PLAN-024, ronda 4).
enum AutomixStrategy {
    /// ¿Se permiten los stems? Es el `allowStems` de la precarga y la condición para pedir `"stems"`:
    /// la calidad no es «siempre rápida» y no se está (con el ajuste activo) con batería o bajo consumo.
    static func allowStems(settings: AutomixSettingsValue, power: AutomixPowerState) -> (allowed: Bool, reason: String) {
        if settings.quality == "fast" { return (false, "calidad «siempre rápida»") }
        if settings.fastOnBattery, power.onBattery || power.lowPower {
            return (false, "con \(power.lowPower ? "bajo consumo" : "batería") sólo la versión rápida")
        }
        return (true, settings.quality == "stems" ? "calidad «siempre con stems»" : "calidad automática")
    }

    /// Calidad de la primera petición: stems directo si están permitidos y la pareja ya está lista en la caché
    /// (≈3–4 s); si no, la rápida enseguida.
    static func initialQuality(allowStems: Bool, pairReady: Bool) -> String { allowStems && pairReady ? "stems" : "fast" }

    /// Decisión y motivo para pedir stems además de la rápida: permitidos y (pareja lista, «siempre con stems» o
    /// automática con la capacidad recomendada).
    static func wantsStems(settings: AutomixSettingsValue, capability: AutomixCapabilityValue?, power: AutomixPowerState,
                           pairReady: Bool = false) -> (wants: Bool, reason: String) {
        let allow = allowStems(settings: settings, power: power)
        guard allow.allowed else { return (false, allow.reason) }
        if pairReady { return (true, "la pareja está lista en la caché de stems") }
        if settings.quality == "stems" { return (true, allow.reason) }
        guard let capability, capability.stemsRecommended else {
            return (false, "automática: esta Mac aún no recomienda stems (capacidad \(capability == nil ? "desconocida" : "insuficiente o sin medir")) y la pareja no está lista")
        }
        return (true, "automática: stems recomendado")
    }
}

/// Qué hacer cuando llega la versión de stems con la rápida ya entregada: su corte y solape pueden ser otros.
enum AutomixUpgradePlanner {
    /// Margen mínimo entre «ahora» y el corte de stems para cambiar a ella (le da tiempo al segundo reproductor).
    static let minimumLeadSeconds = 8.0

    enum Decision: Equatable {
        case apply(sameCut: Bool)
        case skip(String)
    }

    static func sameCut(_ a: AutomixTransition, _ b: AutomixTransition) -> Bool {
        abs(a.aCut - b.aCut) < 0.001 && abs(a.overlapStart - b.overlapStart) < 0.001 && abs(a.overlapEnd - b.overlapEnd) < 0.001
    }

    /// `position`: segundos de la canción que suena, o nil si aún no suena. `committed`: el arranque ya está programado
    /// o el archivo suena.
    static func decide(fast: AutomixTransition, stems: AutomixTransition, position: Double?, committed: Bool) -> Decision {
        if committed { return .skip("llegó tras el empalme") }
        let same = sameCut(fast, stems)
        guard let position, position.isFinite else { return .apply(sameCut: same) }
        let lead = stems.aCut - position
        if lead <= 0 { return .skip("el corte de stems (\(String(format: "%.1f", stems.aCut)) s) ya quedó atrás") }
        if !same, lead < minimumLeadSeconds {
            return .skip("el corte de stems queda a \(String(format: "%.1f", lead)) s (< \(Int(minimumLeadSeconds)) s) y no coincide con el de la rápida")
        }
        return .apply(sameCut: same)
    }
}

/// Qué temas se le pasan a `prefetchAutomix`: el que suena y `lookahead + 1` siguientes. El core separa la COLA de cada
/// tema de la lista y la CABEZA de todos menos el primero; para que `automixPairReady(next, next+1)` sea cierto cuando
/// `next` pase a sonar hace falta `next+1` en la lista, o sea `lookahead + 2` temas en total ([actual, next, next+1, …]).
enum AutomixPrefetchPlan {
    /// Máximo de temas siguientes que se miran (el adelanto va de 1 a 3 y siempre se añade uno más).
    static let maxUpcoming = 4

    static func items(current: AutomixSong, upcoming: [AutomixSong], lookahead: Int) -> [AutomixSong] {
        [current] + upcoming.prefix(max(1, min(3, lookahead)) + 1)
    }
}

/// Cuándo pedir la versión buena (stems) con la rápida ya lista: la precarga del core separa los temas por tramos y
/// una petición en primer plano la duplicaría, así que se espera a que la pareja quede lista en la caché (`automixPairReady`)
/// y, si aún no lo está, se pide una sola vez cuando faltan ~60 s para el corte (así el primer plano acelera la precarga).
enum AutomixUpgradeTiming {
    /// Segundos antes del corte en que se pide la buena aunque la precarga no haya terminado.
    static let foregroundLeadSeconds = 60.0

    enum Decision: Equatable {
        /// Pedirla ahora, por este motivo.
        case request(String)
        /// Esperar a la precarga.
        case wait
    }

    /// - Parameters:
    ///   - wants: los ajustes y la capacidad piden stems (sin contar la pareja lista).
    ///   - pairReady: `automixPairReady` ahora.
    ///   - secondsToCut: segundos que faltan para el corte de la rápida (nil si la canción aún no suena).
    static func decide(wants: Bool, pairReady: Bool, secondsToCut: Double?) -> Decision {
        if pairReady { return .request("la pareja ya está lista en la caché de stems") }
        guard wants else { return .wait }
        if let secondsToCut, secondsToCut.isFinite, secondsToCut <= foregroundLeadSeconds {
            return .request("faltan \(Int(max(0, secondsToCut).rounded())) s para el corte y la precarga no terminó: se pide en primer plano")
        }
        return .wait
    }
}

// MARK: - Línea de tiempo del archivo

/// Qué hacer con un salto del usuario mientras el archivo de la transición está (o va a estar) sonando.
enum AudioSeekRoute: Equatable, Sendable {
    /// Buscar en el elemento actual con la conversión de tiempos vigente.
    case direct
    /// La canción actual aún suena de su stream, pero el destino cae dentro del archivo: entrar en él.
    case intoFile
    /// El destino queda más allá de lo que el archivo reproduce igual que la canción: desarmar el empalme y buscar normal.
    case disarmThenDirect
    /// El archivo no contiene ese momento: resolver la canción y reproducirla desde ahí por la vía normal.
    case restream
}

enum AudioSpliceCommitDecision: Equatable, Sendable {
    /// Aún falta más de `commitLead` para el corte: seguir precargando.
    case wait
    /// Programar el arranque del archivo en ese segundo del archivo (0 = el corte; más = entrada tardía).
    case commit(fileSeconds: Double)
    /// Ya no cabe el fundido dentro de la parte del archivo que es la canción tal cual.
    case giveUp
}

enum AudioSpliceStage: Equatable, Sendable {
    case none
    /// El elemento del archivo está en cola detrás de la canción actual.
    case armed
    /// Suena el archivo y la interfaz aún muestra la canción anterior.
    case inFile
    /// Suena el archivo y la interfaz ya muestra la canción siguiente.
    case handedOver
}

/// Conversión de tiempos y rutas de salto del archivo. Puro y sin dependencias.
struct AudioSpliceTimeline: Equatable, Sendable {
    var cut: Double
    var overlapStart: Double
    var overlapEnd: Double
    var handover: Double
    var bOffset: Double
    var bEntry: Double
    var fileDuration: Double

    /// Hasta este margen antes del corte todavía se puede empalmar sin cortes.
    static let armMargin = 0.5
    /// Un salto no cae a menos de esto de donde termina la parte idéntica a la canción.
    static let overlapMargin = 0.5
    /// Un salto a la siguiente no cae antes de `bEntry` más esto.
    static let entryMargin = 0.25
    static let endMargin = 0.5

    /// `tiempo mostrado = tiempo del elemento − sesgo`. Antes del traspaso el archivo muestra la canción
    /// anterior desde `cut`; después, la siguiente desplazada `bOffset`.
    func bias(for stage: AudioSpliceStage) -> Double {
        switch stage {
        case .none: 0
        case .armed, .inFile: -cut
        case .handedOver: bOffset
        }
    }

    /// Fin de la canción siguiente tal como suena en el archivo.
    var nextDuration: Double { max(0, fileDuration - bOffset) }

    /// Cuánto antes del corte se programa el arranque del archivo (hay tiempo de sobra tras la precarga).
    static let commitLead = 0.9
    /// Cuánto después de «ahora» se pone el punto de empalme cuando el corte ya pasó o está encima.
    static let switchLead = 0.45
    /// Margen entre el fin del fundido y el fin de la parte del archivo idéntica a la canción.
    static let crossfadeEndMargin = 0.15
    /// Con el arranque simple (`play()`), el archivo arranca mudo esto antes del punto de empalme y se alinea con la canción:
    /// la salida (sobre todo una virtual) tarda en empezar a sonar y no se puede esperar al instante del fundido.
    static let plainLeadIn = 0.7

    /// Qué hacer con el empalme según la posición de la canción (segundos de la canción mostrada).
    func commitDecision(position: Double) -> AudioSpliceCommitDecision {
        guard position.isFinite else { return .giveUp }
        if position < cut - Self.commitLead { return .wait }
        let file = max(0, position + Self.switchLead - cut)
        return fits(fileSeconds: file) ? .commit(fileSeconds: file) : .giveUp
    }

    /// El fundido de 50 ms que empieza en `fileSeconds` cabe dentro de la primera parte del archivo.
    func fits(fileSeconds: Double) -> Bool {
        fileSeconds + AudioCrossfade.duration <= overlapStart - Self.crossfadeEndMargin
    }

    /// `target` está en segundos de la canción mostrada.
    func route(forSeek target: Double, stage: AudioSpliceStage) -> AudioSeekRoute {
        guard target.isFinite else { return .restream }
        switch stage {
        case .none:
            return .direct
        case .armed:
            if target < cut { return .direct }
            return target - cut <= overlapStart - Self.overlapMargin ? .intoFile : .disarmThenDirect
        case .inFile:
            let file = target - cut
            return file >= 0 && file <= overlapStart - Self.overlapMargin ? .direct : .restream
        case .handedOver:
            let file = target + bOffset
            return target >= bEntry + Self.entryMargin && file <= fileDuration - Self.endMargin ? .direct : .restream
        }
    }
}
