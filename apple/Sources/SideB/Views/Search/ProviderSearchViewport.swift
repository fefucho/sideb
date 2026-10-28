import AppKit
import SwiftUI

/// One occurrence in the flattened provider-search presentation. Heights are
/// supplied by the projection because principal blocks can change with width.
struct ProviderSearchViewportEntry: Identifiable, Hashable {
    enum Kind: Hashable { case row, heading, principal, carousel, action, footer }

    let id: AnyHashable
    let kind: Kind
    let height: CGFloat?
    let measurementRevision: AnyHashable

    init<ID: Hashable>(id: ID, kind: Kind, height: CGFloat? = nil,
                       measurementRevision: AnyHashable = AnyHashable(0)) {
        self.id = AnyHashable(id)
        self.kind = kind
        self.height = height.map { max(1, $0) }
        self.measurementRevision = measurementRevision
    }
}

/// A single native scroll viewport with variable-height, recycled SwiftUI rows.
/// The optional header is one persistent host in the same scrolling document.
struct ProviderSearchViewport: NSViewRepresentable {
    let entries: [ProviderSearchViewportEntry]
    let resetIdentity: AnyHashable
    let snapshotRevision: AnyHashable
    var renderRevision: AnyHashable = 0
    var scrollingHeader: AnyView? = nil
    let rowContent: (ProviderSearchViewportEntry, CGFloat) -> AnyView
    var onActivate: ((ProviderSearchViewportEntry) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeScrollView() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 800, height: proposal.height ?? 600)
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(parent: self)
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.dismantle()
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private(set) var parent: ProviderSearchViewport
        weak var scroll: NSScrollView?
        weak var table: NSTableView?
        private weak var document: ProviderSearchDocumentView?
        private var headerView: LibraryCollectionHeaderView?
        private var headerHeight: CGFloat = 0
        private var viewportWidth: CGFloat = 0
        private var rowKeys: [ProviderSearchRowKey] = []
        private var measuredHeights: [ProviderSearchHeightKey: CGFloat] = [:]
        private var rowsHeight: CGFloat = 0
        private var updatingGeometry = false

        var tableForTesting: NSTableView? { table }
        var rowKeysForTesting: [AnyHashable] { rowKeys.map { AnyHashable($0) } }
        var headerForTesting: NSView? { headerView }
        var documentForTesting: NSView? { document }
        func updateGeometryForTesting() { updateGeometry() }

        init(parent: ProviderSearchViewport) {
            self.parent = parent
            super.init()
            rebuildKeys()
        }

        func makeScrollView() -> NSScrollView {
            let scroll = HomeFeedScrollView()
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.horizontalScrollElasticity = .none
            scroll.verticalScrollElasticity = .allowed
            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 120, right: 0)

            let table = ProviderSearchTableView()
            table.headerView = nil
            table.style = .plain
            table.rowHeight = 58
            table.intercellSpacing = .zero
            table.usesAutomaticRowHeights = false
            table.selectionHighlightStyle = .none
            table.allowsEmptySelection = true
            table.allowsColumnSelection = false
            table.focusRingType = .none
            table.backgroundColor = .clear
            table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
            table.delegate = self
            table.dataSource = self
            table.onActivate = { [weak self] row in
                guard let self, self.parent.entries.indices.contains(row) else { return }
                self.parent.onActivate?(self.parent.entries[row])
            }
            table.addTableColumn(NSTableColumn(identifier: Self.columnID))

