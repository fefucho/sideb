import AppKit

protocol NativeFeaturedLayoutObserver: AnyObject {
    func featuredLayoutDidChange()
}

private final class PlayerTitleActionField: NativeTrackActionField, NativeFeaturedLayoutObserver {
    var layoutChanged: (() -> Void)?
    func featuredLayoutDidChange() { layoutChanged?() }
}

/// The cycle is independent of playback progress and preserves elapsed time while paused.
struct PlayerTitleMotionCycle {
    let overflow: CGFloat
    var travelDuration: Double { max(3.5, Double(overflow) / 24) }
    var duration: Double { 1 + travelDuration + 1.3 }
    func offset(at elapsed: Double) -> CGFloat {
        -overflow * CGFloat(min(1, max(0, (elapsed - 1) / travelDuration)))
    }
}

/// NSAnimation drives actual clip bounds, so drawing, pointer coordinates and AX frames agree.
private final class PlayerTitleAnimation: NSAnimation {
    var tick: ((Double) -> Void)?
    override var currentProgress: NSAnimation.Progress {
        get { super.currentProgress }
        set { super.currentProgress = newValue; tick?(Double(newValue)) }
    }
}

@MainActor final class NativePlayerTitleViewport: NSClipView, NSAnimationDelegate {
    private let titleField = PlayerTitleActionField(frame: .zero)
    var field: NativeTrackActionField { titleField }
    private var animation: PlayerTitleAnimation?
    private var observers: [NSObjectProtocol] = []
    private var hoverArea: NSTrackingArea?
    private var identity = ""
    private var enabled = false
    private var reduceMotion = false
    private var active = true
    private var hovering = false
    private var menuDepth = 0
    private var measuredSize = CGSize.zero
    private var measuredViewportWidth: CGFloat = 0
    private(set) var elapsed: Double = 0
    private(set) var overflow: CGFloat = 0
    var cycle: PlayerTitleMotionCycle { PlayerTitleMotionCycle(overflow: overflow) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        copiesOnScroll = false
        documentView = field
        titleField.layoutChanged = { [weak self] in self?.updateClippedLinks() }
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSWindow.didChangeOcclusionStateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshMotion() }
            })
        }
        // Menus track in a nested event loop. Keep the same position until tracking ends,
        // even when opening a credit menu causes the pointer to leave this viewport.
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; self.menuDepth += 1; self.refreshMotion() }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; self.menuDepth = max(0, self.menuDepth - 1); self.refreshMotion() }
        })
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    func configure(identity: String, enabled: Bool, reduceMotion: Bool, active: Bool) {
        let reset = self.identity != identity || self.enabled != enabled || self.reduceMotion != reduceMotion
        self.identity = identity; self.enabled = enabled; self.reduceMotion = reduceMotion; self.active = active
        if reset { resetCycle() }
        needsLayout = true
        layoutSubtreeIfNeeded()
        refreshMotion()
    }

    override func layout() {
        super.layout()
        // Measure the whole native line, including accents and emoji, using its actual font.
        let intrinsicWidth = ceil(field.intrinsicContentSize.width)
        let width = enabled && !reduceMotion ? max(bounds.width, intrinsicWidth) : bounds.width
        let size = CGSize(width: width, height: bounds.height)
        if size != measuredSize || bounds.width != measuredViewportWidth {
            measuredSize = size
            measuredViewportWidth = bounds.width
            resetCycle()
        }
        field.lineBreakMode = enabled && !reduceMotion ? .byClipping : .byTruncatingTail
        field.frame = CGRect(origin: .zero, size: size)
        overflow = max(0, width - bounds.width)
        field.layoutSubtreeIfNeeded()
        updateClippedLinks()
        refreshMotion()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    func setHovered(_ hovered: Bool) { hovering = hovered; refreshMotion() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshMotion() }
    override func viewDidHide() { super.viewDidHide(); refreshMotion() }
    override func viewDidUnhide() { super.viewDidUnhide(); refreshMotion() }
    override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }

    private var hasFocus: Bool {
        // become/resignFirstResponder callbacks run before NSWindow replaces its responder.
        field.subviews.compactMap { $0 as? NativeFeaturedArtistButton }.contains { $0.isLinkFocused }
    }
    func refreshMotion() {
        let shouldRun = enabled && !reduceMotion && overflow > 1 && active && !hovering && !hasFocus && menuDepth == 0
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
            && !isHiddenOrHasHiddenAncestor && NSApp.isActive
        guard shouldRun else { animation?.stop(); animation = nil; return }
        guard animation == nil else { return }
        let start = elapsed
        let remaining = max(0.001, cycle.duration - start)
        let next = PlayerTitleAnimation(duration: remaining, animationCurve: .linear)
        next.animationBlockingMode = .nonblocking
        next.delegate = self
        next.tick = { [weak self] progress in
            guard let self else { return }
            self.advance(to: start + remaining * progress)
        }
        animation = next
        next.start()
    }
    nonisolated func animationDidEnd(_ animation: NSAnimation) {
        // Nonblocking NSAnimation delivers its delegate callback on the starting main thread.
        MainActor.assumeIsolated {
            guard animation === self.animation else { return }
            self.animation = nil
            elapsed = 0; showOffset(0)
            refreshMotion()
        }
    }
    private func resetCycle() {
        animation?.stop(); animation = nil
        elapsed = 0; showOffset(0)
    }
    func advance(to elapsed: Double) {
        self.elapsed = elapsed
        showOffset(cycle.offset(at: elapsed))
    }
    /// Internal entry point also permits deterministic geometry checks without a running animation.
    func showOffset(_ offset: CGFloat) {
        scroll(to: NSPoint(x: -offset, y: 0))
        updateClippedLinks()
    }
    private func updateClippedLinks() {
        for button in field.subviews.compactMap({ $0 as? NativeFeaturedArtistButton }) {
            // Partially clipped names remain text; only fully visible names are actionable.
            button.isHidden = !active || !bounds.contains(convert(button.bounds, from: button))
        }
    }
    func tearDown() {
        animation?.stop(); animation = nil
        field.clearFeatured()
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
    }
}

extension NSView {
    func refreshPlayerTitleMotion() {
        var ancestor: NSView? = self
        while let current = ancestor {
            if let viewport = current as? NativePlayerTitleViewport { viewport.refreshMotion(); return }
            ancestor = current.superview
        }
    }
}
