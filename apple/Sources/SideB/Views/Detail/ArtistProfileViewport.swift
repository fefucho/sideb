import AppKit
import SwiftUI
import SideBCore

/// Observation of playback/hover belongs to each mounted host, not the feed.
struct ArtistProfileHostedContent: View {
    let content: () -> AnyView
    var body: some View { content() }
}

public typealias ArtistDetail = ArtistDetailRecord
public typealias BrowseSection = ArtistCarouselRecord

extension ArtistDetailRecord {
    public var id: String { channelId }
}

/// One vertical viewport; only mounted shelves create horizontal card hosts.
struct ArtistProfileViewport: NSViewRepresentable {
    let artist: ArtistDetailRecord
    var isObscured = false
    let header: AnyView
    let makeCard: (BrowseCardRecord) -> AnyView
    let onMore: (ArtistCarouselRecord) -> Void
    let localizationRevision = L10n.revision

    static let albumsBrowseParams = "ggMIegYIARoCAQI%3D"
    static let singlesBrowseParams = "ggMIegYIAhoCAQI%3D"

    static func resolvedSection(_ section: ArtistCarouselRecord, artistId: String) -> ArtistCarouselRecord {
        guard section.moreBrowseId == nil || section.moreBrowseId?.isEmpty == true else { return section }
        let trimmedId = artistId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedId.hasPrefix("UC"), !section.items.isEmpty else { return section }
        guard section.items.allSatisfy({ $0.kind.lowercased() == "album" }) else { return section }
        let normalized = section.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let params: String?
        if ["albums", "álbumes", "albumes", "אלבומים"].contains(normalized) {
            params = albumsBrowseParams
        } else if normalized.contains("single") || normalized.contains("sencillo") || normalized == "ep" || normalized == "eps" {
            params = singlesBrowseParams
        } else {
            params = nil
        }
        guard let resolvedParams = params else { return section }
        return ArtistCarouselRecord(
            title: section.title,
            items: section.items,
            moreBrowseId: "MPAD\(trimmedId)",
            moreParams: resolvedParams
        )
    }

    static func resolvedSections(for detail: ArtistDetailRecord) -> [ArtistCarouselRecord] {
        detail.sections.map { resolvedSection($0, artistId: detail.channelId) }
    }

    static func resolvedArtist(_ detail: ArtistDetailRecord) -> ArtistDetailRecord {
        ArtistDetailRecord(
            channelId: detail.channelId,
            name: detail.name,
            thumbnail: detail.thumbnail,
            description: detail.description,
            subscribers: detail.subscribers,
            monthlyListeners: detail.monthlyListeners,
            subscribed: detail.subscribed,
            radioPlaylistId: detail.radioPlaylistId,
            topSongs: detail.topSongs,
            topSongsId: detail.topSongsId,
            sections: resolvedSections(for: detail)
        )
    }