            let document = ProviderSearchDocumentView()
            document.table = table
            document.addSubview(table)
            scroll.documentView = document
            self.scroll = scroll
            self.table = table
            self.document = document
            scroll.onViewportLayout = { [weak self] in self?.updateGeometry() }
            table.reloadData()
            updateHeader()
            updateGeometry()
            return scroll
        }

        private static let columnID = NSUserInterfaceItemIdentifier("ProviderSearchColumn")

        func update(parent: ProviderSearchViewport) {
            let old = self.parent
            self.parent = parent
            guard let table else { return }
            let identityChanged = old.resetIdentity != parent.resetIdentity
            let expectedWidth = max(1, (scroll?.contentView.bounds.width ?? 0) - 56)
            let widthChanged = abs(expectedWidth - viewportWidth) > 0.5
            let entriesChanged = old.entries != parent.entries
            let snapshotChanged = old.snapshotRevision != parent.snapshotRevision
            if identityChanged { measuredHeights.removeAll(keepingCapacity: true) }
            if entriesChanged || snapshotChanged || identityChanged {
                let offset = scroll?.contentView.bounds.minY ?? 0
                if entriesChanged { rebuildKeys() }
                if entriesChanged || identityChanged { pruneMeasuredHeights() }
                table.reloadData()
                recomputeRowsHeight(width: viewportWidth)
                updateGeometry(refreshRows: false)
                refreshVisibleRows()
                if let clip = scroll?.contentView {
                    clip.scroll(to: NSPoint(x: 0, y: offset))
                    scroll?.reflectScrolledClipView(clip)
                }
            } else if old.renderRevision != parent.renderRevision {
                refreshVisibleRows()
            }
            if old.scrollingHeader != nil || parent.scrollingHeader != nil { updateHeader() }
            if identityChanged {
                scroll?.contentView.scroll(to: .zero)
                scroll?.reflectScrolledClipView(scroll!.contentView)
            }
            if widthChanged || entriesChanged || snapshotChanged || ((old.scrollingHeader == nil) != (parent.scrollingHeader == nil)) {
                updateGeometry()
            }
        }

        private func rebuildKeys() {
            var counts: [AnyHashable: Int] = [:]
            rowKeys = parent.entries.map { entry in
                let occurrence = counts[entry.id, default: 0]
                counts[entry.id] = occurrence + 1
                return ProviderSearchRowKey(id: entry.id, occurrence: occurrence)
            }
            recomputeRowsHeight(width: viewportWidth)
        }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.entries.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard parent.entries.indices.contains(row) else { return 1 }
            return resolvedHeight(row: row, width: viewportWidth)
        }

        private func resolvedHeight(row: Int, width: CGFloat) -> CGFloat {
            guard parent.entries.indices.contains(row) else { return 1 }
            let entry = parent.entries[row]
            if let height = entry.height { return height }
            let key = ProviderSearchHeightKey(id: rowKeys[row], width: Int(width.rounded()),
                                              measurementRevision: entry.measurementRevision)
            if let cached = measuredHeights[key] { return cached }
            switch entry.kind {
            case .row: return 58
            case .heading: return 44
            case .principal: return 260
            case .carousel: return 240
            case .action, .footer: return 48
            }
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.entries.indices.contains(row) else { return nil }
            let view = (tableView.makeView(withIdentifier: ProviderSearchRowView.identifier, owner: self) as? ProviderSearchRowView)
                ?? ProviderSearchRowView()
            configure(view, row: row)
            return view
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { parent.entries.indices.contains(row) }

        private func configure(_ view: ProviderSearchRowView, row: Int) {
            guard parent.entries.indices.contains(row) else { view.prepareForReuse(); return }
            let entry = parent.entries[row]
            let key = rowKeys[row]
            let requestIdentity = parent.resetIdentity
            let measurementRevision = entry.measurementRevision
            let width = viewportWidth
            view.configure(key: key, width: max(1, width), content: parent.rowContent(entry, width)) { [weak self] measured in
                Task { @MainActor [weak self] in
                    guard let self, self.parent.resetIdentity == requestIdentity,
                          self.parent.entries.indices.contains(row),
                          self.parent.entries[row].measurementRevision == measurementRevision,
                          abs(self.viewportWidth - width) < 0.5 else { return }
                    self.acceptMeasuredHeight(measured, for: key, row: row)
                }
            }
        }

        private func acceptMeasuredHeight(_ height: CGFloat, for id: ProviderSearchRowKey, row: Int) {
            guard parent.entries.indices.contains(row), rowKeys[row] == id,
                  parent.entries[row].height == nil, height.isFinite, height > 1 else { return }
            let key = ProviderSearchHeightKey(id: id, width: Int(viewportWidth.rounded()),
                                              measurementRevision: parent.entries[row].measurementRevision)
            let previousHeight = measuredHeights[key] ?? resolvedHeight(row: row, width: viewportWidth)
            guard abs(previousHeight - height) > 1 else { return }
            let rowRect = table?.rect(ofRow: row) ?? .zero
            let isEntirelyAboveViewport = rowRect.maxY <= (table?.visibleRect.minY ?? 0)
            measuredHeights[key] = ceil(height)
            guard let table, row < table.numberOfRows else { return }
            let offset = scroll?.contentView.bounds.minY ?? 0
            rowsHeight += ceil(height) - previousHeight
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
            updateGeometry(refreshRows: false)
            if let clip = scroll?.contentView {
                let adjustedOffset = isEntirelyAboveViewport ? offset + ceil(height) - previousHeight : offset
                clip.scroll(to: NSPoint(x: 0, y: adjustedOffset))
                scroll?.reflectScrolledClipView(clip)
            }
        }

        private func refreshVisibleRows() {
            guard let table else { return }
            table.needsLayout = true
            table.layoutSubtreeIfNeeded()
            let range = table.rows(in: table.visibleRect)
            guard range.location != NSNotFound else { return }
            for row in range.location..<NSMaxRange(range) {
                guard let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ProviderSearchRowView else { continue }
                view.needsLayout = true
                view.layoutSubtreeIfNeeded()
                configure(view, row: row)
            }
        }

        private func updateHeader() {
            guard let document else { return }
            guard let content = parent.scrollingHeader else {
                headerView?.removeFromSuperview()
                headerView = nil
                headerHeight = 0
                return
            }
            let header = headerView ?? LibraryCollectionHeaderView()
            if headerView == nil {
                headerView = header
                document.addSubview(header)
            }
            header.configure(content: content) { [weak self] height in
                guard let self, abs(self.headerHeight - height) > 0.5 else { return }
                self.headerHeight = ceil(height)
                self.updateGeometry()
            }
        }

        private func recomputeRowsHeight(width: CGFloat) {
            rowsHeight = parent.entries.indices.reduce(CGFloat.zero) { $0 + resolvedHeight(row: $1, width: width) }
        }

        private func pruneMeasuredHeights() {
            let current = Set(parent.entries.indices.map { index in
                ProviderSearchMeasurementIdentity(id: rowKeys[index], revision: parent.entries[index].measurementRevision)
            })
            measuredHeights = measuredHeights.filter { current.contains(ProviderSearchMeasurementIdentity(id: $0.key.id, revision: $0.key.measurementRevision)) }
        }

        private func updateGeometry(refreshRows: Bool = true) {
            guard !updatingGeometry, let scroll, let table, let document else { return }
            let fullWidth = scroll.contentView.bounds.width
            guard fullWidth > 1 else { return }
            updatingGeometry = true
            defer { updatingGeometry = false }
            let width = max(1, fullWidth - 56)
            let widthChanged = abs(width - viewportWidth) > 0.5
            if widthChanged {
                viewportWidth = width
                measuredHeights = measuredHeights.filter { $0.key.width == Int(width.rounded()) }
                recomputeRowsHeight(width: width)
            }
            let left = (fullWidth - width) / 2
            let totalHeight = max(scroll.contentView.bounds.height, headerHeight + rowsHeight)
            document.frame = NSRect(x: 0, y: 0, width: fullWidth, height: totalHeight)
            table.frame = NSRect(x: left, y: headerHeight, width: width, height: max(1, totalHeight - headerHeight))
            table.tableColumns.first?.width = width
            headerView?.frame = NSRect(x: left, y: 0, width: width, height: headerHeight)
            if widthChanged {
                let visible = table.rows(in: table.visibleRect)
                if visible.location != NSNotFound {
                    table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: visible.location..<NSMaxRange(visible)))
                }
            }
            if refreshRows && widthChanged { refreshVisibleRows() }
        }

        func dismantle() {
            (scroll as? HomeFeedScrollView)?.onViewportLayout = nil
            table?.delegate = nil
            table?.dataSource = nil
            if let table {
                let range = table.rows(in: table.visibleRect)
                if range.location != NSNotFound {
                    for row in range.location..<NSMaxRange(range) {
                        (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ProviderSearchRowView)?.prepareForReuse()
                    }
                }
                (table as? ProviderSearchTableView)?.onActivate = nil
            }
            headerView?.removeFromSuperview()
            headerView = nil
            table = nil
            document = nil
            scroll = nil
        }
    }
}

