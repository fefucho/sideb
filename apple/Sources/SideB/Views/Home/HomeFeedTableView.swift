import AppKit
import SwiftUI
import Observation
import SideBCore

/// Native viewport geometry has its own observation scope. A sidebar animation
/// changes this value without replacing the hosting root or its data snapshot.
@MainActor @Observable
final class HomeFeaturedViewport {
    var width: CGFloat = 260
}

private struct HomeFeaturedHostedContent: View {
    let viewport: HomeFeaturedViewport
    let builder: (CGFloat) -> AnyView

    var body: some View { builder(viewport.width) }
}

/// Maps scrolling intro/featured content, shelves and pagination to native rows.
struct HomeFeedRows {
    let sectionCount: Int
    let hasHeader: Bool
    let hasMore: Bool
    var hasFeatured: Bool = false
    var featuredRow: Int? { hasFeatured ? (hasHeader ? 1 : 0) : nil }
    var sectionOffset: Int { (hasHeader ? 1 : 0) + (hasFeatured ? 1 : 0) }
    var count: Int { sectionOffset + sectionCount + (hasMore ? 1 : 0) }
    var loadMoreRow: Int? { hasMore ? sectionOffset + sectionCount : nil }
    func sectionIndex(forRow row: Int) -> Int? {
        let index = row - sectionOffset
        return (0..<sectionCount).contains(index) ? index : nil
    }
}

/// El scroll vertical recicla estantes completos; cada estante recicla sus tarjetas en horizontal.
/// Así las categorías agregadas por paginación no mantienen scrollers ortogonales fuera de pantalla.
struct HomeFeedTableView: NSViewRepresentable {
    let headerContent: AnyView?
    let headerHeight: CGFloat
    let featuredContent: ((CGFloat) -> AnyView)?
    let featuredHeight: ((CGFloat) -> CGFloat)?
    var hasFeatured: Bool { featuredContent != nil && featuredHeight != nil }
    let topContentInset: CGFloat
    let sections: [HomeSectionPresentation]
    let isObscured: Bool
    let revision: UInt64
    let selectedChip: String?
    let hasMore: Bool
    let isLoadingMore: Bool
    let loadMoreMessage: String?
    private var hasPaginationFooter: Bool { hasMore || loadMoreMessage != nil }
    let currentTrackID: String?
    let currentAlbumBrowseId: String?
    let currentPlaylistBrowseId: String?
    let isPlaying: Bool
    let queueContext: QueueContext?
    let player: PlayerViewModel
    let router: NavigationRouter?
    let onNavigate: (PageDestination) -> Void
    let onLoadMore: () -> Void

