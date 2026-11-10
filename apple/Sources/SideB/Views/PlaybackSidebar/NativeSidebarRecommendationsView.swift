import AppKit
import os
import SwiftUI
import SideBCore

private let sidebarRecommendationsLog = OSLog(subsystem: "com.fefucho.SideB", category: .pointsOfInterest)

/// Owns the sole vertical viewport above the fixed hero. Observation stops at
/// semantic inputs: playback position and the per-pixel artwork progress are absent.
struct NativeSidebarRecommendationsView: View {
    let viewModel: PlayerViewModel
    var router: NavigationRouter?
    let heroHeight: CGFloat
    let state: SidebarArtworkScrollState
    let occurrenceKey: SidebarArtworkOccurrenceKey

    var body: some View {
        NativeSidebarRecommendationsViewport(
            player: viewModel, router: router, heroHeight: heroHeight,
            state: state, occurrenceKey: occurrenceKey,
            dataRevision: viewModel.recommendedRevision, data: viewModel.recommendedData, loading: viewModel.isLoadingRecommended,
            error: viewModel.recommendedData?.loadedVideoId == viewModel.currentTrack?.videoId ? viewModel.recommendedError : nil,
            liked: viewModel.likedVideoIds, playing: viewModel.isPlaying,
            currentVideoID: viewModel.currentTrack?.videoId,
            requestKey: viewModel.recommendationContextKey
        )
    }
}

struct NativeSidebarRecommendationsProjection {
    enum Row: Equatable {
        case hero, refresh, heading(String, String?, Bool), track(SidebarRecommendedItem)
        case artists([BrowseCardRecord]), status(String)

        var identity: String {
            switch self {
            case .hero: return "hero"
            case .refresh: return "refresh"
            case .heading(let title, _, _): return "heading:" + title
            case .track(let item): return item.id
            case .artists: return "artists"
            case .status: return "status"
            }
        }
    }
    let rows: [Row]

    init(data: RecommendedData?, activated: Bool, loading: Bool, error: String? = nil) {
        var result: [Row] = [.hero]
        // No artwork requests or artist views are constructed before actual scroll.
        guard activated else { rows = result + [.status("")]; return }
        result.append(.refresh)
        if let data, !data.isEmpty {
            let prepared = PreparedSidebarRecommendations(data: data)
            if !prepared.artists.isEmpty {
                result.append(.heading(L10n.text("fullscreen.fansAlsoLike"), nil, true))
                result.append(.artists(prepared.artists))
            }
            func append(_ items: [SidebarRecommendedItem], title: String, destination: String? = nil, artist: Bool = false) {
                guard !items.isEmpty else { return }
                result.append(.heading(title, destination, artist))
                result += items.map { .track($0) }
            }
            append(prepared.similarSongs, title: L10n.text("fullscreen.similarSongs"))
            append(prepared.artistSongs,
                   title: prepared.artistName.map { L10n.text("fullscreen.moreByArtist", args: [$0]) } ?? L10n.text("fullscreen.moreByThisArtist"),
                   destination: prepared.artistBrowseId, artist: true)
            append(prepared.albumSongs,
                   title: prepared.albumTitle.map { L10n.text("fullscreen.fromAlbum", args: [$0]) } ?? L10n.text("fullscreen.fromSameAlbum"),
                   destination: prepared.albumBrowseId)
        } else {
            result.append(.status(error ?? L10n.text(loading ? "common.loading" : "fullscreen.noRecommendations")))
        }
        if data?.isEmpty == false, let error { result.append(.status(error)) }
        rows = result
    }
}

struct NativeSidebarRecommendationsViewport: NSViewRepresentable {
    let player: PlayerViewModel
    let router: NavigationRouter?
    let heroHeight: CGFloat
    let state: SidebarArtworkScrollState
    let occurrenceKey: SidebarArtworkOccurrenceKey
    var dataRevision: UInt64? = nil
    let data: RecommendedData?
    let loading: Bool
    let error: String?
    let liked: Set<String>
    let playing: Bool
    let currentVideoID: String?
    let requestKey: RecommendedRequestState.Key?
    private var localizationRevision = L10n.revision

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView { makeScrollView(coordinator: context.coordinator) }

