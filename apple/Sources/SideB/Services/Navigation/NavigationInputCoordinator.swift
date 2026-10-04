import AppKit
import SwiftUI

/// Paged content owns a whole gesture, including its start/end and momentum.
/// Window history must not steal it before the content responder receives the event.
@MainActor
protocol HorizontalNavigationGestureOwner: AnyObject {
    var ownsHorizontalNavigationGesture: Bool { get }
}

@MainActor
enum HorizontalNavigationGestureRouting {
    static func contentOwnsGesture(at point: NSPoint, in view: NSView) -> Bool {
        guard !view.isHidden, view.alphaValue > 0.01, view.bounds.contains(point) else { return false }
        if let owner = view as? HorizontalNavigationGestureOwner, owner.ownsHorizontalNavigationGesture { return true }
        return view.subviews.reversed().contains { child in
            contentOwnsGesture(at: child.convert(point, from: view), in: child)
        }
    }
}

/// Tracks one physical two-finger gesture. Vertical scrolling keeps its events; horizontal
/// scrolling becomes navigation only after the content under the pointer reaches its edge.
@MainActor
struct NavigationSwipeTracker {
    enum Axis { case undecided, horizontal, vertical }

    static let axisThreshold: CGFloat = 8
    static let navigationThreshold: CGFloat = 55

    private(set) var axis: Axis = .undecided
    private(set) var pull: CGFloat = 0
    private var totalX: CGFloat = 0
    private var totalY: CGFloat = 0

    mutating func reset() {
        axis = .undecided
        pull = 0
        totalX = 0
        totalY = 0
    }

    mutating func observeAxis(deltaX: CGFloat, deltaY: CGFloat) {
        guard axis == .undecided else { return }
        totalX += abs(deltaX)
        totalY += abs(deltaY)
        guard max(totalX, totalY) >= Self.axisThreshold else { return }
        axis = totalX > totalY * 1.25 ? .horizontal : .vertical
    }

    mutating func contentCanScroll() { pull = 0 }

    mutating func addEdgeDelta(_ physicalDeltaX: CGFloat) {
        pull += physicalDeltaX
    }
}

@MainActor
final class WindowNavigationCoordinator: NSObject {
    private(set) weak var window: NSWindow?
    private var router: NavigationRouter?
    private var canNavigate: (() -> Bool)?
    private nonisolated(unsafe) var eventMonitor: Any?
    private var swipe = NavigationSwipeTracker()
    private weak var horizontalScrollView: NSScrollView?
    private var trackingGesture = false
    private var contentOwnsGesture = false

    func setup(router: NavigationRouter, canNavigate: @escaping () -> Bool) {
        self.router = router
        self.canNavigate = canNavigate
    }