    init(
        headerContent: AnyView? = nil,
        headerHeight: CGFloat = 0,
        featuredContent: ((CGFloat) -> AnyView)? = nil,
        featuredHeight: ((CGFloat) -> CGFloat)? = nil,
        topContentInset: CGFloat = 0,
        sections: [HomeSectionPresentation],
        isObscured: Bool,
        revision: UInt64,
        selectedChip: String?,
        hasMore: Bool,
        isLoadingMore: Bool,
        loadMoreMessage: String? = nil,
        currentTrackID: String?,
        currentAlbumBrowseId: String? = nil,
        currentPlaylistBrowseId: String? = nil,
        isPlaying: Bool,
        queueContext: QueueContext? = nil,
        player: PlayerViewModel,
        router: NavigationRouter?,
        onNavigate: @escaping (PageDestination) -> Void,
        onLoadMore: @escaping () -> Void
    ) {
        self.headerContent = headerContent
        self.headerHeight = headerHeight
        self.featuredContent = featuredContent
        self.featuredHeight = featuredHeight
        self.topContentInset = topContentInset
        self.sections = sections
        self.isObscured = isObscured
        self.revision = revision
        self.selectedChip = selectedChip
        self.hasMore = hasMore
        self.isLoadingMore = isLoadingMore
        self.loadMoreMessage = loadMoreMessage
        self.currentTrackID = currentTrackID
        self.currentAlbumBrowseId = currentAlbumBrowseId
        self.currentPlaylistBrowseId = currentPlaylistBrowseId
        self.isPlaying = isPlaying
        self.queueContext = queueContext
        self.player = player
        self.router = router
        self.onNavigate = onNavigate
        self.onLoadMore = onLoadMore
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        makeNativeScrollView(coordinator: context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        // The viewport fills the parent's proposal. Measuring the document's
        // intrinsic size walks every mounted shelf/hosting subtree on scroll.
        // Use the same sizing contract as NativeTrackTableView.
        CGSize(width: proposal.width ?? 800, height: proposal.height ?? 600)
    }

    func makeNativeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scroll = HomeFeedScrollView()
        scroll.isHidden = isObscured
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScroller = nil
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .allowed
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(
            top: topContentInset + (headerContent == nil && !hasFeatured ? 10 : 0), left: 0, bottom: 120, right: 0
        )

        let table = NSTableView()
        table.headerView = nil
        table.style = .plain
        table.usesAutomaticRowHeights = false
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.delegate = coordinator
        table.dataSource = coordinator
        table.setAccessibilityLabel("Recomendaciones de Inicio")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("HomeShelfColumn"))
        column.minWidth = 260
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        scroll.documentView = table
        scroll.onViewportLayout = { [weak coordinator] in coordinator?.updateFeatured() }
        coordinator.table = table
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.boundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )
        table.reloadData()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top))
        scroll.reflectScrolledClipView(scroll.contentView)
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        if let table = scroll.documentView as? NSTableView {
            table.delegate = nil
            table.dataSource = nil
        }
        (scroll as? HomeFeedScrollView)?.onViewportLayout = nil
        coordinator.table = nil
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        updateNativeScrollView(scroll, coordinator: context.coordinator)
    }

    func updateNativeScrollView(_ scroll: NSScrollView, coordinator: Coordinator) {
        let old = coordinator.parent
        coordinator.parent = self
        if old.isObscured != isObscured {
            if isObscured { coordinator.clearHover() }
            // AppKit tooltips and tracking areas outlive SwiftUI's opacity/hit-testing state.
            scroll.isHidden = isObscured
        }
        guard let table = scroll.documentView as? NSTableView else { return }
        coordinator.setFeedVisible(!isObscured)
        coordinator.updateHeader()
        coordinator.updateFeatured(force: true)
        let newTopInset = topContentInset + (headerContent == nil && !hasFeatured ? 10 : 0)
        let oldTopInset = scroll.contentInsets.top
        let wasAtTop = abs(scroll.contentView.bounds.minY + oldTopInset) < 0.5
        if oldTopInset != newTopInset {
            scroll.contentInsets.top = newTopInset
            if wasAtTop {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: -newTopInset))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        if headerContent != nil, old.headerHeight != headerHeight {
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: 0))
        }
        let contextChanged = coordinator.lastQueueContext != queueContext
        coordinator.lastQueueContext = queueContext
        let compact = scroll.contentView.bounds.width < 760
        if old.hasPaginationFooter != hasPaginationFooter || old.selectedChip != selectedChip ||
            coordinator.wasCompact != compact || (old.headerContent == nil) != (headerContent == nil) || old.hasFeatured != hasFeatured {
            coordinator.wasCompact = compact
            table.reloadData()
            if old.selectedChip != selectedChip {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            coordinator.scheduleHoverUpdate()
        } else {
            // Featured capacity changes also advance contentRevision. Reload
            // only changed shelves: replacing every row tears down mounted
            // controls even when the change is confined to the featured panel.
            if old.revision != revision, old.sections != sections {
                if old.sections.count == sections.count {
                    let changedRows = IndexSet(sections.indices.compactMap { index in
                        old.sections[index] == sections[index] ? nil : index + coordinator.rows.sectionOffset
                    })
                    table.reloadData(forRowIndexes: changedRows, columnIndexes: IndexSet(integer: 0))
                    table.noteHeightOfRows(withIndexesChanged: changedRows)
                } else {
                    table.reloadData()
                }
                coordinator.scheduleHoverUpdate()
            }
            if old.currentTrackID != currentTrackID ||
               old.currentAlbumBrowseId != currentAlbumBrowseId ||
               old.currentPlaylistBrowseId != currentPlaylistBrowseId ||
               old.isPlaying != isPlaying || contextChanged {
                coordinator.updateVisiblePlayback()
            }
            if old.hasMore != hasMore || old.isLoadingMore != isLoadingMore || old.loadMoreMessage != loadMoreMessage {
                coordinator.updateLoadMore()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: HomeFeedTableView
        weak var table: NSTableView?
        var wasCompact = false
        private var headerHost: NSHostingView<AnyView>?
        private var featuredHost: NSHostingView<AnyView>?
        let featuredViewport = HomeFeaturedViewport()
        private var measuredFeaturedHeight: CGFloat = -1
        var rows: HomeFeedRows {
            HomeFeedRows(sectionCount: parent.sections.count, hasHeader: parent.headerContent != nil,
                         hasMore: parent.hasPaginationFooter, hasFeatured: parent.hasFeatured)
        }

        func updateHeader() {
            if let headerContent = parent.headerContent {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { headerHost?.rootView = headerContent }
            }
        }
        private var viewportWidth: CGFloat {
            max(260, table?.enclosingScrollView?.contentView.bounds.width ?? table?.bounds.width ?? 260)
        }

        /// Geometry belongs to the native viewport, including every intermediate sidebar width.
        func updateFeatured(force: Bool = false) {
            guard let table, let row = rows.featuredRow, let height = parent.featuredHeight else { return }
            let width = viewportWidth
            let nextHeight = height(width)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if featuredViewport.width != width { featuredViewport.width = width }
                if force, let host = featuredHost, let builder = parent.featuredContent {
                    host.rootView = AnyView(HomeFeaturedHostedContent(viewport: featuredViewport, builder: builder))
                }
            }
            let loadedRow = table.numberOfRows == rows.count && row < table.numberOfRows
            // The delegate can build a view before AppKit invalidates its cached row geometry.
            // Compare the table's actual row too, especially on remount after navigation.
            let cachedHeightDiffers = loadedRow && abs(table.rect(ofRow: row).height - nextHeight) > 0.5
            if nextHeight != measuredFeaturedHeight || cachedHeightDiffers {
                measuredFeaturedHeight = nextHeight
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    context.allowsImplicitAnimation = false
                    if loadedRow {
                        table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
                    }
                }
            }
        }
        private var horizontalOffsets: [String: CGFloat] = [:]
        private weak var hoveredShelf: HomeShelfRowView?
        private var hoverUpdateScheduled = false
        fileprivate var lastQueueContext: QueueContext?

        init(parent: HomeFeedTableView) {
            self.parent = parent
            self.lastQueueContext = parent.queueContext
        }
        deinit { NotificationCenter.default.removeObserver(self) }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            if rows.hasHeader, row == 0 { return parent.headerHeight }
            if row == rows.featuredRow { return parent.featuredHeight?(viewportWidth) ?? 0 }
            guard let index = rows.sectionIndex(forRow: row) else { return 68 }
            let headerHeight: CGFloat = 38
            let bottomSpacing: CGFloat = 16
            if parent.sections[index].style == .compactSong {
                return headerHeight + 230 + bottomSpacing
            }
            let availableWidth = tableView.enclosingScrollView?.contentView.bounds.width ?? tableView.bounds.width
            let artworkWidth: CGFloat = availableWidth < 760 ? 120 : 140
            return headerHeight + artworkWidth + HomeItemView.largeCardTextHeight + bottomSpacing
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            if rows.hasHeader, row == 0, let headerContent = parent.headerContent {
                if headerHost == nil {
                    headerHost = NSHostingView(rootView: headerContent)
                    headerHost?.sizingOptions = []
                }
                headerHost?.rootView = headerContent
                return headerHost
            }
            if row == rows.featuredRow, let builder = parent.featuredContent {
                let width = viewportWidth
                featuredViewport.width = width
                if featuredHost == nil {
                    featuredHost = NSHostingView(rootView: AnyView(HomeFeaturedHostedContent(viewport: featuredViewport, builder: builder)))
                    featuredHost?.sizingOptions = []
                }
                return featuredHost
            }
            if row == rows.loadMoreRow {
                let view = (tableView.makeView(withIdentifier: HomeLoadMoreRowView.identifier, owner: nil) as? HomeLoadMoreRowView)
                    ?? HomeLoadMoreRowView()
                view.configure(loading: parent.isLoadingMore, hasMore: parent.hasMore,
                               message: parent.loadMoreMessage) { [weak self] in self?.parent.onLoadMore() }
                return view
            }

            guard let index = rows.sectionIndex(forRow: row) else { return nil }
            let section = parent.sections[index]
            let view = (tableView.makeView(withIdentifier: HomeShelfRowView.identifier, owner: nil) as? HomeShelfRowView)
                ?? HomeShelfRowView()
            view.configure(
                section: section,
                horizontalOffset: horizontalOffsets[section.id] ?? 0,
                onHorizontalOffset: { [weak self, id = section.id] offset in self?.horizontalOffsets[id] = offset },
                onMore: { [weak self, id = section.id] in self?.navigateMore(sectionID: id) },
                onActivate: { [weak self] item in self?.activate(itemID: item.id, fromCover: true) },
                onConfigure: { [weak self] cell, item in self?.configure(cell, item: item) }
            )
            return view
        }

        func updateVisiblePlayback() {
            lastQueueContext = parent.queueContext
            guard let table else { return }
            let visible = table.rows(in: table.visibleRect)
            guard visible.location != NSNotFound else { return }
            for row in visible.location..<NSMaxRange(visible) where rows.sectionIndex(forRow: row) != nil {
                (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? HomeShelfRowView)?
                    .updateVisiblePlayback(
                        trackID: parent.currentTrackID,
                        albumBrowseId: parent.currentAlbumBrowseId ?? parent.player.currentAlbumBrowseId,
                        playlistBrowseId: parent.currentPlaylistBrowseId ?? parent.player.currentPlaylistBrowseId,
                        isPlaying: parent.isPlaying,
                        queueContext: parent.queueContext
                    )
            }
        }

        func setFeedVisible(_ visible: Bool) {
            guard let table else { return }
            let rows = table.rows(in: table.visibleRect)
            guard rows.location != NSNotFound else { return }
            for row in rows.location..<NSMaxRange(rows) {
                (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? HomeShelfRowView)?
                    .setFeedVisible(visible)
            }
        }

        func updateLoadMore() {
            guard let table, let row = rows.loadMoreRow else { return }
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? HomeLoadMoreRowView)?
                .configure(loading: parent.isLoadingMore, hasMore: parent.hasMore,
                           message: parent.loadMoreMessage) { [weak self] in self?.parent.onLoadMore() }
        }

        @objc func boundsChanged(_ notification: Notification) {
            updateFeatured()
            updateRowHeightsIfCompactModeChanged()
            scheduleHoverUpdate()
        }

        private func updateRowHeightsIfCompactModeChanged() {
            guard let table,
                  let width = table.enclosingScrollView?.contentView.bounds.width else { return }
            let compact = width < 760
            guard compact != wasCompact else { return }
            wasCompact = compact
            let rowCount = numberOfRows(in: table)
            guard rowCount > 0, table.numberOfRows == rowCount else { return }
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rowCount))
        }

        func scheduleHoverUpdate() {
            guard !hoverUpdateScheduled else { return }
            hoverUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.hoverUpdateScheduled = false
                self.updateHoverAtPointer()
            }
        }

        private func updateHoverAtPointer() {
            setFeedVisible(!parent.isObscured)
            guard !parent.isObscured else { clearHover(); return }
            guard let table, let window = table.window else { return }
            let point = table.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let row = table.visibleRect.contains(point) ? table.row(at: point) : -1
            let next = rows.sectionIndex(forRow: row) != nil
                ? table.view(atColumn: 0, row: row, makeIfNecessary: false) as? HomeShelfRowView
                : nil
            if hoveredShelf !== next { hoveredShelf?.clearHover() }
            hoveredShelf = next
            next?.updateHoverAtPointer()
        }

        func clearHover() {
            hoveredShelf?.clearHover()
            hoveredShelf = nil
        }

        private func item(for id: String) -> HomeItemPresentation? {
            for section in parent.sections {
                if let item = section.items.first(where: { $0.id == id }) { return item }
            }
            return nil
        }

        private func configure(_ cell: HomeCollectionItem, item: HomeItemPresentation) {
            let id = item.id
            cell.content.configure(
                record: item.record,
                style: item.style,
                currentTrackID: parent.currentTrackID,
                currentAlbumBrowseId: parent.currentAlbumBrowseId ?? parent.player.currentAlbumBrowseId,
                currentPlaylistBrowseId: parent.currentPlaylistBrowseId ?? parent.player.currentPlaylistBrowseId,
                isPlaying: parent.isPlaying,
                queueContext: parent.queueContext,
                onCard: { [weak self] in self?.activate(itemID: id, fromCover: true) },
                onCover: { [weak self] in self?.activate(itemID: id, fromCover: true) },
                onTitle: { [weak self] in self?.activate(itemID: id, fromCover: true) },
                onArtist: { [weak self] in self?.navigateArtist(itemID: id) },
                onAlbum: { [weak self] in self?.navigateAlbum(itemID: id) },
                onDirectPlay: { [weak self] in self?.handleDirectPlay(itemID: id) },
                menuProvider: { [weak self, record = item.record] in self?.menu(record: record) }
            )
        }

        private func handleDirectPlay(itemID: String) {
            guard let record = item(for: itemID)?.record else { return }
            switch record.kind {
            case "song":
                parent.player.activateMediaRadio(SongItemRecord(fromHomeItem: record))
            case "album":
                parent.player.activateMediaCollection(id: record.id, kind: "album")
            case "playlist":
                parent.player.activateMediaCollection(id: record.id, kind: "playlist")
            case "artist":
                parent.player.startRadioForCollection(
                    id: record.id,
                    title: record.title,
                    prefix: "RDAMVM",
                    directRadioId: nil
                )
            default:
                break
            }
        }

        private func activate(itemID: String, fromCover: Bool) {
            guard let record = item(for: itemID)?.record else { return }
            if record.kind == "song" {
                parent.player.activateMediaRadio(SongItemRecord(fromHomeItem: record))
                return
            }
            switch record.kind {
            case "album": parent.onNavigate(.album(browseId: record.id))
            case "artist": parent.onNavigate(.artist(browseId: record.id))
            default: parent.onNavigate(.playlist(browseId: record.id))
            }
        }

        private func navigateArtist(itemID: String) {
            guard let record = item(for: itemID)?.record,
                  let id = record.artistId ?? record.artistRuns.first(where: { $0.id?.isEmpty == false })?.id,
                  !id.isEmpty else { return }
            parent.onNavigate(.artist(browseId: id))
        }

        private func navigateAlbum(itemID: String) {
            guard let record = item(for: itemID)?.record, let id = record.albumId, !id.isEmpty else { return }
            parent.onNavigate(.album(browseId: id))
        }

        private func navigateMore(sectionID: String) {
            guard let section = parent.sections.first(where: { $0.id == sectionID }),
                  let id = section.moreBrowseId else { return }
            if id.hasPrefix("MPRE") {
                parent.onNavigate(.album(browseId: id))
            } else if id.hasPrefix("UC") {
                parent.onNavigate(.artist(browseId: id))
            } else if !id.hasPrefix("FE") {
                parent.onNavigate(.playlist(browseId: id))
            }
        }

        private func menu(record: HomeItemRecord) -> NSMenu? {
            let factory = AppContextMenuFactory.shared
            let core = parent.player.rustCore
            switch record.kind {
            case "song":
                return factory.buildSongNSMenu(song: SongItemRecord(fromHomeItem: record), player: parent.player,
                                               router: parent.router, core: core, origin: .home)
            case "album":
                return factory.buildAlbumNSMenu(browseId: record.id, playlistId: nil, title: record.title,
                                                artist: record.subtitle, thumbnail: record.thumbnail, inLibrary: nil,
                                                origin: .home, player: parent.player, router: parent.router, core: core)
            case "artist":
                return factory.buildArtistNSMenu(channelId: record.id, name: record.title,
                                                 thumbnail: record.thumbnail, radioPlaylistId: nil, origin: .home,
                                                 player: parent.player, router: parent.router, core: core)
            default:
                return factory.buildPlaylistNSMenu(id: record.id, title: record.title, subtitle: record.subtitle,
                                                   thumbnail: record.thumbnail, origin: .home, player: parent.player,
                                                   router: parent.router, core: core)
            }
        }
    }
}

