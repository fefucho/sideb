import AppKit
import SwiftUI
import SideBCore

struct ExploreCatalogHeaderIdentity: Equatable {
    let route: ExploreRoute
    let session: Int
    let loading: Bool
    let error: String?
    let empty: Bool
}

/// One native viewport, with flat item identities and the same recycled controls
/// and image lifecycle as Home. SwiftUI hosts only the page header, never albums.
struct ExploreCatalogGridView: NSViewRepresentable {
    @Environment(\.sideBGesturePreviewVisible) var gesturePreviewVisible
    enum Axis { case vertical, horizontal }
    let cards: [BrowseCardRecord]
    let route: ExploreRoute
    let sessionRevision: Int
    var axis: Axis = .vertical
    var header: AnyView? = nil
    var headerIdentity: ExploreCatalogHeaderIdentity? = nil
    var isObscured = false
    var queueContext: QueueContext? = nil
    var isPlaying = false
    var loadingAlbumID: String? = nil
    var loadingPlaylistID: String? = nil
    let onOpen: (BrowseCardRecord) -> Void
    let onPlay: (BrowseCardRecord) -> Void
    let menuProvider: (BrowseCardRecord) -> NSMenu?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSScrollView { makeScrollView(coordinator: context.coordinator) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        // FIX-102: measure the viewport, without traversing the album document.
        CGSize(width: proposal.width ?? 800, height: proposal.height ?? (axis == .horizontal ? 258 : 600))
    }

