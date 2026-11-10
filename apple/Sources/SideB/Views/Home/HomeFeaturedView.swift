import SwiftUI
import AppKit
import SideBCore

struct HomeFeaturedLayout {
    static let horizontalInset: CGFloat = 28
    static let sectionGap: CGFloat = 30
    static let stackGap: CGFloat = 30
    static let headerHeight: CGFloat = 38
    static let contentGap: CGFloat = 8
    static let albumGap: CGFloat = 14
    /// Cards keep one size at every window width, like Apple Music shelves: resizing only
    /// reveals more or fewer cards. Scaling them with the width re-laid out every cell and
    /// changed the row height on each frame.
    static let songTileWidth: CGFloat = 190
    static let albumCardWidth: CGFloat = 176
    /// Artwork stays square; below it: title, creator and one detail line.
    static let albumTextHeight: CGFloat = 64
    /// Air between the featured block and the next feed section.
    static let bottomGap: CGFloat = 20
    let songWidth: CGFloat
    let albumWidth: CGFloat
    let albumColumnWidth: CGFloat
    let tile: CGFloat
    let songGridHeight: CGFloat
    let albumContentHeight: CGFloat
    let songPanelHeight: CGFloat
    let albumPanelHeight: CGFloat
    let albumCardHeight: CGFloat
    let totalHeight: CGFloat

