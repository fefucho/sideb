import Foundation
import Darwin.Mach

// PLAN-024: persistencia del diagnóstico de Automix. El búfer circular vive en memoria y se pierde con un cierre
// inesperado; cada línea (ya saneada) se añade también a `<carpeta de Automix>/diagnostics.log` desde una cola en
// segundo plano, con rotación a ~1 MB (queda un `.1`), y al arrancar se recargan las últimas ~1000 líneas.

// MARK: - Normalización y nivel

enum AutomixLogLimits {
    /// Tope por entrada (bytes UTF-8): cabe un mensaje de error largo entero, pero no una cadena desbocada.
    static let maxEntryBytes = 4096

    /// Una línea: saltos de línea escapados y tope de tamaño cortando en un límite de carácter.
    static func normalize(_ message: String, maxBytes: Int = maxEntryBytes) -> String {
        var text = message
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
        guard text.utf8.count > maxBytes else { return text }
        var bytes = 0
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let size = String(scalar).utf8.count
            if bytes + size > maxBytes { break }
            kept.append(scalar)
            bytes += size
        }
        let dropped = text.utf8.count - bytes
        text = String(kept) + "…[truncado: \(dropped) B más]"
        return text
    }
}

enum AutomixLogLevel: Equatable, Sendable {
    case notice, error

    /// Los fallos van al registro unificado como `.error`; el resto como `.notice` (que sí se conserva en disco).
    static func classify(_ message: String) -> AutomixLogLevel {
        let lower = message.lowercased()
        let markers = ["falló", "fallo", "error", "no se pudo", "sin transición", "descartada: contrato", "imposible", "rechazad", "abandonad"]
        return markers.contains { lower.contains($0) } ? .error : .notice
    }
}

// MARK: - Formato de archivo

struct AutomixPersistedLine: Equatable, Sendable {
    var date: Date
    var source: String
    var message: String
}

enum AutomixLogFileFormat {
    /// `2026-11-16 12:34:56.789 [origen] mensaje`
    static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }

    static func line(_ entry: AutomixPersistedLine, formatter: DateFormatter) -> String {
        "\(formatter.string(from: entry.date)) [\(entry.source)] \(entry.message)"
    }

    static func parse(_ text: String, formatter: DateFormatter) -> AutomixPersistedLine? {
        // 23 caracteres de fecha, espacio, «[origen]», espacio, mensaje.
        guard text.count > 26, let open = text.firstIndex(of: "["), let close = text.firstIndex(of: "]"), open < close else { return nil }
        let stamp = text[text.startIndex..<open].trimmingCharacters(in: .whitespaces)
        guard let date = formatter.date(from: stamp) else { return nil }
        let source = String(text[text.index(after: open)..<close])
        var message = text[text.index(after: close)...]
        if message.first == " " { message = message.dropFirst() }
        return AutomixPersistedLine(date: date, source: source, message: String(message))
    }
}

// MARK: - Archivo con rotación

/// Escribe líneas en `diagnostics.log` desde una cola propia y rota a `maxBytes` dejando un solo `.1`.
final class AutomixLogFile: @unchecked Sendable {
    static let fileName = "diagnostics.log"

    let directory: URL
    let maxBytes: Int
    private let queue = DispatchQueue(label: "sideb.automix.logfile", qos: .utility)
    private let formatter: DateFormatter
    private var handle: FileHandle?
    private var size = 0

    var currentURL: URL { directory.appendingPathComponent(Self.fileName) }
    var previousURL: URL { directory.appendingPathComponent(Self.fileName + ".1") }

    init(directory: URL, maxBytes: Int = 1 << 20, timeZone: TimeZone = .current) {
        self.directory = directory
        self.maxBytes = max(256, maxBytes)
        self.formatter = AutomixLogFileFormat.formatter(timeZone: timeZone)
    }

