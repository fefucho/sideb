import SwiftUI
import AppKit

/// Ventana de diagnóstico del Automix (beta). Valores en monoespaciada, secciones agrupadas. Sólo se calcula
/// mientras está abierta: el `TimelineView` refresca la instantánea cada 0,25 s y desaparece al cerrarla.
/// Los textos son de depuración y se dejan en español (no pasan por el catálogo); el título de la ventana y el
/// menú sí están localizados.
struct AutomixDiagnosticsView: View {
    let player: PlayerViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let snapshot = player.automixDiagnosticsSnapshot(now: context.date)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        AutomixDiagnosticsSections(snapshot: snapshot)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 220)
                Divider()
                actions(snapshot)
                Divider()
                AutomixLogList(log: AutomixDiagnostics.shared.log)
                    .equatable()
                    .frame(minHeight: 170)
            }
        }
        .frame(minWidth: 560, minHeight: 560)
        .accessibilityIdentifier("automix-diagnostics")
    }

    /// Guarda un .txt con el estado actual, todo el registro persistido de la app y el `automix.log` del core.
    @MainActor
    private static func export(_ snapshot: AutomixDiagnosticsSnapshot) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let stamp = AutomixDiagnosticsFiles.stamp(Date())
        panel.nameFieldStringValue = "automix-diagnostico-\(stamp).txt"
        panel.title = "Exportar diagnóstico de Automix"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let store = AutomixDiagnostics.shared
        let directory = store.logDirectory ?? AutomixPreferences.cacheDirectory
        let file = store.file
        let header = AutomixDiagnosticsFiles.header(directory: directory)
        // Lectura y escritura fuera del hilo principal: los registros pueden pesar un par de MB.
        Task.detached(priority: .userInitiated) {
            let persisted = file?.fullText() ?? ""
            let core = AutomixDiagnosticsFiles.readCoreLog(directory: directory)
            let text = AutomixDiagnosticsExport.render(header: header, snapshot: snapshot, persistedLog: persisted, coreLog: core)
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                await MainActor.run { store.record("sesión", "diagnóstico exportado: \(text.utf8.count) B") }
            } catch {
                await MainActor.run { store.record("sesión", "no se pudo exportar el diagnóstico: \(error.localizedDescription)") }
            }
        }
    }

    /// Muestra en Finder la carpeta con `diagnostics.log` (y el `automix.log` del core).
    @MainActor
    private static func revealLogs() {
        let store = AutomixDiagnostics.shared
        store.file?.flush()
        let directory = store.logDirectory ?? AutomixPreferences.cacheDirectory
        if let log = store.file?.currentURL, FileManager.default.fileExists(atPath: log.path) {
            NSWorkspace.shared.activateFileViewerSelecting([log])
        } else {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        }
    }

    private func actions(_ snapshot: AutomixDiagnosticsSnapshot) -> some View {
        let fileURL = snapshot.transition.map { URL(fileURLWithPath: $0.filePath) }
        let fileExists = fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        // Muchos botones: se reparten en filas según el ancho de la ventana.
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
            Button("Copiar registro") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(AutomixDiagnostics.shared.log.text(), forType: .string)
            }
            Button("Limpiar registro") { AutomixDiagnostics.shared.clear() }
                .help("Vacía esta ventana; diagnostics.log en disco se conserva para exportarlo")
            Button("Exportar diagnóstico…") { Self.export(snapshot) }
            Button("Mostrar carpeta de registros") { Self.revealLogs() }
            Button("Mostrar archivo en Finder") { if let fileURL { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) } }
                .disabled(!fileExists)
            Button("Abrir archivo en el reproductor") { if let fileURL { NSWorkspace.shared.open(fileURL) } }
                .disabled(!fileExists)
            Button("Cancelar preparación") { player.automix.cancelPreparation() }
                .disabled(!snapshot.canCancel)
            Button("Preparar ahora") { player.automix.prepareNow() }
                .disabled(!snapshot.canPrepareNow)
            Button("Saltar a 10 s antes del corte") { player.automixJumpBeforeCut() }
                .disabled(snapshot.jumpTarget == nil)
        }
        .controlSize(.small)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Secciones

private struct AutomixDiagnosticsSections: View {
    let snapshot: AutomixDiagnosticsSnapshot

