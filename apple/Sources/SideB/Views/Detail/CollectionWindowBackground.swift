import AppKit
import SwiftUI

private struct CollectionBackgroundControllerKey: EnvironmentKey {
    static let defaultValue: CollectionBackgroundController? = nil
}

extension EnvironmentValues {
    var collectionBackgroundController: CollectionBackgroundController? {
        get { self[CollectionBackgroundControllerKey.self] }
        set { self[CollectionBackgroundControllerKey.self] = newValue }
    }
}

/// A single background belongs to the window, while the native table supplies
/// its scroll geometry. Scroll events move an AppKit view without updating the feed.
@MainActor
final class CollectionBackgroundController {
    private final class Source {
        let identity: String
        weak var document: NSView?
        var headerHeight: CGFloat
        var content: (Bool) -> AnyView
        let revision: UInt64

        init(identity: String, document: NSView, headerHeight: CGFloat, revision: UInt64, content: @escaping (Bool) -> AnyView) {
            self.identity = identity
            self.document = document
            self.headerHeight = headerHeight
            self.content = content
            self.revision = revision
        }
    }

    private weak var canvas: CollectionBackgroundCanvas?
    private var sources: [UUID: Source] = [:]
    private var revision: UInt64 = 0
    private var identity: String?
    private var enabled = true
    private var reduceMotion = false
    private var scenePhase: ScenePhase = .active
    private var displayedOwner: UUID?
    private var visible: Bool?
    private(set) var host: CollectionBackgroundHostingView?

    func attach(_ canvas: CollectionBackgroundCanvas) {
        self.canvas = canvas
        canvas.controller = self
        updateGeometry(refreshContent: true)
    }

    func detach(_ canvas: CollectionBackgroundCanvas) {
        guard self.canvas === canvas else { return }
        clearHost()
        self.canvas = nil
    }

    func activate(identity: String?, enabled: Bool, reduceMotion: Bool, scenePhase: ScenePhase) {
        let changed = self.identity != identity || self.enabled != enabled ||
            self.reduceMotion != reduceMotion || self.scenePhase != scenePhase
        if self.identity != identity { clearHost() }
        self.identity = identity
        self.enabled = enabled
        self.reduceMotion = reduceMotion
        self.scenePhase = scenePhase
        updateGeometry(refreshContent: changed)
    }

    func register(owner: UUID, identity: String, document: NSView, headerHeight: CGFloat,
                  content: @escaping (Bool) -> AnyView) {
        // Registration may precede the shell's update during navigation. Keep
        // candidates, but only the active page/account can supply the backdrop.
        revision &+= 1
        sources[owner] = Source(identity: identity, document: document, headerHeight: headerHeight,
                                revision: revision, content: content)
        updateGeometry(refreshContent: true)
    }

    func unregister(owner: UUID) {
        sources.removeValue(forKey: owner)
        if displayedOwner == owner { clearHost() }
        updateGeometry()
    }

    func updateGeometry(refreshContent: Bool = false) {
        guard let canvas, let identity,
              let (owner, source) = sources.filter({
                  $0.value.identity == identity && $0.value.document?.window != nil &&
                      $0.value.document?.window === canvas.window
              }).max(by: { $0.value.revision < $1.value.revision }),
              let document = source.document, let scroll = document.enclosingScrollView else {
            clearHost()
            return
        }

        let viewport = canvas.convert(scroll.contentView.bounds, from: scroll.contentView)
        let offset = scroll.contentView.bounds.minY - document.bounds.minY
        let frame = Self.frame(canvas: canvas.bounds, viewport: viewport, headerHeight: source.headerHeight,
                               scrollOffset: offset)
        let isVisible = enabled && frame.intersects(canvas.bounds)
        if displayedOwner != owner { clearHost() }
        if host == nil {
            let created = CollectionBackgroundHostingView(rootView: hostedContent(source, visible: isVisible))
            created.setAccessibilityElement(false)
            host = created
            displayedOwner = owner
            canvas.addSubview(created)
        }
        guard let host else { return }
        if host.frame != frame { host.frame = frame }
        host.isHidden = !enabled
        if refreshContent || visible != isVisible {
            host.rootView = hostedContent(source, visible: isVisible)
        }
        visible = isVisible
    }

    /// Top clearance applies to foreground only. The color starts at the window's
    /// top edge and spans its full width, including the space behind the sidebar.
    static func frame(canvas: NSRect, viewport: NSRect, headerHeight: CGFloat, scrollOffset: CGFloat) -> NSRect {
        let topClearance = max(0, viewport.minY - canvas.minY)
        let overscroll = max(0, -scrollOffset)
        return NSRect(x: canvas.minX, y: canvas.minY - max(0, scrollOffset), width: canvas.width,
                      height: max(1, headerHeight) + 140 + topClearance + overscroll)
    }

    private func hostedContent(_ source: Source, visible: Bool) -> AnyView {
        AnyView(source.content(visible)
            .environment(\.collectionAmbientActivity,
                         CollectionAmbientActivity(reduceMotion: reduceMotion, isActive: scenePhase == .active)))
    }

    private func clearHost() {
        host?.removeFromSuperview()
        host = nil
        displayedOwner = nil
        visible = nil
    }
}

struct CollectionWindowBackground: NSViewRepresentable {
    let controller: CollectionBackgroundController
    let identity: String?
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func makeNSView(context: Context) -> CollectionBackgroundCanvas {
        let canvas = CollectionBackgroundCanvas()
        canvas.wantsLayer = true
        canvas.layer?.masksToBounds = true
        canvas.setAccessibilityElement(false)
        controller.activate(identity: identity, enabled: enabled, reduceMotion: reduceMotion, scenePhase: scenePhase)
        controller.attach(canvas)
        return canvas
    }

    func updateNSView(_ canvas: CollectionBackgroundCanvas, context: Context) {
        controller.activate(identity: identity, enabled: enabled, reduceMotion: reduceMotion, scenePhase: scenePhase)
    }

    static func dismantleNSView(_ canvas: CollectionBackgroundCanvas, coordinator: ()) {
        canvas.controller?.detach(canvas)
    }
}

final class CollectionBackgroundCanvas: NSView {
    weak var controller: CollectionBackgroundController?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        controller?.updateGeometry()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        controller?.updateGeometry()
    }
}
