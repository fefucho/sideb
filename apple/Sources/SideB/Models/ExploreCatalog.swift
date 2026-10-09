import Foundation

enum ExploreRoute: Hashable {
    case discover, releases, charts, genres, moods
    case category(String)
    case chartCountry(String)

    static let tabs: [Self] = [.discover, .releases, .charts, .genres, .moods]

    var title: String {
        switch self {
        case .discover: return L10n.text("explore.route.discover")
        case .releases: return L10n.text("explore.route.releases")
        case .charts: return L10n.text("explore.route.charts")
        case .chartCountry(let code): return L10n.text("explore.route.chart_country", args: [ExploreChartRegion.name(code)])
        case .genres: return L10n.text("explore.route.genres")
        case .moods: return L10n.text("explore.route.moods")
        case .category(let id): return ExploreCategory.find(id)?.displayTitle ?? L10n.text("home.collection.playlists")
        }
    }

    var symbol: String {
        switch self {
        case .discover: return "safari"
        case .releases: return "opticaldisc"
        case .charts: return "chart.line.uptrend.xyaxis"
        case .chartCountry: return "globe"
        case .genres: return "music.note.list"
        case .moods: return "sun.horizon"
        case .category(let id): return ExploreCategory.find(id)?.symbol ?? "music.note.list"
        }
    }

    var selectedTab: Self {
        if case .chartCountry = self { return .charts }
        if case .category(let id) = self {
            return ExploreCategory.moods.contains(where: { $0.id == id }) ? .moods : .genres
        }
        return self
    }

    var source: ExploreSource? {
        switch self {
        case .discover, .releases: return .browse("FEmusic_new_releases_albums")
        case .charts: return nil
        case .chartCountry(let code): return .charts(code)
        case .category(let id): return ExploreCategory.find(id).map { .playlists($0.query) }
        case .genres, .moods: return nil
        }
    }
}

enum ExploreSource: Hashable {
    case browse(String)
    case playlists(String)
    case charts(String)
}

enum ExploreChartRegion {
    static func name(_ code: String) -> String {
        code == "ZZ" ? L10n.text("explore.region.global") : (Locale(identifier: L10n.language.rawValue).localizedString(forRegionCode: code) ?? code)
    }
}

/// Initial Side B categories. Playlist results come from the provider's search,
/// rather than pretending these are YouTube's editorial category endpoints.
struct ExploreCategory: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let hue: Double
    let query: String

    var displayTitle: String { L10n.text("explore.category.\(id).title") }
    var displaySubtitle: String { L10n.text("explore.category.\(id).subtitle") }

    static func find(_ id: String) -> Self? { (genres + moods).first { $0.id == id } }

    static let moods: [Self] = [
        .init(id: "focus", title: "Concentración", subtitle: "Menos ruido, más foco", symbol: "scope", hue: 0.57, query: "música para concentrarse"),
        .init(id: "relax", title: "Relajación", subtitle: "Bajá un cambio", symbol: "water.waves", hue: 0.47, query: "música relajante"),
        .init(id: "workout", title: "Entrenar", subtitle: "Un poco más de energía", symbol: "figure.run", hue: 0.03, query: "música para entrenar"),
        .init(id: "party", title: "Fiesta", subtitle: "Que siga la noche", symbol: "sparkles", hue: 0.88, query: "música fiesta"),
        .init(id: "sleep", title: "Dormir", subtitle: "Hasta mañana", symbol: "moon.stars", hue: 0.65, query: "música para dormir"),
        .init(id: "road", title: "En ruta", subtitle: "El viaje también se escucha", symbol: "car.side", hue: 0.09, query: "música para viajar"),
        .init(id: "good-mood", title: "Buen día", subtitle: "Para sentirse bien", symbol: "sun.max", hue: 0.13, query: "música para sentirse bien"),
        .init(id: "romance", title: "Romance", subtitle: "Para compartir", symbol: "heart", hue: 0.96, query: "canciones románticas"),
    ]

    static let genres: [Self] = [
        .init(id: "pop", title: "Pop", subtitle: "Melodías que se quedan", symbol: "mic", hue: 0.91, query: "pop hits"),
        .init(id: "rock", title: "Rock", subtitle: "Guitarras al frente", symbol: "guitars", hue: 0.02, query: "rock"),
        .init(id: "latin", title: "Latina", subtitle: "Ritmos de acá", symbol: "sun.max", hue: 0.08, query: "éxitos latinos"),
        .init(id: "hiphop", title: "Hip-hop", subtitle: "Beats y palabras", symbol: "waveform", hue: 0.12, query: "hip hop"),
        .init(id: "electronic", title: "Electrónica", subtitle: "Seguí el pulso", symbol: "slider.horizontal.3", hue: 0.61, query: "electrónica dance"),
        .init(id: "indie", title: "Indie y alternativa", subtitle: "Otros caminos", symbol: "radio", hue: 0.43, query: "indie alternativa"),
        .init(id: "rnb", title: "R&B y soul", subtitle: "Con alma", symbol: "hifispeaker", hue: 0.76, query: "R&B soul"),
        .init(id: "jazz", title: "Jazz", subtitle: "Espacio para improvisar", symbol: "pianokeys", hue: 0.55, query: "jazz"),
        .init(id: "cumbia", title: "Cumbia", subtitle: "Siempre hay una más", symbol: "music.note", hue: 0.31, query: "cumbia"),
        .init(id: "reggaeton", title: "Reggaetón", subtitle: "Para mover el día", symbol: "flame", hue: 0.04, query: "reggaeton"),
        .init(id: "classical", title: "Clásica", subtitle: "Sin apuro", symbol: "music.quarternote.3", hue: 0.11, query: "música clásica"),
        .init(id: "metal", title: "Metal", subtitle: "Subí el volumen", symbol: "bolt", hue: 0.69, query: "metal"),
        .init(id: "kpop", title: "K-Pop", subtitle: "Todo el color", symbol: "star", hue: 0.83, query: "k pop"),
        .init(id: "acoustic", title: "Folk y acústica", subtitle: "Más cerca", symbol: "guitars", hue: 0.28, query: "folk acústico"),
        .init(id: "reggae", title: "Reggae", subtitle: "A otro ritmo", symbol: "leaf", hue: 0.38, query: "reggae"),
        .init(id: "soundtracks", title: "Bandas sonoras", subtitle: "Música de película", symbol: "film", hue: 0.59, query: "bandas sonoras"),
    ]
}
