import AppKit
import SwiftUI

/// Paged content owns a whole gesture, including its start/end and momentum.
@MainActor
protocol HorizontalNavigationGestureOwner: AnyObject {
    var ownsHorizontalNavigationGesture: Bool { get }
}

@MainActor
enum HorizontalNavigationGestureRouting {
    static func contentOwnsGesture(at point: NSPoint, in view: NSView) -> Bool {
        WindowGestureRegions.horizontalContentOwnsHistoryGesture(at: point, in: view)
    }
}

/// One adapter per window. Input decisions are pure; presentation observes only its own state.
@MainActor
final class WindowNavigationCoordinator: NSObject {
    private(set) weak var window: NSWindow?
    private var router: NavigationRouter?
    private var presentation: WindowGesturePresentation?
    private var isFullscreenPresented = false
    private var canHandleGestures = false
    private var reduceMotion = false
    private var onDismissFullscreen: (() -> Void)?
    private nonisolated(unsafe) var eventMonitor: Any?
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    private var volumePolicy = VolumeScrollPolicy()
    private weak var volumePlayer: PlayerViewModel?
    private var volumeRevision = 0
    private var pendingVolume: Float?
    private var pendingVolumeBaseRevision = 0
    private var lastVolumeApplication = -Double.infinity
    private nonisolated(unsafe) var volumeFrameTimer: Timer?
    private var machine = WindowGestureStateMachine()
    private var sequenceContext = WindowGestureStateMachine.Context(mode: .history)
    private var candidateHistory: [PageDestination] = []
    private var candidateIndex = 0
    private var previousAcceptsMouseMovedEvents = false
    private var menuIsTracking = false
    private var sessionRevision = 0
    private var diagnosticTask: Task<Void, Never>?
    private let performHaptic: () -> Void
    private let interactionIsAllowed: (() -> Bool)?

