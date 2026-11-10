import Foundation

public enum PlaybackPresentation: Equatable { case bar, sidebar, fullscreen }
public enum PlaybackSidebarPanel: String, CaseIterable, Identifiable {
    case lyrics, artwork, queue
    public var id: String { rawValue }
    var title: String {
        L10n.text(self == .lyrics ? "fullscreen.lyrics" : self == .queue ? "queue.title" : "playbackSidebar.nowPlaying")
    }
    var icon: String { self == .lyrics ? "quote.bubble" : self == .queue ? "list.bullet" : "music.note" }
}

public enum SidebarBottomContent: String, CaseIterable, Identifiable {
    case queue = "queue"
    case lyrics = "lyrics"

    public var id: String { rawValue }

    public static func resolve(_ raw: String?) -> Self {
        Self(rawValue: raw ?? "") ?? .queue
    }

    public var labelKey: String {
        switch self {
        case .queue:
            return "settings.sidebarBottomContent.queue"
        case .lyrics:
            return "settings.sidebarBottomContent.lyrics"
        }
    }
}

enum SidebarBottomContentPreferences {
    static let preferenceKey = "sideb.sidebar.bottomContent.v1"

    static func selection(in defaults: UserDefaults = HomeAppearance.preferences) -> SidebarBottomContent {
        SidebarBottomContent.resolve(defaults.string(forKey: preferenceKey))
    }
}

/// UI state only. Playback occurrence, clock and queue remain authoritative in the player.
public struct PlaybackPresentationState: Equatable {
    public private(set) var mode: PlaybackPresentation = .bar
    private var fullscreenOrigin: PlaybackPresentation = .bar
    public init() {}
    public mutating func presentSidebar() { mode = .sidebar }
    public mutating func closeSidebar() { if mode == .sidebar { mode = .bar } }
    public mutating func setFullscreen(_ presented: Bool) {
        if presented {
            guard mode != .fullscreen else { return }
            fullscreenOrigin = mode
            mode = .fullscreen
        } else if mode == .fullscreen {
            mode = fullscreenOrigin
        }
    }
}

struct PlaybackSidebarLayout {
    static let width: CGFloat = 380
    static let inset: CGFloat = 6
    static let reserve = width + inset * 2
    static let metadataHeight: CGFloat = 68
    static let metadataSpacing: CGFloat = 16
    static let footerHeight: CGFloat = 284
    static let lyricsFontSize: CGFloat = 28
    static let lyricsPreviewFontSize: CGFloat = 26
    static func showsUpcoming(for panelHeight: CGFloat, panel: PlaybackSidebarPanel, isPortrait: Bool = false) -> Bool {
        panel == .artwork && !isPortrait && panelHeight >= 840
    }
    static func footerHeight(for panelHeight: CGFloat, panel: PlaybackSidebarPanel = .lyrics, isPortrait: Bool = false, width: CGFloat = Self.width) -> CGFloat {
        let controls = min(240, max(200, panelHeight * 0.24))
        let minimum = controls + (panel == .artwork ? 0 : metadataHeight + metadataSpacing)
            + (showsUpcoming(for: panelHeight, panel: panel, isPortrait: isPortrait) ? 134 : 0)
        guard panel == .artwork, !isPortrait else { return minimum }
        let idealHero = 58 + 12 + max(0, width - 40) + metadataSpacing + metadataHeight
        return max(minimum, panelHeight - idealHero)
    }
    static func contentReserve(windowWidth: CGFloat, leftReserve: CGFloat, presented: Bool) -> CGFloat {
        presented && windowWidth - leftReserve - reserve >= 480 ? reserve : 0
    }
    static func progressToTransportSpacing(for panelHeight: CGFloat) -> CGFloat {
        let controls = min(240, max(200, panelHeight * 0.24))
        return 10 + max(0, controls - 194) / 4
    }
}