    func attach(to window: NSWindow) {
        guard self.window !== window || eventMonitor == nil else { return }
        detach()
        self.window = window
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .otherMouseUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleEvent(event)
        }
    }

    func detach() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        window = nil
        resetGesture()
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    private func resetGesture() {
        swipe.reset()
        horizontalScrollView = nil
        trackingGesture = false
        contentOwnsGesture = false
    }

    @discardableResult
    func handleEvent(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        guard window.isKeyWindow, window.attachedSheet == nil,
              NSApp.modalWindow == nil, canNavigate?() == true else {
            resetGesture()
            return event
        }

        switch event.type {
        case .otherMouseUp:
            guard let router else { return event }
            switch event.buttonNumber {
            case 3:
                guard router.canGoBack else { return event }
                router.goBack()
                return nil
            case 4:
                guard router.canGoForward else { return event }
                router.goForward()
                return nil
            default:
                return event
            }
        case .scrollWheel:
            return handleScroll(event, in: window)
        default:
            return event
        }
    }

    private func handleScroll(_ event: NSEvent, in window: NSWindow) -> NSEvent? {
        guard event.hasPreciseScrollingDeltas, NSEvent.isSwipeTrackingFromScrollEventsEnabled else {
            resetGesture()
            return event
        }
        // Inertial scrolling must never start another navigation.
        if !event.momentumPhase.isEmpty { return event }

        if event.phase == .began || event.phase == .mayBegin {
            resetGesture()
            trackingGesture = true
            horizontalScrollView = findHorizontalScrollView(at: event.locationInWindow, in: window)
            if let root = window.contentView {
                contentOwnsGesture = HorizontalNavigationGestureRouting.contentOwnsGesture(
                    at: root.convert(event.locationInWindow, from: nil), in: root)
            }
        }

        if event.phase == .cancelled {
            resetGesture()
            return event
        }
        if event.phase == .ended {
            defer { resetGesture() }
            guard !contentOwnsGesture, trackingGesture, swipe.axis == .horizontal,
                  abs(swipe.pull) >= NavigationSwipeTracker.navigationThreshold,
                  let router else { return event }
            if swipe.pull > 0, router.canGoBack {
                router.goBack()
                return nil
            }
            if swipe.pull < 0, router.canGoForward {
                router.goForward()
                return nil
            }
            return event
        }

        // Some scroll views receive the first changed event without a separate began.
        // Start there as well, but never treat phase-less mouse wheel events as gestures.
        if !trackingGesture, event.phase == .changed {
            trackingGesture = true
            horizontalScrollView = findHorizontalScrollView(at: event.locationInWindow, in: window)
            if let root = window.contentView {
                contentOwnsGesture = HorizontalNavigationGestureRouting.contentOwnsGesture(
                    at: root.convert(event.locationInWindow, from: nil), in: root)
            }
        }
        guard trackingGesture, !contentOwnsGesture else { return event }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        swipe.observeAxis(deltaX: dx, deltaY: dy)
        guard swipe.axis == .horizontal else { return event }

        let physicalDX = event.isDirectionInvertedFromDevice ? dx : -dx
        guard abs(physicalDX) > 0.1, let router else { return event }
        let canNavigateDirection = physicalDX > 0 ? router.canGoBack : router.canGoForward
        guard canNavigateDirection else { return event }

        if let scrollView = horizontalScrollView,
           canScroll(scrollView, towardBack: physicalDX > 0) {
            swipe.contentCanScroll()
            return event
        }

        swipe.addEdgeDelta(physicalDX)
        // Consume only the overscroll. Vertical scroll events and useful horizontal
        // movement have already passed through to their native NSScrollView.
        return nil
    }

    private func findHorizontalScrollView(at point: NSPoint, in window: NSWindow) -> NSScrollView? {
        guard let contentView = window.contentView else { return nil }
        let pointInSuperview = contentView.superview?.convert(point, from: nil) ?? point
        var view = contentView.hitTest(pointInSuperview)
        while let current = view {
            if let scroll = current as? NSScrollView,
               scroll.horizontalScrollElasticity != .none,
               scroll.documentView != nil {
                return scroll
            }
            view = current.superview
        }
        return nil
    }

    private func canScroll(_ scroll: NSScrollView, towardBack: Bool) -> Bool {
        guard let document = scroll.documentView else { return false }
        let clip = scroll.contentView.bounds
        let documentWidth: CGFloat
        if let collection = document as? NSCollectionView,
           let layout = collection.collectionViewLayout {
            documentWidth = max(document.bounds.width, layout.collectionViewContentSize.width)
        } else {
            documentWidth = document.bounds.width
        }
        let maxX = max(0, documentWidth - clip.width)
        let tolerance: CGFloat = 2
        return towardBack ? clip.minX > tolerance : clip.minX < maxX - tolerance
    }
}

final class WindowNavigationHostingView: NSView {
    weak var coordinator: WindowNavigationCoordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { coordinator?.attach(to: window) }
        else { coordinator?.detach() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct WindowNavigationGestureBridge: NSViewRepresentable {
    let router: NavigationRouter
    let canNavigate: () -> Bool

    func makeCoordinator() -> WindowNavigationCoordinator { WindowNavigationCoordinator() }

    func makeNSView(context: Context) -> WindowNavigationHostingView {
        let view = WindowNavigationHostingView()
        view.coordinator = context.coordinator
        context.coordinator.setup(router: router, canNavigate: canNavigate)
        return view
    }

    func updateNSView(_ view: WindowNavigationHostingView, context: Context) {
        context.coordinator.setup(router: router, canNavigate: canNavigate)
    }

    static func dismantleNSView(_ view: WindowNavigationHostingView, coordinator: WindowNavigationCoordinator) {
        coordinator.detach()
    }
}
