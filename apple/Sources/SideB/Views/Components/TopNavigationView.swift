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
                               reduceTransparency: Bool) {
        coordinator.parent = self
        coordinator.surface?.update(reduceTransparency: reduceTransparency)
        coordinator.bar?.updateLocalization()
        coordinator.bar?.select(selection.index)
        coordinator.setPresentation(progress: revealProgress ?? (isPresented ? 1 : 0), isPresented: isPresented, reduceMotion: reduceMotion)
    }

    final class Coordinator: NSObject {
        var parent: TopNavigationView
        weak var bar: NativeNavigationBar?
        weak var surface: NavigationGlassSurface?
        weak var container: WindowAlignedToolbarContainer?
        var localizationObserver: AppKitLocalizationObserver?
        private var presented = false

        init(_ parent: TopNavigationView) { self.parent = parent }

        func setPresentation(progress: Double, isPresented: Bool, reduceMotion: Bool) {
            let progress = max(0, min(1, progress))
            presented = isPresented
            bar?.setInteractionEnabled(isPresented && progress > 0.95)
            let hidden = progress <= 0.001
            container?.isHidden = hidden
            surface?.isHidden = hidden
            surface?.setEffectHidden(hidden)
            bar?.control.isHidden = hidden
            // Slide the entire native surface; reduced motion uses one shared fade.
            container?.alphaValue = 1
            surface?.alphaValue = 1
            bar?.control.alphaValue = 1
            surface?.setPresentation(progress: progress, reduceMotion: reduceMotion)
            let distance = ShellLayout.navigationRowCenter + (surface?.fittingSize.height ?? ShellLayout.navigationSurfaceHeight) / 2 + 8
            container?.presentationOffset = surface?.presentationOffset(exitDistance: distance) ?? 0
        }

        @objc func select(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard presented, bar?.control.isEnabled == true, index >= 0,
                  sender.isEnabled(forSegment: index) else { return }
            switch index {
            case 0: parent.onHome()
            case 1: parent.onExplore()
            case 2: parent.onLibrary()
            case 3: parent.onSearch()
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
        case .search: return 3
        }
    }
}

/// AppKit owns the selection lens, pointer tracking, keyboard navigation and accessibility.
/// Measure the actual cell; enlarging only its frame does not enlarge its native bezel.
final class NativeNavigationBar: NSView {
    static let preferredWidth: CGFloat = 262
    static let inset: CGFloat = 3
    let control: NSSegmentedControl
    private let measuredSize: NSSize
    private let controlSize: NSSize

    init(target: AnyObject, action: Selector) {
        let titles = Self.localizedTitles
        let symbols = ["house", "sparkles", "books.vertical", "magnifyingglass"]
        let images = zip(symbols, titles).map { symbol, title in
            NSImage(systemSymbolName: symbol, accessibilityDescription: title)!
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))!
        }
        control = NSSegmentedControl(images: images, trackingMode: .selectOne, target: target, action: action)
        control.segmentStyle = .automatic
        control.segmentDistribution = .fillEqually
        control.controlSize = .large
        if #available(macOS 26.0, *) {
            control.borderShape = .capsule
        }
        if #available(macOS 27.0, *) { control.role = .tabs }
        for index in 0..<4 {
            control.setWidth(64, forSegment: index)
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
            control.setToolTip(titles[index], forSegment: index)
            control.setTag(index, forSegment: index)
        }
        control.setAccessibilityLabel(L10n.text("navigation.main"))
        control.sizeToFit()
        // Account for AppKit's own horizontal padding instead of scaling the control.
        let adjustment = (control.frame.width - (Self.preferredWidth - 2 * Self.inset)) / 4
        for index in 0..<4 { control.setWidth(64 - adjustment, forSegment: index) }
        control.sizeToFit()
        let nativeSize = control.frame.size
        controlSize = nativeSize
        measuredSize = NSSize(width: nativeSize.width + 2 * Self.inset,
                              height: nativeSize.height + 2 * Self.inset)
        super.init(frame: NSRect(origin: .zero, size: measuredSize))
        wantsLayer = true
        control.wantsLayer = true
        control.frame.origin = NSPoint(x: Self.inset, y: Self.inset)
        addSubview(control)
    }

    private static var localizedTitles: [String] {
        [L10n.text("navigation.home"), L10n.text("navigation.explore"),
         L10n.text("navigation.library"), L10n.text("navigation.search")]
    }

    func updateLocalization() {
        let titles = Self.localizedTitles
        let symbols = ["house", "sparkles", "books.vertical", "magnifyingglass"]
        for index in 0..<4 {
            if let image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: titles[index])?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)) {
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
    }

    func setInteractionEnabled(_ enabled: Bool) {
        control.isEnabled = enabled
    }

    func select(_ index: Int) {
        guard (0..<4).contains(index), index != control.selectedSegment else { return }
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
        effectHidden = hidden
        surfaceView?.isHidden = hidden
    }

    func setEffectOpacity(_ opacity: CGFloat) {
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
        surfaceView?.frame = bounds
        // One full-size content plane for both native glass and its fallback.
        // The native bar centers its own control within that plane.
        if let surfaceView {
            content.frame = surfaceView.bounds
            if #available(macOS 26.0, *), let glass = surfaceView as? NSGlassEffectView {
                glass.cornerRadius = bounds.height / 2
            } else {
                surfaceView.layer?.cornerRadius = bounds.height / 2
            }
        }
        content.needsLayout = true
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