    init(width: CGFloat, hasSongs: Bool, hasAlbums: Bool, songCount: Int = 9, albumCount: Int = 2,
         trailingInset: CGFloat = Self.horizontalInset) {
        let inner = max(0, width - Self.horizontalInset - max(0, trailingInset))
        songWidth = inner
        albumWidth = inner
        tile = Self.songTileWidth
        albumColumnWidth = Self.albumCardWidth
        let rows = hasSongs ? CGFloat(min(3, max(0, songCount))) : 0
        songGridHeight = rows * 126 + max(0, rows - 1) * 12
        albumCardHeight = albumColumnWidth + Self.albumTextHeight
        albumContentHeight = hasAlbums ? albumCardHeight : 0
        songPanelHeight = hasSongs ? 46 + songGridHeight : 0
        albumPanelHeight = hasAlbums ? 46 + albumContentHeight : 0
        totalHeight = songPanelHeight + albumPanelHeight + (hasSongs && hasAlbums ? 30 : 0) + (hasSongs || hasAlbums ? Self.bottomGap : 0)
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

    @State private var albumMetadataModel = HomeAlbumMetadataModel()
    @State private var playlistMetadataModel = HomePlaylistMetadataModel()
    @State private var visibleCollectionIDs: [String] = []
    @State private var showsAll = false
    @State private var visibleSheetIDs: [String] = []
    private var layout: HomeFeaturedLayout {
        HomeFeaturedLayout(width: width, hasSongs: !songs.isEmpty, hasAlbums: !collections.isEmpty,
            songCount: songs.count, albumCount: collections.count, trailingInset: trailingInset)
    }
    private var collectionIDs: [String] { collections.map(Self.identity) }

    var body: some View {
        let _ = L10n.revision
        VStack(alignment: .leading, spacing: HomeFeaturedLayout.sectionGap) {
            if !songs.isEmpty {
                VStack(spacing: 8) {
                    HStack { Text(L10n.text("app.home.speedDial")).font(.system(size: 22, weight: .bold)); Spacer() }.frame(height: 38)
                    HomeFeaturedNativeRail(records: Array(songs.prefix(27)), rows: min(3, songs.count), itemWidth: layout.tile, itemHeight: 126,
                        session: resetKey, playback: playbackContext, playing: isPlaying, onOpen: onSong, onPlay: onSong, menu: menuProvider)
                        .frame(height: layout.songGridHeight)
                }

            }
            if !collections.isEmpty { collectionsPanel }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.leading, HomeFeaturedLayout.horizontalInset)
        .padding(.trailing, max(0, trailingInset))
        .frame(width: width, height: layout.totalHeight, alignment: .topLeading)
        .task(id: metadataRequest) {
            switch collectionKind {
            case .albums:
                await albumMetadataModel.load(items: visibleCollections, core: core, sessionKey: metadataSessionKey ?? resetKey)
            case .playlists:
                await playlistMetadataModel.load(items: visibleCollections, core: core, sessionKey: metadataSessionKey ?? resetKey)
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
                    }.scrollTargetLayout()
                }
                .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.01) { visibleSheetIDs = $0 }
            }.padding(24).frame(width: min(840, max(320, width - 48)), height: 500)
        }
        .onChange(of: resetKey) { _, _ in showsAll = false; visibleSheetIDs = [] }
    }

    private var collectionsPanel: some View {
        // Read observable metadata while SwiftUI tracks this presentation, then pass
        // immutable values into AppKit callbacks.
        let metadata = Dictionary(collections.map { (Self.identity($0), collectionMetadata(for: $0)) }, uniquingKeysWith: { first, _ in first })
        return VStack(spacing: HomeFeaturedLayout.contentGap) {
            HStack {
                Text(collectionKind.title).font(.system(size: 22, weight: .bold))
                Spacer()
                Button { visibleSheetIDs = []; showsAll = true } label: {
                    HStack(spacing: 3) {
                        Text(L10n.text("detail.viewAll"))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }.frame(height: HomeFeaturedLayout.headerHeight)
            HomeFeaturedNativeRail(records: collections, rows: 1, itemWidth: layout.albumColumnWidth, itemHeight: layout.albumCardHeight,
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
                summary: { record in metadata[Self.identity(record)]!.firstLine },
                onOpen: openCollection, onPlay: { onPlayCollection($0, false) }, onArtist: onArtist, menu: menuProvider,
                onVisible: { visibleCollectionIDs = $0 }).frame(height: layout.albumContentHeight)
        }
    }

    private func metadataRevision(_ metadata: [String: CollectionMetadata]) -> Int {
        var hasher = Hasher()
        for key in metadata.keys.sorted() {
            let value = metadata[key]!
            hasher.combine(key); hasher.combine(value.title); hasher.combine(value.credit)
            hasher.combine(value.creditID); hasher.combine(value.firstLine)
        }
        return hasher.finalize()
    }

    private struct MetadataRequest: Equatable {
        let session: String
        let collectionIDs: [String]
        let kind: HomeFeaturedCollectionKind
        let coreIdentity: ObjectIdentifier?
    }
    private var metadataRequest: MetadataRequest {
        MetadataRequest(session: metadataSessionKey ?? resetKey, collectionIDs: visibleCollections.map(\.id), kind: collectionKind, coreIdentity: core.map(ObjectIdentifier.init))
    }

    private var visibleCollections: [HomeItemRecord] {
        collections.filter { (showsAll ? visibleSheetIDs : visibleCollectionIDs).contains(Self.identity($0)) }
    }

    private var collectionName: String { collectionKind == .albums ? L10n.text("metadata.album").lowercased() : L10n.text("metadata.playlist").lowercased() }
    private var collectionBadge: String { collectionKind == .albums ? L10n.text("metadata.album").uppercased() : L10n.text("metadata.playlist.short").uppercased() }

    private struct CollectionMetadata {
        let title: String
        let credit: String?
        let creditID: String?
        let firstLine: String
        let duration: String
    }

    private func collectionMetadata(for record: HomeItemRecord) -> CollectionMetadata {
        switch collectionKind {
        case .albums:
            let value = albumMetadataModel.display(for: record, sessionKey: metadataSessionKey ?? resetKey)
            return CollectionMetadata(title: value.title, credit: value.artist,
                creditID: value.artistID, firstLine: value.cardSummary, duration: value.duration ?? "")
        case .playlists:
            let value = playlistMetadataModel.display(for: record, sessionKey: metadataSessionKey ?? resetKey)
            return CollectionMetadata(title: value.title, credit: value.creator,
                creditID: value.creatorID, firstLine: value.cardSummary, duration: value.duration ?? "")
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

/// Intersect card bounds, excluding gaps, without mounting or fetching the catalogue.
enum HomeFeaturedRailViewport {
    static func visibleIDs(ids: [String], itemWidth: CGFloat, rows: Int, spacing: CGFloat,
                           offset: CGFloat, width: CGFloat) -> [String] {
        guard width > 0, itemWidth > 0, rows > 0 else { return [] }
        let stride = itemWidth + spacing
        let first = max(0, Int(floor(max(0, offset) / stride))) * rows
        let end = min(ids.count, Int(ceil((max(0, offset) + width) / stride)) * rows)
        guard first < end else { return [] }
        return (first..<end).filter { index in
            let x = CGFloat(index / rows) * stride
            return x + itemWidth > offset && x < offset + width
        }.map { ids[$0] }
    }
}