    func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scroll = NativeSidebarScrollView()
        scroll.wantsLayer = true
        scroll.appearance = NSAppearance(named: .darkAqua)
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.contentView.wantsLayer = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        let table = NativeSidebarRecommendationsTable()
        table.wantsLayer = true
        table.headerView = nil
        table.backgroundColor = .clear
        table.style = .plain
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: .init("recommendations"))
        column.minWidth = 0
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.autoresizingMask = [.width]
        table.delegate = coordinator
        table.dataSource = coordinator
        table.owner = coordinator
        table.target = coordinator
        table.action = #selector(Coordinator.activate(_:))
        scroll.documentView = table
        scroll.installHero(player: player, router: router, state: state, height: heroHeight)
        coordinator.table = table
        coordinator.scroll = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        coordinator.update(self, initial: true)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) { context.coordinator.update(self) }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.parent.state.savedOffsetY = max(0, nsView.contentView.bounds.minY)
        coordinator.cancelVisibleImages()
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeSidebarRecommendationsViewport
        weak var table: NSTableView?
        weak var scroll: NSScrollView?
        var rows: [NativeSidebarRecommendationsProjection.Row] = []
        private var projectedData: RecommendedData?
        private var activated = false
        private var projectedLoading = false
        private var applying = false
        private var lastHeroHeight: CGFloat = 0
        private(set) var projectionBuildCount = 0
        init(_ parent: NativeSidebarRecommendationsViewport) { self.parent = parent }
        deinit { NotificationCenter.default.removeObserver(self) }

        func update(_ next: NativeSidebarRecommendationsViewport, initial: Bool = false) {
            let interval = OSSignpostID(log: sidebarRecommendationsLog)
            os_signpost(.begin, log: sidebarRecommendationsLog, name: "SidebarRecommendations.Update", signpostID: interval)
            defer { os_signpost(.end, log: sidebarRecommendationsLog, name: "SidebarRecommendations.Update", signpostID: interval) }
            let previous = parent
            parent = next
            (scroll as? NativeSidebarScrollView)?.updateHero(player: next.player, router: next.router, state: next.state, height: next.heroHeight)
            let reset = next.state.synchronizeOccurrence(next.occurrenceKey)
            var target = reset ? 0 : (initial ? next.state.savedOffsetY : scroll?.contentView.bounds.minY ?? 0)
            let geometryAnchorRow = table?.row(at: NSPoint(x: 1, y: target + 1)) ?? -1
            let geometryAnchor: (String, CGFloat)? = !reset && previous.heroHeight != next.heroHeight && geometryAnchorRow > 0 && rows.indices.contains(geometryAnchorRow)
                ? (rows[geometryAnchorRow].identity, target - (table?.rect(ofRow: geometryAnchorRow).minY ?? target)) : nil
            let active = (!reset && (activated || next.state.isRecommendationsActive)) || target >= SidebarRecommendationScrollPolicy.activationOffset
            let dataChanged = next.dataRevision.map { previous.dataRevision != $0 } ?? (projectedData != next.data)
            let changed = initial || reset || active != activated || dataChanged || projectedLoading != next.loading || previous.error != next.error || previous.localizationRevision != next.localizationRevision
            if active { next.state.isRecommendationsActive = true }
            applying = true
            if changed {
                activated = active
                projectedData = next.data
                projectedLoading = next.loading
                let nextRows = NativeSidebarRecommendationsProjection(data: next.data, activated: active, loading: next.loading, error: next.error).rows
                projectionBuildCount += 1
                let oldRows = rows
                let oldAnchorRow = table?.row(at: NSPoint(x: 1, y: target + 1)) ?? -1
                let anchorID = oldRows.indices.contains(oldAnchorRow) ? oldRows[oldAnchorRow].identity : nil
                let anchorInset = oldAnchorRow >= 0 ? target - (table?.rect(ofRow: oldAnchorRow).minY ?? target) : 0
                rows = nextRows
                if initial || reset || oldRows.isEmpty { table?.reloadData() }
                else if oldRows.map(\.identity) == nextRows.map(\.identity) {
                    let changedRows = IndexSet(nextRows.indices.filter { oldRows[$0] != nextRows[$0] })
                    if !changedRows.isEmpty { table?.reloadData(forRowIndexes: changedRows, columnIndexes: IndexSet(integer: 0)) }
                } else {
                    var prefix = 0
                    while prefix < min(oldRows.count, nextRows.count), oldRows[prefix].identity == nextRows[prefix].identity { prefix += 1 }
                    var suffix = 0
                    while suffix < min(oldRows.count, nextRows.count) - prefix,
                          oldRows[oldRows.count - suffix - 1].identity == nextRows[nextRows.count - suffix - 1].identity { suffix += 1 }
                    table?.beginUpdates()
                    if oldRows.count - suffix > prefix { table?.removeRows(at: IndexSet(integersIn: prefix..<(oldRows.count - suffix)), withAnimation: []) }
                    if nextRows.count - suffix > prefix { table?.insertRows(at: IndexSet(integersIn: prefix..<(nextRows.count - suffix)), withAnimation: []) }
                    table?.endUpdates()
                    // Retained identities can still carry updated metadata or artist cards.
                    var changedRows = IndexSet()
                    for index in 0..<prefix where oldRows[index] != nextRows[index] { changedRows.insert(index) }
                    for index in 0..<suffix where oldRows[oldRows.count-index-1] != nextRows[nextRows.count-index-1] { changedRows.insert(nextRows.count-index-1) }
                    if !changedRows.isEmpty { table?.reloadData(forRowIndexes: changedRows, columnIndexes: IndexSet(integer: 0)) }
                }
                if !initial && !reset, let anchorID, let newIndex = rows.firstIndex(where: { $0.identity == anchorID }), oldAnchorRow > 0 {
                    target = (table?.rect(ofRow: newIndex).minY ?? target) + anchorInset
                }
            }
            if previous.loading != next.loading, let refreshRow = rows.firstIndex(where: { if case .refresh = $0 { return true }; return false }) {
                table?.reloadData(forRowIndexes: IndexSet(integer: refreshRow), columnIndexes: IndexSet(integer: 0))
            }
            if previous.localizationRevision != next.localizationRevision {
                table?.reloadData(forRowIndexes: IndexSet(integersIn: 0..<rows.count), columnIndexes: IndexSet(integer: 0))
            }
            if previous.liked != next.liked || previous.playing != next.playing || previous.currentVideoID != next.currentVideoID {
                refreshVisibleTracks()
            }
            if lastHeroHeight != next.heroHeight {
                table?.noteHeightOfRows(withIndexesChanged: IndexSet(integer: 0))
                lastHeroHeight = next.heroHeight
            }
            table?.layoutSubtreeIfNeeded()
            if let (identity, inset) = geometryAnchor, let row = rows.firstIndex(where: { $0.identity == identity }) {
                target = (table?.rect(ofRow: row).minY ?? target) + inset
            }
            scroll?.contentView.scroll(to: NSPoint(x: 0, y: max(0, target)))
            if let scroll { scroll.reflectScrolledClipView(scroll.contentView) }
            (table as? NativeSidebarRecommendationsTable)?.refreshPointerHover()
            next.state.savedOffsetY = max(0, scroll?.contentView.bounds.minY ?? target)
            (scroll as? NativeSidebarScrollView)?.layoutHeroLayers()
            applying = false
            if previous.requestKey != next.requestKey, target >= SidebarRecommendationScrollPolicy.activationOffset {
                DispatchQueue.main.async { [weak self] in self?.scrolled() }
            }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            switch rows[row] {
            case .hero: return max(1, parent.heroHeight)
            case .refresh: return 44
            case .heading: return 40
            case .track: return 54
            case .artists: return NativeSidebarArtistShelfCell.height
            case .status: return 180
            }
        }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            if case .track = rows[row] { return true }; return false
        }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            if case .track(let item) = rows[row] {
                let view = NativeTrackRowView()
                view.isCurrentTrack = item.track.videoId == parent.currentVideoID
                return view
            }
            return NativeSidebarTableRowView()
        }
        func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
            (rowView.view(atColumn: 0) as? NativeQueueTrackCellView)?.prepareForReuse()
            (rowView.view(atColumn: 0) as? NativeSidebarArtistShelfCell)?.prepareForReuse()
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            switch rows[row] {
            case .hero:
                // The transparent spacer exposes the fixed hero below this viewport.
                return SidebarHeroSpacerView()
            case .track(let item):
                let id = NSUserInterfaceItemIdentifier("SidebarRecommendationTrack")
                let cell = tableView.makeView(withIdentifier: id, owner: self) as? NativeQueueTrackCellView ?? NativeQueueTrackCellView()
                cell.identifier = id
                configure(cell, item: item)
                return cell
            case .artists(let cards):
                let id = NativeSidebarArtistShelfCell.reuseIdentifier
                let cell = tableView.makeView(withIdentifier: id, owner: self) as? NativeSidebarArtistShelfCell ?? NativeSidebarArtistShelfCell()
                cell.identifier = id
                cell.configure(cards: cards, onActivate: { [weak self] in self?.navigate($0.id, artist: true) },
                               onMenu: { [weak self] in self?.artistMenu($0) })
                return cell
            default:
                let id = NSUserInterfaceItemIdentifier("SidebarRecommendationHeading")
                let cell = tableView.makeView(withIdentifier: id, owner: self) as? NativeSidebarActionCell ?? NativeSidebarActionCell()
                cell.identifier = id
                cell.action = nil
                switch rows[row] {
                case .refresh:
                    cell.configure(title: L10n.text("fullscreen.recommendations"), button: L10n.text("common.refresh"), enabled: !parent.loading && parent.currentVideoID != nil)
                    cell.action = { [weak self] in self?.parent.player.refreshRecommendations() }
                case .heading(let title, let id, let artist):
                    cell.configure(title: title, button: id == nil ? nil : L10n.text(artist ? "detail.viewArtist" : "detail.viewAlbum"), enabled: parent.router != nil)
                    cell.action = { [weak self] in if let id { self?.navigate(id, artist: artist) } }
                case .status(let title):
                    cell.configure(title: title, button: activated && !parent.loading ? L10n.text("common.retry") : nil, enabled: parent.currentVideoID != nil)
                    cell.action = { [weak self] in self?.parent.player.refreshRecommendations() }
                default: break
                }
                return cell
            }
        }
        private func configure(_ cell: NativeQueueTrackCellView, item: SidebarRecommendedItem) {
            let song = item.track
            let current = parent.currentVideoID == song.videoId
            cell.configure(track: song, index: item.index, isCurrentTrack: current, isPlaying: current && parent.playing,
                           isLiked: parent.liked.contains(song.videoId), hideAlbum: true, showAlbumInSubtitle: true, isReorderable: false, rowHeight: 54)
            cell.setSidebarRecommendationAppearance()
            cell.setAddToQueueAction { [weak self] in
                self?.parent.player.addToQueue(song: song)
            }
            cell.onLike = { [weak self] in self?.parent.player.toggleTrackLike($0) }
            cell.onDislike = { [weak self] in self?.parent.player.dislikeTrack($0) }
            cell.onArtistDestination = { [weak self] id, name in
                guard let self else { return }
                if let id { self.navigate(id, artist: true) }
                else { self.parent.router?.navigate(to: .search(query: name)) }
            }
        }
        private func refreshVisibleTracks() {
            guard let table else { return }
            let range = table.rows(in: table.visibleRect)
            guard range.location != NSNotFound else { return }
            for row in range.location..<NSMaxRange(range) where rows.indices.contains(row) {
                if case .track(let item) = rows[row], let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? NativeQueueTrackCellView {
                    configure(cell, item: item)
                    let rowView = table.rowView(atRow: row, makeIfNecessary: false) as? NativeTrackRowView
                    rowView?.isCurrentTrack = item.track.videoId == parent.currentVideoID
                    cell.updateHover(isHovered: rowView?.isHovered ?? false)
                }
            }
        }
        func cancelVisibleImages() {
            guard let table else { return }
            for row in 0..<table.numberOfRows {
                (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? NativeQueueTrackCellView)?.prepareForReuse()
                (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? NativeSidebarArtistShelfCell)?.prepareForReuse()
            }
        }
        func navigate(_ id: String, artist: Bool) {
            if parent.player.isFullscreenPresented { parent.player.dismissFullscreen() }
            parent.router?.navigate(to: artist ? .artist(browseId: id) : .album(browseId: id))
        }
        @objc func activate(_ sender: NSTableView) { perform(sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow) }
        func perform(_ row: Int) {
            guard rows.indices.contains(row) else { return }
            switch rows[row] {
            case .track(let item):
                if parent.currentVideoID == item.track.videoId { parent.player.togglePlayPause() }
                else { parent.player.activateMediaRadio(item.track) }
            default: break
            }
        }
        func menu(_ row: Int) -> NSMenu? {
            guard rows.indices.contains(row) else { return nil }
            switch rows[row] {
            case .track(let item): return AppContextMenuFactory.shared.buildSongNSMenu(song: item.track, player: parent.player, router: parent.router, core: parent.player.rustCore, origin: .recommendations)
            default: return nil
            }
        }
        private func artistMenu(_ card: BrowseCardRecord) -> NSMenu? {
            AppContextMenuFactory.shared.buildArtistNSMenu(channelId: card.id, name: card.title, thumbnail: card.thumbnail,
                radioPlaylistId: nil, origin: .recommendations, player: parent.player, router: parent.router, core: parent.player.rustCore)
        }
        @objc func scrolled() {
            guard !applying, let scroll else { return }
            (scroll as? NativeSidebarScrollView)?.layoutHeroLayers()
            let offset = max(0, scroll.contentView.bounds.minY)
            parent.state.evaluateScroll(offsetY: offset, hasTrack: parent.currentVideoID != nil, recommendationKey: parent.requestKey, upperHeight: parent.heroHeight) { [weak self] in
                guard let self, let track = self.parent.player.currentTrack else { return }
                self.parent.player.fetchRecommendations(for: track)
            }
            if !activated && offset >= SidebarRecommendationScrollPolicy.activationOffset { update(parent) }
        }
    }
}

