import AppKit
import SwiftUI
import SideBCore

/// Un solo viewport vertical; los estantes horizontales son secciones del layout nativo.
struct HomeFeedCollectionView: NSViewRepresentable {
    let localizationRevision = L10n.revision
    let sections: [HomeSectionPresentation]
    let revision: UInt64
    let selectedChip: String?
    let hasMore: Bool
    let isLoadingMore: Bool
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
        sections: [HomeSectionPresentation],
        revision: UInt64,
        selectedChip: String?,
        hasMore: Bool,
        isLoadingMore: Bool,
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
        self.sections = sections
        self.revision = revision
        self.selectedChip = selectedChip
        self.hasMore = hasMore
        self.isLoadingMore = isLoadingMore
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
        let coordinator = context.coordinator
        let layout = NSCollectionViewCompositionalLayout { [weak coordinator] index, environment in
            coordinator?.layoutSection(at: index, width: environment.container.effectiveContentSize.width)
        }
        let collection = HomeNativeCollectionView()
        collection.collectionViewLayout = layout
        collection.backgroundColors = [.clear]
        collection.isSelectable = true
        collection.allowsMultipleSelection = false
        collection.delegate = coordinator
        collection.register(HomeCollectionItem.self, forItemWithIdentifier: HomeCollectionItem.identifier)
        collection.register(HomeLoadMoreItem.self, forItemWithIdentifier: HomeLoadMoreItem.identifier)
        collection.register(
            HomeSectionHeaderView.self,
            forSupplementaryViewOfKind: Coordinator.headerKind,
            withIdentifier: HomeSectionHeaderView.identifier
        )
        collection.setAccessibilityLabel(L10n.text("home.accessibility.recommendations"))
        collection.onActivateSelection = { [weak coordinator] indexPath in
            coordinator?.activate(at: indexPath)
        }
        collection.onHoverPosition = { [weak coordinator] point in
            coordinator?.updateHover(at: point)
        }
        collection.onViewportMoved = { [weak coordinator] in
            coordinator?.scheduleHoverUpdate()
        }

        let scroll = HomeFeedScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScroller = nil
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 10, left: 0, bottom: 120, right: 0)
        scroll.documentView = collection
        scroll.contentView.postsBoundsChangedNotifications = true
        coordinator.collection = collection
        coordinator.installDataSource(on: collection)
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.clipBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )
        coordinator.applyContent()
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        if let collection = scroll.documentView as? HomeNativeCollectionView {
            collection.delegate = nil
            collection.onActivateSelection = nil
            collection.onHoverPosition = nil
            collection.onViewportMoved = nil
        }
        coordinator.collection = nil
        coordinator.dataSource = nil
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let old = coordinator.parent
        coordinator.parent = self
        guard scroll.documentView is HomeNativeCollectionView else { return }
        if coordinator.localizationRevision != localizationRevision, !playerViewModelIsFullscreen {
            coordinator.localizationRevision = localizationRevision
            coordinator.updateLocalization()
        }
        if old.revision != revision || old.hasMore != hasMore {
            coordinator.applyContent()
            if old.selectedChip != selectedChip {
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        } else {
            let contextChanged = coordinator.lastQueueContext != queueContext
            coordinator.lastQueueContext = queueContext
            if old.currentTrackID != currentTrackID ||
               old.currentAlbumBrowseId != currentAlbumBrowseId ||
               old.currentPlaylistBrowseId != currentPlaylistBrowseId ||
               old.isPlaying != isPlaying || contextChanged {
                coordinator.updateVisiblePlayback()
            }
            if old.isLoadingMore != isLoadingMore {
                coordinator.updateLoadMore()
            }
        }
    }

    private var playerViewModelIsFullscreen: Bool { player.isFullscreenPresented }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDelegate {
        static let headerKind = "HomeSectionHeader"
        static let footerSection = "__home_pagination__"
        static let footerItem = "__home_load_more__"

        var parent: HomeFeedCollectionView
        var localizationRevision = -1
        fileprivate weak var collection: HomeNativeCollectionView?
        var dataSource: NSCollectionViewDiffableDataSource<String, String>?
        private var itemByID: [String: HomeItemPresentation] = [:]
        private var sectionByID: [String: HomeSectionPresentation] = [:]
        private var appliedSections: [HomeSectionPresentation] = []
        private var appliedSectionIDs: [String] = []
        private var appliedHasMore = false
        private weak var hoveredItem: HomeCollectionItem?
        private var hoverUpdateScheduled = false
        fileprivate var lastQueueContext: QueueContext?

        init(parent: HomeFeedCollectionView) {
            self.parent = parent
            self.lastQueueContext = parent.queueContext
        }
        deinit { NotificationCenter.default.removeObserver(self) }

        fileprivate func installDataSource(on collection: HomeNativeCollectionView) {
            let source = NSCollectionViewDiffableDataSource<String, String>(collectionView: collection) { [weak self] collection, indexPath, identifier in
                guard let self else { return nil }
                if identifier == Self.footerItem {
                    let item = collection.makeItem(withIdentifier: HomeLoadMoreItem.identifier, for: indexPath) as! HomeLoadMoreItem
                    item.configure(loading: self.parent.isLoadingMore) { [weak self] in self?.parent.onLoadMore() }
                    return item
                }
                guard let payload = self.itemByID[identifier] else { return nil }
                let item = collection.makeItem(withIdentifier: HomeCollectionItem.identifier, for: indexPath) as! HomeCollectionItem
                self.configure(item, payload: payload, style: payload.style)
                return item
            }
            source.supplementaryViewProvider = { [weak self] collection, kind, indexPath in
                guard let self, kind == Self.headerKind else { return nil }
                let header = collection.makeSupplementaryView(
                    ofKind: kind, withIdentifier: HomeSectionHeaderView.identifier, for: indexPath
                ) as! HomeSectionHeaderView
                if indexPath.section < self.appliedSectionIDs.count,
                   let section = self.sectionByID[self.appliedSectionIDs[indexPath.section]] {
                    header.configure(title: L10n.providerHeading(section.title), showsMore: section.isNavigableMore,
                                     showsArrows: false,
                                     previous: { [weak self] in self?.scrollSection(section.id, direction: -1) },
                                     next: { [weak self] in self?.scrollSection(section.id, direction: 1) },
                                     action: { [weak self] in self?.navigateMore(in: section.id) })
                }
                return header
            }
            dataSource = source
        }

        func applyContent() {
            guard let dataSource, let collection else { return }
            let unchangedPrefix = !appliedSections.isEmpty && parent.sections.count >= appliedSections.count &&
                zip(appliedSections, parent.sections).allSatisfy { $0 == $1 }

            if unchangedPrefix {
                let appended = parent.sections.dropFirst(appliedSections.count)
                guard !appended.isEmpty || appliedHasMore != parent.hasMore else {
                    updateLoadMore()
                    return
                }
                var snapshot = dataSource.snapshot()
                if appliedHasMore { snapshot.deleteSections([Self.footerSection]) }
                for section in appended {
                    sectionByID[section.id] = section
                    for item in section.items { itemByID[item.id] = item }
                    snapshot.appendSections([section.id])
                    snapshot.appendItems(section.items.map(\.id), toSection: section.id)
                }
                if parent.hasMore {
                    snapshot.appendSections([Self.footerSection])
                    snapshot.appendItems([Self.footerItem], toSection: Self.footerSection)
                }
                appliedSections = parent.sections
                appliedHasMore = parent.hasMore
                appliedSectionIDs = snapshot.sectionIdentifiers
                dataSource.apply(snapshot, animatingDifferences: false)
                updateLoadMore()
                return
            }

            sectionByID = Dictionary(uniqueKeysWithValues: parent.sections.map { ($0.id, $0) })
            itemByID = Dictionary(uniqueKeysWithValues: parent.sections.flatMap { $0.items.map { ($0.id, $0) } })

            var snapshot = NSDiffableDataSourceSnapshot<String, String>()
            for section in parent.sections {
                snapshot.appendSections([section.id])
                snapshot.appendItems(section.items.map(\.id), toSection: section.id)
            }
            if parent.hasMore {
                snapshot.appendSections([Self.footerSection])
                snapshot.appendItems([Self.footerItem], toSection: Self.footerSection)
            }
            appliedSections = parent.sections
            appliedHasMore = parent.hasMore
            appliedSectionIDs = snapshot.sectionIdentifiers
            dataSource.apply(snapshot, animatingDifferences: false)
            for indexPath in collection.indexPathsForVisibleItems() {
                guard let identifier = dataSource.itemIdentifier(for: indexPath),
                      let payload = itemByID[identifier],
                      let item = collection.item(at: indexPath) as? HomeCollectionItem else { continue }
                configure(item, payload: payload, style: payload.style)
            }
            updateLoadMore()
        }

        func layoutSection(at index: Int, width: CGFloat) -> NSCollectionLayoutSection? {
            guard parent.sections.indices.contains(index) || (parent.hasMore && index == parent.sections.count) else { return nil }
            if index == parent.sections.count {
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(64))
                let item = NSCollectionLayoutItem(layoutSize: size)
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 28, bottom: 0, trailing: 28)
                return section
            }
            let spec = parent.sections[index]
            let compact = width < 760
            let item: NSCollectionLayoutItem
            let group: NSCollectionLayoutGroup
            let section: NSCollectionLayoutSection
            if spec.style == .compactSong {
                let row = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(56))
                item = NSCollectionLayoutItem(layoutSize: row)
                let groupSize = NSCollectionLayoutSize(
                    widthDimension: .absolute(compact ? 286 : 330), heightDimension: .absolute(230)
                )
                group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitem: item, count: 4)
                group.interItemSpacing = .fixed(1)
            } else {
                let cardWidth: CGFloat = compact ? 120 : 140
                let height = cardWidth + HomeItemView.largeCardTextHeight
                let size = NSCollectionLayoutSize(widthDimension: .absolute(cardWidth), heightDimension: .absolute(height))
                item = NSCollectionLayoutItem(layoutSize: size)
                group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
            }
            section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuous
            section.interGroupSpacing = 16
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 28, bottom: 16, trailing: 28)
            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(38))
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize, elementKind: Self.headerKind, alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            return section
        }

        private func configure(_ cell: HomeCollectionItem, payload: HomeItemPresentation, style: HomeSectionStyle) {
            let id = payload.id
            cell.content.configure(
                record: payload.record,
                style: style,
                currentTrackID: parent.currentTrackID,
                currentAlbumBrowseId: parent.currentAlbumBrowseId ?? parent.player.currentAlbumBrowseId,
                currentPlaylistBrowseId: parent.currentPlaylistBrowseId ?? parent.player.currentPlaylistBrowseId,
                isPlaying: parent.isPlaying,
                queueContext: parent.queueContext,
                onCard: { [weak self] in self?.activate(itemID: id, fromCover: true) },
                onCover: { [weak self] in self?.activate(itemID: id, fromCover: true) },
                onTitle: { [weak self] in self?.activate(itemID: id, fromCover: true) },
                onArtist: { [weak self] in self?.navigateArtist(itemID: id) },
                onFeatured: { [weak self] id,name in self?.parent.router?.navigate(to:id.map { .artist(browseId:$0) } ?? .search(query:name)) },
                onAlbum: { [weak self] in self?.navigateAlbum(itemID: id) },
                onDirectPlay: { [weak self] in self?.handleDirectPlay(itemID: id) },
                // El menú debe usar el mismo valor inmutable que pintó esta celda. Consultar
                // itemByID más tarde puede leer otro snapshot si Inicio se actualiza entretanto.
                menuProvider: { [weak self, record = payload.record] in self?.menu(record: record) }
            )
        }

        private func handleDirectPlay(itemID: String) {
            guard let record = itemByID[itemID]?.record else { return }
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

        func activate(at indexPath: IndexPath) {
            guard let id = dataSource?.itemIdentifier(for: indexPath) else { return }
            activate(itemID: id, fromCover: true)
        }

        private func activate(itemID: String, fromCover: Bool) {
            guard let record = itemByID[itemID]?.record else { return }
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
            guard let record = itemByID[itemID]?.record else { return }
            if let id = record.artistId ?? record.artistRuns.first(where: { $0.id?.isEmpty == false })?.id,
               !id.isEmpty {
                parent.onNavigate(.artist(browseId: id))
            }
        }

        private func navigateAlbum(itemID: String) {
            guard let record = itemByID[itemID]?.record else { return }
            if let id = record.albumId, !id.isEmpty {
                parent.onNavigate(.album(browseId: id))
            }
        }

        private func scrollSection(_ sectionID: String, direction: Int) {
            guard let collection,
                  let sectionIndex = parent.sections.firstIndex(where: { $0.id == sectionID }) else { return }
            let itemCount = parent.sections[sectionIndex].items.count
            guard itemCount > 0 else { return }
            let visibleStep = parent.sections[sectionIndex].style == .compactSong ? 4 : 1
            let visible = collection.indexPathsForVisibleItems()
                .filter { $0.section == sectionIndex }
                .map(\.item)
            let anchor = direction > 0 ? (visible.max() ?? 0) + visibleStep : max(0, (visible.min() ?? 0) - visibleStep)
            let target = min(itemCount - 1, anchor)
            collection.scrollToItems(at: [IndexPath(item: target, section: sectionIndex)],
                                     scrollPosition: direction > 0 ? .right : .left)
        }

        private func navigateMore(in sectionID: String) {
            guard let section = sectionByID[sectionID], let id = section.moreBrowseId else { return }
            if id.hasPrefix("MPRE") {
                parent.onNavigate(.album(browseId: id))
            } else if id.hasPrefix("UC") {
                parent.onNavigate(.artist(browseId: id))
            } else if id.hasPrefix("FE") {
                print("[HomeFeed] moreBrowseId de categoría \(id) no es navegable como playlist.")
            } else {
                parent.onNavigate(.playlist(browseId: id))
            }
        }

        private func menu(record: HomeItemRecord) -> NSMenu? {
            let factory = AppContextMenuFactory.shared
            let core = parent.player.rustCore
            switch record.kind {
            case "song":
                return factory.buildSongNSMenu(
                    song: SongItemRecord(fromHomeItem: record),
                    player: parent.player,
                    router: parent.router,
                    core: core,
                    origin: .home
                )
            case "album":
                return factory.buildAlbumNSMenu(
                    browseId: record.id,
                    playlistId: nil,
                    title: record.title,
                    artist: record.subtitle,
                    thumbnail: record.thumbnail,
                    inLibrary: nil,
                    origin: .home,
                    player: parent.player,
                    router: parent.router,
                    core: core
                )
            case "artist":
                return factory.buildArtistNSMenu(
                    channelId: record.id,
                    name: record.title,
                    thumbnail: record.thumbnail,
                    radioPlaylistId: nil,
                    origin: .home,
                    player: parent.player,
                    router: parent.router,
                    core: core
                )
            default:
                return factory.buildPlaylistNSMenu(
                    id: record.id,
                    title: record.title,
                    subtitle: record.subtitle,
                    thumbnail: record.thumbnail,
                    origin: .home,
                    player: parent.player,
                    router: parent.router,
                    core: core
                )
            }
        }

        func updateVisiblePlayback() {
            lastQueueContext = parent.queueContext
            guard let collection else { return }
            for indexPath in collection.indexPathsForVisibleItems() {
                (collection.item(at: indexPath) as? HomeCollectionItem)?.content.updatePlayback(
                    currentTrackID: parent.currentTrackID,
                    currentAlbumBrowseId: parent.currentAlbumBrowseId ?? parent.player.currentAlbumBrowseId,
                    currentPlaylistBrowseId: parent.currentPlaylistBrowseId ?? parent.player.currentPlaylistBrowseId,
                    isPlaying: parent.isPlaying,
                    queueContext: parent.queueContext
                )
            }
        }

        func updateLocalization() {
            guard let collection else { return }
            collection.setAccessibilityLabel(L10n.text("home.accessibility.recommendations"))
            for indexPath in collection.indexPathsForVisibleItems() {
                if let header = collection.supplementaryView(forElementKind: Self.headerKind, at: indexPath) as? HomeSectionHeaderView {
                    if indexPath.section < appliedSectionIDs.count,
                       let section = sectionByID[appliedSectionIDs[indexPath.section]] {
                        header.setLocalizedTitle(L10n.providerHeading(section.title))
                    }
                    header.refreshLocalization()
                }
                (collection.item(at: indexPath) as? HomeCollectionItem)?.content.refreshLocalization(
                    currentTrackID: parent.currentTrackID,
                    currentAlbumBrowseId: parent.currentAlbumBrowseId ?? parent.player.currentAlbumBrowseId,
                    currentPlaylistBrowseId: parent.currentPlaylistBrowseId ?? parent.player.currentPlaylistBrowseId,
                    isPlaying: parent.isPlaying,
                    queueContext: parent.queueContext
                )
            }
            updateLoadMore()
        }

        func updateLoadMore() {
            guard let collection, let dataSource,
                  let path = dataSource.indexPath(for: Self.footerItem),
                  collection.indexPathsForVisibleItems().contains(path) else { return }
            (collection.item(at: path) as? HomeLoadMoreItem)?.configure(loading: parent.isLoadingMore) { [weak self] in
                self?.parent.onLoadMore()
            }
        }

        @objc func clipBoundsChanged(_ notification: Notification) {
            scheduleHoverUpdate()
        }

        func scheduleHoverUpdate() {
            guard !hoverUpdateScheduled else { return }
            hoverUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.hoverUpdateScheduled = false
                self.updateHoverAtCurrentPointer()
            }
        }

        private func updateHoverAtCurrentPointer() {
            guard let collection, let window = collection.window else { return }
            let point = window.mouseLocationOutsideOfEventStream
            let collectionPoint = collection.convert(point, from: nil)
            updateHover(at: collectionPoint)
        }

        func updateHover(at point: NSPoint?) {
            guard let collection else { return }
            for path in collection.indexPathsForVisibleItems() {
                guard let item = collection.item(at: path) as? HomeCollectionItem else { continue }
                item.content.setFeedVisible(!item.content.visibleRect.isEmpty)
            }
            var next: HomeCollectionItem?
            var pointInItem: NSPoint?
            if let point, collection.visibleRect.contains(point),
               let indexPath = collection.indexPathForItem(at: point),
               let item = collection.item(at: indexPath) as? HomeCollectionItem {
                next = item
                pointInItem = item.view.convert(point, from: collection)
            }
            if hoveredItem !== next {
                hoveredItem?.content.setHovered(false, localPoint: nil)
                next?.content.setHovered(true, localPoint: pointInItem)
                hoveredItem = next
            } else if let next, let pointInItem {
                next.content.updateHoverLocation(pointInItem)
            }
        }
    }
}

