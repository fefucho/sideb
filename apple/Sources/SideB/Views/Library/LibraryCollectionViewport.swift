import AppKit
import SwiftUI
import SideBCore

/// Cache the filtered/sorted snapshot across scroll and playback observation updates.
@MainActor final class LibraryCardProjectionCache {
    private var source: [BrowseCardRecord] = []
    private var query: String?
    private var order: String?
    private var projected: [BrowseCardRecord] = []
    private(set) var projectionCount = 0
    func cards(_ source: [BrowseCardRecord], query: String, order: String,
               project: () -> [BrowseCardRecord]) -> [BrowseCardRecord] {
        guard self.source != source || self.query != query || self.order != order else { return projected }
        self.source = source; self.query = query; self.order = order
        projected = project(); projectionCount += 1
        return projected
    }
}

/// Flat, recycled cells and an explicitly measured viewport, following Explore/Home.
/// Header/tools remain SwiftUI; the catalog never creates a hosting view per card.
struct LibraryCollectionViewport: NSViewRepresentable {
    @Environment(\.sideBGesturePreviewVisible) private var gesturePreviewVisible
    let localizationRevision = L10n.revision
    let cards: [BrowseCardRecord]
    let tab: String
    let accountRevision: UInt
    let list: Bool
    @Binding var scrollOffset: CGFloat
    var pinned: Set<String> = []
    var isObscured = false
    var queueContext: QueueContext? = nil
    var isPlaying = false
    var loadingAlbumID: String? = nil
    var loadingPlaylistID: String? = nil
    let onOpen: (BrowseCardRecord) -> Void
    let onPlay: (BrowseCardRecord) -> Void
    let onPin: (BrowseCardRecord) -> Void
    let menuProvider: (BrowseCardRecord) -> NSMenu?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSScrollView { makeScrollView(coordinator: context.coordinator) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 800, height: proposal.height ?? 600)
    }
    func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scroll = HomeFeedScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true; scroll.horizontalScrollElasticity = .none; scroll.verticalScrollElasticity = .allowed
        scroll.automaticallyAdjustsContentInsets = false
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 18; layout.minimumLineSpacing = list ? 8 : 24
        let collection = HomeNativeCollectionView()
        collection.backgroundColors = [.clear]; collection.isSelectable = true; collection.allowsMultipleSelection = false
        collection.autoresizingMask = [.width]; collection.collectionViewLayout = layout
        collection.register(LibraryCollectionItem.self, forItemWithIdentifier: LibraryCollectionItem.identifier)
        collection.dataSource = coordinator; collection.delegate = coordinator
        collection.setAccessibilityLabel(L10n.text("library.title") + " · " + tab)
        collection.onActivateSelection = { [weak coordinator] in coordinator?.open(at: $0) }
        collection.onHoverPosition = { [weak coordinator] in coordinator?.updateHover(at: $0) }
        collection.onViewportMoved = { [weak coordinator] in coordinator?.scheduleHoverUpdate() }
        scroll.documentView = collection
        coordinator.collection = collection; coordinator.scroll = scroll; coordinator.layout = layout
        scroll.onViewportLayout = { [weak coordinator] in coordinator?.updateGeometry() }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.boundsChanged(_:)), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        scroll.isHidden = isObscured && !gesturePreviewVisible
        scroll.setAccessibilityHidden(isObscured)
        collection.reloadData(); coordinator.updateGeometry()
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { updateScrollView(scroll, coordinator: context.coordinator) }
    func updateScrollView(_ scroll: NSScrollView, coordinator: Coordinator) {
        scroll.setAccessibilityHidden(isObscured)
        if isObscured {
            if !coordinator.isSuspended {
                coordinator.updateHover(at: nil)
                for case let item as LibraryCollectionItem in coordinator.collection?.visibleItems() ?? [] {
                    item.cell.setVisible(false)
                }
            }
            coordinator.isSuspended = true
            scroll.isHidden = !gesturePreviewVisible
            return
        }
        let resumed = coordinator.isSuspended
        coordinator.isSuspended = false
        let old = coordinator.parent
        coordinator.parent = self
        guard let collection = coordinator.collection else { return }
        let reset = old.tab != tab || old.accountRevision != accountRevision
        scroll.isHidden = isObscured && !gesturePreviewVisible
        if reset || old.list != list || old.cards != cards {
            coordinator.updateHover(at: nil)
            let identityChanged = reset || old.list != list || old.cards.map(LibraryPin.key) != cards.map(LibraryPin.key)
            if identityChanged {
                collection.selectionIndexPaths = []; collection.reloadData()
            } else { coordinator.configureVisibleItems() }
            coordinator.invalidateGeometry()
            if reset { coordinator.pendingOffset = scrollOffset }
        }
        if old.localizationRevision != localizationRevision {
            collection.setAccessibilityLabel(L10n.text("library.title") + " · " + tab)
            coordinator.configureVisibleItems()
        }
        if old.pinned != pinned { coordinator.updateVisiblePins() }
        if old.queueContext != queueContext || old.isPlaying != isPlaying || old.loadingAlbumID != loadingAlbumID || old.loadingPlaylistID != loadingPlaylistID {
            coordinator.updateVisiblePlayback()
        }
        if resumed || old.isObscured != isObscured {
            coordinator.updateHover(at: nil)
            for case let item as LibraryCollectionItem in collection.visibleItems() { item.cell.setVisible(!isObscured) }
        }
        coordinator.updateGeometry()
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        (scroll as? HomeFeedScrollView)?.onViewportLayout = nil
        coordinator.updateHover(at: nil)
        if let collection = coordinator.collection {
            for case let item as LibraryCollectionItem in collection.visibleItems() { item.cell.prepareForReuse() }
            collection.dataSource = nil; collection.delegate = nil
            collection.onActivateSelection = nil; collection.onHoverPosition = nil; collection.onViewportMoved = nil
        }
        coordinator.collection = nil; coordinator.scroll = nil
    }

    @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var isSuspended = false
        var parent: LibraryCollectionViewport
        weak var collection: HomeNativeCollectionView?
        weak var scroll: NSScrollView?
        weak var layout: NSCollectionViewFlowLayout?
        private weak var hoveredItem: LibraryCollectionItem?
        private var lastWidth: CGFloat = -1
        private var hoverScheduled = false
        private var adjustingGeometry = false
        var pendingOffset: CGFloat?
        private(set) var configuredItems = 0
        init(parent: LibraryCollectionViewport) { self.parent = parent; pendingOffset = parent.scrollOffset }
        deinit { NotificationCenter.default.removeObserver(self) }
        func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { parent.cards.count }
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: LibraryCollectionItem.identifier, for: indexPath) as! LibraryCollectionItem
            configure(item, at: indexPath); return item
        }
        func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
            guard let item = item as? LibraryCollectionItem else { return }
            configure(item, at: indexPath)
        }
        func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
            guard let item = item as? LibraryCollectionItem else { return }
            if hoveredItem === item { updateHover(at: nil) }
            item.cell.prepareForReuse()
        }
        private func card(at index: IndexPath) -> BrowseCardRecord? {
            guard index.section == 0, parent.cards.indices.contains(index.item) else { return nil }
            return parent.cards[index.item]
        }
        func configure(_ item: LibraryCollectionItem, at index: IndexPath) {
            guard let card = card(at: index) else { return }
            configuredItems += 1
            item.cell.configure(card: card, list: parent.list, pinned: parent.pinned.contains(LibraryPin.key(card)),
                onOpen: { [weak self] in self?.open(card) },
                onPlay: { [weak self] in guard let self, !self.isSuspended && !self.parent.isObscured, !self.isLoading(card) else { return }; self.parent.onPlay(card) },
                onPin: { [weak self] in guard let self, !self.isSuspended && !self.parent.isObscured else { return }; self.parent.onPin(card) },
                menuProvider: { [weak self] in guard let self, !self.isSuspended && !self.parent.isObscured else { return nil }; return self.parent.menuProvider(card) })
            updatePlayback(item.cell, card: card)
            item.cell.setVisible(!isSuspended && !parent.isObscured)
        }
        private func open(_ card: BrowseCardRecord) { if !isSuspended && !parent.isObscured { parent.onOpen(card) } }
        func open(at index: IndexPath) { if let card = card(at: index) { open(card) } }
        func configureVisibleItems() {
            guard let collection else { return }
            for index in collection.indexPathsForVisibleItems() {
                if let item = collection.item(at: index) as? LibraryCollectionItem { configure(item, at: index) }
            }
        }
        private func isLoading(_ card: BrowseCardRecord) -> Bool {
            if card.kind == "album" { return parent.loadingAlbumID.map(MenuIDNormalizer.normalize) == MenuIDNormalizer.normalize(card.id) }
            if card.kind == "playlist" { return parent.loadingPlaylistID.map(MenuIDNormalizer.canonicalPlaylistId) == MenuIDNormalizer.canonicalPlaylistId(card.id) }
            return false
        }
        private func updatePlayback(_ cell: LibraryCollectionCell, card: BrowseCardRecord) {
            cell.updatePlayback(isPlaying: parent.isPlaying, queueContext: parent.queueContext, loading: isLoading(card))
        }
        func updateVisiblePlayback() {
            guard let collection else { return }
            for index in collection.indexPathsForVisibleItems() {
                if let card = card(at: index), let item = collection.item(at: index) as? LibraryCollectionItem { updatePlayback(item.cell, card: card) }
            }
        }
        func updateVisiblePins() {
            guard let collection else { return }
            for index in collection.indexPathsForVisibleItems() {
                if let card = card(at: index), let item = collection.item(at: index) as? LibraryCollectionItem { item.cell.updatePin(parent.pinned.contains(LibraryPin.key(card))) }
            }
        }
        func invalidateGeometry() { lastWidth = -1 }
        func updateGeometry() {
            guard !isSuspended else { return }
            guard !adjustingGeometry, let scroll, let collection, let layout else { return }
            let width = scroll.contentView.bounds.width
            guard width > 80, scroll.contentView.bounds.height > 1 else { return }
            guard abs(lastWidth - width) > 0.5 || pendingOffset != nil else { return }
            adjustingGeometry = true; defer { adjustingGeometry = false }
            lastWidth = width
            let available = max(1, width - 76.8)
            let columns = max(1, Int((available + 18) / 178))
            let itemWidth = min(220, floor((available - CGFloat(columns - 1) * 18) / CGFloat(columns)))
            layout.minimumLineSpacing = parent.list ? 8 : 24
            layout.sectionInset = NSEdgeInsets(top: 20, left: 38.4, bottom: 130, right: 38.4)
            layout.itemSize = parent.list ? NSSize(width: available, height: 68) : NSSize(width: max(1, itemWidth), height: max(1, itemWidth) + HomeItemView.largeCardTextHeight + 24)
            collection.frame.size.width = width
            layout.invalidateLayout()
            collection.layoutSubtreeIfNeeded()
            let height = max(scroll.contentView.bounds.height, layout.collectionViewContentSize.height)
            collection.frame.size.height = height
            if let offset = pendingOffset, scroll.contentView.bounds.height > 1, width > 1 {
                pendingOffset = nil
                scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, offset), max(0, height - scroll.contentView.bounds.height))))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        @objc func boundsChanged(_ notification: Notification) {
            guard !isSuspended else { return }
            updateGeometry(); scheduleHoverUpdate()
            guard !adjustingGeometry, pendingOffset == nil, let scroll, !isSuspended && !parent.isObscured else { return }
            let offset = scroll.contentView.bounds.minY
            if abs(parent.scrollOffset - offset) > 0.5 { parent.scrollOffset = offset }
        }
        func scheduleHoverUpdate() {
            guard !hoverScheduled else { return }; hoverScheduled = true
            Task { @MainActor [weak self] in
                await Task.yield(); guard let self else { return }; self.hoverScheduled = false
                guard let collection = self.collection, let window = collection.window, !self.isSuspended && !self.parent.isObscured else { self.updateHover(at: nil); return }
                self.updateHover(at: collection.convert(window.mouseLocationOutsideOfEventStream, from: nil))
            }
        }
        func updateHover(at point: NSPoint?) {
            guard let collection, let point, !isSuspended && !parent.isObscured, collection.visibleRect.contains(point),
                  let index = collection.indexPathForItem(at: point), let item = collection.item(at: index) as? LibraryCollectionItem else {
                hoveredItem?.cell.setHovered(false); hoveredItem = nil; return
            }
            if hoveredItem !== item { hoveredItem?.cell.setHovered(false); hoveredItem = item }
            item.cell.setHovered(true, point: item.cell.convert(point, from: collection))
        }
    }
}

