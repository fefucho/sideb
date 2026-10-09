import SwiftUI
import AppKit
import SideBCore

struct HomeFeaturedLayout {
    static let horizontalInset: CGFloat = 28
    static let sectionGap: CGFloat = 24
    static let stackGap: CGFloat = 16
    static let headerHeight: CGFloat = 38
    static let contentGap: CGFloat = 8
    static let footerHeight: CGFloat = 48
    static let albumGap: CGFloat = 24
    static let minimumAlbumColumnWidth: CGFloat = 432

    let wide: Bool
    let songWidth: CGFloat
    let albumWidth: CGFloat
    let albumColumns: Int
    let albumColumnWidth: CGFloat
    var albumsPerPage: Int { albumColumns * 2 }
    let tile: CGFloat
    let songGridHeight: CGFloat
    let albumContentHeight: CGFloat
    let songPanelHeight: CGFloat
    let albumPanelHeight: CGFloat
    let albumCardHeight: CGFloat
    let totalHeight: CGFloat

    init(width: CGFloat, hasSongs: Bool, hasAlbums: Bool, songCount: Int = 9, albumCount: Int = 2) {
        wide = width >= 900
        let inner = max(0, width - Self.horizontalInset * 2)
        let songAvailable = wide && hasAlbums ? inner - Self.sectionGap - Self.minimumAlbumColumnWidth : inner
        tile = min(wide ? 144 : 140, max(0, (songAvailable - 16) / 3))
        songWidth = 3 * tile + 16
        albumWidth = wide && hasSongs ? max(0, inner - Self.sectionGap - songWidth) : inner
        let availableColumns = max(1, Int((albumWidth + Self.sectionGap) / (Self.minimumAlbumColumnWidth + Self.sectionGap)))
        albumColumns = min(3, max(1, (albumCount + 1) / 2), availableColumns)
        albumColumnWidth = (albumWidth - CGFloat(albumColumns - 1) * Self.sectionGap) / CGFloat(albumColumns)
        let songRows = hasSongs ? CGFloat((min(9, max(1, songCount)) + 2) / 3) : 0
        songGridHeight = songRows * tile + max(0, songRows - 1) * 8
        let albumRows = hasAlbums ? CGFloat(min(2, max(1, albumCount))) : 0
        if wide && hasSongs && hasAlbums {
            albumCardHeight = min(212, max(152, (songGridHeight - max(0, albumRows - 1) * Self.albumGap) / albumRows))
        } else {
            albumCardHeight = min(212, max(164, albumColumnWidth * 0.3))
        }
        albumContentHeight = albumRows * albumCardHeight + max(0, albumRows - 1) * Self.albumGap
        let chrome = Self.headerHeight + Self.contentGap + Self.footerHeight
        songPanelHeight = hasSongs ? chrome + songGridHeight : 0
        albumPanelHeight = hasAlbums ? chrome + albumContentHeight : 0
        totalHeight = wide ? max(songPanelHeight, albumPanelHeight) :
            songPanelHeight + albumPanelHeight + (hasSongs && hasAlbums ? Self.stackGap : 0)
    }

    static func height(width: CGFloat, hasSongs: Bool, hasAlbums: Bool, songCount: Int = 9, albumCount: Int = 2) -> CGFloat {
        Self(width: width, hasSongs: hasSongs, hasAlbums: hasAlbums, songCount: songCount, albumCount: albumCount).totalHeight
    }
}

/// Destacados de Home: Speed Dial y colecciones con acciones directas.
struct HomeFeaturedView: View {
    let songs: [HomeItemRecord]
    let collections: [HomeItemRecord]
    let collectionKind: HomeFeaturedCollectionKind
    let width: CGFloat
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var albumMetadataModel = HomeAlbumMetadataModel()
    @State private var playlistMetadataModel = HomePlaylistMetadataModel()
    @State private var songPage = 0
    @State private var collectionAnchor = 0

    private var layout: HomeFeaturedLayout {
        HomeFeaturedLayout(width: width, hasSongs: !songs.isEmpty, hasAlbums: !collections.isEmpty, songCount: songs.count, albumCount: collections.count)
    }
    private var wide: Bool { layout.wide }
    private var leftWidth: CGFloat { layout.songWidth }
    private var albumWidth: CGFloat { layout.albumWidth }
    private var tileSize: CGFloat { layout.tile }
    private var songPages: [[HomeItemRecord]] { Self.pages(songs, size: 9, limit: 3) }
    private var collectionPages: [[HomeItemRecord]] { Self.pages(collections, size: layout.albumsPerPage, limit: 6) }
    private var collectionPage: Int { min(collectionAnchor / layout.albumsPerPage, max(0, collectionPages.count - 1)) }
    private var collectionPageBinding: Binding<Int> {
        Binding(get: { collectionPage }, set: { collectionAnchor = $0 * layout.albumsPerPage })
    }
    private var songIDs: [String] { songs.map(Self.identity) }
    private var collectionIDs: [String] { collections.map(Self.identity) }