    static func featuredAlbumsSection(from detail: ArtistDetailRecord) -> ArtistCarouselRecord? {
        resolvedSections(for: detail).first { section in
            let normalized = section.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["albums", "álbumes", "albumes", "אלבומים"].contains(normalized)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 800, height: proposal.height ?? 600)
    }
    func makeNSView(context: Context) -> NSScrollView { makeScrollView(coordinator: context.coordinator) }
    func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scroll = HomeFeedScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .allowed
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        let table = NSTableView()
        table.backgroundColor = .clear
        table.style = .plain
        table.headerView = nil
        table.selectionHighlightStyle = .none
        table.intercellSpacing = .zero
        table.usesAutomaticRowHeights = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.autoresizingMask = [.width]
        let column = NSTableColumn(identifier: .init("artist-profile"))
        column.minWidth = 0
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = coordinator
        table.delegate = coordinator
        table.setAccessibilityLabel(artist.name)
        scroll.documentView = table
        coordinator.table = table
        scroll.onViewportLayout = { [weak coordinator] in coordinator?.updateWidth() }
        table.reloadData()
        scroll.isHidden = isObscured
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { update(scroll, coordinator: context.coordinator) }
    func update(_ scroll: NSScrollView, coordinator: Coordinator) {
        let old = coordinator.parent
        coordinator.parent = self
        scroll.isHidden = isObscured
        scroll.setAccessibilityHidden(isObscured)
        let reset = old.artist.channelId != artist.channelId
        let changed = old.artist != artist || old.localizationRevision != localizationRevision
        let newSections = ArtistProfileViewport.resolvedSections(for: artist).filter { !$0.items.isEmpty }
        if reset || coordinator.sections.map({ [$0.title, $0.moreBrowseId ?? "", $0.moreParams ?? ""] }) !=
            newSections.map({ [$0.title, $0.moreBrowseId ?? "", $0.moreParams ?? ""] }) {
            coordinator.offsets.removeAll()
        }
        if changed {
            coordinator.sections = newSections
            coordinator.table?.setAccessibilityLabel(artist.name)
            coordinator.table?.reloadData()
        } else if old.isObscured != isObscured {
            if isObscured { coordinator.suspendVisibleShelves() }
            else { coordinator.refreshVisibleShelves() }
        }
        coordinator.updateWidth()
        if reset { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll as? HomeFeedScrollView)?.onViewportLayout = nil
        coordinator.suspendVisibleShelves()
        coordinator.table?.dataSource = nil
        coordinator.table?.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: ArtistProfileViewport
        var sections: [ArtistCarouselRecord] {
            didSet { sectionHeights = sections.map(ArtistProfileShelf.height) }
        }
        private var sectionHeights: [CGFloat]
        weak var table: NSTableView?
        var offsets: [Int: CGFloat] = [:]
        private var headerHeight: CGFloat = 400
        private var lastWidth: CGFloat = -1
        private(set) var configuredShelves = 0
        init(parent: ArtistProfileViewport) {
            self.parent = parent
            sections = ArtistProfileViewport.resolvedSections(for: parent.artist).filter { !$0.items.isEmpty }
            sectionHeights = sections.map(ArtistProfileShelf.height)
        }
        func numberOfRows(in tableView: NSTableView) -> Int { sections.count + 2 }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            if row == 0 { return headerHeight }
            guard row <= sections.count else { return 120 }
            return sectionHeights[row - 1]
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            if row == 0 {
                let identifier = NSUserInterfaceItemIdentifier("artist-header")
                let header = (tableView.makeView(withIdentifier: identifier, owner: nil) as? LibraryCollectionHeaderView)
                    ?? LibraryCollectionHeaderView()
                header.identifier = identifier
                header.configure(content: parent.header) { [weak self] height in
                    guard let self, height.isFinite, height > 0, abs(self.headerHeight - height) > 0.5 else { return }
                    self.headerHeight = height
                    self.table?.noteHeightOfRows(withIndexesChanged: IndexSet(integer: 0))
                }
                return header
            }
            guard row <= sections.count else { return NSView() }
            let shelf = (tableView.makeView(withIdentifier: ArtistProfileShelf.identifier, owner: nil) as? ArtistProfileShelf)
                ?? ArtistProfileShelf()
            configure(shelf, row: row)
            return shelf
        }
        private func configure(_ shelf: ArtistProfileShelf, row: Int) {
            let index = row - 1
            guard sections.indices.contains(index) else { return }
            configuredShelves += 1
            shelf.configure(section: sections[index], offset: offsets[index] ?? 0,
                active: !parent.isObscured, makeCard: parent.makeCard,
                onMore: { [weak self] in
                    guard let self, !self.parent.isObscured, self.sections.indices.contains(index) else { return }
                    self.parent.onMore(self.sections[index])
                }, offsetChanged: { [weak self] in self?.offsets[index] = $0 })
        }
        func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
            for case let shelf as ArtistProfileShelf in rowView.subviews { shelf.suspend() }
        }
        func refreshVisibleShelves() {
            guard let table else { return }
            let visible = table.rows(in: table.visibleRect)
            guard visible.location != NSNotFound else { return }
            let start = max(1, visible.location)
            let end = min(sections.count + 1, NSMaxRange(visible))
            guard start < end else { return }
            for row in start..<end {
                if let shelf = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ArtistProfileShelf {
                    configure(shelf, row: row)
                }
            }
        }
        func suspendVisibleShelves() {
            guard let table else { return }
            for row in 1..<(sections.count + 1) {
                (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ArtistProfileShelf)?.suspend()
            }
        }
        func updateWidth() {
            guard let table, let scroll = table.enclosingScrollView else { return }
            let width = scroll.contentView.bounds.width
            guard width > 0, abs(width - lastWidth) > 0.5 else { return }
            lastWidth = width
            table.tableColumns.first?.width = width
        }
    }
}

private final class ArtistProfileHorizontalScroll: NSScrollView, HorizontalNavigationGestureOwner {
    var ownsHorizontalNavigationGesture: Bool { true }
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? NSScrollView { scroll.scrollWheel(with: event); return }
                ancestor = view.superview
            }
        }
        super.scrollWheel(with: event)
    }
}

