import AppKit
import SwiftUI

/// Native presentation owns its frame clock; SwiftUI supplies semantic state only.
struct AnimatedWindowNavigationToolbarView: View {
    let selection: MainNavigationDestination
    let isPresented: Bool
    let reduceMotion: Bool
    var revealProgress: Double
    let router: NavigationRouter
    let isHistoryDisabled: Bool
    let showsHistory: Bool
    var viewportWidth: CGFloat = ShellLayout.navigationMinimumWidth
    var isHomeSettingsPresented: Bool = false
    var onHistoryFrameChanged: ((CGRect) -> Void)? = nil
    var onHomeSettings: () -> Void = {}
    let onHome: () -> Void
    var onExplore: () -> Void = {}
    let onLibrary: () -> Void
    let onSearch: () -> Void
    var isSidebarExpanded: Bool = false
    var isSearchExpanded: Bool = false
    var searchQuery: String = ""
    var searchFocusRevision: Int = 0
    var searchSessionRevision: Int = 0
    var onSearchExpansionChange: (Bool) -> Void = { _ in }
    var onSearchQueryChange: (String) -> Void = { _ in }
    var onSearchSubmit: ((String) -> Void)? = nil
    var onSearchMoveSelection: ((Int) -> Void)? = nil
    var searchSelectionLabel: String? = nil
    var searchResultsContent: AnyView? = nil

    var body: some View {
        WindowNavigationToolbarView(
            navigation: TopNavigationView(selection: selection, isPresented: isPresented, reduceMotion: reduceMotion,
                                          revealProgress: revealProgress, onHome: onHome, onExplore: onExplore,
                                          onLibrary: onLibrary, onSearch: onSearch),
            history: HistoryToolbarView(router: router, isDisabled: isHistoryDisabled,
                                        isHomeSettingsPresented: isHomeSettingsPresented,
                                        onHomeSettings: onHomeSettings), showsHistory: showsHistory,
            viewportWidth: viewportWidth, onHistoryFrameChanged: onHistoryFrameChanged,
            isSidebarExpanded: isSidebarExpanded, isSearchExpanded: isSearchExpanded,
            searchQuery: searchQuery, searchFocusRevision: searchFocusRevision,
            searchSessionRevision: searchSessionRevision,
            onSearchExpansionChange: onSearchExpansionChange, onSearchQueryChange: onSearchQueryChange,
            onSearchSubmit: onSearchSubmit, onSearchMoveSelection: onSearchMoveSelection,
            searchSelectionLabel: searchSelectionLabel, searchResultsContent: searchResultsContent,
            fillsViewport: true)
    }
}

struct WindowNavigationToolbarView: NSViewRepresentable {
    let navigation: TopNavigationView
    let history: HistoryToolbarView
    let showsHistory: Bool
    var viewportWidth: CGFloat = ShellLayout.navigationMinimumWidth
    var onHistoryFrameChanged: ((CGRect) -> Void)? = nil
    var isSidebarExpanded: Bool = false
    var isSearchExpanded: Bool = false
    var searchQuery: String = ""
    var searchFocusRevision: Int = 0
    var searchSessionRevision: Int = 0
    var onSearchExpansionChange: (Bool) -> Void = { _ in }
    var onSearchQueryChange: (String) -> Void = { _ in }
    var onSearchSubmit: ((String) -> Void)? = nil
    var onSearchMoveSelection: ((Int) -> Void)? = nil
    var searchSelectionLabel: String? = nil
    var searchResultsContent: AnyView? = nil

    var fillsViewport = false

