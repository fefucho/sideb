import AppKit
import XCTest
@testable import SideB

@MainActor
final class NavigationPresentationPerformanceTests: XCTestCase {
    func testSemanticUpdatesKeepThreeNativeBlocksAndFixedHistoryGeometry() throws {
        let router = NavigationRouter()
        var events: [String] = []
        var view = toolbar(router: router, onHome: { events.append("initial") })
        let coordinator = view.makeCoordinator()
        let header = view.makeNativeHeader(coordinator: coordinator, reduceTransparency: true)
        header.frame.size.width = 900
        header.layoutSubtreeIfNeeded()

        let navigation = try XCTUnwrap(coordinator.navigation.bar)
        let history = try XCTUnwrap(coordinator.history.bar)
        let search = header.searchBar
        let navigationImages = (0..<3).map { navigation.control.image(forSegment: $0) }
        let backImage = history.back.image
        let forwardImage = history.forward.image
        let iconImage = search.iconButton.image
        let closeImage = search.closeButton.image
        let blocks = [ObjectIdentifier(navigation), ObjectIdentifier(history), ObjectIdentifier(search)]

        XCTAssertEqual(navigation.control.segmentCount, 3)
        XCTAssertEqual(history.fittingSize.width, 76)
        XCTAssertTrue(history.refresh.isHidden)
        XCTAssertTrue(history.settings.isHidden)
        XCTAssertNil(history.refresh.target)
        XCTAssertNil(history.refresh.action)
        XCTAssertNil(history.settings.target)
        XCTAssertNil(history.settings.action)

        for (sidebar, expanded) in [(false, true), (true, true), (true, false), (false, false), (false, true)] {
            history.needsLayout = false
            let query = expanded ? "Portishead" : ""
            view = toolbar(router: router, sidebar: sidebar, search: expanded, query: query,
                           onHome: { events.append("current") })
            view.updateNativeHeader(header, coordinator: coordinator, reduceTransparency: true)
            XCTAssertFalse(history.needsLayout, "Opening the search field must not reconfigure history")
            XCTAssertEqual(history.fittingSize.width, 76)
            XCTAssertEqual(header.searchProgress, expanded ? 1 : 0)
            XCTAssertEqual(header.sidebarProgress, sidebar ? 1 : 0)
            XCTAssertEqual(search.textField.stringValue, query)
            XCTAssertEqual([ObjectIdentifier(navigation), ObjectIdentifier(history), ObjectIdentifier(search)], blocks)
            for index in 0..<3 {
                XCTAssertTrue(navigation.control.image(forSegment: index) === navigationImages[index])
            }
            XCTAssertTrue(history.back.image === backImage)
            XCTAssertTrue(history.forward.image === forwardImage)
            XCTAssertTrue(search.iconButton.image === iconImage)
            XCTAssertTrue(search.closeButton.image === closeImage)
        }

        // Closing the search restores destination interaction and retains current callbacks.
        view = toolbar(router: router, onHome: { events.append("current") })
        view.updateNativeHeader(header, coordinator: coordinator, reduceTransparency: true)
        header.layoutSubtreeIfNeeded()
        navigation.control.selectedSegment = 0
        navigation.control.sendAction(try XCTUnwrap(navigation.control.action), to: navigation.control.target)
        XCTAssertEqual(events, ["current"])

        view = toolbar(router: router, onHome: { events.append("after-close") })
        view.updateNativeHeader(header, coordinator: coordinator, reduceTransparency: true)
        header.needsLayout = false
        view.updateNativeHeader(header, coordinator: coordinator, reduceTransparency: true)
        XCTAssertFalse(header.needsLayout, "An identical semantic presentation must not schedule layout")
        navigation.control.sendAction(try XCTUnwrap(navigation.control.action), to: navigation.control.target)
        XCTAssertEqual(events, ["current", "after-close"])
    }

    func testAttachedExpandedHeaderKeepsSelectionForIdenticalQueryAndUpdatedCallbacks() throws {
        let router = NavigationRouter()
        var view = toolbar(router: router, search: true, query: "Björk")
        let coordinator = view.makeCoordinator()
        let header = view.makeNativeHeader(coordinator: coordinator, reduceTransparency: true)
        header.frame.size.width = 900

        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 120),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView?.addSubview(header)
        header.layoutSubtreeIfNeeded()
        XCTAssertEqual(header.searchProgress, 1)
        XCTAssertEqual(header.searchHost.frame.width, 298, accuracy: 0.001)
        let editor = try XCTUnwrap(header.searchBar.textField.currentEditor() as? NSTextView)
        XCTAssertTrue(window.firstResponder === editor, "The already-expanded search field should focus when attached")
        editor.setSelectedRange(NSRange(location: 2, length: 1))
        let selection = editor.selectedRange()