@MainActor final class ArtistProfileShelf: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("artist-shelf")
    let collection = NSCollectionView()
    private let scroll = ArtistProfileHorizontalScroll()
    private let flow = NSCollectionViewFlowLayout()
    private let title = NSTextField(labelWithString: "")
    private let more = NSButton()
    private var section: ArtistCarouselRecord?
    private var makeCard: ((BrowseCardRecord) -> AnyView)?
    private var onMore: (() -> Void)?
    private var offsetChanged: ((CGFloat) -> Void)?
    private var pendingOffset: CGFloat?
    private var active = false
    private(set) var configuredCards = 0
    override var isFlipped: Bool { true }
    static func cardSize(_ card: BrowseCardRecord) -> NSSize {
        card.kind.lowercased() == "video" ? NSSize(width: 200, height: 156) : NSSize(width: 144, height: 188)
    }
    static func height(for section: ArtistCarouselRecord) -> CGFloat {
        let cardHeight: CGFloat = section.items.allSatisfy { $0.kind.lowercased() == "video" } ? 156 : 188
        return cardHeight + 24 + 14 + 32
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.lineBreakMode = .byTruncatingTail
        addSubview(title)
        more.isBordered = false
        more.font = .systemFont(ofSize: 13, weight: .semibold)
        more.target = self
        more.action = #selector(showMore)
        addSubview(more)
        flow.scrollDirection = .horizontal
        flow.minimumLineSpacing = 16
        flow.minimumInteritemSpacing = 0
        flow.sectionInset = NSEdgeInsets(top: 0, left: 32, bottom: 0, right: 32)
        collection.collectionViewLayout = flow
        collection.backgroundColors = [.clear]
        collection.isSelectable = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(ArtistProfileCardItem.self, forItemWithIdentifier: ArtistProfileCardItem.identifier)
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
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func layout() {
        super.layout()
        more.sizeToFit()
        more.frame = NSRect(x: max(32, bounds.width - 32 - more.frame.width), y: 0, width: more.frame.width, height: 24)
        title.frame = NSRect(x: 32, y: 0, width: max(0, bounds.width - 64 - (more.isHidden ? 0 : more.frame.width + 16)), height: 24)
        scroll.frame = NSRect(x: 0, y: 38, width: bounds.width, height: max(0, bounds.height - 70))
        if let offset = pendingOffset {
            collection.layoutSubtreeIfNeeded()
            let maximum = max(0, flow.collectionViewContentSize.width - scroll.contentView.bounds.width)
            scroll.contentView.scroll(to: NSPoint(x: min(maximum, max(0, offset)), y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            pendingOffset = nil
        }
    }
    func configure(section: ArtistCarouselRecord, offset: CGFloat, active: Bool,
                   makeCard: @escaping (BrowseCardRecord) -> AnyView, onMore: @escaping () -> Void,
                   offsetChanged: @escaping (CGFloat) -> Void) {
        self.section = section
        self.active = active
        self.makeCard = makeCard
        self.onMore = onMore
        self.offsetChanged = offsetChanged
        title.stringValue = section.title
        more.title = L10n.text("detail.viewAll")
        more.setAccessibilityLabel(L10n.text("detail.viewAllSection", args: [section.title]))
        more.isHidden = section.moreBrowseId?.isEmpty != false
        collection.setAccessibilityLabel(section.title)
        pendingOffset = offset
        collection.reloadData()
        needsLayout = true
    }
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        active ? self.section?.items.count ?? 0 : 0
    }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ArtistProfileCardItem.identifier, for: indexPath) as! ArtistProfileCardItem
        configure(item, at: indexPath)
        return item
    }
    private func configure(_ item: ArtistProfileCardItem, at path: IndexPath) {
        guard active, let section, section.items.indices.contains(path.item), let makeCard else { return }
        configuredCards += 1
        let card = section.items[path.item]
        item.configure { makeCard(card) }
    }
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        guard let item = item as? ArtistProfileCardItem, !item.hasContent else { return }
        configure(item, at: indexPath)
    }
    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        (item as? ArtistProfileCardItem)?.suspend()
    }
    func suspend() {
        for case let item as ArtistProfileCardItem in collection.visibleItems() { item.suspend() }
        active = false
        makeCard = nil
        onMore = nil
        offsetChanged = nil
        collection.reloadData()
    }
    @objc private func showMore() { if active { onMore?() } }
    @objc private func scrolled() {
        if pendingOffset == nil { offsetChanged?(scroll.contentView.bounds.minX) }
    }
}

extension ArtistProfileShelf: NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> NSSize {
        guard let section, section.items.indices.contains(indexPath.item) else { return NSSize(width: 144, height: 188) }
        return Self.cardSize(section.items[indexPath.item])
    }
}

@MainActor final class ArtistProfileCardItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("artist-card")
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private(set) var hasContent = false
    override func loadView() { host.sizingOptions = []; view = host }
    func configure(content: @escaping () -> AnyView) {
        hasContent = true
        host.rootView = AnyView(ArtistProfileHostedContent(content: content).preferredColorScheme(.dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
    }
    func suspend() { hasContent = false; host.rootView = AnyView(EmptyView()) }
    override func prepareForReuse() { super.prepareForReuse(); suspend() }
}
