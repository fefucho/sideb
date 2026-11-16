import SwiftUI

/// Ajustes de Automix del core, bajo el interruptor: calidad, batería, mismo disco y un bloque «Avanzado».
/// Todo pasa por `AutomixPreferences` (el core guarda y corrige los valores).
struct AutomixSettingsSection: View {
    @Bindable var preferences: AutomixPreferences
    @State private var showsAdvanced = false
    @State private var confirmsModelDeletion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L10n.text("settings.automix.quality"), selection: binding(\.quality)) {
                Text(L10n.text("settings.automix.quality.auto")).tag("auto")
                Text(L10n.text("settings.automix.quality.fast")).tag("fast")
                Text(L10n.text("settings.automix.quality.stems")).tag("stems")
            }
            .pickerStyle(.menu)
            .font(.system(size: 12))
            .accessibilityIdentifier("automix-quality-picker")

            Toggle(L10n.text("settings.automix.fastOnBattery"), isOn: binding(\.fastOnBattery))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .accessibilityIdentifier("automix-battery-toggle")
            Toggle(L10n.text("settings.automix.skipSameAlbum"), isOn: binding(\.skipSameAlbum))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .accessibilityIdentifier("automix-same-album-toggle")

            DisclosureGroup(isExpanded: $showsAdvanced) {
                advanced
                    .padding(.top, 6)
            } label: {
                Text(L10n.text("settings.automix.advanced")).font(.system(size: 12, weight: .medium))
            }
            .accessibilityIdentifier("automix-advanced")
            .onChange(of: showsAdvanced) { _, shown in
                if shown { preferences.refreshCapability(); preferences.refreshUsage() }
            }
        }
        .padding(.leading, 20)
        .confirmationDialog(L10n.text("settings.automix.model.delete.title"), isPresented: $confirmsModelDeletion, titleVisibility: .visible) {
            Button(L10n.text("settings.automix.model.delete.confirm"), role: .destructive) { preferences.deleteModel() }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("settings.automix.model.delete.message"))
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L10n.text("settings.automix.compute"), selection: binding(\.compute)) {
                Text(L10n.text("settings.automix.compute.auto")).tag("auto")
                Text(L10n.text("settings.automix.compute.gpu")).tag("gpu")
                Text(L10n.text("settings.automix.compute.cpu")).tag("cpu")
            }
            .pickerStyle(.menu)
            .font(.system(size: 12))
            .accessibilityIdentifier("automix-compute-picker")

            Picker(L10n.text("settings.automix.lookahead"), selection: binding(\.lookahead)) {
                ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .font(.system(size: 12))
            .accessibilityIdentifier("automix-lookahead-picker")

            Toggle(L10n.text("settings.automix.keepModel"), isOn: binding(\.keepModelLoaded))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .accessibilityIdentifier("automix-keep-model-toggle")
            Text(L10n.text("settings.automix.keepModel.hint"))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Text(AutomixCapabilityText.line(preferences.capability))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("automix-capability")

            Text(AutomixCacheText.cacheLine(preferences.usage))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(AutomixCacheText.modelLine(preferences.usage, capability: preferences.capability))
                .font(.system(size: 12)).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(L10n.text("settings.automix.cache.clear")) { preferences.clearCache() }
                    .disabled(preferences.isClearing)
                    .accessibilityIdentifier("automix-clear-cache")
                Button(L10n.text("settings.automix.model.delete")) { confirmsModelDeletion = true }
                    .disabled(preferences.isClearing || !(preferences.capability?.modelReady ?? false) && preferences.usage.modelBytes == 0)
                    .accessibilityIdentifier("automix-delete-model")
            }
            .font(.system(size: 12))
            if let error = preferences.lastError {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AutomixSettingsValue, Value>) -> Binding<Value> {
        Binding(get: { preferences.settings[keyPath: keyPath] },
                set: { newValue in preferences.update { $0[keyPath: keyPath] = newValue } })
    }
}

/// Texto del uso de disco (pura: se prueba sin vistas).
enum AutomixCacheText {
    static func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))), countStyle: .file) }

    static func cacheLine(_ usage: AutomixCacheUsageValue, language: AppLanguage? = nil) -> String {
        L10n.text("settings.automix.cache.usage", args: [bytes(usage.total), bytes(usage.audioBytes), bytes(usage.stemsBytes), bytes(usage.transitionsBytes)], language: language)
    }

    static func modelLine(_ usage: AutomixCacheUsageValue, capability: AutomixCapabilityValue?, language: AppLanguage? = nil) -> String {
        if usage.modelBytes > 0 { return L10n.text("settings.automix.model.size", args: [bytes(usage.modelBytes)], language: language) }
        if capability?.modelDownloading == true { return L10n.text("settings.automix.model.downloading", language: language) }
        return L10n.text("settings.automix.model.absent", language: language)
    }
}
