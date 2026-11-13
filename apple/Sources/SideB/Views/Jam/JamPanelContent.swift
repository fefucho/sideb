import AppKit
import SwiftUI

/// Colours of the panel: system colours in the popover, light-on-dark over the fullscreen scene.
struct JamPalette {
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let card: Color
    let border: Color

    static let popover = JamPalette(primary: .primary, secondary: .secondary,
                                    tertiary: Color(nsColor: .secondaryLabelColor).opacity(0.78),
                                    card: Color.primary.opacity(0.055), border: Color.primary.opacity(0.09))
    static let fullscreen = JamPalette(primary: .white, secondary: .white.opacity(0.70), tertiary: .white.opacity(0.52),
                                       card: Color.white.opacity(0.07), border: Color.white.opacity(0.11))
}

/// Everything the panel can ask for; the hosting view wires it to the controller.
struct JamPanelActions {
    var join: (String) -> Void = { _ in }
    var joinInvite: ((JamPanelInvite) -> Void)? = nil
    var dismissInvite: (String) -> Void = { _ in }
    var cancel: () -> Void = {}
    var leave: () -> Void = {}
    var choose: (String) -> Void = { _ in }
    var signIn: () -> Void = {}
    var signOut: () -> Void = {}
    var openDebug: () -> Void = {}
    var setNudge: (Double) -> Void = { _ in }
    var setGlobalOffset: (Double) -> Void = { _ in }
}

/// The panel drawn from a snapshot. No controller access, so any state can be rendered from fixtures.
struct JamPanelContent: View {
    let snapshot: JamPanelSnapshot
    var style: JamPanelView.Style = .popover
    var actions = JamPanelActions()

    @State private var link: String
    @State private var showVersions: Bool
    @State private var showSync: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(snapshot: JamPanelSnapshot, style: JamPanelView.Style = .popover, actions: JamPanelActions = JamPanelActions(),
         link: String = "", showVersions: Bool = false, showSync: Bool = false) {
        self.snapshot = snapshot
        self.style = style
        self.actions = actions
        _link = State(initialValue: link)
        _showVersions = State(initialValue: showVersions)
        _showSync = State(initialValue: showSync)
    }