final class HomeNativeCollectionView: NSCollectionView {
    var onActivateSelection: ((IndexPath) -> Void)?
    var onHoverPosition: ((NSPoint?) -> Void)?
    var onViewportMoved: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private let observedClipViews = NSHashTable<NSClipView>.weakObjects()

    override var collectionViewLayout: NSCollectionViewLayout? {
        didSet {
            guard oldValue !== collectionViewLayout else { return }
            stopObservingScrollViews()
            // AppKit's setter may have laid out the new tree synchronously.
            // Rearm its clips on the next normal pass after retiring old ones.
            if shouldConfigureOrthogonalScrollViews { needsLayout = true }
        }
    }

    private var shouldConfigureOrthogonalScrollViews: Bool {
        guard let layout = collectionViewLayout else { return false }
        // Current shelves and catalogs use Flow, which does not own orthogonal
        // scrollers. Preserve handling for compositional, custom and transition
        // layouts, including transitions whose endpoints use different layouts.
        return !(layout is NSCollectionViewFlowLayout || layout is HomeMosaicCollectionLayout)
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard shouldConfigureOrthogonalScrollViews else { return }
        configureOrthogonalScrollViews(in: subview)
    }

    override func layout() {
        super.layout()
        guard shouldConfigureOrthogonalScrollViews else { return }
        // Compositional layout owns these orthogonal scroll views and may tile
        // them again as sections are laid out or reused.
        for subview in subviews { configureOrthogonalScrollViews(in: subview) }
    }

    private func configureOrthogonalScrollViews(in view: NSView) {
        if let scroll = view as? NSScrollView {
            if scroll.hasHorizontalScroller { scroll.hasHorizontalScroller = false }
            if scroll.horizontalScroller != nil { scroll.horizontalScroller = nil }
            if scroll.hasVerticalScroller { scroll.hasVerticalScroller = false }
            if scroll.drawsBackground { scroll.drawsBackground = false }
            if scroll.horizontalScrollElasticity != .allowed { scroll.horizontalScrollElasticity = .allowed }
            if !scroll.contentView.postsBoundsChangedNotifications { scroll.contentView.postsBoundsChangedNotifications = true }
            if !observedClipViews.contains(scroll.contentView) {
                observedClipViews.add(scroll.contentView)
                NotificationCenter.default.addObserver(self, selector: #selector(shelfBoundsChanged(_:)),
                                                       name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            }
        }
        for child in view.subviews { configureOrthogonalScrollViews(in: child) }
    }

    override func willRemoveSubview(_ subview: NSView) {
        stopObservingScrollViews(in: subview)
        super.willRemoveSubview(subview)
    }

    private func stopObservingScrollViews(in view: NSView? = nil) {
        // Work is proportional to clips actually registered, not every control
        // in the departing card subtree. Flow collections keep this set empty.
        for clip in observedClipViews.allObjects {
            if let view, clip !== view && !clip.isDescendant(of: view) { continue }
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: clip)
            observedClipViews.remove(clip)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func shelfBoundsChanged(_ notification: Notification) {
        onViewportMoved?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hoverTrackingArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverPosition?(convert(event.locationInWindow, from: nil))
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverPosition?(nil)
        super.mouseExited(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 49 || event.keyCode == 36), let selected = selectionIndexPaths.first {
            onActivateSelection?(selected)
            return
        }
        super.keyDown(with: event)
    }

    override func setFrameSize(_ newSize: NSSize) {
        if let mosaic = collectionViewLayout as? HomeMosaicCollectionLayout {
            let contentSize = mosaic.collectionViewContentSize
            let clipSize = enclosingScrollView?.contentView.bounds.size ?? .zero
            super.setFrameSize(
                NSSize(
                    width: max(newSize.width, max(clipSize.width, contentSize.width)),
                    height: max(newSize.height, max(clipSize.height, contentSize.height))
                )
            )
        } else {
            super.setFrameSize(newSize)
        }
    }
}

final class HomeCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("HomeFeedItem")
    var content: HomeItemView { view as! HomeItemView }
    override func loadView() { view = HomeItemView(frame: NSRect(x: 0, y: 0, width: 160, height: 254)) }
    override var isSelected: Bool { didSet { content.isSelectedInFeed = isSelected } }
    override func prepareForReuse() { super.prepareForReuse(); content.prepareForReuse() }
}

final class HomeSectionHeaderView: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("HomeFeedHeader")
    private let title = NSTextField(labelWithString: "")
    private let more = NSButton(title: L10n.text("home.see_all"), target: nil, action: nil)
    private let previous = NSButton(title: "", target: nil, action: nil)
    private let next = NSButton(title: "", target: nil, action: nil)
    private var action: (() -> Void)?
    private var previousAction: (() -> Void)?
    private var nextAction: (() -> Void)?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = .systemFont(ofSize: 19, weight: .bold)
        title.textColor = .labelColor
        addSubview(title)
        more.isBordered = false
        more.font = .systemFont(ofSize: 13, weight: .semibold)
        more.contentTintColor = .labelColor
        more.target = self
        more.action = #selector(openMore)
        more.setAccessibilityLabel(L10n.text("home.see_all"))
        addSubview(more)
        for (button, symbol, selector, label) in [
            (previous, "chevron.left", #selector(scrollPrevious), L10n.text("home.shelf.previous")),
            (next, "chevron.right", #selector(scrollNext), L10n.text("home.shelf.next"))
        ] {
            button.isBordered = false
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.imagePosition = .imageOnly
            button.contentTintColor = .secondaryLabelColor
            button.target = self
            button.action = selector
            button.setAccessibilityLabel(label)
            addSubview(button)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
    override func prepareForReuse() {
        super.prepareForReuse()
        action = nil
        previousAction = nil
        nextAction = nil
    }
    override func layout() {
        super.layout()
        let controlsWidth: CGFloat = (previous.isHidden ? 0 : 64) + (more.isHidden ? 0 : 90) + 12
        title.frame = NSRect(x: 0, y: 6, width: max(0, bounds.width - controlsWidth), height: 28)
        next.frame = NSRect(x: max(0, bounds.width - (more.isHidden ? 30 : 120)), y: 7, width: 26, height: 26)
        previous.frame = NSRect(x: max(0, bounds.width - (more.isHidden ? 60 : 150)), y: 7, width: 26, height: 26)
        more.frame = NSRect(x: max(0, bounds.width - 88), y: 8, width: 84, height: 25)
    }
    func configure(title: String, showsMore: Bool, showsArrows: Bool,
                   previous: @escaping () -> Void, next: @escaping () -> Void,
                   action: @escaping () -> Void) {
        self.title.stringValue = title
        self.more.title = L10n.text("home.see_all")
        self.more.isHidden = !showsMore
        self.previous.isHidden = !showsArrows
        self.next.isHidden = !showsArrows
        self.more.setAccessibilityLabel(L10n.text("home.see_all_named", args: [title]))
        self.action = action
        previousAction = previous
        nextAction = next
    }
    func refreshLocalization() {
        more.title = L10n.text("home.see_all")
        previous.setAccessibilityLabel(L10n.text("home.shelf.previous"))
        next.setAccessibilityLabel(L10n.text("home.shelf.next"))
        more.setAccessibilityLabel(L10n.text("home.see_all_named", args: [title.stringValue]))
        previous.setAccessibilityLabel(L10n.text("home.shelf.previous"))
        next.setAccessibilityLabel(L10n.text("home.shelf.next"))
    }
    func setLocalizedTitle(_ value: String) { title.stringValue = value }
    @objc private func openMore() { action?() }
    @objc private func scrollPrevious() { previousAction?() }
    @objc private func scrollNext() { nextAction?() }
}

private final class HomeLoadMoreItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("HomeLoadMore")
    private let button = NSButton(title: L10n.text("home.load_more"), target: nil, action: nil)
    private var action: (() -> Void)?
    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 64))
        button.isBordered = true
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(loadMore)
        root.addSubview(button)
        view = root
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        button.frame = NSRect(x: max(0, (view.bounds.width - 220) / 2), y: 12, width: 220, height: 32)
    }
    func configure(loading: Bool, action: @escaping () -> Void) {
        button.title = loading ? L10n.text("home.loading_recommendations") : L10n.text("home.load_more")
        self.action = action
        button.isEnabled = !loading
    }
    @objc private func loadMore() { action?() }
}