@MainActor
private final class HomeShelfScrollView: HomeFeedScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            var ancestor = superview
            while let view = ancestor {
                if let outerScroll = view as? NSScrollView,
                   outerScroll.documentView is NSTableView {
                    outerScroll.scrollWheel(with: event)
                    return
                }
                ancestor = view.superview
            }
        }
        super.scrollWheel(with: event)
    }
}

@MainActor
final class HomeShelfRowView: NSView, NSCollectionViewDataSource {
    static let identifier = NSUserInterfaceItemIdentifier("HomeShelfRow")

    private let header = HomeSectionHeaderView()
    private let scroll = HomeShelfScrollView()
    private let collection = HomeNativeCollectionView()
    private let flow = NSCollectionViewFlowLayout()
    private var section: HomeSectionPresentation?
    private var pendingHorizontalOffset: CGFloat?
    private var isApplyingSection = false
    private var onHorizontalOffset: ((CGFloat) -> Void)?
    private var onActivate: ((HomeItemPresentation) -> Void)?
    private var onConfigure: ((HomeCollectionItem, HomeItemPresentation) -> Void)?
    private weak var hoveredItem: HomeCollectionItem?
    private var feedVisible = true
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        addSubview(header)
        flow.scrollDirection = .horizontal
        flow.minimumInteritemSpacing = 1
        flow.minimumLineSpacing = 16
        flow.sectionInset = NSEdgeInsets(top: 0, left: 28, bottom: 0, right: 28)
        collection.collectionViewLayout = flow
        collection.backgroundColors = [.clear]
        collection.isSelectable = true
        collection.dataSource = self
        collection.register(HomeCollectionItem.self, forItemWithIdentifier: HomeCollectionItem.identifier)
        collection.onActivateSelection = { [weak self] indexPath in
            guard let self, let section = self.section,
                  section.items.indices.contains(indexPath.item) else { return }
            self.onActivate?(section.items[indexPath.item])
        }
        collection.onHoverPosition = { [weak self] point in self?.updateHover(at: point) }
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.horizontalScroller = nil
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.documentView = collection
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(horizontalBoundsChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func layout() {
        super.layout()
        header.frame = NSRect(x: 28, y: 0, width: max(0, bounds.width - 56), height: 38)
        let shelfHeight: CGFloat = section?.style == .compactSong ? 230 :
            (bounds.width < 760 ? 120 : 140) + HomeItemView.largeCardTextHeight
        scroll.frame = NSRect(x: 0, y: 38, width: bounds.width, height: shelfHeight)
        let itemSize = section?.style == .compactSong
            ? NSSize(width: bounds.width < 760 ? 286 : 330, height: 56)
            : NSSize(width: bounds.width < 760 ? 120 : 140, height: shelfHeight)
        if flow.itemSize != itemSize {
            flow.itemSize = itemSize
            flow.invalidateLayout()
        }
        if let pendingHorizontalOffset {
            self.pendingHorizontalOffset = nil
            collection.layoutSubtreeIfNeeded()
            let maxOffset = max(0, flow.collectionViewContentSize.width - scroll.contentView.bounds.width)
            scroll.contentView.scroll(to: NSPoint(x: min(maxOffset, max(0, pendingHorizontalOffset)), y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            isApplyingSection = false
            onHorizontalOffset?(scroll.contentView.bounds.minX)
        }
    }

    func configure(
        section: HomeSectionPresentation,
        horizontalOffset: CGFloat,
        onHorizontalOffset: @escaping (CGFloat) -> Void,
        onMore: @escaping () -> Void,
        onActivate: @escaping (HomeItemPresentation) -> Void,
        onConfigure: @escaping (HomeCollectionItem, HomeItemPresentation) -> Void
    ) {
        let changed = self.section != section
        let changedIdentity = self.section?.id != section.id
        self.section = section
        self.onHorizontalOffset = onHorizontalOffset
        self.onActivate = onActivate
        self.onConfigure = onConfigure
        header.configure(title: section.title, showsMore: section.isNavigableMore,
                         showsArrows: false,
                         previous: { [weak self] in self?.scrollShelf(direction: -1) },
                         next: { [weak self] in self?.scrollShelf(direction: 1) },
                         action: onMore)
        if changed {
            clearHover()
            isApplyingSection = true
            if changedIdentity {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            pendingHorizontalOffset = horizontalOffset
            collection.reloadData()
            needsLayout = true
        }
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection sectionIndex: Int) -> Int {
        section?.items.count ?? 0
    }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: HomeCollectionItem.identifier, for: indexPath) as! HomeCollectionItem
        if let section, section.items.indices.contains(indexPath.item) {
            onConfigure?(cell, section.items[indexPath.item])
        }
        cell.content.setFeedVisible(feedVisible && !cell.content.visibleRect.isEmpty)
        return cell
    }

    func updateVisiblePlayback(
        trackID: String?,
        albumBrowseId: String? = nil,
        playlistBrowseId: String? = nil,
        isPlaying: Bool,
        queueContext: QueueContext?
    ) {
        for path in collection.indexPathsForVisibleItems() {
            (collection.item(at: path) as? HomeCollectionItem)?.content.updatePlayback(
                currentTrackID: trackID,
                currentAlbumBrowseId: albumBrowseId,
                currentPlaylistBrowseId: playlistBrowseId,
                isPlaying: isPlaying,
                queueContext: queueContext
            )
        }
    }

    func setFeedVisible(_ visible: Bool) {
        feedVisible = visible
        for path in collection.indexPathsForVisibleItems() {
            guard let content = (collection.item(at: path) as? HomeCollectionItem)?.content else { continue }
            content.setFeedVisible(visible && !content.visibleRect.isEmpty)
        }
    }

    func clearHover() {
        hoveredItem?.content.setHovered(false, localPoint: nil)
        hoveredItem = nil
    }

    func updateHoverAtPointer() {
        guard let window else { clearHover(); return }
        let point = collection.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        updateHover(at: point)
    }

    private func updateHover(at point: NSPoint?) {
        for path in collection.indexPathsForVisibleItems() {
            guard let content = (collection.item(at: path) as? HomeCollectionItem)?.content else { continue }
            content.setFeedVisible(feedVisible && !content.visibleRect.isEmpty)
        }
        var next: HomeCollectionItem?
        var localPoint: NSPoint?
        if let point, collection.visibleRect.contains(point),
           let path = collection.indexPathForItem(at: point),
           let cell = collection.item(at: path) as? HomeCollectionItem {
            next = cell
            localPoint = cell.view.convert(point, from: collection)
        }
        if hoveredItem !== next {
            clearHover()
            next?.content.setHovered(true, localPoint: localPoint)
            hoveredItem = next
        } else if let next, let localPoint {
            next.content.updateHoverLocation(localPoint)
        }
    }

    @objc private func horizontalBoundsChanged(_ notification: Notification) {
        guard section != nil, !isApplyingSection else { return }
        onHorizontalOffset?(scroll.contentView.bounds.minX)
        updateHoverAtPointer()
    }

    private func scrollShelf(direction: Int) {
        guard let section, !section.items.isEmpty else { return }
        let items = collection.indexPathsForVisibleItems().map(\.item)
        let step = section.style == .compactSong ? 4 : 1
        let anchor = direction > 0 ? (items.max() ?? 0) + step : max(0, (items.min() ?? 0) - step)
        let target = min(section.items.count - 1, anchor)
        collection.scrollToItems(at: [IndexPath(item: target, section: 0)],
                                 scrollPosition: direction > 0 ? .right : .left)
    }
}

@MainActor
private final class HomeLoadMoreRowView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("HomeLoadMoreRow")
    private let button = NSButton(title: "Cargar más recomendaciones", target: nil, action: nil)
    private let messageLabel = NSTextField(labelWithString: "")
    private var action: (() -> Void)?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(loadMore)
        addSubview(button)
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.isHidden = true
        addSubview(messageLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
    override func layout() {
        super.layout()
        button.frame = NSRect(x: max(0, (bounds.width - 220) / 2), y: messageLabel.isHidden ? 14 : 30, width: 220, height: 32)
        messageLabel.frame = NSRect(x: 16, y: button.isHidden ? 24 : 6,
                                    width: max(0, bounds.width - 32), height: 20)
    }
    func configure(loading: Bool, hasMore: Bool, message: String?, action: @escaping () -> Void) {
        self.action = action
        button.title = loading ? "Cargando recomendaciones…" : "Cargar más recomendaciones"
        button.isEnabled = hasMore && !loading
        button.isHidden = !hasMore
        messageLabel.stringValue = message ?? ""
        messageLabel.isHidden = message == nil
        needsLayout = true
    }
    @objc private func loadMore() { action?() }
}
