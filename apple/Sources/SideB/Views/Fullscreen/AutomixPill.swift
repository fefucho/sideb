import SwiftUI

/// «Automix» en pantalla completa: activa o desactiva el ajuste y dice en palabras llanas qué versión de la mezcla hay
/// (rápida o buena), si la buena se está preparando y cuándo empieza la mezcla. Vive sobre la portada (fuera de la
/// barra inferior); misma cápsula que el distintivo del Jam.
struct AutomixPill: View {
    let viewModel: PlayerViewModel

    var body: some View {
        // A Jam forces Automix off without touching the saved preference: the pill stays visible but disabled.
        let jam = viewModel.isJamSessionActive
        let status: AutomixCoordinator.Status = jam ? .unavailable(.jam) : viewModel.automix.status
        let quality = jam ? AutomixQualityState() : viewModel.automix.qualityState
        let isOn = !jam && AutomixStatusPresentation.isOn(status)
        let mixStart = viewModel.automix.mixStartSeconds.map { viewModel.formattedTime(at: $0) }
        let action = jam ? L10n.text("automix.unavailable.jam") : L10n.text(isOn ? "automix.pill.turnOff" : "automix.pill.turnOn")
        let tooltip = AutomixUserText.pillTooltip(status: status, quality: quality, mixStart: mixStart)
        let ticking = !jam && quality.isImproving && status.isReady
        Button { viewModel.automixEnabled.toggle() } label: {
            HStack(spacing: 6) {
                if status == .preparing || ticking {
                    ProgressView().controlSize(.mini).scaleEffect(0.8).frame(width: 12, height: 12)
                } else {
                    Image(systemName: AutomixStatusPresentation.symbol(for: status, quality: quality))
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
                // Los segundos de «mejorando…» avanzan una vez por segundo, sólo mientras se prepara la versión buena.
                TimelineView(.periodic(from: .now, by: ticking ? 1 : 3600)) { context in
                    Text(AutomixUserText.pillText(status: status, quality: quality, now: context.date))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
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
        .help("\(tooltip) \(action)")
        .accessibilityLabel(L10n.text("automix.pill.title"))
        .accessibilityValue(AutomixUserText.pillText(status: status, quality: quality, now: Date()))
        .accessibilityHint("\(tooltip) \(action)")
        .accessibilityIdentifier("automix-pill")
    }
}

/// Aviso breve dentro de la pantalla completa cuando la versión buena sustituye a la rápida. No es una notificación
/// del sistema: aparece unos segundos sobre la portada y se va solo.
struct AutomixGoodVersionToast: View {
    let viewModel: PlayerViewModel
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        Group {
            if visible {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
                    Text(L10n.text("automix.toast.goodReady")).font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.95))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .overlay(Capsule().strokeBorder(AppTheme.cardBorder, lineWidth: AppTheme.cardBorderWidth))
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("automix-good-toast")
            }
        }
        .allowsHitTesting(false)
        .onChange(of: viewModel.automix.goodVersionLandedCount) { _, _ in
            hideTask?.cancel()
            withAnimation(.easeOut(duration: 0.2)) { visible = true }
            hideTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.25)) { visible = false }
            }
        }
        .onDisappear { hideTask?.cancel() }
    }
}
