import AppKit
import SwiftUI

struct TopNavigationView: NSViewRepresentable {
    let selection: MainNavigationDestination
    let isPresented: Bool
    let reduceMotion: Bool
    var revealProgress: Double? = nil
    let onHome: () -> Void
    var onExplore: () -> Void = {}
    let onLibrary: () -> Void
    let onSearch: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WindowAlignedToolbarContainer {
        makeNativeContainer(coordinator: context.coordinator,
                            reduceTransparency: context.environment.accessibilityReduceTransparency)
    }

    func makeNativeContainer(coordinator: Coordinator, reduceTransparency: Bool) -> WindowAlignedToolbarContainer {
        let bar = NativeNavigationBar(target: coordinator, action: #selector(Coordinator.select(_:)))
        let surface = NavigationGlassSurface(content: bar)
        surface.update(reduceTransparency: reduceTransparency)
        coordinator.bar = bar
        coordinator.surface = surface
        bar.select(selection.index)
        let container = WindowAlignedToolbarContainer(contentView: surface, topInset: ShellLayout.navigationTopInset)
        coordinator.container = container
        coordinator.localizationObserver = AppKitLocalizationObserver { [weak coordinator] in
            coordinator?.bar?.updateLocalization()
        }
        coordinator.localizationObserver?.start()
        coordinator.setPresentation(progress: revealProgress ?? (isPresented ? 1 : 0), isPresented: isPresented, reduceMotion: reduceMotion)
        return container
    }

    func updateNSView(_ container: WindowAlignedToolbarContainer, context: Context) {
        updateNativeContainer(container, coordinator: context.coordinator,
                              reduceTransparency: context.environment.accessibilityReduceTransparency)
    }

    func updateNativeContainer(_ container: WindowAlignedToolbarContainer, coordinator: Coordinator,
                               reduceTransparency: Bool, updatesPresentation: Bool = true) {
        coordinator.parent = self
        coordinator.surface?.update(reduceTransparency: reduceTransparency)
        coordinator.bar?.updateLocalization()
        coordinator.bar?.select(selection.index)
        if updatesPresentation {
            coordinator.setPresentation(progress: revealProgress ?? (isPresented ? 1 : 0), isPresented: isPresented, reduceMotion: reduceMotion)
        }
    }

    final class Coordinator: NSObject {
        var parent: TopNavigationView
        weak var bar: NativeNavigationBar?
        weak var surface: NavigationGlassSurface?
        weak var container: WindowAlignedToolbarContainer?
        var localizationObserver: AppKitLocalizationObserver?
        private var presented = false
        private var lastPresentation: Presentation?
        private var lastClusterPresentation: Presentation?

        private struct Presentation: Equatable {
            let progress: Double
            let isPresented: Bool
            let reduceMotion: Bool
        }

        init(_ parent: TopNavigationView) { self.parent = parent }

        /// Fade the complete capsule, as in the three-block prototype. Changing
        /// the glass content's own visibility/opacity disrupts its native lens.
        func setClusterPresentation(progress: Double, isPresented: Bool) {
            let progress = max(0, min(1, progress))
            let next = Presentation(progress: progress, isPresented: isPresented, reduceMotion: true)
            guard next != lastClusterPresentation else { return }
            lastClusterPresentation = next
            presented = isPresented
            bar?.setInteractionEnabled(isPresented && progress > 0.95)
            // The standalone factory may have started with the sidebar open.
            // Restore its inner planes once; only the outer host fades/hides.
            surface?.isHidden = false
            surface?.setEffectHidden(false)
            surface?.setPresentation(progress: 1, reduceMotion: true)
            bar?.control.isHidden = false
            container?.alphaValue = progress
            container?.isHidden = progress <= 0.001
        }

        func setPresentation(progress: Double, isPresented: Bool, reduceMotion: Bool) {
            let progress = max(0, min(1, progress))
            let presentation = Presentation(progress: progress, isPresented: isPresented, reduceMotion: reduceMotion)
            guard presentation != lastPresentation else { return }
            lastPresentation = presentation
            presented = isPresented
            bar?.setInteractionEnabled(isPresented && progress > 0.95)
            let hidden = progress <= 0.001
            if container?.isHidden != hidden { container?.isHidden = hidden }
            if surface?.isHidden != hidden { surface?.isHidden = hidden }
            surface?.setEffectHidden(hidden)
            if bar?.control.isHidden != hidden { bar?.control.isHidden = hidden }
            // Slide the entire native surface; reduced motion uses one shared fade.
            surface?.setPresentation(progress: progress, reduceMotion: reduceMotion)
            if container?.usesWindowAlignment == false {
                // The shared header owns the exact exit distance in window coordinates.
                // Do not assign an approximate offset and then correct it during layout.
                container?.superview?.needsLayout = true
            } else {
                let distance = ShellLayout.navigationRowCenter + (surface?.fittingSize.height ?? ShellLayout.navigationSurfaceHeight) / 2 + 8
                container?.presentationOffset = surface?.presentationOffset(exitDistance: distance) ?? 0
            }
        }

        @objc func select(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard presented, bar?.control.isEnabled == true, index >= 0,
                  sender.isEnabled(forSegment: index) else { return }
            switch index {
            case 0: parent.onHome()
            case 1: parent.onExplore()
            case 2: parent.onLibrary()
            default: break
            }
        }
    }
}

private extension MainNavigationDestination {
    var index: Int {
        switch self {
        case .home: return 0
        case .explore: return 1
        case .library: return 2
        }
    }
}

/// AppKit owns the selection lens, pointer tracking, keyboard navigation and accessibility.
/// The fixed control frame defines three equal slots without a sizeToFit measurement.
final class NativeNavigationBar: NSView {
    static let preferredWidth: CGFloat = 246
    static let inset: CGFloat = 3
    static let segmentWidth: CGFloat = 80
    static let controlHeight: CGFloat = 36
    let control: NSSegmentedControl
    private let measuredSize: NSSize
    private let controlSize: NSSize
    private var localizationRevision: Int?
    private var sublayersObservation: NSKeyValueObservation?
    private weak var observedHostingView: NSView?
    private weak var observedHostingLayer: CALayer?
    private weak var suppressedLayer: CALayer?
    private var originalLayerOpacity: Float = 1

