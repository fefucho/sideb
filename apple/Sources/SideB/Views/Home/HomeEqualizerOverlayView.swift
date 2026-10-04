import AppKit
import QuartzCore

/// Indicador de fuente de reproducción con animaciones de capas; no analiza el audio.
final class HomeEqualizerOverlayView: NSView {
    private let scrimLayer = CALayer()
    private var barLayers: [CALayer] = []
    private var isAnimating = false
    private var isCompact = false
    private var wantsPlaying = false
    private var isPaused = false
    private var indicatorSuppressed = false
    private var motionEnabled = true
    private var feedVisible = true
    private var occlusionObserver: NSObjectProtocol?
    private var activationObservers: [NSObjectProtocol] = []

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true

        guard let root = layer else { return }
        root.masksToBounds = true

        scrimLayer.backgroundColor = NSColor.black.withAlphaComponent(0.13).cgColor
        root.addSublayer(scrimLayer)

        setupBars(compact: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        activationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeActivityObservers()
        refreshPlaybackPresentation()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // La animación es puramente visual; todos los clics y hovers deben pasar a los controles
        nil
    }

    func setCornerRadius(_ radius: CGFloat) {
        layer?.cornerRadius = radius
        scrimLayer.cornerRadius = radius
    }

    func updateStyle(compact: Bool) {
        guard compact != isCompact else { return }
        isCompact = compact
        setupBars(compact: compact)
        layoutBars()
        if isAnimating {
            applyAnimations()
        }
    }

    func setMotionEnabled(_ enabled: Bool) {
        guard motionEnabled != enabled else { return }
        motionEnabled = enabled
        refreshPlaybackPresentation()
    }

    func setFeedVisible(_ visible: Bool) {
        guard feedVisible != visible else { return }
        feedVisible = visible
        refreshPlaybackPresentation()
    }

    func setIndicatorSuppressed(_ suppressed: Bool) {
        guard indicatorSuppressed != suppressed else { return }
        indicatorSuppressed = suppressed
        refreshPlaybackPresentation()
    }

    private func setupBars(compact: Bool) {
        barLayers.forEach { $0.removeFromSuperlayer() }
        barLayers.removeAll()

        let count = compact ? 4 : 5
        let barColor = NSColor.white.withAlphaComponent(0.82).cgColor

        for _ in 0..<count {
            let bar = CALayer()
            bar.backgroundColor = barColor
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(bar)
            barLayers.append(bar)
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrimLayer.frame = bounds
        layoutBars()
        CATransaction.commit()
    }

    private func layoutBars() {
        guard !barLayers.isEmpty, bounds.width > 0, bounds.height > 0 else { return }

        let count = CGFloat(barLayers.count)
        let barWidth: CGFloat = isCompact ? 2.5 : 3.5
        let barSpacing: CGFloat = isCompact ? 2.0 : 3.0
        let totalWidth = (count * barWidth) + ((count - 1) * barSpacing)
        let startX = (bounds.width - totalWidth) / 2.0
        let centerY = bounds.height / 2.0
        let maxHeight: CGFloat = isCompact ? 14.0 : min(34.0, bounds.height * 0.30)
        let cornerRadius = barWidth / 2.0

        for (index, bar) in barLayers.enumerated() {
            let x = startX + CGFloat(index) * (barWidth + barSpacing)
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: maxHeight)
            bar.position = CGPoint(x: x + barWidth / 2.0, y: centerY)
            bar.cornerRadius = cornerRadius
        }
    }

    func startAnimating() {
        wantsPlaying = true
        isPaused = false
        refreshPlaybackPresentation()
    }

    func pauseAnimation() {
        wantsPlaying = true
        isPaused = true
        isAnimating = false
        isHidden = !feedVisible || indicatorSuppressed
        resetLayerTiming()
        barLayers.forEach { $0.removeAllAnimations() }
        setStaticBars(dimmed: true)
    }

    private func resetLayerTiming() {
        guard let root = layer else { return }
        root.speed = 1.0
        root.timeOffset = 0.0
        root.beginTime = 0.0
    }

