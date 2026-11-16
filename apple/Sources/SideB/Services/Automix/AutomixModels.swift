import Foundation
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

    init(requestID: String, fromVideoID: String, toVideoID: String, kind: String, filePath: String,
         fileDuration: Double, aCut: Double, overlapStart: Double, overlapEnd: Double, bOffset: Double,
         bEntry: Double, handover: Double, bpmFrom: Double = 0, bpmTo: Double = 0, bars: Int = 0,
         stemsModel: Bool = false, detail: String = "") {
        self.requestID = requestID; self.fromVideoID = fromVideoID; self.toVideoID = toVideoID
        self.kind = kind; self.filePath = filePath; self.fileDuration = fileDuration; self.aCut = aCut
        self.overlapStart = overlapStart; self.overlapEnd = overlapEnd; self.bOffset = bOffset
        self.bEntry = bEntry; self.handover = handover; self.bpmFrom = bpmFrom; self.bpmTo = bpmTo
        self.bars = bars; self.stemsModel = stemsModel; self.detail = detail
    }

    init(record: AutomixTransitionRecord) {
        self.init(requestID: record.requestId, fromVideoID: record.fromVideoId, toVideoID: record.toVideoId,
                  kind: record.kind, filePath: record.filePath, fileDuration: record.fileDurationSeconds,
                  aCut: record.aCutSeconds, overlapStart: record.overlapStartSeconds,
                  overlapEnd: record.overlapEndSeconds, bOffset: record.bOffsetSeconds,
                  bEntry: record.bEntrySeconds, handover: record.handoverSeconds,
                  bpmFrom: record.bpmFrom, bpmTo: record.bpmTo, bars: Int(record.bars),
                  stemsModel: record.stemsModel, detail: record.detail)
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

    init?(transition: AutomixTransition) {
        let seconds = transition.aCut + transition.overlapStart
        guard seconds.isFinite, seconds >= 0 else { return nil }
        songSeconds = seconds
    }

    init(songSeconds: Double) { self.songSeconds = songSeconds }

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
}

struct AutomixPlanKey: Hashable, Sendable {
    var token: UUID
    var from: String
    var to: String
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
        if let from = context.current.albumID, !from.isEmpty, from == next.albumID { return .sameAlbum }
        return nil
    }
}

/// Fallos del core que la interfaz distingue, a partir del prefijo estable del mensaje de `StreamError`.
enum AutomixFailure: Error, Equatable, Sendable {
    case cancelled
    case unsupportedFormat
    case tooLong
    case badID
    case other

    init(coreMessage message: String) {
        if message.hasPrefix("automix:cancelled") { self = .cancelled }
        else if message.hasPrefix("automix:unsupported-format") { self = .unsupportedFormat }
        else if message.hasPrefix("automix:too-long") { self = .tooLong }
        else if message.hasPrefix("automix:bad-id") { self = .badID }
        else { self = .other }
    }

    /// Etiqueta para el registro: nunca el mensaje crudo (un error de red puede traer una URL firmada).
    var logLabel: String {
        switch self {
        case .cancelled: "cancelled"
        case .unsupportedFormat: "unsupported-format"
        case .tooLong: "too-long"
        case .badID: "bad-id"
        case .other: "other"
        }
    }

    var reason: AutomixUnavailableReason? {
        switch self {
        case .cancelled: nil
        case .unsupportedFormat: .unsupportedFormat
        case .tooLong: .tooLong
        case .badID, .other: .failed
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

enum AudioSpliceArmDecision: Equatable, Sendable {
    /// Aún falta para el corte: empalme sin cortes con `forwardPlaybackEndTime`.
    case arm
    /// El corte ya pasó pero el archivo todavía es la canción tal cual: entrar al archivo en ese segundo.
    case lateEntry(fileSeconds: Double)
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

    func armDecision(position: Double) -> AudioSpliceArmDecision {
        guard position.isFinite else { return .giveUp }
        if position <= cut - Self.armMargin { return .arm }
        if position <= cut + overlapStart - Self.overlapMargin { return .lateEntry(fileSeconds: max(0, position - cut)) }
        return .giveUp
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