    /// Añade una línea sin bloquear a quien llama.
    func append(_ entry: AutomixPersistedLine) {
        queue.async { [self] in write(AutomixLogFileFormat.line(entry, formatter: formatter) + "\n") }
    }

    /// Espera a que se escriba lo pendiente (pruebas, exportación, cierre).
    func flush() { queue.sync {} }

    /// Últimas `limit` líneas válidas (del `.1` y del actual), de la más antigua a la más nueva.
    func readLastEntries(limit: Int) -> [AutomixPersistedLine] {
        queue.sync {
            closeHandle()
            let lines = (readText(previousURL) + readText(currentURL)).split(separator: "\n", omittingEmptySubsequences: true)
            return lines.suffix(limit).compactMap { AutomixLogFileFormat.parse(String($0), formatter: formatter) }
        }
    }

    /// Todo el registro persistido (`.1` y actual), tal cual está en disco.
    func fullText() -> String {
        queue.sync {
            closeHandle()
            return readText(previousURL) + readText(currentURL)
        }
    }

    func reset() {
        queue.sync {
            closeHandle()
            try? FileManager.default.removeItem(at: currentURL)
            try? FileManager.default.removeItem(at: previousURL)
            size = 0
        }
    }

    // MARK: Cola de escritura

    private func write(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if handle == nil { openHandle() }
        if size > 0, size + data.count > maxBytes { rotate() }
        guard let handle else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            size += data.count
        } catch {
            closeHandle() // se reabre en la próxima línea; aquí no se puede registrar el fallo sin recursión
        }
    }

    private func openHandle() {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: currentURL.path) { manager.createFile(atPath: currentURL.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: currentURL)
        size = (try? manager.attributesOfItem(atPath: currentURL.path)[.size] as? NSNumber)?.intValue ?? 0
    }

    private func rotate() {
        closeHandle()
        let manager = FileManager.default
        try? manager.removeItem(at: previousURL)
        try? manager.moveItem(at: currentURL, to: previousURL)
        size = 0
        openHandle()
    }

    private func closeHandle() {
        try? handle?.close()
        handle = nil
    }

    private func readText(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Memoria

struct AutomixMemoryInfo: Equatable, Sendable {
    /// `phys_footprint` de la app (lo que cuenta Activity Monitor como «Memoria»).
    var footprint: UInt64
    /// Pico del `phys_footprint` desde que arrancó el proceso.
    var peak: UInt64
}

enum AutomixMemory {
    nonisolated(unsafe) private static var observedPeak: UInt64 = 0

    static func current() -> AutomixMemoryInfo? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let footprint = UInt64(info.phys_footprint)
        observedPeak = max(observedPeak, footprint, UInt64(info.ledger_phys_footprint_peak))
        return AutomixMemoryInfo(footprint: footprint, peak: observedPeak)
    }

    static func gigabytes(_ bytes: UInt64) -> String { String(format: "%.2f GB", Double(bytes) / Double(1 << 30)) }
}

/// Avisa cada vez que la huella cruza 2, 4 y 8 GB hacia arriba (y vuelve a armarse al bajar un 10 % por debajo).
struct AutomixMemoryWatcher: Equatable, Sendable {
    static let defaultThresholds: [UInt64] = [2, 4, 8].map { $0 << 30 }

    let thresholds: [UInt64]
    private var armed: Set<UInt64>

    init(thresholds: [UInt64] = AutomixMemoryWatcher.defaultThresholds) {
        self.thresholds = thresholds.sorted()
        self.armed = Set(thresholds)
    }

    /// Umbrales cruzados desde la última lectura.
    mutating func update(footprint: UInt64) -> [UInt64] {
        var crossed: [UInt64] = []
        for threshold in thresholds {
            if armed.contains(threshold), footprint >= threshold {
                armed.remove(threshold)
                crossed.append(threshold)
            } else if !armed.contains(threshold), Double(footprint) < Double(threshold) * 0.9 {
                armed.insert(threshold)
            }
        }
        return crossed
    }
}

