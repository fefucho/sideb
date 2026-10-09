import AppKit
import SwiftUI

/// Shared cover interactions. Navigation, playback and menus are sibling controls.
struct MediaArtworkControls<Artwork: View>: View {
    let isCollection: Bool
    var isActive: Bool = false
    var isPlaying: Bool = false
    var isLoading: Bool = false
    var showsIndicator: Bool = false
    let accessibilityTitle: String
    let onOpen: () -> Void
    let onPlay: () -> Void
    var menuProvider: (() -> NSMenu?)? = nil
    @ViewBuilder let artwork: () -> Artwork

    private enum Control: Hashable { case cover, play, menu }
    @FocusState private var focused: Control?
    @State private var hovered = false
    @State private var playHovered = false
    @State private var menuLocation = MediaMenuLocation()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.mediaCardIsHovered) private var cardHovered
    @Environment(\.mediaCardIsFocused) private var cardFocused

    private var revealsControls: Bool { hovered || cardHovered || cardFocused || focused != nil || isLoading }
    private var playbackLabel: String {
        L10n.text(isActive && isPlaying ? "player.pauseNamedTrack" : "player.playNamedTrack", args: [accessibilityTitle])
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 64
            let playSize: CGFloat = compact ? 16 : 32
            let menuSize: CGFloat = compact ? 12 : 24
            ZStack {
                Button(action: onOpen) { artwork().frame(maxWidth: .infinity, maxHeight: .infinity) }
                    .buttonStyle(.plain)
                    .focused($focused, equals: .cover)
                    .accessibilityLabel(isCollection ? L10n.text("detail.openNamed", args: [accessibilityTitle]) : playbackLabel)

                if isActive && showsIndicator && !revealsControls {
                    SharedMediaPlayingIndicator(isPlaying: isPlaying, compact: compact, reduceMotion: reduceMotion)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                Button(action: onPlay) {
                    Group {
                        if isLoading { ProgressView().controlSize(.small).scaleEffect(compact ? 0.6 : 0.8) }
                        else { Image(systemName: isActive && isPlaying ? "pause.fill" : "play.fill") }
                    }
                    .font(.system(size: compact ? 9 : 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: playSize, height: playSize)
                    .background(isCollection && playHovered ? AppTheme.accent : Color.black.opacity(0.62), in: Circle())
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .focused($focused, equals: .play)
                .onHover { playHovered = $0 }
                .accessibilityLabel(playbackLabel)
                .opacity(revealsControls ? 1 : 0)
                .allowsHitTesting(revealsControls)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: isCollection ? .bottomTrailing : .center)
                .padding(isCollection ? (compact ? 2 : 8) : 0)

                if let menuProvider {
                    Button {
                        guard let menu = menuProvider() else { return }
                        menuLocation.show(menu)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: compact ? 8 : 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: menuSize, height: menuSize)
                            .background(Color.black.opacity(0.62), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focused($focused, equals: .menu)
                    .accessibilityLabel(L10n.text("common.moreOptionsFor", args: [accessibilityTitle]))
                    .background(MediaMenuAnchor(location: menuLocation))
                    .opacity(revealsControls ? 1 : 0)
                    .allowsHitTesting(revealsControls)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(compact ? 0 : 6)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .background(MediaControlFocusBridge(isFocused: focused != nil))
            .overlay {
                if let menuProvider { NativeContextMenuOverlay(menuProvider: menuProvider) }
            }
        }
    }
}

private struct MediaCardHoverKey: EnvironmentKey { static let defaultValue = false }
private struct MediaCardFocusKey: EnvironmentKey { static let defaultValue = false }
private struct MediaCardFocusReporterKey: EnvironmentKey {
    static let defaultValue: ((UUID, Bool) -> Void)? = nil
}
extension EnvironmentValues {
    var mediaCardIsHovered: Bool {
        get { self[MediaCardHoverKey.self] }
        set { self[MediaCardHoverKey.self] = newValue }
    }
    var mediaCardIsFocused: Bool {
        get { self[MediaCardFocusKey.self] }
        set { self[MediaCardFocusKey.self] = newValue }
    }
    var mediaCardFocusReporter: ((UUID, Bool) -> Void)? {
        get { self[MediaCardFocusReporterKey.self] }
        set { self[MediaCardFocusReporterKey.self] = newValue }
    }
}

private struct MediaCardSurface: ViewModifier {
    @State private var hovered = false
    @State private var focusedControls: Set<UUID> = []
    func body(content: Content) -> some View {
        content.environment(\.mediaCardIsHovered, hovered)
            .environment(\.mediaCardIsFocused, !focusedControls.isEmpty)
            .environment(\.mediaCardFocusReporter) { id, isFocused in
                if isFocused { focusedControls.insert(id) }
                else { focusedControls.remove(id) }
            }
            .contentShape(Rectangle()).onHover { hovered = $0 }
    }
}

extension View {
    func mediaCardSurface() -> some View { modifier(MediaCardSurface()) }
    func mediaCardFocusControl() -> some View { modifier(MediaCardFocusControl()) }
    func mediaCardActivation(label: String = L10n.text("player.play"), action: @escaping () -> Void) -> some View {
        modifier(MediaCardActivation(label: label, action: action))
    }
}

/// Credits and titles stay independent buttons while sharing focus visibility with their card.
private struct MediaCardFocusControl: ViewModifier {
    @State private var identity = UUID()
    @FocusState private var focused: Bool
    @Environment(\.mediaCardFocusReporter) private var reportFocus
    func body(content: Content) -> some View {
        content.focused($focused)
            .onChange(of: focused) { _, value in reportFocus?(identity, value) }
            .onDisappear { reportFocus?(identity, false) }
            .background(MediaControlFocusBridge(isFocused: focused))
    }
}

/// The background receives empty-space clicks; foreground links/buttons consume their own action.
private struct MediaCardActivation: ViewModifier {
    let label: String
    let action: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.mediaCardIsFocused) private var cardFocused

    func body(content: Content) -> some View {
        content.environment(\.mediaCardIsFocused, focused || cardFocused)
            .background {
                Button(action: action) {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain).focused($focused).accessibilityLabel(label)
                .background(MediaControlFocusBridge(isFocused: focused))
            }
    }
}

struct SharedMediaPlayingIndicator: NSViewRepresentable {
    let isPlaying: Bool
    var compact = false
    var reduceMotion = false

    func makeNSView(context: Context) -> HomeEqualizerOverlayView { HomeEqualizerOverlayView() }
    func updateNSView(_ view: HomeEqualizerOverlayView, context: Context) {
        view.updateStyle(compact: compact)
        view.setCornerRadius(compact ? AppTheme.artworkThumbnailRadius : AppTheme.artworkCardRadius)
        view.setMotionEnabled(!reduceMotion)
        view.startAnimating()
        if !isPlaying { view.pauseAnimation() }
    }
    static func dismantleNSView(_ view: HomeEqualizerOverlayView, coordinator: ()) { view.stopAnimating() }
}

@MainActor private final class MediaMenuLocation {
    weak var anchor: NSView?
    func show(_ menu: NSMenu) {
        guard let anchor, anchor.window != nil else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: anchor.bounds.maxX, y: anchor.bounds.maxY), in: anchor)
    }
}

private struct MediaMenuAnchor: NSViewRepresentable {
    let location: MediaMenuLocation
    func makeNSView(context: Context) -> NSView {
        let view = MediaPassthroughView()
        location.anchor = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { location.anchor = view }
}

private final class MediaPassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct MediaControlFocusBridge: NSViewRepresentable {
    let isFocused: Bool
    func makeNSView(context: Context) -> PlaybackSpaceFocusView { PlaybackSpaceFocusView() }
    func updateNSView(_ view: PlaybackSpaceFocusView, context: Context) { view.isControlFocused = isFocused }
    static func dismantleNSView(_ view: PlaybackSpaceFocusView, coordinator: ()) { view.clearScope() }
}
