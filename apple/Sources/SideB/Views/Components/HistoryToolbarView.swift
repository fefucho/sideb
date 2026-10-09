import AppKit
import SwiftUI

struct HistoryToolbarView: NSViewRepresentable {
    let router: NavigationRouter
    let isDisabled: Bool
    var isHomeSettingsPresented: Bool = false
    var onHomeSettings: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNativeContainer(coordinator: Coordinator, reduceTransparency: Bool) -> WindowAlignedToolbarContainer {
        let bar = NativeHistoryBar(target: coordinator)
        let surface = NavigationGlassSurface(content: bar)
        surface.update(reduceTransparency: reduceTransparency)
        coordinator.bar = bar
        coordinator.surface = surface
        coordinator.localizationObserver = AppKitLocalizationObserver { [weak bar] in
            bar?.updateLocalization()
        }
        coordinator.localizationObserver?.start()
        update(bar)
        return WindowAlignedToolbarContainer(contentView: surface, topInset: ShellLayout.navigationTopInset,
                                             trailingInset: ShellLayout.navigationTopInset)
    }

    func makeNSView(context: Context) -> WindowAlignedToolbarContainer {
        makeNativeContainer(coordinator: context.coordinator,
                            reduceTransparency: context.environment.accessibilityReduceTransparency)
    }

    func updateNativeContainer(_ view: WindowAlignedToolbarContainer, coordinator: Coordinator,
                               reduceTransparency: Bool) {
        coordinator.parent = self
        if let bar = coordinator.bar { update(bar) }
        coordinator.surface?.update(reduceTransparency: reduceTransparency)
        view.refreshNaturalSize()
    }

    func updateNSView(_ view: WindowAlignedToolbarContainer, context: Context) {
        updateNativeContainer(view, coordinator: context.coordinator,
                              reduceTransparency: context.environment.accessibilityReduceTransparency)
    }

    private func update(_ bar: NativeHistoryBar) {
        _ = L10n.revision
        bar.updateLocalization()
        let showsHomeActions = router.currentPage == .home && !isDisabled
        bar.update(showsRefresh: showsHomeActions, showsSettings: showsHomeActions,
                   isSettingsPresented: isHomeSettingsPresented, canGoBack: router.canGoBack,
                   canGoForward: router.canGoForward, isDisabled: isDisabled)
    }

    @MainActor final class Coordinator: NSObject {
        var parent: HistoryToolbarView
        weak var bar: NativeHistoryBar?
        weak var surface: NavigationGlassSurface?
        var localizationObserver: AppKitLocalizationObserver?
        init(_ parent: HistoryToolbarView) { self.parent = parent }
        @objc func refresh(_ sender: NSButton) {
            guard sender.isEnabled, !parent.isDisabled, parent.router.currentPage == .home else { return }
            parent.router.refreshHome()
        }
        @objc func back(_ sender: NSButton) {
            guard sender.isEnabled, !parent.isDisabled else { return }
            parent.router.goBack()
        }
        @objc func forward(_ sender: NSButton) {
            guard sender.isEnabled, !parent.isDisabled else { return }
            parent.router.goForward()
        }
        @objc func homeSettings(_ sender: NSButton) {
            guard sender.isEnabled, !parent.isDisabled, parent.router.currentPage == .home else { return }
            parent.onHomeSettings()
        }
    }
}

/// Fixed native geometry, independent of SwiftUI hosting-view fitting proposals.
final class NativeHistoryBar: NSView {
    let refresh = NSButton()
    let back = NSButton()
    let forward = NSButton()
    let settings = NSButton()
    private let divider = NSBox()
    private let settingsDivider = NSBox()
    private var showsRefresh = true
    private var showsSettings = true
    override var fittingSize: NSSize {
        NSSize(width: 62 + (showsRefresh ? 34 : 0) + (showsSettings ? 36 : 0), height: 34)
    }
    override var intrinsicContentSize: NSSize { fittingSize }

