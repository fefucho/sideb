import Foundation
import SideBCore

// MARK: - MenuIDNormalizer

/// Utilidad pura para normalizar y resolver identificadores de YouTube Music.
/// Evita prefijos duplicados como `RDAMPLVLRD...` y resuelve URLs canónicas.
public enum MenuIDNormalizer {
    
    /// Remueve el prefijo de navegación `VL` de listas de reproducción o radios si está presente.
    /// Ejemplo: `VLPL123` -> `PL123`, `VLRD456` -> `RD456`, `VLLM` -> `LM`.
    public static func canonicalPlaylistId(_ id: String) -> String {
        var clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("VL") {
            clean = String(clean.dropFirst(2))
        }
        return clean
    }

    /// Normaliza cualquier identificador eliminando espacios y prefijos de navegación si corresponde.
    public static func normalize(_ id: String) -> String {
        return canonicalPlaylistId(id)
    }

    /// Determina si un identificador corresponde a un mix dinámico o radio continua.
    /// Un mix dinámico comienza por `RD` (o `VLRD`), independientemente del título visible.
    public static func isDynamicRadioMix(id: String) -> Bool {
        let clean = canonicalPlaylistId(id)
        return clean.hasPrefix("RD")
    }

    /// Resuelve el ID de radio de una colección (álbum, playlist, artista) sin generar prefijos dobles.
    public static func radioPlaylistId(
        forCollectionId id: String,
        prefix: String = "RDAMPL",
        directRadioId: String? = nil
    ) -> String {
        if let direct = directRadioId, !direct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return canonicalPlaylistId(direct)
        }
        let clean = canonicalPlaylistId(id)
        if clean.hasPrefix("RD") {
            return clean
        }
        return "\(prefix)\(clean)"
    }

    /// Genera la URL canónica para compartir una canción.
    public static func songShareURL(videoId: String) -> URL? {
        guard !videoId.isEmpty else { return nil }
        return URL(string: "https://music.youtube.com/watch?v=\(videoId)")
    }

    /// Genera la URL canónica para compartir un álbum o playlist.
    public static func collectionShareURL(id: String) -> URL? {
        let clean = canonicalPlaylistId(id)
        guard !clean.isEmpty else { return nil }
        return URL(string: "https://music.youtube.com/playlist?list=\(clean)")
    }

    /// Genera la URL canónica para compartir un artista o canal.
    public static func artistShareURL(channelId: String) -> URL? {
        let clean = channelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if clean.hasPrefix("UC") {
            return URL(string: "https://music.youtube.com/channel/\(clean)")
        } else {
            return URL(string: "https://music.youtube.com/browse/\(clean)")
        }
    }
}

// MARK: - MenuOrigin

/// Ubicación exacta desde donde se abre el menú contextual o el botón de elipsis.
public enum MenuOrigin: Equatable, Sendable {
    case home
    case search
    case searchSpotlight
    case album(browseId: String)
    case playlist(id: String)
    case artist(channelId: String)
    case library
    case history
    case queue(occurrenceIndex: Int)
    case nowPlaying
    case recommendations
    case sidebar
}

// MARK: - MenuTarget

/// Entidad exacta sobre la que actúa el menú.
public enum MenuTarget: Equatable, Sendable {
    case song(SongItemRecord)
    case album(
        browseId: String,
        playlistId: String?,
        title: String,
        artist: String?,
        artistId: String?,
        thumbnail: String?
    )
    case playlist(
        id: String,
        title: String,
        subtitle: String?,
        thumbnail: String?,
        isRadioMix: Bool
    )
    case radioMix(
        id: String,
        title: String,
        subtitle: String?,
        thumbnail: String?
    )
    case artist(
        channelId: String,
        name: String,
        thumbnail: String?,
        radioPlaylistId: String?
    )
}

// MARK: - TriStateStatus

/// Modela el conocimiento de un estado en el cliente (p. ej. en biblioteca o suscripción).
public enum TriStateStatus: Equatable, Sendable {
    case unknown
    case known(Bool)
    
    public var isTrue: Bool {
        if case .known(let val) = self { return val }
        return false
    }
}

// MARK: - MenuFacts

