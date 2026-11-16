import Foundation
import Observation
import SideBCore

/// Ajustes de Automix del core (calidad, batería, mismo álbum, procesador, adelanto, modelo en memoria), su capacidad
/// medida y el uso de disco. Una sola fuente para Ajustes, el coordinador y el diagnóstico: el core es quien guarda.
@MainActor
@Observable
final class AutomixPreferences {
    static let shared = AutomixPreferences()

    private(set) var settings = AutomixSettingsValue()
    private(set) var capability: AutomixCapabilityValue?
    private(set) var usage = AutomixCacheUsageValue()
    private(set) var isLoaded = false
    private(set) var isClearing = false
    private(set) var lastError: String?
    @ObservationIgnored private var core: SideBCore?

    /// Carpeta de las cachés de Automix: dentro de la de la app (el HomeLab usa la suya).
    static var cacheDirectory: URL {
        let bundle = Bundle.main.bundleIdentifier ?? "com.fefucho.SideB"
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundle, isDirectory: true)
            .appendingPathComponent(HomeLabConfiguration.enabled ? "automix-lab" : "automix", isDirectory: true)
    }

    /// Engancha el core (nil al cerrar la cuenta o en pruebas) y le dice dónde viven las cachés desde el arranque.
    func attach(core: SideBCore?, cacheDirectory: URL) {
        self.core = core
        guard let core else { isLoaded = false; capability = nil; return }
        core.setAutomixCacheDir(cacheDir: cacheDirectory.path)
        settings = AutomixSettingsValue(record: core.getAutomixSettings())
        capability = AutomixCapabilityValue(record: core.automixCapability())
        isLoaded = true
        AutomixDiagnostics.shared.record("prefs", "ajustes del core: calidad \(settings.quality), batería \(settings.fastOnBattery), mismo álbum \(settings.skipSameAlbum), "
            + "procesador \(settings.compute), adelanto \(settings.lookahead), modelo en memoria \(settings.keepModelLoaded)")
    }

    /// Cambia un ajuste: el core corrige lo fuera de rango y devuelve lo guardado.
    func update(_ change: (inout AutomixSettingsValue) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        if let core {
            settings = AutomixSettingsValue(record: core.setAutomixSettings(settings: next.record))
            AutomixDiagnostics.shared.record("prefs", "ajuste guardado: calidad \(settings.quality), batería \(settings.fastOnBattery), mismo álbum \(settings.skipSameAlbum), "
                + "procesador \(settings.compute), adelanto \(settings.lookahead), modelo en memoria \(settings.keepModelLoaded)")
        } else {
            settings = next
        }
        capability = core.map { AutomixCapabilityValue(record: $0.automixCapability()) } ?? capability
    }

    func refreshCapability() {
        capability = core.map { AutomixCapabilityValue(record: $0.automixCapability()) }
    }

    /// Recorre las carpetas de caché fuera del hilo principal.
    func refreshUsage() {
        guard let core else { return }
        Task { [weak self] in
            let record = await Task.detached(priority: .utility) { core.automixCacheUsage() }.value
            self?.usage = AutomixCacheUsageValue(audioBytes: record.audioBytes, stemsBytes: record.stemsBytes,
                                                 transitionsBytes: record.transitionsBytes, modelBytes: record.modelBytes)
        }
    }

    func clearCache() {
        guard let core, !isClearing else { return }
        isClearing = true
        Task { [weak self] in
            await Task.detached(priority: .utility) { core.clearAutomixCache() }.value
            AutomixDiagnostics.shared.record("prefs", "caché de Automix borrada")
            self?.isClearing = false
            self?.refreshUsage()
        }
    }

    func deleteModel() {
        guard let core, !isClearing else { return }
        isClearing = true
        Task { [weak self] in
            let result: Result<Void, Error> = await Task.detached(priority: .utility) { Result { try core.deleteAutomixModel() } }.value
            switch result {
            case .success:
                AutomixDiagnostics.shared.record("prefs", "modelo de Automix borrado")
                self?.lastError = nil
            case .failure(let error):
                self?.lastError = error.localizedDescription
                AutomixDiagnostics.shared.record("prefs", "no se pudo borrar el modelo: \(error.localizedDescription)")
            }
            self?.isClearing = false
            self?.refreshCapability()
            self?.refreshUsage()
        }
    }
}

/// Texto de la línea de capacidad de Ajustes: «Este equipo: 5,6× tiempo real · CoreML…» o «sin medir todavía».
enum AutomixCapabilityText {
    static func line(_ capability: AutomixCapabilityValue?, language: AppLanguage? = nil) -> String {
        guard let capability else { return L10n.text("settings.automix.capability.unknown", language: language) }
        let provider = capability.provider.isEmpty ? "" : " · \(capability.provider)"
        guard let factor = capability.realtimeFactor else {
            return L10n.text("settings.automix.capability.unmeasured", args: [provider], language: language)
        }
        let number = String(format: "%.1f", locale: (language ?? L10n.language).locale, factor)
        return L10n.text("settings.automix.capability.measured", args: [number, provider], language: language)
    }
}