    var body: some View {
        let _ = L10n.revision
        // AnyLayout preserves the panels (and their artwork/tasks) across the
        // stacked/side-by-side breakpoint instead of replacing the view tree.
        let panelLayout = wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: HomeFeaturedLayout.sectionGap))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: HomeFeaturedLayout.stackGap))
        panelLayout {
            if !songs.isEmpty {
                songsPanel.frame(width: wide && !collections.isEmpty ? leftWidth : nil,
                                 alignment: .leading)
            }
            if !collections.isEmpty { collectionsPanel }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, HomeFeaturedLayout.horizontalInset)
        .frame(width: width, height: layout.totalHeight, alignment: .topLeading)
        .task(id: metadataRequest) {
            switch collectionKind {
            case .albums:
                await albumMetadataModel.load(items: currentCollectionPage, core: core, sessionKey: metadataSessionKey ?? resetKey)
            case .playlists:
                await playlistMetadataModel.load(items: currentCollectionPage, core: core, sessionKey: metadataSessionKey ?? resetKey)
            }
        }
        .onChange(of: resetKey) { _, _ in resetPages() }
        .onChange(of: songIDs) { _, _ in songPage = 0 }
        .onChange(of: collectionIDs) { oldIDs, newIDs in
            // Preserve the visible collection across capacity changes and bounded continuation growth.
            let anchorID = oldIDs.indices.contains(collectionAnchor) ? oldIDs[collectionAnchor] : nil
            collectionAnchor = anchorID.flatMap { newIDs.firstIndex(of: $0) } ?? 0
        }
        .onChange(of: collectionKind) { _, _ in collectionAnchor = 0 }
        .onChange(of: songPages.count) { _, count in songPage = min(songPage, max(0, count - 1)) }
    }

    @ViewBuilder private var songsPanel: some View {
        if !songs.isEmpty {
            VStack(spacing: 0) {
                sectionHeader(L10n.text("app.home.speedDial"))
                ZStack(alignment: .topLeading) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileSize), spacing: 8), count: 3), spacing: 8) {
                        ForEach(currentSongPage.map(FeaturedItem.init), id: \.id) { item in
                            let record = item.record
                            let isRadioOrigin = MediaPlaybackIdentity.isRadioOrigin(videoID: record.id, context: playbackContext)
                            MediaArtworkControls(
                                isCollection: false,
                                isActive: isRadioOrigin,
                                isPlaying: isPlaying, showsIndicator: true,
                                accessibilityTitle: record.title,
                                onOpen: { onSong(record) }, onPlay: { onSong(record) },
                                menuProvider: menuProvider.map { provider in { provider(record) } }
                            ) {
                                songTile(record)
                            }
                            .frame(width: tileSize, height: tileSize)
                            .help(isRadioOrigin
                                ? L10n.text(isPlaying ? "home.radio.pause" : "home.radio.resume", args: [record.title])
                                : L10n.text("home.radio.start", args: [record.title]))
                        }
                    }
                    .frame(width: 3 * tileSize + 16, alignment: .leading)
                    .id(songPage)
                    .transition(.opacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: layout.songGridHeight, alignment: .topLeading)
                .clipped()
                .overlay { HomeFeaturedPageWheel(enabled: songPages.count > 1) { delta in move($songPage, by: delta, count: songPages.count) } }
                .padding(.top, HomeFeaturedLayout.contentGap)
                pageControls(page: $songPage, count: songPages.count, label: L10n.text("search.filter.songs"))
                    .padding(.top, 8)
            }
            .padding(.bottom, 16)
            .frame(height: layout.songPanelHeight, alignment: .top)
        }
    }

    @ViewBuilder private var collectionsPanel: some View {
        if !collections.isEmpty {
            VStack(spacing: 0) {
                sectionHeader(collectionKind.title)
                ZStack(alignment: .topLeading) {
                    HomeFeaturedCollectionLayout(columnWidth: layout.albumColumnWidth,
                                                 cardHeight: albumCardHeight) {
                        ForEach(currentCollectionPage.map(FeaturedItem.init), id: \.id) { item in
                            collectionCard(item.record, width: layout.albumColumnWidth, height: albumCardHeight)
                                .overlay { NativeContextMenuOverlay { menuProvider?(item.record) } }
                                .transition(.opacity)
                        }
                    }
                }
                .frame(width: albumWidth, height: layout.albumContentHeight, alignment: .topLeading)
                .clipped()
                .overlay { HomeFeaturedPageWheel(enabled: collectionPages.count > 1) { delta in move(collectionPageBinding, by: delta, count: collectionPages.count) } }
                .padding(.top, HomeFeaturedLayout.contentGap)
                pageControls(page: collectionPageBinding, count: collectionPages.count, label: collectionKind.title)
                    .padding(.top, 8)
            }
            .padding(.bottom, 16)
            .frame(height: layout.albumPanelHeight, alignment: .top)
        }
    }

    private struct MetadataRequest: Equatable {
        let session: String
        let collectionIDs: [String]
        let kind: HomeFeaturedCollectionKind
        let coreIdentity: ObjectIdentifier?
    }
    private var metadataRequest: MetadataRequest {
        MetadataRequest(session: metadataSessionKey ?? resetKey, collectionIDs: currentCollectionPage.map(\.id), kind: collectionKind, coreIdentity: core.map(ObjectIdentifier.init))
    }

    private var currentSongPage: [HomeItemRecord] { songPages.indices.contains(songPage) ? songPages[songPage] : [] }
    private var currentCollectionPage: [HomeItemRecord] { collectionPages.indices.contains(collectionPage) ? collectionPages[collectionPage] : [] }
    private var albumCardHeight: CGFloat { layout.albumCardHeight }

    private func songTile(_ record: HomeItemRecord) -> some View {
        ZStack(alignment: .bottomLeading) {
            artwork(record.thumbnail, radius: 5)
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if tileSize >= 110, let artist = record.artists, !artist.isEmpty {
                    Text(artist).font(.system(size: 10)).foregroundStyle(.white.opacity(0.76)).lineLimit(1)
                }
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(RoundedRectangle(cornerRadius: 5))
    }

    private var collectionName: String { collectionKind == .albums ? L10n.text("metadata.album").lowercased() : L10n.text("metadata.playlist").lowercased() }
    private var collectionBadge: String { collectionKind == .albums ? L10n.text("metadata.album").uppercased() : L10n.text("metadata.playlist.short").uppercased() }

    private struct CollectionMetadata {
        let title: String
        let credit: String?
        let creditID: String?
        let summary: String
    }

    private func collectionMetadata(for record: HomeItemRecord) -> CollectionMetadata {
        switch collectionKind {
        case .albums:
            let value = albumMetadataModel.display(for: record, sessionKey: metadataSessionKey ?? resetKey)
            return CollectionMetadata(title: value.title, credit: value.artist,
                creditID: value.artistID, summary: value.summary)
        case .playlists:
            let value = playlistMetadataModel.display(for: record, sessionKey: metadataSessionKey ?? resetKey)
            return CollectionMetadata(title: value.title, credit: value.creator,
                creditID: value.creatorID, summary: value.summary)
        }
    }

    private func collectionCard(_ record: HomeItemRecord, width: CGFloat, height: CGFloat) -> some View {
        let metadata = collectionMetadata(for: record)
        let spacious = height >= 190
        return HStack(alignment: .top, spacing: 16) {
            MediaArtworkControls(
                isCollection: true,
                isActive: MediaPlaybackIdentity.isCollectionActive(kind: record.kind, id: record.id, context: playbackContext),
                isPlaying: isPlaying,
                isLoading: loadingCollectionID.map(MenuIDNormalizer.normalize) == MenuIDNormalizer.normalize(record.id),
                showsIndicator: true, accessibilityTitle: metadata.title,
                onOpen: { onCollection(record) }, onPlay: { onPlayCollection(record, false) },
                menuProvider: menuProvider.map { provider in { provider(record) } }
            ) {
                artwork(record.thumbnail, radius: 5)
            }
            .frame(width: height, height: height)

            VStack(alignment: .leading, spacing: spacious ? 7 : 5) {
                Text(collectionBadge).font(.system(size: 10, weight: .bold))
                    .tracking(1.3).foregroundStyle(.secondary)
                    .allowsHitTesting(false)
                Button { onCollection(record) } label: {
                    Text(metadata.title)
                        .font(.system(size: spacious ? 25 : 22, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
                                onArtist(artistRecord)
                            }.buttonStyle(.plain).mediaCardFocusControl()
                        } else { Text(artist).allowsHitTesting(false) }
                    }
                    .font(.system(size: spacious ? 15 : 13, weight: .semibold))
                    .lineLimit(1)
                }
                Text(metadata.summary)
                    .font(.system(size: spacious ? 12 : 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height, alignment: .topLeading)

        }
        .frame(width: width, height: height, alignment: .topLeading)
        .contentShape(Rectangle())
        .mediaCardActivation(label: L10n.text("search.open_card", args: [metadata.title])) { onCollection(record) }
        .mediaCardSurface()
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

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.system(size: 20, weight: .semibold))
            Spacer()
        }
        .frame(height: HomeFeaturedLayout.headerHeight)
    }

    private func pageControls(page: Binding<Int>, count: Int, label: String) -> some View {
        HStack(spacing: 7) {
            Button { move(page, by: -1, count: count) } label: {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)).frame(width: 20, height: 24)
            }
            .disabled(count < 2 || page.wrappedValue == 0)
            .accessibilityLabel(L10n.text("home.page.previous", args: [label]))
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { index in
                    Button { changePage(page, to: index) } label: {
                        Circle().fill(index == page.wrappedValue ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.35))
                            .frame(width: 7, height: 7).frame(width: 14, height: 24)
                    }
                    .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("home.page.position", args: [label, String(index + 1), String(count)]))
                    .accessibilityAddTraits(index == page.wrappedValue ? .isSelected : [])
                }
            }
            Button { move(page, by: 1, count: count) } label: {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).frame(width: 20, height: 24)
            }
            .disabled(count < 2 || page.wrappedValue >= count - 1)
            .accessibilityLabel(L10n.text("home.page.next", args: [label]))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
    }

    private func move(_ page: Binding<Int>, by delta: Int, count: Int) {
        changePage(page, to: min(max(page.wrappedValue + delta, 0), max(0, count - 1)))
    }
    private func changePage(_ page: Binding<Int>, to value: Int) {
        guard value != page.wrappedValue else { return }
        if reduceMotion { page.wrappedValue = value }
        else { withAnimation(.easeInOut(duration: 0.14)) { page.wrappedValue = value } }
    }
    private func resetPages() { songPage = 0; collectionAnchor = 0 }

    private static func identity(_ record: HomeItemRecord) -> String { "\(record.kind):\(record.id)" }
    private struct FeaturedItem: Identifiable {
        let record: HomeItemRecord
        var id: String { "\(record.kind):\(record.id)" }
    }
    private static func pages(_ records: [HomeItemRecord], size: Int, limit: Int) -> [[HomeItemRecord]] {
        stride(from: 0, to: min(records.count, size * limit), by: size).map { start in
            Array(records[start..<min(start + size, records.count)])
        }
    }
}

