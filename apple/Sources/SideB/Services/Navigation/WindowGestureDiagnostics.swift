import AppKit

/// Opt-in geometry evidence for isolated lab bundles. Never logs account data,
/// destination titles, queries, track IDs or continuous production input.
@MainActor
enum WindowGestureDiagnostics {
    static let enabled = HomeLabConfiguration.enabled &&
        Bundle.main.object(forInfoDictionaryKey: "SideBGestureDiagnostics") as? Bool == true

    static func record(window: NSWindow, fullscreen: Bool, isHome: Bool) {
        guard enabled, let root = window.contentView else { return }
        let bounds = root.bounds
        let points = [0.1, 0.35, 0.6, 0.9].flatMap { x in
            [0.1, 0.3, 0.55, 0.8].map { y -> [String: Any] in
                let point = NSPoint(x: bounds.minX + bounds.width * x, y: bounds.minY + bounds.height * y)
                let route = WindowGestureRegions.routing(at: point, in: root, includeNativeFallback: !fullscreen)
                let homeOwner = isHome && !fullscreen &&
                    HorizontalNavigationGestureRouting.contentOwnsGesture(at: point, in: root)
                return ["x": point.x, "y": point.y, "content": route.isInContent,
                        "excluded": route.isExcluded, "horizontal": route.ownsHorizontal,
                        "vertical": route.ownsVertical, "homeOwner": homeOwner,
                        "history": !fullscreen && route.allowsHistory && !homeOwner,
                        "dismissal": route.allowsFullscreenDismissal]
            }
        }
        let markers = descendants(root).compactMap { view -> [String: Any]? in
            guard let marker = view as? WindowGestureRegionView else { return nil }
            let rect = marker.convert(marker.bounds, to: root)
            return ["region": String(describing: marker.region), "active": marker.isRegionActive,
                    "hidden": marker.isHidden, "x": rect.minX, "y": rect.minY,
                    "width": rect.width, "height": rect.height]
        }
        let record: [String: Any] = ["fullscreen": fullscreen, "home": isHome, "width": bounds.width,
                                   "height": bounds.height, "points": points, "markers": markers]
        guard var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("gesture-routing.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        } else if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