    @MainActor final class Coordinator {
        let navigation: TopNavigationView.Coordinator
        let history: HistoryToolbarView.Coordinator
        var localizationObserver: AppKitLocalizationObserver?
        init(_ parent: WindowNavigationToolbarView) {
            navigation = parent.navigation.makeCoordinator()
            history = parent.history.makeCoordinator()
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNativeHeader(coordinator: Coordinator, reduceTransparency: Bool) -> NativeNavigationHeader {
        let menu = navigation.makeNativeContainer(coordinator: coordinator.navigation, reduceTransparency: reduceTransparency)
        let actions = history.makeNativeContainer(coordinator: coordinator.history, reduceTransparency: reduceTransparency)
        let search = NativeSearchBar()
        let surface = NavigationGlassSurface(content: search)
        surface.update(reduceTransparency: reduceTransparency)
        let header = NativeNavigationHeader(menu: menu, history: actions, searchHost: surface,
                                            searchBar: search, navigationCoordinator: coordinator.navigation)
        coordinator.localizationObserver = AppKitLocalizationObserver { [weak search] in search?.updateLocalization() }
        coordinator.localizationObserver?.start()
        updateNativeHeader(header, coordinator: coordinator, reduceTransparency: reduceTransparency)
        return header
    }
    func makeNSView(context: Context) -> NativeNavigationHeader {
        makeNativeHeader(coordinator: context.coordinator,
                         reduceTransparency: context.environment.accessibilityReduceTransparency)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NativeNavigationHeader, context: Context) -> CGSize? {
        CGSize(width: max(ShellLayout.navigationMinimumWidth, proposal.width ?? viewportWidth),
               height: fillsViewport ? max(ShellLayout.toolbarHostHeight, proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 0) : ShellLayout.toolbarHostHeight)
    }
    func updateNSView(_ header: NativeNavigationHeader, context: Context) {
        updateNativeHeader(header, coordinator: context.coordinator,
                           reduceTransparency: context.environment.accessibilityReduceTransparency)
    }
    func updateNativeHeader(_ header: NativeNavigationHeader, coordinator: Coordinator, reduceTransparency: Bool) {
        navigation.updateNativeContainer(header.navigationHost, coordinator: coordinator.navigation,
                                         reduceTransparency: reduceTransparency, updatesPresentation: false)
        history.updateNativeContainer(header.history, coordinator: coordinator.history, reduceTransparency: reduceTransparency)
        header.searchHost.update(reduceTransparency: reduceTransparency)
        header.searchBar.updateLocalization()
        header.setSearchSession(revision: searchSessionRevision, query: searchQuery)
        header.searchBar.setQuery(searchQuery)
        header.searchBar.onToggleExpand = onSearchExpansionChange
        header.searchBar.onQueryChange = onSearchQueryChange
        header.searchBar.onSubmit = onSearchSubmit
        header.searchBar.onMoveSelection = onSearchMoveSelection
        header.searchBar.selectionLabel = searchSelectionLabel
        header.searchResultsHost.setContent(searchResultsContent)
        header.viewportWidth = viewportWidth
        header.onHistoryFrameChanged = onHistoryFrameChanged
        header.setPresentation(sidebarExpanded: isSidebarExpanded, searchExpanded: isSearchExpanded,
                               visible: showsHistory, reduceMotion: navigation.reduceMotion,
                               focusRevision: searchFocusRevision)
    }
    static func dismantleNSView(_ nsView: NativeNavigationHeader, coordinator: Coordinator) {
        nsView.stopAnimation()
        nsView.searchBar.unfocusField()
        nsView.searchResultsHost.setContent(nil)
    }
}

/// Both independent transitions can reverse from the value already on screen.
struct NavigationProgressAnimation {
    let start: CGFloat
    let target: CGFloat
    let startTime: CFTimeInterval
    let duration: CFTimeInterval

    func value(at time: CFTimeInterval) -> CGFloat {
        let t = min(1, max(0, (time - startTime) / duration))
        return start + (target - start) * CGFloat(1 - pow(1 - t, 4))
    }
    func isComplete(at time: CFTimeInterval) -> Bool { time >= startTime + duration }
}

struct NavigationClusterFrames {
    let search: CGRect
    let destinations: CGRect
    let history: CGRect