/// One identity domain for the visible collections. Adding a column only mounts
/// the new cards; existing cards never move to a different ForEach parent.
struct HomeFeaturedCollectionLayout: Layout {
    let columnWidth: CGFloat
    let cardHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let columns = CGFloat((subviews.count + 1) / 2)
        let rows = CGFloat(min(2, subviews.count))
        return CGSize(width: columns * columnWidth + max(0, columns - 1) * HomeFeaturedLayout.sectionGap,
                      height: rows * cardHeight + max(0, rows - 1) * HomeFeaturedLayout.albumGap)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index / 2) * (columnWidth + HomeFeaturedLayout.sectionGap),
                                     y: bounds.minY + CGFloat(index % 2) * (cardHeight + HomeFeaturedLayout.albumGap)),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: columnWidth, height: cardHeight))
        }
    }
}

/// One native responder per panel: horizontal wheel gestures page, vertical gestures pass to the feed.
private struct HomeFeaturedPageWheel: NSViewRepresentable {
    let enabled: Bool
    let onPage: (Int) -> Void
    func makeNSView(context: Context) -> HomeFeaturedWheelView { HomeFeaturedWheelView() }
    func updateNSView(_ view: HomeFeaturedWheelView, context: Context) { view.onPage = onPage; view.ownsHorizontalNavigationGesture = enabled }
}

