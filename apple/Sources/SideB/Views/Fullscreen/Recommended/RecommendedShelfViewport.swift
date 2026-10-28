import AppKit
import SwiftUI
import SideBCore

/// Prepared once per data revision. Occurrences, rather than video IDs alone,
/// keep repeated provider items distinct without changing their order.
struct RecommendedShelf: Equatable {
    enum Kind: Int, CaseIterable { case artist, album, similar, relatedArtists }
    struct Song: Identifiable, Equatable {
        let id: Int
        let track: SongItemRecord
    }
    enum Item: Equatable { case songs([Song]), artist(BrowseCardRecord) }
    let kind: Kind
    let name: String?
    let browseID: String?
    let items: [Item]
    var isArtist: Bool { kind == .relatedArtists }
    var contentHeight: CGFloat { isArtist ? 118 : 168 }
    var height: CGFloat { 28 + contentHeight + 22 }
    var title: String {
        switch kind {
        case .artist: return name.map { L10n.text("fullscreen.moreByArtist", args: [$0]) } ?? L10n.text("fullscreen.moreByThisArtist")
        case .album: return name.map { L10n.text("fullscreen.fromAlbum", args: [$0]) } ?? L10n.text("fullscreen.fromSameAlbum")
        case .similar: return L10n.text("fullscreen.similarSongs")
        case .relatedArtists: return L10n.text("fullscreen.fansAlsoLike")
        }
    }
    static func make(from data: RecommendedData) -> [Self] {
        func songs(_ tracks: [SongItemRecord]) -> [Item] {
            stride(from: 0, to: tracks.count, by: 3).map { start in
                .songs((start..<min(start + 3, tracks.count)).map { Song(id: $0, track: tracks[$0]) })
            }
        }
        return [
            Self(kind: .artist, name: data.artistName, browseID: data.artistBrowseId, items: songs(data.artistSongs)),
            Self(kind: .album, name: data.albumTitle, browseID: data.albumBrowseId, items: songs(data.albumSongs)),
            Self(kind: .similar, name: nil, browseID: nil, items: songs(data.similarSongs)),
            Self(kind: .relatedArtists, name: nil, browseID: nil, items: data.relatedArtists.map(Item.artist))
        ].filter { !$0.items.isEmpty }
    }
}

/// Native scrolling/reuse, with the existing compact SwiftUI artwork controls.
/// Playback observation stays inside mounted song rows; it never rebuilds the feed.
struct RecommendedShelfViewport: NSViewRepresentable {
    let data: RecommendedData
    let player: PlayerViewModel
    let router: NavigationRouter?
    let localizationRevision = L10n.revision

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSScrollView { makeScrollView(coordinator: context.coordinator) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 600, height: proposal.height ?? 500)
    }
    func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scroll = HomeFeedScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 2, right: 0)
        let table = NSTableView()
        table.backgroundColor = .clear
        table.style = .plain
        table.usesAutomaticRowHeights = false
        table.headerView = nil
        table.selectionHighlightStyle = .none
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.autoresizingMask = [.width]
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("related"))
        column.minWidth = 0
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = coordinator
        table.delegate = coordinator
        table.setAccessibilityLabel(L10n.text("fullscreen.recommendations"))
        scroll.documentView = table
        coordinator.table = table
        coordinator.scroll = scroll
        table.reloadData()
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { update(scroll, coordinator: context.coordinator) }
    func update(_ scroll: NSScrollView, coordinator: Coordinator) {
        let old = coordinator.parent
        coordinator.parent = self
        guard old.data != data || old.localizationRevision != localizationRevision || old.router !== router || old.player !== player else { return }
        coordinator.shelves = RecommendedShelf.make(from: data)
        if old.data.loadedVideoId != data.loadedVideoId {
            coordinator.offsets.removeAll()
            scroll.contentView.scroll(to: .zero)
        }
        coordinator.table?.setAccessibilityLabel(L10n.text("fullscreen.recommendations"))
        coordinator.table?.reloadData()
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.table?.enumerateAvailableRowViews { row, _ in
            row.subviews.compactMap { $0 as? RecommendedNativeShelf }.forEach { $0.suspend() }
        }
        coordinator.table?.delegate = nil
        coordinator.table?.dataSource = nil
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: RecommendedShelfViewport
        var shelves: [RecommendedShelf]
        var offsets: [RecommendedShelf.Kind: CGFloat] = [:]
        weak var table: NSTableView?
        weak var scroll: NSScrollView?
        init(parent: RecommendedShelfViewport) { self.parent = parent; shelves = RecommendedShelf.make(from: parent.data) }
        func numberOfRows(in tableView: NSTableView) -> Int { shelves.count }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { shelves[row].height }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let shelf = shelves[row]
            let view = tableView.makeView(withIdentifier: RecommendedNativeShelf.identifier, owner: nil) as? RecommendedNativeShelf
                ?? RecommendedNativeShelf(frame: .zero)
            view.configure(shelf: shelf, player: parent.player, router: parent.router,
                           offset: offsets[shelf.kind] ?? 0) { [weak self] offset in self?.offsets[shelf.kind] = offset }
            return view
        }
        func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
            rowView.subviews.compactMap { $0 as? RecommendedNativeShelf }.forEach { $0.suspend() }
        }
    }
}

private final class RecommendedHorizontalScroll: NSScrollView, HorizontalNavigationGestureOwner {
    var ownsHorizontalNavigationGesture: Bool { true }
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? NSScrollView, scroll.documentView is NSTableView {
                    scroll.scrollWheel(with: event)
                    return
                }
                ancestor = view.superview
            }
        }
        super.scrollWheel(with: event)
    }
}