@MainActor final class LibraryCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("LibraryCollectionItem")
    var cell: LibraryCollectionCell { view as! LibraryCollectionCell }
    override func loadView() { view = LibraryCollectionCell() }
    override func prepareForReuse() { super.prepareForReuse(); cell.prepareForReuse() }
    override var isSelected: Bool { didSet { if isViewLoaded { cell.cardView.isSelectedInFeed = isSelected } } }
}

@MainActor final class LibraryCollectionCell: NSView {
    let cardView = HomeItemView()
    let pin = NSButton()
    private(set) var row: LibraryCollectionRow?
    private var card: BrowseCardRecord?
    private var list = false
    private var onPin: (() -> Void)?
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pin.bezelStyle = .inline; pin.isBordered = false; pin.target = self; pin.action = #selector(pinPressed)
        pin.imagePosition = .imageOnly; pin.contentTintColor = .secondaryLabelColor
        addSubview(pin)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    func configure(card: BrowseCardRecord, list: Bool, pinned: Bool, onOpen: @escaping () -> Void,
                   onPlay: @escaping () -> Void, onPin: @escaping () -> Void, menuProvider: @escaping () -> NSMenu?) {
        self.card = card; self.list = list; self.onPin = onPin
        if list {
            cardView.prepareForReuse(); cardView.removeFromSuperview()
            let row = self.row ?? LibraryCollectionRow(); self.row = row
            if row.superview == nil { addSubview(row, positioned: .below, relativeTo: pin) }
            row.configure(card: card, onOpen: onOpen, onPlay: onPlay, menuProvider: menuProvider)
        } else {
            row?.prepareForReuse(); row?.removeFromSuperview(); row = nil
            if cardView.superview == nil { addSubview(cardView, positioned: .below, relativeTo: pin) }
            let record = HomeItemRecord(kind: card.kind, id: card.id, title: card.displayTitle, subtitle: card.subtitle,
                thumbnail: card.thumbnail, duration: card.duration, artists: nil, artistId: nil, album: nil, albumId: nil, artistRuns: [], explicit: false)
            cardView.configure(record: record, style: .largeCard, currentTrackID: nil, isPlaying: false,
                onCard: onOpen, onCover: onOpen, onTitle: onOpen, onArtist: {}, onAlbum: {},
                onDirectPlay: card.kind == "artist" ? onOpen : onPlay, menuProvider: menuProvider)
            cardView.showsDirectPlayControl = card.kind != "artist"
        }
        updatePin(pinned); needsLayout = true
    }
    func updatePin(_ pinned: Bool) {
        guard let card else { return }
        let title = L10n.text(pinned ? "library.unpin" : "library.pin", args: [card.displayTitle])
        pin.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: nil)
        pin.contentTintColor = pinned ? NSColor(AppTheme.accentHighlight) : .secondaryLabelColor
        pin.toolTip = title; pin.setAccessibilityLabel(title)
    }
    func updatePlayback(isPlaying: Bool, queueContext: QueueContext?, loading: Bool) {
        cardView.updatePlayback(currentTrackID: nil, isPlaying: isPlaying, queueContext: queueContext)
        cardView.setLoading(loading)
        row?.updatePlayback(isPlaying: isPlaying, queueContext: queueContext, loading: loading)
    }
    func setVisible(_ visible: Bool) { cardView.setFeedVisible(visible); row?.setVisible(visible) }
    func setHovered(_ hovered: Bool, point: NSPoint? = nil) { cardView.setHovered(hovered, localPoint: point.map { cardView.convert($0, from: self) }) }
    override func layout() {
        super.layout()
        if list { row?.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - 34), height: bounds.height); pin.frame = NSRect(x: bounds.width - 30, y: 22, width: 24, height: 24) }
        else { cardView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - 24)); pin.frame = NSRect(x: 0, y: bounds.height - 24, width: 24, height: 24) }
    }
    override func prepareForReuse() { super.prepareForReuse(); cardView.prepareForReuse(); row?.prepareForReuse(); card = nil; onPin = nil }
    @objc private func pinPressed() { onPin?() }
}