    init(target: AnyObject, action: Selector) {
        let titles = Self.localizedTitles
        let symbols = ["house", "sparkles", "books.vertical"]
        let images = zip(symbols, titles).map { symbol, title in
            NSImage(systemSymbolName: symbol, accessibilityDescription: title)!
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium))!
        }
        control = NSSegmentedControl(images: images, trackingMode: .selectOne, target: target, action: action)
        control.segmentStyle = .automatic
        control.segmentDistribution = .fillEqually
        if #available(macOS 26.0, *) {
            control.controlSize = .extraLarge
        } else {
            control.controlSize = .large
        }
        if #available(macOS 26.0, *) {
            control.borderShape = .capsule
        }
        if #available(macOS 27.0, *) { control.role = .tabs }
        for index in 0..<3 {
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
            control.setToolTip(titles[index], forSegment: index)
            control.setTag(index, forSegment: index)
        }
        control.setAccessibilityLabel(L10n.text("navigation.main"))
        // fillEqually distributes the 240pt frame. setWidth(80) instead requests
        // 80pt of native content per segment plus AppKit's padding (258pt total),
        // which pushes the end lenses beyond this frame and into the outer glass.
        let nativeSize = NSSize(width: Self.segmentWidth * 3, height: Self.controlHeight)
        control.frame.size = nativeSize
        controlSize = nativeSize
        measuredSize = NSSize(width: nativeSize.width + 2 * Self.inset,
                              height: nativeSize.height + 2 * Self.inset)
        super.init(frame: NSRect(origin: .zero, size: measuredSize))
        wantsLayer = true
        control.wantsLayer = true
        control.frame.origin = NSPoint(x: Self.inset, y: Self.inset)
        addSubview(control)
        if #available(macOS 26.0, *) { ensureTrackObservation() }
        localizationRevision = L10n.revision
    }

    private static var localizedTitles: [String] {
        [L10n.text("navigation.home"), L10n.text("navigation.explore"), L10n.text("navigation.library")]
    }

    func updateLocalization() {
        let revision = L10n.revision
        guard localizationRevision != revision else { return }
        localizationRevision = revision
        let titles = Self.localizedTitles
        let symbols = ["house", "sparkles", "books.vertical"]
        for index in 0..<3 {
            if let image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: titles[index])?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)) {
                control.setImage(image, forSegment: index)
            }
            control.setToolTip(titles[index], forSegment: index)
        }
        control.setAccessibilityLabel(L10n.text("navigation.main"))
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { measuredSize }
    override var fittingSize: NSSize { measuredSize }

    override func layout() {
        super.layout()
        // NSGlassEffectView owns its content's bounds. Recenter after each native
        // layout instead of relying on the frame assigned before attachment.
        control.frame = NSRect(x: bounds.midX - controlSize.width / 2,
                               y: bounds.midY - controlSize.height / 2,
                               width: controlSize.width, height: controlSize.height)
        if #available(macOS 26.0, *) {
            control.layoutSubtreeIfNeeded()
            ensureTrackObservation()
            hideMiddleTrack()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if #available(macOS 26.0, *) {
            ensureTrackObservation()
            hideMiddleTrack()
        }
    }

    @available(macOS 26.0, *)
    private func ensureTrackObservation() {
        let hostingView: NSView
        if let cached = observedHostingView,
           cached.superview === control,
           NSStringFromClass(type(of: cached)).contains("NSCoreHostingView") {
            hostingView = cached
        } else if let found = control.subviews.first(where: { NSStringFromClass(type(of: $0)).contains("NSCoreHostingView") }) {
            hostingView = found
            observedHostingView = found
        } else {
            observedHostingView = nil
            return
        }
        guard let hostingLayer = hostingView.layer else { return }
        observeSublayers(of: hostingLayer)
    }

    func observeSublayers(of hostingLayer: CALayer) {
        guard observedHostingLayer !== hostingLayer else { return }
        sublayersObservation?.invalidate()
        observedHostingLayer = hostingLayer
        sublayersObservation = hostingLayer.observe(\.sublayers, options: [.new, .initial]) { [weak self, weak hostingLayer] _, _ in
            let update = {
                guard let self, let hostingLayer, self.observedHostingLayer === hostingLayer else { return }
                self.hideMiddleTrack(in: hostingLayer)
            }
            if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
        }
    }

    @available(macOS 26.0, *)
    private func hideMiddleTrack() {
        guard let hostingLayer = observedHostingLayer else { return }
        hideMiddleTrack(in: hostingLayer)
    }

    func hideMiddleTrack(in hostingLayer: CALayer) {
        guard let rootTrack = hostingLayer.sublayers?.first else { return }
        let changedFirstLayer = suppressedLayer !== rootTrack
        guard changedFirstLayer || rootTrack.opacity != 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // AppKit may temporarily remove the track while rebuilding its layers.
        // Release our override if that temporary first layer becomes a sibling
        // again, otherwise the selection lens can remain invisible after KVO.
        if changedFirstLayer {
            if let previous = suppressedLayer, previous.superlayer === hostingLayer,
               previous.opacity == 0 {
                previous.opacity = originalLayerOpacity
            }
            suppressedLayer = rootTrack
            originalLayerOpacity = rootTrack.opacity
        }
        if rootTrack.opacity != 0 {
            originalLayerOpacity = rootTrack.opacity
            rootTrack.opacity = 0
        }
        CATransaction.commit()
    }

    func setInteractionEnabled(_ enabled: Bool) {
        guard control.isEnabled != enabled else { return }
        control.isEnabled = enabled
    }

    func select(_ index: Int) {
        guard (0..<3).contains(index), index != control.selectedSegment else { return }
        // Do not overlay or animate a separate lens: that belongs to the system control.
        control.selectedSegment = index
    }
}

