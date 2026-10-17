import SwiftUI

private struct PageActivityKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var sideBPageIsActive: Bool {
        get { self[PageActivityKey.self] }
        set { self[PageActivityKey.self] = newValue }
    }
}

/// At most three primary pages per account. Details keep their existing lifecycle.
/// Each branch has a stable identity, even when a different page is selected.
struct RetainedMainPages<Home: View, Explore: View, Library: View, Detail: View>: View {
    let page: PageDestination
    var isCovered = false
    @ViewBuilder let home: () -> Home
    @ViewBuilder let explore: (ExploreRoute) -> Explore
    @ViewBuilder let library: () -> Library
    @ViewBuilder let detail: () -> Detail
    @State private var visitedExplore = false
    @State private var visitedLibrary = false
    @State private var exploreRoute: ExploreRoute = .discover

    private var isExplore: Bool { if case .explore = page { return true }; return false }
    private var currentExploreRoute: ExploreRoute {
        if case .explore(let route) = page { return route }
        return exploreRoute
    }
    private var isPrimary: Bool { page == .home || page == .library || isExplore }

    var body: some View {
        ZStack {
            RetainedPageViewport(isSelected: page == .home, isCovered: isCovered, content: home())
            if visitedExplore || isExplore {
                RetainedPageViewport(isSelected: isExplore, isCovered: isCovered,
                                     content: explore(currentExploreRoute))
            }
            if visitedLibrary || page == .library {
                RetainedPageViewport(isSelected: page == .library, isCovered: isCovered, content: library())
            }
            if !isPrimary {
                detail().environment(\.sideBPageIsActive, !isCovered)
            }
        }
        .onChange(of: page, initial: true) { _, page in
            if case .explore(let route) = page { visitedExplore = true; exploreRoute = route }
            if page == .library { visitedLibrary = true }
        }
    }
}

/// Freeze the hidden page's viewport as well as its activity. Resizing the shell
/// must not lay out all three retained documents or enlarge the window proposal.
private struct RetainedPageViewport<Content: View>: View {
    let isSelected: Bool
    let isCovered: Bool
    let content: Content
    var body: some View {
        // AppKit owns the hosted document's retained size. Feeding each native
        // resize back into State needlessly reconfigures the hosting boundary.
        RetainedPageContent(content: content, isSelected: isSelected,
                            accessibilityActive: isSelected && !isCovered)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.sideBPageIsActive, isSelected && !isCovered)
        .opacity(isSelected ? 1 : 0)
        .allowsHitTesting(isSelected && !isCovered)
        .disabled(!isSelected)
        .zIndex(isSelected ? 1 : 0)
        .clipped()
    }
}

/// Opacity/accessibilityHidden on a GeometryReader does not reliably remove
/// SwiftUI or representable descendants on macOS. Keep an explicit native
/// accessibility boundary without destroying the page's hosted view/state.
private struct RetainedPageContent<Content: View>: NSViewRepresentable {
    let content: Content
    let isSelected: Bool
    let accessibilityActive: Bool
    @Environment(\.sideBPageIsActive) private var pageIsActive
    @Environment(\.sideBGesturePreviewVisible) private var gesturePreviewVisible
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.sideBMenuContext) private var menuContext
    @Environment(\.collectionBackgroundController) private var collectionBackgroundController

    // Forward public page inputs, preserving the new hosting view's own
    // accessibility/layout context instead of copying SwiftUI's private keys.
    private var root: AnyView {
        AnyView(content
            .environment(\.sideBPageIsActive, pageIsActive)
            .environment(\.sideBGesturePreviewVisible, gesturePreviewVisible)
            .environment(\.scenePhase, scenePhase)
            .environment(\.colorScheme, colorScheme)
            .environment(\.locale, locale)
            .environment(\.layoutDirection, layoutDirection)
            .environment(\.isEnabled, isEnabled)
            .environment(\.sideBMenuContext, menuContext)
            .environment(\.collectionBackgroundController, collectionBackgroundController))
    }

    func makeNSView(context: Context) -> RetainedPageHostView {
        let view = RetainedPageHostView(rootView: root)
        view.isSelected = isSelected
        view.accessibilityActive = accessibilityActive
        return view
    }

    func updateNSView(_ view: RetainedPageHostView, context: Context) {
        view.hostedView.rootView = root
        view.isSelected = isSelected
        view.accessibilityActive = accessibilityActive
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RetainedPageHostView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 800, height: proposal.height ?? 600)
    }

    static func dismantleNSView(_ view: RetainedPageHostView, coordinator: ()) {
        view.accessibilityActive = false
        view.hostedView.rootView = AnyView(EmptyView())
    }
}

@MainActor final class RetainedPageHostView: NSView {
    let hostedView: NSHostingView<AnyView>
    var isSelected = true {
        didSet {
            guard oldValue != isSelected else { return }
            if isSelected { updateDocumentFrame() }
            isHidden = !isSelected
            needsLayout = true
        }
    }
    var accessibilityActive = true {
        didSet {
            guard oldValue != accessibilityActive else { return }
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
    }

    init(rootView: AnyView) {
        hostedView = NSHostingView(rootView: rootView)
        hostedView.sizingOptions = []
        hostedView.safeAreaRegions = [] // The shell/feed already applies the titlebar inset.
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        hostedView.setAccessibilityElement(true)
        hostedView.setAccessibilityRole(.group)
        hostedView.setAccessibilityParent(self)
        // The outer viewport always accepts the shell proposal. A hidden
        // document keeps its last frame without constraining that proposal.
        hostedView.autoresizingMask = []
        addSubview(hostedView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard isSelected else { return }
        updateDocumentFrame()
    }

    private func updateDocumentFrame() {
        if hostedView.frame != bounds { hostedView.frame = bounds }
    }

    override func accessibilityChildren() -> [Any]? {
        guard accessibilityActive && !isHidden else { return [] }
        return [hostedView]
    }
}