@MainActor final class RecommendedNativeShelf: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("RecommendedShelf")
    let collection = NSCollectionView()
    private let scroll = RecommendedHorizontalScroll()
    private let flow = NSCollectionViewFlowLayout()
    private let header = NSHostingView(rootView: AnyView(EmptyView()))
    private var shelf: RecommendedShelf?
    private weak var player: PlayerViewModel?
    private weak var router: NavigationRouter?
    private var offsetChanged: ((CGFloat) -> Void)?
    private var pendingOffset: CGFloat?
    private var applying = false
    private(set) var configuredItemCount = 0
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        header.sizingOptions = []
        addSubview(header)
        flow.scrollDirection = .horizontal
        flow.minimumInteritemSpacing = 6
        flow.minimumLineSpacing = 14
        flow.sectionInset = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        collection.collectionViewLayout = flow
        collection.backgroundColors = [.clear]
        collection.isSelectable = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(RecommendedHostedItem.self, forItemWithIdentifier: RecommendedHostedItem.identifier)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = collection
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func layout() {
        super.layout()
        guard let shelf else { return }
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 22)
        scroll.frame = NSRect(x: 0, y: 28, width: bounds.width, height: shelf.contentHeight)
        if let pendingOffset {
            self.pendingOffset = nil
            collection.layoutSubtreeIfNeeded()
            let maximum = max(0, flow.collectionViewContentSize.width - scroll.contentView.bounds.width)
            scroll.contentView.scroll(to: NSPoint(x: min(maximum, max(0, pendingOffset)), y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            applying = false
        }
    }
    func configure(shelf: RecommendedShelf, player: PlayerViewModel, router: NavigationRouter?, offset: CGFloat,
                   offsetChanged: @escaping (CGFloat) -> Void) {
        self.shelf = shelf; self.player = player; self.router = router
        self.offsetChanged = offsetChanged
        applying = true
        pendingOffset = offset
        flow.itemSize = NSSize(width: shelf.isArtist ? 86 : 270, height: shelf.isArtist ? 118 : 168)
        flow.minimumLineSpacing = shelf.isArtist ? 16 : 14
        header.rootView = AnyView(RecommendedShelfHeader(shelf: shelf, player: player, router: router).preferredColorScheme(.dark))
        collection.setAccessibilityLabel(shelf.title)
        collection.reloadData()
        needsLayout = true
    }
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { shelf?.items.count ?? 0 }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: RecommendedHostedItem.identifier, for: indexPath) as! RecommendedHostedItem
        if let shelf, shelf.items.indices.contains(indexPath.item), let player {
            configuredItemCount += 1
            item.configure(item: shelf.items[indexPath.item], player: player, router: router)
        }
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        guard let item = item as? RecommendedHostedItem, !item.hasContent,
              let shelf, shelf.items.indices.contains(indexPath.item), let player else { return }
        configuredItemCount += 1
        item.configure(item: shelf.items[indexPath.item], player: player, router: router)
    }
    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        (item as? RecommendedHostedItem)?.suspend()
    }
    func suspend() {
        for case let item as RecommendedHostedItem in collection.visibleItems() { item.suspend() }
        header.rootView = AnyView(EmptyView())
        player = nil; router = nil; offsetChanged = nil
    }
    @objc private func scrolled() {
        guard !applying else { return }
        offsetChanged?(scroll.contentView.bounds.minX)
    }
}

@MainActor final class RecommendedHostedItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("RecommendedColumn")
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private(set) var hasContent = false
    override func loadView() { host.sizingOptions = []; view = host }
    func configure(item: RecommendedShelf.Item, player: PlayerViewModel, router: NavigationRouter?) {
        hasContent = true
        host.rootView = AnyView(RecommendedShelfItemContent(item: item, player: player, router: router).preferredColorScheme(.dark))
    }
    func suspend() { hasContent = false; host.rootView = AnyView(EmptyView()) }
    override func prepareForReuse() { super.prepareForReuse(); suspend() }
}

private struct RecommendedShelfHeader: View {
    let shelf: RecommendedShelf
    let player: PlayerViewModel
    let router: NavigationRouter?
    var body: some View {
        HStack {
            Text(shelf.title).font(.system(size: 14.5, weight: .bold)).foregroundStyle(.white.opacity(0.95)).lineLimit(1)
            Spacer(minLength: 8)
            if let id = shelf.browseID, !id.isEmpty, let router {
                Button {
                    player.dismissFullscreen()
                    router.navigate(to: shelf.kind == .album ? .album(browseId: id) : .artist(browseId: id))
                } label: {
                    HStack(spacing: 3) {
                        Text(L10n.text(shelf.kind == .album ? "detail.viewAlbum" : "detail.viewArtist")).font(.system(size: 11.5, weight: .medium))
                        Image(systemName: "chevron.right").font(.system(size: 9.5, weight: .semibold))
                    }
                }.buttonStyle(.plain).foregroundStyle(.white)
            }
        }
    }
}

private struct RecommendedShelfItemContent: View {
    let item: RecommendedShelf.Item
    let player: PlayerViewModel
    let router: NavigationRouter?
    var body: some View {
        switch item {
        case .songs(let songs):
            VStack(spacing: 6) {
                ForEach(songs) { song in RecommendedTrackRow(track: song.track, viewModel: player, router: router) }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .artist(let card):
            RecommendedArtistCard(card: card) {
                guard let router else { return }
                player.dismissFullscreen()
                router.navigate(to: .artist(browseId: card.id))
            }
            .browseCardContextMenu(card: card, player: player, router: router, core: player.rustCore, origin: .recommendations)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
