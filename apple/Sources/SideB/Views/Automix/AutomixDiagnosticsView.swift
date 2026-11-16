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

    private func actions(_ snapshot: AutomixDiagnosticsSnapshot) -> some View {
        let fileURL = snapshot.transition.map { URL(fileURLWithPath: $0.filePath) }
        let fileExists = fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        return HStack(spacing: 8) {
            Button("Copiar registro") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(AutomixDiagnostics.shared.log.text(), forType: .string)
            }
            Button("Limpiar registro") { AutomixDiagnostics.shared.clear() }
            Divider().frame(height: 16)
            Button("Mostrar archivo en Finder") { if let fileURL { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) } }
                .disabled(!fileExists)
            Button("Abrir archivo en el reproductor") { if let fileURL { NSWorkspace.shared.open(fileURL) } }
                .disabled(!fileExists)
            Divider().frame(height: 16)
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
        section("Ajuste y estado efectivo") {
            row("Ajuste guardado", onOff(snapshot.settingEnabled))
            row("Jam activo", yesNo(snapshot.jamActive))
            row("Repetir un tema", yesNo(snapshot.repeatOne))
            row("El tema ya sonó", yesNo(snapshot.hasStarted) + (snapshot.isLoadingStream ? " (resolviendo stream)" : ""))
            row("Elegibilidad", snapshot.eligibility ?? "elegible")
            row("Estado del coordinador", snapshot.coordinatorStatus)
            row("Modelo (automixModelReady)", snapshot.modelReady.map(yesNo) ?? "—")
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