private final class SidebarPassiveVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class SidebarPassiveView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class SidebarHeroSpacerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Fixed metadata and one viewport-sized material sit below the transparent table.
/// Only the material's boundary moves; no hosting root is rebuilt while scrolling.
final class NativeSidebarScrollView: NSScrollView {
    override var isFlipped: Bool { true }

    private(set) var heroMetadata: NSHostingView<SidebarArtworkMetadataHost>?
    private let feedMaterial = SidebarPassiveVisualEffectView()
    private let feedTint = SidebarPassiveView()
    private var heroHeight: CGFloat = 0
    /// Accessibility display options change rarely; reading them on every scroll tick is wasted work.
    private var opaqueSurfaces = false
    private var appliedOpaqueSurfaces: Bool?
    private var appliedMetadataHidden: Bool?
    var feedTop: CGFloat { max(0, heroHeight - max(0, contentView.bounds.minY)) }

    private func refreshAccessibilityOptions() {
        let workspace = NSWorkspace.shared
        opaqueSurfaces = workspace.accessibilityDisplayShouldReduceTransparency || workspace.accessibilityDisplayShouldIncreaseContrast
    }

    func installHero(player: PlayerViewModel, router: NavigationRouter?, state: SidebarArtworkScrollState, height: CGFloat) {
        heroHeight = height
        wantsLayer = true
        contentView.wantsLayer = true
        documentView?.wantsLayer = true
        refreshAccessibilityOptions()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityOptionsChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        let host = SidebarFixedMetadataHostingView(rootView: SidebarArtworkMetadataHost(viewModel: player, router: router, state: state, height: height))
        host.scrollOwner = self
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.wantsLayer = true
        heroMetadata = host
        addSubview(host, positioned: .below, relativeTo: contentView)
        // A single compositor material covers the paused hero; no software blur or frame capture.
        // The subtle dark tint supplies local readability over any artwork palette while preserving blur.
        feedMaterial.material = .fullScreenUI
        feedMaterial.blendingMode = .withinWindow
        feedMaterial.state = .active
        feedMaterial.appearance = NSAppearance(named: .darkAqua)
        feedMaterial.wantsLayer = true
        addSubview(feedMaterial, positioned: .above, relativeTo: host)
        feedTint.wantsLayer = true
        feedMaterial.addSubview(feedTint)
        if let clipLayer = contentView.layer, let feedLayer = feedMaterial.layer {
            layer?.insertSublayer(feedLayer, below: clipLayer)
            if let hostLayer = host.layer {
                layer?.insertSublayer(hostLayer, below: feedLayer)
            }
            feedLayer.zPosition = 0
            clipLayer.zPosition = 1
            host.layer?.zPosition = -1
        }
    }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    @objc private func accessibilityOptionsChanged() {
        refreshAccessibilityOptions()
        layoutHeroLayers()
    }