    func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scroll = axis == .vertical ? HomeFeedScrollView() : NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = axis == .vertical
        scroll.hasHorizontalScroller = axis == .horizontal
        if axis == .horizontal { scroll.scrollerStyle = .overlay }
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = axis == .horizontal ? .allowed : .none
        scroll.verticalScrollElasticity = axis == .vertical ? .allowed : .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: axis == .vertical ? 140 : 0, right: 0)
        scroll.isHidden = isObscured && !gesturePreviewVisible

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = axis == .vertical ? .vertical : .horizontal
        layout.minimumInteritemSpacing = 20
        layout.minimumLineSpacing = axis == .vertical ? 26 : 18
        let collection = HomeNativeCollectionView()
        collection.collectionViewLayout = layout
        collection.backgroundColors = [.clear]
        collection.isSelectable = true
        collection.allowsMultipleSelection = false
        collection.autoresizingMask = axis == .vertical ? [.width] : [.height]
        collection.register(HomeCollectionItem.self, forItemWithIdentifier: HomeCollectionItem.identifier)
        collection.register(ExploreCatalogHeaderView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                            withIdentifier: ExploreCatalogHeaderView.identifier)
        collection.dataSource = coordinator
        collection.delegate = coordinator
        collection.setAccessibilityLabel(axis == .vertical ? "Catálogo de Explorar" : "Lanzamientos destacados")
        collection.onActivateSelection = { [weak coordinator] in coordinator?.open(at: $0) }
        collection.onHoverPosition = { [weak coordinator] in coordinator?.updateHover(at: $0) }
        collection.onViewportMoved = { [weak coordinator] in coordinator?.scheduleHoverUpdate() }
        scroll.documentView = collection
        coordinator.collection = collection
        coordinator.scroll = scroll
        coordinator.layout = layout
        if let viewport = scroll as? HomeFeedScrollView {
            viewport.onViewportLayout = { [weak coordinator] in coordinator?.updateGeometry() }
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.boundsChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        coordinator.updateGeometry()
        collection.reloadData()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) { updateScrollView(scroll, coordinator: context.coordinator) }

    func updateScrollView(_ scroll: NSScrollView, coordinator: Coordinator) {
        let old = coordinator.parent
        coordinator.parent = self
        guard let collection = coordinator.collection else { return }
        let reset = old.route != route || old.sessionRevision != sessionRevision
        scroll.isHidden = isObscured && !gesturePreviewVisible
        if old.isObscured != isObscured {
            coordinator.updateHover(at: nil)
            for case let item as HomeCollectionItem in collection.visibleItems() { item.content.setFeedVisible(!isObscured) }
        }
        if reset || old.cards.map(\.exploreIdentity) != cards.map(\.exploreIdentity) {
            coordinator.updateHover(at: nil)
            collection.selectionIndexPaths = []
            collection.reloadData()
        } else if old.cards != cards {
            coordinator.configureVisibleItems() // Metadata refresh keeps item/control/image identities.
        }
        if reset || old.headerIdentity != headerIdentity {
            coordinator.updateHeader()
        }
        if old.queueContext != queueContext || old.isPlaying != isPlaying ||
            old.loadingAlbumID != loadingAlbumID || old.loadingPlaylistID != loadingPlaylistID {
            coordinator.updateVisiblePlayback()
        }
        coordinator.updateGeometry()
        if reset {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        (scroll as? HomeFeedScrollView)?.onViewportLayout = nil
        coordinator.updateHover(at: nil)
        if let collection = coordinator.collection {
            for case let item as HomeCollectionItem in collection.visibleItems() { item.content.prepareForReuse() }
            collection.dataSource = nil
            collection.delegate = nil
            collection.onActivateSelection = nil
            collection.onHoverPosition = nil
            collection.onViewportMoved = nil
        }
        coordinator.collection = nil
        coordinator.scroll = nil
        coordinator.headerView = nil
    }

    @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: ExploreCatalogGridView
        weak var collection: HomeNativeCollectionView?
        weak var scroll: NSScrollView?
        weak var layout: NSCollectionViewFlowLayout?
        weak var headerView: ExploreCatalogHeaderView?
        private weak var hoveredItem: HomeCollectionItem?
        private var lastWidth: CGFloat = -1
        private var headerHeight: CGFloat = 280
        private var hoverUpdateScheduled = false
        private(set) var configuredItems = 0

        init(parent: ExploreCatalogGridView) { self.parent = parent }
        deinit { NotificationCenter.default.removeObserver(self) }

        func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { parent.cards.count }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: HomeCollectionItem.identifier, for: indexPath) as! HomeCollectionItem
            configure(item, at: indexPath)
            return item
        }

        func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: String,
                            at indexPath: IndexPath) -> NSView {
            let view = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: ExploreCatalogHeaderView.identifier,
                                                           for: indexPath) as! ExploreCatalogHeaderView
            headerView = view
            updateHeader()
            return view
        }

        func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
                            forRepresentedObjectAt indexPath: IndexPath) {
            guard let item = item as? HomeCollectionItem else { return }
            configure(item, at: indexPath)
            item.content.setFeedVisible(!parent.isObscured)
        }

        func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem,
                            forRepresentedObjectAt indexPath: IndexPath) {
            guard let item = item as? HomeCollectionItem else { return }
            if hoveredItem === item { updateHover(at: nil) }
            // Cancel this consumer and animations immediately, including prepared offscreen cells.
            item.content.setFeedVisible(false)
            item.content.prepareForReuse()
        }

        private func card(at indexPath: IndexPath) -> BrowseCardRecord? {
            guard indexPath.section == 0, parent.cards.indices.contains(indexPath.item) else { return nil }
            return parent.cards[indexPath.item]
        }

        func configure(_ item: HomeCollectionItem, at indexPath: IndexPath) {
            guard let card = card(at: indexPath) else { return }
            configuredItems += 1
            let record = HomeItemRecord(kind: card.kind == "video" ? "song" : card.kind, id: card.id, title: card.title,
                subtitle: card.subtitle, thumbnail: card.thumbnail, duration: card.duration,
                artists: nil, artistId: nil, album: nil, albumId: nil, artistRuns: [], explicit: false)
            item.content.configure(record: record, style: .largeCard, currentTrackID: nil, isPlaying: parent.isPlaying,
                queueContext: parent.queueContext,
                onCard: { [weak self] in self?.open(card) },
                onCover: { [weak self] in self?.open(card) },
                onTitle: { [weak self] in self?.open(card) },
                onArtist: {}, onAlbum: {},
                onDirectPlay: { [weak self] in
                    guard let self, !self.parent.isObscured, !self.isLoading(card) else { return }
                    self.parent.onPlay(card)
                }, menuProvider: { [weak self] in
                    guard let self, !self.parent.isObscured else { return nil }
                    return self.parent.menuProvider(card)
                })
            item.content.setLoading(isLoading(card))
            item.content.setFeedVisible(!parent.isObscured)
        }

        private func open(_ card: BrowseCardRecord) { if !parent.isObscured { parent.onOpen(card) } }
        func open(at indexPath: IndexPath) { if let card = card(at: indexPath) { open(card) } }

        func configureVisibleItems() {
            guard let collection else { return }
            for index in collection.indexPathsForVisibleItems() {
                if let item = collection.item(at: index) as? HomeCollectionItem { configure(item, at: index) }
            }
        }

        private func isLoading(_ card: BrowseCardRecord) -> Bool {
            if card.kind == "album" {
                return parent.loadingAlbumID.map(MenuIDNormalizer.normalize) == MenuIDNormalizer.normalize(card.id)
            }
            if card.kind == "playlist" {
                return parent.loadingPlaylistID.map(MenuIDNormalizer.canonicalPlaylistId) == MenuIDNormalizer.canonicalPlaylistId(card.id)
            }
            return false
        }

        func updateVisiblePlayback() {
            guard let collection else { return }
            for index in collection.indexPathsForVisibleItems() {
                guard let item = collection.item(at: index) as? HomeCollectionItem, let card = card(at: index) else { continue }
                item.content.updatePlayback(currentTrackID: nil, isPlaying: parent.isPlaying, queueContext: parent.queueContext)
                item.content.setLoading(isLoading(card))
            }
        }

        func updateHeader() {
            guard let content = parent.header else { return }
            let identity = parent.headerIdentity
            headerView?.configure(content: content) { [weak self] height in
                guard let self, self.parent.headerIdentity == identity,
                      height > 0, abs(self.headerHeight - height) > 0.5 else { return }
                self.headerHeight = ceil(height)
                self.lastWidth = -1
                self.updateGeometry()
            }
        }

        func updateGeometry() {
            guard let scroll, let collection, let layout else { return }
            let width = max(1, scroll.contentView.bounds.width)
            guard abs(lastWidth - width) > 0.5 else { return }
            lastWidth = width
            if parent.axis == .vertical {
                let contentWidth = min(1400, width)
                let available = max(1, contentWidth - 64)
                let columns = max(1, Int((available + 20) / 180))
                let itemWidth = min(230, floor((available - CGFloat(columns - 1) * 20) / CGFloat(columns)))
                let sideInset = max(0, (width - contentWidth) / 2) + 32
                layout.sectionInset = NSEdgeInsets(top: 0, left: sideInset, bottom: 0, right: sideInset)
                layout.itemSize = NSSize(width: max(1, itemWidth), height: max(1, itemWidth) + HomeItemView.largeCardTextHeight)
                layout.headerReferenceSize = parent.header == nil ? .zero : NSSize(width: width, height: headerHeight)
                collection.frame.size.width = width
            } else {
                layout.sectionInset = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
                layout.itemSize = NSSize(width: 164, height: 164 + HomeItemView.largeCardTextHeight)
                collection.frame.size.height = 164 + HomeItemView.largeCardTextHeight + 6
            }
            layout.invalidateLayout()
        }

        @objc func boundsChanged(_ notification: Notification) {
            updateGeometry()
            scheduleHoverUpdate()
        }

        func scheduleHoverUpdate() {
            guard !hoverUpdateScheduled else { return }
            hoverUpdateScheduled = true
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                self.hoverUpdateScheduled = false
                guard let collection = self.collection, let window = collection.window, !self.parent.isObscured else {
                    self.updateHover(at: nil); return
                }
                self.updateHover(at: collection.convert(window.mouseLocationOutsideOfEventStream, from: nil))
            }
        }

        func updateHover(at point: NSPoint?) {
            guard let collection, let point, !parent.isObscured,
                  collection.visibleRect.contains(point), let index = collection.indexPathForItem(at: point),
                  let item = collection.item(at: index) as? HomeCollectionItem else {
                hoveredItem?.content.setHovered(false)
                hoveredItem = nil
                return
            }
            if hoveredItem !== item { hoveredItem?.content.setHovered(false); hoveredItem = item }
            item.content.setHovered(true, localPoint: item.content.convert(point, from: collection))
        }
    }
}

private struct ExploreHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

@MainActor final class ExploreCatalogHeaderView: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("ExploreCatalogHeader")
    private let host = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
    override func layout() { super.layout(); host.frame = bounds }

    func configure(content: AnyView, onHeightChanged: @escaping @MainActor (CGFloat) -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            host.rootView = AnyView(content.fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: ExploreHeaderHeightKey.self, value: geometry.size.height)
                })
                .onPreferenceChange(ExploreHeaderHeightKey.self) { height in
                    Task { @MainActor in onHeightChanged(height) }
                })
        }
    }
}