    static func make(bounds: CGRect, center: CGPoint, leading: CGFloat, trailing: CGFloat,
                     sidebarProgress: CGFloat, searchProgress: CGFloat, reduceMotion: Bool,
                     windowTop: CGFloat) -> Self {
        let height = ShellLayout.navigationSurfaceHeight
        let gap = ShellLayout.navigationClusterGap
        let searchWidth = ShellLayout.searchCollapsedWidth
        let destinationsWidth = ShellLayout.destinationsSurfaceWidth
        let historyWidth = ShellLayout.historySurfaceWidth
        let clusterWidth = searchWidth + destinationsWidth + historyWidth + gap * 2
        let startX = min(max(center.x - clusterWidth / 2, bounds.minX), bounds.maxX - clusterWidth)
        let restingY = center.y - height / 2
        let openSearchX = max(bounds.minX, leading)
        let openHistoryX = min(bounds.maxX, trailing) - historyWidth
        let searchX = startX + (openSearchX - startX) * sidebarProgress
        let closedHistoryX = startX + searchWidth + destinationsWidth + gap * 2
        let historyX = closedHistoryX + (openHistoryX - closedHistoryX) * sidebarProgress
        // In exact fusion only the search width changes. Its end is precisely the
        // destinations' end, leaving the same ten points before history.
        let desiredWidth = searchWidth + (ShellLayout.searchExpandedWidth - searchWidth) * searchProgress
        let width = min(desiredWidth, max(searchWidth, historyX - gap - searchX))
        let exitDistance = max(0, restingY + height - windowTop + 8)
        return Self(
            search: CGRect(x: searchX, y: restingY, width: width, height: height),
            destinations: CGRect(x: startX + searchWidth + gap,
                                 y: restingY - (reduceMotion ? 0 : exitDistance * sidebarProgress),
                                 width: destinationsWidth, height: height),
            history: CGRect(x: historyX, y: restingY, width: historyWidth, height: height))
    }
}

/// A full-viewport native sibling keeps results inside normal AppKit hit testing.
final class NavigationSearchResultsHost: NSView {
    let hostingView = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))
    private(set) var hasContent = false
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = false
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        isHidden = true
    }
    required init?(coder: NSCoder) { nil }

    func setContent(_ content: AnyView?) {
        guard content != nil || hasContent else { return }
        hasContent = content != nil
        hostingView.rootView = content ?? AnyView(EmptyView())
        if content == nil { isHidden = true }
    }

    override func layout() {
        super.layout()
        if hostingView.frame != bounds { hostingView.frame = bounds }
    }
}

struct NavigationSearchPanelLayout {
    static func frame(search: CGRect, viewport: CGRect) -> CGRect {
        let inset: CGFloat = 18
        let width = min(560, max(0, viewport.width - inset * 2))
        let x = min(max(search.minX, viewport.minX + inset), viewport.maxX - inset - width)
        let y = search.maxY + 8
        let height = min(540, max(0, viewport.maxY - 114 - y))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

final class NativeNavigationHeader: NSView {
    let navigationHost: WindowAlignedToolbarContainer
    let history: WindowAlignedToolbarContainer
    let searchHost: NavigationGlassSurface
    let searchBar: NativeSearchBar
    let searchResultsHost = NavigationSearchResultsHost(frame: .zero)
    private weak var navigationCoordinator: TopNavigationView.Coordinator?
    var viewportWidth: CGFloat = ShellLayout.navigationMinimumWidth {
        didSet {
            guard oldValue != viewportWidth else { return }
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }
    var onHistoryFrameChanged: ((CGRect) -> Void)?
    private var lastReportedHistoryFrame: CGRect?
    private var searchSessionRevision: Int?
    private(set) var sidebarProgress: CGFloat = 0
    private(set) var searchProgress: CGFloat = 0
    private var sidebarAnimation: NavigationProgressAnimation?
    private var searchAnimation: NavigationProgressAnimation?
    private var opacityAnimation: NavigationProgressAnimation?
    private var presentation: Presentation?
    private var frameLink: CADisplayLink?
    private var frameTarget: FrameTarget?
    private var sidebarRevision = 0
    private var opacityRevision = 0
    private var positionMotions: [ObjectIdentifier: PositionMotion] = [:]
    private var trackingOrigins: [ObjectIdentifier: CGPoint] = [:]
    private var trackingButtonMask: UInt = 0
    private var trackingReleaseScheduled = false
    private var outsideClickMonitor: Any?
    private var lastGeometry: Geometry?
    static let sidebarPositionAnimationKey = "sideb.sidebar.position"
    static let destinationsOpacityAnimationKey = "sideb.destinations.opacity"

    private struct Presentation: Equatable {
        let sidebarExpanded: Bool
        let searchExpanded: Bool
        let visible: Bool
        let reduceMotion: Bool
        let focusRevision: Int
    }
    private struct Geometry: Equatable {
        let bounds: CGRect
        let center: CGPoint
        let leading: CGFloat
        let trailing: CGFloat
        let windowTop: CGFloat
    }
    private struct PositionMotion {
        let offset: CGPoint
        let progress: NavigationProgressAnimation
        func value(at time: CFTimeInterval) -> CGPoint {
            let remainder = 1 - progress.value(at: time)
            return CGPoint(x: offset.x * remainder, y: offset.y * remainder)
        }
    }
    private final class FrameTarget: NSObject {
        weak var owner: NativeNavigationHeader?
        init(owner: NativeNavigationHeader) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) { owner?.advanceAnimation(at: CACurrentMediaTime()) }
    }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: max(ShellLayout.navigationMinimumWidth, viewportWidth), height: ShellLayout.toolbarHostHeight)
    }
    override var fittingSize: NSSize { intrinsicContentSize }
    var isAnimating: Bool { sidebarAnimation != nil || searchAnimation != nil || opacityAnimation != nil }
    var isFrameClockRunning: Bool { frameLink != nil }
    private var clusterViews: [NSView] { [navigationHost, searchHost, history, searchResultsHost] }