    func updateHero(player: PlayerViewModel, router: NavigationRouter?, state: SidebarArtworkScrollState, height: CGFloat) {
        guard let host = heroMetadata else { return }
        let previous = host.rootView
        if previous.viewModel !== player || previous.router !== router || previous.state !== state || heroHeight != height {
            host.rootView = SidebarArtworkMetadataHost(viewModel: player, router: router, state: state, height: height)
        }
        heroHeight = height
    }

    func layoutHeroLayers() {
        let viewport = contentView.frame
        heroMetadata?.frame = viewport
        let coveredHeight = max(0, viewport.height - feedTop)
        feedMaterial.frame = NSRect(x: viewport.minX, y: isFlipped ? viewport.minY + feedTop : viewport.minY,
                                    width: viewport.width, height: coveredHeight)
        feedTint.frame = feedMaterial.bounds
        if appliedOpaqueSurfaces != opaqueSurfaces {
            appliedOpaqueSurfaces = opaqueSurfaces
            feedMaterial.state = opaqueSurfaces ? .inactive : .active
            feedTint.layer?.backgroundColor = NSColor(calibratedWhite: 0.055, alpha: opaqueSurfaces ? 1 : 0.28).cgColor
        }
        let metadataCovered = feedTop <= 0
        if heroMetadata?.isHidden != metadataCovered { heroMetadata?.isHidden = metadataCovered }
        if let host = heroMetadata {
            let geometry = SidebarArtworkLayout(width: viewport.width, height: heroHeight, portrait: host.rootView.state.isPortrait)
            let accessibilityHidden = feedTop < geometry.metadataTop + PlaybackSidebarLayout.metadataHeight
            if appliedMetadataHidden != accessibilityHidden {
                appliedMetadataHidden = accessibilityHidden
                host.setAccessibilityHidden(accessibilityHidden)
            }
        }
        // Force layer composition order so the frosted blur sits strictly BEHIND the table items:
        // Layer 0 (bottom): heroMetadata.layer
        // Layer 1 (middle): feedMaterial.layer (blur)
        // Layer 2 (top): contentView.layer (table with recommendations)
        if let clipLayer = contentView.layer, let feedLayer = feedMaterial.layer {
            if feedLayer.superlayer !== layer || clipLayer.superlayer !== layer {
                layer?.insertSublayer(feedLayer, below: clipLayer)
                if let hostLayer = heroMetadata?.layer {
                    layer?.insertSublayer(hostLayer, below: feedLayer)
                }
            } else if let sublayers = layer?.sublayers,
                      let feedIdx = sublayers.firstIndex(of: feedLayer),
                      let clipIdx = sublayers.firstIndex(of: clipLayer),
                      feedIdx >= clipIdx {
                layer?.insertSublayer(feedLayer, below: clipLayer)
            }
            feedLayer.zPosition = 0
            clipLayer.zPosition = 1
            heroMetadata?.layer?.zPosition = -1
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let clipPoint = contentView.convert(local, from: self)
        let viewportY = clipPoint.y - contentView.bounds.minY
        if viewportY >= 0, viewportY < feedTop, let heroMetadata {
            let geometry = SidebarArtworkLayout(width: contentView.frame.width, height: heroHeight, portrait: heroMetadata.rootView.state.isPortrait)
            let metadataRect = NSRect(x: (contentView.frame.width - geometry.metadataWidth) / 2,
                                      y: geometry.metadataTop, width: geometry.metadataWidth,
                                      height: PlaybackSidebarLayout.metadataHeight)
            if metadataRect.contains(NSPoint(x: clipPoint.x - contentView.bounds.minX, y: viewportY)),
               let hit = heroMetadata.hitTest(local) { return hit }
        }
        return super.hitTest(point)
    }

    override func layout() {
        super.layout()
        if let table = documentView as? NSTableView {
            let width = contentSize.width
            if abs(table.frame.width - width) > 0.5 { table.setFrameSize(NSSize(width: width, height: table.frame.height)) }
        }
        layoutHeroLayers()
    }
}

private final class SidebarFixedMetadataHostingView: NSHostingView<SidebarArtworkMetadataHost> {
    weak var scrollOwner: NSScrollView?
    override func scrollWheel(with event: NSEvent) { scrollOwner?.scrollWheel(with: event) }
}

final class NativeSidebarRecommendationsTable: NSTableView {
    private var hoverTracking: NSTrackingArea?
    private var hoveredRow = -1
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTracking = area
    }
    override func mouseMoved(with event: NSEvent) { updateHoveredRow(row(at: convert(event.locationInWindow, from: nil))) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { updateHoveredRow(-1) }
    func refreshPointerHover() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        updateHoveredRow(visibleRect.contains(point) ? row(at: point) : -1)
    }
    func updateHoveredRow(_ proposed: Int) {
        let next: Int
        if let owner, owner.rows.indices.contains(proposed), case .track = owner.rows[proposed] { next = proposed }
        else { next = -1 }
        if hoveredRow >= 0, hoveredRow < numberOfRows, hoveredRow != next {
            (view(atColumn: 0, row: hoveredRow, makeIfNecessary: false) as? NativeQueueTrackCellView)?.updateHover(isHovered: false)
            (rowView(atRow: hoveredRow, makeIfNecessary: false) as? NativeTrackRowView)?.isHovered = false
        }
        hoveredRow = next
        if next >= 0 {
            (view(atColumn: 0, row: next, makeIfNecessary: false) as? NativeQueueTrackCellView)?.updateHover(isHovered: true)
            (rowView(atRow: next, makeIfNecessary: false) as? NativeTrackRowView)?.isHovered = true
        }
    }
    weak var owner: NativeSidebarRecommendationsViewport.Coordinator?
    override func menu(for event: NSEvent) -> NSMenu? { owner?.menu(row(at: convert(event.locationInWindow, from: nil))) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { owner?.perform(selectedRow) } else { super.keyDown(with: event) }
    }

}

private final class NativeSidebarTableRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}
}

private final class NativeSidebarActionCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    let button = NSButton()
    var action: (() -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        button.bezelStyle = .inline
        button.target = self
        button.action = #selector(invoke)
        for view in [label, button] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -8),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14), button.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(title: String, button titleButton: String?, enabled: Bool) {
        label.stringValue = title
        label.textColor = .white
        button.title = titleButton ?? ""
        button.isHidden = titleButton == nil
        button.isEnabled = enabled
    }
    @objc private func invoke() { action?() }
}

