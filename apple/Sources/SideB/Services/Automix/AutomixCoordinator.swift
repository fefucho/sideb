import Foundation
import Observation

/// Resultado de entregar la transición al reproductor.
enum AutomixArmOutcome: Equatable, Sendable {
    /// El archivo quedó cargado en un segundo reproductor, listo para empalmar en el corte.
    case armed
    /// Sin uso en el empalme de dos reproductores (se conserva por compatibilidad con las pruebas).
    case enteredLate
    case tooLate
    case failed
}

/// Lo que el coordinador pide al reproductor. Lo implementa `PlayerViewModel`; las pruebas usan uno falso.
@MainActor
protocol AutomixHost: AnyObject {
    func automixContext() -> AutomixContext?
    func automixPrepare(_ request: AutomixRequest) async throws -> AutomixTransition
    func automixCancel(requestID: String)
    func automixArm(_ transition: AutomixTransition) async -> AutomixArmOutcome
    /// Cambia el archivo armado por otro de la misma pareja (la versión de stems, cuyo corte y solape pueden ser
    /// otros) si el empalme aún no se comprometió y el corte nuevo todavía cabe.
    func automixReplace(_ transition: AutomixTransition) async -> AutomixArmOutcome
    func automixDisarm()
    /// La cola cambió su siguiente tema mientras el archivo ya sonaba: se abandona la mezcla.
    func automixAbortMixing()
    func automixCacheDirectory() -> URL
    /// `SideBCore.automixModelReady()`, o nil sin core (sólo diagnóstico).
    func automixModelReady() -> Bool?
    func automixSettings() -> AutomixSettingsValue
    func automixCapability() -> AutomixCapabilityValue?
    func automixPower() -> AutomixPowerState
    /// `SideBCore.automixPairReady(from:to:)`: los stems de la pareja están en la caché y el modelo en disco.
    func automixPairReady(from: String, to: String) -> Bool
    /// Segundos de la canción que suena (los que muestra la barra), o nil si no hay.
    func automixPosition() -> Double?
    /// El empalme armado aún admite cambiar de archivo (no se programó el arranque). Verdadero si nada está armado.
    func automixCanReplaceSplice() -> Bool
    /// Precarga del core: `items[0]` es el tema que suena, el resto los siguientes. Vuelve enseguida.
    func automixPrefetch(_ items: [AutomixSong], allowStems: Bool)
    func automixCancelPrefetch()
}

/// Decide cuándo pedir la transición, la descarta cuando deja de valer y refleja su estado para la UI.
/// No conoce AVFoundation ni el core: todo pasa por `AutomixHost`.
///
/// Estrategia (PLAN-024, ronda 4):
/// - Con el siguiente tema conocido: si los stems están permitidos y la pareja está lista (`automixPairReady`) se pide
///   `"stems"` directamente (≈3–4 s); si no, `"fast"` enseguida.
/// - Con la rápida ya lista se pide `"stems"` si el ajuste/capacidad lo recomiendan o cuando la precarga deja la pareja
///   lista (se vigila cada pocos segundos mientras no se haya empalmado) y se cambia sólo si llega antes de comprometer
///   el empalme y su corte aún queda a ≥ 8 s. El corte y el solape de stems pueden diferir de los de la rápida.
/// - **Sin vaivén**: el plan se identifica por la pareja (no por la ocurrencia de reproducción) y una cancelación del
///   core o un contexto transitorio no borran la petición; el core une las peticiones idénticas.
@MainActor
@Observable
final class AutomixCoordinator {
    enum Status: Equatable {
        case off
        /// Activado, sin nada que preparar todavía (sin tema sonando).
        case idle
        case preparing
        case ready(kind: String, bpm: Double)
        case unavailable(AutomixUnavailableReason)
        case mixing(kind: String)
    }

    private(set) var status: Status = .off {
        didSet { if status != oldValue { log("estado: \(Self.describe(oldValue)) → \(Self.describe(status))") } }
    }
    /// Dónde empieza la mezcla sobre la barra de progreso mientras haya una transición lista o sonando para la
    /// canción actual; nil si se cancela, se abandona o ya hubo traspaso.
    private(set) var marker: AutomixProgressMarker? {
        didSet {
            if marker != oldValue {
                log(marker.map { "marcador de la barra: segundo \(String(format: "%.2f", $0.songSeconds))" } ?? "marcador de la barra: quitado")
            }
        }
    }
    /// Calidad de la transición en curso (rápida o buena) y estado de la mejora a stems, para la interfaz.
    private(set) var qualityState = AutomixQualityState()
    /// Cuántas veces la versión buena sustituyó a la rápida (la interfaz muestra un aviso breve por cada una).
    private(set) var goodVersionLandedCount = 0
    /// Lo que tardó la última versión buena preparada de verdad (no reutilizada), para estimar la siguiente.
    @ObservationIgnored private(set) var typicalUpgradeSeconds: Double?
    /// Segundo de la canción actual en que empieza la mezcla, aunque la barra aún no tenga la marca (el archivo se
    /// entrega al reproductor cuando el tema suena).
    var mixStartSeconds: Double? {
        marker?.songSeconds ?? request?.transition.flatMap(AutomixProgressMarker.init(transition:))?.songSeconds
    }
    /// Última petición (también tras terminar), para el diagnóstico.
    @ObservationIgnored private(set) var request: AutomixRequestInfo?
    /// El plan en curso existe y está preparándose.
    var isPreparing: Bool { plan?.stage == .preparing }
    /// Lista de precarga vigente y su estado, para el diagnóstico.
    @ObservationIgnored private(set) var prefetchItems: [AutomixSong]?
    @ObservationIgnored private(set) var prefetchAllowStems: Bool?
    @ObservationIgnored private(set) var prefetchRequestedAt: Date?
    @ObservationIgnored private(set) var prefetchStatus = "sin precarga"
    /// Última decisión de estrategia y lectura de «pareja lista», para el diagnóstico.
    @ObservationIgnored private(set) var strategy = AutomixStrategyInfo()

