import AppKit
import SwiftUI

/// The sidebar and menu still share SwiftUI's animated progress; both navigation
/// groups now live in one native toolbar item and one coordinate system.
struct AnimatedWindowNavigationToolbarView: View, Animatable {
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
    let onLibrary: () -> Void
    let onSearch: () -> Void

    var animatableData: Double {
        get { revealProgress }
        set { revealProgress = newValue }
    }
    var body: some View {
        WindowNavigationToolbarView(
            navigation: TopNavigationView(selection: selection, isPresented: isPresented, reduceMotion: reduceMotion,
                                          revealProgress: revealProgress, onHome: onHome, onLibrary: onLibrary, onSearch: onSearch),
            history: HistoryToolbarView(router: router, isDisabled: isHistoryDisabled,
                                        isHomeSettingsPresented: isHomeSettingsPresented,
                                        onHomeSettings: onHomeSettings), showsHistory: showsHistory,
            viewportWidth: viewportWidth,
            onHistoryFrameChanged: onHistoryFrameChanged)
    }
}

struct WindowNavigationToolbarView: NSViewRepresentable {
    let navigation: TopNavigationView
    let history: HistoryToolbarView
    let showsHistory: Bool
    var viewportWidth: CGFloat = ShellLayout.navigationMinimumWidth
    var onHistoryFrameChanged: ((CGRect) -> Void)? = nil

    @MainActor final class Coordinator {
        let navigation: TopNavigationView.Coordinator
        let history: HistoryToolbarView.Coordinator
        init(_ parent: WindowNavigationToolbarView) {
            navigation = parent.navigation.makeCoordinator()
            history = parent.history.makeCoordinator()
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNativeHeader(coordinator: Coordinator, reduceTransparency: Bool) -> NativeNavigationHeader {
        let menu = navigation.makeNativeContainer(coordinator: coordinator.navigation, reduceTransparency: reduceTransparency)
        let actions = history.makeNativeContainer(coordinator: coordinator.history, reduceTransparency: reduceTransparency)
        actions.isHidden = !showsHistory
        coordinator.history.surface?.setEffectHidden(!showsHistory)
        let header = NativeNavigationHeader(menu: menu, history: actions)
        header.viewportWidth = viewportWidth
        header.onHistoryFrameChanged = onHistoryFrameChanged
        return header
    }
    func makeNSView(context: Context) -> NativeNavigationHeader {
        makeNativeHeader(coordinator: context.coordinator,
                         reduceTransparency: context.environment.accessibilityReduceTransparency)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NativeNavigationHeader, context: Context) -> CGSize? {
        // The toolbar's explicit viewport must reach the native view, not just an
        // outer SwiftUI frame around a narrower view with an intrinsic width.
        CGSize(width: max(ShellLayout.navigationMinimumWidth, proposal.width ?? viewportWidth),
               height: ShellLayout.toolbarHostHeight)
    }

    func updateNSView(_ header: NativeNavigationHeader, context: Context) {
        navigation.updateNativeContainer(header.navigationHost, coordinator: context.coordinator.navigation,
                                         reduceTransparency: context.environment.accessibilityReduceTransparency)
        history.updateNativeContainer(header.history, coordinator: context.coordinator.history,
                                      reduceTransparency: context.environment.accessibilityReduceTransparency)
        header.history.isHidden = !showsHistory
        header.viewportWidth = viewportWidth
        header.onHistoryFrameChanged = onHistoryFrameChanged
        context.coordinator.history.surface?.setEffectHidden(!showsHistory)
        header.needsLayout = true
        header.layoutSubtreeIfNeeded()
    }
}

final class NativeNavigationHeader: NSView {
    let navigationHost: WindowAlignedToolbarContainer
    let history: WindowAlignedToolbarContainer
    var viewportWidth: CGFloat = ShellLayout.navigationMinimumWidth {
        didSet {
            guard oldValue != viewportWidth else { return }
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }
    var onHistoryFrameChanged: ((CGRect) -> Void)?
    private var lastReportedHistoryFrame: CGRect?
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: max(ShellLayout.navigationMinimumWidth, viewportWidth), height: ShellLayout.toolbarHostHeight)
    }
    override var fittingSize: NSSize { intrinsicContentSize }