    func stopAnimating() {
        wantsPlaying = false
        isPaused = false
        isAnimating = false
        isHidden = true
        removeActivityObservers()
        resetLayerTiming()
        barLayers.forEach { $0.removeAllAnimations() }
    }

    private func applyAnimations() {
        guard !barLayers.isEmpty else { return }

        // Variaciones asimétricas orgánicas para simular un ecualizador musical vivo
        let profiles: [(duration: Double, keyframes: [Double])] = [
            (1.48, [0.48, 0.70, 0.52, 0.82, 0.55, 0.48]),
            (1.72, [0.58, 0.44, 0.73, 0.50, 0.76, 0.58]),
            (1.58, [0.42, 0.76, 0.50, 0.70, 0.48, 0.42]),
            (1.84, [0.66, 0.48, 0.82, 0.53, 0.72, 0.66]),
            (1.64, [0.46, 0.69, 0.43, 0.75, 0.52, 0.46]),
            (1.78, [0.54, 0.78, 0.48, 0.80, 0.58, 0.54])
        ]

        let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)

        for (index, bar) in barLayers.enumerated() {
            bar.removeAllAnimations()
            bar.opacity = 0.82
            bar.transform = CATransform3DIdentity
            let profile = profiles[index % profiles.count]

            let anim = CAKeyframeAnimation(keyPath: "transform.scale.y")
            anim.values = profile.keyframes
            anim.duration = profile.duration
            anim.repeatCount = .infinity
            anim.autoreverses = true
            anim.timingFunction = easeInOut
            anim.isRemovedOnCompletion = false

            bar.add(anim, forKey: "equalizerBounce")
        }
    }

    private func refreshPlaybackPresentation() {
        guard wantsPlaying else {
            isHidden = true
            removeActivityObservers()
            return
        }
        guard !indicatorSuppressed else {
            isAnimating = false
            resetLayerTiming()
            barLayers.forEach { $0.removeAllAnimations() }
            isHidden = true
            removeActivityObservers()
            return
        }
        guard feedVisible else {
            isAnimating = false
            resetLayerTiming()
            barLayers.forEach { $0.removeAllAnimations() }
            isHidden = true
            removeActivityObservers()
            return
        }
        guard let window else {
            isAnimating = false
            isHidden = false
            resetLayerTiming()
            barLayers.forEach { $0.removeAllAnimations() }
            setStaticBars(dimmed: isPaused)
            removeActivityObservers()
            return
        }
        installActivityObserversIfNeeded()
        let canAnimate = !isPaused && window.occlusionState.contains(.visible) && NSApp.isActive && motionEnabled &&
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        isHidden = !feedVisible
        if canAnimate {
            guard !isAnimating else { return }
            isAnimating = true
            resetLayerTiming()
            applyAnimations()
        } else if isAnimating || barLayers.contains(where: { $0.animation(forKey: "equalizerBounce") != nil }) {
            isAnimating = false
            resetLayerTiming()
            barLayers.forEach { $0.removeAllAnimations() }
            setStaticBars(dimmed: isPaused)
        } else if isPaused {
            setStaticBars(dimmed: true)
        } else {
            setStaticBars(dimmed: false)
        }
    }

    private func installActivityObserversIfNeeded() {
        if occlusionObserver == nil, let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshPlaybackPresentation() }
            }
        }
        if activationObservers.isEmpty {
            let center = NotificationCenter.default
            activationObservers = [NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification].map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.refreshPlaybackPresentation() }
                }
            }
        }
    }

    private func removeActivityObservers() {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        activationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        activationObservers.removeAll()
    }

    private func setStaticBars(dimmed: Bool) {
        let heights: [CGFloat] = [0.42, 0.72, 0.5, 0.84, 0.56]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            bar.opacity = dimmed ? 0.40 : 0.82
            bar.transform = CATransform3DMakeScale(1, heights[index % heights.count], 1)
        }
        CATransaction.commit()
    }
}