private final class HomePassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

class HomeFocusTrackingButton: NSButton {
    var onFocusChanged: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChanged?() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChanged?() }
        return resigned
    }
}

final class HomeInteractiveLinkButton: HomeFocusTrackingButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        refusesFirstResponder = false
        focusRingType = .default
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled && !isHidden && bounds.width > 0 && bounds.height > 0 {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

final class HomePlayHitButton: HomeFocusTrackingButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled && !isHidden && bounds.width > 0 && bounds.height > 0 {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

private final class HomeCardTitleLabel: NativeTrackActionField {
    override func hitTest(_ point:NSPoint)->NSView? { let hit = super.hitTest(point); return hit is NativeFeaturedArtistButton ? hit : nil }
}

final class HomeItemView: NSView {
    // Dos líneas de título y detalle, más las separaciones. Compartido con el layout del estante.
    var featuredSong = false
    /// Tarjeta grande de colección: portada cuadrada y panel de texto claro debajo.
    var featuredCollection = false {
        didSet {
            guard oldValue != featuredCollection else { return }
            renderedAppearance = nil
            needsLayout = true
        }
    }
    /// Acabado del panel de la tarjeta de colección; cambiarlo repinta el texto y el lavado sin reiniciar.
    var albumCardStyle: HomeAlbumCardStyle = .tinted {
        didSet {
            guard oldValue != albumCardStyle, featuredCollection else { return }
            applyCollectionStyle()
            refreshWash()
        }
    }
    private let featuredGradient = CAGradientLayer()
    private let featuredArtwork = CALayer()
    private let featuredFooter = CALayer()
    private let titleFadeMask = CAGradientLayer()
    /// Tamaño de la celda en el mosaico (sólo aplica al modo `featuredSong`).
    var mosaicSize: HomeMosaicSize = .small {
        didSet {
            guard oldValue != mosaicSize else { return }
            appliedTitleKey = nil
            renderedAppearance = nil
            needsLayout = true
            refreshAppearance()
        }
    }
    /// Sesión con la que se pide el color de la carátula del degradado (la del carril).
    var coverSession: String?
    /// Caché de colores por carátula; se inyecta en pruebas.
    var coverColorStore: HomeCoverColorStore = .shared
    /// Preferencia del sistema «Reducir movimiento»; se inyecta en pruebas.
    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Preferencia del sistema «Reducir transparencia»; se inyecta en pruebas.
    var reducesTransparency: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    /// Caché de lavados de portada por carátula; se inyecta en pruebas.
    var coverWashStore: HomeCoverWashStore = .shared
    private var colorTask: Task<Void, Never>?
    private var washTask: Task<Void, Never>?
    private var coverBitmap: CGImage?
    // Pieza de la tarjeta de colección: se crean al primer uso, no por cada celda del feed.
    private lazy var collectionPanel = HomeCollectionPanelView()
    private lazy var coverDim = CALayer()
    private var playGlass: HomeGlassCircleView?
    private var moreGlass: HomeGlassCircleView?
    private var collectionChromeInstalled = false
    private var collectionLifted = false
    private var collectionArtistWidth: CGFloat = 0
    private var isMoreHovered = false
    private var scrimCover: HomeAmbientRGB?
    private var appliedTitleKey: String?
    private var mosaicPlayVisible = false
    private var playSymbolRaised = false
    private var artworkZoomed = false
    private(set) var featuredScrimCoverForTesting: HomeAmbientRGB?
    func applyFeaturedLayout(song: Bool, summary: String = "", mosaicSize size: HomeMosaicSize? = nil) {
        featuredSong = song
        featuredCollection = !song
        if let size { mosaicSize = size }
        subtitle.stringValue = summary
        if !song && subtitle.superview == nil { addSubview(subtitle) }
        subtitle.isHidden = song
        if !song { applyCollectionStyle() }
        needsLayout = true
    }
    static let largeCardTextHeight: CGFloat = 94
    /// Two fixed request sizes for featured artwork, never derived from the live width: deriving it gave every
    /// intermediate resize width its own URL and cache entry, so covers reloaded. The small mosaic cell (144 pt)
    /// asks for 480 px; the wide and large mosaic cells (296 pt) and the collection cards (up to 320 pt) ask for
    /// 640 px, which is what they need at 2x.
    static let featuredArtworkPixels = 480
    static let featuredArtworkTarget = CGSize(width: 240, height: 240)
    static let featuredLargeArtworkPixels = 640
    static let featuredLargeArtworkTarget = CGSize(width: 320, height: 320)

    /// Resolución pedida de una carátula: `nil` si la celda no es destacada.
    static func featuredArtworkRequest(song: Bool, collection: Bool, size: HomeMosaicSize) -> (pixels: Int, target: CGSize)? {
        if collection || (song && size != .small) { return (featuredLargeArtworkPixels, featuredLargeArtworkTarget) }
        return song ? (featuredArtworkPixels, featuredArtworkTarget) : nil
    }
    private static let largeTitleFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
    private static let largeMetadataFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    private static let compactArtistMeasureFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)

    private struct Appearance: Equatable {
        let hovered: Bool
        let selected: Bool
        let playing: Bool
        let isCurrent: Bool
        let compactSong: Bool
        let playButtonHovered: Bool
        let feedVisible: Bool
        let reduceMotion: Bool
        let focusWithinCard: Bool
        let loading: Bool
        let mosaicSize: HomeMosaicSize?
        let collection: Bool
        let moreHovered: Bool
        let artistFocused: Bool
        let reduceTransparency: Bool
    }

    var showsDirectPlayControl = true {
        didSet {
            guard oldValue != showsDirectPlayControl else { return }
            renderedAppearance = nil
            refreshAppearance()
        }
    }
    let cardButton = HomeFocusTrackingButton()
    private let cover = HomeFocusTrackingButton()
    let equalizerOverlay = HomeEqualizerOverlayView()
    private let playButton = HomePlayHitButton()
    private let playSymbol = HomePassthroughImageView()
    private let playImage = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
    private let pauseImage = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: nil)
    private let waveformImage = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
    private let title = HomeCardTitleLabel(labelWithString: "")
    let artist = HomeInteractiveLinkButton()
    private let largeArtistLabel = NSTextField(labelWithString: "")
    private let songArtistLinks = NativeTrackActionField(frame:.zero)
    private let album = HomeInteractiveLinkButton()
    private let subtitle = NSTextField(labelWithString: "")
    private let bullet = NSTextField(labelWithString: "•")
    private let typeLabel = NSTextField(labelWithString: "")
    private let explicitBadge = NativeContentRatingBadge(frame: .zero)
    private let more = HomeInteractiveLinkButton()
    var artworkLoader: ((URL, CGSize) async -> NSImage?)?
    private(set) var artworkRequestCount = 0
    private(set) var featuredArtworkSizeForTesting: CGSize?
    private var imageTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var representedID: String?
    private var representedRecord: HomeItemRecord?
    private var style: HomeSectionStyle = .largeCard
    private var compactArtistTextWidth: CGFloat = 0
    private var measuredLargeCardWidth: CGFloat = -1
    private var measuredTitleLines: CGFloat = 1
    private var measuredTypeWidth: CGFloat = 0
    private var measuredDetailLines: CGFloat = 1
    private var isCurrent = false
    private var playing = false
    private var feedVisible = true
    private var loading = false
    private var loadingIndicator: NSProgressIndicator?
    private var renderedAppearance: Appearance?
    var hovered = false { didSet { if hovered != oldValue { refreshAppearance() } } }
    var isSelectedInFeed = false { didSet { if isSelectedInFeed != oldValue { refreshAppearance() } } }
    private var onCard: (() -> Void)?
    private var onCover: (() -> Void)?
    private var onTitle: (() -> Void)?
    private var onArtist: (() -> Void)?
    private var onAlbum: (() -> Void)?
    private var onDirectPlay: (() -> Void)?
    private var menuProvider: (() -> NSMenu?)?
    private var rawArtistTitle: String = ""
    private var rawAlbumTitle: String = ""
    private(set) var isArtistHovered = false
    private var isAlbumHovered = false
    private var isPlayButtonHovered = false
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        // El radio del contenedor es solo para su fondo hover; no debe recortar
        // la portada que empieza en su borde superior con un radio distinto.
        layer?.masksToBounds = false
        layer?.borderWidth = AppTheme.cardBorderWidth
        layer?.borderColor = NSColor.clear.cgColor

        // Botón base que cubre todo el marco de la tarjeta
        cardButton.title = ""
        cardButton.isTransparent = true
        setup(cardButton, selector: #selector(cardPressed), font: nil)
        cardButton.title = ""
        cardButton.isTransparent = true
        cardButton.refusesFirstResponder = true
        cardButton.focusRingType = .none
        cardButton.onFocusChanged = { [weak self] in self?.scheduleFocusAppearanceRefresh() }
        cover.onFocusChanged = { [weak self] in self?.scheduleFocusAppearanceRefresh() }

        setup(cover, selector: #selector(cardPressed), font: nil)
        cover.imagePosition = .imageOnly
        cover.imageScaling = .scaleProportionallyUpOrDown
        cover.wantsLayer = true
        cover.layer?.masksToBounds = true
        cover.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.12).cgColor
        cover.refusesFirstResponder = true
        cover.focusRingType = .none

        addSubview(equalizerOverlay)

        playSymbol.imageScaling = .scaleProportionallyDown
        playSymbol.contentTintColor = .white
        addSubview(playSymbol)

        setup(playButton, selector: #selector(playButtonPressed), font: nil)
        playButton.title = ""
        playButton.isTransparent = true
        playButton.wantsLayer = true
        playButton.refusesFirstResponder = false
        playButton.focusRingType = .default
        playButton.onFocusChanged = { [weak self] in self?.scheduleFocusAppearanceRefresh() }
        playButton.setAccessibilityLabel(L10n.text("home.play"))

        title.font = Self.largeTitleFont
        title.textColor = .labelColor
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        title.cell?.wraps = true
        title.setAccessibilityElement(false)
        addSubview(title)
        songArtistLinks.isEditable = false; songArtistLinks.isSelectable = false; songArtistLinks.isBezeled = false; songArtistLinks.drawsBackground = false
        songArtistLinks.lineBreakMode = .byTruncatingTail; songArtistLinks.maximumNumberOfLines = 1
        songArtistLinks.font = Self.compactArtistMeasureFont; songArtistLinks.textColor = .secondaryLabelColor
        songArtistLinks.isHidden = true

        setup(artist, selector: #selector(artistPressed), font: .systemFont(ofSize: 15.5, weight: .regular), attach: false)
        artist.onFocusChanged = { [weak self] in self?.scheduleFocusAppearanceRefresh() }
        artist.alignment = .left
        artist.contentTintColor = .secondaryLabelColor

        largeArtistLabel.font = Self.largeMetadataFont
        largeArtistLabel.textColor = .secondaryLabelColor
        largeArtistLabel.maximumNumberOfLines = 2
        largeArtistLabel.lineBreakMode = .byTruncatingTail
        largeArtistLabel.cell?.wraps = true
        largeArtistLabel.setAccessibilityElement(false)

        setup(album, selector: #selector(albumPressed), font: .systemFont(ofSize: 11.5, weight: .medium), attach: false)
        album.onFocusChanged = { [weak self] in self?.scheduleFocusAppearanceRefresh() }
        album.alignment = .left
        album.contentTintColor = .secondaryLabelColor

        subtitle.font = Self.largeMetadataFont
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.maximumNumberOfLines = 2
        subtitle.cell?.wraps = true

        bullet.font = Self.largeMetadataFont
        bullet.textColor = .tertiaryLabelColor

        typeLabel.font = Self.largeMetadataFont
        typeLabel.textColor = .secondaryLabelColor


        setup(more, selector: #selector(morePressed), font: nil)
        more.onFocusChanged = { [weak self] in self?.scheduleFocusAppearanceRefresh() }
        more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L10n.text("home.more_options"))
        more.imagePosition = .imageOnly
        more.contentTintColor = NSColor.white.withAlphaComponent(0.78)
        more.setAccessibilityLabel(L10n.text("home.more_options"))
        more.refusesFirstResponder = false
        more.focusRingType = .default

        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    private func setup(_ button: NSButton, selector: Selector, font: NSFont?, attach: Bool = true) {
        button.isBordered = false
        button.target = self
        button.action = selector
        button.lineBreakMode = .byTruncatingTail
        if let font { button.font = font }
        if attach { addSubview(button) }
    }

    private func showMetadata(_ view: NSView, when visible: Bool, below sibling: NSView? = nil) {
        view.isHidden = !visible
        if visible {
            guard view.superview !== self else { return }
            addSubview(view, positioned: sibling == nil ? .above : .below, relativeTo: sibling)
        } else if view.superview === self {
            // Hidden NSControls still refresh their semantic style when a shelf
            // leaves/re-enters the window. Keep the reusable instance off-tree.
            view.removeFromSuperview()
        }
    }

    private static func displayedLines(for text: String, width: CGFloat, font: NSFont) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return 1 }
        if text.contains("\n") { return 2 }
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return textWidth > width - 2 ? 2 : 1
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardButton.frame = bounds
        if featuredCollection {
            layoutCollectionCard()
            CATransaction.commit()
            return
        }
        leaveCollectionChrome()
        if style == .compactSong {
            layer?.cornerRadius = 14
            cover.frame = NSRect(x: 6, y: 6, width: 44, height: 44)
            equalizerOverlay.frame = cover.frame
            equalizerOverlay.setCornerRadius(AppTheme.artworkThumbnailRadius)
            equalizerOverlay.updateStyle(compact: true)
            playSymbol.frame = NSRect(x: 19, y: 19, width: 18, height: 18)
            playButton.frame = cover.frame
            playButton.layer?.cornerRadius = AppTheme.artworkThumbnailRadius

            let textLeading: CGFloat = 58
            let moreTrailingMargin: CGFloat = 38
            let maxTextWidth = max(0, bounds.width - textLeading - moreTrailingMargin)
            title.frame = NSRect(x: textLeading, y: 5, width: maxTextWidth, height: 23)

            let badgeSide = ContentRatingBadgeMetrics.side(for: Self.compactArtistMeasureFont.pointSize)
            let badgeWidth: CGFloat = explicitBadge.isHidden ? 0 : badgeSide + ContentRatingBadgeMetrics.gap
            explicitBadge.fontSize = Self.compactArtistMeasureFont.pointSize
            explicitBadge.frame = NSRect(x: textLeading, y: 30 + (17 - badgeSide) / 2, width: badgeSide, height: badgeSide)
            let metadataLeading = textLeading + badgeWidth
            let artistWidth = artist.isHidden && songArtistLinks.isHidden ? 0 : min(compactArtistTextWidth, max(0, maxTextWidth - badgeWidth))
            artist.frame = NSRect(x: metadataLeading, y: 30, width: artistWidth, height: 17)
            let separatorX = metadataLeading + artistWidth + 3
            bullet.frame = NSRect(x: separatorX, y: 30, width: 10, height: 17)
            bullet.isHidden = artist.isHidden && songArtistLinks.isHidden || album.isHidden
            let albumX = separatorX + (bullet.isHidden ? 0 : 10)
            album.frame = NSRect(x: albumX, y: 30, width: max(0, bounds.width - albumX - moreTrailingMargin), height: 17)

            more.frame = NSRect(x: bounds.width - 34, y: 14, width: 28, height: 28)
            more.layer?.backgroundColor = NSColor.clear.cgColor
            typeLabel.isHidden = true
            subtitle.isHidden = true
            largeArtistLabel.isHidden = true
        } else {
            layer?.cornerRadius = 14
            let art = bounds.width
            let artX: CGFloat = 0
            cover.frame = NSRect(x: artX, y: 0, width: art, height: art)
            let cornerRadius: CGFloat = representedKind == "artist"
                ? bounds.width / 2
                : AppTheme.artworkCardRadius
            equalizerOverlay.frame = cover.frame
            equalizerOverlay.setCornerRadius(cornerRadius)
            equalizerOverlay.updateStyle(compact: false)
            let buttonSize: CGFloat = 32
            let isSong = representedKind == "song"
            let hitX = isSong ? max(0, (art - buttonSize) / 2) : max(0, artX + art - buttonSize - 8)
            let hitY = isSong ? max(0, (art - buttonSize) / 2) : max(0, art - buttonSize - 8)
            playButton.frame = NSRect(x: hitX, y: hitY, width: buttonSize, height: buttonSize)
            playButton.layer?.cornerRadius = buttonSize / 2
            let symbolSize: CGFloat = 14
            playSymbol.frame = NSRect(
                x: hitX + (buttonSize - symbolSize) / 2,
                y: hitY + (buttonSize - symbolSize) / 2,
                width: symbolSize,
                height: symbolSize
            )
            let badgeSide = ContentRatingBadgeMetrics.side(for: Self.largeMetadataFont.pointSize)
            let badgeWidth: CGFloat = explicitBadge.isHidden ? 0 : badgeSide + ContentRatingBadgeMetrics.gap
            explicitBadge.fontSize = Self.largeMetadataFont.pointSize
            if measuredLargeCardWidth != bounds.width {
                measuredLargeCardWidth = bounds.width
                measuredTitleLines = Self.displayedLines(for: title.stringValue, width: bounds.width, font: Self.largeTitleFont)
                measuredTypeWidth = ceil((typeLabel.stringValue as NSString).size(withAttributes: [.font: Self.largeMetadataFont]).width)
                let actualDetailWidth = max(0, bounds.width - badgeWidth - measuredTypeWidth - 15)
                let detailText = artist.isHidden ? subtitle.stringValue : rawArtistTitle
                measuredDetailLines = Self.displayedLines(for: detailText, width: actualDetailWidth, font: Self.largeMetadataFont)
            }
            let titleHeight = measuredTitleLines * 18
            title.frame = NSRect(x: 0, y: art + 11, width: bounds.width, height: titleHeight)
            let metadataY = title.frame.maxY + 3
            let metadataLeading = badgeWidth
            explicitBadge.frame = NSRect(x: 0, y: metadataY + (17 - badgeSide) / 2, width: badgeSide, height: badgeSide)
            typeLabel.frame = NSRect(x: metadataLeading, y: metadataY, width: measuredTypeWidth, height: 17)
            let showMetadataDetail = !artist.isHidden || !songArtistLinks.isHidden || !subtitle.isHidden
            let separatorX = metadataLeading + measuredTypeWidth + 5
            bullet.frame = NSRect(x: separatorX, y: metadataY, width: 8, height: 17)
            bullet.isHidden = !showMetadataDetail
            let detailX = separatorX + (showMetadataDetail ? 10 : 0)
            let detailFrame = NSRect(x: detailX, y: metadataY, width: max(0, bounds.width - detailX), height: measuredDetailLines * 16)
            artist.frame = detailFrame
            largeArtistLabel.frame = detailFrame
            largeArtistLabel.isHidden = artist.isHidden
            subtitle.frame = detailFrame
            more.frame = NSRect(x: artX + art - 34, y: 6, width: 28, height: 28)
            more.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
            more.layer?.cornerRadius = 14
        }
        // El círculo de Play del mosaico es blanco opaco: su icono va encima; en el resto, debajo del vidrio oscuro.
        if featuredSong != playSymbolRaised {
            playSymbolRaised = featuredSong
            addSubview(playSymbol, positioned: featuredSong ? .above : .below, relativeTo: playButton)
        }
        if featuredSong {
            layoutMosaicSong()
        } else {
            equalizerOverlay.updateInline(nil)
            if title.layer?.mask != nil { title.layer?.mask = nil }
        }
        // La tarjeta de colección ya fijó su portada (sólo las esquinas de arriba): no se pisa acá.
        if !featuredCollection {
            cover.layer?.cornerRadius = style == .compactSong
                ? AppTheme.artworkThumbnailRadius
                : (featuredSong ? 10 : (representedKind == "artist" ? bounds.width / 2 : AppTheme.artworkCardRadius))
            cover.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        cover.layer?.borderWidth = 0
        loadingIndicator?.frame = playSymbol.frame.insetBy(dx: -1, dy: -1)
        if !songArtistLinks.isHidden {
            songArtistLinks.frame = artist.frame
            songArtistLinks.font = style == .compactSong ? Self.compactArtistMeasureFont : Self.largeMetadataFont
        }
        CATransaction.commit()
    }

    // MARK: Celda de canción del mosaico

    private static let mosaicEase = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
    private static let mosaicPlayIcon = NSColor(srgbRed: 17.0 / 255, green: 17.0 / 255, blue: 17.0 / 255, alpha: 1)

    var mosaicStyle: HomeMosaicCellStyle { .make(mosaicSize) }

    private func setArtworkGeometry(in rect: CGRect? = nil) {
        // Con transform activo no se usa `frame`: bounds + position mantienen el zoom centrado.
        let rect = rect ?? cover.bounds
        featuredArtwork.bounds = CGRect(origin: .zero, size: rect.size)
        featuredArtwork.position = CGPoint(x: rect.midX, y: rect.midY)
    }

    /// Texto sobre la portada, degradado, Play, ecualizador y fundido del título (Windows: `.mosaic`).
    private func layoutMosaicSong() {
        let metrics = mosaicStyle
        layer?.masksToBounds = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor
        cover.frame = bounds
        cover.imageScaling = .scaleAxesIndependently
        installFeaturedLayers()
        setArtworkGeometry()
        featuredArtwork.masksToBounds = true
        featuredFooter.isHidden = true
        layoutScrim(metrics)

        let width = bounds.width, height = bounds.height
        let reserve = mosaicPlayVisible ? metrics.playReserve : 0
        let textRight = max(metrics.inset, width - metrics.inset - reserve)
        let artistY = height - metrics.bottom - metrics.artistLineHeight
        let titleY = artistY - metrics.titleLineHeight
        let shift = isCurrent ? metrics.barsShift : 0
        applyMosaicTitleStyle(metrics)
        title.frame = NSRect(x: metrics.inset + shift, y: titleY,
                             width: max(0, textRight - metrics.inset - shift), height: metrics.titleLineHeight)
        updateTitleFade()
        let artistFont = NSFont.systemFont(ofSize: metrics.artistSize)
        let artistTextWidth = ceil((rawArtistTitle as NSString).size(withAttributes: [.font: artistFont]).width) + 2
        let maxArtistWidth = max(0, textRight - metrics.inset)
        let artistHeight = metrics.artistLineHeight
        let artistFrame = NSRect(x: metrics.inset, y: artistY, width: min(maxArtistWidth, artistTextWidth), height: artistHeight)
        artist.frame = artistFrame
        largeArtistLabel.frame = NSRect(x: metrics.inset, y: artistY, width: maxArtistWidth, height: artistHeight)
        largeArtistLabel.font = .systemFont(ofSize: metrics.artistSize)
        largeArtistLabel.maximumNumberOfLines = 1
        largeArtistLabel.lineBreakMode = .byTruncatingTail
        largeArtistLabel.textColor = isArtistHovered ? .white : NSColor.white.withAlphaComponent(0.72)
        largeArtistLabel.wantsLayer = true
        largeArtistLabel.shadow = Self.textShadow
        largeArtistLabel.isHidden = artist.isHidden
        artist.contentTintColor = .white
        typeLabel.isHidden = true
        subtitle.isHidden = true
        bullet.isHidden = true
        explicitBadge.isHidden = true
        album.isHidden = true
        equalizerOverlay.updateInline(metrics)
        equalizerOverlay.setCornerRadius(0)
        equalizerOverlay.frame = NSRect(x: metrics.inset, y: titleY + (metrics.titleLineHeight - metrics.barHeight) / 2,
                                        width: metrics.barsWidth, height: metrics.barHeight)
        more.frame = NSRect(x: width - 32, y: 4, width: 28, height: 28)
        let side = metrics.playDiameter
        playButton.frame = NSRect(x: width - metrics.playGap - side, y: height - metrics.playGap - side, width: side, height: side)
        playButton.layer?.cornerRadius = side / 2
        let symbol = (side * 0.43).rounded()
        playSymbol.frame = NSRect(x: playButton.frame.midX - symbol / 2, y: playButton.frame.midY - symbol / 2, width: symbol, height: symbol)
    }

    private static let textShadow: NSShadow = {
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        return shadow
    }()

    private func applyMosaicTitleStyle(_ metrics: HomeMosaicCellStyle) {
        let key = "\(title.stringValue)|\(mosaicSize)"
        guard appliedTitleKey != key else { return }
        appliedTitleKey = key
        // Sin puntos suspensivos: el título largo se recorta y se desvanece (máscara).
        title.lineBreakMode = .byClipping
        title.maximumNumberOfLines = 1
        title.wantsLayer = true
        title.shadow = Self.textShadow
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        title.attributedStringValue = NSAttributedString(string: title.stringValue, attributes: [
            .font: NSFont.systemFont(ofSize: metrics.titleSize, weight: metrics.titleWeight),
            .foregroundColor: NSColor.white, .kern: metrics.titleTracking, .paragraphStyle: paragraph])
    }

    /// Los últimos 18 pt del ancho del título se desvanecen en lugar de cortarse con puntos suspensivos.
    private func updateTitleFade() {
        title.wantsLayer = true
        guard let layer = title.layer else { return }
        let width = max(1, title.bounds.width)
        titleFadeMask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        titleFadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        titleFadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        titleFadeMask.locations = [0, NSNumber(value: Double(max(0, width - 18) / width)), 1]
        titleFadeMask.frame = title.bounds
        if layer.mask !== titleFadeMask { layer.mask = titleFadeMask }
    }

    private func installFeaturedLayers() {
        if featuredArtwork.superlayer == nil { cover.layer?.insertSublayer(featuredArtwork, at: 0) }
        if featuredGradient.superlayer == nil {
            cover.layer?.addSublayer(featuredGradient)
            paintScrimColors()
        }
        featuredGradient.isHidden = !featuredSong
    }

    /// Degradado inferior: 72 % del alto (52 % en la grande) con las cinco paradas de `HomeCoverScrim`.
    private func layoutScrim(_ metrics: HomeMosaicCellStyle) {
        let height = cover.bounds.height * metrics.gradientFraction
        // Las subcapas de una vista volteada miden hacia abajo. `layer.isGeometryFlipped` no lo
        // refleja (AppKit voltea en un ancestro), así que manda la vista: con él el velo quedaba arriba.
        let flipped = cover.isFlipped
        featuredGradient.frame = CGRect(x: 0, y: flipped ? cover.bounds.height - height : 0, width: cover.bounds.width, height: height)
        // Parada 0 abajo y 1 arriba, sea cual sea la orientación de la capa.
        featuredGradient.startPoint = CGPoint(x: 0.5, y: flipped ? 1 : 0)
        featuredGradient.endPoint = CGPoint(x: 0.5, y: flipped ? 0 : 1)
        featuredGradient.locations = HomeCoverScrim.stops.map { NSNumber(value: $0.location) }
    }

    private func paintScrimColors() {
        let base = HomeCoverScrim.color(cover: scrimCover)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        featuredGradient.colors = HomeCoverScrim.stops.map { base.nsColor.withAlphaComponent($0.alpha).cgColor }
        CATransaction.commit()
    }

    /// Fija el color de carátula del degradado (`nil` = color de reserva).
    private func applyScrim(cover rgb: HomeAmbientRGB?) {
        scrimCover = rgb
        featuredScrimCoverForTesting = rgb
        guard featuredSong else { return }
        installFeaturedLayers()
        paintScrimColors()
    }

    /// Pinta de inmediato el color en caché (sin parpadeo al reciclar) o el de reserva.
    private func paintCachedCoverColor(for record: HomeItemRecord) {
        guard featuredSong else { return }
        if let url = record.thumbnail, let session = coverSession, let hit = coverColorStore.cached(url: url, session: session) {
            applyScrim(cover: hit)
        } else { applyScrim(cover: nil) }
    }

    /// Color de la carátula a partir de la imagen ya decodificada, sin pedirla otra vez a la red.
    private func requestCoverColor(image: CGImage?) {
        guard featuredSong, let image, let url = representedRecord?.thumbnail, let session = coverSession else { return }
        if let hit = coverColorStore.cached(url: url, session: session) { applyScrim(cover: hit); return }
        colorTask?.cancel()
        let expected = generation
        let store = coverColorStore
        colorTask = Task { @MainActor [weak self] in
            let color = await store.color(url: url, session: session, image: { image })
            guard !Task.isCancelled, let self, self.generation == expected else { return }
            self.applyScrim(cover: color)
        }
    }

    /// Zoom de la portada al 104 % dentro de su marco: 250 ms; sin transición con Reduce Motion.
    private func setArtworkZoom(_ zoomed: Bool) {
        guard artworkZoomed != zoomed || featuredArtwork.transform.m11 != (zoomed ? 1.04 : 1) else { return }
        artworkZoomed = zoomed
        let scale: CGFloat = zoomed ? 1.04 : 1
        CATransaction.begin()
        if reducesMotion() { CATransaction.setDisableActions(true) }
        else {
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setAnimationTimingFunction(Self.mosaicEase)
        }
        featuredArtwork.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
    }

    var featuredArtworkScaleForTesting: CGFloat { featuredArtwork.transform.m11 }
    var featuredTitleFrameForTesting: NSRect { title.frame }
    var featuredArtistFrameForTesting: NSRect { largeArtistLabel.frame }
    var featuredPlayFrameForTesting: NSRect { playButton.frame }
    var featuredPlayVisibleForTesting: Bool { !playButton.isHidden }
    var featuredTitleFontForTesting: NSFont? { title.attributedStringValue.length > 0 ? title.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : title.font }
    var featuredArtistFontForTesting: NSFont? { largeArtistLabel.font }
    var featuredEqualizerFrameForTesting: NSRect { equalizerOverlay.frame }
    var featuredGradientFrameForTesting: CGRect { featuredGradient.frame }
    var featuredGradientAlphasForTesting: [CGFloat] {
        (featuredGradient.colors as? [CGColor] ?? []).map { $0.alpha }
    }
    var featuredTitleMaskedForTesting: Bool { title.layer?.mask != nil }

    // MARK: Tarjeta de colección

    private static let hoverEase = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)

    private var collectionPalette: HomeCollectionCardPalette { .make(albumCardStyle) }

    /// Pone las piezas propias de la tarjeta de colección (panel, atenuación de portada, sombra) la primera vez.
    private func installCollectionChrome() {
        guard !collectionChromeInstalled else { return }
        collectionChromeInstalled = true
        addSubview(collectionPanel, positioned: .below, relativeTo: title)
        coverDim.backgroundColor = NSColor.black.cgColor
        coverDim.opacity = 0
        cover.layer?.addSublayer(coverDim)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = .zero
        applyCollectionStyle()
    }

    /// La celda vuelve a un modo distinto de colección: sin panel, sombra ni elevación.
    private func leaveCollectionChrome() {
        guard collectionChromeInstalled else { return }
        collectionChromeInstalled = false
        resetCollectionChrome()
        collectionPanel.removeFromSuperview()
        coverDim.removeFromSuperlayer()
        layer?.shadowOpacity = 0
        layer?.shadowPath = nil
    }

    /// Estado de reposo, sin transiciones: se usa al reciclar la celda.
    private func resetCollectionChrome() {
        collectionLifted = false
        coverDim.removeAllAnimations()
        coverDim.opacity = 0
        if let layer {
            layer.removeAllAnimations()
            layer.transform = CATransform3DIdentity
            layer.zPosition = 0
        }
        playGlass?.removeFromSuperview(); playGlass = nil
        moreGlass?.removeFromSuperview(); moreGlass = nil
        isMoreHovered = false
        collectionPanel.setWash(nil)
    }

    /// Fuentes, colores y textos del panel según el acabado. Se llama al cambiar de registro, de acabado o de modo;
    /// `layout()` sólo coloca marcos.
    private func applyCollectionStyle() {
        guard featuredCollection else { return }
        installCollectionChrome()
        let palette = collectionPalette
        collectionPanel.apply(palette: palette)
        let record = representedRecord
        let badge = HomeCollectionBadge.text(kind: record?.kind ?? "", subtitle: record?.subtitle)
        let tail = NSMutableParagraphStyle()
        tail.lineBreakMode = .byTruncatingTail
        typeLabel.attributedStringValue = NSAttributedString(string: badge, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold), .kern: 1.2, .foregroundColor: palette.muted, .paragraphStyle: tail])
        typeLabel.maximumNumberOfLines = 1
        typeLabel.lineBreakMode = .byTruncatingTail
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = palette.title
        title.maximumNumberOfLines = 1
        title.lineBreakMode = .byTruncatingTail
        largeArtistLabel.maximumNumberOfLines = 1
        largeArtistLabel.lineBreakMode = .byTruncatingTail
        largeArtistLabel.cell?.wraps = false
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = palette.muted
        subtitle.maximumNumberOfLines = 2
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.cell?.wraps = true
        refreshArtistAppearance()
        needsLayout = true
    }

    private static let collectionArtistFont = NSFont.systemFont(ofSize: 14, weight: .medium)

    /// Artista o creador: color del acabado; con puntero o foco, negro y subrayado como un enlace.
    private func applyCollectionArtistAppearance() {
        guard featuredCollection, !artist.isHidden else { return }
        let palette = collectionPalette
        let emphasized = artist.isEnabled && (isArtistHovered || window?.firstResponder === artist)
        artist.title = ""
        artist.isTransparent = true
        let tail = NSMutableParagraphStyle()
        tail.lineBreakMode = .byTruncatingTail
        largeArtistLabel.attributedStringValue = NSAttributedString(string: rawArtistTitle, attributes: [
            .font: Self.collectionArtistFont, .foregroundColor: emphasized ? palette.artistHover : palette.artist,
            .underlineStyle: emphasized ? NSUnderlineStyle.single.rawValue : 0, .paragraphStyle: tail])
        collectionArtistWidth = ceil((rawArtistTitle as NSString).size(withAttributes: [.font: Self.collectionArtistFont]).width) + 2
        needsLayout = true
    }

    /// Sólo marcos y capas: sin medir texto ni crear fuentes, porque se ejecuta en cada cuadro de un resize.
    private func layoutCollectionCard() {
        installCollectionChrome()
        typealias Metrics = HomeCollectionCardMetrics
        let width = max(0, bounds.width)
        let side = Metrics.paddingSide
        let textWidth = max(0, width - 2 * side)
        layer?.cornerRadius = 0
        layer?.masksToBounds = false
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor

        // Portada cuadrada arriba. Su marco (y el del velo de reproducción) se alarga un radio por debajo
        // del panel, que va encima y lo tapa: con las cuatro esquinas redondeadas sólo se ven las de arriba
        // y la unión con el panel queda recta, sin depender de `maskedCorners`.
        let artSquare = CGRect(x: 0, y: 0, width: width, height: width)
        cover.frame = NSRect(x: 0, y: 0, width: width, height: width + Metrics.cornerRadius)
        cover.imageScaling = .scaleAxesIndependently
        cover.layer?.cornerRadius = Metrics.cornerRadius
        cover.layer?.borderWidth = 0
        if featuredArtwork.superlayer == nil { cover.layer?.insertSublayer(featuredArtwork, at: 0) }
        setArtworkGeometry(in: artSquare)
        featuredArtwork.masksToBounds = true
        featuredFooter.isHidden = true
        featuredGradient.isHidden = true
        coverDim.frame = artSquare
        equalizerOverlay.frame = cover.frame
        equalizerOverlay.setCornerRadius(Metrics.cornerRadius)
        equalizerOverlay.updateStyle(compact: false)
        equalizerOverlay.updateInline(nil)
        if title.layer?.mask != nil { title.layer?.mask = nil }

        // Panel claro: 12 + 14 + 2 + 22 + 19 + 6 + 32 + 14 = 121.
        collectionPanel.frame = NSRect(x: 0, y: width, width: width, height: Metrics.panelHeight)
        var y = width + Metrics.paddingTop
        typeLabel.frame = NSRect(x: side, y: y, width: textWidth, height: Metrics.badgeHeight)
        y += Metrics.badgeHeight + Metrics.badgeBottom
        title.frame = NSRect(x: side, y: y, width: textWidth, height: Metrics.titleHeight)
        y += Metrics.titleHeight
        largeArtistLabel.frame = NSRect(x: side, y: y, width: textWidth, height: Metrics.artistHeight)
        // El enlace ocupa sólo el texto, no toda la fila.
        artist.frame = NSRect(x: side, y: y, width: min(textWidth, collectionArtistWidth), height: Metrics.artistHeight)
        largeArtistLabel.isHidden = artist.isHidden
        y += Metrics.artistHeight + Metrics.summaryGap
        subtitle.frame = NSRect(x: side, y: y, width: textWidth, height: Metrics.summaryHeight)
        bullet.isHidden = true
        explicitBadge.isHidden = true
        album.isHidden = true

        // Play (abajo a la izquierda) y menú (abajo a la derecha): 38 pt a 12 pt de los bordes de la portada.
        let diameter = Metrics.controlDiameter, inset = Metrics.controlInset
        playButton.frame = NSRect(x: inset, y: width - inset - diameter, width: diameter, height: diameter)
        playButton.layer?.cornerRadius = diameter / 2
        let icon = Metrics.controlIcon
        playSymbol.frame = NSRect(x: playButton.frame.midX - icon / 2, y: playButton.frame.midY - icon / 2, width: icon, height: icon)
        more.frame = NSRect(x: width - inset - diameter, y: width - inset - diameter, width: diameter, height: diameter)
        more.layer?.backgroundColor = NSColor.clear.cgColor
        playGlass?.frame = playButton.frame
        moreGlass?.frame = more.frame
        loadingIndicator?.frame = playSymbol.frame.insetBy(dx: -1, dy: -1)

        applyShadowModel(collectionLifted ? Metrics.liftedShadow : Metrics.restShadow)
    }

    private func shadowPath(_ shadow: HomeCollectionCardMetrics.Shadow) -> CGPath {
        var rect = bounds.insetBy(dx: shadow.inset, dy: shadow.inset)
        // El eje Y de las capas de una vista volteada crece hacia abajo.
        rect.origin.y += isFlipped ? shadow.offset : -shadow.offset
        let radius = max(0, min(HomeCollectionCardMetrics.cornerRadius, min(rect.width, rect.height) / 2))
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private func applyShadowModel(_ shadow: HomeCollectionCardMetrics.Shadow) {
        guard let layer else { return }
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOffset = .zero
        layer.shadowOpacity = shadow.opacity
        layer.shadowRadius = shadow.radius
        layer.shadowPath = shadowPath(shadow)
    }

    private func liftTransform(_ lifted: Bool) -> CATransform3D {
        // Hacia arriba: negativo cuando el contenedor tiene el eje Y hacia abajo.
        let up: CGFloat = (superview?.isFlipped ?? false) ? -1 : 1
        return lifted ? CATransform3DMakeTranslation(0, up * HomeCollectionCardMetrics.lift, 0) : CATransform3DIdentity
    }

    /// Hover o foco: sube 4 pt (transformación, no marco) en 180 ms, queda sobre las vecinas, la sombra pasa a
    /// `0 20 34 −18` al 80 % y la portada se atenúa con negro al 30 % en 150 ms. Con Reduce Motion, al instante.
    private func setCollectionLifted(_ lifted: Bool) {
        guard collectionChromeInstalled, let layer, lifted != collectionLifted else { return }
        collectionLifted = lifted
        typealias Metrics = HomeCollectionCardMetrics
        layer.zPosition = lifted ? (hovered ? 2 : 1) : 0
        let shadow = lifted ? Metrics.liftedShadow : Metrics.restShadow
        let animated = !reducesMotion() && window != nil
        let fromTransform = layer.presentation()?.transform ?? layer.transform
        let fromPath = layer.presentation()?.shadowPath ?? layer.shadowPath
        let fromRadius = layer.presentation()?.shadowRadius ?? layer.shadowRadius
        let fromOpacity = layer.presentation()?.shadowOpacity ?? layer.shadowOpacity
        let fromDim = coverDim.presentation()?.opacity ?? coverDim.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = liftTransform(lifted)
        applyShadowModel(shadow)
        coverDim.opacity = lifted ? Metrics.dimOpacity : 0
        CATransaction.commit()
        guard animated else {
            layer.removeAllAnimations()
            coverDim.removeAllAnimations()
            return
        }
        func animation(_ keyPath: String, from: Any?, to: Any?, duration: CFTimeInterval) -> CABasicAnimation {
            let value = CABasicAnimation(keyPath: keyPath)
            value.fromValue = from
            value.toValue = to
            value.duration = duration
            value.timingFunction = Self.hoverEase
            return value
        }
        layer.add(animation("transform", from: NSValue(caTransform3D: fromTransform), to: NSValue(caTransform3D: layer.transform), duration: Metrics.hoverDuration), forKey: "lift")
        layer.add(animation("shadowPath", from: fromPath, to: layer.shadowPath, duration: Metrics.hoverDuration), forKey: "shadowPath")
        layer.add(animation("shadowRadius", from: fromRadius, to: layer.shadowRadius, duration: Metrics.hoverDuration), forKey: "shadowRadius")
        layer.add(animation("shadowOpacity", from: fromOpacity, to: layer.shadowOpacity, duration: Metrics.hoverDuration), forKey: "shadowOpacity")
        coverDim.add(animation("opacity", from: fromDim, to: coverDim.opacity, duration: Metrics.dimDuration), forKey: "dim")
    }

    /// Círculos de vidrio de Play y menú, sólo para la tarjeta que los muestra.
    private func syncGlassControls() {
        guard featuredCollection else { return }
        let solid = reducesTransparency()
        func sync(_ glass: inout HomeGlassCircleView?, visible: Bool, highlighted: Bool, frame: NSRect) {
            guard visible else { glass?.isHidden = true; return }
            if let current = glass, current.isSolid != solid { current.removeFromSuperview(); glass = nil }
            if glass == nil {
                let created = HomeGlassCircleView(solid: solid)
                created.setAccessibilityElement(false)
                created.frame = frame
                addSubview(created, positioned: .below, relativeTo: playSymbol)
                glass = created
            }
            glass?.isHidden = false
            glass?.highlighted = highlighted
        }
        sync(&playGlass, visible: !playButton.isHidden, highlighted: isPlayButtonHovered, frame: playButton.frame)
        sync(&moreGlass, visible: !more.isHidden, highlighted: isMoreHovered, frame: more.frame)
        needsLayout = true
    }

    /// Lavado de la portada para el acabado teñido: una vez por carátula, fuera del hilo principal.
    /// Se descarta si la celda se recicló a otro registro (generación) o el carril se desmontó (`prepareForReuse`).
    private func refreshWash() {
        guard featuredCollection else { return }
        washTask?.cancel()
        washTask = nil
        guard collectionPalette.washed, let url = representedRecord?.thumbnail, let session = coverSession else {
            collectionPanel.setWash(nil)
            return
        }
        if let hit = coverWashStore.cached(url: url, session: session) {
            collectionPanel.setWash(hit)
            return
        }
        collectionPanel.setWash(nil)
        guard let image = coverBitmap else { return }
        let expected = generation
        let store = coverWashStore
        washTask = Task { @MainActor [weak self] in
            let wash = await store.wash(url: url, session: session, image: { image })
            guard !Task.isCancelled, let self, self.generation == expected, self.collectionPalette.washed else { return }
            self.collectionPanel.setWash(wash)
        }
    }

    var collectionWashForTesting: CGImage? { collectionPanel.washImage }
    var collectionPanelFrameForTesting: NSRect { collectionPanel.frame }
    var collectionBadgeFrameForTesting: NSRect { typeLabel.frame }
    var collectionBadgeTextForTesting: String { typeLabel.stringValue }
    var collectionTitleFrameForTesting: NSRect { title.frame }
    var collectionArtistLabelFrameForTesting: NSRect { largeArtistLabel.frame }
    var collectionArtistLinkFrameForTesting: NSRect { artist.frame }
    var collectionSummaryFrameForTesting: NSRect { subtitle.frame }
    var collectionCoverFrameForTesting: NSRect { cover.frame }
    var collectionTextColorsForTesting: (badge: NSColor?, title: NSColor?, artist: NSColor?, summary: NSColor?) {
        func color(_ field: NSTextField) -> NSColor? {
            field.attributedStringValue.length > 0
                ? field.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor : field.textColor
        }
        return (color(typeLabel), title.textColor, color(largeArtistLabel), subtitle.textColor)
    }
    var collectionPanelColorForTesting: NSColor? { collectionPanel.surfaceColor.flatMap { NSColor(cgColor: $0) } }
    var collectionPanelSurfaceFrameForTesting: CGRect { collectionPanel.surfaceFrame }
    var collectionLiftForTesting: CGFloat { layer?.transform.m42 ?? 0 }
    var collectionIsLiftedForTesting: Bool { collectionLifted }
    var collectionZPositionForTesting: CGFloat { layer?.zPosition ?? 0 }
    var collectionShadowForTesting: (opacity: Float, radius: CGFloat, box: CGRect) {
        (layer?.shadowOpacity ?? 0, layer?.shadowRadius ?? 0, layer?.shadowPath?.boundingBoxOfPath ?? .null)
    }
    var collectionDimOpacityForTesting: Float { coverDim.opacity }
    var collectionGlassForTesting: (play: HomeGlassCircleView?, more: HomeGlassCircleView?) { (playGlass, moreGlass) }
    var collectionPlayControlFrameForTesting: NSRect { playButton.frame }
    var collectionMoreControlFrameForTesting: NSRect { more.frame }
    var collectionArtworkFrameForTesting: CGRect { featuredArtwork.frame }
    /// Orden de las subvistas: en el mosaico el icono va sobre el círculo blanco; en el resto, bajo el vidrio.
    var playSymbolIsAboveCircleForTesting: Bool {
        guard let symbol = subviews.firstIndex(of: playSymbol), let button = subviews.firstIndex(of: playButton) else { return false }
        return symbol > button
    }
    var typeLabelForTesting: NSAttributedString { typeLabel.attributedStringValue }
    var collectionArtistFontForTesting: NSFont? {
        largeArtistLabel.attributedStringValue.length > 0
            ? largeArtistLabel.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : largeArtistLabel.font
    }
    var collectionSummaryFontForTesting: NSFont? { subtitle.font }
    var largeArtistLabelHiddenForTesting: Bool { largeArtistLabel.isHidden }
    var collectionArtistUnderlinedForTesting: Bool {
        guard largeArtistLabel.attributedStringValue.length > 0 else { return false }
        return (largeArtistLabel.attributedStringValue.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) != 0
    }
    var coverDimDurationForTesting: CFTimeInterval { coverDim.animation(forKey: "dim")?.duration ?? 0 }
    var collectionCardAnimationKeysForTesting: [String] { (layer?.animationKeys() ?? []) + (coverDim.animationKeys() ?? []) }

    static func parseSubtitleComponents(_ rawSubtitle: String?) -> [String] {
        guard let raw = rawSubtitle, !raw.isEmpty else { return [] }
        return raw.components(separatedBy: " • ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func isGenericTypePrefix(_ text: String) -> Bool {
        let lower = text.lowercased()
        let prefixes = ["album", "álbum", "single", "sencillo", "ep", "song", "canción", "video", "vídeo", "playlist", "lista", "mix"]
        return prefixes.contains(lower)
    }

    static func cleanArtistName(from record: HomeItemRecord) -> String {
        if record.kind == "song" || record.kind == "video" {
            return HomeSongMetadata.artist(from: record)
        }
        if let artists = record.artists, !artists.isEmpty {
            return artists
        }
        if let linkedArtist = record.artistRuns.first(where: { $0.id != nil })?.text, !linkedArtist.isEmpty {
            return linkedArtist
        }
        let comps = parseSubtitleComponents(record.subtitle)
        if let first = comps.first {
            if isGenericTypePrefix(first) && comps.count > 1 {
                return comps[1]
            } else if !isGenericTypePrefix(first) {
                return first
            }
        }
        return record.subtitle ?? L10n.text("metadata.various_artists")
    }

    static func cleanAlbumName(from record: HomeItemRecord) -> String? {
        if record.kind == "song" || record.kind == "video" {
            return HomeSongMetadata.album(from: record)
        }
        if record.kind == "album" || record.kind == "artist" {
            return nil
        }
        if let album = record.album, !album.isEmpty {
            return album
        }
        let comps = parseSubtitleComponents(record.subtitle)
        let startIndex: Int
        if let first = comps.first, isGenericTypePrefix(first) {
            startIndex = 2
        } else {
            startIndex = 1
        }
        if comps.count > startIndex {
            let candidate = comps[startIndex]
            if candidate.range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
                return nil
            }
            if candidate.range(of: #"^\d+:\d{2}$"#, options: .regularExpression) != nil {
                return nil
            }
            let lower = candidate.lowercased()
            if lower.contains("vistas") || lower.contains("views") || lower.contains("reproducciones") {
                return nil
            }
            return candidate
        }
        return nil
    }

    private var representedKind = ""

    func configure(
        record: HomeItemRecord, style: HomeSectionStyle,
        currentTrackID: String?,
        currentAlbumBrowseId: String? = nil,
        currentPlaylistBrowseId: String? = nil,
        isPlaying: Bool,
        queueContext: QueueContext? = nil,
        onCard: @escaping () -> Void, onCover: @escaping () -> Void, onTitle: @escaping () -> Void,
        onArtist: @escaping () -> Void, onFeatured: ((String?,String)->Void)? = nil, onAlbum: @escaping () -> Void,
        onDirectPlay: (() -> Void)? = nil,
        menuProvider: @escaping () -> NSMenu?
    ) {
        let samePresentation = representedRecord == record && self.style == style
            && ((record.kind == "song" && onFeatured != nil) == !songArtistLinks.isHidden)
        if representedID != nil && !samePresentation { prepareForReuse() }
        self.style = style
        representedID = record.id
        representedRecord = record
        representedKind = record.kind
        self.onCard = onCard
        self.onCover = onCover
        self.onTitle = onTitle
        self.onArtist = onArtist
        self.onAlbum = onAlbum
        self.onDirectPlay = onDirectPlay
        self.menuProvider = menuProvider
        if record.kind == "song", let onFeatured {
            let track = SongItemRecord(fromHomeItem:record)
            title.configureFeatured(track:track,isTitle:true,onNavigate:onFeatured)
            songArtistLinks.configureFeatured(track:track,isTitle:false,onNavigate:onFeatured)
            if songArtistLinks.superview == nil { addSubview(songArtistLinks) }; songArtistLinks.isHidden = false
        } else { title.clearFeatured(); songArtistLinks.clearFeatured(); songArtistLinks.isHidden = true; songArtistLinks.removeFromSuperview() }
        if samePresentation {
            if !songArtistLinks.isHidden { artist.isHidden = true; largeArtistLabel.isHidden = true }
            refreshMetadataAccessibility(for: record)
            updatePlayback(
                currentTrackID: currentTrackID,
                currentAlbumBrowseId: currentAlbumBrowseId,
                currentPlaylistBrowseId: currentPlaylistBrowseId,
                isPlaying: isPlaying,
                queueContext: queueContext
            )
            return
        }

        cardButton.title = ""
        cardButton.isTransparent = true
        cardButton.toolTip = record.title
        title.stringValue = record.title
        title.font = style == .compactSong ? .systemFont(ofSize: 13, weight: .semibold) : Self.largeTitleFont
        title.maximumNumberOfLines = style == .compactSong ? 1 : 2
        title.toolTip = record.title
        let typeName = Self.displayType(for: record)
        typeLabel.stringValue = typeName

        let artistName = Self.cleanArtistName(from: record)
        rawArtistTitle = artistName
        compactArtistTextWidth = ceil((artistName as NSString).size(withAttributes: [.font: Self.compactArtistMeasureFont]).width) + 2
        measuredLargeCardWidth = -1
        artist.title = artistName
        largeArtistLabel.stringValue = artistName
        largeArtistLabel.toolTip = artistName
        artist.toolTip = artistName
        let hasArtistDestination = (record.artistId ?? record.artistRuns.first(where: { $0.id?.isEmpty == false })?.id)?.isEmpty == false
        artist.isEnabled = hasArtistDestination
        artist.setAccessibilityLabel(hasArtistDestination ? L10n.text("home.artist.view", args: [artistName]) : L10n.text("home.artist.label", args: [artistName]))
        rawAlbumTitle = Self.cleanAlbumName(from: record) ?? ""
        album.title = rawAlbumTitle
        let hasAlbumDestination = record.albumId?.isEmpty == false
        album.isEnabled = hasAlbumDestination
        album.setAccessibilityLabel(hasAlbumDestination ? L10n.text("home.album.view", args: [rawAlbumTitle]) : L10n.text("home.album.label", args: [rawAlbumTitle]))

        let creatorHasLink = record.kind == "playlist" && record.artistRuns.contains { $0.id?.isEmpty == false }
        // La tarjeta de colección muestra siempre el creador (con enlace sólo si hay ID), como Windows.
        let artistCanShow = !artistName.isEmpty && record.kind != "artist" && (featuredCollection || record.kind != "playlist" || creatorHasLink)
        subtitle.stringValue = record.kind == "playlist" && !creatorHasLink ? (record.subtitle ?? "") : ""
        let showsAlbum = style == .compactSong && record.kind == "song" && !rawAlbumTitle.isEmpty
        let showsSubtitle = style == .largeCard && !subtitle.stringValue.isEmpty
        showMetadata(artist, when: artistCanShow)
        showMetadata(largeArtistLabel, when: style == .largeCard && artistCanShow, below: artist)
        showMetadata(album, when: showsAlbum)
        showMetadata(typeLabel, when: style == .largeCard)
        showMetadata(subtitle, when: showsSubtitle)
        showMetadata(bullet, when: style == .compactSong ? artistCanShow && showsAlbum : artistCanShow || showsSubtitle)
        explicitBadge.rating = record.effectiveContentRating
        showMetadata(explicitBadge, when: record.effectiveContentRating != .unknown)

        if !songArtistLinks.isHidden { artist.isHidden = true; largeArtistLabel.isHidden = true }
        refreshMetadataAccessibility(for: record)
        refreshArtistAppearance()
        updatePlayback(
            currentTrackID: currentTrackID,
            currentAlbumBrowseId: currentAlbumBrowseId,
            currentPlaylistBrowseId: currentPlaylistBrowseId,
            isPlaying: isPlaying,
            queueContext: queueContext
        )
        refreshAppearance()
        needsLayout = true
        paintCachedCoverColor(for: record)

        let featuredRequest = Self.featuredArtworkRequest(song: featuredSong, collection: featuredCollection, size: mosaicSize)
        refreshWash()
        guard let url = ImageURLHelper.optimizedThumbnailURL(
            from: record.thumbnail, targetPixelSize: featuredRequest?.pixels ?? (style == .compactSong ? 112 : 320)
        ) else {
            cover.image = NSImage(systemSymbolName: record.kind == "artist" ? "person.crop.circle" : "music.note", accessibilityDescription: nil)
            cover.contentTintColor = .secondaryLabelColor
            return
        }
        let target = featuredRequest?.target ?? (style == .compactSong ? CGSize(width: 48, height: 48) : CGSize(width: 156, height: 156))
        if let cached = ImageCache.shared.imageFromMemoryCache(for: url, targetSize: target) {
            setArtwork(cached)
            return
        }
        let expectedGeneration = generation
        let loader = artworkLoader
        artworkRequestCount += 1
        imageTask = Task(priority: .utility) { @MainActor [weak self] in
            let image = if let loader { await loader(url, target) } else { await ImageCache.shared.image(for: url, targetSize: target) }
            guard !Task.isCancelled else { return }
            guard let self, self.generation == expectedGeneration else { return }
            self.setArtwork(image)
        }
    }

    func setArtwork(_ image: NSImage?) {
        if featuredSong || featuredCollection {
            cover.image = nil
            let bitmap = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            featuredArtwork.contents = bitmap
            featuredArtworkSizeForTesting = bitmap.map { CGSize(width: $0.width, height: $0.height) }
            featuredArtwork.contentsGravity = .resizeAspectFill
            cover.layer?.masksToBounds = true
            requestCoverColor(image: bitmap)
            if featuredCollection { coverBitmap = bitmap; refreshWash() }
        } else { cover.image = image }
    }

    private static func displayType(for record: HomeItemRecord) -> String {
        if record.kind == "album", let prefix = Self.parseSubtitleComponents(record.subtitle).first?.lowercased() {
            switch prefix {
            case "single", "sencillo": return L10n.text("metadata.single")
            case "ep": return "EP"
            case "album", "álbum": return L10n.text("metadata.album")
            default: break
            }
        }
        return switch record.kind {
        case "song": L10n.text("metadata.song")
        case "video": L10n.text("search.filter.videos")
        case "album": L10n.text("metadata.album")
        case "artist": L10n.text("search.filter.artists")
        default: L10n.text("metadata.playlist")
        }
    }

    private func refreshMetadataAccessibility(for record: HomeItemRecord) {
        // Missing provider names are presentation fallbacks, never translated identities.
        if record.title.isEmpty {
            title.stringValue = Self.displayType(for: record)
            title.toolTip = title.stringValue
            cardButton.toolTip = title.stringValue
        }
        let artistName = Self.cleanArtistName(from: record)
        if rawArtistTitle != artistName {
            rawArtistTitle = artistName
            artist.title = artistName
            largeArtistLabel.stringValue = artistName
            largeArtistLabel.toolTip = artistName
            artist.toolTip = artistName
            compactArtistTextWidth = ceil((artistName as NSString).size(withAttributes: [.font: Self.compactArtistMeasureFont]).width) + 2
            measuredLargeCardWidth = -1
            refreshArtistAppearance()
        }
        // La tarjeta de colección muestra su etiqueta propia (`applyCollectionStyle`); aquí sólo el texto accesible.
        if !featuredCollection { typeLabel.stringValue = Self.displayType(for: record) }
        let hasArtistDestination = (record.artistId ?? record.artistRuns.first(where: { $0.id?.isEmpty == false })?.id)?.isEmpty == false
        let hasAlbumDestination = record.albumId?.isEmpty == false
        artist.setAccessibilityLabel(rawArtistTitle.isEmpty ? "" : L10n.text(hasArtistDestination ? "home.artist.view" : "home.artist.label", args: [rawArtistTitle]))
        album.setAccessibilityLabel(rawAlbumTitle.isEmpty ? "" : L10n.text(hasAlbumDestination ? "home.album.view" : "home.album.label", args: [rawAlbumTitle]))
        let rating = explicitBadge.rating
        explicitBadge.rating = rating
        more.setAccessibilityLabel(L10n.text("home.more_options"))
    }

    func refreshLocalization(currentTrackID: String?, currentAlbumBrowseId: String?,
                             currentPlaylistBrowseId: String?, isPlaying: Bool,
                             queueContext: QueueContext?) {
        guard let record = representedRecord else { return }
        if !songArtistLinks.isHidden { artist.isHidden = true; largeArtistLabel.isHidden = true }
        refreshMetadataAccessibility(for: record)
        updatePlayback(currentTrackID: currentTrackID, currentAlbumBrowseId: currentAlbumBrowseId,
                       currentPlaylistBrowseId: currentPlaylistBrowseId, isPlaying: isPlaying,
                       queueContext: queueContext)
    }

    private func refreshArtistAppearance() {
        guard !artist.isHidden else { return }
        let text = rawArtistTitle.isEmpty ? artist.title : rawArtistTitle
        guard !text.isEmpty else { return }
        if featuredCollection { applyCollectionArtistAppearance(); return }
        let isHovered = isArtistHovered
        if style == .largeCard {
            artist.title = ""
            artist.isTransparent = true
            if featuredSong {
                largeArtistLabel.textColor = isHovered ? .white : NSColor.white.withAlphaComponent(0.72)
            } else {
                largeArtistLabel.textColor = isHovered ? .labelColor : .secondaryLabelColor
            }
            return
        }
        artist.isTransparent = false
        let font = NSFont.systemFont(ofSize: 11.5, weight: isHovered ? .semibold : .medium)
        let color: NSColor = isHovered ? .labelColor : .secondaryLabelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .left

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        artist.attributedTitle = NSAttributedString(string: text, attributes: attrs)
    }

    private func refreshAlbumAppearance() {
        guard !album.isHidden else { return }
        let text = rawAlbumTitle.isEmpty ? album.title : rawAlbumTitle
        guard !text.isEmpty else { return }
        let isHovered = isAlbumHovered
        let font = NSFont.systemFont(ofSize: 11.5, weight: isHovered ? .semibold : .medium)
        let color: NSColor = isHovered ? .labelColor : .secondaryLabelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .left

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        album.attributedTitle = NSAttributedString(string: text, attributes: attrs)
    }

    func updatePlayback(
        currentTrackID: String?,
        currentAlbumBrowseId: String? = nil,
        currentPlaylistBrowseId: String? = nil,
        isPlaying: Bool,
        queueContext: QueueContext? = nil
    ) {
        let isSongMatch = representedKind == "song" &&
            MediaPlaybackIdentity.isRadioOrigin(videoID: representedID ?? "", context: queueContext)
        let isAlbumMatch = representedKind == "album" &&
            MediaPlaybackIdentity.isCollectionActive(kind: "album", id: representedID ?? "", context: queueContext)
        let isPlaylistMatch = (representedKind == "playlist" || representedKind == "mix") &&
            MediaPlaybackIdentity.isCollectionActive(kind: "playlist", id: representedID ?? "", context: queueContext)

        isCurrent = isSongMatch || isAlbumMatch || isPlaylistMatch
        playing = isCurrent && isPlaying

        let typeName = representedRecord.map(Self.displayType(for:)) ?? typeLabel.stringValue
        let metadata = [typeName, explicitBadge.isHidden ? nil : ContentRatingMetadata.label(explicitBadge.rating),
                        rawArtistTitle.isEmpty ? nil : rawArtistTitle,
                        rawAlbumTitle.isEmpty ? nil : rawAlbumTitle]
            .compactMap { $0 }
            .joined(separator: " · ")
        let action = playing ? L10n.text("home.pause") : (representedKind == "song" ? L10n.text("home.play") : L10n.text("home.open"))
        let actionLabel = L10n.text("home.card.accessibility", args: [action, title.stringValue, metadata])
        cover.setAccessibilityLabel(actionLabel)
        cardButton.setAccessibilityLabel(actionLabel)
        playButton.setAccessibilityLabel(L10n.text(playing ? "home.pause_named" : "home.play_named", args: [title.stringValue]))
        cardButton.title = ""
        cardButton.isTransparent = true
        refreshAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        showsDirectPlayControl = true
        setLoading(false)
        imageTask?.cancel()
        imageTask = nil
        colorTask?.cancel()
        colorTask = nil
        washTask?.cancel()
        washTask = nil
        coverBitmap = nil
        if collectionChromeInstalled { resetCollectionChrome() }
        scrimCover = nil
        featuredScrimCoverForTesting = nil
        if featuredGradient.superlayer != nil { paintScrimColors() }
        appliedTitleKey = nil
        mosaicPlayVisible = false
        artworkZoomed = false
        CATransaction.begin(); CATransaction.setDisableActions(true)
        featuredArtwork.transform = CATransform3DIdentity
        CATransaction.commit()
        generation &+= 1
        equalizerOverlay.stopAnimating()
        isCurrent = false
        playing = false
        playButton.isHidden = true
        onDirectPlay = nil
        representedID = nil
        representedRecord = nil
        title.clearFeatured(); songArtistLinks.clearFeatured(); songArtistLinks.isHidden = true; songArtistLinks.removeFromSuperview()
        representedKind = ""
        compactArtistTextWidth = 0
        measuredLargeCardWidth = -1
        cardButton.title = ""
        cardButton.isTransparent = true
        cover.image = nil
        featuredArtwork.contents = nil
        featuredArtworkSizeForTesting = nil
        cover.contentTintColor = nil
        hovered = false
        isArtistHovered = false
        isAlbumHovered = false
        rawArtistTitle = ""
        rawAlbumTitle = ""
        artist.isEnabled = true
        album.isEnabled = true
        explicitBadge.rating = .unknown
        isPlayButtonHovered = false
        isMoreHovered = false
        renderedAppearance = nil
        onCard = nil
        onCover = nil
        onTitle = nil
        onArtist = nil
        onAlbum = nil
        menuProvider = nil
    }

    func setHovered(_ value: Bool, localPoint: NSPoint? = nil) {
        if hovered != value { hovered = value }
        if !value {
            if isPlayButtonHovered || isMoreHovered {
                isPlayButtonHovered = false
                isMoreHovered = false
                refreshAppearance()
            }
            if isArtistHovered {
                isArtistHovered = false
        refreshArtistAppearance()
        refreshAlbumAppearance()
            }
            if isAlbumHovered {
                isAlbumHovered = false
                refreshAlbumAppearance()
            }
        } else if let localPoint {
            updateHoverLocation(localPoint)
        }
    }

    func setFeedVisible(_ visible: Bool) {
        feedVisible = visible
        title.setFeaturedVisible(visible)
        songArtistLinks.setFeaturedVisible(visible)
        equalizerOverlay.setFeedVisible(visible)
        if loading {
            if visible { loadingIndicator?.startAnimation(nil) }
            else { loadingIndicator?.stopAnimation(nil) }
        }
    }

    /// Optional collection loading state. Mount a spinner only while it is used,
    /// preserving the small Home control hierarchy for every other card.
    func setLoading(_ value: Bool) {
        guard loading != value else { return }
        loading = value
        if value {
            let indicator = loadingIndicator ?? NSProgressIndicator()
            loadingIndicator = indicator
            indicator.style = .spinning
            indicator.controlSize = .small
            indicator.isDisplayedWhenStopped = false
            // Trazo oscuro sobre el círculo blanco del mosaico; claro sobre el vidrio del resto.
            indicator.appearance = NSAppearance(named: featuredSong ? .aqua : .darkAqua)
            indicator.setAccessibilityLabel(L10n.text("home.loading_named", args: [title.stringValue]))
            indicator.frame = playSymbol.frame.insetBy(dx: -1, dy: -1)
            addSubview(indicator)
            if feedVisible { indicator.startAnimation(nil) }
        } else {
            loadingIndicator?.stopAnimation(nil)
            loadingIndicator?.removeFromSuperview()
        }
        refreshAppearance()
    }

    func updateHoverLocation(_ point: NSPoint) {
        let overPlayButton = !playButton.isHidden && playButton.frame.contains(point)
        let overMore = featuredCollection && !more.isHidden && more.frame.contains(point)
        if isPlayButtonHovered != overPlayButton || isMoreHovered != overMore {
            isPlayButtonHovered = overPlayButton
            isMoreHovered = overMore
            refreshAppearance()
        }
        if artist.isEnabled && !artist.isHidden {
            let overArtist = artist.frame.contains(point)
            if isArtistHovered != overArtist {
                isArtistHovered = overArtist
                refreshArtistAppearance()
            }
        }
        if album.isEnabled && !album.isHidden {
            let overAlbum = album.frame.contains(point)
            if isAlbumHovered != overAlbum {
                isAlbumHovered = overAlbum
                refreshAlbumAppearance()
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // AppKit entrega el punto en coordenadas del superview. Resolver primero los
        // controles hermanos evita que el botón de portada oculte Play/menú según el
        // orden de inserción de subviews al reciclar una tarjeta.
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        guard bounds.contains(localPoint) else { return nil }
        for field in [title,songArtistLinks] where !field.isHidden {
            if let hit = field.hitTest(convert(localPoint,to:field.superview)), hit is NativeFeaturedArtistButton { return hit }
        }
        if let event = NSApp.currentEvent,
           event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            return self
        }
        if !playButton.isHidden, playButton.isEnabled, playButton.frame.contains(localPoint) {
            return playButton
        }
        if !more.isHidden, more.isEnabled, more.frame.contains(localPoint) {
            return more
        }
        if !artist.isHidden, artist.isEnabled, artist.frame.contains(localPoint) {
            return artist
        }
        if !album.isHidden, album.isEnabled, album.frame.contains(localPoint) {
            return album
        }
        if !cover.isHidden, cover.isEnabled, cover.frame.contains(localPoint) {
            return cover
        }
        return cardButton.isHidden || !cardButton.isEnabled ? nil : cardButton
    }
    func currentMenuForTesting() -> NSMenu? { menuProvider?() }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = menuProvider?() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
        else { super.rightMouseDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let menu = menuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else { super.mouseDown(with: event) }
    }

    private var focusWithinCard: Bool {
        containsResponderInCard(window?.firstResponder)
    }

    func containsResponderInCard(_ responder: NSResponder?) -> Bool {
        guard var focusedView = responder as? NSView else { return false }
        while true {
            if focusedView === self { return true }
            guard let parent = focusedView.superview else { return false }
            focusedView = parent
        }
    }

    private func scheduleFocusAppearanceRefresh() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.refreshAppearance()
        }
    }

    private func refreshAppearance() {
        let next = Appearance(hovered: hovered, selected: isSelectedInFeed,
                              playing: playing, isCurrent: isCurrent, compactSong: style == .compactSong,
                              playButtonHovered: isPlayButtonHovered, feedVisible: feedVisible,
                              reduceMotion: reducesMotion(),
                              focusWithinCard: focusWithinCard, loading: loading,
                              mosaicSize: featuredSong ? mosaicSize : nil,
                              collection: featuredCollection, moreHovered: isMoreHovered,
                              artistFocused: featuredCollection && window?.firstResponder === artist,
                              reduceTransparency: featuredCollection && reducesTransparency())
        guard renderedAppearance != next else { return }
        renderedAppearance = next
        let isHighlighted = hovered || isSelectedInFeed || focusWithinCard || loading
        // En el mosaico el ecualizador va en línea y no se oculta con hover; la grande muestra siempre Play.
        let showsPlay = isHighlighted || (featuredSong && mosaicSize == .large)
        equalizerOverlay.setIndicatorSuppressed(!featuredSong && isCurrent && isHighlighted)
        if style == .compactSong {
            playButton.layer?.backgroundColor = NSColor.clear.cgColor
            playButton.layer?.cornerRadius = AppTheme.artworkThumbnailRadius
            layer?.backgroundColor = (isHighlighted ? NSColor.white.withAlphaComponent(0.08) : NSColor.clear).cgColor
            layer?.borderColor = NSColor.clear.cgColor
        } else {
            playButton.wantsLayer = true
            let isCollection = representedKind == "album" || representedKind == "playlist"
            // En la tarjeta de colección el círculo es el vidrio de detrás; el botón es sólo el área de clic.
            let fill = featuredSong
                ? NSColor.white
                : (featuredCollection ? NSColor.clear : isCollection && isPlayButtonHovered
                    ? AppTheme.nsAccent.withAlphaComponent(0.98)
                    : NSColor.black.withAlphaComponent(0.62))
            playButton.layer?.backgroundColor = fill.cgColor
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = NSColor.clear.cgColor
        }

        if playing {
            equalizerOverlay.startAnimating()
            if showsPlay {
                playSymbol.isHidden = false
                playSymbol.image = pauseImage
            } else {
                playSymbol.isHidden = true
            }
        } else if isCurrent {
            equalizerOverlay.pauseAnimation()
            if showsPlay {
                playSymbol.isHidden = false
                playSymbol.image = playImage
            } else {
                playSymbol.isHidden = true
            }
        } else {
            equalizerOverlay.stopAnimating()
            playSymbol.isHidden = !showsPlay
            playSymbol.image = playImage
        }
        playButton.isHidden = !showsPlay || !showsDirectPlayControl
        playButton.isEnabled = !loading && showsDirectPlayControl
        if loading || !showsDirectPlayControl { playSymbol.isHidden = true }
        playSymbol.contentTintColor = featuredSong ? Self.mosaicPlayIcon : .white
        loadingIndicator?.appearance = NSAppearance(named: featuredSong ? .aqua : .darkAqua)
        equalizerOverlay.setMotionEnabled(!reducesMotion())
        equalizerOverlay.setFeedVisible(feedVisible)
        if featuredSong {
            setArtworkZoom((hovered || focusWithinCard) && !reducesMotion())
            let playVisible = !playButton.isHidden
            if mosaicPlayVisible != playVisible { mosaicPlayVisible = playVisible }
            needsLayout = true
        }

        more.contentTintColor = NSColor.white.withAlphaComponent(isHighlighted ? 1.0 : 0.82)
        more.isHidden = !isHighlighted
        if featuredCollection {
            installCollectionChrome()
            setCollectionLifted(hovered || focusWithinCard)
            syncGlassControls()
            applyCollectionArtistAppearance()
        }
    }

    @objc private func playButtonPressed() { onDirectPlay?() }
    @objc private func cardPressed() { (onCard ?? onCover ?? onTitle)?() }
    @objc private func coverPressed() { cardPressed() }
    @objc private func artistPressed() { onArtist?() }
    @objc private func albumPressed() { onAlbum?() }
    @objc private func morePressed() {
        menuProvider?()?.popUp(positioning: nil, at: NSPoint(x: 0, y: more.bounds.height), in: more)
    }
}
