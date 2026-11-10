import AppKit
import SwiftUI
import SideBCore

/// Uses the same collection items, image cache, focus controls and menus as the feed.
struct HomeFeaturedNativeRail: NSViewRepresentable {
    var records: [HomeItemRecord]
    var rows: Int
    var itemWidth: CGFloat
    var itemHeight: CGFloat
    var session: String
    var playback: QueueContext?
    var playing: Bool
    var loadingID: String? = nil
    /// Changes when the metadata behind `display`/`summary` changes (closures cannot be compared).
    var revision: Int = 0
    var display: (HomeItemRecord) -> HomeItemRecord = { $0 }
    var summary: (HomeItemRecord) -> String = { _ in "" }
    var onOpen: (HomeItemRecord) -> Void
    var onPlay: (HomeItemRecord) -> Void
    var onArtist: (HomeItemRecord) -> Void = { _ in }
    var menu: ((HomeItemRecord) -> NSMenu?)?
    var onVisible: ([String]) -> Void = { _ in }
    @Environment(\.sideBPageIsActive) private var pageIsActive
    func makeNSView(context: Context) -> HomeFeaturedRailView { HomeFeaturedRailView() }
    func updateNSView(_ view: HomeFeaturedRailView, context: Context) { view.apply(self, active: pageIsActive) }
    static func dismantleNSView(_ view: HomeFeaturedRailView, coordinator: ()) { view.stop() }
}