    init(performHaptic: @escaping () -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }, interactionIsAllowed: (() -> Bool)? = nil) {
        self.performHaptic = performHaptic
        self.interactionIsAllowed = interactionIsAllowed
        super.init()
    }

    func setup(router: NavigationRouter, presentation: WindowGesturePresentation,
               isFullscreenPresented: Bool, canHandleGestures: Bool,
               reduceMotion: Bool, sessionRevision: Int = 0,
               volumePlayer: PlayerViewModel? = nil, onDismissFullscreen: @escaping () -> Void) {
        // NSViewRepresentable must observe navigation even while idle. Route
        // content can update in a child without rebuilding this background host.
        let history = router.history
        let index = router.currentIndex
        let candidateIsCurrent = candidateIndex == index && candidateHistory == history
        let changed = self.router !== router || self.presentation !== presentation ||
            self.isFullscreenPresented != isFullscreenPresented ||
            self.canHandleGestures != canHandleGestures || self.sessionRevision != sessionRevision ||
            self.volumePlayer !== volumePlayer
        if changed || ((machine.isTracking || presentation.fullscreenIsBusy) && !candidateIsCurrent) {
            invalidate()
        } else if self.volumeRevision != (volumePlayer?.volumeScroll.contextRevision ?? 0) {
            // Moving the fullscreen under the pointer can end its hover during
            // a pull or settlement. Cancel volume ownership without resetting navigation.
            invalidateVolume()
        }
        self.volumePlayer = volumePlayer
        self.volumeRevision = volumePlayer?.volumeScroll.contextRevision ?? 0
        self.router = router
        self.presentation = presentation
        self.isFullscreenPresented = isFullscreenPresented
        self.canHandleGestures = canHandleGestures
        self.reduceMotion = reduceMotion
        self.sessionRevision = sessionRevision
        self.onDismissFullscreen = onDismissFullscreen
        if !isFullscreenPresented, presentation.fullscreenStage != .idle {
            presentation.resetFullscreen()
        }
        scheduleDiagnosticSnapshot()
    }

    func attach(to window: NSWindow) {
        guard self.window !== window || eventMonitor == nil else { return }
        detach()
        self.window = window
        previousAcceptsMouseMovedEvents = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .otherMouseUp, .mouseMoved, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handleEvent(event)
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.invalidate() }
            })
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidate() }
        })
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuIsTracking = true; self?.invalidate() }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuIsTracking = false }
        })
        scheduleDiagnosticSnapshot()
    }

    private func scheduleDiagnosticSnapshot() {
        guard WindowGestureDiagnostics.enabled else { return }
        diagnosticTask?.cancel()
        diagnosticTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, let window = self.window else { return }
            WindowGestureDiagnostics.record(window: window, fullscreen: self.isFullscreenPresented,
                                            isHome: self.router?.currentPage == .home)
        }
    }

    func detach() {
        diagnosticTask?.cancel()
        diagnosticTask = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        invalidate()
        machine.reset()
        volumePolicy.reset()
        window?.acceptsMouseMovedEvents = previousAcceptsMouseMovedEvents
        window = nil
        menuIsTracking = false
    }

    deinit {
        volumeFrameTimer?.invalidate()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func invalidate() {
        invalidateVolume()
        _ = machine.invalidate()
        presentation?.resetHorizontal()
        presentation?.resetFullscreen()
    }

    private func invalidateVolume() {
        flushVolume()
        volumePolicy.invalidate()
        volumePlayer?.volumeScroll.clear()
    }

    private func historyCandidateIsCurrent(_ router: NavigationRouter) -> Bool {
        candidateIndex == router.currentIndex && candidateHistory == router.history
    }

    private var windowAllowsInteraction: Bool {
        guard let window else { return false }
        return NSApp.isActive && window.isKeyWindow && window.attachedSheet == nil && NSApp.modalWindow == nil &&
            !menuIsTracking && canHandleGestures
    }

    @discardableResult
    func handleEvent(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, let router, let presentation else { return event }
        let enabled = windowAllowsInteraction
        if event.type == .otherMouseUp {
            guard enabled, !isFullscreenPresented, !presentation.fullscreenIsBusy else { return event }
            switch event.buttonNumber {
            case 3 where router.canGoBack: invalidate(); router.goBack(); return nil
            case 4 where router.canGoForward: invalidate(); router.goForward(); return nil
            default: return event
            }
        }
        if event.type == .mouseMoved || event.type == .flagsChanged {
            if let root = window.contentView, volumePlayer?.volumeScroll.isVisible == true || volumePolicy.requiresPointerValidation(at: event.timestamp) {
                let zone = WindowGestureRegions.volumeZone(at: root.convert(event.locationInWindow, from: nil), in: root)
                if !enabled || zone == nil || (volumePolicy.ownedZone != nil && zone != volumePolicy.ownedZone) ||
                    !event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty {
                    flushVolume(); volumePolicy.invalidate(); volumePlayer?.volumeScroll.clear()
                }
            }
            return event
        }
        guard event.type == .scrollWheel else { return event }
        let hasVolumeSurface = volumePlayer?.volumeScroll.isCapsuleOpen == true ||
            (isFullscreenPresented && volumePlayer?.currentTrack != nil)
        let volumeZone = hasVolumeSurface ? window.contentView.flatMap { root in
            WindowGestureRegions.volumeZone(at: root.convert(event.locationInWindow, from: nil), in: root)
        } : nil
        let volumeInput = VolumeScrollPolicy.Input(x: Double(event.scrollingDeltaX), y: Double(event.scrollingDeltaY),
            precise: event.hasPreciseScrollingDeltas, phase: Self.phase(event.phase),
            momentum: Self.phase(event.momentumPhase),
            modified: !event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty,
            timestamp: event.timestamp)
        if handleVolumeInput(volumeInput, zone: volumeZone, enabled: enabled) { return nil }
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let input = WindowGestureStateMachine.Event(deltaX: event.scrollingDeltaX * sign,
            deltaY: event.scrollingDeltaY * sign, phase: Self.phase(event.phase),
            momentumPhase: Self.phase(event.momentumPhase),
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas)
        let output = handleScrollInput(input, enabled: enabled) {
            guard let root = window.contentView else {
                return .init(mode: isFullscreenPresented ? .fullscreen : .history,
                             allowsHorizontalNavigation: false, allowsFullscreenDismissal: false)
            }
            return scrollContext(at: root.convert(event.locationInWindow, from: nil), in: root, enabled: enabled)
        }
        return output.disposition == .consume ? nil : event
    }

    /// Real monitor arbitration, also exposed to deterministic routing tests.
    @discardableResult
    func handleVolumeInput(_ input: VolumeScrollPolicy.Input, zone: VolumeScrollPolicy.Zone?, enabled: Bool) -> Bool {
        guard let player = volumePlayer else { return false }
        if let ownedZone = volumePolicy.ownedZone, ownedZone != zone {
            flushVolume(); player.volumeScroll.clear()
        }
        let eligible = enabled && !player.volumeScroll.isDragging &&
            (zone != .fullscreen || (isFullscreenPresented && player.currentTrack != nil))
        if volumeRevision != player.volumeScroll.contextRevision || !eligible {
            flushVolume(); volumePolicy.invalidate(); player.volumeScroll.clear()
            volumeRevision = player.volumeScroll.contextRevision
        }
        if pendingVolume != nil && pendingVolumeBaseRevision != player.audioService.volumeAssignmentRevision {
            pendingVolume = nil
        }
        let output = volumePolicy.handle(input, zone: eligible ? zone : nil, value: pendingVolume ?? player.volume)
        if output.consume {
            _ = machine.invalidate()
            presentation?.resetHorizontal()
            presentation?.resetFullscreen()
        }
        if output.steps != 0 {
            if pendingVolume == nil { pendingVolumeBaseRevision = player.audioService.volumeAssignmentRevision }
            pendingVolume = VolumeScrollPolicy.adjusting(pendingVolume ?? player.volume, by: output.steps)
            if !input.precise || input.timestamp - lastVolumeApplication >= 1.0 / 60 {
                flushVolume(timestamp: input.timestamp)
            } else if volumeFrameTimer == nil {
                volumeFrameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.flushVolume() }
                }
            }
        }
        if output.finished { flushVolume(timestamp: input.timestamp) }
        if let feedback = output.feedback {
            let displayZone: VolumeScrollPolicy.Zone = isFullscreenPresented && player.currentTrack != nil ? .fullscreen : feedback
            player.volumeScroll.receivedInput(in: displayZone, value: player.volume)
        }
        return output.consume
    }

    private func flushVolume(timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        volumeFrameTimer?.invalidate(); volumeFrameTimer = nil
        guard let value = pendingVolume, let player = volumePlayer else { pendingVolume = nil; return }
        pendingVolume = nil
        // A later slider, mute or AX assignment wins over this coalesced frame,
        // including an explicit assignment of the currently effective value.
        guard pendingVolumeBaseRevision == player.audioService.volumeAssignmentRevision else { return }
        player.volume = value
        player.volumeScroll.updateValue(player.volume)
        lastVolumeApplication = timestamp
    }

    /// Home explicitly reserves its horizontal viewports. Everywhere else keeps
    /// window-wide history; fullscreen dismissal uses separate panel routing.
    func scrollContext(at point: NSPoint, in root: NSView, enabled: Bool) -> WindowGestureStateMachine.Context {
        let available = enabled && canHandleGestures && presentation?.fullscreenIsBusy == false
        let homeContentOwnsGesture = !isFullscreenPresented && router?.currentPage == .home &&
            HorizontalNavigationGestureRouting.contentOwnsGesture(at: point, in: root)
        let routing = isFullscreenPresented
            ? WindowGestureRegions.routing(at: point, in: root, includeNativeFallback: false) : nil
        let volumeReplacesDismissal = isFullscreenPresented && volumePlayer?.currentTrack != nil &&
            WindowGestureRegions.volumeZone(at: point, in: root) == .fullscreen
        return .init(
            mode: isFullscreenPresented ? .fullscreen : .history,
            allowsHorizontalNavigation: available && !isFullscreenPresented && !homeContentOwnsGesture &&
                WindowGestureRegions.allowsHistory(at: point, in: root),
            allowsFullscreenDismissal: available && isFullscreenPresented && !volumeReplacesDismissal && routing?.allowsFullscreenDismissal == true,
            verticalContentOwnsGesture: routing?.ownsVertical ?? false,
            canGoBack: router?.canGoBack == true, canGoForward: router?.canGoForward == true,
            fullscreenHeight: root.bounds.height
        )
    }

    /// Test the real adapter flow without manufacturing NSWindow/NSEvent input.
    /// Region hit testing is performed only when the engine starts a new contact.
    @discardableResult
    func handleScrollInput(_ input: WindowGestureStateMachine.Event, enabled: Bool,
                           startContext: () -> WindowGestureStateMachine.Context) -> WindowGestureStateMachine.Output {
        guard let router, let presentation else {
            return .init(snapshot: machine.snapshot, disposition: .passThrough, commit: nil, didArm: false)
        }
        if !enabled || ((machine.isTracking || presentation.fullscreenIsBusy) && !historyCandidateIsCurrent(router)) {
            invalidate()
        }
        if machine.requiresStartContext(for: input) {
            candidateHistory = router.history
            candidateIndex = router.currentIndex
            sequenceContext = startContext()
            sequenceContext.allowsHorizontalNavigation = sequenceContext.allowsHorizontalNavigation && enabled
            sequenceContext.allowsFullscreenDismissal = sequenceContext.allowsFullscreenDismissal && enabled
        }
        let wasTracking = machine.isTracking
        let output = machine.handle(input, context: sequenceContext)
        let didFinishContact = wasTracking && !machine.isTracking
        if output.didArm { performHaptic() }
        let snapshot = output.snapshot
        switch snapshot.action {
        case .back, .forward:
            if snapshot.phase == .pulling || snapshot.phase == .armed {
                let back = snapshot.action == .back
                let index = candidateIndex + (back ? -1 : 1)
                let title = candidateHistory.indices.contains(index) ? candidateHistory[index].gestureTitle : ""
                presentation.updateHorizontal(.init(direction: back ? .back : .forward,
                    title: title, progress: snapshot.progress, offset: snapshot.offset,
                    available: snapshot.isAvailable, armed: snapshot.isArmed))
            } else if didFinishContact && (snapshot.phase == .cancelled || snapshot.phase == .committed) {
                presentation.finishHorizontal(reduceMotion: reduceMotion)
            }
        case .dismissFullscreen:
            if snapshot.phase == .pulling || snapshot.phase == .armed {
                presentation.beginFullscreenPull()
                presentation.updateFullscreenPull(offset: snapshot.offset,
                    progress: snapshot.progress, armed: snapshot.isArmed)
            } else if didFinishContact && snapshot.phase == .cancelled {
                presentation.settleFullscreen(shouldClose: false, travel: sequenceContext.fullscreenHeight,
                    reduceMotion: reduceMotion, onClosed: {})
            }
        case nil: break
        }
        if let action = output.commit, enabled, historyCandidateIsCurrent(router) {
            switch action {
            case .back: router.goBack()
            case .forward: router.goForward()
            case .dismissFullscreen:
                if isFullscreenPresented {
                    presentation.settleFullscreen(shouldClose: true,
                        travel: sequenceContext.fullscreenHeight + 24, reduceMotion: reduceMotion,
                        onClosed: { [weak self] in
                            guard let self, self.isFullscreenPresented, self.canHandleGestures,
                                  !self.menuIsTracking, let router = self.router,
                                  self.interactionIsAllowed?() ?? self.windowAllowsInteraction,
                                  self.historyCandidateIsCurrent(router) else { return }
                            self.onDismissFullscreen?()
                        })
                }
            }
        }
        return output
    }

    private static func phase(_ phase: NSEvent.Phase) -> WindowGestureStateMachine.EventPhase {
        if phase.contains(.cancelled) { return .cancelled }
        if phase.contains(.ended) { return .ended }
        if phase.contains(.began) { return .began }
        if phase.contains(.mayBegin) { return .mayBegin }
        if phase.contains(.changed) { return .changed }
        if phase.contains(.stationary) { return .stationary }
        return .none
    }
}

