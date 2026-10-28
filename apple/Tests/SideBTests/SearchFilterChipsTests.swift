import AppKit
import SwiftUI
import SideBCore
import XCTest
@testable import SideB

@MainActor final class SearchFilterChipsTests: XCTestCase {
    func testOverflowScrollsToLastCategoryAndResizeKeepsOneFixedHeightStrip() async throws {
        let titles = ["Songs", "Albums", "Videos", "Episodes", "Community playlists", "Artists", "Podcasts", "Profiles", "Featured playlists"]
        let chips = titles.enumerated().map { SearchChipRecord(id: "chip-\($0)", title: $1, params: "params-\($0)", selected: $0 == 0) }
        let host = NSHostingView(rootView: SearchFilterChips(chips: chips, onSelect: { _ in })
            .padding(.horizontal, 28).padding(.vertical, 16)
            .background(Color(red: 0.10, green: 0.10, blue: 0.12)).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: -2400, y: -1500, width: 700, height: 88),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        await settle(host)
        let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertEqual(scroll.frame.height, SideBControlMetrics.categoryHeight + 8, accuracy: 1)
        XCTAssertGreaterThan(document.bounds.width, scroll.contentView.bounds.width + 100)
        try capture(host, name: "overflow-leading")

        let end = document.bounds.maxX - scroll.contentView.bounds.width
        scroll.contentView.scroll(to: NSPoint(x: end, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle(host)
        XCTAssertGreaterThan(scroll.contentView.bounds.minX, 100)
        XCTAssertEqual(scroll.contentView.bounds.maxX, document.bounds.maxX, accuracy: 1)
        try capture(host, name: "overflow-trailing")

        window.setContentSize(NSSize(width: 1800, height: 88))
        await settle(host)
        XCTAssertEqual(scroll.frame.height, SideBControlMetrics.categoryHeight + 8, accuracy: 1)
        XCTAssertLessThanOrEqual(document.bounds.width, scroll.contentView.bounds.width + 1)
        try capture(host, name: "fitting")
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func settle(_ host: NSView) async {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
    private func capture(_ host: NSView, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["SIDEB_LAYOUT_REVIEW_DIR"] else { return }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("search-chips-\(name).png"))
    }
}
