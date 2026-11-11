import SwiftUI
import AppKit
import SideBCore

struct HomeFeaturedLayout {
    static let horizontalInset: CGFloat = 28
    static let sectionGap: CGFloat = 30
    static let headerHeight: CGFloat = 38
    static let contentGap: CGFloat = 8
    /// Sólo la hoja «Ver todo»: conserva la tarjeta anterior, de ancho fijo y texto debajo.
    static let albumCardWidth: CGFloat = 176
    /// Artwork stays square; below it: title, creator and one detail line.
    static let albumTextHeight: CGFloat = 64
    /// Air between the songs mosaic and the next feed section when there are no collections
    /// (con colecciones, el aire de la sombra bajo la tarjeta ya deja 48 pt).
    static let bottomGap: CGFloat = 20
    let songWidth: CGFloat
    /// Ancho de la tarjeta de colección: depende del ancho disponible (`HomeCollectionRowLayout`).
    let albumColumnWidth: CGFloat
    /// Alto del mosaico de canciones: tres filas fijas (448), haya o no tres canciones.
    let songGridHeight: CGFloat
    /// Alto del carril de colecciones: tarjeta (`ancho + 121`) más el aire de la sombra (8 arriba y 48 abajo).
    let albumContentHeight: CGFloat
    let songPanelHeight: CGFloat
    let albumPanelHeight: CGFloat
    let albumCardHeight: CGFloat
    let totalHeight: CGFloat

    init(width: CGFloat, hasSongs: Bool, hasAlbums: Bool, songCount: Int = 9, albumCount: Int = 2,
         trailingInset: CGFloat = Self.horizontalInset) {
        let inner = max(0, width - Self.horizontalInset - max(0, trailingInset))
        songWidth = inner
        albumColumnWidth = HomeCollectionRowLayout(width: width, leadingInset: Self.horizontalInset,
                                                   trailingInset: trailingInset).cardWidth
        songGridHeight = hasSongs ? HomeMosaicMetrics.totalHeight : 0
        albumCardHeight = HomeCollectionCardMetrics.cardHeight(cardWidth: albumColumnWidth)
        albumContentHeight = hasAlbums ? HomeCollectionCardMetrics.railHeight(cardWidth: albumColumnWidth) : 0
        songPanelHeight = hasSongs ? 46 + songGridHeight : 0
        // Encabezado y rail van pegados: los 8 pt de aire superior del rail reemplazan la separación de 8.
        albumPanelHeight = hasAlbums ? Self.headerHeight + albumContentHeight : 0
        totalHeight = songPanelHeight + albumPanelHeight + (hasSongs && hasAlbums ? Self.sectionGap : 0)
            + (hasSongs && !hasAlbums ? Self.bottomGap : 0)
    }

    static func height(width: CGFloat, hasSongs: Bool, hasAlbums: Bool, songCount: Int = 9, albumCount: Int = 2,
                       trailingInset: CGFloat = Self.horizontalInset) -> CGFloat {
        Self(width: width, hasSongs: hasSongs, hasAlbums: hasAlbums, songCount: songCount,
             albumCount: albumCount, trailingInset: trailingInset).totalHeight
    }
}

/// Destacados de Home: Speed Dial y colecciones con acciones directas.
struct HomeFeaturedView: View {
    let songs: [HomeItemRecord]
    let collections: [HomeItemRecord]
    let collectionKind: HomeFeaturedCollectionKind
    let width: CGFloat
    var trailingInset: CGFloat = HomeFeaturedLayout.horizontalInset
    let resetKey: String
    var metadataSessionKey: String? = nil
    let loadingCollectionID: String?
    let core: SideBCore?
    let onSong: (HomeItemRecord) -> Void
    let onCollection: (HomeItemRecord) -> Void
    let onArtist: (HomeItemRecord) -> Void
    let onPlayCollection: (HomeItemRecord, Bool) -> Void
    var menuProvider: ((HomeItemRecord) -> NSMenu?)? = nil
    var playbackContext: QueueContext? = nil
    var isPlaying: Bool = false

    /// Se piden los detalles de toda la fila (hasta 36 colecciones): el caché cubre las 48 posibles.
    private static let metadataLimit = 48
    @State private var albumMetadataModel = HomeAlbumMetadataModel(limit: HomeFeaturedView.metadataLimit)
    @State private var playlistMetadataModel = HomePlaylistMetadataModel(limit: HomeFeaturedView.metadataLimit)
    @State private var visibleTracker = HomeVisibleCollectionTracker()
    @State private var showsAll = false
    /// Acabado del panel de las tarjetas: cambiarlo en Configuración → Apariencia actualiza la fila sin reiniciar.
    @AppStorage(HomeAppearance.albumCardStyleKey, store: HomeAppearance.preferences)
    private var albumCardStyleRawValue = HomeAlbumCardStyle.tinted.rawValue
    private var albumCardStyle: HomeAlbumCardStyle { HomeAlbumCardStyle(rawValue: albumCardStyleRawValue) ?? .tinted }
    private var layout: HomeFeaturedLayout {
        HomeFeaturedLayout(width: width, hasSongs: !songs.isEmpty, hasAlbums: !collections.isEmpty,
            songCount: songs.count, albumCount: collections.count, trailingInset: trailingInset)
    }