    init(menu: WindowAlignedToolbarContainer, history: WindowAlignedToolbarContainer,
         searchHost: NavigationGlassSurface, searchBar: NativeSearchBar,
         navigationCoordinator: TopNavigationView.Coordinator) {
        self.navigationHost = menu
        self.history = history
        self.searchHost = searchHost
        self.searchBar = searchBar
        self.navigationCoordinator = navigationCoordinator
        super.init(frame: NSRect(x: 0, y: 0, width: ShellLayout.navigationMinimumWidth,
                                height: ShellLayout.toolbarHostHeight))
        wantsLayer = true
        clipsToBounds = false
        menu.usesWindowAlignment = false
        history.usesWindowAlignment = false
        addSubview(menu)
        addSubview(searchHost)
        addSubview(history)
        addSubview(searchResultsHost)
    }
    required init?(coder: NSCoder) { nil }
    deinit {
        frameLink?.invalidate()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }

    func setSearchSession(revision: Int, query: String) {
        guard searchSessionRevision != revision else { return }
        searchSessionRevision = revision
        stopAnimation()
        presentation = nil
        searchBar.resetForSession(query: query)
        searchResultsHost.setContent(nil)
    }

    func setPresentation(sidebarExpanded: Bool, searchExpanded: Bool, visible: Bool,
                         reduceMotion: Bool, focusRevision: Int = 0) {
        let next = Presentation(sidebarExpanded: sidebarExpanded, searchExpanded: searchExpanded,
                                visible: visible, reduceMotion: reduceMotion, focusRevision: focusRevision)
        guard next != presentation else { return }
        let previous = presentation
        let now = CACurrentMediaTime()
        advanceProgress(at: now)
        let positions = visiblePositions(at: now)
        let opacity = visibleDestinationsOpacity(at: now)
        presentation = next
        searchBar.setExpanded(searchExpanded && visible)
        let sidebarChanged = previous?.sidebarExpanded != sidebarExpanded || previous?.reduceMotion != reduceMotion
        let searchChanged = previous?.searchExpanded != searchExpanded || previous?.reduceMotion != reduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if previous == nil || window == nil || !visible {
            stopAnimation()
            sidebarProgress = sidebarExpanded ? 1 : 0
            searchProgress = searchExpanded ? 1 : 0
            layoutClusters()
            setDestinationModel()
        } else {
            let duration = reduceMotion ? 0.15 : 0.42
            if sidebarChanged {
                sidebarAnimation = NavigationProgressAnimation(start: sidebarProgress, target: sidebarExpanded ? 1 : 0,
                                                               startTime: now, duration: duration)
            }
            if searchChanged {
                let target: CGFloat = searchExpanded ? 1 : 0
                if reduceMotion {
                    searchProgress = target
                    searchAnimation = nil
                } else if target != searchProgress {
                    searchAnimation = NavigationProgressAnimation(start: searchProgress, target: target,
                                                                  startTime: now, duration: duration)
                } else {
                    searchAnimation = nil
                }
            }
            // The NSView model reaches the lateral endpoint once. Only the
            // compositor interpolates translation; the search clock owns width.
            layoutClusters(retargetSidebar: false)
            if sidebarChanged { animateSidebar(from: positions, at: now, duration: duration) }
            if sidebarChanged || searchChanged || previous?.visible != visible {
                animateDestinationsOpacity(from: opacity, at: now, duration: duration)
            }
            if searchAnimation != nil { startFrameLink() } else { stopFrameLink() }
        }
        CATransaction.commit()
        updateOutsideClickMonitor()
        if previous?.focusRevision != focusRevision, searchExpanded, visible { searchBar.requestFocus() }
        needsLayout = true
    }

