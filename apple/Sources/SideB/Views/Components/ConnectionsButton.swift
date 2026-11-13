import SwiftUI
import AVKit
import AppKit

// MARK: - Bar-side state

/// What the player surfaces need to know about a live Spotify Jam. Plain values so the
/// presentation rules can be tested without a running session.
struct ConnectionsJamState: Equatable {
    var isLive: Bool
    var hostName: String?
    var hostImageURL: URL?
    var canControl: Bool

    /// Set by tests and the visual harness only.
    nonisolated(unsafe) static var testOverride: ConnectionsJamState?

    static let inactive = ConnectionsJamState(isLive: false, hostName: nil, hostImageURL: nil, canControl: false)

    @MainActor
    static func current(_ jam: JamSessionController? = nil) -> ConnectionsJamState {
        if let override = testOverride { return override }
        let jam = jam ?? JamSessionController.shared
        guard jam.phase == .live else { return .inactive }
        let host = jam.members.first(where: \.isHost)
        let name = host?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ConnectionsJamState(
            isLive: true,
            hostName: (name?.isEmpty ?? true) ? nil : name,
            hostImageURL: host?.imageUrl.flatMap { URL(string: $0) },
            canControl: jam.canControl
        )
    }

    var contextLabel: String {
        hostName.map { L10n.text("connections.bar.jamContext", args: [$0]) } ?? L10n.text("connections.bar.jamContextUnknownHost")
    }

    var buttonAccessibilityLabel: String {
        hostName.map { L10n.text("connections.activeJam", args: [$0]) } ?? L10n.text("connections.activeJamUnknownHost")
    }

    // Transport rules while a Jam is live.
    var shuffleRepeatEnabled: Bool { !isLive }
    var nextPreviousSeekEnabled: Bool { !isLive || canControl }

    /// Tooltip for a control forwarded to the Jam, or `nil` outside a Jam.
    func sharedControlHelp(_ label: String) -> String? {
        guard isLive else { return nil }
        return canControl
            ? L10n.text("connections.jam.sharedControl", args: [label])
            : L10n.text("connections.jam.noControl", args: [label])
    }
}

// MARK: - AirPlay route picker trigger

/// Keeps a real `AVRoutePickerView` (bound to the app's AVPlayer, FIX-039) in the bar so the
/// popover can ask for the system route menu without hosting the picker inside the popover,
/// whose transient window would be closed by the system menu taking key focus.
@MainActor
final class AirPlayRoutePresenter {
    fileprivate weak var picker: AVRoutePickerView?

    /// Clicks the picker's inner button; falls back to the Sound settings pane.
    func present() {
        if let picker, let button = Self.routeButton(in: picker) {
            button.performClick(nil)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func routeButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton { return button }
        for sub in view.subviews { if let found = routeButton(in: sub) { return found } }
        return nil
    }
}

private struct AirPlayRouteAnchor: NSViewRepresentable {
    let presenter: AirPlayRoutePresenter

    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        picker.player = AudioPlayerService.shared.avPlayer
        presenter.picker = picker
        return picker
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        nsView.player = AudioPlayerService.shared.avPlayer
        presenter.picker = nsView
    }
}

// MARK: - Button

/// Replaces the bare AirPlay button: same 32x32 footprint, opens a list of connection sections.
struct ConnectionsButton: View {
    var player: PlayerViewModel
    @State private var isPresented = false
    @State private var presenter = AirPlayRoutePresenter()
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func glyph(live: Bool) -> String { live ? "person.2.wave.2.fill" : "person.2.wave.2" }

    var body: some View {
        let jam = ConnectionsJamState.current()
        Button {
            isPresented.toggle()
        } label: {
            ZStack {
                Image(systemName: Self.glyph(live: jam.isLive))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(jam.isLive ? Color.sidebAccentHighlight : Color.white.opacity(isHovering || isPresented ? 0.95 : 0.70))
                    .frame(width: 32, height: 32)
                if jam.isLive {
                    // Small badge on the bottom-trailing corner, separated from the glyph by a ring
                    // in the bar colour so it reads as a notification dot, not part of the icon.
                    ConnectionsHostBadge(imageURL: jam.hostImageURL, name: jam.hostName, diameter: 9)
                        .padding(1.5)
                        .background(Circle().fill(Color(white: 0.10)))
                        .offset(x: 10, y: 10)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: jam.isLive)
        .help(jam.hostName.map { L10n.text("connections.activeJam", args: [$0]) } ?? L10n.text("connections.help"))
        .accessibilityLabel(jam.isLive ? jam.buttonAccessibilityLabel : L10n.text("connections.title"))
        .accessibilityHint(L10n.text("connections.help"))
        .background {
            // Real route picker kept out of the way; the popover row triggers it.
            AirPlayRouteAnchor(presenter: presenter)
                .frame(width: 32, height: 32)
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ConnectionsPopoverContent(player: player) {
                isPresented = false
                // Let the popover finish closing so the system menu is not dismissed with it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { presenter.present() }
            }
        }
        .frame(width: 32, height: 32)
    }
}

/// The host's avatar as a small badge (falls back to the initial).
struct ConnectionsHostBadge: View {
    var imageURL: URL?
    var name: String?
    var diameter: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().fill(Color.sidebAccent)
            if let imageURL {
                CachedAsyncImage(url: imageURL, targetSize: CGSize(width: diameter * 2, height: diameter * 2)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { initial }
                .clipShape(Circle())
            } else {
                initial
            }
        }
        .frame(width: diameter, height: diameter)
                .accessibilityHidden(true)
    }

    private var initial: some View {
        Text(String((name ?? "J").prefix(1)).uppercased())
            .font(.system(size: diameter * 0.58, weight: .bold))
            .foregroundStyle(.white)
    }
}

// MARK: - Popover content

/// A section of the Connections popover. A third one (Side B's own listen-together) is added by
/// appending a case here.
enum ConnectionsSection: CaseIterable, Identifiable {
    case audioOutput, spotifyJam
    var id: Self { self }
}

struct ConnectionsPopoverContent: View {
    var player: PlayerViewModel
    var onChooseAudioOutput: () -> Void

    static let width: CGFloat = 340

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(ConnectionsSection.allCases.enumerated()), id: \.element) { index, section in
                if index > 0 { Divider().padding(.horizontal, 14) }
                switch section {
                case .audioOutput:
                    AudioOutputRow(action: onChooseAudioOutput)
                case .spotifyJam:
                    JamPanelView(player: player, style: .popover)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: Self.width)
    }
}

private struct AudioOutputRow: View {
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "airplayaudio")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.text("connections.audioOutput.title")).font(.system(size: 13, weight: .semibold))
                    Text(L10n.text("connections.audioOutput.subtitle")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(isHovering ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
        .help(L10n.text("connections.audioOutput.help"))
        .accessibilityLabel(L10n.text("connections.audioOutput.title"))
        .accessibilityHint(L10n.text("connections.audioOutput.subtitle"))
    }
}