/// Hechos comprobados, permisos y callbacks requeridos para construir y ejecutar el menú.
@MainActor
public struct MenuFacts {
    public var isLoggedIn: Bool
    public var inLibrary: TriStateStatus
    public var isOwned: TriStateStatus
    public var sortEditable: Bool
    public var isSubscribed: TriStateStatus
    public var isCurrentPlayingTrack: Bool
    public var isLiked: Bool
    public var userPlaylists: [BrowseCardRecord]

    // Callbacks contextuales para mutaciones específicas
    public var onRemoveFromPlaylist: (@MainActor () -> Void)?
    public var onRemoveFromQueue: (@MainActor (Int) -> Void)?
    public var onEditPlaylist: (@MainActor () -> Void)?
    public var onDeletePlaylist: (@MainActor () -> Void)?
    public var onSortPlaylist: (@MainActor (String) -> Void)?

    public init(
        isLoggedIn: Bool = true,
        inLibrary: TriStateStatus = .unknown,
        isOwned: TriStateStatus = .unknown,
        sortEditable: Bool = false,
        isSubscribed: TriStateStatus = .unknown,
        isCurrentPlayingTrack: Bool = false,
        isLiked: Bool = false,
        userPlaylists: [BrowseCardRecord] = [],
        onRemoveFromPlaylist: (@MainActor () -> Void)? = nil,
        onRemoveFromQueue: (@MainActor (Int) -> Void)? = nil,
        onEditPlaylist: (@MainActor () -> Void)? = nil,
        onDeletePlaylist: (@MainActor () -> Void)? = nil,
        onSortPlaylist: (@MainActor (String) -> Void)? = nil
    ) {
        self.isLoggedIn = isLoggedIn
        self.inLibrary = inLibrary
        self.isOwned = isOwned
        self.sortEditable = sortEditable
        self.isSubscribed = isSubscribed
        self.isCurrentPlayingTrack = isCurrentPlayingTrack
        self.isLiked = isLiked
        self.userPlaylists = userPlaylists
        self.onRemoveFromPlaylist = onRemoveFromPlaylist
        self.onRemoveFromQueue = onRemoveFromQueue
        self.onEditPlaylist = onEditPlaylist
        self.onDeletePlaylist = onDeletePlaylist
        self.onSortPlaylist = onSortPlaylist
    }
}

// MARK: - MenuActionId

/// Identificador semántico de cada acción que puede figurar en un menú.
public enum MenuActionId: Equatable, Hashable, Sendable {
    // 1. Reproducción
    case play
    case shuffle
    case startMix
    case playNext
    case addToQueue

    // 2. Biblioteca, Me gusta y Playlists
    case toggleLike
    case toggleLibrary(inLibrary: Bool)
    case addToPlaylist(playlistId: String, title: String)
    case createPlaylistAndAdd
    case toggleSubscription(subscribed: Bool)

    // 3. Navegación
    case goToAlbum(browseId: String)
    case goToArtist(channelId: String)
    case goToPlaylist(id: String)

    // 4. Compartir
    case share

    // 5. Edición y Destructivas
    case editDetails
    case sort(value: String, title: String)
    case removeFromPlaylist
    case removeFromQueue(index: Int)
    case deletePlaylist
}

// MARK: - MenuActionItem

/// Elemento ejecutable dentro de una sección del menú.
public struct MenuActionItem: Identifiable, Sendable {
    public var id: MenuActionId
    public var title: String
    public var systemImage: String
    public var isDestructive: Bool
    public var isEnabled: Bool
    public var subitems: [MenuActionItem]?

    public init(
        id: MenuActionId,
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        subitems: [MenuActionItem]? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.isEnabled = isEnabled
        self.subitems = subitems
    }
}

// MARK: - MenuSection

/// Grupo ordenado de acciones con separador visual entre secciones presentes.
public struct MenuSection: Identifiable, Sendable {
    public enum SectionKind: String, Sendable {
        case playback
        case collection
        case navigation
        case share
        case destructive
    }

    public var kind: SectionKind
    public var items: [MenuActionItem]

    public var id: String { kind.rawValue }

    public init(kind: SectionKind, items: [MenuActionItem]) {
        self.kind = kind
        self.items = items
    }
}