    init(menu: WindowAlignedToolbarContainer, history: WindowAlignedToolbarContainer) {
        self.navigationHost = menu
        self.history = history
        super.init(frame: NSRect(x: 0, y: 0, width: ShellLayout.navigationMinimumWidth,
                                height: ShellLayout.toolbarHostHeight))
        wantsLayer = true
        clipsToBounds = false
        menu.wantsLayer = true
        history.wantsLayer = true
        menu.usesWindowAlignment = false
        history.usesWindowAlignment = false
        addSubview(menu)
        addSubview(history)
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
    override func layout() {
        super.layout()
        var center = NSPoint(x: bounds.midX, y: ShellLayout.navigationRowCenter)
        var windowTop = bounds.minY
        var panelCenterX: CGFloat?
        if let content = window?.contentView {
            let top = content.isFlipped ? content.bounds.minY : content.bounds.maxY
            windowTop = convert(NSPoint(x: content.bounds.midX, y: top), from: content).y
            let y = content.isFlipped ? content.bounds.minY + ShellLayout.navigationRowCenter
                                     : content.bounds.maxY - ShellLayout.navigationRowCenter
            center = convert(NSPoint(x: content.bounds.midX, y: y), from: content)
            // Keep the actions over the panel's location even when it is closed.
            let panelCenterInContent = NSPoint(
                x: content.bounds.maxX - ShellLayout.sidebarInset - ShellLayout.homeSettingsWidth / 2,
                y: top
            )
            panelCenterX = convert(panelCenterInContent, from: content).x
        }
        let frames = ShellLayout.navigationFrames(bounds: bounds, menuSize: navigationHost.contentView.fittingSize,
                                                  historySize: history.contentView.fittingSize, requestedCenter: center,
                                                  historyCenterX: panelCenterX)
        if let surface = navigationHost.contentView as? NavigationGlassSurface {
            // The resting menu's lower edge must clear the actual window top,
            // including its shadow, before the menu is hidden at progress zero.
            navigationHost.presentationOffset = surface.presentationOffset(exitDistance: max(0, frames.menu.maxY - windowTop + 8))
        }
        navigationHost.frame = frames.menu.offsetBy(dx: 0, dy: navigationHost.presentationOffset)
        history.frame = frames.history
        navigationHost.bounds = NSRect(origin: .zero, size: frames.menu.size)
        history.bounds = NSRect(origin: .zero, size: frames.history.size)
        navigationHost.needsLayout = true
        history.needsLayout = true
        if onHistoryFrameChanged != nil, let frame = historyFrameInWindowTopDown(),
           lastReportedHistoryFrame.map({ !ShellLayout.sameControlFrame($0, frame) }) ?? true {
            lastReportedHistoryFrame = frame
            DispatchQueue.main.async { [weak self] in
                guard let self, let callback = self.onHistoryFrameChanged,
                      let latest = self.lastReportedHistoryFrame,
                      ShellLayout.sameControlFrame(latest, frame) else { return }
                callback(frame)
            }
        }
    }

    /// Full window-frame coordinates with a top-left origin, including the titlebar.
    private func historyFrameInWindowTopDown() -> CGRect? {
        guard let window else { return nil }
        let rectInWindowBase = history.convert(history.bounds, to: nil)
        let contentRect = window.contentRect(forFrameRect: window.frame)
        let leadingInset = contentRect.minX - window.frame.minX
        let topInset = window.frame.maxY - contentRect.maxY
        return CGRect(x: leadingInset + rectInWindowBase.minX,
                      y: topInset + contentRect.height - rectInWindowBase.maxY,
                      width: rectInWindowBase.width,
                      height: rectInWindowBase.height)
    }
}
