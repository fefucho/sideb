import AppKit
import SwiftUI

/// Temporary floating panel to drive and inspect the Spotify Jam mirror. Not the final UI:
/// strings are intentionally not localized.
@MainActor
final class JamDebugWindow {
    static let shared = JamDebugWindow()
    private var panel: NSPanel?

    func show(player: PlayerViewModel?) {
        guard let player else { return }
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 680),
                                styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.title = "Spotify Jam · debug"
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: JamDebugView(controller: .shared, player: player))
            panel.center()
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}

private struct JamDebugView: View {
    var controller: JamSessionController
    var player: PlayerViewModel
    @State private var link = ""
    @State private var bearer = ""

    var body: some View {
        @Bindable var controller = controller
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                connection
                if controller.phase == .live {
                    Divider()
                    nowPlaying
                    Divider()
                    sync(offset: $controller.globalOffsetMs)
                    Divider()
                    versions
                    Divider()
                    queue
                }
                Divider()
                logView
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
        .frame(minWidth: 420, minHeight: 420)
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(status).font(.system(size: 13, weight: .semibold))
            if controller.isActive {
                HStack {
                    Text(controller.members.map { ($0.name ?? "?") + ($0.isHost ? " (anfitrión)" : $0.isMe ? " (yo)" : "") }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Salir del Jam") { controller.leave() }
                }
            } else {
                TextField("Link de invitación del Jam", text: $link)
                    .textFieldStyle(.roundedBorder)
                SecureField("Bearer de Spotify (opcional; si no, usa el login de Canvas)", text: $bearer)
                    .textFieldStyle(.roundedBorder)
                Button("Unirse") { controller.join(link: link, player: player, manualCredential: bearer) }
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let notice = controller.notice {
                Text("Aviso de Spotify: \(notice)").foregroundStyle(.orange)
            }
        }
    }

    private var status: String {
        switch controller.phase {
        case .idle: "Sin Jam"
        case .connecting: "Conectando…"
        case .live: "En el Jam de \(controller.hostName ?? "?")\(controller.canControl ? "" : " · sin control")"
        case .ended(let reason): "Jam terminado (\(reason))"
        case .failed(let reason): "Error: \(reason)"
        }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let track = controller.spotifyTrack {
                Text("Spotify: \(track.displayTitle) — \(track.displayArtists)")
                Text("ISRC \(track.isrc ?? "?") · \(time((track.durationMs ?? 0) / 1000))").foregroundStyle(.secondary)
            }
            if let matched = controller.matched {
                Text("YT Music: \(matched.song.title) — \(matched.song.artists)")
                Text("puntaje \(matched.score, specifier: "%.1f") · Δduración \(matched.durationDelta.map { String(format: "%+.0f s", $0) } ?? "?")\(matched.song.isVideo ? " · VIDEO" : "")")
                    .foregroundStyle(abs(matched.durationDelta ?? 0) > 1.6 ? .orange : .secondary)
            } else {
                Text("YT Music: sin equivalente").foregroundStyle(.orange)
            }
            HStack {
                Button("⏮") { controller.send("previous") }
                Button(controller.playback?.paused == true ? "▶︎" : "⏸") { controller.send(controller.playback?.paused == true ? "resume" : "pause") }
                Button("⏭") { controller.send("next") }
                Button("−10 s") { controller.seek(bySeconds: -10) }
                Button("+10 s") { controller.seek(bySeconds: 10) }
            }
            .disabled(!controller.canControl)
        }
    }

    private func sync(offset: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                Text("Jam \(time(controller.liveSeconds))")
                Text("Side B \(time(player.audioService.avPlayer.currentTime().seconds))")
                Text("desfase \(controller.driftMs.map { String(format: "%+.0f ms", $0) } ?? "—")")
                    .foregroundStyle(abs(controller.driftMs ?? 0) > 60 ? .orange : .green)
                Text("vel. \(player.audioService.avPlayer.rate, specifier: "%.2f")").foregroundStyle(.secondary)
                Text(controller.isAdjusting ? "ajustando" : "fijo").foregroundStyle(controller.isAdjusting ? .orange : .green)
            }
            .monospacedDigit()
            HStack(spacing: 8) {
                Text("Motor: \(controller.syncEngine.mode.rawValue)")
                if let summary = controller.syncEngine.lastSummary {
                    Text("Última ventana: \(summary.text)").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11))
            HStack {
                Button("Mostrar registro en Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([JamSyncLog.shared.url])
                }
                Button("Copiar últimas 200 líneas") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(JamSyncLog.shared.tail(200), forType: .string)
                }
            }
            HStack {
                Text("Ajuste de esta versión: \(controller.nudgeMs, specifier: "%+.0f") ms")
                Button("−50") { controller.nudgeMs -= 50 }
                Button("−10") { controller.nudgeMs -= 10 }
                Button("+10") { controller.nudgeMs += 10 }
                Button("+50") { controller.nudgeMs += 50 }
                Button("0") { controller.nudgeMs = 0 }
            }
            HStack {
                Text("Ajuste global (salida): \(offset.wrappedValue, specifier: "%+.0f") ms")
                Button("−50") { offset.wrappedValue -= 50 }
                Button("−10") { offset.wrappedValue -= 10 }
                Button("+10") { offset.wrappedValue += 10 }
                Button("+50") { offset.wrappedValue += 50 }
                Button("0") { offset.wrappedValue = 0 }
            }
        }
    }

    private var versions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Versiones en YT Music (clic para corregir)").font(.system(size: 12, weight: .semibold))
            ForEach(controller.candidates.prefix(8)) { candidate in
                Button {
                    controller.choose(candidate)
                } label: {
                    HStack {
                        Text(candidate.id == controller.matched?.id ? "●" : "○")
                        Text("\(candidate.song.title) — \(candidate.song.artists)").lineLimit(1)
                        Spacer()
                        Text("\(candidate.song.duration ?? "?") · \(candidate.score, specifier: "%.1f")\(candidate.song.isVideo ? " · video" : "")")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Cola del Jam (\(controller.queue.count))").font(.system(size: 12, weight: .semibold))
            ForEach(Array(controller.queue.prefix(12).enumerated()), id: \.offset) { _, track in
                Text("\(track.displayTitle) — \(track.displayArtists)\(track.provider == "queue" ? "  · agregada" : track.provider == "enhanced_recommendation" ? "  · recomendada por Spotify" : "")")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Registro").font(.system(size: 12, weight: .semibold))
            ForEach(Array(controller.log.suffix(40).enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        return String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
}
