import AppKit
import SwiftUI
import SideBCore

// MARK: - Native Track Table View (AppKit Bridge)

/// Representa una sección dentro de `NativeTrackTableView`, con un título opcional para encabezados nativos.
public struct TrackTableSection: Sendable, Equatable {
    public let id: String
    public let title: String?
    public let tracks: [SongItemRecord]

    public init(id: String = UUID().uuidString, title: String? = nil, tracks: [SongItemRecord]) {
        self.id = id
        self.title = title
        self.tracks = tracks
    }
}

enum TableRowItem: Equatable {
    case header(title: String, sectionIndex: Int)
    case track(track: SongItemRecord, overallIndex: Int, sectionIndex: Int, itemIndex: Int)
    case footer
    case scrollingHeader
    case columnLabels
}

/// Proyección pura de secciones a filas planas; `overallIndex` identifica la ocurrencia,
/// incluso si dos filas contienen el mismo `videoId`.
struct TrackTableRowProjection {
    let tracks: [SongItemRecord]
    let rows: [TableRowItem]

    static func make(sections: [TrackTableSection], hasFooter: Bool = false,
                     hasScrollingHeader: Bool = false, hasColumnLabels: Bool = false) -> Self {
        var tracks: [SongItemRecord] = []
        var rows: [TableRowItem] = []
        if hasScrollingHeader { rows.append(.scrollingHeader) }
        if hasColumnLabels { rows.append(.columnLabels) }
        for (sectionIndex, section) in sections.enumerated() {
            if let title = section.title, !title.isEmpty {
                rows.append(.header(title: title, sectionIndex: sectionIndex))
            }
            for (itemIndex, track) in section.tracks.enumerated() {
                let overallIndex = tracks.count
                tracks.append(track)
                rows.append(.track(track: track, overallIndex: overallIndex,
                                   sectionIndex: sectionIndex, itemIndex: itemIndex))
            }
        }
        if hasFooter { rows.append(.footer) }
        return Self(tracks: tracks, rows: rows)
    }
}

enum TrackTableInteractionPolicy {
    enum Source { case row, thumbnailPlay, artistLink, albumLink, menu }

    static func isSingleClick(clickCount: Int?) -> Bool {
        guard let clickCount else { return true }
        return clickCount <= 1
    }

    static func playbackIndex(for row: TableRowItem, source: Source, isSelectionGesture: Bool = false) -> Int? {
        guard !isSelectionGesture else { return nil }
        switch source {
        case .row, .thumbnailPlay:
            guard case .track(_, let overallIndex, _, _) = row else { return nil }
            return overallIndex
        case .artistLink, .albumLink, .menu:
            return nil
        }
    }

    /// Translate a visual insertion row (including collection headers) into the source occurrence index.
    static func dropDestination(proposedRow: Int, sourceIndex: Int, rows: [TableRowItem], trackCount: Int) -> Int? {
        guard sourceIndex >= 0, sourceIndex < trackCount else { return nil }
        let start = max(0, min(proposedRow, rows.count))
        let insertionIndex = rows.dropFirst(start).compactMap { item -> Int? in
            if case .track(_, let index, _, _) = item { return index }
            return nil
        }.first ?? trackCount
        let destination = insertionIndex > sourceIndex ? insertionIndex - 1 : insertionIndex
        guard destination >= 0, destination < trackCount, destination != sourceIndex else { return nil }
        return destination
    }

    @discardableResult
    static func dispatchPlayback(
        for row: TableRowItem,
        source: Source,
        isSelectionGesture: Bool = false,
        play: (Int) -> Void
    ) -> Bool {
        guard let index = playbackIndex(for: row, source: source, isSelectionGesture: isSelectionGesture) else {
            return false
        }
        play(index)
        return true
    }
}

/// Componente universal de lista de canciones de ultra-alto rendimiento respaldado por `NSTableView` de AppKit.
/// - Soporte de secciones nativas con encabezados sticky/separadores sin overhead (`isGroupRow`).
/// - Reciclaje estricto de celdas (`makeView(withIdentifier:owner:)`): solo ~15 vistas físicas creadas en memoria RAM.
/// - Carga de imágenes desacoplada directamente en `NSImageView` sin mutar `@State` en SwiftUI ni saturar el hilo principal.
/// - Hover de fuente única de verdad (`hoveredRowIndex`): solo una fila puede estar resaltada a la vez, a 120 FPS.
/// - Reordenamiento de cola, enlaces y menú secundarios separados de la reproducción de fila.
struct NativeTrackTableView: NSViewRepresentable {
    private var localizationRevision = L10n.revision
    @Environment(\.sideBMenuContext) private var menuContext
    @Environment(\.collectionBackgroundController) private var collectionBackgroundController
    let sections: [TrackTableSection]
    let tracks: [SongItemRecord]
    let rowItems: [TableRowItem]
    let currentTrackVideoId: String?
    let currentQueueOccurrenceID: String?
    let currentQueueIndex: Int?
    let currentQueueDuration: String?
    let isPlaying: Bool
    let playerViewModel: PlayerViewModel?
    let router: NavigationRouter?
    let rustCore: SideBCore?
    let presentation: TrackTablePresentation
    let hideAlbumColumn: Bool
    let showAlbumInSubtitle: Bool
    let isReorderable: Bool
    let rowHeight: CGFloat
    let likedVideoIds: Set<String>
    let onPlayTrack: (Int) -> Void
    let onLikeTrack: ((SongItemRecord) -> Void)?
    let onDislikeTrack: ((SongItemRecord) -> Void)?
    let playlistContext: (playlistId: String, isOwned: Bool)?
    let onRemoveTrackFromPlaylist: (@MainActor @Sendable (SongItemRecord) -> Void)?
    let menuOrigin: ((Int) -> MenuOrigin)?
    let onMoveTrack: ((Int, Int) -> Void)?
    let onNearBottom: (() -> Void)?
    let contentInsets: NSEdgeInsets
    let scrollingHeader: AnyView?
    let scrollingHeaderHeight: CGFloat
    let scrollingBackground: ((Bool) -> AnyView)?
    let scrollingBackgroundIdentity: String?
    let footer: AnyView?
    let footerHeight: CGFloat