        header.needsLayout = false
        view = toolbar(router: router, search: true, query: "Björk", onHome: {})
        view.updateNativeHeader(header, coordinator: coordinator, reduceTransparency: true)
        XCTAssertFalse(header.needsLayout, "Changing only callbacks with the same query must not schedule layout")
        XCTAssertEqual(header.searchProgress, 1)
        XCTAssertEqual(header.searchBar.textField.stringValue, "Björk")
        XCTAssertEqual(editor.selectedRange(), selection)
        XCTAssertEqual(header.history.frame.width, 76, accuracy: 0.001)
    }

    func testConfigurationIsCompleteAtMountAndLanguageUpdatesReuseNativeBlocks() throws {
        let previousLanguage = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previousLanguage) }
        AppLanguageStore.shared.setLanguage(.es)
        let router = NavigationRouter()
        let view = toolbar(router: router, settingsPresented: true)
        let coordinator = view.makeCoordinator()
        let header = view.makeNativeHeader(coordinator: coordinator, reduceTransparency: true)
        let navigation = try XCTUnwrap(coordinator.navigation.bar)
        let history = try XCTUnwrap(coordinator.history.bar)
        let blocks = [ObjectIdentifier(navigation), ObjectIdentifier(history), ObjectIdentifier(header.searchBar)]

        XCTAssertEqual(navigation.control.segmentCount, 3)
        for index in 0..<3 { XCTAssertNotNil(navigation.control.image(forSegment: index)) }
        XCTAssertEqual(history.fittingSize.width, 76)
        XCTAssertNotNil(history.back.image)
        XCTAssertNotNil(history.forward.image)
        XCTAssertNotNil(history.refresh.accessibilityLabel())
        XCTAssertNotNil(history.settings.accessibilityLabel())
        XCTAssertNotNil(history.back.toolTip)
        XCTAssertTrue(history.refresh.isHidden)
        XCTAssertTrue(history.settings.isHidden)
        XCTAssertNil(history.settings.target)
        XCTAssertNil(history.settings.action)
        XCTAssertEqual(history.back.keyEquivalent, "[")
        XCTAssertEqual(history.back.keyEquivalentModifierMask, .command)
        XCTAssertEqual(history.back.accessibilityLabel(), L10n.text("navigation.back"))

        AppLanguageStore.shared.setLanguage(.en)
        view.updateNativeHeader(header, coordinator: coordinator, reduceTransparency: true)
        XCTAssertEqual(navigation.control.toolTip(forSegment: 0), "Home")
        XCTAssertEqual(navigation.control.accessibilityLabel(), L10n.text("navigation.main"))
        XCTAssertEqual(history.back.accessibilityLabel(), L10n.text("navigation.back"))
        XCTAssertEqual(header.searchBar.textField.placeholderString, L10n.text("search.spotlight.placeholder"))
        XCTAssertEqual([ObjectIdentifier(navigation), ObjectIdentifier(history), ObjectIdentifier(header.searchBar)], blocks)
    }

    func testEmbeddedOffsetDoesNotRelayoutStableNativeContent() {
        let content = LayoutCountingContent()
        let container = WindowAlignedToolbarContainer(contentView: content)
        container.usesWindowAlignment = false
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 72))
        parent.addSubview(container)
        container.frame = CGRect(origin: .zero, size: content.fittingSize)
        container.layoutSubtreeIfNeeded()
        container.needsLayout = false
        parent.needsLayout = false
        content.needsLayout = false
        content.layoutCount = 0
        let originalFrame = content.frame

        container.presentationOffset = -20
        XCTAssertTrue(parent.needsLayout)
        XCTAssertFalse(container.needsLayout, "The header moves the embedded container; its content size remains unchanged")
        XCTAssertFalse(content.needsLayout)
        XCTAssertEqual(content.frame, originalFrame)

        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(content.layoutCount, 0, "An unchanged embedded frame must not invalidate its content")
        XCTAssertEqual(content.frame, originalFrame)
    }

    func testSurfaceReplacementPreservesHiddenAndReducedMotionOpacityAtIdenticalProgress() throws {
        for progress in [0.0, 0.5, 1.0] {
            let view = TopNavigationView(selection: .home, isPresented: progress == 1,
                                         reduceMotion: true, revealProgress: progress,
                                         onHome: {}, onLibrary: {}, onSearch: {})
            let coordinator = view.makeCoordinator()
            let container = view.makeNativeContainer(coordinator: coordinator, reduceTransparency: true)
            let surface = try XCTUnwrap(coordinator.surface)
            let initialEffect = try XCTUnwrap(surface.subviews.first)
            view.updateNativeContainer(container, coordinator: coordinator, reduceTransparency: false)
            let replacementEffect = try XCTUnwrap(surface.subviews.first)
            XCTAssertFalse(initialEffect === replacementEffect)
            XCTAssertEqual(replacementEffect.isHidden, progress == 0)
            XCTAssertEqual(replacementEffect.alphaValue, progress, accuracy: 0.001)
            XCTAssertEqual(container.isHidden, progress == 0)
            XCTAssertEqual(container.presentationOffset, 0)
        }
    }

    private func toolbar(router: NavigationRouter, sidebar: Bool = false, search: Bool = false,
                         query: String = "", focusRevision: Int = 0, settingsPresented: Bool = false,
                         onHome: @escaping () -> Void = {}) -> WindowNavigationToolbarView {
        WindowNavigationToolbarView(
            navigation: TopNavigationView(selection: .home, isPresented: !sidebar && !search,
                                          reduceMotion: false, revealProgress: 1,
                                          onHome: onHome, onExplore: {}, onLibrary: {}, onSearch: {}),
            history: HistoryToolbarView(router: router, isDisabled: false,
                                        isHomeSettingsPresented: settingsPresented),
            showsHistory: true, viewportWidth: 900, isSidebarExpanded: sidebar,
            isSearchExpanded: search, searchQuery: query, searchFocusRevision: focusRevision)
    }
}

@MainActor
private final class LayoutCountingContent: NSView {
    var layoutCount = 0
    override var fittingSize: NSSize { NSSize(width: 262, height: 34) }
    override func layout() {
        super.layout()
        layoutCount += 1
    }
}
