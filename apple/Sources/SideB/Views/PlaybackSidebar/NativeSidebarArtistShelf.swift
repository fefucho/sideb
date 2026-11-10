import AppKit
import SideBCore

/// Recyclable native artist shelf used by the playback sidebar renderer.
@MainActor
final class NativeSidebarArtistShelfCell: NSTableCellView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("NativeSidebarArtistShelfCell")
    static let height: CGFloat = 140

    private let scrollView = SidebarArtistShelfScrollView()
    private let collectionView = ArtistShelfCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()
    private var cards: [BrowseCardRecord] = []
    private var onActivate: ((BrowseCardRecord) -> Void)?
    private var onMenu: ((BrowseCardRecord) -> NSMenu?)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        flowLayout.scrollDirection = .horizontal
        flowLayout.itemSize = NSSize(width: 92, height: Self.height)
        flowLayout.minimumLineSpacing = 12
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        collectionView.collectionViewLayout = flowLayout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(NativeSidebarArtistShelfItem.self, forItemWithIdentifier: NativeSidebarArtistShelfItem.reuseIdentifier)
        collectionView.onActivateSelection = { [weak self] indexPath in self?.activate(indexPath) }

        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScroller = nil
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        addSubview(scrollView)

        collectionView.setAccessibilityLabel(L10n.text("fullscreen.fansAlsoLike"))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        let contentWidth = CGFloat(cards.count) * 104 + 20
        collectionView.frame = NSRect(x: 0, y: 0, width: max(scrollView.contentView.bounds.width, contentWidth), height: Self.height)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onActivate = nil
        onMenu = nil
        for indexPath in collectionView.indexPathsForVisibleItems() {
            (collectionView.item(at: indexPath) as? NativeSidebarArtistShelfItem)?.prepareForReuse()
        }
        cards = []
        collectionView.reloadData()
    }

    func configure(
        cards: [BrowseCardRecord],
        onActivate: @escaping (BrowseCardRecord) -> Void,
        onMenu: @escaping (BrowseCardRecord) -> NSMenu?
    ) {
        self.onActivate = onActivate
        self.onMenu = onMenu
        guard self.cards != cards else {
            refreshVisibleItems()
            return
        }
        self.cards = cards
        collectionView.reloadData()
        needsLayout = true
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        cards.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NativeSidebarArtistShelfItem.reuseIdentifier, for: indexPath) as! NativeSidebarArtistShelfItem
        configure(item, at: indexPath)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first,
              NSApp.currentEvent?.type == .leftMouseDown || NSApp.currentEvent?.type == .leftMouseUp else { return }
        activate(indexPath)
    }

    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        item.prepareForReuse()
    }

    private func activate(_ indexPath: IndexPath) {
        guard cards.indices.contains(indexPath.item) else { return }
        onActivate?(cards[indexPath.item])
    }

    private func configure(_ item: NativeSidebarArtistShelfItem, at indexPath: IndexPath) {
        guard cards.indices.contains(indexPath.item) else { item.prepareForReuse(); return }
        let card = cards[indexPath.item]
        item.configure(card: card, menu: { [weak self] in self?.onMenu?(card) },
                       activate: { [weak self] in self?.onActivate?(card) })
    }

    private func refreshVisibleItems() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? NativeSidebarArtistShelfItem else { continue }
            configure(item, at: indexPath)
        }
    }
}

@MainActor
private final class NativeSidebarArtistShelfItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("NativeSidebarArtistShelfItem")

    private let artwork = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private var imageTask: Task<Void, Never>?
    private var requestIdentity: UUID?

    override func loadView() {
        let root = SidebarArtistCardView(frame: NSRect(x: 0, y: 0, width: 92, height: NativeSidebarArtistShelfCell.height))
        root.setAccessibilityElement(true)
        root.setAccessibilityRole(.button)
        root.addSubview(artwork)
        root.addSubview(titleLabel)

        artwork.translatesAutoresizingMaskIntoConstraints = false
        artwork.imageScaling = .scaleProportionallyUpOrDown
        artwork.wantsLayer = true
        artwork.layer?.cornerRadius = 36
        artwork.layer?.masksToBounds = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: root.topAnchor, constant: 4),
            artwork.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            artwork.widthAnchor.constraint(equalToConstant: 72),
            artwork.heightAnchor.constraint(equalToConstant: 72),
            titleLabel.topAnchor.constraint(equalTo: artwork.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            titleLabel.heightAnchor.constraint(lessThanOrEqualToConstant: 36)
        ])
        view = root
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        requestIdentity = nil
        artwork.image = nil
        titleLabel.stringValue = ""
        (view as? SidebarArtistCardView)?.makeMenu = nil
        (view as? SidebarArtistCardView)?.activate = nil
        view.setAccessibilityLabel(nil)
    }

    func configure(card: BrowseCardRecord, menu: @escaping () -> NSMenu?, activate: @escaping () -> Void) {
        prepareForReuse()
        titleLabel.stringValue = card.title
        view.setAccessibilityLabel(card.title)
        (view as? SidebarArtistCardView)?.makeMenu = menu
        (view as? SidebarArtistCardView)?.activate = activate

        guard let thumbnail = card.thumbnail,
              let url = ImageURLHelper.optimizedThumbnailURL(from: thumbnail, targetPixelSize: 144) else { return }
        let targetSize = CGSize(width: 72, height: 72)
        if let cached = ImageCache.shared.imageFromMemoryCache(for: url, targetSize: targetSize) {
            artwork.image = cached
            return
        }

        let identity = UUID()
        requestIdentity = identity
        imageTask = Task { @MainActor [weak self] in
            let image = await ImageCache.shared.image(for: url, targetSize: targetSize)
            guard !Task.isCancelled, let self, self.requestIdentity == identity else { return }
            self.artwork.image = image
            self.imageTask = nil
        }
    }
}

@MainActor
final class SidebarArtistShelfScrollView: NSScrollView {
    private var lockedVerticalGesture: Bool?

    override func scrollWheel(with event: NSEvent) {
        let hasDelta = event.scrollingDeltaY != 0 || event.scrollingDeltaX != 0
        if event.phase == .began || (event.phase.isEmpty && event.momentumPhase.isEmpty && hasDelta) || lockedVerticalGesture == nil {
            lockedVerticalGesture = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
        }
        let routeVertically = lockedVerticalGesture == true
        if event.momentumPhase == .ended || event.momentumPhase == .cancelled ||
            (!event.hasPreciseScrollingDeltas && (event.phase == .ended || event.phase == .cancelled || event.phase.isEmpty)) {
            lockedVerticalGesture = nil
        }
        if routeVertically {
            if let outer = enclosingVerticalScrollView() { outer.scrollWheel(with: event) }
            else { nextResponder?.scrollWheel(with: event) }
            return
        }
        super.scrollWheel(with: event)
    }

    func enclosingVerticalScrollView() -> NSScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? NSScrollView, scroll !== self { return scroll }
            ancestor = view.superview
        }
        return nil
    }
}

@MainActor
private final class ArtistShelfCollectionView: NSCollectionView {
    var onActivateSelection: ((IndexPath) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 {
            if let selected = selectionIndexPaths.first { onActivateSelection?(selected) }
            return
        }
        super.keyDown(with: event)
    }
}

private final class SidebarArtistCardView: NSView {
    var makeMenu: (() -> NSMenu?)?
    var activate: (() -> Void)?
    override func menu(for event: NSEvent) -> NSMenu? { makeMenu?() }
    override func accessibilityPerformPress() -> Bool { activate?(); return activate != nil }
}