    @ObservationIgnored weak var host: (any AutomixHost)?
    @ObservationIgnored private(set) var isEnabled: Bool

    private enum Stage { case preparing, ready, mixing, failed }
    private struct Plan {
        var key: AutomixPlanKey
        var requestID: String
        var stage: Stage
        var task: Task<Void, Never>?
        /// Calidad de la petición principal.
        var quality = "fast"
        /// Transición vigente (la rápida, o la de stems cuando la sustituye).
        var transition: AutomixTransition?
        /// El reproductor aceptó el archivo.
        var armed = false
        var arming = false
        var upgradeRequestID: String?
        var upgradeTask: Task<Void, Never>?
        /// Ya se pidió o se descartó la mejora: no se vuelve a decidir.
        var upgradeSettled = false
        /// Stems llegó mientras el reproductor aún cargaba la rápida: se cambia al terminar de armarla.
        var pendingUpgrade: AutomixTransition?
        /// Tras una cancelación del core (no pedida por nosotros): cuándo se puede volver a intentar, y cuántas veces.
        var retryAt: Date?
        var retries = 0
    }
    @ObservationIgnored private var plan: Plan?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let log: @MainActor (String) -> Void
    @ObservationIgnored private let dropGrace: Duration
    @ObservationIgnored private let pollInterval: Duration?
    @ObservationIgnored private let retryDelay: TimeInterval
    @ObservationIgnored private var dropTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Parejas cuya petición directa de stems falló: se vuelve a la rápida sin repetir el intento.
    @ObservationIgnored private var directStemsFailed: Set<AutomixPlanKey> = []

    init(enabled: Bool = false, now: @escaping () -> Date = Date.init,
         dropGrace: Duration = .seconds(2), pollInterval: Duration? = nil, retryDelay: TimeInterval = 10,
         log: @escaping @MainActor (String) -> Void = { AutomixDiagnostics.shared.record("coord", $0) }) {
        self.isEnabled = enabled
        self.now = now
        self.log = log
        self.dropGrace = dropGrace
        self.pollInterval = pollInterval
        self.retryDelay = retryDelay
        self.status = enabled ? .idle : .off
        if enabled { startPolling() }
    }

