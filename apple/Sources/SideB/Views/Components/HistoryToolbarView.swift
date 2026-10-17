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
        let previousSize = view.contentView.fittingSize
        if let bar = coordinator.bar { update(bar) }
        coordinator.surface?.update(reduceTransparency: reduceTransparency)
        view.refreshNaturalSize()
        if view.contentView.fittingSize != previousSize {
            view.superview?.needsLayout = true
        }
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
    private var localizationRevision: Int?
    private var configuration: Configuration?

    private struct Configuration: Equatable {
        let showsRefresh: Bool
        let showsSettings: Bool
        let isSettingsPresented: Bool
        let canGoBack: Bool
        let canGoForward: Bool
        let isDisabled: Bool
    }

    override var fittingSize: NSSize {
        NSSize(width: ShellLayout.historySurfaceWidth, height: ShellLayout.navigationSurfaceHeight)
    }
    override var intrinsicContentSize: NSSize { fittingSize }

    init(target: HistoryToolbarView.Coordinator) {
        super.init(frame: NSRect(x: 0, y: 0, width: ShellLayout.historySurfaceWidth,
                                 height: ShellLayout.navigationSurfaceHeight))
        wantsLayer = true
        let specs: [(NSButton, String, Selector)] = [
            (refresh, "r", #selector(HistoryToolbarView.Coordinator.refresh(_:))),
            (back, "[", #selector(HistoryToolbarView.Coordinator.back(_:))),
            (forward, "]", #selector(HistoryToolbarView.Coordinator.forward(_:))),
            (settings, "", #selector(HistoryToolbarView.Coordinator.homeSettings(_:)))
        ]
        for (button, key, action) in specs {
            // Images and translated accessibility text are configured together below.
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.contentTintColor = .labelColor
            button.target = target
            button.action = action
            button.keyEquivalent = key
            button.keyEquivalentModifierMask = key.isEmpty ? [] : .command
            button.wantsLayer = true
            addSubview(button)
        }
        // Contextual refresh and Home settings remain API-compatible but are not part of this surface.
        refresh.target = nil
        refresh.action = nil
        refresh.keyEquivalent = ""
        settings.target = nil
        settings.action = nil
        settings.keyEquivalent = ""
        refresh.isHidden = true
        refresh.setAccessibilityElement(false)
        settings.isHidden = true
        settings.setAccessibilityElement(false)
        divider.boxType = .separator
        divider.wantsLayer = true
        divider.isHidden = false
        addSubview(divider)
        settingsDivider.boxType = .separator
        settingsDivider.isHidden = true
        addSubview(settingsDivider)
        settings.layer?.cornerRadius = 7
        settings.setAccessibilityIdentifier("home-settings-toggle")
        updateLocalization()
        needsLayout = true
    }
    required init?(coder: NSCoder) { nil }

    func updateLocalization() {
        let revision = L10n.revision
        guard localizationRevision != revision else { return }
        localizationRevision = revision
        let labels: [(NSButton, String, String)] = [
            (refresh, "arrow.clockwise", "navigation.refresh"),
            (back, "chevron.left", "navigation.back"),
            (forward, "chevron.right", "navigation.forward"),
            (settings, "gearshape", "navigation.home_settings")
        ]
        for (button, symbol, key) in labels {
            let title = L10n.text(key)
            let isHistoryControl = button === back || button === forward
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(
                    pointSize: isHistoryControl ? 15 : 13,
                    weight: isHistoryControl ? .semibold : .medium
                ))
            button.toolTip = title
            button.setAccessibilityLabel(title)
        }
        updateSettingsAccessibilityValue()
    }

    func update(showsRefresh: Bool, showsSettings: Bool, isSettingsPresented: Bool,
                canGoBack: Bool, canGoForward: Bool, isDisabled: Bool) {
        let next = Configuration(showsRefresh: showsRefresh, showsSettings: showsSettings,
                                 isSettingsPresented: isSettingsPresented, canGoBack: canGoBack,
                                 canGoForward: canGoForward, isDisabled: isDisabled)
        guard configuration != next else { return }
        let settingsChanged = configuration?.isSettingsPresented != isSettingsPresented
        configuration = next
        refresh.isHidden = true
        settings.isHidden = true
        refresh.setAccessibilityElement(false)
        settings.setAccessibilityElement(false)
        refresh.isEnabled = false
        settings.isEnabled = false
        if settingsChanged {
            settings.state = isSettingsPresented ? .on : .off
            updateSettingsAppearance()
            updateSettingsAccessibilityValue()
        }
        back.isEnabled = canGoBack && !isDisabled
        forward.isEnabled = canGoForward && !isDisabled
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSettingsAppearance()
    }

    private func updateSettingsAppearance() {
        settings.layer?.backgroundColor = configuration?.isSettingsPresented == true
            ? NSColor.labelColor.withAlphaComponent(0.12).cgColor : nil
    }

    private func updateSettingsAccessibilityValue() {
        settings.setAccessibilityValue(L10n.text(configuration?.isSettingsPresented == true
                                                ? "navigation.open" : "navigation.closed"))
    }

    override func layout() {
        super.layout()
        refresh.frame = .zero
        divider.frame = .zero
        settings.frame = .zero
        settingsDivider.frame = .zero
        back.frame = NSRect(x: 3, y: 3, width: 34, height: 36)
        forward.frame = NSRect(x: 39, y: 3, width: 34, height: 36)
        divider.frame = NSRect(x: 37.5, y: 13, width: 1, height: 16)
    }
}