// MARK: - Exportación

enum AutomixDiagnosticsExport {
    /// Texto plano de la instantánea (para el informe exportado).
    static func snapshotLines(_ snapshot: AutomixDiagnosticsSnapshot) -> [String] {
        func yesNo(_ value: Bool) -> String { value ? "sí" : "no" }
        func f(_ value: Double, _ digits: Int = 3) -> String { value.isFinite ? String(format: "%.\(digits)f", value) : "—" }
        var lines: [String] = []
        lines.append("Ajuste guardado: \(snapshot.settingEnabled ? "encendido" : "apagado")")
        lines.append("Jam activo: \(yesNo(snapshot.jamActive)); repetir un tema: \(yesNo(snapshot.repeatOne)); el tema ya sonó: \(yesNo(snapshot.hasStarted))")
        lines.append("Elegibilidad: \(snapshot.eligibility ?? "elegible")")
        lines.append("Estado del coordinador: \(snapshot.coordinatorStatus)")
        lines.append("Modelo listo: \(snapshot.modelReady.map(yesNo) ?? "—")")
        let s = snapshot.settings
        lines.append("Ajustes del core: calidad \(s.quality), rápida con batería \(yesNo(s.fastOnBattery)), saltar mismo álbum \(yesNo(s.skipSameAlbum)), procesador \(s.compute), adelanto \(s.lookahead), modelo en memoria \(yesNo(s.keepModelLoaded))")
        if let c = snapshot.capability {
            lines.append("Capacidad: modelo \(c.modelReady ? "listo" : "no listo")\(c.modelDownloading ? " (descargando)" : ""), factor \(c.realtimeFactor.map { String(format: "%.2f×", $0) } ?? "sin medir"), stems recomendado \(yesNo(c.stemsRecommended)), proveedor \(c.provider.isEmpty ? "—" : c.provider)")
        }
        lines.append("Energía: batería \(yesNo(snapshot.power.onBattery)); bajo consumo \(yesNo(snapshot.power.lowPower))")
        if let memory = snapshot.memory {
            lines.append("Memoria: huella \(AutomixMemory.gigabytes(memory.footprint)) (\(memory.footprint) B); pico \(AutomixMemory.gigabytes(memory.peak)) (\(memory.peak) B)")
        }
        lines.append("Actual: \(track(snapshot.current))")
        lines.append("Siguiente: \(track(snapshot.next))")
        lines.append("Precarga: \(snapshot.prefetchItems.map { $0.map(\.videoID).joined(separator: " → ") } ?? "ninguna"); estado: \(snapshot.prefetchStatus)")
        if let r = snapshot.request {
            lines.append("Petición \(r.requestID): fase \(r.phase.rawValue), \(r.from.videoID) → \(r.to.videoID)\(r.forced ? " (forzada)" : ""), "
                + "transcurrido \(f(r.elapsed(now: snapshot.date), 1)) s, calidad pedida \(r.requestedQuality) / obtenida \(r.transition?.quality ?? "—")")
            lines.append("Mejora a stems: \(r.upgrade)")
            if let note = r.note { lines.append("Nota: \(note)") }
            if let label = r.failureLabel { lines.append("Fallo: \(label)") }
            if let raw = r.rawError { lines.append("Mensaje del core: \(AutomixLogLimits.normalize(raw))") }
        } else {
            lines.append("Petición: ninguna")
        }
        if let t = snapshot.transition {
            lines.append("Transición: \(t.kind) · \(t.detail)")
            lines.append("  bpm \(f(t.bpmFrom, 1)) / \(f(t.bpmTo, 1)), compases \(t.bars), stemsModel \(yesNo(t.stemsModel)), quality \(t.quality), sameCutAsFast \(yesNo(t.sameCutAsFast))")
            lines.append("  aCut \(f(t.aCut)), overlap \(f(t.overlapStart)) / \(f(t.overlapEnd)), bOffset \(f(t.bOffset)), bEntry \(f(t.bEntry)), handover \(f(t.handover)), duración \(f(t.fileDuration))")
            lines.append("  separatedSeconds \(f(t.separatedSeconds, 1)), elapsedSeconds \(f(t.elapsedSeconds, 1)), archivo \(snapshot.fileSize.map { "\($0) B" } ?? "no existe")")
        }
        let p = snapshot.player
        lines.append("Reproductor: etapa \(p.stage), tiempo crudo \(f(p.rawItemSeconds)), sesgo \(f(p.timeBias)), mostrado \(f(p.displayedSeconds)), "
            + "isPlaying \(yesNo(p.isPlaying)), isBuffering \(yesNo(p.isBuffering)), timeControlStatus \(p.timeControlStatus)\(p.waitingReason.map { ", espera \($0)" } ?? "")")
        for item in p.items { lines.append("  elemento \(item)") }
        if let sp = snapshot.splice {
            lines.append("Segundo reproductor: fase \(sp.phase), precarga \(sp.prerolledFileSeconds.map { f($0) } ?? "—") s, arranque programado \(sp.scheduledHostSeconds.map { f($0) } ?? "no"), "
                + "fundido \(sp.crossfadeStartHost.map { f($0) } ?? "—") / \(sp.crossfadeEndHost.map { f($0) } ?? "—"), desfase medido \(sp.measuredOffsetMilliseconds.map { f($0, 2) + " ms" } ?? "—")")
        }
        if let c = snapshot.countdown {
            lines.append("Cuentas atrás: archivo \(f(c.fileSeconds)), corte \(f(c.untilCut)), solape \(f(c.untilOverlapStart)) / \(f(c.untilOverlapEnd)), traspaso \(f(c.untilHandover)), fin \(f(c.untilFileEnd))")
        }
        return lines
    }

