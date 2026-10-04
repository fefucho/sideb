import AppKit
import SwiftUI
import SideBCore

/// Un solo viewport vertical; los estantes horizontales son secciones del layout nativo.
struct HomeFeedCollectionView: NSViewRepresentable {
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
        collection.setAccessibilityLabel("Recomendaciones de Inicio")
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

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDelegate {
        static let headerKind = "HomeSectionHeader"
        static let footerSection = "__home_pagination__"
        static let footerItem = "__home_load_more__"

        var parent: HomeFeedCollectionView
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
                    header.configure(title: section.title, showsMore: section.isNavigableMore,
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

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        configureOrthogonalScrollViews(in: subview)
    }

    override func layout() {
        super.layout()
        // Compositional layout owns these orthogonal scroll views and may tile
        // them again as sections are laid out or reused.
        for subview in subviews { configureOrthogonalScrollViews(in: subview) }
    }

    private func configureOrthogonalScrollViews(in view: NSView) {
        if let scroll = view as? NSScrollView {
            scroll.hasHorizontalScroller = false
            scroll.horizontalScroller = nil
            scroll.hasVerticalScroller = false
            scroll.drawsBackground = false
            scroll.horizontalScrollElasticity = .allowed
            scroll.contentView.postsBoundsChangedNotifications = true
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

    private func stopObservingScrollViews(in view: NSView) {
        if let scroll = view as? NSScrollView {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification,
                                                      object: scroll.contentView)
            observedClipViews.remove(scroll.contentView)
        }
        for child in view.subviews { stopObservingScrollViews(in: child) }
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
    private let more = NSButton(title: "Ver todo", target: nil, action: nil)
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
        more.setAccessibilityLabel("Ver todo")
        addSubview(more)
        for (button, symbol, selector, label) in [
            (previous, "chevron.left", #selector(scrollPrevious), "Desplazar estante a la izquierda"),
            (next, "chevron.right", #selector(scrollNext), "Desplazar estante a la derecha")
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
        self.more.isHidden = !showsMore
        self.previous.isHidden = !showsArrows
        self.next.isHidden = !showsArrows
        self.more.setAccessibilityLabel("Ver todo: \(title)")
        self.action = action
        previousAction = previous
        nextAction = next
    }
    @objc private func openMore() { action?() }
    @objc private func scrollPrevious() { previousAction?() }
    @objc private func scrollNext() { nextAction?() }
}

private final class HomeLoadMoreItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("HomeLoadMore")
    private let button = NSButton(title: "Cargar más recomendaciones", target: nil, action: nil)
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
        self.action = action
        button.title = loading ? "Cargando recomendaciones…" : "Cargar más recomendaciones"
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

private final class HomeCardTitleLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class HomeItemView: NSView {
    // Dos líneas de título y detalle, más las separaciones. Compartido con el layout del estante.
    static let largeCardTextHeight: CGFloat = 94
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
    private let album = HomeInteractiveLinkButton()
    private let subtitle = NSTextField(labelWithString: "")
    private let bullet = NSTextField(labelWithString: "•")
    private let typeLabel = NSTextField(labelWithString: "")
    private let explicitBadge = NSTextField(labelWithString: "E")
    private let more = HomeInteractiveLinkButton()
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
        playButton.setAccessibilityLabel("Reproducir")

        title.font = Self.largeTitleFont
        title.textColor = .labelColor
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        title.cell?.wraps = true
        title.setAccessibilityElement(false)
        addSubview(title)

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

        explicitBadge.font = .systemFont(ofSize: 10, weight: .bold)
        explicitBadge.textColor = .black
        explicitBadge.alignment = .center
        explicitBadge.wantsLayer = true
        explicitBadge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.78).cgColor
        explicitBadge.layer?.cornerRadius = 3
        explicitBadge.setAccessibilityLabel("Contenido explícito")

        setup(more, selector: #selector(morePressed), font: nil)
        more.onFocusChanged = { [weak self] in self?.scheduleFocusAppearanceRefresh() }
        more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Más opciones")
        more.imagePosition = .imageOnly
        more.contentTintColor = NSColor.white.withAlphaComponent(0.78)
        more.setAccessibilityLabel("Más opciones")
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

            let badgeWidth: CGFloat = explicitBadge.isHidden ? 0 : 18
            explicitBadge.frame = NSRect(x: textLeading, y: 31, width: 14, height: 14)
            let metadataLeading = textLeading + badgeWidth
            let artistWidth = artist.isHidden ? 0 : min(compactArtistTextWidth, max(0, maxTextWidth - badgeWidth))
            artist.frame = NSRect(x: metadataLeading, y: 30, width: artistWidth, height: 17)
            let separatorX = metadataLeading + artistWidth + 3
            bullet.frame = NSRect(x: separatorX, y: 30, width: 10, height: 17)
            bullet.isHidden = artist.isHidden || album.isHidden
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
            let badgeWidth: CGFloat = explicitBadge.isHidden ? 0 : 20
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
            explicitBadge.frame = NSRect(x: 0, y: metadataY + 1, width: 15, height: 15)
            let metadataLeading = badgeWidth
            typeLabel.frame = NSRect(x: metadataLeading, y: metadataY, width: measuredTypeWidth, height: 17)
            let showMetadataDetail = !artist.isHidden || !subtitle.isHidden
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
        cover.layer?.cornerRadius = style == .compactSong
            ? AppTheme.artworkThumbnailRadius
            : (representedKind == "artist" ? bounds.width / 2 : AppTheme.artworkCardRadius)
        CATransaction.commit()
    }

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
        return record.subtitle ?? "Varios Artistas"
    }

    static func cleanAlbumName(from record: HomeItemRecord) -> String? {
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
        onArtist: @escaping () -> Void, onAlbum: @escaping () -> Void,
        onDirectPlay: (() -> Void)? = nil,
        menuProvider: @escaping () -> NSMenu?
    ) {
        let samePresentation = representedRecord == record && self.style == style
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
        if samePresentation {
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
        artist.setAccessibilityLabel(hasArtistDestination ? "Ver artista: \(artistName)" : "Artista: \(artistName)")
        rawAlbumTitle = Self.cleanAlbumName(from: record) ?? ""
        album.title = rawAlbumTitle
        let hasAlbumDestination = record.albumId?.isEmpty == false
        album.isEnabled = hasAlbumDestination
        album.setAccessibilityLabel(hasAlbumDestination ? "Ver álbum: \(rawAlbumTitle)" : "Álbum: \(rawAlbumTitle)")

        let creatorHasLink = record.kind == "playlist" && record.artistRuns.contains { $0.id?.isEmpty == false }
        let artistCanShow = !artistName.isEmpty && record.kind != "artist" && (record.kind != "playlist" || creatorHasLink)
        subtitle.stringValue = record.kind == "playlist" && !creatorHasLink ? (record.subtitle ?? "") : ""
        let showsAlbum = style == .compactSong && record.kind == "song" && !rawAlbumTitle.isEmpty
        let showsSubtitle = style == .largeCard && !subtitle.stringValue.isEmpty
        showMetadata(artist, when: artistCanShow)
        showMetadata(largeArtistLabel, when: style == .largeCard && artistCanShow, below: artist)
        showMetadata(album, when: showsAlbum)
        showMetadata(typeLabel, when: style == .largeCard)
        showMetadata(subtitle, when: showsSubtitle)
        showMetadata(bullet, when: style == .compactSong ? artistCanShow && showsAlbum : artistCanShow || showsSubtitle)
        showMetadata(explicitBadge, when: record.explicit)

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

        guard let url = ImageURLHelper.optimizedThumbnailURL(
            from: record.thumbnail, targetPixelSize: style == .compactSong ? 112 : 320
        ) else {
            cover.image = NSImage(systemSymbolName: record.kind == "artist" ? "person.crop.circle" : "music.note", accessibilityDescription: nil)
            cover.contentTintColor = .secondaryLabelColor
            return
        }
        let target = style == .compactSong ? CGSize(width: 48, height: 48) : CGSize(width: 156, height: 156)
        if let cached = ImageCache.shared.imageFromMemoryCache(for: url, targetSize: target) {
            cover.image = cached
            return
        }
        let expectedGeneration = generation
        imageTask = Task(priority: .utility) { @MainActor [weak self] in
            let image = await ImageCache.shared.image(for: url, targetSize: target)
            guard !Task.isCancelled else { return }
            guard let self, self.generation == expectedGeneration else { return }
            self.cover.image = image
        }
    }

    private static func displayType(for record: HomeItemRecord) -> String {
        if record.kind == "album", let prefix = Self.parseSubtitleComponents(record.subtitle).first?.lowercased() {
            switch prefix {
            case "single", "sencillo": return "Sencillo"
            case "ep": return "EP"
            case "album", "álbum": return "Álbum"
            default: break
            }
        }
        return switch record.kind {
        case "song": "Canción"
        case "album": "Álbum"
        case "artist": "Artista"
        default: "Playlist"
        }
    }

    private func refreshArtistAppearance() {
        guard !artist.isHidden else { return }
        let text = rawArtistTitle.isEmpty ? artist.title : rawArtistTitle
        guard !text.isEmpty else { return }
        let isHovered = isArtistHovered
        if style == .largeCard {
            artist.title = ""
            artist.isTransparent = true
            largeArtistLabel.textColor = isHovered ? .labelColor : .secondaryLabelColor
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

        let metadata = [typeLabel.stringValue, explicitBadge.isHidden ? nil : "Explícita",
                        rawArtistTitle.isEmpty ? nil : rawArtistTitle,
                        rawAlbumTitle.isEmpty ? nil : rawAlbumTitle]
            .compactMap { $0 }
            .joined(separator: " · ")
        let action = playing ? "Pausar" : (representedKind == "song" ? "Reproducir" : "Abrir")
        let actionLabel = "\(action) \(title.stringValue). \(metadata)"
        cover.setAccessibilityLabel(actionLabel)
        cardButton.setAccessibilityLabel(actionLabel)
        playButton.setAccessibilityLabel(playing ? "Pausar \(title.stringValue)" : "Reproducir \(title.stringValue)")
        cardButton.title = ""
        cardButton.isTransparent = true
        refreshAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        generation &+= 1
        equalizerOverlay.stopAnimating()
        isCurrent = false
        playing = false
        playButton.isHidden = true
        onDirectPlay = nil
        representedID = nil
        representedRecord = nil
        representedKind = ""
        compactArtistTextWidth = 0
        measuredLargeCardWidth = -1
        cardButton.title = ""
        cardButton.isTransparent = true
        cover.image = nil
        cover.contentTintColor = nil
        hovered = false
        isArtistHovered = false
        isAlbumHovered = false
        rawArtistTitle = ""
        rawAlbumTitle = ""
        artist.isEnabled = true
        album.isEnabled = true
        explicitBadge.isHidden = true
        isPlayButtonHovered = false
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
            if isPlayButtonHovered {
                isPlayButtonHovered = false
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
        equalizerOverlay.setFeedVisible(visible)
    }

    func updateHoverLocation(_ point: NSPoint) {
        let overPlayButton = !playButton.isHidden && playButton.frame.contains(point)
        if isPlayButtonHovered != overPlayButton {
            isPlayButtonHovered = overPlayButton
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
                              reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                              focusWithinCard: focusWithinCard)
        guard renderedAppearance != next else { return }
        renderedAppearance = next
        let isHighlighted = hovered || isSelectedInFeed || focusWithinCard
        equalizerOverlay.setIndicatorSuppressed(isCurrent && isHighlighted)
        if style == .compactSong {
            playButton.layer?.backgroundColor = NSColor.clear.cgColor
            playButton.layer?.cornerRadius = AppTheme.artworkThumbnailRadius
            layer?.backgroundColor = (isHighlighted ? NSColor.white.withAlphaComponent(0.08) : NSColor.clear).cgColor
            layer?.borderColor = NSColor.clear.cgColor
        } else {
            playButton.wantsLayer = true
            let isCollection = representedKind == "album" || representedKind == "playlist"
            let fill = isCollection && isPlayButtonHovered
                ? AppTheme.nsAccent.withAlphaComponent(0.98)
                : NSColor.black.withAlphaComponent(0.62)
            playButton.layer?.backgroundColor = fill.cgColor
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = NSColor.clear.cgColor
        }

        if playing {
            equalizerOverlay.startAnimating()
            if isHighlighted {
                playSymbol.isHidden = false
                playSymbol.image = pauseImage
            } else {
                playSymbol.isHidden = true
            }
        } else if isCurrent {
            equalizerOverlay.pauseAnimation()
            if isHighlighted {
                playSymbol.isHidden = false
                playSymbol.image = playImage
            } else {
                playSymbol.isHidden = true
            }
        } else {
            equalizerOverlay.stopAnimating()
            playSymbol.isHidden = !isHighlighted
            playSymbol.image = playImage
        }
        playButton.isHidden = !isHighlighted
        playSymbol.contentTintColor = .white
        equalizerOverlay.setMotionEnabled(!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        equalizerOverlay.setFeedVisible(feedVisible)

        more.contentTintColor = NSColor.white.withAlphaComponent(isHighlighted ? 1.0 : 0.82)
        more.isHidden = !isHighlighted
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