    /// Inicializador principal que soporta múltiples secciones con encabezados de fecha/categoría.
    init(
        sections: [TrackTableSection],
        currentTrackVideoId: String? = nil,
        isPlaying: Bool = false,
        playerViewModel: PlayerViewModel? = nil,
        router: NavigationRouter? = nil,
        rustCore: SideBCore? = nil,
        presentation: TrackTablePresentation = .standard,
        hideAlbumColumn: Bool = false,
        showAlbumInSubtitle: Bool = false,
        isReorderable: Bool = false,
        rowHeight: CGFloat = 52.0,
        likedVideoIds: Set<String> = [],
        playlistContext: (playlistId: String, isOwned: Bool)? = nil,
        menuOrigin: ((Int) -> MenuOrigin)? = nil,
        onPlayTrack: @escaping (Int) -> Void,
        onLikeTrack: ((SongItemRecord) -> Void)? = nil,
        onDislikeTrack: ((SongItemRecord) -> Void)? = nil,
        onRemoveTrackFromPlaylist: (@MainActor @Sendable (SongItemRecord) -> Void)? = nil,
        onMoveTrack: ((Int, Int) -> Void)? = nil,
        onNearBottom: (() -> Void)? = nil,
        contentInsets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 120, right: 0),
        scrollingHeader: AnyView? = nil,
        scrollingHeaderHeight: CGFloat = 0,
        scrollingBackground: ((Bool) -> AnyView)? = nil,
        scrollingBackgroundIdentity: String? = nil,
        footer: AnyView? = nil,
        footerHeight: CGFloat = 0
    ) {
        self.sections = sections
        let projection = TrackTableRowProjection.make(sections: sections, hasFooter: footer != nil,
                                                     hasScrollingHeader: scrollingHeader != nil,
                                                     hasColumnLabels: presentation == .collectionPlaylist)
        self.tracks = projection.tracks
        self.rowItems = projection.rows
        self.currentTrackVideoId = currentTrackVideoId
        self.currentQueueOccurrenceID = playerViewModel?.queueManager.currentOccurrenceID
        self.currentQueueIndex = playerViewModel?.queueManager.currentIndex
        if presentation == .queue, let playerViewModel,
           currentTrackVideoId == playerViewModel.currentTrack?.videoId,
           playerViewModel.duration.isFinite, playerViewModel.duration > 0 {
            self.currentQueueDuration = playerViewModel.formattedDuration
        } else {
            self.currentQueueDuration = nil
        }
        self.isPlaying = isPlaying
        self.playerViewModel = playerViewModel
        self.router = router
        self.rustCore = rustCore
        self.presentation = presentation
        self.hideAlbumColumn = hideAlbumColumn
        self.showAlbumInSubtitle = showAlbumInSubtitle
        self.isReorderable = isReorderable
        self.rowHeight = rowHeight
        self.likedVideoIds = likedVideoIds
        self.playlistContext = playlistContext
        self.menuOrigin = menuOrigin
        self.onPlayTrack = onPlayTrack
        self.onLikeTrack = onLikeTrack
        self.onDislikeTrack = onDislikeTrack
        self.onRemoveTrackFromPlaylist = onRemoveTrackFromPlaylist
        self.onMoveTrack = onMoveTrack
        self.onNearBottom = onNearBottom
        self.contentInsets = contentInsets
        self.scrollingHeader = scrollingHeader
        self.scrollingHeaderHeight = scrollingHeaderHeight
        self.scrollingBackground = scrollingBackground
        self.scrollingBackgroundIdentity = scrollingBackgroundIdentity
        self.footer = footer
        self.footerHeight = footerHeight
    }

    /// Inicializador de conveniencia para listas planas continuas (Playlists, Álbumes, Búsqueda, Cola).
    init(
        tracks: [SongItemRecord],
        currentTrackVideoId: String? = nil,
        isPlaying: Bool = false,
        playerViewModel: PlayerViewModel? = nil,
        router: NavigationRouter? = nil,
        rustCore: SideBCore? = nil,
        presentation: TrackTablePresentation = .standard,
        hideAlbumColumn: Bool = false,
        showAlbumInSubtitle: Bool = false,
        isReorderable: Bool = false,
        rowHeight: CGFloat = 52.0,
        likedVideoIds: Set<String> = [],
        playlistContext: (playlistId: String, isOwned: Bool)? = nil,
        menuOrigin: ((Int) -> MenuOrigin)? = nil,
        onPlayTrack: @escaping (Int) -> Void,
        onLikeTrack: ((SongItemRecord) -> Void)? = nil,
        onDislikeTrack: ((SongItemRecord) -> Void)? = nil,
        onRemoveTrackFromPlaylist: (@MainActor @Sendable (SongItemRecord) -> Void)? = nil,
        onMoveTrack: ((Int, Int) -> Void)? = nil,
        onNearBottom: (() -> Void)? = nil,
        contentInsets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 120, right: 0),
        scrollingHeader: AnyView? = nil,
        scrollingHeaderHeight: CGFloat = 0,
        scrollingBackground: ((Bool) -> AnyView)? = nil,
        scrollingBackgroundIdentity: String? = nil,
        footer: AnyView? = nil,
        footerHeight: CGFloat = 0
    ) {
        self.init(
            sections: [TrackTableSection(title: nil, tracks: tracks)],
            currentTrackVideoId: currentTrackVideoId,
            isPlaying: isPlaying,
            playerViewModel: playerViewModel,
            router: router,
            rustCore: rustCore,
            presentation: presentation,
            hideAlbumColumn: hideAlbumColumn,
            showAlbumInSubtitle: showAlbumInSubtitle,
            isReorderable: isReorderable,
            rowHeight: rowHeight,
            likedVideoIds: likedVideoIds,
            playlistContext: playlistContext,
            menuOrigin: menuOrigin,
            onPlayTrack: onPlayTrack,
            onLikeTrack: onLikeTrack,
            onDislikeTrack: onDislikeTrack,
            onRemoveTrackFromPlaylist: onRemoveTrackFromPlaylist,
            onMoveTrack: onMoveTrack,
            onNearBottom: onNearBottom,
            contentInsets: contentInsets,
            scrollingHeader: scrollingHeader,
            scrollingHeaderHeight: scrollingHeaderHeight,
            scrollingBackground: scrollingBackground,
            scrollingBackgroundIdentity: scrollingBackgroundIdentity,
            footer: footer,
            footerHeight: footerHeight
        )
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScroller = nil
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .allowed
        scrollView.autoresizingMask = [.width, .height]
        scrollView.translatesAutoresizingMaskIntoConstraints = true

        let tableView = NativeTrackTableViewInternal()
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = rowHeight
        tableView.usesAutomaticRowHeights = false
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.wantsLayer = true
        tableView.layer?.masksToBounds = false
        tableView.autoresizingMask = [.width]
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        // Configuración de Drag & Drop para reordenamiento si está habilitado
        if isReorderable {
            tableView.registerForDraggedTypes([NSPasteboard.PasteboardType("com.fefucho.sideb.trackRow")])
            tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        }

        // Columna única a ancho completo
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TrackColumn"))
        column.minWidth = 200
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.coordinator = context.coordinator
        tableView.action = #selector(Coordinator.onTableRowClicked(_:))

        scrollView.documentView = tableView
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = contentInsets
        context.coordinator.tableView = tableView

        // Notificación de scroll para actualizar el hover con precisión milimétrica a 120 FPS
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.onClipViewBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        tableView.reloadData()
        context.coordinator.updateScrollingBackground(refreshContent: true)
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        let oldParent = context.coordinator.parent
        let rowsChanged = oldParent.rowItems.count != rowItems.count ||
                          oldParent.rowItems != rowItems || oldParent.presentation != presentation
        if rowsChanged,
           let selected = menuContext?.selectedSong,
           oldParent.tracks.contains(where: { $0.videoId == selected.videoId }),
           !tracks.contains(where: { $0.videoId == selected.videoId }) {
            menuContext?.clearSelection()
        }
        let activeTrackChanged = oldParent.currentTrackVideoId != currentTrackVideoId ||
            oldParent.currentQueueOccurrenceID != currentQueueOccurrenceID ||
            oldParent.currentQueueIndex != currentQueueIndex
        let isPlayingChanged = oldParent.isPlaying != isPlaying
        let likedChanged = oldParent.likedVideoIds != likedVideoIds
        let reorderabilityChanged = oldParent.isReorderable != isReorderable
        let queueDurationChanged = oldParent.currentQueueDuration != currentQueueDuration
        let rowHeightChanged = oldParent.rowHeight != rowHeight || oldParent.footerHeight != footerHeight

        let preservesHeader = scrollingHeader != nil && oldParent.scrollingHeader != nil &&
            oldParent.presentation == presentation
        if rowsChanged, preservesHeader, let tableView = nsView.documentView as? NativeTrackTableViewInternal {
            context.coordinator.replaceCollectionRows(with: self, in: tableView)
        } else {
            context.coordinator.update(parent: self)
        }
        nsView.contentInsets = contentInsets

        if let tableView = nsView.documentView as? NativeTrackTableViewInternal {
            context.coordinator.updateScrollingBackground(refreshContent: true)
            if rowHeightChanged {
                tableView.rowHeight = rowHeight
            }

            // Sincronizar columna para bloqueo total de scroll horizontal
            if let column = tableView.tableColumns.first {
                let targetWidth = nsView.contentView.bounds.width
                if targetWidth > 0 && abs(column.width - targetWidth) > 1 {
                    column.width = targetWidth
                }
            }

            if isReorderable {
                tableView.registerForDraggedTypes([NSPasteboard.PasteboardType("com.fefucho.sideb.trackRow")])
                tableView.setDraggingSourceOperationMask(.move, forLocal: true)
            } else { tableView.unregisterDraggedTypes() }

            if rowsChanged || likedChanged || rowHeightChanged {
                if preservesHeader {
                    // Keep the hosting header attached while typing/filtering so the search field retains focus.
                    let prefix = presentation == .collectionPlaylist ? 2 : 1
                    if !rowsChanged, rowItems.count > prefix {
                        tableView.reloadData(forRowIndexes: IndexSet(integersIn: prefix..<rowItems.count),
                                             columnIndexes: IndexSet(integer: 0))
                        tableView.updateHover()
                    }
                } else { tableView.reloadData() }
            } else if activeTrackChanged || isPlayingChanged || reorderabilityChanged || queueDurationChanged {
                tableView.enumerateAvailableRowViews { rowView, row in
                    guard row < self.rowItems.count else { return }
                    if case .track(let track, let overallIndex, _, let itemIndex) = self.rowItems[row] {
                        if let trackRow = rowView as? NativeTrackRowView {
                            trackRow.isCurrentTrack = context.coordinator.isCurrentOccurrence(videoId: track.videoId, index: overallIndex)
                        }
                        if rowView.numberOfColumns > 0, let cellView = rowView.view(atColumn: 0) as? any NativeTrackCellPresenting {
                            let isCurrent = context.coordinator.isCurrentOccurrence(videoId: track.videoId, index: overallIndex)
                            let displayIndex = (self.sections.count > 1 && self.sections.contains(where: { $0.title != nil })) ? itemIndex : overallIndex
                            cellView.configure(
                                track: track,
                                index: displayIndex,
                                isCurrentTrack: isCurrent,
                                isPlaying: isCurrent && self.isPlaying,
                                isLiked: self.likedVideoIds.contains(track.videoId),
                                hideAlbum: self.hideAlbumColumn,
                                showAlbumInSubtitle: self.showAlbumInSubtitle,
                                isReorderable: self.isReorderable,
                                rowHeight: self.rowHeight
                            )
                            (cellView as? NativeQueueTrackCellView)?.updatePlaybackDuration(isCurrent ? self.currentQueueDuration : nil)
                            cellView.updateCreditFocus(cellView.containsKeyboardFocus)
                            let hovered = (tableView as? NativeTrackTableViewInternal)?.hoveredRowIndex == row
                            cellView.updateHover(isHovered: hovered)
                            cellView.updateSelection(isSelected: tableView.selectedRow == row)
                        }
                    }
                }
            }
            // Height/layout can query the data source. Update it only after the
            // row transaction is complete, especially when clearing an empty filter.
            if let scrollingHeader {
                if oldParent.scrollingHeader != nil, oldParent.scrollingHeaderHeight != scrollingHeaderHeight {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0
                        context.allowsImplicitAnimation = false
                        tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: 0))
                    }
                }
                if let cell = tableView.view(atColumn: 0, row: 0, makeIfNecessary: false) as? NativeTrackFooterCellView {
                    cell.configure(scrollingHeader)
                }
            }
            if let footer, let row = rowItems.indices.last,
               case .footer = rowItems[row],
               let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NativeTrackFooterCellView {
                // Even when two consecutive filters both have zero matches,
                // refresh the message's query without replacing the header.
                cell.configure(footer)
            }
            if oldParent.localizationRevision != localizationRevision {
                context.coordinator.refreshVisibleLocalization(in: tableView)
            }
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? 800,
            height: proposal.height ?? 600
        )
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.detachScrollingBackground()
        (nsView.documentView as? NativeTrackTableViewInternal)?.coordinator = nil
    }

    // MARK: - Coordinator

    @MainActor
    public class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeTrackTableView
        weak var tableView: NativeTrackTableViewInternal?
        private var scrollingBackgroundHost: CollectionBackgroundHostingView?
        private var backgroundInViewport: Bool?
        private let backgroundOwner = UUID()
        private weak var windowBackground: CollectionBackgroundController?

        init(parent: NativeTrackTableView) {
            self.parent = parent
        }

        func update(parent: NativeTrackTableView) {
            self.parent = parent
        }

        func replaceCollectionRows(with next: NativeTrackTableView, in tableView: NativeTrackTableViewInternal) {
            let prefix = next.presentation == .collectionPlaylist ? 2 : 1
            let oldCount = tableView.numberOfRows
            // The data source and AppKit's row cache change in one transaction.
            // Preserve the header/editor rather than detaching them on every keystroke.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                tableView.beginUpdates()
                parent = next
                if oldCount > prefix {
                    tableView.removeRows(at: IndexSet(integersIn: prefix..<oldCount), withAnimation: [])
                }
                if next.rowItems.count > prefix {
                    tableView.insertRows(at: IndexSet(integersIn: prefix..<next.rowItems.count), withAnimation: [])
                }
                tableView.endUpdates()
            }
            tableView.updateHover()
        }

        func isCurrentOccurrence(videoId: String, index: Int) -> Bool {
            guard videoId == parent.currentTrackVideoId else { return false }
            if let origin = parent.menuOrigin?(index), case .queue(let occurrenceIndex) = origin {
                guard let currentIndex = parent.currentQueueIndex else { return false }
                return occurrenceIndex == currentIndex
            }
            return true
        }

        @objc func onClipViewBoundsChanged(_ notification: Notification) {
            tableView?.updateHover()
            updateScrollingBackground()
        }

        func updateScrollingBackground(refreshContent: Bool = false) {
            guard let tableView, let content = parent.scrollingBackground else {
                detachScrollingBackground()
                return
            }
            if let controller = parent.collectionBackgroundController, let identity = parent.scrollingBackgroundIdentity {
                if windowBackground !== controller {
                    detachScrollingBackground()
                    windowBackground = controller
                    controller.register(owner: backgroundOwner, identity: identity, document: tableView,
                                        headerHeight: parent.scrollingHeaderHeight, content: content)
                } else if refreshContent {
                    controller.register(owner: backgroundOwner, identity: identity, document: tableView,
                                        headerHeight: parent.scrollingHeaderHeight, content: content)
                } else {
                    controller.updateGeometry()
                }
                return
            }
            if windowBackground != nil { detachScrollingBackground() }
            // Isolated previews retain a local background when no window shell is present.
            let frame = NSRect(x: 0, y: 0, width: tableView.bounds.width,
                               height: max(1, parent.scrollingHeaderHeight) + 140)
            let visible = tableView.visibleRect.intersects(frame)
            if scrollingBackgroundHost == nil {
                let host = CollectionBackgroundHostingView(rootView: content(visible))
                host.setAccessibilityElement(false)
                scrollingBackgroundHost = host
            }
            guard let host = scrollingBackgroundHost else { return }
            // A document child follows native scrolling without publishing every offset to SwiftUI.
            if host.superview !== tableView || tableView.subviews.first !== host {
                tableView.addSubview(host, positioned: .below, relativeTo: nil)
            }
            if host.frame != frame { host.frame = frame }
            if refreshContent || backgroundInViewport != visible { host.rootView = content(visible) }
            backgroundInViewport = visible
        }

        func detachScrollingBackground() {
            windowBackground?.unregister(owner: backgroundOwner)
            windowBackground = nil
            scrollingBackgroundHost?.removeFromSuperview()
            scrollingBackgroundHost = nil
            backgroundInViewport = nil
        }

        // MARK: - NSTableViewDataSource

        public func numberOfRows(in tableView: NSTableView) -> Int {
            parent.rowItems.count
        }

        // MARK: - NSTableViewDelegate

        public func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            guard row >= 0 && row < parent.rowItems.count else { return false }
            if case .header = parent.rowItems[row] { return true }
            return false
        }

        public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard row >= 0 && row < parent.rowItems.count else { return false }
            if case .header = parent.rowItems[row] { return false }
            if case .footer = parent.rowItems[row] { return false }
            if case .scrollingHeader = parent.rowItems[row] { return false }
            if case .columnLabels = parent.rowItems[row] { return false }
            return true
        }

        public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard row >= 0 && row < parent.rowItems.count else { return parent.rowHeight }
            switch parent.rowItems[row] {
            case .header:
                return 38.0
            case .track:
                return parent.rowHeight
            case .footer:
                return parent.footerHeight
            case .scrollingHeader:
                return max(1, parent.scrollingHeaderHeight)
            case .columnLabels:
                return 42
            }
        }

        public func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else { return }
            tableView.enumerateAvailableRowViews { rowView, row in
                guard rowView.numberOfColumns > 0,
                      let cell = rowView.view(atColumn: 0) as? any NativeTrackCellPresenting else { return }
                cell.updateSelection(isSelected: row == tableView.selectedRow)
                cell.updateHover(isHovered: (tableView as? NativeTrackTableViewInternal)?.hoveredRowIndex == row)
            }
            guard tableView.selectedRow >= 0,
                  tableView.selectedRow < parent.rowItems.count else { return }
            if case .track(let track, _, _, _) = parent.rowItems[tableView.selectedRow] {
                parent.menuContext?.select(track)
            }
        }

        func refreshVisibleLocalization(in tableView: NSTableView) {
            tableView.enumerateAvailableRowViews { rowView, _ in
                guard rowView.numberOfColumns > 0,
                      let content = rowView.view(atColumn: 0) else { return }
                if let cell = content as? any NativeTrackCellPresenting { cell.refreshLocalization() }
                if let labels = content as? NativeCollectionColumnsCellView { labels.updateLocalization() }
            }
        }

        public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard row >= 0 && row < parent.rowItems.count else { return nil }
            switch parent.rowItems[row] {
            case .header:
                let identifier = NSUserInterfaceItemIdentifier("NativeTrackGroupRowView")
                var rowView = tableView.makeView(withIdentifier: identifier, owner: self) as? NativeTrackGroupRowView
                if rowView == nil {
                    rowView = NativeTrackGroupRowView()
                    rowView?.identifier = identifier
                }
                return rowView

            case .footer, .scrollingHeader, .columnLabels:
                return NativeTrackGroupRowView()

            case .track(let track, let overallIndex, _, _):
                let identifier = NSUserInterfaceItemIdentifier("NativeTrackRowView")
                var rowView = tableView.makeView(withIdentifier: identifier, owner: self) as? NativeTrackRowView
                if rowView == nil {
                    rowView = NativeTrackRowView()
                    rowView?.identifier = identifier
                }
                rowView?.isCurrentTrack = isCurrentOccurrence(videoId: track.videoId, index: overallIndex)
                if let customTable = tableView as? NativeTrackTableViewInternal {
                    rowView?.isHovered = (row == customTable.hoveredRowIndex)
                } else {
                    rowView?.isHovered = false
                }
                return rowView
            }
        }

        public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0 && row < parent.rowItems.count else { return nil }
            switch parent.rowItems[row] {
            case .header(let title, _):
                let identifier = NSUserInterfaceItemIdentifier("NativeTrackSectionHeaderCellView")
                var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NativeTrackSectionHeaderCellView
                if cell == nil {
                    cell = NativeTrackSectionHeaderCellView()
                    cell?.identifier = identifier
                }
                cell?.configure(title: title)
                return cell

            case .scrollingHeader:
                guard let content = parent.scrollingHeader else { return nil }
                let identifier = NSUserInterfaceItemIdentifier("NativeCollectionScrollingHeader")
                let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NativeTrackFooterCellView)
                    ?? NativeTrackFooterCellView()
                cell.identifier = identifier
                cell.configure(content)
                return cell
            case .columnLabels:
                let identifier = NSUserInterfaceItemIdentifier("NativeCollectionColumnLabels")
                let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NativeCollectionColumnsCellView)
                    ?? NativeCollectionColumnsCellView(frame: .zero)
                cell.identifier = identifier
                return cell
            case .track(let track, let overallIndex, _, let itemIndex):
                if overallIndex >= parent.tracks.count - 15 { parent.onNearBottom?() }
                if parent.presentation == .collectionAlbum || parent.presentation == .collectionPlaylist {
                    let showsAlbum = parent.presentation == .collectionPlaylist
                    let identifier = NSUserInterfaceItemIdentifier(showsAlbum ? "NativeCollectionPlaylistTrack" : "NativeCollectionAlbumTrack")
                    let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NativeCollectionTrackCellView)
                        ?? NativeCollectionTrackCellView(showsAlbum: showsAlbum)
                    cell.identifier = identifier
                    cell.onPlay = { [weak self] in
                        self?.play(overallIndex: overallIndex, row: row)
                    }
                    cell.onLike = { [weak self] track in self?.parent.onLikeTrack?(track) }
                    cell.onSelectionMouseDown = { [weak self] event in self?.tableView?.mouseDown(with: event) }
                    cell.onMenu = { [weak self] button in
                        guard let menu = self?.menuForRow(row) else { return }
                        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.maxX, y: button.bounds.maxY), in: button)
                    }
                    cell.onCreditFocusChanged = { [weak cell] _ in
                        Task { @MainActor [weak cell] in
                            guard let cell else { return }
                            cell.updateCreditFocus(cell.containsKeyboardFocus)
                        }
                    }
                    cell.onArtist = { [weak self] track in
                        guard let id = track.artistId ?? track.artistRuns.first(where: { $0.id != nil })?.id else { return }
                        self?.parent.router?.navigate(to: .artist(browseId: id))
                    }
                    cell.onAlbum = { [weak self] track in
                        guard let id = track.albumId else { return }
                        self?.parent.router?.navigate(to: .album(browseId: id))
                    }
                    let isCurrent = isCurrentOccurrence(videoId: track.videoId, index: overallIndex)
                    cell.configure(track: track, index: overallIndex, isCurrentTrack: isCurrent,
                                   isPlaying: isCurrent && parent.isPlaying, isLiked: parent.likedVideoIds.contains(track.videoId),
                                   hideAlbum: !showsAlbum, showAlbumInSubtitle: false,
                                   isReorderable: parent.isReorderable, rowHeight: parent.rowHeight)
                    cell.refreshLocalization()
                    cell.updateCreditFocus(cell.containsKeyboardFocus)
                    cell.updateHover(isHovered: (tableView as? NativeTrackTableViewInternal)?.hoveredRowIndex == row)
                    return cell
                }
                if parent.presentation == .queue {
                    let identifier = NSUserInterfaceItemIdentifier("NativeQueueTrackCellView")
                    let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NativeQueueTrackCellView)
                        ?? NativeQueueTrackCellView(frame: .zero)
                    cell.identifier = identifier
                    cell.onLike = { [weak self] track in self?.parent.onLikeTrack?(track) }
                    cell.onDislike = { [weak self] track in self?.parent.onDislikeTrack?(track) }
                    let isCurrent = isCurrentOccurrence(videoId: track.videoId, index: overallIndex)
                    let displayIndex = (parent.sections.count > 1 && parent.sections.contains(where: { $0.title != nil })) ? itemIndex : overallIndex
                    cell.configure(track: track, index: displayIndex, isCurrentTrack: isCurrent,
                                   isPlaying: isCurrent && parent.isPlaying,
                                   isLiked: parent.likedVideoIds.contains(track.videoId),
                                   hideAlbum: true, showAlbumInSubtitle: true,
                                   isReorderable: parent.isReorderable, rowHeight: parent.rowHeight)
                    cell.updatePlaybackDuration(isCurrent ? parent.currentQueueDuration : nil)
                    cell.refreshLocalization()
                    cell.updateCreditFocus(cell.containsKeyboardFocus)
                    cell.updateHover(isHovered: (tableView as? NativeTrackTableViewInternal)?.hoveredRowIndex == row)
                    cell.updateSelection(isSelected: tableView.selectedRow == row)
                    return cell
                }
                let identifier = NSUserInterfaceItemIdentifier("NativeTrackCellView")
                var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NativeTrackCellView
                if cell == nil {
                    cell = NativeTrackCellView()
                    cell?.identifier = identifier
                }

                let isCurrent = isCurrentOccurrence(videoId: track.videoId, index: overallIndex)
                let isHovered = (tableView as? NativeTrackTableViewInternal)?.hoveredRowIndex == row

                cell?.onPlay = { [weak self] in
                    guard let self else { return }
                    TrackTableInteractionPolicy.dispatchPlayback(for: self.parent.rowItems[row], source: .thumbnailPlay) {
                        self.play(overallIndex: $0, row: row)
                    }
                }
                cell?.onMenu = { [weak self] button in
                    guard let self, let menu = self.menuForRow(row) else { return }
                    menu.popUp(positioning: nil,
                               at: NSPoint(x: button.bounds.maxX, y: button.bounds.maxY),
                               in: button)
                }
                cell?.onSelectionMouseDown = { [weak self] event in
                    self?.tableView?.mouseDown(with: event)
                }
                cell?.onCreditFocusChanged = { [weak self, weak cell] focused in
                    guard let self, let cell, let tableView = self.tableView else { return }
                    if focused {
                        cell.updateCreditFocus(true)
                        cell.updateHover(isHovered: (tableView as? NativeTrackTableViewInternal)?.hoveredRowIndex == row)
                        cell.updateSelection(isSelected: tableView.selectedRow == row)
                    } else {
                        Task { @MainActor [weak self, weak cell] in
                            guard let self, let cell, let tableView = self.tableView else { return }
                            cell.updateCreditFocus(cell.containsKeyboardFocus)
                            cell.updateHover(isHovered: (tableView as? NativeTrackTableViewInternal)?.hoveredRowIndex == row)
                            cell.updateSelection(isSelected: tableView.selectedRow == row)
                        }
                    }
                }
                cell?.onArtist = { [weak self] track in
                    guard let self, let router = self.parent.router,
                          let browseId = track.artistId ?? track.artistRuns.first(where: { $0.id != nil })?.id else { return }
                    router.navigate(to: .artist(browseId: browseId))
                }
                cell?.onAlbum = { [weak self] track in
                    guard let self, let router = self.parent.router, let browseId = track.albumId else { return }
                    router.navigate(to: .album(browseId: browseId))
                }

                let displayIndex = (parent.sections.count > 1 && parent.sections.contains(where: { $0.title != nil })) ? itemIndex : overallIndex

                cell?.configure(
                    track: track,
                    index: displayIndex,
                    isCurrentTrack: isCurrent,
                    isPlaying: isCurrent && parent.isPlaying,
                    hideAlbum: parent.hideAlbumColumn,
                    showAlbumInSubtitle: parent.showAlbumInSubtitle,
                    isReorderable: parent.isReorderable,
                    rowHeight: parent.rowHeight
                )
                cell?.refreshLocalization()
                cell?.updateCreditFocus(cell?.containsKeyboardFocus == true)
                cell?.updateHover(isHovered: isHovered)
                cell?.updateSelection(isSelected: tableView.selectedRow == row)

                return cell

            case .footer:
                guard let footer = parent.footer else { return nil }
                let identifier = NSUserInterfaceItemIdentifier("NativeTrackFooterCellView")
                let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NativeTrackFooterCellView)
                    ?? NativeTrackFooterCellView()
                cell.identifier = identifier
                cell.configure(footer)
                return cell
            }
        }

        // MARK: - Drag & Drop (Reordenamiento de Cola)

        public func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard parent.isReorderable, row >= 0 && row < parent.rowItems.count else { return nil }
            guard case .track(_, let overallIndex, _, _) = parent.rowItems[row] else { return nil }
            let item = NSPasteboardItem()
            item.setString("\(overallIndex)", forType: NSPasteboard.PasteboardType("com.fefucho.sideb.trackRow"))
            return item
        }

        public func tableView(
            _ tableView: NSTableView,
            validateDrop info: any NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard parent.isReorderable, parent.onMoveTrack != nil,
                  let sourceTable = info.draggingSource as? NSTableView, sourceTable === tableView else { return [] }
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }

        public func tableView(
            _ tableView: NSTableView,
            acceptDrop info: any NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            guard parent.isReorderable,
                  let sourceTable = info.draggingSource as? NSTableView, sourceTable === tableView,
                  let pasteboard = info.draggingPasteboard.pasteboardItems?.first,
                  let str = pasteboard.string(forType: NSPasteboard.PasteboardType("com.fefucho.sideb.trackRow")),
                  let sourceRow = Int(str) else {
                return false
            }

            guard let destRow = TrackTableInteractionPolicy.dropDestination(
                proposedRow: row, sourceIndex: sourceRow, rows: parent.rowItems, trackCount: parent.tracks.count
            ) else { return false }

            parent.onMoveTrack?(sourceRow, destRow)
            return true
        }

        // MARK: - Context Menu

        func menuForRow(_ row: Int) -> NSMenu? {
            guard row >= 0 && row < parent.rowItems.count else { return nil }
            guard case .track(let track, let overallIndex, _, _) = parent.rowItems[row] else { return nil }
            parent.menuContext?.select(track)
            guard let player = parent.playerViewModel else { return nil }
            let origin = parent.menuOrigin?(overallIndex)
            return AppContextMenuFactory.shared.buildSongNSMenu(
                song: track,
                player: player,
                router: parent.router,
                core: parent.rustCore,
                origin: origin,
                playlistContext: parent.playlistContext,
                onRemoveFromPlaylist: parent.onRemoveTrackFromPlaylist
            )
        }

        func isHeaderRow(_ row: Int) -> Bool {
            guard row >= 0 && row < parent.rowItems.count else { return false }
            if case .header = parent.rowItems[row] { return true }
            if case .footer = parent.rowItems[row] { return true }
            if case .scrollingHeader = parent.rowItems[row] { return true }
            if case .columnLabels = parent.rowItems[row] { return true }
            return false
        }

        // MARK: - Actions

        @objc func onTableRowClicked(_ sender: NSTableView) {
            guard TrackTableInteractionPolicy.isSingleClick(clickCount: NSApp.currentEvent?.clickCount) else { return }
            let clickedRow = sender.clickedRow
            guard clickedRow >= 0 && clickedRow < parent.rowItems.count else { return }
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            let selectionGesture = modifiers.contains(.command) || modifiers.contains(.shift) || modifiers.contains(.control)
            TrackTableInteractionPolicy.dispatchPlayback(
                for: parent.rowItems[clickedRow], source: .row, isSelectionGesture: selectionGesture
            ) { self.play(overallIndex: $0, row: clickedRow) }
        }

        private func play(overallIndex: Int, row: Int) {
            guard parent.rowItems.indices.contains(row),
                  case .track(let track, _, _, _) = parent.rowItems[row] else { return }
            tableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .leftMouseUp {
                // A mouse press does not leave the floating Play focused after leaving the row.
                tableView?.window?.makeFirstResponder(tableView)
            }
            parent.menuContext?.select(track)
            parent.onPlayTrack(overallIndex)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - Native Track Table View Internal (Single Source of Truth for Hover)

final class CollectionBackgroundHostingView: NSHostingView<AnyView> {
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        // The canvas already supplies window/scroll geometry. A second hosting
        // safe area would inset the artwork below the native titlebar again.
        safeAreaRegions = []
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class NativeTrackFooterCellView: NSTableCellView {
    private var hosted: NSHostingView<AnyView>?

    func configure(_ content: AnyView) {
        if let hosted {
            hosted.rootView = content
            return
        }
        let hosted = NSHostingView(rootView: content)
        hosted.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosted)
        NSLayoutConstraint.activate([
            hosted.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosted.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosted.topAnchor.constraint(equalTo: topAnchor),
            hosted.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        self.hosted = hosted
    }
}

final class NativeTrackTableViewInternal: NSTableView {
    weak var coordinator: NativeTrackTableView.Coordinator?

    override func layout() {
        super.layout()
        coordinator?.updateScrollingBackground()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.updateScrollingBackground()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let r = row(at: point)
        guard r >= 0, let coordinator = self.coordinator, !coordinator.isHeaderRow(r) else {
            return super.menu(for: event)
        }
        hoveredRowIndex = r
        return coordinator.menuForRow(r)
    }

    var hoveredRowIndex: Int = -1 {
        didSet {
            guard oldValue != hoveredRowIndex else { return }
            if oldValue >= 0 && oldValue < numberOfRows, let oldRow = rowView(atRow: oldValue, makeIfNecessary: false) as? NativeTrackRowView {
                oldRow.isHovered = false
            }
            if hoveredRowIndex >= 0 && hoveredRowIndex < numberOfRows, let newRow = rowView(atRow: hoveredRowIndex, makeIfNecessary: false) as? NativeTrackRowView {
                newRow.isHovered = true
            }
        }
    }

    override func reloadData() {
        if hoveredRowIndex >= numberOfRows {
            hoveredRowIndex = -1
        }
        super.reloadData()
        updateHover()
    }

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredRowIndex = -1
    }

    func updateHover(at locationInWindow: NSPoint? = nil) {
        guard let window = self.window else {
            hoveredRowIndex = -1
            return
        }
        let loc = locationInWindow ?? window.mouseLocationOutsideOfEventStream
        let pointInTable = convert(loc, from: nil)
        if bounds.contains(pointInTable) {
            let r = row(at: pointInTable)
            if r >= 0 && r < numberOfRows {
                if let coordinator = self.coordinator, coordinator.isHeaderRow(r) {
                    hoveredRowIndex = -1
                } else {
                    hoveredRowIndex = r
                }
            } else {
                hoveredRowIndex = -1
            }
        } else {
            hoveredRowIndex = -1
        }
    }
}

// MARK: - Native Track Section Header & Group Row Views

final class NativeTrackGroupRowView: NSTableRowView {
    override var isOpaque: Bool { false }

    override func drawBackground(in dirtyRect: NSRect) {
        // Fondo transparente para grupo nativo
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // Encabezados no seleccionables
    }
}

final class NativeTrackSectionHeaderCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let dividerLine = NSBox()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.stringValue = ""
    }

    private func setupViews() {
        wantsLayer = true

        titleLabel.font = .systemFont(ofSize: 11.5, weight: .bold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        dividerLine.boxType = .separator
        dividerLine.alphaValue = 0.15
        dividerLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dividerLine)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            dividerLine.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            dividerLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            dividerLine.centerYAnchor.constraint(equalTo: centerYAnchor),
            dividerLine.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    func configure(title: String) {
        titleLabel.stringValue = title.uppercased()
    }
}

// MARK: - Native Track Row View (Zero-Desync Hover)

final class NativeTrackRowView: NSTableRowView {
    var isCurrentTrack: Bool = false {
        didSet {
            if oldValue != isCurrentTrack {
                needsDisplay = true
            }
        }
    }

    var isHovered: Bool = false {
        didSet {
            guard oldValue != isHovered else { return }
            needsDisplay = true
            if numberOfColumns > 0, let cell = view(atColumn: 0) as? any NativeTrackCellPresenting {
                cell.updateHover(isHovered: isHovered)
            }
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let rect = bounds.insetBy(dx: 10, dy: 1)
        let cornerRadius: CGFloat = bounds.height <= 48.0 ? 6 : (bounds.height >= 60.0 ? 8 : 7)
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        if isCurrentTrack {
            context.addPath(path)
            context.setFillColor(NSColor.sidebActiveRowBackground.cgColor)
            context.fillPath()

            context.addPath(path)
            context.setStrokeColor(NSColor.sidebActiveRowBorder.cgColor)
            context.setLineWidth(AppTheme.cardBorderWidth)
            context.strokePath()
        } else if isHovered {
            context.addPath(path)
            context.setFillColor(NSColor.white.withAlphaComponent(0.045).cgColor)
            context.fillPath()
        }
    }
}

// MARK: - Native Track Cell View (Pure AppKit Cell Recycling)

final class NativeTrackCellView: NSTableCellView, NativeTrackCellPresenting {
    private let indexLabel = NSTextField(labelWithString: "")
    private let playingIconView = NSImageView()
    let artworkImageView = NativeTrackActionImageView(frame: .zero)
    let titleLabel = NativeTrackActionField(frame: .zero)
    private let subtitleLabel = NativeTrackCreditField(frame: .zero)
    private let albumLabel = NativeTrackCreditField(frame: .zero)
    private let durationLabel = NSTextField(labelWithString: "")
    private let reorderHandleImageView = NSImageView()
    
    private let thumbnailPlayButton = HomeFocusTrackingButton()
    private let menuButton = HomeFocusTrackingButton()

    private var currentVideoId: String?
    private var imageFetchTask: Task<Void, Never>?
    private var boundTrack: SongItemRecord?
    private var isReorderable: Bool = false
    private var isPointerHovered = false
    private var isRowSelected = false
    private var isCreditFocused = false
    var onPlay: (() -> Void)?
    var onMenu: ((NSButton) -> Void)?
    var onArtist: ((SongItemRecord) -> Void)?
    var onAlbum: ((SongItemRecord) -> Void)?
    var onSelectionMouseDown: ((NSEvent) -> Void)?
    var onCreditFocusChanged: ((Bool) -> Void)?

    private var artworkWidthConstraint: NSLayoutConstraint?
    private var artworkHeightConstraint: NSLayoutConstraint?
    private var thumbnailPlayWidthConstraint: NSLayoutConstraint?
    private var thumbnailPlayHeightConstraint: NSLayoutConstraint?
    private var menuButtonWidthConstraint: NSLayoutConstraint?
    private var menuButtonHeightConstraint: NSLayoutConstraint?
    private var reorderHandleWidthConstraint: NSLayoutConstraint?
    private var reorderHandleHeightConstraint: NSLayoutConstraint?
    private var playingIconWidthConstraint: NSLayoutConstraint?
    private var playingIconHeightConstraint: NSLayoutConstraint?
    private var titleTrailingWithAlbum: NSLayoutConstraint?
    private var titleTrailingNoAlbum: NSLayoutConstraint?
    private var subtitleTrailingWithAlbum: NSLayoutConstraint?
    private var subtitleTrailingNoAlbum: NSLayoutConstraint?
    private var subtitleTrailingInlineAlbum: NSLayoutConstraint?
    private var inlineAlbumLeading: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageFetchTask?.cancel()
        imageFetchTask = nil
        currentVideoId = nil
        boundTrack = nil
        artworkImageView.image = nil
        thumbnailPlayButton.isHidden = true
        menuButton.isHidden = true
        reorderHandleImageView.isHidden = true
        durationLabel.isHidden = false
        isPointerHovered = false
        isRowSelected = false
        isCreditFocused = false
    }

    private func setupViews() {
        wantsLayer = true

        // 1. Índice / Icono
        indexLabel.font = .systemFont(ofSize: 12, weight: .regular)
        indexLabel.textColor = .secondaryLabelColor
        indexLabel.alignment = .right
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indexLabel)

        playingIconView.imageScaling = .scaleProportionallyDown
        playingIconView.contentTintColor = .white
        playingIconView.translatesAutoresizingMaskIntoConstraints = false
        playingIconView.isHidden = true
        addSubview(playingIconView)

        let playingW = playingIconView.widthAnchor.constraint(equalToConstant: 14)
        let playingH = playingIconView.heightAnchor.constraint(equalToConstant: 14)
        self.playingIconWidthConstraint = playingW
        self.playingIconHeightConstraint = playingH

        // 2. Artwork (Dinámico: 36x36, 40x40 o 48x48)
        artworkImageView.wantsLayer = true
        artworkImageView.layer?.cornerRadius = AppTheme.artworkThumbnailRadius
        artworkImageView.layer?.masksToBounds = true
        artworkImageView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        artworkImageView.imageScaling = .scaleProportionallyUpOrDown
        artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        artworkImageView.onActivate = { [weak self] in self?.performArtworkAction() }
        artworkImageView.onSelectionMouseDown = { [weak self] in self?.onSelectionMouseDown?($0) }
        addSubview(artworkImageView)

        // 3. Título y Subtítulo
        for field in [titleLabel, subtitleLabel, albumLabel] {
            field.isEditable = false
            field.isSelectable = false
            field.isBezeled = false
            field.drawsBackground = false
        }
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.onActivate = { [weak self] in self?.performTitleAction() }
        titleLabel.onSelectionMouseDown = { [weak self] in self?.onSelectionMouseDown?($0) }
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.onSelectionMouseDown = { [weak self] in self?.onSelectionMouseDown?($0) }
        subtitleLabel.onFocusChanged = { [weak self] in
            self?.isCreditFocused = $0
            self?.onCreditFocusChanged?($0)
        }
        addSubview(subtitleLabel)

        // 4. Álbum (Columna separada opcional para vistas de Playlist/Álbum)
        albumLabel.font = .systemFont(ofSize: 12, weight: .regular)
        albumLabel.textColor = .secondaryLabelColor
        albumLabel.lineBreakMode = .byTruncatingTail
        albumLabel.maximumNumberOfLines = 1
        albumLabel.translatesAutoresizingMaskIntoConstraints = false
        albumLabel.onSelectionMouseDown = { [weak self] in self?.onSelectionMouseDown?($0) }
        albumLabel.onFocusChanged = { [weak self] in
            self?.isCreditFocused = $0
            self?.onCreditFocusChanged?($0)
        }
        addSubview(albumLabel)

        // 5. El play queda centrado en la miniatura; el menú ocupa el extremo derecho.
        thumbnailPlayButton.bezelStyle = .regularSquare
        thumbnailPlayButton.isBordered = false
        thumbnailPlayButton.imagePosition = .imageOnly
        thumbnailPlayButton.imageScaling = .scaleProportionallyDown
        thumbnailPlayButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: L10n.text("detail.track.play"))
        thumbnailPlayButton.contentTintColor = .white
        thumbnailPlayButton.wantsLayer = true
        thumbnailPlayButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
        thumbnailPlayButton.layer?.cornerRadius = 7
        thumbnailPlayButton.isHidden = true
        thumbnailPlayButton.target = self
        thumbnailPlayButton.action = #selector(onThumbnailPlayClicked)
        thumbnailPlayButton.setAccessibilityLabel(L10n.text("detail.track.play"))
        thumbnailPlayButton.identifier = NSUserInterfaceItemIdentifier("NativeTrackThumbnailPlay")
        thumbnailPlayButton.translatesAutoresizingMaskIntoConstraints = false
        for button in [thumbnailPlayButton, menuButton] {
            button.onFocusChanged = { [weak self] in
                Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self else { return }
                    self.updateCreditFocus(self.containsKeyboardFocus)
                }
            }
        }
        addSubview(thumbnailPlayButton)

        let thumbnailPlayW = thumbnailPlayButton.widthAnchor.constraint(equalToConstant: 28)
        let thumbnailPlayH = thumbnailPlayButton.heightAnchor.constraint(equalToConstant: 28)
        thumbnailPlayWidthConstraint = thumbnailPlayW
        thumbnailPlayHeightConstraint = thumbnailPlayH

        menuButton.bezelStyle = .regularSquare
        menuButton.isBordered = false
        menuButton.imagePosition = .imageOnly
        menuButton.imageScaling = .scaleProportionallyDown
        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L10n.text("common.moreOptions"))
        menuButton.contentTintColor = NSColor.white.withAlphaComponent(0.78)
        menuButton.isHidden = true
        menuButton.target = self
        menuButton.action = #selector(onMenuClicked)
        menuButton.setAccessibilityLabel(L10n.text("detail.track.moreOptionsForSong"))
        menuButton.identifier = NSUserInterfaceItemIdentifier("NativeTrackMenu")
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(menuButton)

        let menuW = menuButton.widthAnchor.constraint(equalToConstant: 24)
        let menuH = menuButton.heightAnchor.constraint(equalToConstant: 22)
        menuButtonWidthConstraint = menuW
        menuButtonHeightConstraint = menuH

        // 6. Duración y Grip Handle de Reordenamiento
        durationLabel.font = .systemFont(ofSize: 12, weight: .regular)
        durationLabel.textColor = .tertiaryLabelColor
        durationLabel.alignment = .right
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(durationLabel)

        reorderHandleImageView.imageScaling = .scaleProportionallyDown
        reorderHandleImageView.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: L10n.text("detail.track.reorder"))
        reorderHandleImageView.contentTintColor = NSColor.white.withAlphaComponent(0.45)
        reorderHandleImageView.translatesAutoresizingMaskIntoConstraints = false
        reorderHandleImageView.isHidden = true
        addSubview(reorderHandleImageView)

        let reorderW = reorderHandleImageView.widthAnchor.constraint(equalToConstant: 18)
        let reorderH = reorderHandleImageView.heightAnchor.constraint(equalToConstant: 16)
        self.reorderHandleWidthConstraint = reorderW
        self.reorderHandleHeightConstraint = reorderH

        // Constraints de tamaño de artwork
        let artW = artworkImageView.widthAnchor.constraint(equalToConstant: 48)
        let artH = artworkImageView.heightAnchor.constraint(equalToConstant: 48)
        self.artworkWidthConstraint = artW
        self.artworkHeightConstraint = artH

        // Constraints condicionales para cuando hay columna de álbum separada vs compacta
        let tWithAlbum = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: albumLabel.leadingAnchor, constant: -14)
        let tNoAlbum = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -12)
        let sWithAlbum = subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: albumLabel.leadingAnchor, constant: -14)
        let sNoAlbum = subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -12)
        let sInlineAlbum = subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: albumLabel.leadingAnchor, constant: -4)
        let inlineAlbumStart = albumLabel.leadingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor, constant: 6)

        self.titleTrailingWithAlbum = tWithAlbum
        self.titleTrailingNoAlbum = tNoAlbum
        self.subtitleTrailingWithAlbum = sWithAlbum
        self.subtitleTrailingNoAlbum = sNoAlbum
        self.subtitleTrailingInlineAlbum = sInlineAlbum
        self.inlineAlbumLeading = inlineAlbumStart

        NSLayoutConstraint.activate([
            // Índice
            indexLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            indexLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            indexLabel.widthAnchor.constraint(equalToConstant: 24),

            playingIconView.centerXAnchor.constraint(equalTo: indexLabel.centerXAnchor),
            playingIconView.centerYAnchor.constraint(equalTo: indexLabel.centerYAnchor),
            playingW,
            playingH,

            // Artwork
            artworkImageView.leadingAnchor.constraint(equalTo: indexLabel.trailingAnchor, constant: 10),
            artworkImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            artW,
            artH,
            thumbnailPlayButton.centerXAnchor.constraint(equalTo: artworkImageView.centerXAnchor),
            thumbnailPlayButton.centerYAnchor.constraint(equalTo: artworkImageView.centerYAnchor),
            thumbnailPlayW,
            thumbnailPlayH,

            // Título
            titleLabel.leadingAnchor.constraint(equalTo: artworkImageView.trailingAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1.5),

            // Subtítulo (Artista • Álbum)
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1.5),

            // Álbum separado (opcional)
            albumLabel.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -12),
            albumLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            albumLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 160),

            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            menuButton.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            menuW,
            menuH,

            // Duración
            durationLabel.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -8),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 44),

            // Handle Reordenar (mismo centro que la duración)
            reorderHandleImageView.centerXAnchor.constraint(equalTo: durationLabel.centerXAnchor),
            reorderHandleImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            reorderW,
            reorderH,

            // Activación inicial sin álbum separado
            tNoAlbum,
            sNoAlbum
        ])
    }

    @objc private func onThumbnailPlayClicked() {
        guard TrackTableInteractionPolicy.isSingleClick(clickCount: NSApp.currentEvent?.clickCount) else { return }
        performThumbnailPlayAction()
    }
    @objc private func onMenuClicked() {
        guard TrackTableInteractionPolicy.isSingleClick(clickCount: NSApp.currentEvent?.clickCount) else { return }
        performMenuAction()
    }

    func performPrimaryAction() { onPlay?() }
    func performTitleAction() { performPrimaryAction() }
    func performArtworkAction() { performPrimaryAction() }
    func performThumbnailPlayAction() { performPrimaryAction() }
    func performArtistCreditAction() { if let boundTrack { onArtist?(boundTrack) } else { onPlay?() } }
    func performAlbumCreditAction() { if let boundTrack { onAlbum?(boundTrack) } else { onPlay?() } }
    func performMenuAction() { onMenu?(menuButton) }

    func updateHover(isHovered: Bool) {
        isPointerHovered = isHovered
        if isReorderable {
            durationLabel.isHidden = isHovered
            reorderHandleImageView.isHidden = !isHovered
        } else {
            durationLabel.isHidden = false
            reorderHandleImageView.isHidden = true
        }

        updateHoverControls()
    }

    func updateSelection(isSelected: Bool) {
        isRowSelected = isSelected
        updateHoverControls()
    }

    func updateCreditFocus(_ isFocused: Bool) {
        isCreditFocused = isFocused
        updateHoverControls()
    }

    func refreshLocalization() {
        if let track = boundTrack {
            if track.artists.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                subtitleLabel.stringValue = track.displayArtist
                subtitleLabel.setAccessibilityLabel(track.displayArtist)
            }
            if track.displayAlbum == nil {
                albumLabel.stringValue = L10n.text("detail.track.album")
                albumLabel.setAccessibilityLabel(albumLabel.stringValue)
            }
        }
        let play = L10n.text("detail.track.play")
        let more = L10n.text("detail.track.moreOptionsForSong")
        let reorder = L10n.text("detail.track.reorder")
        artworkImageView.setAccessibilityLabel(L10n.text("detail.track.artwork"))
        thumbnailPlayButton.setAccessibilityLabel(play)
        thumbnailPlayButton.toolTip = play
        menuButton.setAccessibilityLabel(more)
        menuButton.toolTip = more
        reorderHandleImageView.setAccessibilityLabel(reorder)
        reorderHandleImageView.toolTip = reorder
    }

    var containsKeyboardFocus: Bool {
        var responder = window?.firstResponder
        while let current = responder {
            guard let view = current as? NSView else { return false }
            if view === self { return true }
            responder = view.superview
        }
        return false
    }

    private func updateHoverControls() {
        // La selección permanece resaltada en NSTableView, pero no mantiene acciones
        // flotantes visibles después de que el puntero abandona la fila.
        let showControls = isPointerHovered || isCreditFocused
        thumbnailPlayButton.isHidden = !showControls
        menuButton.isHidden = !showControls
    }

    func configure(
        track: SongItemRecord,
        index: Int,
        isCurrentTrack: Bool,
        isPlaying: Bool,
        isLiked: Bool = false,
        hideAlbum: Bool = false,
        showAlbumInSubtitle: Bool = false,
        isReorderable: Bool = false,
        rowHeight: CGFloat = 52.0
    ) {
        self.boundTrack = track
        self.currentVideoId = track.videoId
        self.isReorderable = isReorderable
        let artistDestination = track.artistId ?? track.artistRuns.first(where: { $0.id != nil })?.id
        subtitleLabel.configureLink(label: track.displayArtist, destinationExists: artistDestination != nil) { [weak self] in
            self?.performArtistCreditAction()
        } fallback: { [weak self] in self?.performPrimaryAction() }
        albumLabel.configureLink(label: track.displayAlbum ?? L10n.text("detail.track.album"), destinationExists: track.albumId != nil) { [weak self] in
            self?.performAlbumCreditAction()
        } fallback: { [weak self] in self?.performPrimaryAction() }

        let isCompact = rowHeight <= 48.0
        let isLarge = rowHeight >= 60.0

        let titleFontSize: CGFloat = isCompact ? 13.0 : (isLarge ? 14.0 : 13.5)
        let subtitleFontSize: CGFloat = isCompact ? 11.5 : (isLarge ? 12.0 : 12.0)

        // 1. Estado de reproducción e índice
        if isCurrentTrack {
            indexLabel.isHidden = true
            playingIconView.isHidden = false
            let symbolName = isPlaying ? "speaker.wave.3.fill" : "speaker.fill"
            let iconPtSize: CGFloat = isCompact ? 11.5 : 13.0
            let iconConfig = NSImage.SymbolConfiguration(pointSize: iconPtSize, weight: .semibold)
            playingIconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(iconConfig)
            titleLabel.textColor = .labelColor
            titleLabel.font = .systemFont(ofSize: titleFontSize, weight: .semibold)
        } else {
            indexLabel.isHidden = false
            playingIconView.isHidden = true
            indexLabel.stringValue = "\(index + 1)"
            indexLabel.font = .systemFont(ofSize: subtitleFontSize, weight: .regular)
            titleLabel.textColor = .labelColor
            titleLabel.font = .systemFont(ofSize: titleFontSize, weight: .medium)
        }

        // 2. Metadatos
        titleLabel.stringValue = track.title

        subtitleLabel.font = .systemFont(ofSize: subtitleFontSize, weight: .regular)

        let albumName = track.displayAlbum?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAlbumName = albumName?.isEmpty == false
        let usesSeparateAlbum = !hideAlbum && !showAlbumInSubtitle && hasAlbumName
        let usesInlineAlbum = showAlbumInSubtitle && hasAlbumName
        let showsAlbum = usesSeparateAlbum || usesInlineAlbum
        albumLabel.stringValue = showsAlbum ? "\(usesInlineAlbum ? "• " : "")\(albumName ?? "")" : ""
        albumLabel.font = .systemFont(ofSize: subtitleFontSize, weight: .regular)
        albumLabel.isHidden = !showsAlbum
        inlineAlbumLeading?.isActive = usesInlineAlbum
        subtitleLabel.setAccessibilityLabel(track.displayArtist)
        albumLabel.setAccessibilityLabel(albumName ?? L10n.text("detail.track.album"))

        if usesSeparateAlbum {
            titleTrailingNoAlbum?.isActive = false
            subtitleTrailingNoAlbum?.isActive = false
            titleTrailingWithAlbum?.isActive = true
            subtitleTrailingWithAlbum?.isActive = true
            subtitleTrailingInlineAlbum?.isActive = false
        } else if usesInlineAlbum {
            titleTrailingNoAlbum?.isActive = false
            subtitleTrailingNoAlbum?.isActive = false
            titleTrailingWithAlbum?.isActive = true
            subtitleTrailingWithAlbum?.isActive = false
            subtitleTrailingInlineAlbum?.isActive = true
        } else {
            titleTrailingWithAlbum?.isActive = false
            subtitleTrailingWithAlbum?.isActive = false
            subtitleTrailingInlineAlbum?.isActive = false
            titleTrailingNoAlbum?.isActive = true
            subtitleTrailingNoAlbum?.isActive = true
        }

        durationLabel.stringValue = track.duration ?? ""
        durationLabel.font = .systemFont(ofSize: subtitleFontSize, weight: .regular)

        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L10n.text("common.moreOptions"))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: isCompact ? 12 : 13, weight: .semibold))

        // Handle de reordenar
        let handleW: CGFloat = isCompact ? 16.0 : 18.0
        let handleH: CGFloat = isCompact ? 14.0 : 16.0
        reorderHandleWidthConstraint?.constant = handleW
        reorderHandleHeightConstraint?.constant = handleH
        let handleConfig = NSImage.SymbolConfiguration(pointSize: isCompact ? 12.0 : 13.5, weight: .regular)
        reorderHandleImageView.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: L10n.text("detail.track.reorder"))?.withSymbolConfiguration(handleConfig)

        // Icono de reproducción
        let playIconSize: CGFloat = isCompact ? 12.0 : 14.0
        playingIconWidthConstraint?.constant = playIconSize
        playingIconHeightConstraint?.constant = playIconSize

        // 4. Adaptación de tamaño de carátula según altura de fila
        let artSize: CGFloat = isLarge ? 48.0 : (isCompact ? 36.0 : 40.0)
        artworkWidthConstraint?.constant = artSize
        artworkHeightConstraint?.constant = artSize
        thumbnailPlayWidthConstraint?.constant = min(28, artSize - 4)
        thumbnailPlayHeightConstraint?.constant = min(28, artSize - 4)
        menuButtonWidthConstraint?.constant = isCompact ? 22 : 24
        menuButtonHeightConstraint?.constant = isCompact ? 20 : 22
        artworkImageView.layer?.cornerRadius = AppTheme.artworkThumbnailRadius

        // 5. Estado inicial de hover
        durationLabel.isHidden = false
        reorderHandleImageView.isHidden = true
        thumbnailPlayButton.isHidden = true
        menuButton.isHidden = true

        // 6. Miniatura Desacoplada (0ms de impacto en SwiftUI)
        loadThumbnail(for: track, targetSize: CGSize(width: artSize, height: artSize))
    }

    private func loadThumbnail(for track: SongItemRecord, targetSize: CGSize) {
        guard let thumbUrlString = track.thumbnail,
              let url = ImageURLHelper.optimizedThumbnailURL(from: thumbUrlString, targetPixelSize: Int(targetSize.width * 2))
        else {
            artworkImageView.image = nil
            return
        }

        // Fast-path en RAM: lectura sincrónica de memoria sin esperas ni tareas
        if let cached = ImageCache.shared.imageFromMemoryCache(for: url, targetSize: targetSize) {
            artworkImageView.image = cached
            return
        }

        // Carga en segundo plano fuera de SwiftUI
        let expectedVideoId = track.videoId
        imageFetchTask?.cancel()
        imageFetchTask = Task(priority: .utility) { @MainActor [weak self] in
            let loaded = await ImageCache.shared.image(for: url, targetSize: targetSize)
            guard !Task.isCancelled else { return }
            guard let self, self.currentVideoId == expectedVideoId else { return }
            self.artworkImageView.image = loaded
        }
    }
}