struct HomeFeaturedWheelInput {
    private var accumulated: CGFloat = 0
    private var handled = false
    private var lastTimestamp: TimeInterval = 0

    mutating func reset() { accumulated = 0; handled = false }
    mutating func consume(x: CGFloat, y: CGFloat, timestamp: TimeInterval, momentum: Bool) -> Int? {
        guard !momentum, abs(x) > abs(y) * 1.4, abs(x) > 0.5 else { return nil }
        if timestamp - lastTimestamp > 0.35 { reset() }
        lastTimestamp = timestamp
        guard !handled else { return nil }
        accumulated += x
        guard abs(accumulated) >= 40 else { return nil }
        handled = true
        return accumulated < 0 ? 1 : -1
    }
}

private final class HomeFeaturedWheelView: NSView, HorizontalNavigationGestureOwner {
    var ownsHorizontalNavigationGesture = false
    var onPage: ((Int) -> Void)?
    private var input = HomeFeaturedWheelInput()
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard ownsHorizontalNavigationGesture, let event = NSApp.currentEvent, event.type == .scrollWheel,
              super.hitTest(point) != nil else { return nil }
        if event.phase.contains(.began) || event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            input.reset()
        }
        return abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.4 &&
            abs(event.scrollingDeltaX) > 0.5 ? self : nil
    }
    override func scrollWheel(with event: NSEvent) {
        if let delta = input.consume(x: event.scrollingDeltaX, y: event.scrollingDeltaY,
                                    timestamp: event.timestamp, momentum: !event.momentumPhase.isEmpty) {
            onPage?(delta)
        }
    }
}
