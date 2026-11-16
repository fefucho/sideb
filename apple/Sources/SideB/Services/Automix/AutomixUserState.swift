import Foundation

// Estado del Automix «para personas»: qué versión de la transición hay lista (rápida o buena, con stems), si la buena
// se está preparando, si ya llegó o por qué no se va a usar. Todo puro y sin vistas: se prueba aparte.

/// Por qué no se va a usar (o no se pidió) la versión buena.
enum AutomixUpgradeSkip: Equatable, Sendable {
    /// Calidad del ajuste en «siempre rápida».
    case alwaysFast
    /// Con batería o ahorro de energía sólo se usa la rápida.
    case battery(lowPower: Bool)
    /// En automático, esta Mac aún no recomienda stems y la pareja no está en la caché.
    case notRecommended
    /// La petición directa de stems ya falló para esta pareja.
    case pairFailed
    /// El corte está demasiado cerca para cambiar de versión.
    case tooClose
    /// El corte de la versión buena ya quedó atrás.
    case cutPassed
    /// Llegó cuando el empalme ya estaba comprometido o sonando.
    case afterSplice
    /// La respuesta de la versión buena no era válida.
    case invalid
    case cancelled

    /// Traduce el motivo de `AutomixUpgradePlanner.decide` (texto de depuración) a un motivo estructurado.
    static func fromPlanner(_ reason: String) -> AutomixUpgradeSkip {
        if reason.hasPrefix("llegó tras") { return .afterSplice }
        if reason.contains("ya quedó atrás") { return .cutPassed }
        return .tooClose
    }

    var key: String {
        switch self {
        case .alwaysFast: "automix.skip.alwaysFast"
        case .battery(let lowPower): lowPower ? "automix.skip.lowPower" : "automix.skip.battery"
        case .notRecommended: "automix.skip.notRecommended"
        case .pairFailed: "automix.skip.pairFailed"
        case .tooClose: "automix.skip.tooClose"
        case .cutPassed: "automix.skip.cutPassed"
        case .afterSplice: "automix.skip.afterSplice"
        case .invalid: "automix.skip.invalid"
        case .cancelled: "automix.skip.cancelled"
        }
    }
}

/// Qué pasa con la versión buena (stems) mientras la rápida ya está lista.
enum AutomixUpgradeState: Equatable, Sendable {
    /// Nada que decir (no hay transición, o ya se pidió la buena directamente).
    case none
    /// La rápida está lista y la buena no se ha pedido aún: se vigila la pareja por si queda lista en la caché.
    case watching
    /// Se está preparando la buena desde `since`.
    case working(since: Date)
    /// La buena ya sustituyó a la rápida.
    case applied
    /// No se va a usar (o no se pidió) por este motivo.
    case notUsed(AutomixUpgradeSkip)
    /// La petición de la buena falló: suena la rápida.
    case failed
}

/// Calidad de la transición en curso. Lo publica el coordinador; la píldora, la marca y el aviso lo leen.
struct AutomixQualityState: Equatable, Sendable {
    /// Calidad de la primera petición mientras se prepara ("fast" o "stems").
    var preparing: String?
    /// Calidad de la transición vigente cuando ya está lista ("fast" o "stems").
    var ready: String?
    var upgrade: AutomixUpgradeState = .none

    var isGood: Bool { ready == "stems" }
    /// Se está mejorando: la rápida lista y la buena en marcha.
    var isImproving: Bool { if case .working = upgrade { true } else { false } }
}

/// Textos del estado del Automix para la gente (píldora, ayuda de la marca, resumen del diagnóstico).
enum AutomixUserText {
    /// Etiqueta de calidad de una transición: «buena» (stems) o «rápida».
    static func qualityWord(good: Bool, language: AppLanguage? = nil) -> String {
        L10n.text(good ? "automix.quality.good" : "automix.quality.fast", language: language)
    }

    static func seconds(_ value: TimeInterval) -> String { String(Int(max(0, value).rounded(.down))) }

    // MARK: Píldora