    private func startFrameLink() {
        guard frameLink == nil, window != nil, searchAnimation != nil else { return }
        let target = FrameTarget(owner: self)
        let link = displayLink(target: target, selector: #selector(FrameTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        frameTarget = target
        frameLink = link
    }
    private func stopFrameLink() {
        frameLink?.invalidate()
        frameLink = nil
        frameTarget = nil
    }
    func stopAnimation() {
        removeOutsideClickMonitor()
        stopFrameLink()
        sidebarRevision &+= 1
        opacityRevision &+= 1
        for view in clusterViews { view.layer?.removeAnimation(forKey: Self.sidebarPositionAnimationKey) }
        navigationHost.layer?.removeAnimation(forKey: Self.destinationsOpacityAnimationKey)
        positionMotions.removeAll()
        trackingOrigins.removeAll()
        trackingButtonMask = 0
        sidebarAnimation = nil
        searchAnimation = nil
        opacityAnimation = nil
    }
    private func advanceProgress(at time: CFTimeInterval) {
        if let animation = sidebarAnimation {
            sidebarProgress = animation.value(at: time)
            if animation.isComplete(at: time) { finishSidebar(revision: sidebarRevision) }
        }
        if let animation = searchAnimation {
            searchProgress = animation.value(at: time)
            if animation.isComplete(at: time) { searchAnimation = nil }
        }
        if let animation = opacityAnimation, animation.isComplete(at: time) {
            finishOpacity(revision: opacityRevision)
        }
    }
    func advanceAnimation(at time: CFTimeInterval) {
        advanceProgress(at: time)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutClusters()
        CATransaction.commit()
        if searchAnimation == nil { stopFrameLink() }
    }
    private func finishSidebar(revision: Int) {
        guard revision == sidebarRevision else { return }
        sidebarProgress = presentation?.sidebarExpanded == true ? 1 : 0
        sidebarAnimation = nil
        positionMotions.removeAll()
        for view in clusterViews { view.layer?.removeAnimation(forKey: Self.sidebarPositionAnimationKey) }
    }
    private func finishOpacity(revision: Int) {
        guard revision == opacityRevision else { return }
        opacityAnimation = nil
        navigationHost.layer?.removeAnimation(forKey: Self.destinationsOpacityAnimationKey)
        navigationHost.isHidden = destinationTargetOpacity <= 0.001
        navigationCoordinator?.bar?.setInteractionEnabled(destinationTargetOpacity > 0.95)
    }
    private var destinationTargetOpacity: CGFloat {
        guard let presentation, presentation.visible else { return 0 }
        return presentation.sidebarExpanded || presentation.searchExpanded ? 0 : 1
    }
    private func setDestinationModel() {
        navigationCoordinator?.setClusterPresentation(progress: destinationTargetOpacity,
                                                       isPresented: destinationTargetOpacity > 0.95)
        // The coordinator deduplicates semantic state; completion/cleanup must
        // still restore visibility after a temporarily unhidden fading host.
        navigationHost.isHidden = destinationTargetOpacity <= 0.001
        navigationCoordinator?.bar?.setInteractionEnabled(destinationTargetOpacity > 0.95)
    }
    private func visibleDestinationsOpacity(at time: CFTimeInterval) -> CGFloat {
        if opacityAnimation != nil, let visible = navigationHost.layer?.presentation() {
            return CGFloat(visible.opacity)
        }
        return opacityAnimation?.value(at: time) ?? navigationHost.alphaValue
    }
    private func visiblePositions(at time: CFTimeInterval) -> [ObjectIdentifier: CGPoint] {
        Dictionary(uniqueKeysWithValues: clusterViews.compactMap { view in
            guard let layer = view.layer else { return nil }
            let key = ObjectIdentifier(view)
            if positionMotions[key] != nil, let visible = layer.presentation() {
                return (key, visible.position)
            }
            let offset = positionMotions[key]?.value(at: time) ?? .zero
            return (key, CGPoint(x: layer.position.x + offset.x, y: layer.position.y + offset.y))
        })
    }
    private func animateSidebar(from positions: [ObjectIdentifier: CGPoint], at time: CFTimeInterval,
                                duration: CFTimeInterval) {
        sidebarRevision &+= 1
        let revision = sidebarRevision
        positionMotions.removeAll()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            DispatchQueue.main.async { self?.finishSidebar(revision: revision) }
        }
        for view in clusterViews {
            guard let layer = view.layer else { continue }
            layer.removeAnimation(forKey: Self.sidebarPositionAnimationKey)
            guard presentation?.reduceMotion == false, trackingOrigins[ObjectIdentifier(view)] == nil,
                  let start = positions[ObjectIdentifier(view)] else { continue }
            let delta = CGPoint(x: start.x - layer.position.x, y: start.y - layer.position.y)
            guard abs(delta.x) > 0.001 || abs(delta.y) > 0.001 else { continue }
            let progress = NavigationProgressAnimation(start: 0, target: 1, startTime: time, duration: duration)
            let motion = PositionMotion(offset: delta, progress: progress)
            positionMotions[ObjectIdentifier(view)] = motion
            let animation = CAKeyframeAnimation(keyPath: "position")
            animation.isAdditive = true
            animation.values = (0...60).map { step in
                NSValue(point: motion.value(at: time + duration * Double(step) / 60))
            }
            animation.duration = duration
            animation.beginTime = layer.convertTime(time, from: nil)
            animation.calculationMode = .linear
            layer.add(animation, forKey: Self.sidebarPositionAnimationKey)
        }
        CATransaction.commit()
    }
    private func animateDestinationsOpacity(from opacity: CGFloat, at time: CFTimeInterval,
                                            duration: CFTimeInterval) {
        opacityRevision &+= 1
        let revision = opacityRevision
        navigationHost.layer?.removeAnimation(forKey: Self.destinationsOpacityAnimationKey)
        setDestinationModel()
        guard let layer = navigationHost.layer, abs(opacity - destinationTargetOpacity) > 0.001 else {
            opacityAnimation = nil
            return
        }
        let progress = NavigationProgressAnimation(start: opacity, target: destinationTargetOpacity,
                                                   startTime: time, duration: duration)
        opacityAnimation = progress
        navigationHost.isHidden = false
        navigationCoordinator?.bar?.setInteractionEnabled(false)
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = (0...60).map { step in progress.value(at: time + duration * Double(step) / 60) }
        animation.duration = duration
        animation.beginTime = layer.convertTime(time, from: nil)
        animation.calculationMode = .linear
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            DispatchQueue.main.async { self?.finishOpacity(revision: revision) }
        }
        layer.add(animation, forKey: Self.destinationsOpacityAnimationKey)
        CATransaction.commit()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopAnimation()
            sidebarProgress = presentation?.sidebarExpanded == true ? 1 : 0
            searchProgress = presentation?.searchExpanded == true ? 1 : 0
            searchBar.unfocusField()
            setDestinationModel()
        }
        updateOutsideClickMonitor()
        needsLayout = true
    }

    private func updateOutsideClickMonitor() {
        guard window != nil, presentation?.visible == true, searchBar.isExpanded else {
            removeOutsideClickMonitor()
            return
        }
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.handleOutsideSearchClick(event)
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// Observe the original event without changing its native dispatch target.
    func handleOutsideSearchClick(_ event: NSEvent) {
        guard [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
              let window, event.window === window, presentation?.visible == true,
              searchBar.isExpanded, !searchHost.isHiddenOrHasHiddenAncestor else { return }
        let point = convert(event.locationInWindow, from: nil)
        let offset = visibleOffset(for: searchHost, positions: visiblePositions(at: CACurrentMediaTime()))
        let visibleFrame = searchHost.frame.offsetBy(dx: offset.x, dy: offset.y)
        if !searchResultsHost.isHidden {
            let panelOffset = visibleOffset(for: searchResultsHost, positions: visiblePositions(at: CACurrentMediaTime()))
            let panelFrame = searchResultsHost.frame.offsetBy(dx: panelOffset.x, dy: panelOffset.y)
            if panelFrame.contains(point) { return }
        }
        guard !visibleFrame.contains(point) else { return }
        searchBar.requestCollapse()
        removeOutsideClickMonitor()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard let (hit, host) = presentedHit(at: localPoint) else { return nil }
        if positionMotions[ObjectIdentifier(host)] != nil,
           let event = NSApp?.currentEvent, event.window === window,
           [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            return beginMouseTracking(at: localPoint, buttonNumber: event.buttonNumber)
        }
        return hit
    }
    private func presentedHit(at localPoint: NSPoint) -> (NSView, NSView)? {
        guard presentation?.visible == true, !isHidden else { return nil }
        let positions = visiblePositions(at: CACurrentMediaTime())
        for view in clusterViews.reversed() where !view.isHidden {
            let delta = visibleOffset(for: view, positions: positions)
            let modelPoint = NSPoint(x: localPoint.x - delta.x, y: localPoint.y - delta.y)
            if let hit = view.hitTest(modelPoint), hit !== view { return (hit, view) }
        }
        return nil
    }
    private func visibleOffset(for view: NSView, positions: [ObjectIdentifier: CGPoint]) -> CGPoint {
        guard let layer = view.layer else { return .zero }
        let position = positions[ObjectIdentifier(view)] ?? layer.position
        let delta = CGPoint(x: position.x - layer.position.x, y: position.y - layer.position.y)
        return CGPoint(x: delta.x, y: layer.superlayer?.isGeometryFlipped == isFlipped ? delta.y : -delta.y)
    }
    /// Put the model under the pointer before AppKit dispatches the original
    /// event. Modern controls own their tracking gestures; never resend mouseDown.
    func beginMouseTracking(at point: NSPoint, buttonNumber: Int) -> NSView? {
        guard let (target, host) = presentedHit(at: point) else { return nil }
        let key = ObjectIdentifier(host)
        guard positionMotions[key] != nil || trackingOrigins[key] != nil else { return target }
        if trackingOrigins[key] == nil {
            let positions = visiblePositions(at: CACurrentMediaTime())
            let movingViews: [NSView] = (host === searchHost || host === searchResultsHost)
                ? [searchHost, searchResultsHost] : [host]
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for view in movingViews {
                let viewKey = ObjectIdentifier(view)
                let delta = visibleOffset(for: view, positions: positions)
                let origin = CGPoint(x: view.frame.minX + delta.x, y: view.frame.minY + delta.y)
                trackingOrigins[viewKey] = origin
                view.setFrameOrigin(origin)
                view.layer?.removeAnimation(forKey: Self.sidebarPositionAnimationKey)
                positionMotions.removeValue(forKey: viewKey)
            }
            CATransaction.commit()
        }
        if (0..<UInt.bitWidth).contains(buttonNumber) { trackingButtonMask |= UInt(1) << buttonNumber }
        scheduleTrackingRelease()
        return target
    }
    private func scheduleTrackingRelease() {
        guard !trackingReleaseScheduled, !trackingOrigins.isEmpty else { return }
        trackingReleaseScheduled = true
        // Classic controls may consume mouse-up in their tracking loop. The
        // physical button state also covers modern, nonblocking gesture tracking.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self else { return }
            self.trackingReleaseScheduled = false
            guard !self.trackingOrigins.isEmpty else { return }
            if UInt(bitPattern: NSEvent.pressedMouseButtons) & self.trackingButtonMask == 0 {
                self.endMouseTracking()
            } else {
                self.scheduleTrackingRelease()
            }
        }
    }
    func endMouseTracking() {
        guard !trackingOrigins.isEmpty else { return }
        let now = CACurrentMediaTime()
        let positions = visiblePositions(at: now)
        trackingOrigins.removeAll()
        trackingButtonMask = 0
        guard window != nil, presentation?.visible == true else { return }
        let remaining = sidebarAnimation.map { $0.startTime + $0.duration - now } ?? 0
        let duration = max(0.12, remaining)
        sidebarAnimation = NavigationProgressAnimation(start: sidebarProgress,
            target: presentation?.sidebarExpanded == true ? 1 : 0, startTime: now, duration: duration)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutClusters(retargetSidebar: false)
        animateSidebar(from: positions, at: now, duration: duration)
        CATransaction.commit()
    }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutClusters()
        CATransaction.commit()
    }
    private func geometry() -> Geometry {
        var center = NSPoint(x: bounds.midX, y: ShellLayout.navigationRowCenter)
        var windowTop = bounds.minY
        var leading = bounds.minX + 18
        var trailing = bounds.maxX - 18
        if let content = window?.contentView {
            let top = content.isFlipped ? content.bounds.minY : content.bounds.maxY
            windowTop = convert(NSPoint(x: content.bounds.midX, y: top), from: content).y
            let y = content.isFlipped ? top + ShellLayout.navigationRowCenter : top - ShellLayout.navigationRowCenter
            center = convert(NSPoint(x: content.bounds.midX, y: y), from: content)
            leading = convert(NSPoint(x: content.bounds.minX + ShellLayout.sidebarReserveWidth(expanded: true) + 18,
                                      y: top), from: content).x
            trailing = convert(NSPoint(x: content.bounds.maxX - 18, y: top), from: content).x
        }
        return Geometry(bounds: bounds, center: center, leading: leading, trailing: trailing, windowTop: windowTop)
    }
    private func layoutClusters(retargetSidebar: Bool = true) {
        guard let presentation else { return }
        let visible = presentation.visible
        if searchHost.isHidden != !visible { searchHost.isHidden = !visible }
        if history.isHidden != !visible { history.isHidden = !visible }
        searchHost.setEffectHidden(!visible)
        (history.contentView as? NavigationGlassSurface)?.setEffectHidden(!visible)
        let geometry = geometry()
        let now = CACurrentMediaTime()
        let shouldRetarget = retargetSidebar && lastGeometry != nil && lastGeometry != geometry && sidebarAnimation != nil
        let positions = shouldRetarget ? visiblePositions(at: now) : [:]
        lastGeometry = geometry
        let geometrySearch = presentation.reduceMotion ? (presentation.searchExpanded ? 1.0 : 0.0) : searchProgress
        let frames = NavigationClusterFrames.make(bounds: geometry.bounds, center: geometry.center,
            leading: geometry.leading, trailing: geometry.trailing,
            sidebarProgress: presentation.sidebarExpanded ? 1 : 0, searchProgress: geometrySearch,
            reduceMotion: presentation.reduceMotion, windowTop: geometry.windowTop)
        apply(frame: frames.destinations, to: navigationHost)
        apply(frame: frames.history, to: history)
        let previousSearchSize = searchHost.bounds.size
        apply(frame: frames.search, to: searchHost)
        let searchSizeChanged = previousSearchSize != searchHost.bounds.size
        let panelFrame = NavigationSearchPanelLayout.frame(search: frames.search, viewport: bounds)
        apply(frame: panelFrame, to: searchResultsHost)
        let showsResults = visible && presentation.searchExpanded && geometrySearch >= 0.65 &&
            searchResultsHost.hasContent && panelFrame.height >= 120
        if searchResultsHost.isHidden == showsResults {
            searchResultsHost.isHidden = !showsResults
            if showsResults {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = 0.14
                searchResultsHost.layer?.add(fade, forKey: "sideb.searchResults.reveal")
            }
        }
        if searchResultsHost.needsLayout { searchResultsHost.layoutSubtreeIfNeeded() }
        if shouldRetarget, let animation = sidebarAnimation {
            let remaining = max(0.001, animation.startTime + animation.duration - now)
            animateSidebar(from: positions, at: now, duration: remaining)
        }
        // A lateral translation leaves the actual glass bounds and its contents
        // intact. Only a genuine width/progress change needs native layout.
        // The search control deduplicates its visual state, while still retrying
        // a pending focus request even when the progress has not changed.
        searchBar.applyExpansionProgress(geometrySearch)
        if searchSizeChanged || searchHost.needsLayout || searchBar.needsLayout {
            searchHost.layoutSubtreeIfNeeded()
        }
        reportHistoryFrame()
    }
    private func apply(frame requestedFrame: CGRect, to view: NSView) {
        let scale = window?.backingScaleFactor ?? 1
        let origin = trackingOrigins[ObjectIdentifier(view)] ?? requestedFrame.origin
        let frame = CGRect(x: (origin.x * scale).rounded() / scale,
                           y: (origin.y * scale).rounded() / scale,
                           width: (requestedFrame.width * scale).rounded() / scale,
                           height: (requestedFrame.height * scale).rounded() / scale)
        let sizeChanged = view.bounds.size != frame.size
        if view.frame != frame { view.frame = frame }
        let localBounds = CGRect(origin: .zero, size: frame.size)
        if view.bounds != localBounds { view.bounds = localBounds }
        if sizeChanged { view.needsLayout = true }
    }
    private func reportHistoryFrame() {
        guard onHistoryFrameChanged != nil, let frame = historyFrameInWindowTopDown(),
              lastReportedHistoryFrame.map({ !ShellLayout.sameControlFrame($0, frame) }) ?? true else { return }
        lastReportedHistoryFrame = frame
        DispatchQueue.main.async { [weak self] in
            guard let self, let latest = self.lastReportedHistoryFrame,
                  ShellLayout.sameControlFrame(latest, frame) else { return }
            self.onHistoryFrameChanged?(frame)
        }
    }
    private func historyFrameInWindowTopDown() -> CGRect? {
        guard let window else { return nil }
        let rectInWindowBase = history.convert(history.bounds, to: nil)
        let contentRect = window.contentRect(forFrameRect: window.frame)
        return CGRect(x: contentRect.minX - window.frame.minX + rectInWindowBase.minX,
                      y: window.frame.maxY - contentRect.maxY + contentRect.height - rectInWindowBase.maxY,
                      width: rectInWindowBase.width, height: rectInWindowBase.height)
    }
}