final class WindowNavigationHostingView: NSView {
    weak var coordinator: WindowNavigationCoordinator?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { coordinator?.attach(to: window) } else { coordinator?.detach() }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct WindowNavigationGestureBridge: NSViewRepresentable {
    let router: NavigationRouter
    let presentation: WindowGesturePresentation
    let isFullscreenPresented: Bool
    let canHandleGestures: Bool
    let reduceMotion: Bool
    let sessionRevision: Int
    var volumePlayer: PlayerViewModel? = nil
    let onDismissFullscreen: () -> Void
    func makeCoordinator() -> WindowNavigationCoordinator { WindowNavigationCoordinator() }
    func makeNSView(context: Context) -> WindowNavigationHostingView {
        let view = WindowNavigationHostingView()
        view.coordinator = context.coordinator
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: WindowNavigationHostingView, context: Context) {
        if let window = view.window, context.coordinator.window !== window {
            context.coordinator.attach(to: window)
        }
        context.coordinator.setup(router: router, presentation: presentation,
            isFullscreenPresented: isFullscreenPresented, canHandleGestures: canHandleGestures,
            reduceMotion: reduceMotion, sessionRevision: sessionRevision, volumePlayer: volumePlayer, onDismissFullscreen: onDismissFullscreen)
    }
    static func dismantleNSView(_ view: WindowNavigationHostingView, coordinator: WindowNavigationCoordinator) {
        coordinator.detach()
    }
}

extension PageDestination {
    @MainActor var gestureTitle: String {
        switch self {
        case .home: return L10n.text("destination.home")
        case .explore(let route): return route == .discover ? L10n.text("destination.explore") : route.title
        case .search(let query): return query.flatMap { $0.isEmpty ? nil : L10n.text("destination.searchQuery", args: [$0]) } ?? L10n.text("destination.search")
        case .album: return L10n.text("destination.album")
        case .artist: return L10n.text("destination.artist")
        case .catalog(_, _, let title): return title
        case .playlist(let id): return PlaylistCatalog.shared.cached(id: id)?.title ?? L10n.text("destination.playlist")
        case .library: return L10n.text("destination.library")
        case .history: return L10n.text("destination.history")
        }
    }
}