    private static func track(_ line: AutomixTrackLine?) -> String {
        guard let line else { return "—" }
        return "\(line.title) · \(line.videoID) · álbum \(line.albumID?.isEmpty == false ? line.albumID! : "—") · \(line.queueIndex.map { "#\($0)" } ?? "fuera de la cola")"
    }

    /// El informe completo: cabecera, estado actual, registro persistido entero y registro del core.
    static func render(header: [String], snapshot: AutomixDiagnosticsSnapshot, persistedLog: String, coreLog: String?) -> String {
        var out: [String] = []
        out.append("=== Diagnóstico de Automix (Side B, Mac) ===")
        out.append(contentsOf: header)
        out.append("")
        out.append("=== Estado actual ===")
        out.append(contentsOf: snapshotLines(snapshot))
        out.append("")
        out.append("=== Registro de la app (diagnostics.log y .1, ya saneado) ===")
        out.append(persistedLog.isEmpty ? "(vacío)" : persistedLog.trimmingCharacters(in: .newlines))
        out.append("")
        out.append("=== Registro del core (automix.log) ===")
        let core = coreLog.map { AutomixLogSanitizer.sanitize($0).trimmingCharacters(in: .newlines) } ?? ""
        out.append(core.isEmpty ? "(no existe o está vacío)" : core)
        out.append("")
        return out.joined(separator: "\n")
    }
}

enum AutomixDiagnosticsFiles {
    /// `20261116-123456`
    static func stamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    static func header(directory: URL, date: Date = Date()) -> [String] {
        let info = Bundle.main.infoDictionary
        return [
            "Fecha: \(AutomixLogFileFormat.formatter(timeZone: .current).string(from: date))",
            "App: \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?")), pid \(ProcessInfo.processInfo.processIdentifier)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Carpeta de registros: \(directory.path)"
        ]
    }

    /// `automix.log` del core (y su `.1` si existiera), o nil si no hay.
    static func readCoreLog(directory: URL) -> String? {
        let names = ["automix.log.1", "automix.log"]
        let parts = names.compactMap { name -> String? in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
