import AppKit
import SwiftUI

/// Places a search preview in the enclosing scroll view's document without
/// reserving space for it in the SwiftUI or native table layout.
struct SearchPagePreviewAnchor: NSViewRepresentable {
    var content: AnyView?
    var gap: CGFloat = 8
    var onDismiss: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> SearchPagePreviewAnchorView {
        let view = SearchPagePreviewAnchorView(frame: .zero)
        view.onMoveToWindow = { [weak coordinator = context.coordinator] in
            coordinator?.reconcileAttachment()
        }
        return view
    }

    func updateNSView(_ view: SearchPagePreviewAnchorView, context: Context) {
        context.coordinator.update(parent: self, anchor: view)
    }

    static func dismantleNSView(_ view: SearchPagePreviewAnchorView, coordinator: Coordinator) {
        coordinator.dismantle()
        view.onMoveToWindow = nil
    }

    @MainActor final class Coordinator {
        private var parent: SearchPagePreviewAnchor
        private weak var anchor: SearchPagePreviewAnchorView?
        private weak var document: NSView?
        private var host: NSHostingView<AnyView>?
        private var generation: UInt64 = 0
        private var measuredHeight: CGFloat = 0
        private var frameObservers: [NSObjectProtocol] = []
        private var observedAncestors: [ObjectIdentifier] = []
        private var outsideClickMonitor: Any?

        var hostForTesting: NSHostingView<AnyView>? { host }
        var documentForTesting: NSView? { document }
        var isMonitoringOutsideClicksForTesting: Bool { outsideClickMonitor != nil }

        init(parent: SearchPagePreviewAnchor) {
            self.parent = parent
        }

        func update(parent: SearchPagePreviewAnchor, anchor: SearchPagePreviewAnchorView) {
            self.parent = parent
            self.anchor = anchor
            generation &+= 1
            measuredHeight = 0
            guard parent.content != nil else {
                removeHost()
                return
            }
            reconcileAttachment()
        }

        func reconcileAttachment() {
            guard let anchor, anchor.window != nil,
                  let targetDocument = anchor.enclosingScrollView?.documentView else {
                removeHost()
                return
            }
            if document !== targetDocument {
                removeHost()
                document = targetDocument
            }
            guard parent.content != nil else { return }
            if host == nil {
                let newHost = NSHostingView(rootView: AnyView(EmptyView()))
                newHost.identifier = NSUserInterfaceItemIdentifier("search-page-preview")
                newHost.sizingOptions = [.intrinsicContentSize]
                newHost.safeAreaRegions = []
                newHost.setAccessibilityElement(false)
                host = newHost
                targetDocument.addSubview(newHost, positioned: .above, relativeTo: nil)
            }
            startOutsideClickMonitor()
            observeAnchorFrames()
            updateHostedContent()
        }

        private func observeAnchorFrames() {
            var views: [NSView] = []
            var current: NSView? = anchor
            while let view = current, view !== document {
                views.append(view)
                current = view.superview
            }
            let identities = views.map(ObjectIdentifier.init)
            guard identities != observedAncestors else { return }
            clearFrameObservers()
            observedAncestors = identities
            for view in views {
                view.postsFrameChangedNotifications = true
                frameObservers.append(NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: view, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let anchor = self.anchor, let host = self.host else { return }
                        if abs(host.frame.width - anchor.bounds.width) > 0.5 {
                            self.generation &+= 1
                            self.updateHostedContent()
                        } else { self.layoutHost() }
                    }
                })
            }
        }

        private func clearFrameObservers() {
            for token in frameObservers { NotificationCenter.default.removeObserver(token) }
            frameObservers.removeAll()
            observedAncestors.removeAll()
        }

        private func startOutsideClickMonitor() {
            guard outsideClickMonitor == nil else { return }
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                _ = MainActor.assumeIsolated {
                    self?.handleMouseDown(window: event.window, locationInWindow: event.locationInWindow)
                }
                return event
            }
        }

        private func stopOutsideClickMonitor() {
            if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
            outsideClickMonitor = nil
        }

        @discardableResult
        func handleMouseDown(window: NSWindow?, locationInWindow: NSPoint) -> Bool {
            guard let anchor, let owningWindow = anchor.window, window === owningWindow,
                  let host, parent.content != nil else { return false }
            let pointInAnchor = anchor.convert(locationInWindow, from: nil)
            let pointInHost = host.convert(locationInWindow, from: nil)
            guard !anchor.bounds.contains(pointInAnchor), !host.bounds.contains(pointInHost) else { return false }
            stopOutsideClickMonitor()
            parent.onDismiss()
            return true
        }

        private func updateHostedContent() {
            guard let anchor, let document, let host, let content = parent.content else { return }
            let currentGeneration = generation
            let width = max(1, anchor.bounds.width)
            host.rootView = AnyView(content
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: .topLeading)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: SearchPagePreviewHeightPreference.self, value: geometry.size.height)
                    }
                }
                .onPreferenceChange(SearchPagePreviewHeightPreference.self) { [weak self] height in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == currentGeneration,
                              height.isFinite, height > 0,
                              abs(self.measuredHeight - ceil(height)) > 0.5 else { return }
                        self.measuredHeight = ceil(height)
                        self.layoutHost()
                    }
                })
            host.layoutSubtreeIfNeeded()
            let intrinsicHeight = host.fittingSize.height
            if intrinsicHeight.isFinite, intrinsicHeight > 0 {
                measuredHeight = ceil(intrinsicHeight)
            }
            if host.superview !== document {
                host.removeFromSuperview()
                document.addSubview(host, positioned: .above, relativeTo: nil)
            }
            layoutHost()
        }

        private func layoutHost() {
            guard let anchor, let document, let host, parent.content != nil else { return }
            let size = NSSize(width: max(1, anchor.bounds.width), height: max(1, measuredHeight))
            let anchorBottomLocal = NSPoint(x: anchor.bounds.minX, y: anchor.isFlipped ? anchor.bounds.maxY : anchor.bounds.minY)
            let bottom = anchor.convert(anchorBottomLocal, to: document)
            let y = document.isFlipped ? bottom.y + parent.gap : bottom.y - parent.gap - size.height
            let frame = NSRect(origin: NSPoint(x: bottom.x, y: y), size: size)
            if host.frame != frame { host.frame = frame }
        }

        private func removeHost() {
            generation &+= 1
            stopOutsideClickMonitor()
            clearFrameObservers()
            host?.removeFromSuperview()
            host = nil
            document = nil
            measuredHeight = 0
        }

        func dismantle() {
            generation &+= 1
            removeHost()
            anchor = nil
        }
    }
}

@MainActor final class SearchPagePreviewAnchorView: NSView {
    var onMoveToWindow: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onMoveToWindow?()
    }
}

private struct SearchPagePreviewHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