private struct ProviderSearchRowKey: Hashable {
    let id: AnyHashable
    let occurrence: Int
}

private struct ProviderSearchHeightKey: Hashable {
    let id: ProviderSearchRowKey
    let width: Int
    let measurementRevision: AnyHashable
}

private struct ProviderSearchMeasurementIdentity: Hashable {
    let id: ProviderSearchRowKey
    let revision: AnyHashable
}

@MainActor private final class ProviderSearchDocumentView: NSView {
    weak var table: NSTableView?
    override var isFlipped: Bool { true }
}

@MainActor private final class ProviderSearchTableView: NSTableView {
    var onActivate: ((Int) -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            if selectedRow >= 0 { onActivate?(selectedRow) }
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor private final class ProviderSearchRowView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("ProviderSearchRow")
    private let host = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))
    private var key: ProviderSearchRowKey?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        host.sizingOptions = [.intrinsicContentSize]
        host.safeAreaRegions = []
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    override func layout() { super.layout(); host.frame = bounds }

    func configure(key: ProviderSearchRowKey, width: CGFloat, content: AnyView, onMeasured: @escaping (CGFloat) -> Void) {
        self.key = key
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            host.rootView = AnyView(content
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: .topLeading)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: ProviderSearchRowHeightPreference.self, value: geometry.size.height)
                })
                .onPreferenceChange(ProviderSearchRowHeightPreference.self) { height in
                    onMeasured(height)
                })
        }
        host.invalidateIntrinsicContentSize()
        host.needsLayout = true
        host.frame = bounds
        host.layoutSubtreeIfNeeded()
        host.needsDisplay = true
        host.setNeedsDisplay(host.bounds)
        let idealHeight = host.fittingSize.height
        if idealHeight.isFinite, idealHeight > 1 { onMeasured(idealHeight) }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        key = nil
        host.rootView = AnyView(EmptyView())
    }
}

private struct ProviderSearchRowHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
