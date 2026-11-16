import Foundation

/// Texto y símbolo del estado del Automix para la píldora de pantalla completa. Puro: se prueba sin vistas.
enum AutomixStatusPresentation {
    static func kindName(_ kind: String, language: AppLanguage? = nil) -> String {
        switch kind {
        case "mix": L10n.text("automix.kind.mix", language: language)
        case "cut": L10n.text("automix.kind.cut", language: language)
        default: L10n.text("automix.kind.fade", language: language)
        }
    }

    static func text(for status: AutomixCoordinator.Status, language: AppLanguage? = nil) -> String {
        switch status {
        case .off: L10n.text("automix.status.off", language: language)
        case .idle: L10n.text("automix.status.idle", language: language)
        case .preparing: L10n.text("automix.status.preparing", language: language)
        case .ready(let kind, let bpm):
            bpm > 0
                ? L10n.text("automix.status.ready", args: [kindName(kind, language: language), String(format: "%.0f", bpm)], language: language)
                : L10n.text("automix.status.readyNoBpm", args: [kindName(kind, language: language)], language: language)
        case .mixing(let kind): L10n.text("automix.status.mixing", args: [kindName(kind, language: language)], language: language)
        case .unavailable(let reason): L10n.text(reasonKey(reason), language: language)
        }
    }

    static func reasonKey(_ reason: AutomixUnavailableReason) -> String {
        switch reason {
        case .jam: "automix.unavailable.jam"
        case .repeatOne: "automix.unavailable.repeatOne"
        case .noNextTrack: "automix.unavailable.noNextTrack"
        case .sameTrack: "automix.unavailable.sameTrack"
        case .sameAlbum: "automix.unavailable.sameAlbum"
        case .unsupportedFormat: "automix.unavailable.unsupportedFormat"
        case .tooLong: "automix.unavailable.tooLong"
        case .tooLate: "automix.unavailable.tooLate"
        case .failed: "automix.unavailable.failed"
        }
    }

    static func symbol(for status: AutomixCoordinator.Status) -> String {
        switch status {
        case .off: "waveform.slash"
        case .idle, .preparing: "waveform"
        case .ready: "checkmark.circle"
        case .mixing: "waveform.path"
        case .unavailable: "minus.circle"
        }
    }

    /// Símbolo según la versión: la buena lista con el check lleno, la rápida con un rayo.
    static func symbol(for status: AutomixCoordinator.Status, quality: AutomixQualityState) -> String {
        if case .ready = status { return quality.isGood ? "checkmark.circle.fill" : "bolt.circle" }
        return symbol(for: status)
    }

    static func isOn(_ status: AutomixCoordinator.Status) -> Bool { status != .off }
}
