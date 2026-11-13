import AppKit
import SwiftUI
import SideBCore

/// Uses the same collection items, image cache, focus controls and menus as the feed.
/// Dos modos: el mosaico de canciones y la fila de tarjetas grandes de colecciones.
struct HomeFeaturedNativeRail: NSViewRepresentable {
    var records: [HomeItemRecord]
    /// Modo mosaico (canciones): disposición de `HomeMosaicLayout` sobre los IDs de `records`.
    /// Sin él, fila de tarjetas de colección cuyo tamaño sale del ancho del carril (`HomeCollectionRowLayout`).
    var usesMosaic = false
    /// Márgenes dentro del contenido desplazable (el carril llega a sangre).
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0
    /// Acabado del panel de las tarjetas de colección.
    var albumCardStyle: HomeAlbumCardStyle = .tinted
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
    /// Recorte lateral de la fila de colecciones (`clip-path: inset(0 5px)` de Windows): como la separación (24)
    /// es menor que el margen (28), en reposo asomarían 4 pt de la tarjeta vecina.
    static let edgeClip: CGFloat = 5

    let collection = HomeNativeCollectionView()
    private let scroll = HomeFeaturedScrollView()
    private let flow = NSCollectionViewFlowLayout()
    private let mosaicLayout = HomeMosaicCollectionLayout()
    private var mosaicIDs: [String]?
    /// Posición horizontal retenida del mosaico; sólo se actualiza con una medida real.
    private(set) var retainedOffset: CGFloat = 0
    /// Índice de la tarjeta alineada a la izquierda en la fila de colecciones; sólo lo mueve una medida real.
    private(set) var anchorIndex = 0
    /// El ancla sólo sigue al scroll cuando lo origina el usuario (gesto, rueda o flechas). Sin esto, un
    /// desplazamiento de AppKit al poblar o medir el carril por primera vez (arranque de la app) se leía como
    /// una medida real y la fila quedaba corrida a la derecha.
    private var userMovedRail = false
    private var isApplying = false
    private(set) var isStopped = false
    private var model: HomeFeaturedNativeRail?
    /// Últimas visibles publicadas; `nil` hasta la primera publicación.
    private var published: [String]?
    private var pendingAnchorID: String?
    private var suspended = Set<ObjectIdentifier>()
    private var observedClips = Set<ObjectIdentifier>()
    private var pageIsActive = true
    private(set) var visibilityUpdateCount = 0
    private let previous = NSButton()
    private let next = NSButton()
    private(set) var reloadCount = 0
    private(set) var configuredCount = 0
    private var isSnapping = false
    /// Hubo un layout con ancho ≤ 0 (Inicio tapado): al volver a medirse hay que reubicar la fila sobre su ancla.
    private var measuredWhileHidden = false
    /// Preferencia del sistema «Reducir movimiento»; se inyecta en pruebas.
    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        flow.scrollDirection = .horizontal
        flow.minimumLineSpacing = HomeCollectionRowLayout.gap
        flow.minimumInteritemSpacing = HomeCollectionRowLayout.gap
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
        scroll.horizontalScrollElasticity = .allowed
        addSubview(scroll)
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
        scroll.onUserScroll = { [weak self] in self?.userMovedRail = true }
        NotificationCenter.default.addObserver(self, selector: #selector(liveScrollBegan),
                                               name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        NotificationCenter.default.addObserver(self, selector: #selector(liveScrollEnded),
                                               name: NSScrollView.didEndLiveScrollNotification, object: scroll)
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

    // MARK: Aplicar el modelo

    func apply(_ next: HomeFeaturedNativeRail, active: Bool = true) {
        // Un carril desmontado no vuelve a actuar.
        guard !isStopped else { return }
        let wasActive = pageIsActive
        pageIsActive = active
        let changed = model?.records != next.records || model?.session != next.session
        // A resize only changes item geometry, which the layout applies by itself.
        // Reconfiguring every visible cell on each frame is what made resizing stutter.
        let sameContent = !changed && wasActive == active && model.map {
            $0.playing == next.playing && $0.loadingID == next.loadingID && $0.playback == next.playback
                && $0.revision == next.revision && $0.usesMosaic == next.usesMosaic
                && $0.albumCardStyle == next.albumCardStyle
        } == true
        let reset = model?.session != next.session
        isApplying = true
        defer { isApplying = false }
        var listChanged = false
        if next.usesMosaic {
            if collection.collectionViewLayout !== mosaicLayout { collection.collectionViewLayout = mosaicLayout; mosaicIDs = nil }
            // La disposición sólo se recalcula cuando cambia la lista de IDs.
            if changed || mosaicIDs == nil {
                let ids = next.records.map(\.id)
                if ids != mosaicIDs {
                    mosaicIDs = ids
                    mosaicLayout.update(mosaic: HomeMosaicLayout.make(ids: ids),
                                        leadingInset: next.leadingInset, trailingInset: next.trailingInset)
                    listChanged = true
                }
            }
            mosaicLayout.update(mosaic: mosaicLayout.mosaic, leadingInset: next.leadingInset, trailingInset: next.trailingInset)
        } else {
            if collection.collectionViewLayout !== flow { collection.collectionViewLayout = flow }
            if changed, !reset, let old = model, !old.usesMosaic, old.records.indices.contains(anchorIndex) {
                // Al cambiar la lista la fila sigue a la misma tarjeta por ID (como `alignCollectionAnchor`).
                pendingAnchorID = "\(old.records[anchorIndex].kind):\(old.records[anchorIndex].id)"
            } else if reset { pendingAnchorID = nil; anchorIndex = 0 }
        }
        model = next
        previous.setAccessibilityLabel(L10n.text("home.shelf.previous"))
        self.next.setAccessibilityLabel(L10n.text("home.shelf.next"))
        if reset {
            for item in collection.visibleItems() { (item as? HomeCollectionItem)?.content.prepareForReuse() }
            scroll.contentView.scroll(to: .zero)
        }
        if next.usesMosaic, reset || listChanged {
            // Lista o sesión distinta: vuelve al inicio. La misma lista conserva su posición.
            retainedOffset = 0
            scroll.contentView.scroll(to: .zero)
        }
        if changed { suspended.removeAll(); reloadCount += 1; collection.reloadData() }
        if next.usesMosaic { restoreOffset() }
        if !sameContent {
            for path in collection.indexPathsForVisibleItems() {
                if let cell = collection.item(at: path) as? HomeCollectionItem, active, !suspended.contains(ObjectIdentifier(cell)) { configure(cell, index: path.item) }
            }
        }
        isApplying = false
        moved()
        needsLayout = true
    }

    /// Devuelve el desplazamiento retenido (acotado al contenido) cuando AppKit lo movió.
    private func restoreOffset() {
        let viewport = scroll.contentSize.width
        guard viewport > 0 else { return }
        let maximum = max(0, mosaicLayout.collectionViewContentSize.width - viewport)
        scrollTo(min(max(0, retainedOffset), maximum))
    }

    /// Mueve el contenido sin que cuente como una acción del usuario.
    private func scrollTo(_ x: CGFloat) {
        let clip = scroll.contentView
        guard abs(clip.bounds.minX - x) > 0.5 else { return }
        let wasApplying = isApplying
        isApplying = true
        clip.scroll(to: NSPoint(x: x, y: 0))
        scroll.reflectScrolledClipView(clip)
        isApplying = wasApplying
    }

    // MARK: Geometría

    override func layout() {
        super.layout()
        guard !isStopped else { return }
        observeScrollAncestors()
        guard let model else { return }
        if model.usesMosaic { layoutMosaic(); return }
        layoutCollections(model)
    }

    private func layoutArrows(centerY: CGFloat? = nil) {
        let y = (centerY ?? bounds.height / 2) - 16
        previous.frame = NSRect(x: 4, y: y, width: 32, height: 32)
        next.frame = NSRect(x: max(0, bounds.width - 36), y: y, width: 32, height: 32)
    }

    private var cardStride: CGFloat { flow.itemSize.width + HomeCollectionRowLayout.gap }
    private var collectionsMaximumOffset: CGFloat { max(0, flow.collectionViewContentSize.width - scroll.contentSize.width) }

    /// Fila de colecciones: el tamaño de ítem sale del ancho del carril. Resizear sólo cambia el tamaño de ítem del
    /// layout y reubica la fila sobre su ancla; no reconfigura celdas ni vuelve a pedir imágenes.
    private func layoutCollections(_ model: HomeFeaturedNativeRail) {
        // Inicio tapado u oculto: no se recalcula ni se reubica nada; se conservan la última medida real y el ancla.
        guard bounds.width > 0, bounds.height > 0 else { measuredWhileHidden = true; return }
        let leading = max(0, model.leadingInset), trailing = max(0, model.trailingInset)
        let row = HomeCollectionRowLayout(width: bounds.width, leadingInset: leading, trailingInset: trailing)
        guard row.cardWidth > 0 else { return }
        let clipLeading = leading > 0 ? Self.edgeClip : 0
        let clipTrailing = trailing > 0 ? Self.edgeClip : 0
        let frame = NSRect(x: clipLeading, y: 0, width: bounds.width - clipLeading - clipTrailing, height: bounds.height)
        let size = NSSize(width: row.cardWidth, height: HomeCollectionCardMetrics.cardHeight(cardWidth: row.cardWidth))
        // Los márgenes van dentro del contenido: la tarjeta `i` queda con desplazamiento `i · paso`.
        let insets = NSEdgeInsets(top: HomeCollectionCardMetrics.airTop, left: leading - clipLeading,
                                  bottom: HomeCollectionCardMetrics.airBottom, right: trailing - clipTrailing)
        let geometryChanged = scroll.frame != frame || flow.itemSize != size || !NSEdgeInsetsEqual(flow.sectionInset, insets)
        isApplying = true
        defer { isApplying = false }
        if geometryChanged {
            scroll.frame = frame
            flow.itemSize = size
            flow.sectionInset = insets
            flow.invalidateLayout()
            collection.layoutSubtreeIfNeeded()
        }
        if let pendingAnchorID {
            self.pendingAnchorID = nil
            collection.layoutSubtreeIfNeeded()
            anchorIndex = model.records.firstIndex(where: { "\($0.kind):\($0.id)" == pendingAnchorID }) ?? 0
            restoreAnchorOffset()
        } else if geometryChanged || measuredWhileHidden {
            // Al volver de un ancho ≤ 0 AppKit pudo mover el contenido: se reubica sobre el ancla conservada.
            restoreAnchorOffset()
        }
        measuredWhileHidden = false
        layoutArrows(centerY: HomeCollectionCardMetrics.airTop + size.width / 2)
        isApplying = false
        moved()
    }

    /// Deja la tarjeta ancla a la izquierda: desplazamiento `ancla · paso`, acotado al contenido.
    private func restoreAnchorOffset() {
        guard scroll.contentSize.width > 0 else { return }
        let count = max(1, model?.records.count ?? 1)
        anchorIndex = min(max(0, anchorIndex), count - 1)
        scrollTo(min(collectionsMaximumOffset, CGFloat(anchorIndex) * cardStride))
    }

    private func layoutMosaic() {
        // Inicio tapado u oculto: no se mide ni se reubica nada; se conservan la última medida real y la posición.
        guard bounds.width > 0, bounds.height > 0 else { return }
        scroll.frame = bounds
        layoutArrows()
        collection.layoutSubtreeIfNeeded()
        let contentSize = mosaicLayout.collectionViewContentSize
        let clipSize = scroll.contentView.bounds.size
        collection.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: max(clipSize.width, contentSize.width),
                height: max(clipSize.height, contentSize.height)
            )
        )
        restoreOffset()
        moved()
    }

    // MARK: Celdas

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let model else { return 0 }
        return model.usesMosaic ? min(model.records.count, mosaicLayout.mosaic.cells.count) : model.records.count
    }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt path: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: HomeCollectionItem.identifier, for: path) as! HomeCollectionItem
        configure(cell, index: path.item)
        return cell
    }
    private func configure(_ cell: HomeCollectionItem, index: Int) {
        guard let model, pageIsActive, model.records.indices.contains(index) else { return }
        configuredCount += 1
        let record = model.display(model.records[index])
        let song = model.usesMosaic
        var mosaicSize = HomeMosaicSize.small
        if model.usesMosaic, mosaicLayout.mosaic.cells.indices.contains(index) {
            let mosaicCell = mosaicLayout.mosaic.cells[index]
            mosaicSize = mosaicCell.size
            cell.view.frame.size = HomeMosaicMetrics.frame(of: mosaicCell).size
        } else if !model.usesMosaic {
            cell.view.frame.size = flow.itemSize
        }
        cell.content.featuredSong = song
        cell.content.featuredCollection = !song
        cell.content.mosaicSize = mosaicSize
        cell.content.albumCardStyle = model.albumCardStyle
        cell.content.coverSession = model.session
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

    // MARK: Desplazamiento

    @objc private func moved() {
        guard !isStopped, let model else { return }
        visibilityUpdateCount += 1
        for path in collection.indexPathsForVisibleItems() {
            guard let cell = collection.item(at: path) as? HomeCollectionItem else { continue }
            let id = ObjectIdentifier(cell)
            let visible = pageIsActive && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty && !cell.view.visibleRect.isEmpty
            if !visible && suspended.insert(id).inserted { cell.content.prepareForReuse() }
            else if visible && suspended.remove(id) != nil { configure(cell, index: path.item) }
            cell.content.setFeedVisible(visible)
        }
        let clip = scroll.contentView
        if model.usesMosaic {
            // Sólo una medida real actualiza la posición retenida.
            if !isApplying, bounds.width > 0 { retainedOffset = max(0, clip.bounds.minX) }
            previous.isHidden = clip.bounds.minX <= 1
            next.isHidden = mosaicLayout.collectionViewContentSize.width <= clip.bounds.maxX + 1
            return
        }
        // Sólo una medida real (ancho > 0, no una reubicación propia) mueve el ancla.
        // Con una reubicación pendiente (tras un ancho ≤ 0) la posición actual no es una medida del usuario.
        if !isApplying, userMovedRail, !measuredWhileHidden, bounds.width > 0, scroll.contentSize.width > 0, cardStride > HomeCollectionRowLayout.gap {
            anchorIndex = min(max(0, model.records.count - 1), max(0, Int((max(0, clip.bounds.minX) / cardStride).rounded())))
        }
        previous.isHidden = clip.bounds.minX <= 1
        next.isHidden = flow.collectionViewContentSize.width <= clip.bounds.maxX + 1
        let visible = !pageIsActive || isHiddenOrHasHiddenAncestor || visibleRect.isEmpty ? [] : HomeCollectionRowViewport.visibleIDs(
            ids: model.records.map { "\($0.kind):\($0.id)" }, cardWidth: flow.itemSize.width, spacing: HomeCollectionRowLayout.gap,
            offset: clip.bounds.minX, width: bounds.width, leadingInset: max(0, model.leadingInset), trailingInset: max(0, model.trailingInset))
        guard visible != published else { return }
        published = visible
        // Defer publishing out of AppKit layout / SwiftUI update; a rail already stopped never publishes.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isStopped, self.published == visible else { return }
            self.model?.onVisible(visible)
        }
    }

    @objc private func goPrevious() { advance(-1) }
    @objc private func goNext() { advance(1) }
    private func advance(_ direction: CGFloat) {
        guard !isStopped, let model else { return }
        let clip = scroll.contentView
        let viewport = scroll.contentSize.width
        let x: CGFloat
        // Misma lógica que HorizontalNavigation.svelte; el extent no cuenta los márgenes.
        if model.usesMosaic {
            let maximum = max(0, mosaicLayout.collectionViewContentSize.width - viewport)
            let extent = viewport - mosaicLayout.leadingInset - mosaicLayout.trailingInset
            x = HomeRailPaging.target(position: clip.bounds.minX, extent: extent, maximum: maximum, direction: direction)
        } else {
            // Tarjetas enteras: paso `ancho + 24`.
            let extent = viewport - flow.sectionInset.left - flow.sectionInset.right
            x = HomeRailPaging.target(position: clip.bounds.minX, extent: extent, maximum: collectionsMaximumOffset,
                                      direction: direction, stride: cardStride)
        }
        userMovedRail = true
        cancelSnap()
        clip.scroll(to: NSPoint(x: x, y: 0))
        scroll.reflectScrolledClipView(clip)
    }

    // MARK: Encaje al inicio de tarjeta

    /// Un gesto nuevo interrumpe el encaje en curso: no se pelea con el usuario.
    @objc private func liveScrollBegan() {
        guard !isStopped else { return }
        userMovedRail = true
        cancelSnap()
    }

    /// Al terminar el gesto, si quedó cerca del inicio de una tarjeta, se acomoda ahí.
    @objc private func liveScrollEnded() {
        guard !isStopped, let model, !model.usesMosaic, bounds.width > 0, scroll.contentSize.width > 0 else { return }
        let clip = scroll.contentView
        guard let target = HomeCollectionRowSnap.target(offset: clip.bounds.minX, stride: cardStride,
                                                        maximum: collectionsMaximumOffset) else { return }
        if reducesMotion() || window == nil {
            clip.scroll(to: NSPoint(x: target, y: 0))
            scroll.reflectScrolledClipView(clip)
            return
        }
        isSnapping = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            clip.animator().setBoundsOrigin(NSPoint(x: target, y: 0))
        }, completionHandler: { [weak self] in
            // Una animación que termina tras desmontar el carril no toca nada.
            guard let self, !self.isStopped else { return }
            self.isSnapping = false
            self.scroll.reflectScrolledClipView(self.scroll.contentView)
        })
    }

    private func cancelSnap() {
        guard isSnapping else { return }
        isSnapping = false
        let clip = scroll.contentView
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = true
            clip.animator().setBoundsOrigin(clip.bounds.origin)
        }
    }

    /// Desmonta el carril: ninguna devolución diferida (publicación, notificación, color, lavado, encaje) vuelve a actuar.
    func stop() {
        isStopped = true
        NotificationCenter.default.removeObserver(self)
        observedClips.removeAll()
        for item in collection.visibleItems() { (item as? HomeCollectionItem)?.content.prepareForReuse() }
        model = nil
    }

    var mosaicLayoutForTesting: HomeMosaicLayout { mosaicLayout.mosaic }
    var mosaicContentSizeForTesting: NSSize { mosaicLayout.collectionViewContentSize }
    var scrollOffsetForTesting: CGFloat { scroll.contentView.bounds.minX }
    func setScrollOffsetForTesting(_ x: CGFloat) {
        userMovedRail = true
        scroll.contentView.scroll(to: NSPoint(x: x, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    var arrowStateForTesting: (previousHidden: Bool, nextHidden: Bool) { (previous.isHidden, next.isHidden) }
    func pressNextForTesting() { goNext() }
    func pressPreviousForTesting() { goPrevious() }
    /// Tamaño de ítem, márgenes y ancho del contenido de la fila de colecciones.
    var collectionGeometryForTesting: (itemSize: NSSize, insets: NSEdgeInsets, contentWidth: CGFloat) {
        (flow.itemSize, flow.sectionInset, flow.collectionViewContentSize.width)
    }
    var scrollFrameForTesting: NSRect { scroll.frame }
    /// Simula el fin de un gesto de desplazamiento.
    func beginLiveScrollForTesting() {
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
    }
    func finishLiveScrollForTesting() {
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
    }
}
private final class HomeFeaturedScrollView: HomeFeedScrollView, HorizontalNavigationGestureOwner {
    var ownsHorizontalNavigationGesture: Bool { true }
    var onUserScroll: (() -> Void)?
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            var parent = superview
            while let view = parent {
                if let outer = view as? NSScrollView, outer.hasVerticalScroller { outer.scrollWheel(with: event); return }
                parent = view.superview
            }
        }
        if abs(event.scrollingDeltaX) > 0 || abs(event.deltaX) > 0 { onUserScroll?() }
        super.scrollWheel(with: event)
    }
}