/// Compact library rows retain the always available Play/pin controls and provider subtitle.
@MainActor final class LibraryCollectionRow: NSView {
    let artwork = NSButton()
    let title = NSButton()
    let subtitle = NSTextField(labelWithString: "")
    let play = NSButton()
    private var card: BrowseCardRecord?
    private var onOpen: (() -> Void)?
    private var onPlay: (() -> Void)?
    private var menuProvider: (() -> NSMenu?)?
    private var imageTask: Task<Void, Never>?
    private var generation = 0
    private var feedVisible = true
    private var artworkLoaded = false
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.cornerRadius = 8; layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
        for button in [artwork, title, play] { button.isBordered = false; button.bezelStyle = .inline; button.target = self; addSubview(button) }
        artwork.imagePosition = .imageOnly; artwork.imageScaling = .scaleAxesIndependently; artwork.wantsLayer = true; artwork.layer?.masksToBounds = true; artwork.action = #selector(openPressed)
        title.alignment = .left; title.font = .systemFont(ofSize: 13, weight: .semibold); title.lineBreakMode = .byTruncatingTail; title.action = #selector(openPressed)
        play.imagePosition = .imageOnly; play.action = #selector(playPressed)
        subtitle.font = .systemFont(ofSize: 11); subtitle.textColor = .secondaryLabelColor; subtitle.lineBreakMode = .byTruncatingTail; addSubview(subtitle)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    func configure(card: BrowseCardRecord, onOpen: @escaping () -> Void, onPlay: @escaping () -> Void, menuProvider: @escaping () -> NSMenu?) {
        let changed = self.card?.thumbnail != card.thumbnail || self.card?.id != card.id
        self.card = card; self.onOpen = onOpen; self.onPlay = onPlay; self.menuProvider = menuProvider
        title.title = card.displayTitle; title.toolTip = card.displayTitle; subtitle.stringValue = card.subtitle ?? ""
        artwork.layer?.cornerRadius = card.kind == "artist" ? 26 : AppTheme.artworkThumbnailRadius
        let label = L10n.text("library.open_card", args: [card.displayTitle]); artwork.setAccessibilityLabel(label); title.setAccessibilityLabel(label)
        play.isHidden = card.kind == "artist"
        if changed { artworkLoaded = false; loadArtwork() }
        needsLayout = true
    }
    func setVisible(_ visible: Bool) {
        guard feedVisible != visible else { return }
        feedVisible = visible
        if visible { if !artworkLoaded { loadArtwork() } }
        else { imageTask?.cancel(); imageTask = nil; generation += 1 }
    }
    private func loadArtwork() {
        imageTask?.cancel(); imageTask = nil; generation += 1
        guard let card else { return }
        artwork.image = NSImage(systemSymbolName: card.kind == "artist" ? "person.crop.circle" : "music.note.list", accessibilityDescription: nil)
        guard feedVisible, let url = ImageURLHelper.optimizedThumbnailURL(from: card.thumbnail, targetPixelSize: 112) else { return }
        let generation = self.generation
        if let image = ImageCache.shared.imageFromMemoryCache(for: url, targetSize: CGSize(width: 52, height: 52)) { artwork.image = image; artworkLoaded = true }
        else {
            imageTask = Task { @MainActor [weak self] in
                let image = await ImageCache.shared.image(for: url, targetSize: CGSize(width: 52, height: 52))
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                self.artwork.image = image; self.artworkLoaded = image != nil; self.imageTask = nil
            }
        }
    }
    func updatePlayback(isPlaying: Bool, queueContext: QueueContext?, loading: Bool) {
        guard let card else { return }
        let playing = MediaPlaybackIdentity.isCollectionActive(kind: card.kind, id: card.id, context: queueContext) && isPlaying
        play.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: nil)
        play.setAccessibilityLabel(L10n.text(playing ? "player.pause" : "player.play")); play.isEnabled = !loading
    }
    override func layout() {
        super.layout(); artwork.frame = NSRect(x: 8, y: 8, width: 52, height: 52)
        let trailing: CGFloat = play.isHidden ? 8 : 40
        title.frame = NSRect(x: 72, y: subtitle.stringValue.isEmpty ? 23 : 14, width: max(0, bounds.width - 72 - trailing), height: 22)
        subtitle.frame = NSRect(x: 72, y: 38, width: max(0, bounds.width - 72 - trailing), height: 16)
        play.frame = NSRect(x: bounds.width - 32, y: 22, width: 24, height: 24)
    }
    override func mouseDown(with event: NSEvent) { if event.modifierFlags.contains(.control) { rightMouseDown(with: event) } else { onOpen?() } }
    override func rightMouseDown(with event: NSEvent) { if let menu = menuProvider?() { NSMenu.popUpContextMenu(menu, with: event, for: self) } }
    override func prepareForReuse() { super.prepareForReuse(); imageTask?.cancel(); imageTask = nil; generation += 1; artworkLoaded = false; card = nil; artwork.image = nil; onOpen = nil; onPlay = nil; menuProvider = nil }
    @objc private func openPressed() { onOpen?() }
    @objc private func playPressed() { onPlay?() }
}