    var body: some View {
        section("Memoria") {
            if let m = snapshot.memory {
                row("Huella (phys_footprint)", "\(AutomixMemory.gigabytes(m.footprint))  (\(ByteCountFormatter.string(fromByteCount: Int64(m.footprint), countStyle: .memory)))")
                row("Pico", "\(AutomixMemory.gigabytes(m.peak))  (\(ByteCountFormatter.string(fromByteCount: Int64(m.peak), countStyle: .memory)))")
                row("Avisos", "una línea en el registro al cruzar 2, 4 y 8 GB")
            } else {
                row("Huella", "no disponible")
            }
        }
        section("Ajuste y estado efectivo") {
            row("Ajuste guardado", onOff(snapshot.settingEnabled))
            row("Jam activo", yesNo(snapshot.jamActive))
            row("Repetir un tema", yesNo(snapshot.repeatOne))
            row("El tema ya sonó", yesNo(snapshot.hasStarted) + (snapshot.isLoadingStream ? " (resolviendo stream)" : ""))
            row("Elegibilidad", snapshot.eligibility ?? "elegible")
            row("Estado del coordinador", snapshot.coordinatorStatus)
            row("Modelo (automixModelReady)", snapshot.modelReady.map(yesNo) ?? "—")
        }
        section("Estrategia de calidad") {
            let st = snapshot.strategy
            row("Stems permitidos", (st.allowStems ?? snapshot.request?.allowStems).map(yesNo) ?? "—")
            row("Por qué", st.allowReason.isEmpty ? (snapshot.request?.allowReason ?? "—") : st.allowReason)
            row("Pareja lista (ahora)", snapshot.pairReadyNow.map(yesNo) ?? "—")
            row("Pareja lista (última lectura)", st.pairReady.map { yesNo($0) + (st.pairReadyAt.map { " a las " + Self.clock($0) } ?? "") } ?? "—")
            row("Precarga con stems", snapshot.prefetchAllowStems.map { $0 ? "permitidos" : "no permitidos" } ?? "—")
            if let r = snapshot.request {
                row("Primera petición", "\(r.requestedQuality) (pareja lista al pedir: \(yesNo(r.pairReadyAtRequest)))")
            }
        }
        section("Ajustes del core, capacidad y energía") {
            let st = snapshot.settings
            row("Calidad", "\(st.quality)   (auto = decide la capacidad)")
            row("Rápida con batería", yesNo(st.fastOnBattery))
            row("Saltar mismo álbum", yesNo(st.skipSameAlbum))
            row("Procesador / adelanto", "\(st.compute) / \(st.lookahead)")
            row("Modelo en memoria", yesNo(st.keepModelLoaded))
            if let c = snapshot.capability {
                row("Capacidad", "modelo \(c.modelReady ? "listo" : "no listo")\(c.modelDownloading ? " (descargando)" : ""); "
                    + "factor \(c.realtimeFactor.map { String(format: "%.2f×", $0) } ?? "sin medir"); "
                    + "stems recomendado: \(yesNo(c.stemsRecommended)); proveedor \(c.provider.isEmpty ? "—" : c.provider)")
            } else {
                row("Capacidad", "—")
            }
            row("Energía", "batería: \(yesNo(snapshot.power.onBattery)); bajo consumo: \(yesNo(snapshot.power.lowPower))")
            if let items = snapshot.prefetchItems {
                row("Precarga", items.map(\.videoID).joined(separator: " → "))
                if let at = snapshot.prefetchRequestedAt { row("Precarga pedida", Self.clock(at)) }
            } else {
                row("Precarga", "ninguna")
            }
            row("Estado de la precarga", snapshot.prefetchStatus)
        }
        section("Temas") {
            row("Actual", track(snapshot.current))
            row("Siguiente", track(snapshot.next))
        }
        section("Petición") {
            if let request = snapshot.request {
                row("Fase", phase(request))
                row("Id de petición", request.requestID)
                row("Par", "\(request.from.videoID) → \(request.to.videoID)\(request.forced ? " (forzada)" : "")")
                row("Pedida", Self.clock(request.requestedAt))
                row("Transcurrido", String(format: "%.1f s", request.elapsed(now: snapshot.date)) + (request.finishedAt == nil ? " (en curso)" : ""))
                row("Calidad pedida / obtenida", "\(request.requestedQuality) / \(request.transition?.quality ?? "—")")
                row("Mejora a stems", request.upgrade)
                if let at = request.upgradeRequestedAt {
                    let end = request.upgradeFinishedAt ?? snapshot.date
                    row("Mejora: tiempo", String(format: "%.1f s", max(0, end.timeIntervalSince(at))) + (request.upgradeFinishedAt == nil && request.upgrade.hasPrefix("pedida") ? " (en curso)" : ""))
                }
                if let note = request.note { row("Nota", note) }
                if let label = request.failureLabel { row("Fallo", label) }
                if let raw = request.rawError { row("Mensaje del core", raw) }
            } else {
                row("Fase", snapshot.settingEnabled && snapshot.eligibility == nil
                    ? (snapshot.hasStarted ? "esperando" : "esperando a que el tema suene") : "sin petición")
            }
        }
        section("Transición (AutomixTransitionRecord)") {
            if let t = snapshot.transition {
                row("kind", t.kind)
                row("detail", t.detail)
                row("bpmFrom / bpmTo / bars", "\(f(t.bpmFrom, 1)) / \(f(t.bpmTo, 1)) / \(t.bars)")
                row("stemsModel", yesNo(t.stemsModel))
                row("quality / sameCutAsFast", "\(t.quality) / \(yesNo(t.sameCutAsFast))")
                row("reused", yesNo(t.reused) + (t.reused ? " (el core devolvió el archivo ya renderizado)" : ""))
                row("separatedSeconds", f(t.separatedSeconds, 1) + " s")
                row("elapsedSeconds (core)", f(t.elapsedSeconds, 1) + " s")
                row("aCut", f(t.aCut) + " s")
                row("overlapStart / End", "\(f(t.overlapStart)) / \(f(t.overlapEnd)) s")
                row("bOffset", f(t.bOffset) + " s")
                row("bEntry", f(t.bEntry) + " s")
                row("handover", f(t.handover) + " s")
                row("fileDuration", f(t.fileDuration) + " s")
                row("filePath", t.filePath)
                row("Tamaño del archivo", snapshot.fileSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) + " (\($0) B)" } ?? "no existe")
            } else {
                row("Registro", "aún no hay")
            }
        }
        section("Reproductor") {
            let p = snapshot.player
            row("Etapa del empalme", "\(p.stage)")
            row("Elementos en cola", "\(p.items.count)")
            ForEach(Array(p.items.enumerated()), id: \.offset) { _, item in row("", item) }
            row("Tiempo crudo del elemento", f(p.rawItemSeconds) + " s")
            row("timeBias", f(p.timeBias) + " s")
            row("Tiempo mostrado", f(p.displayedSeconds) + " s")
            row("forwardPlaybackEndTime", p.forwardEndSeconds.map { f($0) + " s" } ?? "—")
            row("isPlaying / isBuffering", "\(yesNo(p.isPlaying)) / \(yesNo(p.isBuffering))")
            row("timeControlStatus", p.timeControlStatus)
            row("reasonForWaitingToPlay", p.waitingReason ?? "—")
        }
        section("Segundo reproductor (empalme)") {
            if let sp = snapshot.splice {
                row("Fase", sp.phase)
                row("Precarga", sp.prerolledFileSeconds.map { "lista en el segundo \(f($0)) del archivo" + (sp.prerollMilliseconds.map { " (\(f($0, 0)) ms)" } ?? "") } ?? "pendiente")
                row("Arranque programado", sp.scheduledHostSeconds.map { "hora de host \(f($0)) s, archivo \(f(sp.scheduledFileSeconds ?? 0)) s, con \(f((sp.scheduledLeadSeconds ?? 0) * 1000, 0)) ms de adelanto" } ?? "no")
                row("Inicio / fin del fundido", "\(sp.crossfadeStartHost.map { f($0) } ?? "—") / \(sp.crossfadeEndHost.map { f($0) } ?? "—") s de host (50 ms)")
                row("Desfase medido", sp.measuredOffsetMilliseconds.map { f($0, 2) + " ms (canción − archivo)" } ?? "—")
                if let note = sp.note { row("Nota", note) }
            } else {
                row("Empalme", "no hay archivo cargado en un segundo reproductor")
            }
        }
        section("Cuentas atrás (negativo = ya pasó)") {
            if let c = snapshot.countdown {
                row("Segundo del archivo", f(c.fileSeconds) + " s")
                row("Hasta el corte", f(c.untilCut) + " s")
                row("Hasta el inicio del solape", f(c.untilOverlapStart) + " s")
                row("Hasta el fin del solape", f(c.untilOverlapEnd) + " s")
                row("Hasta el traspaso", f(c.untilHandover) + " s")
                row("Hasta el final del archivo", f(c.untilFileEnd) + " s")
            } else {
                row("Sin empalme", "no hay transición armada ni sonando")
            }
        }
    }

    // MARK: Piezas

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) { content() }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 190, alignment: .leading)
            Text(verbatim: value).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11.5))
    }

    private func f(_ v: Double, _ digits: Int = 3) -> String { v.isFinite ? String(format: "%.\(digits)f", v) : "—" }
    private func yesNo(_ v: Bool) -> String { v ? "sí" : "no" }
    private func onOff(_ v: Bool) -> String { v ? "encendido" : "apagado" }

    private func track(_ line: AutomixTrackLine?) -> String {
        guard let line else { return "—" }
        let index = line.queueIndex.map { "#\($0)" } ?? "fuera de la cola"
        return "\(line.title) · \(line.videoID) · álbum \(line.albumID?.isEmpty == false ? line.albumID! : "—") · \(index)"
    }

    private func phase(_ request: AutomixRequestInfo) -> String {
        switch request.phase {
        case .preparing: "preparando"
        case .ready: "lista"
        case .failed: "falló"
        case .cancelled: "cancelada"
        }
    }

    private static func clock(_ date: Date) -> String { AutomixEventLog.timestamp(date) }
}

// MARK: - Registro

/// Sólo se vuelve a dibujar cuando el registro cambia (último id y cantidad).
private struct AutomixLogList: View, Equatable {
    let log: AutomixEventLog

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.log.lastID == rhs.log.lastID && lhs.log.entries.count == rhs.log.entries.count }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(log.entries) { entry in
                        Text(verbatim: entry.line())
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                    }
                }
                .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: log.lastID) { _, last in
                if let last { proxy.scrollTo(last, anchor: .bottom) }
            }
            .onAppear { if let last = log.lastID { proxy.scrollTo(last, anchor: .bottom) } }
        }
    }
}
