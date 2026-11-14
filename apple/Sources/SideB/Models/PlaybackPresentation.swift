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
    /// Ancho por defecto (y ideal) del panel; el real es redimensionable entre `minimumWidth` y `maximumWidth`.
    static let width: CGFloat = 380
    static let minimumWidth: CGFloat = 340
    static let maximumWidth: CGFloat = 520
    static let keyboardStep: CGFloat = 16
    static let widthPreferenceKey = "sideb.playbackSidebar.width.v1"
    /// Pagina util minima que debe quedar junto al panel (si no, el panel se superpone como antes).
    static let minimumContentWidth: CGFloat = 480
    static let inset: CGFloat = 6
    static let reserve = width + inset * 2
    static func reserve(forWidth width: CGFloat) -> CGFloat { width + inset * 2 }

    static func clampWidth(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return width }
        return min(maximumWidth, max(minimumWidth, value))
    }
    static func storedWidth(in defaults: UserDefaults) -> CGFloat {
        guard defaults.object(forKey: widthPreferenceKey) != nil else { return width }
        return clampWidth(CGFloat(defaults.double(forKey: widthPreferenceKey)))
    }
    /// Ancho maximo que cabe dejando `minimumContentWidth` de pagina; nunca baja de `minimumWidth` (entonces se superpone).
    static func availableWidth(windowWidth: CGFloat, leftReserve: CGFloat) -> CGFloat {
        max(minimumWidth, min(maximumWidth, windowWidth - leftReserve - inset * 2 - minimumContentWidth))
    }
    /// Ancho efectivo: el guardado, reducido si la ventana es angosta (el valor guardado no se pierde).
    static func effectiveWidth(stored: CGFloat, windowWidth: CGFloat, leftReserve: CGFloat) -> CGFloat {
        min(clampWidth(stored), availableWidth(windowWidth: windowWidth, leftReserve: leftReserve))
    }
    static let metadataHeight: CGFloat = 68
    /// Header band that stays above the cover (the cover starts just inside it).
    static let coverTop: CGFloat = 56
    /// The cover uses almost the full panel width; text and controls keep `contentInset`.
    static let coverInset: CGFloat = 4
    static let contentInset: CGFloat = 20
    /// Single vertical rhythm of the artwork panel (cover → title, transport → lyrics → volume → edge),
    /// measured between visible glyph/shape edges rather than between layout frames.
    static let gap: CGFloat = 23
    /// Progress bar spacing, measured from the bar itself (not from the time labels around it).
    static let progressGap: CGFloat = 28
    /// Cover → title text; title glyphs sit ~6 pt below the metadata frame top.
    static let metadataSpacing: CGFloat = gap - 6
    /// Lyrics/queue footers keep their own metadata spacing.
    static let footerMetadataSpacing: CGFloat = 16
    /// Metadata frame leaves ~20 pt under the artist line; the bar is 4.5 pt below its view top.
    static let progressTopOffset: CGFloat = progressGap - 20 - 4.5
    /// Time labels (22.5 pt below the bar) leave the bar-bottom → play-top distance at `progressGap + 1`.
    static let progressToTransportGap: CGFloat = 6.5
    /// Volume glyphs sit 8 pt inside their 32 pt row.
    static let volumeRowSlack: CGFloat = 8
    static let footerHeight: CGFloat = 284
    static let lyricsFontSize: CGFloat = 28
    static let lyricsPreviewFontSize: CGFloat = 26
    static func showsUpcoming(for panelHeight: CGFloat, panel: PlaybackSidebarPanel, isPortrait: Bool = false) -> Bool {
        panel == .artwork && !isPortrait && panelHeight >= 840
    }
    static func footerHeight(for panelHeight: CGFloat, panel: PlaybackSidebarPanel = .lyrics, isPortrait: Bool = false, width: CGFloat = Self.width) -> CGFloat {
        let controls = min(240, max(200, panelHeight * 0.24))
        let minimum = controls + (panel == .artwork ? 0 : metadataHeight + footerMetadataSpacing)
            + (showsUpcoming(for: panelHeight, panel: panel, isPortrait: isPortrait) ? 134 : 0)
        guard panel == .artwork, !isPortrait else { return minimum }
        let idealHero = coverTop + max(0, width - coverInset * 2) + metadataSpacing + metadataHeight
        return max(minimum, panelHeight - idealHero)
    }
    /// Reserva de contenido: con `panelWidth` omitido usa el ancho por defecto. Si ni el ancho minimo deja
    /// `minimumContentWidth` de pagina, no se reserva (el panel se superpone).
    static func contentReserve(windowWidth: CGFloat, leftReserve: CGFloat, presented: Bool, panelWidth: CGFloat = Self.width) -> CGFloat {
        let reserve = reserve(forWidth: panelWidth)
        return presented && windowWidth - leftReserve - reserve >= minimumContentWidth ? reserve : 0
    }
}
