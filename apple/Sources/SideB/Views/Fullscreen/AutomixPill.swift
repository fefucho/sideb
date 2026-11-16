import SwiftUI

/// «Beta · Automix» en pantalla completa: activa o desactiva el ajuste y muestra el estado de la
/// transición. Vive sobre la portada (fuera de la barra inferior); misma cápsula que el distintivo del Jam.
struct AutomixPill: View {
    let viewModel: PlayerViewModel

    var body: some View {
        // A Jam forces Automix off without touching the saved preference: the pill stays visible but disabled.
        let jam = viewModel.isJamSessionActive
        let status: AutomixCoordinator.Status = jam ? .unavailable(.jam) : viewModel.automix.status
        let isOn = !jam && AutomixStatusPresentation.isOn(status)
        let statusText = AutomixStatusPresentation.text(for: status)
        let action = jam ? statusText : L10n.text(isOn ? "automix.pill.turnOff" : "automix.pill.turnOn")
        Button { viewModel.automixEnabled.toggle() } label: {
            HStack(spacing: 6) {
                if status == .preparing {
                    ProgressView().controlSize(.mini).scaleEffect(0.8).frame(width: 12, height: 12)
                } else {
                    Image(systemName: AutomixStatusPresentation.symbol(for: status))
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
                Text(L10n.text("automix.pill.title"))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white.opacity(jam ? 0.4 : (isOn ? 0.95 : 0.62)))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background { Capsule().fill(Color.clear).compatGlass(in: Capsule()) }
            .background(Capsule().fill(Color.black.opacity(0.18)))
            .overlay(Capsule().strokeBorder(AppTheme.cardBorder, lineWidth: AppTheme.cardBorderWidth))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(jam)
        .help("\(L10n.text("automix.pill.title")): \(statusText). \(action)")
        .accessibilityLabel(L10n.text("automix.pill.title"))
        .accessibilityValue(statusText)
        .accessibilityHint(action)
        .accessibilityIdentifier("automix-pill")
    }
}