/// The outer surface stays only three points from the selected capsule.
final class NavigationGlassSurface: NSView {
    private let content: NSView
    private var surfaceView: NSView?
    private var isUsingSolidSurface: Bool?
    private var effectHidden = false
    private var effectOpacity: CGFloat = 1
    private var presentationProgress: CGFloat = 1
    private var reducesPresentationMotion = false

    init(content: NSView) {
        self.content = content
        super.init(frame: NSRect(origin: .zero, size: content.fittingSize))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize {
        content.fittingSize
    }
    override var fittingSize: NSSize { intrinsicContentSize }

    func update(reduceTransparency: Bool) {
        guard isUsingSolidSurface != reduceTransparency else { return }
        isUsingSolidSurface = reduceTransparency
        surfaceView?.removeFromSuperview()
        let surface = makeSurface(reduceTransparency: reduceTransparency)
        surface.frame = bounds
        surface.isHidden = effectHidden
        surface.alphaValue = effectOpacity
        surface.autoresizingMask = [.width, .height]
        addSubview(surface)
        surfaceView = surface
        needsLayout = true
    }

    func setEffectHidden(_ hidden: Bool) {
        guard effectHidden != hidden else { return }
        effectHidden = hidden
        surfaceView?.isHidden = hidden
    }

    func setEffectOpacity(_ opacity: CGFloat) {
        guard effectOpacity != opacity else { return }
        effectOpacity = opacity
        surfaceView?.alphaValue = opacity
    }

    func setPresentation(progress: CGFloat, reduceMotion: Bool) {
        presentationProgress = progress
        reducesPresentationMotion = reduceMotion
        setEffectOpacity(reduceMotion ? progress : 1)
    }

    func presentationOffset(exitDistance: CGFloat) -> CGFloat {
        reducesPresentationMotion ? 0 : -exitDistance * (1 - presentationProgress)
    }

    override func layout() {
        super.layout()
        if surfaceView?.frame != bounds { surfaceView?.frame = bounds }
        // One full-size content plane for both native glass and its fallback.
        // The native bar centers its own control within that plane.
        if let surfaceView {
            if content.frame != surfaceView.bounds {
                content.frame = surfaceView.bounds
                content.needsLayout = true
            }
            if #available(macOS 26.0, *), let glass = surfaceView as? NSGlassEffectView {
                if glass.cornerRadius != bounds.height / 2 { glass.cornerRadius = bounds.height / 2 }
            } else if surfaceView.layer?.cornerRadius != bounds.height / 2 {
                surfaceView.layer?.cornerRadius = bounds.height / 2
            }
            surfaceView.layoutSubtreeIfNeeded()
        }
    }

    private func makeSurface(reduceTransparency: Bool) -> NSView {
        let surfaceHeight = fittingSize.height
        if reduceTransparency {
            let solid = NSView(frame: bounds)
            solid.wantsLayer = true
            solid.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            solid.layer?.cornerRadius = surfaceHeight / 2
            solid.layer?.masksToBounds = true
            solid.addSubview(content)
            content.frame = bounds
            return solid
        }
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .regular
            glass.cornerRadius = surfaceHeight / 2
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            glass.contentView = content
            return glass
        }
        let visualEffect = NSVisualEffectView(frame: bounds)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .followsWindowActiveState
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = surfaceHeight / 2
        visualEffect.layer?.masksToBounds = true
        visualEffect.addSubview(content)
        content.frame = bounds
        return visualEffect
    }
}
