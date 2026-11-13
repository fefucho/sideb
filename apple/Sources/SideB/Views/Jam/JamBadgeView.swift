import SwiftUI

/// "In X's Jam" marker with participant avatars. Renders nothing while no Jam is live.
struct JamBadgeView: View {
    enum Size { case regular, compact }
    var size: Size = .regular
    var onTap: (() -> Void)?

    var body: some View {
        let controller = JamSessionController.shared
        if controller.phase == .live {
            JamBadgeContent(hostName: controller.hostName, members: Self.members(controller), size: size, onTap: onTap)
        }
    }

    private static func members(_ controller: JamSessionController) -> [JamPanelMember] {
        controller.members.enumerated().map {
            JamPanelMember(id: $0.offset, name: $0.element.name, imageURL: $0.element.imageUrl.flatMap(URL.init(string:)),
                           isHost: $0.element.isHost, isMe: $0.element.isMe)
        }
    }
}

/// The pill itself, free of controller state so it can be rendered from fixtures.
struct JamBadgeContent: View {
    let hostName: String?
    let members: [JamPanelMember]
    var size: JamBadgeView.Size = .regular
    var onTap: (() -> Void)?

    private var label: String {
        if let hostName, !hostName.trimmingCharacters(in: .whitespaces).isEmpty { return L10n.text("jam.badge.label", args: [hostName]) }
        return L10n.text("jam.badge.labelNoHost")
    }

    private var pill: some View {
        let compact = size == .compact
        return HStack(spacing: compact ? 6 : 8) {
            if !members.isEmpty {
                JamAvatarStack(members: members, size: compact ? 16 : 22, limit: compact ? 3 : 4)
            } else {
                Image(systemName: "person.2.fill").font(.system(size: compact ? 10 : 12, weight: .semibold)).accessibilityHidden(true)
            }
            Text(verbatim: label)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.leading, compact ? 6 : 8)
        .padding(.trailing, compact ? 10 : 14)
        .padding(.vertical, compact ? 4 : 5)
        .background { Capsule().fill(Color.clear).compatGlass(in: Capsule()) }
        .background(Capsule().fill(Color.black.opacity(0.18)))
        .overlay(Capsule().strokeBorder(AppTheme.cardBorder, lineWidth: AppTheme.cardBorderWidth))
        .contentShape(Capsule())
    }

    var body: some View {
        if let onTap {
            Button(action: onTap) { pill }
                .buttonStyle(.plain)
                .help(L10n.text("jam.badge.help"))
                .accessibilityLabel(label)
                .accessibilityHint(L10n.text("jam.badge.help"))
        } else {
            pill.accessibilityElement(children: .ignore).accessibilityLabel(label)
        }
    }
}
