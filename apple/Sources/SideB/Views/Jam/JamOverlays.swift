import SwiftUI

extension View {
    /// Shows the outcome of Jam queue edits (`JamSessionController.lastActionMessage`) as a transient toast.
    func jamToasts() -> some View { modifier(JamToastModifier()) }

    /// Asks before leaving the Jam to play something else (`PlayerViewModel.pendingJamExit`).
    func jamExitConfirmation(player: PlayerViewModel) -> some View { modifier(JamExitConfirmation(player: player)) }

    /// Shows incoming live Spotify Jam invitations as a transient top banner below the toolbar.
    func jamInviteBanner(player: PlayerViewModel) -> some View { modifier(JamInviteBannerModifier(player: player)) }
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

// MARK: Incoming Jam Invite Banner

private struct JamInviteBannerModifier: ViewModifier {
    let player: PlayerViewModel
    @State private var controller = JamSessionController.shared
    @State private var autoDismissTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let invite = controller.bannerInvite {
                    JamInviteBannerView(
                        invite: invite,
                        onJoin: {
                            autoDismissTask?.cancel()
                            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.18)) {
                                controller.joinInvite(invite, player: player)
                            }
                        },
                        onDismiss: {
                            autoDismissTask?.cancel()
                            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.18)) {
                                controller.dismissInvite(id: invite.id)
                            }
                        }
                    )
                    .padding(.top, player.isFullscreenPresented ? 14 : ShellLayout.toolbarHostHeight + 8)
                    .padding(.horizontal, 16)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .zIndex(11)
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.18), value: controller.bannerInvite)
            .onChange(of: controller.bannerInvite, initial: true) { _, invite in
                autoDismissTask?.cancel()
                guard let invite else { return }
                AccessibilityNotification.Announcement(JamInviteBannerView.announcementText(for: invite)).post()
                let inviteId = invite.id
                autoDismissTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) {
                        controller.dismissBanner(id: inviteId)
                    }
                }
            }
            .onDisappear { autoDismissTask?.cancel() }
    }
}

struct JamInviteBannerView: View {
    let invite: JamInvite
    var onJoin: () -> Void = {}
    var onDismiss: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isJoinHovered = false
    @State private var isDismissHovered = false

    static func titleText(for invite: JamInvite) -> String {
        let trimmed = invite.senderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return L10n.text("jam.invite.banner.title", args: [trimmed])
        }
        return L10n.text("jam.invite.banner.titleUnknown")
    }

    static func announcementText(for invite: JamInvite) -> String {
        "\(titleText(for: invite)). \(L10n.text("jam.invite.banner.subtitle"))"
    }

    private var avatarURL: URL? {
        invite.senderImageUrl.flatMap(URL.init(string:))
    }

    var body: some View {
        let title = Self.titleText(for: invite)
        let subtitle = L10n.text("jam.invite.banner.subtitle")
        HStack(spacing: 12) {
            JamAvatarView(name: invite.senderName, imageURL: avatarURL, size: 36)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 260, alignment: .leading)

            HStack(spacing: 6) {
                Button(action: onJoin) {
                    Text(verbatim: L10n.text("jam.invite.join"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(
                            Capsule()
                                .fill(Color.sidebAccent.opacity(isJoinHovered ? 1 : 0.92))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.sidebAccentHighlight.opacity(0.78), lineWidth: 0.75)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { isJoinHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isJoinHovered)
                .accessibilityLabel("\(L10n.text("jam.invite.join")), \(title)")

                Button(action: onDismiss) {
                    Text(verbatim: L10n.text("jam.invite.dismiss"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(isDismissHovered ? 0.96 : 0.78))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(isDismissHovered ? 0.16 : 0.09))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { isDismissHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isDismissHovered)
                .accessibilityLabel("\(L10n.text("jam.invite.dismiss")), \(title)")
            }
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.clear)
                .compatGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AppTheme.cardBorder, lineWidth: 0.75))
        .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .windowGestureRegion(.excluded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.announcementText(for: invite))
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
