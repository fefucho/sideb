import AppKit
import SwiftUI
import SideBCore

/// Per-window scroll context retained when the active playback host changes layout.
@MainActor final class PlaybackQueueViewport {
    var queueToken: UUID?
    var anchor: (String, CGFloat)?
    var historyStart: Int?
    var followsCurrent = true
}

/// Queue-only projection: visual row indices never escape to playback commands.
/// A single NSTableView recycles existing NativeQueueTrackCellView instances.
struct NativeSeparatedQueueView: NSViewRepresentable {
    let manager: QueueManager
    let revision: UInt64
    let player: PlayerViewModel
    let router: NavigationRouter?
    let liked: Set<String>
    let playing: Bool
    let loading: Bool
    let error: String?
    var viewport: PlaybackQueueViewport? = nil
    /// Set while a Spotify Jam owns the queue: the list follows the Jam order and mixes in rows
    /// that cannot be played from here.
    var jam: JamQueueContext? = nil
    private var localizationRevision = L10n.revision

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSScrollView {
        makeScrollView(coordinator: context.coordinator)
    }
    // Shared by production and geometry tests, so fixtures exercise the actual container.
    func makeScrollView(coordinator: Coordinator) -> QueueScrollView {
        let scroll = QueueScrollView()
        scroll.contentView = VerticalClipView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .allowed
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let table = QueueTable()
        table.style = .plain
        table.backgroundColor = .clear
        table.headerView = nil
        table.rowHeight = 46
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: .init("queue"))
        column.minWidth = 0
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.allowsMultipleSelection = false
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .none
        table.delegate = coordinator
        table.dataSource = coordinator
        table.owner = coordinator
        table.target = coordinator
        table.action = #selector(Coordinator.activate(_:))
        table.registerForDraggedTypes([Coordinator.dragType])
        table.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        table.autoresizingMask = [.width]
        scroll.documentView = table
        scroll.owner = coordinator
        coordinator.table = table
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.viewportChanged), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.userScrollStarted), name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        coordinator.refresh(parent: self, force: true)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.refresh(parent: self)
        (scroll as? QueueScrollView)?.fitWidth()
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        coordinator.saveViewport()
        NotificationCenter.default.removeObserver(coordinator)
    }

    enum Row: Equatable {
        case heading(String), committed(String), proposal(String), more, status(String), retry, jamPending(String)
        var isCommitted: Bool { if case .committed = self { return true }; return false }
        var identity: String {
            switch self {
            case .committed(let id): return "track:" + id
            case .proposal(let id): return "proposal:" + id
            case .heading(let key): return key
            case .status(let key): return "status:" + key
            case .more: return "more"
            case .retry: return "retry"
            case .jamPending(let id): return "jam:" + id
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        static let dragType = NSPasteboard.PasteboardType("com.fefucho.sideb.queue-entry-v3")
        var parent: NativeSeparatedQueueView
        weak var table: QueueTable?
        var rows: [Row] = []
        var committedIndices: [String:Int] = [:]
        var proposalIndices: [String:Int] = [:]
        /// Jam entries by occurrence ID (playable rows) and by entry ID (placeholders).
        var jamByOccurrence: [String: JamQueueEntry] = [:]
        var jamPlaceholders: [String: (entry: JamQueueEntry, resolving: Bool)] = [:]
        var historyStart: Int?
        var followsCurrent = true
        var positioning = false
        var positionedInitially = false
        var pendingViewportAnchor: (String, CGFloat)?
        var lastCurrentID: String?
        var lastQueueToken: UUID?
        var focusAfterMutationID: String?
        var lastRevision: UInt64?
        var lastLoading = false
        var lastError: String?
        var lastLocalization: UInt64 = 0
        init(parent: NativeSeparatedQueueView) { self.parent = parent }
        deinit { NotificationCenter.default.removeObserver(self) }

        func saveViewport() {
            guard let memory = parent.viewport, lastQueueToken == parent.manager.queueToken else { return }
            memory.queueToken = lastQueueToken
            memory.anchor = viewportAnchor()
            memory.historyStart = historyStart
            memory.followsCurrent = followsCurrent
        }

        func viewportAnchor() -> (String, CGFloat)? {
            guard let table, !rows.isEmpty else { return nil }
            let y = table.visibleRect.minY
            let range = table.rows(in: table.visibleRect)
            guard range.location != NSNotFound else { return nil }
            for index in range.location..<min(rows.count, NSMaxRange(range)) {
                switch rows[index] {
                case .committed, .proposal: return (rows[index].identity, table.rect(ofRow: index).minY - y)
                default: continue
                }
            }
            return nil
        }
        func scroll(to y: CGFloat) {
            guard let table, let scroll = table.enclosingScrollView else { return }
            let maxY = max(0, table.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(maxY, max(0, y))))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        func positionCurrent() {
            guard let table, table.visibleRect.height > 0 else { return }
            if let (identity, offset) = pendingViewportAnchor,
               let row = rows.firstIndex(where: { $0.identity == identity }) {
                scroll(to: table.rect(ofRow: row).minY - offset)
                pendingViewportAnchor = nil
                positionedInitially = true
                return
            }
            pendingViewportAnchor = nil
            guard let id = parent.manager.currentOccurrenceID,
                  let row = rows.firstIndex(of: .committed(id)) else { return }
            scroll(to: table.rect(ofRow: max(0, row - 2)).minY)
            positionedInitially = true
        }
        @objc func viewportChanged() {
            if !positioning { saveViewport() }
            guard !positioning, positionedInitially, !followsCurrent,
                  let table, table.visibleRect.minY < 90, let start = historyStart, start > 0 else { return }
            historyStart = max(0, start - 100)
            refresh(parent: parent, force: true)
        }
        @objc func userScrollStarted() { followsCurrent = false }

        func refresh(parent next: NativeSeparatedQueueView, force: Bool = false) {
            let old = parent
            parent = next
            let changed = force || lastRevision != next.revision || lastLoading != next.loading || lastError != next.error || old.localizationRevision != next.localizationRevision || old.jam != next.jam
            guard let table else { return }
            if changed {
                let newSession = lastQueueToken != next.manager.queueToken
                let restoring = newSession && next.viewport?.queueToken == next.manager.queueToken
                let anchor = restoring ? next.viewport?.anchor : (newSession ? nil : viewportAnchor())
                let focus = focusAfterMutationID
                let selected = focus ?? (rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].identity : nil)
                let currentChanged = lastCurrentID != next.manager.currentOccurrenceID
                if newSession {
                    historyStart = restoring ? next.viewport?.historyStart : nil
                    followsCurrent = restoring ? next.viewport?.followsCurrent ?? true : true
                    pendingViewportAnchor = restoring && !followsCurrent ? anchor : nil
                    positionedInitially = false
                }
                focusAfterMutationID = nil
                positioning = true
                defer { positioning = false }
                buildRows()
                lastRevision = next.revision; lastLoading = next.loading; lastError = next.error
                lastQueueToken = next.manager.queueToken; lastCurrentID = next.manager.currentOccurrenceID
                table.reloadData()
                table.layoutSubtreeIfNeeded()
                if let selected, let index = rows.firstIndex(where: { $0.identity == selected }) {
                    table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                    if focus != nil { followsCurrent = false; table.scrollRowToVisible(index) }
                } else { table.deselectAll(nil) }
                if focus == nil {
                    if !positionedInitially || (followsCurrent && currentChanged) { positionCurrent() }
                    else if let (id, offset) = anchor, let row = rows.firstIndex(where: { $0.identity == id }) {
                        scroll(to: table.rect(ofRow: row).minY - offset)
                    }
                }
            } else if old.playing != next.playing || old.liked != next.liked {
                table.enumerateAvailableRowViews { [weak self] row, index in
                    guard let self else { return }
                    if let cell = row.view(atColumn: 0) as? NativeQueueTrackCellView { self.configure(cell, row: index) }
                }
            }
        }
        /// Jam order with placeholders for tracks that have no playable row. No recommendations,
        /// no "more" rows: the Jam owns the whole queue and Side B's own radio is off.
        func buildJamRows(_ jam: JamQueueContext) {
            let q = parent.manager
            func add(_ index: Int) {
                guard q.queue.indices.contains(index), q.occurrenceIDs.indices.contains(index) else { return }
                let id = q.occurrenceIDs[index]; committedIndices[id] = index; rows.append(.committed(id))
            }
            if !q.queue.isEmpty || !jam.entries.isEmpty { rows.append(.heading("queue.now")) }
            if q.currentTrack != nil { add(q.currentIndex) }
            let first = q.currentIndex + 1
            let last = min(q.queue.count, q.occurrenceIDs.count, first + 200)
            let upcoming = first < last
                ? (first..<last).map { JamQueueMerge.Occurrence(id: q.occurrenceIDs[$0], videoID: q.queue[$0].videoId) } : []
            let entries = jam.entries.prefix(200)
            let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { kept, _ in kept })
            for item in JamQueueMerge.merge(entries: entries.map(JamQueueMerge.Entry.init), upcoming: upcoming) {
                switch item {
                case .occurrence(let id, let entry):
                    guard let index = q.occurrenceIndex(id: id) else { continue }
                    committedIndices[id] = index; rows.append(.committed(id))
                    if let entry, let full = byID[entry.id] { jamByOccurrence[id] = full }
                case .placeholder(let entry, let resolving):
                    guard let full = byID[entry.id] else { continue }
                    jamPlaceholders[entry.id] = (full, resolving); rows.append(.jamPending(entry.id))
                }
            }
        }
        func buildRows() {
            let q = parent.manager
            rows = []; committedIndices = [:]; proposalIndices = [:]
            jamByOccurrence = [:]; jamPlaceholders = [:]
            if let jam = parent.jam { buildJamRows(jam); return }
            func add(_ index: Int) {
                guard q.queue.indices.contains(index), q.occurrenceIDs.indices.contains(index) else { return }
                let id = q.occurrenceIDs[index]; committedIndices[id] = index; rows.append(.committed(id))
            }
            if !q.queue.isEmpty { rows.append(.heading("queue.now")) }
            let current = min(q.currentIndex, q.queue.count)
            if historyStart == nil { historyStart = max(0, current - 100) }
            if followsCurrent { historyStart = max(historyStart ?? 0, current - 100) }
            historyStart = min(historyStart ?? 0, current)
            for index in (historyStart ?? 0)..<current { add(index) }
            if q.currentTrack != nil { add(q.currentIndex) }
            var pending = q.visiblePendingIndices
            pending = pending.filter { $0 > q.currentIndex }
            var last = q.currentIndex
            for index in pending {
                if index > last + 1 { rows.append(.more) }
                add(index); last = index
            }
            if last + 1 < q.queue.count { rows.append(.more) }
            let hasRecommendations = !q.recommendationEntries.isEmpty
            if hasRecommendations || parent.loading || parent.error != nil {
                rows.append(.heading("queue.recommendations"))
            }
            if q.isRepeat && hasRecommendations { rows.append(.status("queue.repeatNote")) }
            // Reserve admission is bounded independently of the source catalog.
            for (index, entry) in q.recommendationEntries.prefix(25).enumerated() {
                proposalIndices[entry.id] = index; rows.append(.proposal(entry.id))
            }
            if parent.loading { rows.append(.status("common.loading")) }
            else if parent.error != nil { rows.append(.retry) }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard rows.indices.contains(row) else { return 46 }
            switch rows[row] { case .committed, .proposal, .jamPending: return 46; case .status: return 32; default: return 36 }
        }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard rows.indices.contains(row) else { return nil }
            switch rows[row] {
            case .heading, .status, .jamPending:
                let identifier = NSUserInterfaceItemIdentifier("SeparatedQueueNoninteractiveRow")
                let view = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableRowView ?? NSTableRowView()
                view.identifier = identifier
                return view
            default: break
            }
            let identifier = NSUserInterfaceItemIdentifier("SeparatedQueueRow")
            let view = (tableView.makeView(withIdentifier: identifier, owner: self) as? NativeTrackRowView) ?? NativeTrackRowView()
            view.identifier = identifier
            view.isHovered = false
            view.drawsHoverBackground = parent.jam == nil
            if rows.indices.contains(row), case .committed(let id) = rows[row] {
                view.isCurrentTrack = id == parent.manager.currentOccurrenceID
            } else { view.isCurrentTrack = false }
            return view
        }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard rows.indices.contains(row) else { return false }
            switch rows[row] { case .heading, .status, .jamPending: return false; default: followsCurrent = false; return true }
        }
        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            guard rows.indices.contains(row) else { return false }
            if case .heading = rows[row] { return true }; return false
        }
        func track(at row: Int) -> SongItemRecord? {
            guard rows.indices.contains(row) else { return nil }
            switch rows[row] {
            case .committed(let id):
                guard let index = committedIndices[id], parent.manager.queue.indices.contains(index), parent.manager.occurrenceIDs[index] == id else { return nil }
                return parent.manager.queue[index]
            case .proposal(let id):
                guard let index = proposalIndices[id], parent.manager.recommendationEntries.indices.contains(index), parent.manager.recommendationEntries[index].id == id else { return nil }
                return parent.manager.recommendationEntries[index].track
            default: return nil
            }
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            if track(at: row) != nil {
                let identifier = NSUserInterfaceItemIdentifier("SeparatedQueueTrack")
                let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NativeQueueTrackCellView) ?? NativeQueueTrackCellView()
                cell.identifier = identifier
                configure(cell, row: row)
                return cell
            }
            if case .jamPending(let id) = rows[row], let placeholder = jamPlaceholders[id] {
                let identifier = NSUserInterfaceItemIdentifier("SeparatedQueueJamPlaceholder")
                let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? JamPlaceholderCellView) ?? JamPlaceholderCellView()
                cell.identifier = identifier
                cell.configure(entry: placeholder.entry, resolving: placeholder.resolving)
                return cell
            }
            let identifier = NSUserInterfaceItemIdentifier("SeparatedQueueLabel")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? QueueLabelCell) ?? QueueLabelCell()
            cell.identifier = identifier
            let text: String
            switch rows[row] {
            case .heading(let key):
                text = L10n.text(key)
            case .status(let key): text = L10n.text(key)
            case .more: text = "↓ " + L10n.text("queue.moreSource")
            case .retry: text = (parent.error ?? "") + " · " + L10n.text("queue.retryRecommendations")
            default: text = ""
            }
            cell.label.stringValue = text
            if case .heading = rows[row] { cell.label.font = .systemFont(ofSize: 12, weight: .semibold) }
            else { cell.label.font = .systemFont(ofSize: 12) }
            cell.separator.isHidden = rows[row] != .heading("queue.recommendations")
            cell.setAccessibilityLabel(text)
            return cell
        }
        func configure(_ cell: NativeQueueTrackCellView, row: Int) {
            guard let song = track(at: row) else { return }
            let item = rows[row], q = parent.manager
            let active: Bool
            if case .committed(let id) = item { active = parent.player.currentTrack != nil && id == q.currentOccurrenceID } else { active = false }
            let index: Int
            if case .committed(let id) = item {
                // In a Jam the rows are numbered in Jam order, so unavailable tracks leave no gap.
                index = jamByOccurrence[id].map { JamQueueMerge.displayNumber(forEntryIndex: $0.index) - 1 } ?? committedIndices[id] ?? 0
            } else { index = proposalIndices[item.identity.replacingOccurrences(of: "proposal:", with: "")] ?? 0 }
            let reorderable: Bool
            if case .committed = item { reorderable = true } else { reorderable = false }
            cell.configure(track: song, index: index, isCurrentTrack: active, isPlaying: active && parent.playing,
                           isLiked: parent.liked.contains(song.videoId), hideAlbum: true, showAlbumInSubtitle: true,
                           isReorderable: reorderable, rowHeight: 46)
            cell.setPreviousAppearance(item.isCommitted && index < q.currentIndex)
            if case .committed(let id) = item { cell.setJamMarker(jamByOccurrence[id].map(JamRowMarker.init)) }
            cell.updatePlaybackDuration(active && parent.player.duration > 0 ? parent.player.formattedDuration : nil)
            cell.onArtistDestination = { [weak self] id, name in
                self?.parent.router?.navigate(to: id.map { .artist(browseId: $0) } ?? .search(query: name))
            }
            let token = q.queueToken, session = q.recommendationSessionID
            if case .proposal(let id) = item {
                cell.setAddToQueueAction { [weak self] in
                    self?.enqueueProposal(id: id, next: false, token: token, session: session)
                }
            }
            cell.onLike = { [weak self] track in
                guard let self, self.parent.manager.queueToken == token else { return }
                self.parent.player.toggleTrackLike(track)
            }
            cell.onDislike = { [weak self] track in
                guard let self, self.parent.manager.queueToken == token else { return }
                switch item {
                case .committed(let id): self.parent.player.dislikeTrack(track, occurrenceID: id)
                case .proposal(let id):
                    guard self.parent.manager.recommendationSessionID == session else { return }
                    self.parent.player.dislikeTrack(track, recommendationID: id)
                default: break
                }
            }
            let hovered = (table?.rowView(atRow: row, makeIfNecessary: false) as? NativeTrackRowView)?.isHovered ?? false
            cell.updateHover(isHovered: hovered)
        }
        @objc func activate(_ sender: NSTableView) {
            let row = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
            perform(row)
        }
        func perform(_ row: Int) {
            guard rows.indices.contains(row) else { return }
            switch rows[row] {
            case .committed(let id): if let index = parent.manager.occurrenceIndex(id: id) { parent.player.playQueueIndex(index) }
            case .proposal(let id):
                parent.player.playQueueRecommendation(id: id, sessionID: parent.manager.recommendationSessionID)
                if let selected = parent.manager.currentOccurrenceID { focusAfterMutationID = "track:" + selected }
            case .more: parent.manager.revealMorePendingTracks()
            case .retry: parent.player.retryQueueRecommendations()
            default: break
            }
        }
        func menu(row: Int) -> NSMenu? {
            guard let song = track(at: row) else { return nil }
            let item = rows[row], q = parent.manager, token = q.queueToken, session = q.recommendationSessionID
            let index: Int
            if case .committed(let id) = item { index = q.occurrenceIndex(id: id) ?? -1 } else { index = -1 }
            let origin: MenuOrigin
            if case .proposal(let id) = item { origin = .queueRecommendation(id: id, sessionID: session) }
            else { origin = .queue(occurrenceIndex: index) }
            let menu = AppContextMenuFactory.shared.buildSongNSMenu(song: song, player: parent.player, router: parent.router,
                core: parent.player.rustCore, origin: origin, actionInterceptor: { [weak self] action in
                    guard let self else { return true }
                    let manager = self.parent.manager
                    guard manager.queueToken == token else { return true }
                    switch item {
                    case .proposal(let id):
                        guard manager.recommendationSessionID == session else { return true }
                        switch action {
                        case .play:
                            self.parent.player.playQueueRecommendation(id: id, sessionID: session)
                            self.focusAfterMutationID = manager.currentOccurrenceID.map { "track:" + $0 }; return true
                        case .playNext:
                            self.enqueueProposal(id: id, next: true, token: token, session: session); return true
                        case .addToQueue:
                            self.enqueueProposal(id: id, next: false, token: token, session: session); return true
                        case .removeFromQueue: manager.removeRecommendation(id: id); return true
                        default: return false
                        }
                    case .committed(let id):
                        guard let index = manager.occurrenceIndex(id: id) else { return true }
                        switch action {
                        case .play: self.parent.player.playQueueIndex(index); return true
                        case .removeFromQueue: self.parent.player.removeQueueTrack(at: index); return true
                        default: return false
                        }
                    default: return false
                    }
                })
            if case .committed(let id) = item, let source = q.occurrenceIndex(id: id), source > q.currentIndex {
                menu.addItem(.separator())
                for (key, end) in [("queue.moveNext", false), ("queue.moveEnd", true)] {
                    let relay = MenuRelay { [weak self] in
                        guard let self, self.parent.manager.queueToken == token,
                              let source = self.parent.manager.occurrenceIndex(id: id), source > self.parent.manager.currentIndex else { return }
                        let target = end ? self.parent.manager.queue.count - 1 : self.parent.manager.currentIndex + 1
                        self.focusAfterMutationID = "track:" + id
                        self.parent.manager.moveTrack(from: source, to: target)
                    }
                    let entry = NSMenuItem(title: L10n.text(key), action: #selector(MenuRelay.run(_:)), keyEquivalent: "")
                    entry.target = relay; entry.representedObject = relay; menu.addItem(entry)
                }
            }
            return menu
        }
        func enqueueProposal(id: String, next: Bool, token: UUID, session: UUID) {
            let q = parent.manager
            guard q.queueToken == token, q.recommendationSessionID == session,
                  q.recommendationEntries.contains(where: { $0.id == id }) else { return }
            let idle = parent.player.currentTrack == nil
            parent.player.enqueueQueueRecommendation(id: id, sessionID: session, next: next)
            let index = idle ? q.currentIndex : (next ? q.currentIndex + 1 : q.queue.count - 1)
            if q.occurrenceIDs.indices.contains(index) { focusAfterMutationID = "track:" + q.occurrenceIDs[index] }
        }
        func reorderSelected(row: Int, delta: Int) {
            guard rows.indices.contains(row), case .committed(let id) = rows[row],
                  let source = parent.manager.occurrenceIndex(id: id) else { return }
            if source <= parent.manager.currentIndex {
                guard delta > 0 else { return }
                let q = parent.manager
                let before = q.occurrenceIDs.indices.contains(q.currentIndex + 1) ? q.occurrenceIDs[q.currentIndex + 1] : nil
                focusAfterMutationID = q.placeQueueOccurrence(id: id, beforeID: before).map { "track:" + $0 }
                return
            }
            let target = source + delta
            guard target > parent.manager.currentIndex, target < parent.manager.queue.count else { return }
            focusAfterMutationID = "track:" + id
            parent.manager.moveTrack(from: source, to: target)
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard rows.indices.contains(row) else { return nil }
            let kind: String, id: String
            switch rows[row] {
            case .committed(let value):
                kind = "chosen"; id = value
            case .proposal(let value): kind = "proposal"; id = value
            default: return nil
            }
            let payload = ["token":parent.manager.queueToken.uuidString,"session":parent.manager.recommendationSessionID.uuidString,"kind":kind,"id":id]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            let item = NSPasteboardItem(); item.setData(data, forType: Self.dragType); return item
        }
        /// A drop "above" a Jam placeholder lands after it: placeholders are not drop targets.
        func resolvedDropRow(_ row: Int) -> Int {
            var row = row
            while rows.indices.contains(row), case .jamPending = rows[row] { row += 1 }
            return row
        }
        func destination(_ row: Int) -> Int? {
            guard row >= 0 else { return nil }
            let row = resolvedDropRow(row)
            if row == rows.count { return parent.manager.queue.count }
            if row > rows.count { return nil }
            switch rows[row] {
            case .committed(let id): guard let index = committedIndices[id], index > parent.manager.currentIndex else { return nil }; return index
            case .heading("queue.recommendations"), .more: return parent.manager.queue.count
            default: return nil
            }
        }
        func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            guard destination(row) != nil else { return [] }
            tableView.setDropRow(resolvedDropRow(row), dropOperation: .above)
            if let data = info.draggingPasteboard.data(forType: Self.dragType),
               let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String:String],
               payload["kind"] == "chosen", let id = payload["id"],
               let source = parent.manager.occurrenceIndex(id: id), source <= parent.manager.currentIndex { return .copy }
            return .move
        }
        func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            guard let target = destination(row), let data = info.draggingPasteboard.data(forType: Self.dragType),
                  let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String:String],
                  payload["token"] == parent.manager.queueToken.uuidString,
                  payload["session"] == parent.manager.recommendationSessionID.uuidString,
                  let id = payload["id"] else { return false }
            let q = parent.manager
            if payload["kind"] == "proposal" {
                guard q.recommendationEntries.contains(where: { $0.id == id }) else { return false }
                parent.player.enqueueQueueRecommendation(id: id, sessionID: q.recommendationSessionID, next: false)
                if target < q.queue.count - 1 { q.moveTrack(from: q.queue.count - 1, to: target) }
            } else if payload["kind"] == "chosen" {
                let before = q.occurrenceIDs.indices.contains(target) ? q.occurrenceIDs[target] : nil
                guard let placed = q.placeQueueOccurrence(id: id, beforeID: before) else { return false }
                focusAfterMutationID = "track:" + placed
            } else { return false }
            return true
        }
    }

    final class MenuRelay: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func run(_ sender: Any?) { action() }
    }
    final class QueueLabelCell: NSTableCellView {
        let label = NSTextField(labelWithString: "")
        let separator = NSBox()
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect); label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false; addSubview(label)
            separator.boxType = .separator; separator.translatesAutoresizingMaskIntoConstraints = false; addSubview(separator)
            NSLayoutConstraint.activate([separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), separator.topAnchor.constraint(equalTo: topAnchor)])
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),label.centerYAnchor.constraint(equalTo: centerYAnchor)])
            label.lineBreakMode = .byTruncatingTail
        }
        required init?(coder: NSCoder) { fatalError() }
    }
    final class VerticalClipView: NSClipView {
        override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
            var bounds = super.constrainBoundsRect(proposedBounds)
            bounds.origin.x = 0
            return bounds
        }
    }
    final class QueueScrollView: NSScrollView {
        weak var owner: Coordinator?
        private var fitting = false
        func fitWidth() {
            guard !fitting, let table = documentView as? NSTableView, let column = table.tableColumns.first else { return }
            fitting = true
            defer { fitting = false }
            let width = max(1, contentView.bounds.width)
            if abs(column.width - width) > 0.5 { column.width = width }
            if abs(table.frame.width - width) > 0.5 { table.setFrameSize(NSSize(width: width, height: table.frame.height)) }
        }
        override func layout() {
            super.layout()
            fitWidth()
            if let owner, !owner.positionedInitially, !owner.positioning, contentView.bounds.height > 0 {
                owner.positioning = true
                owner.positionCurrent()
                owner.positioning = false
            }
        }
        override func scrollWheel(with event: NSEvent) {
            owner?.followsCurrent = false
            super.scrollWheel(with: event)
        }
    }
    final class QueueTable: NSTableView {
        weak var owner: Coordinator?
        private var hoverArea: NSTrackingArea?
        private var hoveredRow = -1
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
            addTrackingArea(area); hoverArea = area
        }
        override func mouseMoved(with event: NSEvent) {
            let next = row(at: convert(event.locationInWindow, from: nil))
            guard next != hoveredRow else { return }
            for row in [hoveredRow, next] where row >= 0 {
                (view(atColumn: 0, row: row, makeIfNecessary: false) as? NativeQueueTrackCellView)?.updateHover(isHovered: row == next)
                (rowView(atRow: row, makeIfNecessary: false) as? NativeTrackRowView)?.isHovered = row == next
            }
            hoveredRow = next
        }
        override func mouseExited(with event: NSEvent) {
            if hoveredRow >= 0 {
                (view(atColumn: 0, row: hoveredRow, makeIfNecessary: false) as? NativeQueueTrackCellView)?.updateHover(isHovered: false)
                (rowView(atRow: hoveredRow, makeIfNecessary: false) as? NativeTrackRowView)?.isHovered = false
            }
            hoveredRow = -1
        }
        override func menu(for event: NSEvent) -> NSMenu? { owner?.menu(row: row(at: convert(event.locationInWindow, from: nil))) }
        override func keyDown(with event: NSEvent) {
            owner?.followsCurrent = false
            if event.modifierFlags.contains(.option), event.keyCode == 125 || event.keyCode == 126 {
                owner?.reorderSelected(row: selectedRow, delta: event.keyCode == 125 ? 1 : -1); return
            }
            if (event.keyCode == 109 && event.modifierFlags.contains(.shift)) || (event.keyCode == 36 && event.modifierFlags.contains(.control)), let menu = owner?.menu(row: selectedRow) {
                menu.popUp(positioning: nil, at: NSPoint(x: 12, y: rect(ofRow: selectedRow).midY), in: self); return
            }
            if event.keyCode == 36 || event.keyCode == 49 { owner?.perform(selectedRow); return }
            super.keyDown(with: event)
        }
    }
}