    init(target: HistoryToolbarView.Coordinator) {
        super.init(frame: NSRect(x: 0, y: 0, width: 132, height: 34))
        wantsLayer = true
        let specs: [(NSButton, String, String, String, Selector)] = [
            (refresh, "arrow.clockwise", "navigation.refresh", "r", #selector(HistoryToolbarView.Coordinator.refresh(_:))),
            (back, "chevron.left", "navigation.back", "[", #selector(HistoryToolbarView.Coordinator.back(_:))),
            (forward, "chevron.right", "navigation.forward", "]", #selector(HistoryToolbarView.Coordinator.forward(_:))),
            (settings, "gearshape", "navigation.home_settings", "", #selector(HistoryToolbarView.Coordinator.homeSettings(_:)))
        ]
        for (button, symbol, titleKey, key, action) in specs {
            let title = L10n.text(titleKey)
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.contentTintColor = .labelColor
            button.target = target
            button.action = action
            button.keyEquivalent = key
            button.keyEquivalentModifierMask = key.isEmpty ? [] : .command
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.wantsLayer = true
            addSubview(button)
        }
        divider.boxType = .separator
        divider.wantsLayer = true
        addSubview(divider)
        settingsDivider.boxType = .separator
        addSubview(settingsDivider)
        settings.layer?.cornerRadius = 7
        settings.setAccessibilityIdentifier("home-settings-toggle")
        updateLocalization()
        needsLayout = true
    }
    required init?(coder: NSCoder) { nil }

    func updateLocalization() {
        let labels: [(NSButton, String, String)] = [
            (refresh, "arrow.clockwise", "navigation.refresh"),
            (back, "chevron.left", "navigation.back"),
            (forward, "chevron.right", "navigation.forward"),
            (settings, "gearshape", "navigation.home_settings")
        ]
        for (button, symbol, key) in labels {
            let title = L10n.text(key)
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
            button.toolTip = title
            button.setAccessibilityLabel(title)
        }
    }

    func update(showsRefresh: Bool, showsSettings: Bool, isSettingsPresented: Bool,
                canGoBack: Bool, canGoForward: Bool, isDisabled: Bool) {
        if self.showsRefresh != showsRefresh || self.showsSettings != showsSettings {
            self.showsRefresh = showsRefresh
            self.showsSettings = showsSettings
            invalidateIntrinsicContentSize()
            superview?.invalidateIntrinsicContentSize()
            superview?.needsLayout = true
        }
        refresh.isHidden = !showsRefresh
        divider.isHidden = !showsRefresh
        settings.isHidden = !showsSettings
        settingsDivider.isHidden = !showsSettings
        refresh.isEnabled = showsRefresh && !isDisabled
        settings.isEnabled = showsSettings && !isDisabled
        settings.state = isSettingsPresented ? .on : .off
        settings.layer?.backgroundColor = isSettingsPresented
            ? NSColor.labelColor.withAlphaComponent(0.12).cgColor : nil
        settings.setAccessibilityValue(L10n.text(isSettingsPresented ? "navigation.open" : "navigation.closed"))
        back.isEnabled = canGoBack && !isDisabled
        forward.isEnabled = canGoForward && !isDisabled
        needsLayout = true
    }
    override func layout() {
        super.layout()
        refresh.frame = NSRect(x: 3, y: 3, width: 28, height: 28)
        divider.frame = NSRect(x: 34, y: 10, width: 1, height: 14)
        back.frame = NSRect(x: showsRefresh ? 38 : 3, y: 3, width: 28, height: 28)
        forward.frame = NSRect(x: showsRefresh ? 65 : 31, y: 3, width: 28, height: 28)
        settingsDivider.frame = NSRect(x: forward.frame.maxX + 3, y: 10, width: 1, height: 14)
        settings.frame = NSRect(x: forward.frame.maxX + 7, y: 3, width: 28, height: 28)
    }
}