    private var palette: JamPalette { style == .fullscreen ? .fullscreen : .popover }
    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 14) {
            header
            switch snapshot.stage {
            case .join: joinContent
            case .connecting: connectingContent
            case .live: liveContent
            }
            if showSync && snapshot.stage != .live { syncSection }
        }
        .padding(style == .fullscreen ? 24 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.jamPalette, palette)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showVersions)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showSync)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: snapshot.invites)
        if style == .fullscreen {
            ScrollView { content }.scrollIndicators(.hidden).environment(\.colorScheme, .dark)
        } else {
            content
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.sidebAccent.opacity(0.9))
                Image(systemName: snapshot.stage == .live ? "person.2.wave.2.fill" : "person.2.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.primary)
                    .lineLimit(1).truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)
                if snapshot.stage == .live {
                    Text(verbatim: participantsText).font(.system(size: 12)).foregroundStyle(palette.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            moreMenu
        }
    }

    private var title: String {
        guard snapshot.stage == .live else { return L10n.text("jam.panel.title") }
        if let host = snapshot.hostDisplayName { return L10n.text("jam.live.title", args: [host]) }
        return L10n.text("jam.live.titleNoHost")
    }

    private var participantsText: String {
        snapshot.members.count == 1 ? L10n.text("jam.participants.one") : L10n.text("jam.participants.many", args: [String(snapshot.members.count)])
    }

    private var moreMenu: some View {
        Menu {
            Toggle(L10n.text("jam.menu.syncSettings"), isOn: $showSync)
            Divider()
            Button(L10n.text("jam.menu.debug"), action: actions.openDebug)
            if snapshot.access == .ready {
                Divider()
                Button(L10n.text("jam.menu.signOut"), action: actions.signOut)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.secondary)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .frame(width: 28, height: 28)
        .help(L10n.text("jam.menu.more"))
        .accessibilityLabel(L10n.text("jam.menu.more"))
    }

    // MARK: Not in a Jam

    @ViewBuilder private var joinContent: some View {
        if let ended = snapshot.ended {
            banner(symbol: "checkmark.circle.fill", tint: .green, title: L10n.text("jam.ended.title"),
                   message: L10n.text("jam.ended.reason.\(ended.rawValue)") + " " + L10n.text("jam.ended.body"))
        }
        if let failure = snapshot.failure {
            banner(symbol: "exclamationmark.triangle.fill", tint: .orange, title: L10n.text("jam.failure.title"),
                   message: L10n.text(failure.messageKey))
        }
        switch snapshot.access {
        case .pluginMissing:
            card {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L10n.text("jam.plugin.missing.title"), systemImage: "puzzlepiece.extension")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.primary)
                    Text(L10n.text("jam.plugin.missing.body")).font(.system(size: 12)).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .needsLogin(let loginFailed):
            introText
            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("jam.signin.title")).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.primary)
                    Text(L10n.text(loginFailed ? "jam.signin.failed" : "jam.signin.body"))
                        .font(.system(size: 12)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(action: actions.signIn) {
                        SideBControlLabel(title: L10n.text(loginFailed ? "jam.signin.retry" : "jam.signin.button"), symbol: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SideBControlStyle(size: .action, prominent: true))
                }
            }
        case .ready:
            introText
            if !snapshot.invites.isEmpty {
                invitesSection
            }
            linkField
            Button { actions.join(trimmedLink) } label: {
                SideBControlLabel(title: L10n.text("jam.join"), symbol: "arrow.right.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(SideBControlStyle(size: .action, prominent: true))
            .disabled(trimmedLink.isEmpty)
            .keyboardShortcut(.defaultAction)
            .help(trimmedLink.isEmpty ? L10n.text("jam.join.needsLink") : "")
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
                Text(L10n.text("jam.signin.connected")).foregroundStyle(palette.tertiary)
            }
            .font(.system(size: 11))
        }
    }

    private var invitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption(L10n.text("jam.invites.section"))
            ForEach(snapshot.invites) { invite in
                JamInviteRow(
                    invite: invite,
                    onJoin: {
                        if let joinInvite = actions.joinInvite {
                            joinInvite(invite)
                        } else {
                            actions.join(invite.link)
                        }
                    },
                    onDismiss: { actions.dismissInvite(invite.id) }
                )
            }
        }
    }

    private var introText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("jam.panel.intro")).font(.system(size: 13)).foregroundStyle(palette.primary)
            Text(L10n.text("jam.panel.introHint")).font(.system(size: 12)).foregroundStyle(palette.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var linkLooksWrong: Bool {
        let value = trimmedLink.lowercased()
        return !value.isEmpty && !value.contains("spotify")
    }

    private var linkField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "link").font(.system(size: 12, weight: .medium)).foregroundStyle(palette.tertiary).accessibilityHidden(true)
                TextField(L10n.text("jam.link.placeholder"), text: $link)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(palette.primary)
                    .onSubmit { if !trimmedLink.isEmpty { actions.join(trimmedLink) } }
                    .accessibilityLabel(L10n.text("jam.link.label"))
                if trimmedLink.isEmpty {
                    Button(L10n.text("jam.link.paste")) {
                        if let text = NSPasteboard.general.string(forType: .string) { link = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.sidebAccentHighlight)
                    .help(L10n.text("jam.link.pasteHelp"))
                } else {
                    Button { link = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(palette.tertiary)
                    }
                    .buttonStyle(.plain).help(L10n.text("jam.link.clear")).accessibilityLabel(L10n.text("jam.link.clear"))
                }
            }
            .padding(.horizontal, 11).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(linkLooksWrong ? Color.orange.opacity(0.7) : palette.border, lineWidth: 0.75))
            if linkLooksWrong {
                Label(L10n.text("jam.link.looksWrong"), systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(Color.orange)
            }
        }
    }

    private var connectingContent: some View {
        card {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("jam.connecting.title")).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.primary)
                    Text(L10n.text("jam.connecting.hint")).font(.system(size: 12)).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .modifier(CancelRow(action: actions.cancel))
    }

    // MARK: Live

    @ViewBuilder private var liveContent: some View {
        pairingCard
        if showVersions { versionsList }
        participantsCard
        if !snapshot.canControl {
            Label(L10n.text("jam.control.noControl"), systemImage: "lock.fill")
                .font(.system(size: 12)).foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if showSync { syncSection }
        Button(action: actions.leave) {
            SideBControlLabel(title: L10n.text("jam.leave"), symbol: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity)
        }
        .buttonStyle(SideBControlStyle(size: .utility))
        .help(L10n.text("jam.leave.help"))
    }

    private var pairingCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                if let spotify = snapshot.spotify {
                    caption(L10n.text("jam.pairing.spotify"))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        trackText(title: spotify.title, artists: spotify.artists)
                        if let duration = spotify.duration { durationText(duration) }
                    }
                    Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.tertiary)
                        .frame(maxWidth: .infinity).accessibilityHidden(true)
                    HStack(spacing: 6) {
                        caption(L10n.text("jam.pairing.ytm"))
                        if snapshot.version?.isVideo == true { videoTag }
                    }
                    versionLine
                } else {
                    Text(L10n.text("jam.pairing.waiting")).font(.system(size: 12)).foregroundStyle(palette.secondary)
                }
                if let version = snapshot.version, version.warnsAboutDuration, let delta = version.durationDelta {
                    Label(L10n.text(delta > 0 ? "jam.pairing.longer" : "jam.pairing.shorter", args: [String(Int(abs(delta).rounded()))]),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().opacity(0.5)
                HStack(spacing: 8) {
                    statusView
                    Spacer(minLength: 4)
                    if snapshot.spotify != nil { versionsToggle }
                }
            }
        }
    }

    @ViewBuilder private var versionLine: some View {
        if let version = snapshot.version {
            HStack(spacing: 10) {
                artwork(version.thumbnailURL, size: 38)
                trackText(title: version.title, artists: version.artists)
                if let duration = version.duration { durationText(duration) }
            }
        } else if snapshot.status == .searching {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.text("jam.pairing.searching")).font(.system(size: 12)).foregroundStyle(palette.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("jam.pairing.noMatch")).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.primary)
                Text(L10n.text("jam.pairing.noMatchHint")).font(.system(size: 11)).foregroundStyle(palette.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusView: some View {
        let (text, color, busy): (String, Color, Bool) = switch snapshot.status {
        case .synced: (L10n.text("jam.status.synced"), .green, false)
        case .adjusting: (L10n.text("jam.status.adjusting"), Color.sidebAccentHighlight, true)
        case .paused: (L10n.text("jam.status.paused"), palette.secondary, false)
        case .hostInactive: (L10n.text("jam.status.hostInactive"), .orange, false)
        case .searching: (L10n.text("jam.status.searching"), palette.secondary, true)
        case .noMatch: (L10n.text("jam.status.noMatch"), .orange, false)
        case .waiting: (L10n.text("jam.status.waiting"), palette.secondary, false)
        }
        return HStack(spacing: 6) {
            if busy { ProgressView().controlSize(.mini) } else { Circle().fill(color).frame(width: 7, height: 7) }
            Text(verbatim: text).font(.system(size: 11, weight: .medium)).foregroundStyle(snapshot.status == .synced ? palette.secondary : color)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .help(snapshot.status == .hostInactive ? L10n.text("jam.status.hostInactive.help") : "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("jam.status.label"))
        .accessibilityValue(text)
    }

    private var versionsToggle: some View {
        Button { showVersions.toggle() } label: {
            HStack(spacing: 3) {
                Text(L10n.text(showVersions ? "jam.versions.hide" : "jam.versions.choose")).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).rotationEffect(.degrees(showVersions ? 180 : 0))
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.sidebAccentHighlight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text(showVersions ? "jam.versions.hide" : "jam.versions.choose"))
    }

    private var versionsList: some View {
        card(padding: 6) {
            VStack(alignment: .leading, spacing: 2) {
                caption(L10n.text("jam.versions.title")).padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 2)
                if snapshot.candidates.isEmpty {
                    Text(L10n.text("jam.versions.empty")).font(.system(size: 12)).foregroundStyle(palette.secondary).padding(8)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(snapshot.candidates.prefix(10)) { candidate in
                                JamVersionRow(version: candidate, isCurrent: candidate.id == snapshot.version?.id) { actions.choose(candidate.id) }
                            }
                        }
                    }
                    .frame(maxHeight: 196)
                    .scrollIndicators(.automatic)
                }
            }
        }
    }

    private var participantsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                let shown = Array(snapshot.members.prefix(4))
                ForEach(shown) { member in
                    HStack(spacing: 9) {
                        JamAvatarView(name: member.name, imageURL: member.imageURL, size: 26)
                        Text(verbatim: member.name ?? L10n.text("jam.member.guest"))
                            .font(.system(size: 13, weight: member.isMe ? .semibold : .regular)).foregroundStyle(palette.primary)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        if member.isHost { memberTag(L10n.text("jam.member.host"), highlighted: true) }
                        else if member.isMe { memberTag(L10n.text("jam.member.you"), highlighted: false) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel([member.name ?? L10n.text("jam.member.guest"),
                                         member.isHost ? L10n.text("jam.member.host") : (member.isMe ? L10n.text("jam.member.you") : "")]
                        .filter { !$0.isEmpty }.joined(separator: ", "))
                }
                if snapshot.members.count > shown.count {
                    Text(L10n.text("jam.members.more", args: [String(snapshot.members.count - shown.count)]))
                        .font(.system(size: 11)).foregroundStyle(palette.tertiary)
                }
            }
        }
    }

    // MARK: Sync settings

    private var syncSection: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                caption(L10n.text("jam.sync.title"))
                if snapshot.stage == .live {
                    JamOffsetControl(title: L10n.text("jam.sync.fine"), hint: snapshot.version == nil ? L10n.text("jam.sync.fineUnavailable") : L10n.text("jam.sync.fineHint"),
                                     value: snapshot.nudgeMs, enabled: snapshot.version != nil, steps: [10, 50], onChange: actions.setNudge)
                }
                JamOffsetControl(title: L10n.text("jam.sync.global"), hint: L10n.text("jam.sync.globalHint"),
                                 value: snapshot.globalOffsetMs, enabled: true, steps: [10, 50], onChange: actions.setGlobalOffset)
            }
        }
    }

    // MARK: Pieces

    private func card<Content: View>(padding: CGFloat = 12, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.border, lineWidth: AppTheme.cardBorderWidth))
    }

    private func banner(symbol: String, tint: Color, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.primary)
                Text(message).font(.system(size: 12)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 0.75))
        .accessibilityElement(children: .combine)
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(palette.tertiary)
    }

    private func trackText(title: String, artists: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.primary).lineLimit(1).truncationMode(.tail)
            if !artists.isEmpty {
                Text(verbatim: artists).font(.system(size: 12)).foregroundStyle(palette.secondary).lineLimit(1).truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(artists.isEmpty ? title : "\(title) · \(artists)")
    }

    private func durationText(_ value: String) -> some View {
        Text(verbatim: value).font(.system(size: 11).monospacedDigit()).foregroundStyle(palette.tertiary).fixedSize()
    }

    private var videoTag: some View {
        Text(L10n.text("jam.tag.video")).font(.system(size: 9, weight: .bold)).tracking(0.4).foregroundStyle(palette.secondary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(palette.border.opacity(2), lineWidth: 0.75))
            .fixedSize()
    }

    private func memberTag(_ text: String, highlighted: Bool) -> some View {
        Text(verbatim: text).font(.system(size: 10, weight: .semibold))
            .foregroundStyle(highlighted ? Color.white : palette.secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(highlighted ? Color.sidebAccent.opacity(0.85) : palette.card))
            .fixedSize()
    }

    private func artwork(_ url: URL?, size: CGFloat) -> some View {
        Group {
            if let url {
                CachedAsyncImage(url: url, targetSize: CGSize(width: size * 2, height: size * 2)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { palette.card }
            } else {
                palette.card.overlay(Image(systemName: "music.note").foregroundStyle(palette.tertiary))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Cancel button under the connecting card.
private struct CancelRow: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        VStack(spacing: 12) {
            content
            Button(action: action) {
                SideBControlLabel(title: L10n.text("jam.cancel")).frame(maxWidth: .infinity)
            }
            .buttonStyle(SideBControlStyle(size: .utility))
        }
    }
}

/// One selectable YouTube Music version.
private struct JamVersionRow: View {
    let version: JamPanelVersion
    let isCurrent: Bool
    let choose: () -> Void
    @Environment(\.jamPalette) private var palette
    @State private var hovered = false

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 9) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14)).foregroundStyle(isCurrent ? Color.sidebAccentHighlight : palette.tertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: version.title).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.primary).lineLimit(1)
                    Text(verbatim: version.artists).font(.system(size: 11)).foregroundStyle(palette.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if version.isVideo {
                    Text(L10n.text("jam.tag.video")).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(palette.border.opacity(2), lineWidth: 0.75))
                }
                if let duration = version.duration {
                    Text(verbatim: duration).font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(version.warnsAboutDuration ? Color.orange : palette.tertiary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isCurrent ? Color.sidebAccent.opacity(0.18) : (hovered ? palette.card : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(version.title), \(version.artists)")
        .accessibilityValue(isCurrent ? L10n.text("jam.versions.current") : "")
        .accessibilityHint(isCurrent ? "" : L10n.text("jam.versions.use"))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Millisecond offset with step buttons and a reset.
private struct JamOffsetControl: View {
    let title: String
    let hint: String
    let value: Double
    let enabled: Bool
    let steps: [Double]
    let onChange: (Double) -> Void
    @Environment(\.jamPalette) private var palette
    private static let limit = 5000.0

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(verbatim: title).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.primary)
                Spacer()
                Button(L10n.text("jam.sync.reset")) { onChange(0) }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.sidebAccentHighlight)
                    .disabled(!enabled || value == 0).opacity(enabled && value != 0 ? 1 : 0.4)
            }
            HStack(spacing: 5) {
                ForEach(steps.reversed(), id: \.self) { step in stepButton(-step) }
                Text(L10n.text("jam.sync.value", args: [Self.format(value)]))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(palette.primary)
                    .frame(maxWidth: .infinity)
                ForEach(steps, id: \.self) { step in stepButton(step) }
            }
            Text(verbatim: hint).font(.system(size: 11)).foregroundStyle(palette.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
    }

    private func stepButton(_ step: Double) -> some View {
        let label = (step > 0 ? "+" : "−") + String(Int(abs(step)))
        return Button { onChange(max(-Self.limit, min(Self.limit, value + step))) } label: {
            Text(verbatim: label).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(palette.primary)
                .frame(width: 36, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.card))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.border, lineWidth: 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text(step > 0 ? "jam.sync.increase" : "jam.sync.decrease", args: [String(Int(abs(step)))]))
    }

    private static func format(_ value: Double) -> String { value > 0 ? "+\(Int(value))" : "\(Int(value))" }
}