/// Texto de crédito que consume su propio clic cuando existe un destino de navegación.
class NativeTrackActionField: NSTextField {
    var onActivate: (() -> Void)?
    var onSelectionMouseDown: ((NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard TrackTableInteractionPolicy.isSingleClick(clickCount: event.clickCount) else { return }
        let selectionModifiers: NSEvent.ModifierFlags = [.command, .shift, .control]
        if !event.modifierFlags.intersection(selectionModifiers).isEmpty {
            if let onSelectionMouseDown { onSelectionMouseDown(event) }
            else { super.mouseDown(with: event) }
            return
        }
        if let onActivate { onActivate() }
        else { super.mouseDown(with: event) }
    }
}

final class NativeTrackCreditField: NativeTrackActionField, PlaybackSpaceControl {
    private var linkAction: (() -> Void)?
    private var fallbackAction: (() -> Void)?
    var onFocusChanged: ((Bool) -> Void)?
    var showsHoverHighlight = false {
        didSet { updateTrackingAreas(); updateLinkAppearance() }
    }
    private var hoverArea: NSTrackingArea?
    private var isCreditHovered = false
    private var isCreditFocused = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        hoverArea = nil
        guard showsHoverHighlight else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if showsHoverHighlight, linkAction != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func mouseEntered(with event: NSEvent) { setCreditHovered(true) }
    override func mouseExited(with event: NSEvent) { setCreditHovered(false) }