    /// Texto de la píldora de pantalla completa. `now` sólo importa mientras se prepara la versión buena (segundos).
    static func pillText(status: AutomixCoordinator.Status, quality: AutomixQualityState, now: Date, language: AppLanguage? = nil) -> String {
        switch status {
        case .off: return L10n.text("automix.pill.title", language: language)
        case .idle: return L10n.text("automix.pill.state.idle", language: language)
        case .preparing:
            return L10n.text(quality.preparing == "stems" ? "automix.pill.state.preparingGood" : "automix.pill.state.preparing", language: language)
        case .ready:
            if quality.isGood { return L10n.text("automix.pill.state.goodReady", language: language) }
            if case .working(let since) = quality.upgrade {
                return L10n.text("automix.pill.state.fastImproving", args: [seconds(now.timeIntervalSince(since))], language: language)
            }
            return L10n.text("automix.pill.state.fastReady", language: language)
        case .mixing:
            return L10n.text("automix.pill.state.mixing", args: [qualityWord(good: quality.isGood, language: language)], language: language)
        case .unavailable(let reason):
            return L10n.text("automix.pill.state.unavailable", args: [shortReason(reason, language: language)], language: language)
        }
    }

    /// Motivo corto para la píldora («Automix · no disponible: <motivo>»).
    static func shortReason(_ reason: AutomixUnavailableReason, language: AppLanguage? = nil) -> String {
        let key: String = switch reason {
        case .jam: "automix.pill.reason.jam"
        case .repeatOne: "automix.pill.reason.repeatOne"
        case .noNextTrack: "automix.pill.reason.noNextTrack"
        case .sameTrack: "automix.pill.reason.sameTrack"
        case .sameAlbum: "automix.pill.reason.sameAlbum"
        case .unsupportedFormat: "automix.pill.reason.unsupportedFormat"
        case .tooLong: "automix.pill.reason.tooLong"
        case .tooLate: "automix.pill.reason.tooLate"
        case .failed: "automix.pill.reason.failed"
        }
        return L10n.text(key, language: language)
    }

    /// Una frase que explica el estado y, si se conoce, cuándo empieza la mezcla (`mixStart` = «m:ss»).
    static func pillTooltip(status: AutomixCoordinator.Status, quality: AutomixQualityState, mixStart: String?, language: AppLanguage? = nil) -> String {
        let base: String
        var withStart = true
        switch status {
        case .off: base = L10n.text("automix.tip.off", language: language); withStart = false
        case .idle: base = L10n.text("automix.tip.idle", language: language); withStart = false
        case .preparing:
            base = L10n.text(quality.preparing == "stems" ? "automix.tip.preparingGood" : "automix.tip.preparing", language: language)
            withStart = false
        case .ready:
            if quality.isGood { base = L10n.text("automix.tip.goodReady", language: language) }
            else if quality.isImproving { base = L10n.text("automix.tip.fastImproving", language: language) }
            else { base = L10n.text("automix.tip.fastReady", language: language) }
        case .mixing:
            base = L10n.text("automix.tip.mixing", args: [qualityWord(good: quality.isGood, language: language)], language: language)
            withStart = false
        case .unavailable(let reason):
            base = L10n.text(AutomixStatusPresentation.reasonKey(reason), language: language); withStart = false
        }
        guard withStart, let mixStart else { return base }
        return base + " " + L10n.text("automix.tip.mixStart", args: [mixStart], language: language)
    }

    // MARK: Marca de la barra

    /// Ayuda de la marca: dónde empieza la mezcla y qué versión sonará.
    static func markerHelp(time: String, quality: AutomixQualityState, language: AppLanguage? = nil) -> String {
        let key = quality.isGood ? "automix.marker.good" : (quality.isImproving ? "automix.marker.fastImproving" : "automix.marker.fast")
        return L10n.text(key, args: [time], language: language)
    }

    // MARK: Resumen del diagnóstico

    struct SummaryInput: Equatable {
        var status: AutomixCoordinator.Status = .off
        var quality = AutomixQualityState()
        /// Título del tema que suena y del siguiente (nil si no hay).
        var current: String?
        var next: String?
        /// Cuándo quedó lista la versión vigente (la rápida, o la buena si se pidió directamente).
        var readyAt: Date?
        /// Cuándo se pidió la buena (mejora) y cuándo llegó.
        var upgradeRequestedAt: Date?
        var upgradeFinishedAt: Date?
        /// Lo que tardó la última versión buena preparada de verdad (estimación para la siguiente), si se conoce.
        var typicalUpgradeSeconds: Double?
        /// Empieza la mezcla en «m:ss», si se conoce.
        var mixStart: String?
        var preparingSince: Date?
    }

