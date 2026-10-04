import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let isFullscreenPresented: Bool
    @Binding var titlebarHeight: CGFloat
    var onContentWidthChange: ((CGFloat) -> Void)? = nil

    func makeNSView(context: Context) -> WindowConfigurationView { WindowConfigurationView() }

    func updateNSView(_ nsView: WindowConfigurationView, context: Context) {
        nsView.onTitlebarHeightChange = { titlebarHeight = $0 }
        nsView.onContentWidthChange = onContentWidthChange
        nsView.setFullscreenPresented(isFullscreenPresented)
    }

    static func dismantleNSView(_ nsView: WindowConfigurationView, coordinator: ()) {
        nsView.detach()
    }
}

final class WindowConfigurationView: NSView {
    var onTitlebarHeightChange: ((CGFloat) -> Void)?
    var onContentWidthChange: ((CGFloat) -> Void)?
    private var reportedContentWidth: CGFloat?
    private var reportedTitlebarHeight: CGFloat?
    private var fullscreenPresented = false
    private var enteringSystemFullscreen = false
    private var configurationPending = false
    private var observers: [NSObjectProtocol] = []

    private final class ButtonPlacement {
        weak var button: NSButton?
        weak var parent: NSView?
        var original: CGRect
        var applied: CGRect?
        init(button: NSButton, parent: NSView) {
            self.button = button
            self.parent = parent
            original = button.frame
        }
    }
    private var placements: [ButtonPlacement] = []

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { detach() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        for name in [NSWindow.didResizeNotification, NSWindow.didUpdateNotification,
                     NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                guard let self else { return }
                if notification.name == NSWindow.willEnterFullScreenNotification { self.enteringSystemFullscreen = true }
                if notification.name == NSWindow.didExitFullScreenNotification { self.enteringSystemFullscreen = false }
                self.scheduleConfiguration()
            })
        }
        scheduleConfiguration()
    }

    override func layout() {
        super.layout()
        scheduleConfiguration()
    }

    func setFullscreenPresented(_ fullscreen: Bool) {
        guard fullscreenPresented != fullscreen else { return }
        fullscreenPresented = fullscreen
        scheduleConfiguration()
    }

    func detach() {
        restoreControls()
        placements.removeAll()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        enteringSystemFullscreen = false
    }

    private func restoreControls() {
        for placement in placements {
            guard let button = placement.button, button.superview === placement.parent else { continue }
            // A new native layout takes precedence over our cached position.
            if let applied = placement.applied, ShellLayout.sameControlFrame(button.frame, applied) { button.frame = placement.original }
            placement.applied = nil
        }
    }

    private func alignControls(in window: NSWindow, contentView: NSView) {
        guard !enteringSystemFullscreen,
              !window.styleMask.contains(.fullScreen) else {
            restoreControls()
            return
        }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard buttons.count == 3, buttons.allSatisfy({ !$0.isHiddenOrHasHiddenAncestor && $0.superview != nil }) else {
            restoreControls()
            return
        }
        if placements.count != buttons.count || zip(placements, buttons).contains(where: { $0.0.button !== $0.1 || $0.0.parent !== $0.1.superview }) {
            restoreControls()
            placements = buttons.map { ButtonPlacement(button: $0, parent: $0.superview!) }
        }
        for placement in placements {
            guard let button = placement.button else { continue }
            if placement.applied.map({ !ShellLayout.sameControlFrame(button.frame, $0) }) ?? true {
                placement.original = button.frame
                placement.applied = nil
            }
        }
        guard let closeParent = placements.first?.parent, let close = placements.first else { return }
        let originalClose = contentView.convert(close.original, from: closeParent)
        let offset = ShellLayout.controlsOffset(closeRect: originalClose, bounds: contentView.bounds, isFlipped: contentView.isFlipped)
        var targetFrames: [CGRect] = []
        for placement in placements {
            guard let parent = placement.parent else { restoreControls(); return }
            let original = contentView.convert(placement.original, from: parent)
            let shifted = ShellLayout.translatedControl(original, offset: offset, isFlipped: contentView.isFlipped)
            let target = parent.convert(shifted, from: contentView)
            guard parent.bounds.contains(target) else { restoreControls(); return }
            targetFrames.append(target)
        }
        for (placement, target) in zip(placements, targetFrames) {
            if let button = placement.button, !ShellLayout.sameControlFrame(button.frame, target) { button.frame = target }
            placement.applied = target
        }
    }

    private func reportTitlebarHeight(in window: NSWindow, contentView: NSView) {
        guard !contentView.bounds.isEmpty else { return }
        let layoutRect = contentView.convert(window.contentLayoutRect, from: nil)
        var controlsRect: CGRect?
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(kind), !button.isHiddenOrHasHiddenAncestor else { continue }
            let rect = contentView.convert(button.bounds, from: button)
            controlsRect = controlsRect.map { $0.union(rect) } ?? rect
        }
        let height = ShellLayout.topClearance(bounds: contentView.bounds, contentLayoutRect: layoutRect,
                                             windowControlsRect: controlsRect, isFlipped: contentView.isFlipped)
        guard reportedTitlebarHeight != height else { return }
        reportedTitlebarHeight = height
        DispatchQueue.main.async { [weak self] in
            guard let self, self.reportedTitlebarHeight == height else { return }
            self.onTitlebarHeightChange?(height)
        }
    }

    private func scheduleConfiguration() {
        guard window != nil, !configurationPending else { return }
        configurationPending = true
        // Reconcile after native layout, coalescing resize/update notifications.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.configurationPending = false
            guard let window = self.window, let contentView = window.contentView else { return }
            if window.isOpaque { window.isOpaque = false }
            if window.backgroundColor != .clear { window.backgroundColor = .clear }
            if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
            if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
            if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
            if window.toolbar?.showsBaselineSeparator == true { window.toolbar?.showsBaselineSeparator = false }
            if window.toolbarStyle != .unifiedCompact { window.toolbarStyle = .unifiedCompact }
            self.alignControls(in: window, contentView: contentView)
            self.reportTitlebarHeight(in: window, contentView: contentView)
            let width = contentView.bounds.width
            if width > 0, self.reportedContentWidth.map({ abs($0 - width) > 0.5 }) ?? true {
                self.reportedContentWidth = width
                self.onContentWidthChange?(width)
            }
        }
    }
}
