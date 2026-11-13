import SwiftUI

extension View {
    /// Shows the outcome of Jam queue edits (`JamSessionController.lastActionMessage`) as a transient toast.
    func jamToasts() -> some View { modifier(JamToastModifier()) }

    /// Asks before leaving the Jam to play something else (`PlayerViewModel.pendingJamExit`).
    func jamExitConfirmation(player: PlayerViewModel) -> some View { modifier(JamExitConfirmation(player: player)) }
}

// MARK: Toasts

private struct JamToastModifier: ViewModifier {
    @State private var controller = JamSessionController.shared
    @State private var current: JamActionMessage?
    @State private var dismissTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let current {
                    JamToastView(message: current) { dismiss() }
                        .padding(.top, 14).padding(.horizontal, 16)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .onChange(of: controller.lastActionMessage) { _, message in
                guard let message else { return }
                show(message)
            }
            .onDisappear { dismissTask?.cancel() }
    }

    private func show(_ message: JamActionMessage) {
        dismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.18)) { current = message }
        AccessibilityNotification.Announcement(JamToastView.text(for: message)).post()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) { current = nil }
    }
}

struct JamToastView: View {
    let message: JamActionMessage
    var onDismiss: () -> Void = {}

    static func text(for message: JamActionMessage) -> String { L10n.text(message.key, args: message.args) }

    private static let successKeys: Set<String> = ["added", "inserted", "moved", "removed", "addedMany", "insertedMany"]
    private var isSuccess: Bool { Self.successKeys.contains(message.key.replacingOccurrences(of: "jam.action.", with: "")) }
    private var isInfo: Bool { ["playRowUnsupported", "removeCurrentUnsupported", "shuffleRepeatInert", "busy"].contains { message.key.hasSuffix($0) } }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : (isInfo ? "info.circle.fill" : "exclamationmark.triangle.fill"))
                .font(.system(size: 15)).foregroundStyle(isSuccess ? Color.green : (isInfo ? Color.white.opacity(0.8) : Color.orange))
                .accessibilityHidden(true)
            Text(verbatim: Self.text(for: message))
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(L10n.text("jam.toast.dismiss")).accessibilityLabel(L10n.text("jam.toast.dismiss"))
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
        .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.clear).compatGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous)) }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AppTheme.cardBorder, lineWidth: 0.75))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Exit confirmation

private struct JamExitConfirmation: ViewModifier {
    let player: PlayerViewModel

    func body(content: Content) -> some View {
        let pending = player.pendingJamExit
        content.confirmationDialog(
            L10n.text("jam.exit.title"),
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { player.cancelJamExit() } }),
            titleVisibility: .visible
        ) {
            Button(L10n.text("jam.exit.confirm")) { player.confirmJamExit() }
            Button(L10n.text("jam.exit.cancel"), role: .cancel) { player.cancelJamExit() }
        } message: {
            if let subject = pending?.subject, !subject.isEmpty { Text(L10n.text("jam.exit.message", args: [subject])) }
            else { Text(L10n.text("jam.exit.messageGeneric")) }
        }
    }
}