    /// Párrafo en lenguaje llano: «Ahora: … Siguiente: … Transición: … La mezcla empieza en m:ss.»
    static func summary(_ input: SummaryInput, now: Date, clock: (Date) -> String, language: AppLanguage? = nil) -> [String] {
        var lines: [String] = []
        lines.append(input.current.map { L10n.text("automix.summary.now", args: [$0], language: language) }
            ?? L10n.text("automix.summary.nowNone", language: language))
        lines.append(input.next.map { L10n.text("automix.summary.next", args: [$0], language: language) }
            ?? L10n.text("automix.summary.nextNone", language: language))
        lines.append(transitionSentence(input, now: now, clock: clock, language: language))
        if let start = input.mixStart, input.status.hasTransition {
            lines.append(L10n.text("automix.summary.mixStart", args: [start], language: language))
        }
        return lines
    }

    private static func transitionSentence(_ input: SummaryInput, now: Date, clock: (Date) -> String, language: AppLanguage?) -> String {
        switch input.status {
        case .off: return L10n.text("automix.summary.transition.off", language: language)
        case .idle: return L10n.text("automix.summary.transition.idle", language: language)
        case .unavailable(let reason):
            return L10n.text("automix.summary.transition.unavailable", args: [L10n.text(AutomixStatusPresentation.reasonKey(reason), language: language)], language: language)
        case .preparing:
            let good = input.quality.preparing == "stems"
            let key = good ? "automix.summary.transition.preparingGood" : "automix.summary.transition.preparing"
            let elapsed = input.preparingSince.map { seconds(now.timeIntervalSince($0)) } ?? "0"
            return L10n.text(key, args: [elapsed], language: language)
        case .ready, .mixing:
            let at = input.readyAt.map(clock) ?? "—"
            let mixing = input.status.isMixing
            // La buena pedida directamente no tuvo «rápida»; si sustituyó a la rápida, se cuentan las dos.
            let directGood = input.quality.isGood && input.quality.upgrade != .applied
            var text = L10n.text(directGood ? "automix.summary.transition.goodReady" : "automix.summary.transition.fastReady", args: [at], language: language)
            if !directGood { text += " " + upgradeSentence(input, now: now, clock: clock, language: language) }
            if mixing { text += " " + L10n.text("automix.summary.transition.mixingNow", args: [qualityWord(good: input.quality.isGood, language: language)], language: language) }
            return text
        }
    }

    private static func upgradeSentence(_ input: SummaryInput, now: Date, clock: (Date) -> String, language: AppLanguage?) -> String {
        switch input.quality.upgrade {
        case .none:
            return L10n.text("automix.summary.good.none", language: language)
        case .watching:
            return L10n.text("automix.summary.good.watching", language: language)
        case .working(let since):
            let elapsed = seconds(now.timeIntervalSince(since))
            if let typical = input.typicalUpgradeSeconds, typical.isFinite, typical > 0 {
                return L10n.text("automix.summary.good.workingEstimate", args: [elapsed, String(Int(typical.rounded()))], language: language)
            }
            return L10n.text("automix.summary.good.working", args: [elapsed], language: language)
        case .applied:
            let at = input.upgradeFinishedAt.map(clock) ?? "—"
            return L10n.text("automix.summary.good.applied", args: [at], language: language)
        case .notUsed(let reason):
            return L10n.text("automix.summary.good.notUsed", args: [L10n.text(reason.key, language: language)], language: language)
        case .failed:
            return L10n.text("automix.summary.good.failed", language: language)
        }
    }
}

extension AutomixCoordinator.Status {
    /// Hay una transición lista o sonando.
    var hasTransition: Bool {
        switch self {
        case .ready, .mixing: true
        default: false
        }
    }
    var isMixing: Bool { if case .mixing = self { true } else { false } }
}