final class HomeFeaturedRailView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let collection = HomeNativeCollectionView()
    private let scroll = HomeFeaturedScrollView()
    private let flow = NSCollectionViewFlowLayout()
    private var model: HomeFeaturedNativeRail?
    private var published: [String] = []
    private var pendingAnchorID: String?
    private var suspended = Set<ObjectIdentifier>()
    private var observedClips = Set<ObjectIdentifier>()
    private var pageIsActive = true
    private(set) var visibilityUpdateCount = 0
    private let leftFade = HomeRailEdgeFade()
    private let rightFade = HomeRailEdgeFade()
    private let previous = NSButton()
    private let next = NSButton()
    private(set) var reloadCount = 0
    private(set) var configuredCount = 0
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        flow.scrollDirection = .horizontal
        flow.minimumLineSpacing = 12
        flow.minimumInteritemSpacing = 12
        collection.collectionViewLayout = flow
        collection.dataSource = self
        collection.delegate = self
        collection.backgroundColors = [.clear]
        collection.isSelectable = true
        collection.register(HomeCollectionItem.self, forItemWithIdentifier: HomeCollectionItem.identifier)
        scroll.documentView = collection
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        addSubview(scroll)
        addSubview(leftFade)
        addSubview(rightFade)
        rightFade.reversed = true
        for (button, symbol, action) in [(previous, "chevron.left", #selector(goPrevious)), (next, "chevron.right", #selector(goNext))] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.bezelStyle = .circular
            button.target = self
            button.action = action
            addSubview(button)
        }
        previous.setAccessibilityLabel(L10n.text("home.shelf.previous"))
        next.setAccessibilityLabel(L10n.text("home.shelf.next"))
        scroll.contentView.postsBoundsChangedNotifications = true
        observeScrollAncestors()
        collection.onActivateSelection = { [weak self] path in
            guard let model = self?.model, model.records.indices.contains(path.item) else { return }
            model.onOpen(model.records[path.item])
        }
        collection.onHoverPosition = { [weak self] point in
            guard let self else { return }
            for path in self.collection.indexPathsForVisibleItems() {
                guard let cell = self.collection.item(at: path) as? HomeCollectionItem else { continue }
                let local = point.map { cell.view.convert($0, from: self.collection) }
                cell.content.setHovered(local.map { cell.view.bounds.contains($0) } ?? false, localPoint: local)
            }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }
    private func observeScrollAncestors() {
        var clips = [scroll.contentView]
        var ancestor = superview
        while let view = ancestor {
            if let clip = view as? NSClipView { clips.append(clip) }
            ancestor = view.superview
        }
        let identities = Set(clips.map(ObjectIdentifier.init))
        guard identities != observedClips else { return }
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        observedClips = identities
        for clip in clips {
            NotificationCenter.default.addObserver(self, selector: #selector(moved), name: NSView.boundsDidChangeNotification, object: clip)
        }
    }
    func apply(_ next: HomeFeaturedNativeRail, active: Bool = true) {
        let wasActive = pageIsActive
        pageIsActive = active
        let changed = model?.records != next.records || model?.session != next.session
        // A resize only changes item geometry, which the flow layout applies by itself.
        // Reconfiguring every visible cell on each frame is what made resizing stutter.
        let sameContent = !changed && wasActive == active && model.map {
            $0.playing == next.playing && $0.loadingID == next.loadingID && $0.playback == next.playback
                && $0.revision == next.revision && $0.rows == next.rows
        } == true
        let reset = model?.session != next.session
        if changed, !reset, let old = model {
            let index = Int(max(0, scroll.contentView.bounds.minX) / max(1, flow.itemSize.width + flow.minimumLineSpacing)) * max(1, old.rows)
            if old.records.indices.contains(index) {
                pendingAnchorID = "\(old.records[index].kind):\(old.records[index].id)"
            }
        } else if reset { pendingAnchorID = nil }
        model = next
        previous.setAccessibilityLabel(L10n.text("home.shelf.previous"))
        self.next.setAccessibilityLabel(L10n.text("home.shelf.next"))
        flow.minimumLineSpacing = next.rows == 1 ? 14 : 12
        if reset {
            for item in collection.visibleItems() { (item as? HomeCollectionItem)?.content.prepareForReuse() }
            scroll.contentView.scroll(to: .zero)
        }
        if changed { suspended.removeAll(); reloadCount += 1; collection.reloadData() }
        if !sameContent {
            for path in collection.indexPathsForVisibleItems() {
                if let cell = collection.item(at: path) as? HomeCollectionItem, active, !suspended.contains(ObjectIdentifier(cell)) { configure(cell, index: path.item) }
            }
        }
        moved()
        needsLayout = true
    }
    override func layout() {
        super.layout()
        observeScrollAncestors()
        guard let model else { return }
        let oldWidth = flow.itemSize.width
        let anchor = oldWidth > 0 ? Int(scroll.contentView.bounds.minX / (oldWidth + (model.rows == 1 ? 14 : 12))) * max(1, model.rows) : 0
        scroll.frame = bounds
        leftFade.frame = NSRect(x: 0, y: 0, width: 44, height: bounds.height)
        rightFade.frame = NSRect(x: max(0, bounds.width - 44), y: 0, width: 44, height: bounds.height)
        previous.frame = NSRect(x: 4, y: (bounds.height - 32) / 2, width: 32, height: 32)
        next.frame = NSRect(x: max(0, bounds.width - 36), y: (bounds.height - 32) / 2, width: 32, height: 32)
        let size = NSSize(width: model.itemWidth, height: model.itemHeight)
        if flow.itemSize != size {
            flow.itemSize = size
            flow.invalidateLayout()
            collection.layoutSubtreeIfNeeded()
            if model.records.indices.contains(anchor) { collection.scrollToItems(at: [IndexPath(item: anchor, section: 0)], scrollPosition: .left) }
        }
        if let pendingAnchorID {
            self.pendingAnchorID = nil
            collection.layoutSubtreeIfNeeded()
            if let index = model.records.firstIndex(where: { "\($0.kind):\($0.id)" == pendingAnchorID }) {
                collection.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .left)
            }
        }
        moved()
    }
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { model?.records.count ?? 0 }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt path: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: HomeCollectionItem.identifier, for: path) as! HomeCollectionItem
        configure(cell, index: path.item)
        return cell
    }
    private func configure(_ cell: HomeCollectionItem, index: Int) {
        guard let model, pageIsActive, model.records.indices.contains(index) else { return }
        configuredCount += 1
        let record = model.display(model.records[index])
        let song = model.rows > 1 || record.kind == "song"
        cell.view.frame.size = NSSize(width: model.itemWidth, height: model.itemHeight)
        cell.content.featuredSong = song
        cell.content.featuredCollection = !song
        cell.content.configure(record: record, style: .largeCard, currentTrackID: nil, isPlaying: model.playing, queueContext: model.playback,
            onCard: { model.onOpen(record) }, onCover: { model.onOpen(record) }, onTitle: { model.onOpen(record) },
            onArtist: { model.onArtist(record) }, onAlbum: {}, onDirectPlay: { model.onPlay(record) }, menuProvider: { model.menu?(record) })
        cell.content.applyFeaturedLayout(song: song, summary: model.summary(record))
        cell.content.setLoading(model.loadingID == record.id)
    }
    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        suspended.remove(ObjectIdentifier(item))
        (item as? HomeCollectionItem)?.content.prepareForReuse()
    }
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        guard let cell = item as? HomeCollectionItem else { return }
        suspended.remove(ObjectIdentifier(cell))
        if pageIsActive { configure(cell, index: indexPath.item) }
        else { cell.content.prepareForReuse(); suspended.insert(ObjectIdentifier(cell)) }
        cell.content.setFeedVisible(pageIsActive && !visibleRect.isEmpty && !cell.view.visibleRect.isEmpty)
    }
    @objc private func moved() {
        guard let model else { return }
        visibilityUpdateCount += 1
        for path in collection.indexPathsForVisibleItems() {
            guard let cell = collection.item(at: path) as? HomeCollectionItem else { continue }
            let id = ObjectIdentifier(cell)
            let visible = pageIsActive && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty && !cell.view.visibleRect.isEmpty
            if !visible && suspended.insert(id).inserted { cell.content.prepareForReuse() }
            else if visible && suspended.remove(id) != nil { configure(cell, index: path.item) }
            cell.content.setFeedVisible(visible)
        }
        previous.isHidden = scroll.contentView.bounds.minX <= 1
        next.isHidden = flow.collectionViewContentSize.width <= scroll.contentView.bounds.maxX + 1
        leftFade.isHidden = previous.isHidden
        rightFade.isHidden = next.isHidden
        let visible = !pageIsActive || isHiddenOrHasHiddenAncestor || visibleRect.isEmpty ? [] : HomeFeaturedRailViewport.visibleIDs(ids: model.records.map { "\($0.kind):\($0.id)" }, itemWidth: model.itemWidth, rows: max(1, model.rows), spacing: model.rows == 1 ? 14 : 12, offset: scroll.contentView.bounds.minX, width: scroll.contentSize.width)
        guard visible != published else { return }
        published = visible
        // Defer publishing out of AppKit layout / SwiftUI update.
        DispatchQueue.main.async { [weak self] in guard let self, self.published == visible else { return }; self.model?.onVisible(visible) }
    }
    @objc private func goPrevious() { advance(-1) }
    @objc private func goNext() { advance(1) }
    private func advance(_ direction: CGFloat) {
        let limit = max(0, flow.collectionViewContentSize.width - scroll.contentSize.width)
        let x = min(limit, max(0, scroll.contentView.bounds.minX + direction * scroll.contentSize.width))
        scroll.contentView.scroll(to: NSPoint(x: x, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    func stop() {
        for item in collection.visibleItems() { (item as? HomeCollectionItem)?.content.prepareForReuse() }
        model = nil
    }
}
private final class HomeFeaturedScrollView: HomeFeedScrollView, HorizontalNavigationGestureOwner {
    var ownsHorizontalNavigationGesture: Bool { true }
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            var parent = superview
            while let view = parent {
                if let outer = view as? NSScrollView, outer.hasVerticalScroller { outer.scrollWheel(with: event); return }
                parent = view.superview
            }
        }
        super.scrollWheel(with: event)
    }
}

private final class HomeRailEdgeFade: NSView {
    var reversed = false
    private let gradient = CAGradientLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(gradient)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        gradient.frame = bounds
        gradient.colors = [NSColor.black.withAlphaComponent(0.22).cgColor, NSColor.clear.cgColor]
        gradient.startPoint = CGPoint(x: reversed ? 1 : 0, y: 0.5)
        gradient.endPoint = CGPoint(x: reversed ? 0 : 1, y: 0.5)
        CATransaction.commit()
    }
}
