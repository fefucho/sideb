import Foundation
import AVFoundation
import Observation
import os

// PLAN-024: diagnóstico del Automix. El almacén sólo registra (barato, siempre); la instantánea se calcula bajo
// demanda y únicamente mientras la ventana de diagnóstico está abierta. Nada de esto cambia la reproducción.

// MARK: - Saneado

/// Quita de cualquier línea lo que no debe llegar nunca a un registro: URLs, cabeceras, cookies, firmas y tokens.
enum AutomixLogSanitizer {
    private static let rules: [(NSRegularExpression, String)] = {
        let patterns: [(String, String)] = [
            (#"(?i)\b[a-z][a-z0-9+.\-]*://[^\s"'<>)\]]+"#, "<url>"),
            // Cabeceras que llevan credenciales: todo el resto de la línea.
            (#"(?i)\b(set-cookie|cookie|authorization|proxy-authorization)\s*[:=].*"#, "$1=<redacted>"),
            (#"(?i)\b(x-goog-[a-z\-]+|x-youtube-[a-z\-]+|visitor-data|po[_-]?token|sapisid\w*|sid|ssid|hsid|apisid|signature|sig|key|token|range)\s*[:=]\s*[^\s,;]+"#, "$1=<redacted>"),
            (#"[A-Za-z0-9_\-%.]{48,}"#, "<token>")
        ]
        return patterns.compactMap { pattern, template in
            (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
        }
    }()

    static func sanitize(_ text: String) -> String {
        var result = text
        for (regex, template) in rules {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        return result
    }
}

// MARK: - Registro circular

struct AutomixLogEntry: Equatable, Sendable, Identifiable {
    let id: UInt64
    let date: Date
    /// Origen corto: coord, player, vm, jam…
    let source: String
    let message: String

    /// `HH:mm:ss.SSS [origen] mensaje`
    func line(calendar: Calendar = .current) -> String {
        "\(AutomixEventLog.timestamp(date, calendar: calendar)) [\(source)] \(message)"
    }
}

/// Búfer circular de eventos: conserva los `capacity` más recientes, del más antiguo al más nuevo.
struct AutomixEventLog: Equatable, Sendable {
    static let defaultCapacity = 1000

    let capacity: Int
    private(set) var entries: [AutomixLogEntry] = []
    private var nextID: UInt64 = 1

    init(capacity: Int = AutomixEventLog.defaultCapacity) { self.capacity = max(1, capacity) }

    @discardableResult
    mutating func append(source: String, message: String, date: Date = Date()) -> AutomixLogEntry {
        let entry = AutomixLogEntry(id: nextID, date: date, source: source, message: message)
        nextID &+= 1
        entries.append(entry)
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        return entry
    }

    mutating func clear() { entries.removeAll(keepingCapacity: true) }

    var lastID: UInt64? { entries.last?.id }

    func text(calendar: Calendar = .current) -> String {
        entries.map { $0.line(calendar: calendar) }.joined(separator: "\n")
    }

    static func timestamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return String(format: "%02d:%02d:%02d.%03d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0,
                      min(999, (parts.nanosecond ?? 0) / 1_000_000))
    }
}

// MARK: - Cuentas atrás

/// Segundos que faltan para cada hito de la transición, medidos sobre el tiempo del archivo. Un valor negativo
/// significa que el hito ya pasó.
struct AutomixCountdown: Equatable, Sendable {
    /// Segundo del archivo que suena ahora (negativo mientras la canción aún no llegó al corte).
    var fileSeconds: Double
    var untilCut: Double
    var untilOverlapStart: Double
    var untilOverlapEnd: Double
    var untilHandover: Double
    var untilFileEnd: Double

    /// `itemSeconds` es el tiempo crudo del elemento actual; `timeBias` el sesgo vigente (tiempo del elemento menos
    /// tiempo mostrado). Con el empalme armado el elemento es la canción y el archivo aún no suena: su segundo 0 es `cut`.
    static func make(timeline: AudioSpliceTimeline, stage: AudioSpliceStage, itemSeconds: Double, timeBias: Double) -> AutomixCountdown? {
        guard itemSeconds.isFinite, timeBias.isFinite else { return nil }
        let file: Double
        switch stage {
        case .none: return nil
        case .armed: file = (itemSeconds - timeBias) - timeline.cut
        case .inFile, .handedOver: file = itemSeconds
        }
        return AutomixCountdown(fileSeconds: file, untilCut: -file, untilOverlapStart: timeline.overlapStart - file,
                                untilOverlapEnd: timeline.overlapEnd - file, untilHandover: timeline.handover - file,
                                untilFileEnd: timeline.fileDuration - file)
    }
}

enum AutomixDebugActions {
    /// Segundos de la canción adonde saltar para oír el empalme enseguida, o nil si no corresponde (la canción ya
    /// pasó el corte o no hay corte).
    static func jumpTarget(cut: Double, position: Double, lead: Double = 10) -> Double? {
        guard cut.isFinite, position.isFinite, cut > 0, position < cut else { return nil }
        return max(0, cut - lead)
    }
}

// MARK: - Fase de la petición

struct AutomixRequestInfo: Equatable, Sendable {
    enum Phase: String, Sendable { case preparing, ready, failed, cancelled }

    var requestID: String
    var from: AutomixSong
    var to: AutomixSong
    var requestedAt: Date
    var finishedAt: Date?
    var phase: Phase
    var forced: Bool
    /// Mensaje crudo del core, ya saneado.
    var rawError: String?
    var failureLabel: String?
    var transition: AutomixTransition?
    /// Qué pasó después de prepararse (entrega al reproductor, descarte…).
    var note: String?
    /// Calidad pedida en esta petición ("fast"); la obtenida está en `transition.quality`.
    var requestedQuality: String = "fast"
    /// Estado de la mejora a stems: sin decidir, no pedida (motivo), pedida, aplicada, omitida, falló…
    var upgrade: String = "sin decidir"
    var upgradeRequestedAt: Date?
    var upgradeFinishedAt: Date?
    /// Si los stems estaban permitidos al pedir y por qué.
    var allowStems = false
    var allowReason = ""
    /// `automixPairReady` en el momento de pedir.
    var pairReadyAtRequest = false

    func elapsed(now: Date) -> TimeInterval { max(0, (finishedAt ?? now).timeIntervalSince(requestedAt)) }
}

/// Última decisión de estrategia (permiso de stems y estado de la pareja), para el diagnóstico.
struct AutomixStrategyInfo: Equatable, Sendable {
    var allowStems: Bool?
    var allowReason = ""
    var pairReady: Bool?
    var pairReadyAt: Date?
}

// MARK: - Instantánea

struct AutomixTrackLine: Equatable, Sendable {
    var title: String
    var videoID: String
    var albumID: String?
    var queueIndex: Int?
}

struct AutomixPlayerSnapshot: Equatable, Sendable {
    var stage: AudioSpliceStage
    var items: [String]
    var currentIndex: Int?
    var rawItemSeconds: Double
    var timeBias: Double
    var displayedSeconds: Double
    var forwardEndSeconds: Double?
    var isPlaying: Bool
    var isBuffering: Bool
    var timeControlStatus: String
    var waitingReason: String?
}

struct AutomixDiagnosticsSnapshot: Equatable, Sendable {
    var date: Date
    var settingEnabled: Bool
    var jamActive: Bool
    var repeatOne: Bool
    var hasStarted: Bool
    var isLoadingStream: Bool
    /// Motivo exacto de elegibilidad: nil si corresponde preparar.
    var eligibility: String?
    var coordinatorStatus: String
    var current: AutomixTrackLine?
    var next: AutomixTrackLine?
    var request: AutomixRequestInfo?
    var modelReady: Bool?
    var transition: AutomixTransition?
    var fileSize: Int64?
    var player: AutomixPlayerSnapshot
    var countdown: AutomixCountdown?
    var canPrepareNow: Bool
    var canCancel: Bool
    var jumpTarget: Double?
    var settings: AutomixSettingsValue = AutomixSettingsValue()
    var capability: AutomixCapabilityValue?
    var power: AutomixPowerState = AutomixPowerState()
    var prefetchItems: [AutomixSong]?
    var prefetchStatus: String = "sin precarga"
    var prefetchRequestedAt: Date?
    /// Cronología del segundo reproductor (precarga, arranque programado, fundido, desfase medido).
    var splice: AutomixSpliceDiagnostics?
    var memory: AutomixMemoryInfo?
    var strategy = AutomixStrategyInfo()
    var prefetchAllowStems: Bool?
    /// `automixPairReady` leído ahora (con caché breve) para la pareja actual → siguiente.
    var pairReadyNow: Bool?
}

// MARK: - Almacén

@MainActor
@Observable
final class AutomixDiagnostics {
    static let shared = AutomixDiagnostics()

    @ObservationIgnored private(set) var log = AutomixEventLog()
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fefucho.SideB", category: "automix")
    @ObservationIgnored private var modelReadyCache: (value: Bool?, date: Date)?
    @ObservationIgnored private var fileSizeCache: (path: String, size: Int64?, date: Date)?
    @ObservationIgnored private var powerCache: (value: AutomixPowerState, date: Date)?
    @ObservationIgnored private var pairReadyCache: (key: String, value: Bool, date: Date)?

    /// Archivo persistente (nil hasta `configurePersistence`: las pruebas y el modo sin carpeta no escriben a disco).
    @ObservationIgnored private(set) var file: AutomixLogFile?
    @ObservationIgnored private var memoryTimer: Timer?
    @ObservationIgnored private var memoryWatcher = AutomixMemoryWatcher()
    /// Lectura de la huella (se sustituye en las pruebas).
    @ObservationIgnored var memoryReader: () -> AutomixMemoryInfo? = { AutomixMemory.current() }
    /// Resume la fase de Automix para las líneas de memoria (lo pone el reproductor).
    @ObservationIgnored var phaseProvider: (@MainActor () -> String)?

    init(capacity: Int = AutomixEventLog.defaultCapacity, memoryThresholds: [UInt64] = AutomixMemoryWatcher.defaultThresholds) {
        log = AutomixEventLog(capacity: capacity)
        memoryWatcher = AutomixMemoryWatcher(thresholds: memoryThresholds)
    }

    /// Registra una línea en el búfer, en `diagnostics.log` y en el registro unificado (`.notice`, `.error` si es un
    /// fallo: así se conserva). Va saneada (nunca URLs, cookies ni cabeceras), en una sola línea y con tope por entrada.
    func record(_ source: String, _ message: String, date: Date = Date()) {
        let clean = AutomixLogLimits.normalize(AutomixLogSanitizer.sanitize(message))
        let entry = log.append(source: source, message: clean, date: date)
        let line = entry.line()
        switch AutomixLogLevel.classify(clean) {
        case .error: logger.error("\(line, privacy: .public)")
        case .notice: logger.notice("\(line, privacy: .public)")
        }
        file?.append(AutomixPersistedLine(date: date, source: source, message: clean))
    }

    /// Activa la persistencia: recarga las últimas ~1000 líneas de la sesión anterior en la ventana y deja una marca de
    /// inicio. `maxBytes` se rota a un `.1`.
    func configurePersistence(directory: URL, maxBytes: Int = 1 << 20, reload: Int = AutomixEventLog.defaultCapacity) {
        let file = AutomixLogFile(directory: directory, maxBytes: maxBytes)
        let previous = file.readLastEntries(limit: reload)
        for line in previous { log.append(source: line.source, message: line.message, date: line.date) }
        self.file = file
        let info = Bundle.main.infoDictionary
        record("sesión", "inicio de sesión — \(previous.count) líneas recargadas de la anterior; app \(info?["CFBundleShortVersionString"] as? String ?? "?") "
            + "(\(info?["CFBundleVersion"] as? String ?? "?")), pid \(ProcessInfo.processInfo.processIdentifier), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    /// Mide la huella cada 2 s (una llamada a `task_info`) y deja una línea al cruzar 2, 4 y 8 GB con la fase de Automix.
    func startMemoryWatch(interval: TimeInterval = 2) {
        memoryTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkMemory() }
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        memoryTimer = timer
        checkMemory()
    }

    func checkMemory() {
        guard let memory = memoryReader() else { return }
        for threshold in memoryWatcher.update(footprint: memory.footprint) {
            record("mem", "la huella de memoria cruzó \(threshold >> 30) GB: actual \(AutomixMemory.gigabytes(memory.footprint)), "
                + "pico \(AutomixMemory.gigabytes(memory.peak)); fase de Automix: \(phaseProvider?() ?? "desconocida")")
        }
    }

    /// Carpeta de los registros (la de las cachés de Automix) si hay persistencia.
    var logDirectory: URL? { file?.directory }

    /// Vacía la ventana; el archivo en disco se conserva (es lo que se exporta).
    func clear() { log.clear() }

    /// Lectura con caché breve: la ventana consulta cada 0,25 s, el sistema de ficheros no hace falta tanto.
    func cachedModelReady(now: Date, read: () -> Bool?) -> Bool? {
        if let cache = modelReadyCache, now.timeIntervalSince(cache.date) < 1 { return cache.value }
        let value = read()
        modelReadyCache = (value, now)
        return value
    }

    func cachedPairReady(key: String, now: Date, read: () -> Bool) -> Bool {
        if let cache = pairReadyCache, cache.key == key, now.timeIntervalSince(cache.date) < 2 { return cache.value }
        let value = read()
        pairReadyCache = (key, value, now)
        return value
    }

    func cachedPower(now: Date, read: () -> AutomixPowerState) -> AutomixPowerState {
        if let cache = powerCache, now.timeIntervalSince(cache.date) < 2 { return cache.value }
        let value = read()
        powerCache = (value, now)
        return value
    }

    func cachedFileSize(path: String, now: Date) -> Int64? {
        if let cache = fileSizeCache, cache.path == path, now.timeIntervalSince(cache.date) < 2 { return cache.size }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
        fileSizeCache = (path, size, now)
        return size
    }
}