    var body: some View {
        let _ = L10n.revision
        VStack(alignment: .leading, spacing: HomeFeaturedLayout.sectionGap) {
            if !songs.isEmpty {
                // El encabezado conserva su margen; el mosaico va a sangre con los márgenes dentro de su contenido.
                VStack(alignment: .leading, spacing: HomeFeaturedLayout.contentGap) {
                    HStack { Text(L10n.text("app.home.speedDial")).font(.system(size: 22, weight: .bold)); Spacer() }
                        .frame(height: HomeFeaturedLayout.headerHeight)
                        .padding(.leading, HomeFeaturedLayout.horizontalInset)
                        .padding(.trailing, max(0, trailingInset))
                    HomeFeaturedNativeRail(records: Array(songs.prefix(27)), usesMosaic: true,
                        leadingInset: HomeFeaturedLayout.horizontalInset, trailingInset: max(0, trailingInset),
                        session: resetKey, playback: playbackContext, playing: isPlaying, onOpen: onSong, onPlay: onSong,
                        onArtist: onArtist, menu: menuProvider)
                        .frame(width: width, height: layout.songGridHeight)
                }
            }
            if !collections.isEmpty {
                collectionsPanel
            }
        }
        .frame(width: width, height: layout.totalHeight, alignment: .topLeading)
        // Depende de la lista completa, la sesión, el tipo y el core: desplazar la fila no reinicia la carga.
        .task(id: metadataRequest) {
            // Las visibles las publica el carril justo después de su primer layout; esperar esa primera publicación
            // decide el orden (visibles primero, después el resto en el orden de la fila) sin carreras.
            let visible = await visibleTracker.firstPublication()
            let ordered = HomeCollectionRequestOrder.order(collections, visible: visible, id: Self.identity)
            let session = metadataSessionKey ?? resetKey
            switch collectionKind {
            case .albums: await albumMetadataModel.load(items: ordered, core: core, sessionKey: session)
            case .playlists: await playlistMetadataModel.load(items: ordered, core: core, sessionKey: session)
            }
        }
        .sheet(isPresented: $showsAll) {
            VStack {
                HStack { Text(collectionKind.title).font(.title2); Spacer(); Button(L10n.text("app.close")) { showsAll = false }.keyboardShortcut(.cancelAction) }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 14) {
                        ForEach(collections.map(FeaturedItem.init)) { item in
                            collectionCard(item.record, width: 180, height: 180 + HomeFeaturedLayout.albumTextHeight)
                                .id(item.id)
                        }
                    }
                }
            }.padding(24).frame(width: min(840, max(320, width - 48)), height: 500)
        }
        .onChange(of: resetKey) { _, _ in showsAll = false }
    }

    private var collectionsPanel: some View {
        // Read observable metadata while SwiftUI tracks this presentation, then pass
        // immutable values into AppKit callbacks.
        let metadata = Dictionary(collections.map { (Self.identity($0), collectionMetadata(for: $0)) }, uniquingKeysWith: { first, _ in first })
        // Sin separación entre encabezado y carril: los 8 pt de aire superior del carril ocupan el lugar de la separación.
        return VStack(spacing: 0) {
            HStack {
                Text(collectionKind.title).font(.system(size: 22, weight: .bold))
                Spacer()
                Button { showsAll = true } label: {
                    HStack(spacing: 3) {
                        Text(L10n.text("detail.viewAll"))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .frame(height: HomeFeaturedLayout.headerHeight)
            // El encabezado conserva su margen; la fila va a sangre con los márgenes dentro de su contenido.
            .padding(.leading, HomeFeaturedLayout.horizontalInset)
            .padding(.trailing, max(0, trailingInset))
            HomeFeaturedNativeRail(records: collections, leadingInset: HomeFeaturedLayout.horizontalInset,
                trailingInset: max(0, trailingInset), albumCardStyle: albumCardStyle,
                session: resetKey + collectionKind.rawValue, playback: playbackContext, playing: isPlaying, loadingID: loadingCollectionID,
                revision: metadataRevision(metadata),
                display: { record in
                    let value = metadata[Self.identity(record)]!
                    var result = record
                    result.title = value.title
                    result.artists = value.credit
                    result.artistId = value.creditID
                    return result
                },
                summary: { record in metadata[Self.identity(record)]!.summary },
                onOpen: openCollection, onPlay: { onPlayCollection($0, false) }, onArtist: onArtist, menu: menuProvider,
                onVisible: { visibleTracker.publish($0) })
                .frame(width: width, height: layout.albumContentHeight)
        }
    }

    private func metadataRevision(_ metadata: [String: CollectionMetadata]) -> Int {
        var hasher = Hasher()
        for key in metadata.keys.sorted() {
            let value = metadata[key]!
            hasher.combine(key); hasher.combine(value.title); hasher.combine(value.credit)
            hasher.combine(value.creditID); hasher.combine(value.firstLine); hasher.combine(value.summary)
        }
        return hasher.finalize()
    }

    struct MetadataRequest: Equatable {
        let session: String
        let collectionIDs: [String]
        let kind: HomeFeaturedCollectionKind
        let coreIdentity: ObjectIdentifier?
    }
    private var metadataRequest: MetadataRequest {
        MetadataRequest(session: metadataSessionKey ?? resetKey, collectionIDs: collections.map(Self.identity),
                        kind: collectionKind, coreIdentity: core.map(ObjectIdentifier.init))
    }

    private var collectionName: String { collectionKind == .albums ? L10n.text("metadata.album").lowercased() : L10n.text("metadata.playlist").lowercased() }

    private struct CollectionMetadata {
        let title: String
        let credit: String?
        let creditID: String?
        /// Una línea para la tarjeta de la hoja «Ver todo».
        let firstLine: String
        /// «Álbum • 2016 • 17 canciones • 1 h 2 min»: el resumen completo de la tarjeta de la fila, como en Windows.
        let summary: String
    }

    private func collectionMetadata(for record: HomeItemRecord) -> CollectionMetadata {
        switch collectionKind {
        case .albums:
            let value = albumMetadataModel.display(for: record, sessionKey: metadataSessionKey ?? resetKey)
            return CollectionMetadata(title: value.title, credit: value.artist,
                creditID: value.artistID,
                firstLine: value.cardSummary, summary: value.summary)
        case .playlists:
            let value = playlistMetadataModel.display(for: record, sessionKey: metadataSessionKey ?? resetKey)
            return CollectionMetadata(title: value.title, credit: value.creator,
                creditID: value.creatorID,
                firstLine: value.cardSummary, summary: value.summary)
        }
    }

    private func collectionCard(_ record: HomeItemRecord, width: CGFloat, height: CGFloat) -> some View {
        let metadata = collectionMetadata(for: record)
        return VStack(alignment: .leading, spacing: 0) {
            MediaArtworkControls(
                isCollection: true,
                isActive: MediaPlaybackIdentity.isCollectionActive(kind: record.kind, id: record.id, context: playbackContext),
                isPlaying: isPlaying,
                isLoading: loadingCollectionID.map(MenuIDNormalizer.normalize) == MenuIDNormalizer.normalize(record.id),
                showsIndicator: true, accessibilityTitle: metadata.title,
                onOpen: { openCollection(record) }, onPlay: { onPlayCollection(record, false) },
                menuProvider: menuProvider.map { provider in { provider(record) } }
            ) {
                artwork(record.thumbnail, radius: 10).frame(width: width, height: width)
            }
            .frame(width: width, height: width)

            VStack(alignment: .leading, spacing: 2) {
                Button { openCollection(record) } label: {
                    Text(metadata.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain).mediaCardFocusControl()
                .accessibilityLabel(L10n.text("home.collection.open", args: [collectionName, metadata.title]))
                if let artist = metadata.credit {
                    Group {
                        if let artistID = metadata.creditID {
                            Button(artist) {
                                var artistRecord = record
                                artistRecord.artistId = artistID
                                showsAll = false
                                onArtist(artistRecord)
                            }.buttonStyle(.plain).mediaCardFocusControl()
                        } else { Text(artist).allowsHitTesting(false) }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Text(metadata.firstLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.top, 8)
            .frame(width: width, alignment: .topLeading)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .contentShape(Rectangle())
        .mediaCardActivation(label: L10n.text("search.open_card", args: [metadata.title])) { openCollection(record) }
        .mediaCardSurface()
        .overlay { NativeContextMenuOverlay { menuProvider?(record) } }
    }

    private func openCollection(_ record: HomeItemRecord) {
        showsAll = false
        onCollection(record)
    }

    private func artwork(_ source: String?, radius: CGFloat) -> some View {
        CachedAsyncImage(url: ImageURLHelper.optimizedThumbnailURL(from: source, targetPixelSize: 480), targetSize: CGSize(width: 240, height: 240)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(.white.opacity(0.06)).overlay(Image(systemName: "music.note").foregroundStyle(.tertiary))
        }
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .clipped()
    }

    private static func identity(_ record: HomeItemRecord) -> String { "\(record.kind):\(record.id)" }
    private struct FeaturedItem: Identifiable {
        let record: HomeItemRecord
        var id: String { "\(record.kind):\(record.id)" }
    }

}