    /// Clave del plan vigente (para pruebas).
    var currentKey: AutomixPlanKey? { plan?.key }
    /// Hay una caída diferida pendiente (para pruebas).
    var hasPendingDrop: Bool { dropTask != nil }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        marker = nil
        log("ajuste Automix: \(enabled ? "encendido" : "apagado")")
        // Apagar descarta todo; encender vuelve a evaluar desde cero (también reintenta un fallo anterior).
        teardown(reason: "cambió el ajuste")
        directStemsFailed.removeAll()
        status = enabled ? .idle : .off
        if enabled { startPolling() } else { pollTask?.cancel(); pollTask = nil }
        reconcile()
    }

    // MARK: - Evaluación

    /// Idempotente y barato: se llama en cada cambio de cola, de tema o de modo.
    func reconcile() {
        guard isEnabled else {
            teardown(reason: "Automix apagado"); cancelPrefetch(reason: "Automix apagado"); status = .off; return
        }
        guard let host, let context = host.automixContext() else {
            // Sin tema (o la cola a medio cambiar): no se cancela nada de inmediato, sólo si dura.
            if plan != nil { scheduleDrop(reason: "sin tema o contexto") } else { status = .idle }
            return
        }
        cancelDrop()
        reconcilePrefetch(context)

        let key = context.next.map { AutomixPlanKey(token: context.token, from: context.current.videoID, to: $0.videoID) }
        let reason = AutomixEligibility.reason(context)

        if let current = plan {
            if current.stage == .mixing {
                // El archivo ya suena: no hay forma de «des-oír» la mezcla.
                if let key, current.key == key, current.key.token == context.token { armIfNeeded(context: context); return }
                guard let key else { return } // siguiente transitoriamente desconocido: se deja seguir; el traspaso lo comprueba
                _ = key
                if current.key.token == context.token, context.hasStarted {
                    teardown(reason: "el siguiente tema cambió con la mezcla sonando")
                    host.automixAbortMixing()
                    status = .idle
                    return
                }
                teardown(reason: "cambió el tema que suena con la mezcla sonando")
            } else if let key, current.key == key {
                // Misma pareja: se conserva la petición aunque cambie la ocurrencia de reproducción (reinicio, salto).
                if let reason {
                    teardown(reason: "ya no es elegible (\(Self.describe(reason)))")
                    status = .unavailable(reason)
                    return
                }
                if current.key.token != context.token { adoptToken(context) }
                armIfNeeded(context: context)
                return
            } else if key == nil, reason == .noNextTrack {
                // La cola puede estar cambiando: se espera un poco antes de cancelar una petición en vuelo.
                scheduleDrop(reason: "sin siguiente conocido")
                return
            } else {
                let why: String
                if let key, current.key.to != key.to || current.key.from != key.from { why = "cambió la pareja (\(current.key.from) → \(current.key.to) ⇒ \(key.from) → \(key.to))" }
                else if let reason { why = "ya no es elegible (\(Self.describe(reason)))" }
                else { why = "contexto distinto" }
                teardown(reason: why)
            }
        }
        if let reason { status = .unavailable(reason); return }
        // La versión rápida no necesita que el tema actual haya sonado: sólo conocer el siguiente.
        guard let next = context.next, let key else { status = .idle; return }
        start(key: key, from: context.current, to: next, host: host, forced: false)
    }

    /// Misma pareja con otra ocurrencia de reproducción: el archivo del empalme anterior se perdió con la reproducción
    /// vieja, la petición (y su resultado) no.
    private func adoptToken(_ context: AutomixContext) {
        log("misma pareja con otra ocurrencia de reproducción: se conserva la petición, se vuelve a entregar el archivo")
        plan?.key.token = context.token
        if plan?.stage == .ready {
            if plan?.armed == true || plan?.arming == true { host?.automixDisarm() }
            plan?.armed = false
            plan?.arming = false
            marker = nil
        }
    }

    private func scheduleDrop(reason: String) {
        guard dropTask == nil else { return }
        log("contexto transitorio (\(reason)): se espera \(dropGrace) antes de cancelar la petición")
        dropTask = Task { [weak self, dropGrace] in
            try? await Task.sleep(for: dropGrace)
            guard !Task.isCancelled, let self else { return }
            self.dropTask = nil
            // Si el contexto sigue sin servir, ahora sí.
            let stillGone = self.host?.automixContext().map { $0.next == nil } ?? true
            if stillGone, self.plan?.stage != .mixing {
                self.teardown(reason: "\(reason) durante más de \(dropGrace)")
                self.status = .idle
            } else {
                self.reconcile()
            }
        }
    }

    private func cancelDrop() { dropTask?.cancel(); dropTask = nil }

    /// Depuración: pide una transición ya. Respeta el ajuste, el Jam y la elegibilidad; descarta cualquier plan anterior.
    @discardableResult
    func prepareNow() -> Bool {
        guard isEnabled else { log("«Preparar ahora» ignorado: Automix está apagado"); return false }
        guard let host, let context = host.automixContext() else { log("«Preparar ahora» ignorado: no hay tema"); return false }
        if let reason = AutomixEligibility.reason(context) {
            log("«Preparar ahora» ignorado: \(Self.describe(reason))")
            status = .unavailable(reason)
            return false
        }
        guard let next = context.next else { return false }
        teardown(reason: "«Preparar ahora»")
        let key = AutomixPlanKey(token: context.token, from: context.current.videoID, to: next.videoID)
        start(key: key, from: context.current, to: next, host: host, forced: true)
        return true
    }

    /// Depuración: cancela la preparación en curso y no la reintenta sola para este par (volver a pedirla: «Preparar ahora»).
    func cancelPreparation() {
        guard var current = plan, current.stage == .preparing else { log("«Cancelar» ignorado: no hay preparación en curso"); return }
        current.task?.cancel()
        host?.automixCancel(requestID: current.requestID)
        current.stage = .failed
        current.task = nil
        current.retryAt = nil
        current.retries = 99
        plan = current
        request?.phase = .cancelled
        request?.finishedAt = now()
        request?.note = "cancelada a mano"
        log("preparación \(Self.short(current.requestID)) cancelada a mano")
        status = .idle
    }

    /// El archivo entró en reproducción: hasta el traspaso la UI sigue en la canción anterior.
    func spliceEntered() {
        guard var plan, plan.stage == .ready || plan.stage == .preparing else { return }
        guard case .ready(let kind, _) = status else { return }
        plan.stage = .mixing
        self.plan = plan
        log("el archivo ya suena (\(kind)); la interfaz sigue en la canción anterior")
        status = .mixing(kind: kind)
    }

    /// La UI ya muestra la siguiente canción; esta transición terminó su trabajo.
    func didHandover() {
        log("traspaso: la interfaz pasa a la siguiente canción")
        request?.note = "traspaso hecho"
        if request?.upgrade.hasPrefix("pedida") == true { request?.upgrade = "omitida: el traspaso ocurrió antes" }
        plan?.task?.cancel()
        if let upgrade = plan?.upgradeRequestID, plan?.stage != .failed { host?.automixCancel(requestID: upgrade) }
        plan?.upgradeTask?.cancel()
        plan = nil
        cancelDrop()
        marker = nil
        qualityState = AutomixQualityState()
        status = isEnabled ? .idle : .off
    }

    /// El reproductor soltó el empalme porque el usuario saltó más allá de lo que el archivo cubre.
    func gaveUp() {
        guard let current = plan, current.stage == .ready else { return }
        log("empalme abandonado: el salto del usuario supera lo que el archivo reproduce igual que la canción")
        request?.note = "abandonado por un salto"
        markFailed(.tooLate)
    }

    /// El reproductor no pudo reproducir el archivo (formato, fichero borrado).
    func spliceFailed() {
        guard let current = plan else { return }
        marker = nil
        qualityState = AutomixQualityState()
        log("el reproductor soltó el archivo (falló al cargar o al empalmar)")
        request?.note = "el archivo falló al cargar o al empalmar"
        var failed = current
        failed.stage = .failed
        failed.armed = false
        failed.retries = 99
        plan = failed
        status = .unavailable(.failed)
    }

    /// Descarta preparación y empalme en curso (salto, cambio de cola, cuenta, Jam, apagado).
    func teardown(reason: String = "descartada") {
        marker = nil
        qualityState = AutomixQualityState()
        cancelDrop()
        guard let plan else { return }
        plan.task?.cancel()
        plan.upgradeTask?.cancel()
        if let upgrade = plan.upgradeRequestID {
            host?.automixCancel(requestID: upgrade)
            request?.upgrade = "cancelada: \(reason)"
        }
        switch plan.stage {
        case .preparing:
            host?.automixCancel(requestID: plan.requestID)
            request?.phase = .cancelled
            request?.finishedAt = now()
            request?.note = reason
            log("preparación \(Self.short(plan.requestID)) cancelada: \(reason)")
        case .ready, .mixing:
            host?.automixDisarm()
            request?.note = "descartada: \(reason)"
            log("transición \(Self.short(plan.requestID)) descartada (\(plan.stage == .mixing ? "sonando" : "lista")): \(reason)")
        case .failed: break
        }
        self.plan = nil
    }

    // MARK: - Vigilancia periódica

    private func startPolling() {
        pollTask?.cancel()
        guard let pollInterval else { pollTask = nil; return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled else { return }
                self?.pollOnce()
            }
        }
    }

    /// Cada pocos segundos: refresca la precarga (por si cambió la batería), reintenta tras una cancelación del core y,
    /// mientras la rápida espera sin empalmarse, mira si la precarga dejó la pareja lista para pedir stems.
    func pollOnce() {
        guard isEnabled, let host, let context = host.automixContext() else { return }
        reconcilePrefetch(context)

        guard var current = plan else { return }
        if current.stage == .failed, let retryAt = current.retryAt, now() >= retryAt, current.retries < 2,
           context.next.map({ AutomixPlanKey(token: context.token, from: context.current.videoID, to: $0.videoID) == current.key }) == true,
           AutomixEligibility.reason(context) == nil, let next = context.next {
            log("reintento tras la cancelación del core (\(current.retries + 1)/2)")
            current.retries += 1
            let retries = current.retries
            plan = nil
            start(key: current.key, from: context.current, to: next, host: host, forced: false)
            plan?.retries = retries
            return
        }
        guard current.stage == .ready, !current.upgradeSettled, current.upgradeRequestID == nil,
              let fast = current.transition, fast.quality == "fast" else { return }
        let settings = host.automixSettings()
        let power = host.automixPower()
        let allow = AutomixStrategy.allowStems(settings: settings, power: power)
        guard allow.allowed else { return }
        let ready = host.automixPairReady(from: current.key.from, to: current.key.to)
        noteStrategy(pairReady: ready, allow: allow)
        let decision = AutomixStrategy.wantsStems(settings: settings, capability: host.automixCapability(), power: power, pairReady: ready)
        if decision.wants, !directStemsFailed.contains(current.key) {
            log("mejora a stems: sí — \(decision.reason) (vigilancia periódica)")
            startUpgrade(key: current.key, from: fast, host: host)
        }
    }

    // MARK: - Precarga

    private func reconcilePrefetch(_ context: AutomixContext) {
        guard !context.jamActive else { cancelPrefetch(reason: "Jam activo"); return }
        guard !context.repeatOne else { cancelPrefetch(reason: "repetición de un tema"); return }
        guard !context.upcoming.isEmpty else { cancelPrefetch(reason: "sin temas siguientes"); return }
        let items = AutomixPrefetchPlan.items(current: context.current, upcoming: context.upcoming, lookahead: context.lookahead)
        let allow = host.map { AutomixStrategy.allowStems(settings: $0.automixSettings(), power: $0.automixPower()) } ?? (allowed: true, reason: "sin anfitrión")
        guard items != prefetchItems || allow.allowed != prefetchAllowStems else { return }
        prefetchItems = items
        prefetchAllowStems = allow.allowed
        prefetchRequestedAt = now()
        prefetchStatus = "en curso"
        log("precarga: \(items.map(\.videoID).joined(separator: " → ")) (adelanto \(context.lookahead)), stems \(allow.allowed ? "permitidos" : "no permitidos") — \(allow.reason)")
        host?.automixPrefetch(items, allowStems: allow.allowed)
    }

    /// Cancela la precarga del core (apagado, Jam, cambio de cuenta).
    func cancelPrefetch(reason: String) {
        guard prefetchItems != nil else { return }
        prefetchItems = nil
        prefetchAllowStems = nil
        prefetchStatus = "cancelada: \(reason)"
        log("precarga cancelada: \(reason)")
        host?.automixCancelPrefetch()
    }

    /// La llamada `prefetchAutomix` volvió (o falló): sólo para el diagnóstico.
    func prefetchScheduled(error: String?) {
        prefetchStatus = error.map { "falló: \($0)" } ?? "programada en el core (corre en segundo plano)"
        if let error { log("precarga falló: \(error)") }
    }

    // MARK: - Preparación

    private func noteStrategy(pairReady: Bool, allow: (allowed: Bool, reason: String)) {
        if strategy.pairReady != pairReady { log("pareja \(pairReady ? "lista" : "no lista") en la caché de stems") }
        strategy.pairReady = pairReady
        strategy.pairReadyAt = now()
        strategy.allowStems = allow.allowed
        strategy.allowReason = allow.reason
    }

    private func start(key: AutomixPlanKey, from: AutomixSong, to: AutomixSong, host: any AutomixHost, forced: Bool) {
        let settings = host.automixSettings()
        let allow = AutomixStrategy.allowStems(settings: settings, power: host.automixPower())
        let ready = allow.allowed && host.automixPairReady(from: from.videoID, to: to.videoID)
        noteStrategy(pairReady: ready, allow: allow)
        var quality = AutomixStrategy.initialQuality(allowStems: allow.allowed, pairReady: ready)
        if quality == "stems", directStemsFailed.contains(key) { quality = "fast" }
        log("estrategia: stems \(allow.allowed ? "permitidos" : "no permitidos") (\(allow.reason)); pareja \(ready ? "lista" : "no lista") ⇒ primera petición \(quality)")
        let requestID = UUID().uuidString
        let request = AutomixRequest(requestID: requestID, from: from, to: to, cacheDirectory: host.automixCacheDirectory(), quality: quality)
        let started = now()
        let model = host.automixModelReady().map { $0 ? "listo" : "no descargado" } ?? "desconocido"
        log("petición \(Self.short(requestID)) [\(quality)]: \(from.videoID) → \(to.videoID)\(forced ? " (forzada)" : ""); modelo \(model)")
        var info = AutomixRequestInfo(requestID: requestID, from: from, to: to, requestedAt: started, finishedAt: nil,
                                      phase: .preparing, forced: forced, rawError: nil, failureLabel: nil,
                                      transition: nil, note: nil, requestedQuality: quality, upgrade: "sin decidir")
        info.allowStems = allow.allowed
        info.allowReason = allow.reason
        info.pairReadyAtRequest = ready
        self.request = info
        qualityState = AutomixQualityState(preparing: quality)
        status = .preparing
        let task = Task { [weak self, weak host] in
            guard let host else { return }
            do {
                let transition = try await host.automixPrepare(request)
                await self?.finish(key: key, requestID: requestID, transition: transition, started: started)
            } catch {
                self?.fail(key: key, requestID: requestID, error: error, started: started)
            }
        }
        var newPlan = Plan(key: key, requestID: requestID, stage: .preparing, task: task)
        newPlan.quality = quality
        plan = newPlan
    }

    private func isCurrent(_ key: AutomixPlanKey, _ requestID: String) -> Bool {
        plan?.key == key && plan?.requestID == requestID
    }

    private func finish(key: AutomixPlanKey, requestID: String, transition: AutomixTransition, started: Date) async {
        // Una respuesta de una petición reemplazada o descartada no se aplica.
        guard isCurrent(key, requestID), plan?.stage == .preparing else { return }
        let seconds = now().timeIntervalSince(started)
        request?.finishedAt = now()
        guard transition.isConsistent, transition.fromVideoID == key.from, transition.toVideoID == key.to else {
            log("transición descartada: contrato incoherente (\(String(format: "%.1f", seconds)) s)")
            request?.phase = .failed
            request?.failureLabel = "contrato incoherente"
            request?.transition = transition
            request?.upgrade = "no aplica"
            markFailed(.failed)
            return
        }
        log("lista \(Self.short(requestID)) [\(transition.quality)]\(transition.reused ? " (reutilizada)" : ""): \(transition.kind) \(String(format: "%.0f", transition.displayBPM)) bpm, compases \(transition.bars), "
            + "modelo \(transition.stemsModel ? "sí" : "no"), aCut \(String(format: "%.2f", transition.aCut)), traspaso \(String(format: "%.2f", transition.handover)) "
            + "en archivo, core \(String(format: "%.1f", transition.elapsedSeconds)) s (separó \(String(format: "%.1f", transition.separatedSeconds)) s), "
            + "total \(String(format: "%.1f", seconds)) s — \(transition.detail)")
        request?.phase = .ready
        request?.transition = transition
        plan?.stage = .ready
        plan?.transition = transition
        qualityState = AutomixQualityState(preparing: nil, ready: transition.quality == "stems" ? "stems" : "fast", upgrade: .none)
        status = .ready(kind: transition.kind, bpm: transition.displayBPM)

        if let host {
            if transition.quality == "stems" {
                // La primera petición ya fue la de stems: no hay nada que mejorar.
                plan?.upgradeSettled = true
                request?.upgrade = "no aplica: la primera petición ya fue la de stems"
                log("mejora a stems: no aplica — la pareja estaba lista y se pidió stems directamente")
            } else {
                // ¿Hay que intentar la versión de stems? Con los ajustes, la capacidad y si la pareja ya quedó lista.
                let settings = host.automixSettings()
                let power = host.automixPower()
                let allow = AutomixStrategy.allowStems(settings: settings, power: power)
                let ready = allow.allowed && host.automixPairReady(from: key.from, to: key.to)
                noteStrategy(pairReady: ready, allow: allow)
                var decision = AutomixStrategy.wantsStems(settings: settings, capability: host.automixCapability(), power: power, pairReady: ready)
                if decision.wants, directStemsFailed.contains(key) { decision = (false, "la petición directa de stems ya falló para esta pareja") }
                log("mejora a stems: \(decision.wants ? "sí" : "no") — \(decision.reason)")
                if decision.wants {
                    startUpgrade(key: key, from: transition, host: host)
                } else if allow.allowed {
                    request?.upgrade = "no pedida: \(decision.reason) (se vigila la pareja)"
                    qualityState.upgrade = directStemsFailed.contains(key) ? .notUsed(.pairFailed) : .watching
                } else {
                    plan?.upgradeSettled = true
                    request?.upgrade = "no pedida: \(decision.reason)"
                    qualityState.upgrade = .notUsed(settings.quality == "fast" ? .alwaysFast : .battery(lowPower: power.lowPower))
                }
            }
        }
        if let host, let context = host.automixContext(), context.hasStarted { armIfNeeded(context: context) }
        else { log("el tema aún no suena: el archivo se entregará al reproductor cuando empiece") }
    }

    // MARK: - Entrega al reproductor

    private func armIfNeeded(context: AutomixContext) {
        guard context.hasStarted, var current = plan, current.stage == .ready, !current.armed, !current.arming,
              let transition = current.transition, let host else { return }
        current.arming = true
        plan = current
        let key = current.key
        let requestID = current.requestID
        Task { [weak self] in
            let outcome = await host.automixArm(transition)
            self?.armed(key: key, requestID: requestID, transition: transition, outcome: outcome)
        }
    }

    private func armed(key: AutomixPlanKey, requestID: String, transition: AutomixTransition, outcome: AutomixArmOutcome) {
        // El tema pudo cambiar mientras el reproductor cargaba el archivo.
        guard plan?.key == key else {
            if outcome == .armed || outcome == .enteredLate { host?.automixDisarm() }
            return
        }
        plan?.arming = false
        switch outcome {
        case .armed:
            plan?.armed = true
            request?.note = "empalme armado (\(transition.quality))"
            marker = AutomixProgressMarker(transition: transition)
            // Stems llegó mientras se cargaba la rápida: se cambia ahora.
            if let pending = plan?.pendingUpgrade {
                plan?.pendingUpgrade = nil
                Task { [weak self] in await self?.applyUpgrade(key: key, stems: pending, fast: transition, requested: self?.request?.upgradeRequestedAt ?? Date()) }
            }
        case .enteredLate:
            plan?.armed = true
            request?.note = "entrada tardía al archivo"
            marker = AutomixProgressMarker(transition: transition)
            spliceEntered()
        case .tooLate:
            request?.note = "llegó tarde: la reproducción ya pasó el punto de corte"
            log("llegó tarde: la reproducción ya pasó el punto de corte")
            markFailed(.tooLate)
        case .failed:
            request?.note = "el reproductor no pudo cargar el archivo"
            log("el reproductor no pudo armar el archivo")
            markFailed(.failed)
        }
    }

    // MARK: - Mejora a stems

    private func startUpgrade(key: AutomixPlanKey, from fast: AutomixTransition, host: any AutomixHost) {
        guard plan?.key == key, plan?.upgradeRequestID == nil, plan?.upgradeSettled == false else { return }
        // Ya no merece la pena si el corte está encima: la de stems tardaría unos segundos y su corte puede moverse.
        if let position = host.automixPosition(), fast.aCut - position < AutomixUpgradePlanner.minimumLeadSeconds {
            plan?.upgradeSettled = true
            request?.upgrade = "omitida: faltan \(String(format: "%.1f", max(0, fast.aCut - position))) s para el corte"
            qualityState.upgrade = .notUsed(.tooClose)
            log("mejora a stems: no se pide — faltan \(String(format: "%.1f", fast.aCut - position)) s para el corte (< \(Int(AutomixUpgradePlanner.minimumLeadSeconds)) s)")
            return
        }
        if !host.automixCanReplaceSplice() {
            plan?.upgradeSettled = true
            request?.upgrade = "omitida: el empalme ya se comprometió"
            qualityState.upgrade = .notUsed(.afterSplice)
            log("mejora a stems: no se pide — el empalme ya se comprometió")
            return
        }
        let requestID = UUID().uuidString
        let request = AutomixRequest(requestID: requestID, from: AutomixSong(videoID: key.from, isUpload: self.request?.from.isUpload ?? false),
                                     to: AutomixSong(videoID: key.to, isUpload: self.request?.to.isUpload ?? false),
                                     cacheDirectory: host.automixCacheDirectory(), quality: "stems")
        let started = now()
        log("petición \(Self.short(requestID)) [stems]: mejora de la versión rápida")
        self.request?.upgrade = "pedida (\(Self.short(requestID)))"
        self.request?.upgradeRequestedAt = started
        qualityState.upgrade = .working(since: started)
        plan?.upgradeRequestID = requestID
        plan?.upgradeSettled = true
        plan?.upgradeTask = Task { [weak self, weak host] in
            guard let host else { return }
            do {
                let transition = try await host.automixPrepare(request)
                await self?.finishUpgrade(key: key, requestID: requestID, transition: transition, fast: fast, started: started)
            } catch {
                self?.failUpgrade(key: key, requestID: requestID, error: error, started: started)
            }
        }
    }

    private func isCurrentUpgrade(_ key: AutomixPlanKey, _ requestID: String) -> Bool {
        plan?.key == key && plan?.upgradeRequestID == requestID
    }

    private func finishUpgrade(key: AutomixPlanKey, requestID: String, transition: AutomixTransition, fast: AutomixTransition, started: Date) async {
        guard isCurrentUpgrade(key, requestID) else { return }
        let seconds = now().timeIntervalSince(started)
        request?.upgradeFinishedAt = now()
        plan?.upgradeRequestID = nil
        if !transition.reused { typicalUpgradeSeconds = typicalUpgradeSeconds.map { ($0 + seconds) / 2 } ?? seconds }
        guard transition.isConsistent, transition.fromVideoID == key.from, transition.toVideoID == key.to else {
            request?.upgrade = "descartada: contrato incoherente"
            qualityState.upgrade = .notUsed(.invalid)
            log("stems descartada: contrato incoherente")
            return
        }
        log("stems lista \(Self.short(requestID))\(transition.reused ? " (reutilizada)" : ""): core \(String(format: "%.1f", transition.elapsedSeconds)) s, separó \(String(format: "%.1f", transition.separatedSeconds)) s, "
            + "total \(String(format: "%.1f", seconds)) s; corte \(String(format: "%.2f", transition.aCut)) s (rápida \(String(format: "%.2f", fast.aCut)) s), mismo corte \(AutomixUpgradePlanner.sameCut(fast, transition) ? "sí" : "no")")
        guard plan?.stage == .ready, let host else {
            request?.upgrade = "omitida: llegó tras el empalme"
            qualityState.upgrade = .notUsed(.afterSplice)
            log("stems llegó tras el empalme (el archivo ya suena): se queda la rápida")
            return
        }
        if plan?.arming == true {
            // El reproductor aún carga la rápida: se cambia en cuanto la acepte.
            plan?.pendingUpgrade = transition
            request?.upgrade = "pendiente: se cambia al terminar de armar la rápida"
            return
        }
        await applyUpgrade(key: key, stems: transition, fast: fast, requested: started, host: host)
    }

    /// Decide con la posición actual y aplica la sustitución (o la descarta con el motivo).
    private func applyUpgrade(key: AutomixPlanKey, stems: AutomixTransition, fast: AutomixTransition, requested: Date, host: (any AutomixHost)? = nil) async {
        guard plan?.key == key, plan?.stage == .ready, let host = host ?? self.host else { return }
        let seconds = now().timeIntervalSince(requested)
        let decision = AutomixUpgradePlanner.decide(fast: fast, stems: stems, position: host.automixPosition(),
                                                    committed: plan?.armed == true && !host.automixCanReplaceSplice())
        switch decision {
        case .skip(let reason):
            request?.upgrade = "omitida: \(reason)"
            qualityState.upgrade = .notUsed(.fromPlanner(reason))
            log("stems no se aplica — \(reason): se queda la rápida")
            return
        case .apply(let same):
            if plan?.armed == true {
                let outcome = await host.automixReplace(stems)
                guard plan?.key == key else { return }
                guard outcome == .armed else {
                    request?.upgrade = "omitida: el empalme se comprometió o el corte nuevo ya no cabe"
                    qualityState.upgrade = .notUsed(.afterSplice)
                    log("stems llegó con el empalme comprometido o el corte nuevo ya no cabe: se queda la rápida")
                    return
                }
            }
            plan?.transition = stems
            request?.transition = stems
            request?.upgrade = "aplicada (\(String(format: "%.1f", seconds)) s tras pedirla\(same ? "" : "; corte nuevo \(String(format: "%.2f", stems.aCut)) s"))"
            request?.note = "empalme armado (stems)"
            qualityState.ready = "stems"
            qualityState.upgrade = .applied
            goodVersionLandedCount += 1
            if case .ready = status { status = .ready(kind: stems.kind, bpm: stems.displayBPM) }
            if plan?.armed == true {
                // El corte y el solape pueden ser otros: la marca de la barra se mueve con ellos.
                marker = AutomixProgressMarker(transition: stems)
            }
            log("la versión de stems sustituyó a la rápida antes de comprometer el empalme\(same ? "" : " (corte y solape nuevos: se vuelve a planear la línea de tiempo y se mueve la marca)")")
        }
    }

    private func failUpgrade(key: AutomixPlanKey, requestID: String, error: Error, started: Date) {
        guard isCurrentUpgrade(key, requestID) else { return }
        let report = error as? AutomixFailureReport
        let failure = report?.failure ?? (error as? AutomixFailure) ?? .other
        let raw = AutomixLogSanitizer.sanitize(report?.message ?? "\(type(of: error))")
        plan?.upgradeRequestID = nil
        request?.upgradeFinishedAt = now()
        request?.upgrade = failure == .cancelled ? "cancelada" : "falló: \(failure.logLabel)"
        qualityState.upgrade = failure == .cancelled ? .notUsed(.cancelled) : .failed
        log("stems sin resultado (\(failure.logLabel)) tras \(String(format: "%.1f", now().timeIntervalSince(started))) s: \(raw) — se queda la rápida")
    }

    // MARK: - Fallos de la petición principal

    private func fail(key: AutomixPlanKey, requestID: String, error: Error, started: Date) {
        guard isCurrent(key, requestID) else { return }
        let report = error as? AutomixFailureReport
        let failure = report?.failure ?? (error as? AutomixFailure) ?? .other
        let seconds = now().timeIntervalSince(started)
        let raw = AutomixLogSanitizer.sanitize(report?.message ?? "\(type(of: error))")
        log("sin transición (\(failure.logLabel)) tras \(String(format: "%.1f", seconds)) s: \(raw)")
        request?.finishedAt = now()
        request?.rawError = raw
        request?.failureLabel = failure.logLabel

        // La petición directa de stems falló (modelo que se fue, etc.): se pide la rápida, una sola vez.
        if plan?.quality == "stems", failure != .cancelled, !directStemsFailed.contains(key), let host, let context = host.automixContext(),
           let next = context.next, next.videoID == key.to {
            directStemsFailed.insert(key)
            log("la petición directa de stems falló (\(failure.logLabel)): se pide la versión rápida")
            plan = nil
            start(key: key, from: context.current, to: next, host: host, forced: false)
            return
        }
        request?.upgrade = "no aplica"
        guard let reason = failure.reason else {
            // Cancelada y no por nosotros (el core la sustituyó por otra pareja o la soltó): no se borra el plan para que
            // el siguiente `reconcile` no la vuelva a pedir al instante; se reintenta con espera, un par de veces.
            request?.phase = .cancelled
            if var current = plan, current.stage == .preparing {
                current.stage = .failed
                current.task = nil
                current.retryAt = now().addingTimeInterval(retryDelay)
                plan = current
                qualityState = AutomixQualityState()
                status = .idle
                log("el core canceló la petición: se reintenta en \(Int(retryDelay)) s (sin volver a pedirla ahora)")
            }
            return
        }
        request?.phase = .failed
        markFailed(reason)
    }

    private func markFailed(_ reason: AutomixUnavailableReason) {
        marker = nil
        qualityState = AutomixQualityState()
        guard var plan else { return }
        plan.stage = .failed
        plan.task = nil
        self.plan = plan
        status = .unavailable(reason)
    }

    // MARK: - Texto de diagnóstico

    nonisolated static func short(_ requestID: String) -> String { String(requestID.prefix(8)) }

    nonisolated static func describe(_ reason: AutomixUnavailableReason) -> String {
        switch reason {
        case .jam: "Jam activo"
        case .repeatOne: "repetición de un tema"
        case .noNextTrack: "sin siguiente conocido"
        case .sameTrack: "el siguiente es el mismo tema"
        case .sameAlbum: "mismo álbum"
        case .unsupportedFormat: "formato no AAC"
        case .tooLong: "canción demasiado larga"
        case .tooLate: "llegó tarde"
        case .failed: "falló la preparación"
        }
    }

    nonisolated static func describe(_ status: Status) -> String {
        switch status {
        case .off: "apagado"
        case .idle: "activado, esperando"
        case .preparing: "preparando"
        case .ready(let kind, let bpm): "lista (\(kind), \(String(format: "%.0f", bpm)) bpm)"
        case .unavailable(let reason): "no disponible: \(describe(reason))"
        case .mixing(let kind): "mezclando (\(kind))"
        }
    }
}