/// One incoming active Spotify Jam invitation row inside the Connections popover / fullscreen panel.
private struct JamInviteRow: View {
    let invite: JamPanelInvite
    let onJoin: () -> Void
    let onDismiss: () -> Void
    @Environment(\.jamPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isJoinHovered = false
    @State private var isDismissHovered = false

    private var titleText: String {
        if let name = invite.senderDisplayName {
            return L10n.text("jam.invites.from", args: [name])
        }
        return L10n.text("jam.invites.fromUnknown")
    }

    private var subtitleText: String {
        if let count = invite.participantCount, count > 0 {
            return count == 1
                ? L10n.text("jam.invites.participants.one")
                : L10n.text("jam.invites.participants.many", args: [String(count)])
        }
        return L10n.text("jam.invite.banner.subtitle")
    }

    var body: some View {
        HStack(spacing: 10) {
            JamAvatarView(name: invite.senderDisplayName, imageURL: invite.senderImageURL, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: titleText)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: subtitleText)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Button(action: onJoin) {
                    Text(verbatim: L10n.text("jam.invite.join"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            Capsule()
                                .fill(Color.sidebAccent.opacity(isJoinHovered ? 1 : 0.92))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.sidebAccentHighlight.opacity(0.75), lineWidth: 0.75)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { isJoinHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isJoinHovered)
                .accessibilityLabel("\(L10n.text("jam.invite.join")), \(titleText)")

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isDismissHovered ? palette.primary : palette.tertiary)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(isDismissHovered ? palette.card : .clear)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { isDismissHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isDismissHovered)
                .help(L10n.text("jam.invite.dismiss"))
                .accessibilityLabel("\(L10n.text("jam.invite.dismiss")), \(titleText)")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.border, lineWidth: 0.75))
    }
}

private struct JamPaletteKey: EnvironmentKey { static let defaultValue = JamPalette.popover }
extension EnvironmentValues {
    var jamPalette: JamPalette {
        get { self[JamPaletteKey.self] }
        set { self[JamPaletteKey.self] = newValue }
    }
}