    func setCreditHovered(_ hovered: Bool) {
        isCreditHovered = hovered
        updateLinkAppearance()
    }

    private func updateLinkAppearance() {
        guard showsHoverHighlight else { return }
        textColor = linkAction != nil && (isCreditHovered || isCreditFocused) ? .labelColor : .secondaryLabelColor
    }

    func configureLink(
        label: String,
        destinationExists: Bool,
        action: @escaping () -> Void,
        fallback: @escaping () -> Void
    ) {
        stringValue = label
        linkAction = destinationExists ? action : nil
        fallbackAction = fallback
        isCreditHovered = window.map { window in
            window.isKeyWindow && visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } ?? false
        onActivate = { [weak self] in self?.activateCredit() }
        setAccessibilityLabel(label)
        if destinationExists {
            setAccessibilityRole(.link)
            focusRingType = .exterior
        } else {
            setAccessibilityRole(.staticText)
            focusRingType = .none
        }
        updateLinkAppearance()
        window?.invalidateCursorRects(for: self)
    }

    override var acceptsFirstResponder: Bool { linkAction != nil }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder { isCreditFocused = true; updateLinkAppearance(); onFocusChanged?(true) }
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { isCreditFocused = false; updateLinkAppearance(); onFocusChanged?(false) }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        if linkAction != nil && (event.keyCode == 36 || event.keyCode == 49) {
            activateCredit()
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard linkAction != nil else { return false }
        activateCredit()
        return true
    }

    private func activateCredit() {
        if let linkAction { linkAction() }
        else { fallbackAction?() }
    }
}

final class NativeTrackActionImageView: NSImageView {
    var onActivate: (() -> Void)?
    var onSelectionMouseDown: ((NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard TrackTableInteractionPolicy.isSingleClick(clickCount: event.clickCount) else { return }
        let selectionModifiers: NSEvent.ModifierFlags = [.command, .shift, .control]
        if !event.modifierFlags.intersection(selectionModifiers).isEmpty {
            if let onSelectionMouseDown { onSelectionMouseDown(event) }
            else { super.mouseDown(with: event) }
            return
        }
        if let onActivate { onActivate() }
        else { super.mouseDown(with: event) }
    }
}
