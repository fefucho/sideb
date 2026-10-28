import AppKit
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class SearchPagePreviewAnchorTests: XCTestCase {
    func testOutsideClickDismissesButPreservesInteriorAndOtherWindowEventsAndCleansMonitor() async throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 420))
        let document = PreviewFixtureDocument(frame: NSRect(x: 0, y: 0, width: 520, height: 1_200))
        scroll.documentView = document
        let header = NSView(frame: NSRect(x: 24, y: 24, width: 320, height: 44))
        let anchor = SearchPagePreviewAnchorView(frame: header.bounds)
        header.addSubview(anchor)
        document.addSubview(header)
        let window = NSWindow(contentRect: NSRect(x: -1800, y: -1200, width: 520, height: 420),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }

        let otherWindow = NSWindow(contentRect: NSRect(x: -1200, y: -1200, width: 300, height: 200),
            styleMask: .borderless, backing: .buffered, defer: false)
        otherWindow.isReleasedWhenClosed = false
        defer { otherWindow.close() }
        var dismissals = 0
        let spec = SearchPagePreviewAnchor(content: AnyView(Button("Suggestion", action: {}).frame(width: 320, height: 52)),
            onDismiss: { dismissals += 1 })
        let coordinator = spec.makeCoordinator()
        defer { coordinator.dismantle() }
        coordinator.update(parent: spec, anchor: anchor)
        await settleHosting()

        XCTAssertTrue(coordinator.isMonitoringOutsideClicksForTesting)
        let anchorPoint = anchor.convert(NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: nil)
        XCTAssertFalse(coordinator.handleMouseDown(window: window, locationInWindow: anchorPoint))
        let host = try XCTUnwrap(coordinator.hostForTesting)
        let previewPoint = host.convert(NSPoint(x: host.bounds.midX, y: host.bounds.midY), to: nil)
        XCTAssertFalse(coordinator.handleMouseDown(window: window, locationInWindow: previewPoint))
        XCTAssertFalse(coordinator.handleMouseDown(window: otherWindow, locationInWindow: NSPoint(x: 20, y: 20)))
        XCTAssertEqual(dismissals, 0)

        XCTAssertTrue(coordinator.handleMouseDown(window: window, locationInWindow: NSPoint(x: 500, y: 400)))
        XCTAssertEqual(dismissals, 1)
        XCTAssertFalse(coordinator.isMonitoringOutsideClicksForTesting)

        coordinator.update(parent: SearchPagePreviewAnchor(content: nil), anchor: anchor)
        XCTAssertNil(coordinator.hostForTesting)
        XCTAssertFalse(coordinator.isMonitoringOutsideClicksForTesting)
    }

    func testPreviewIsPlacedBelowAnchorInNonFlippedDocument() async throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 420))
        let document = PreviewFixtureDocument(frame: NSRect(x: 0, y: 0, width: 520, height: 1_200), usesFlippedCoordinates: false)
        scroll.documentView = document
        let header = NSView(frame: NSRect(x: 24, y: 1_100, width: 320, height: 44))
        let anchor = SearchPagePreviewAnchorView(frame: header.bounds)
        header.addSubview(anchor)
        document.addSubview(header)

        let window = NSWindow(contentRect: NSRect(x: -1800, y: -1200, width: 520, height: 420),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 760))
        scroll.reflectScrolledClipView(scroll.contentView)

        let spec = SearchPagePreviewAnchor(content: AnyView(Button("Suggestion") {}.frame(width: 320, height: 52)))
        let coordinator = spec.makeCoordinator()
        defer { coordinator.dismantle() }
        coordinator.update(parent: spec, anchor: anchor)
        await settleHosting()

        let host = try XCTUnwrap(coordinator.hostForTesting)
        XCTAssertFalse(document.isFlipped)
        XCTAssertEqual(host.frame.maxY, header.frame.minY - 8, accuracy: 0.5)
        let target = host.convert(NSPoint(x: host.bounds.midX, y: host.bounds.midY), to: document)
        let hit = try XCTUnwrap(document.hitTest(target))
        XCTAssertTrue(hit === host || hit.isDescendant(of: host))
    }

    func testPreviewOverlaysRowsWithoutChangingDocumentLayoutAndCleansUp() async throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 420))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let document = PreviewFixtureDocument(frame: NSRect(x: 0, y: 0, width: 520, height: 1_200))
        scroll.documentView = document
        let header = NSView(frame: NSRect(x: 24, y: 24, width: 320, height: 44))
        let anchor = SearchPagePreviewAnchorView(frame: header.bounds)
        header.addSubview(anchor)
        document.addSubview(header)

        let table = NSTableView(frame: NSRect(x: 0, y: 100, width: 520, height: 1_050))
        table.headerView = nil
        table.rowHeight = 42
        table.intercellSpacing = .zero
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("preview-test"))
        column.width = 520
        table.addTableColumn(column)
        let source = PreviewRowsSource(count: 24)
        table.dataSource = source
        document.addSubview(table)
        table.reloadData()

        let window = NSWindow(contentRect: NSRect(x: -1800, y: -1200, width: 520, height: 420),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        scroll.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()

        let closed = SearchPagePreviewAnchor(content: nil)
        let coordinator = closed.makeCoordinator()
        defer { coordinator.dismantle(); table.dataSource = nil }
        coordinator.update(parent: closed, anchor: anchor)
        XCTAssertNil(coordinator.hostForTesting)

        let rowFramesBefore = (0..<table.numberOfRows).map { table.rect(ofRow: $0) }
        let headerFrameBefore = header.frame
        let panelContent = AnyView(Button("Open suggestion") {}
            .accessibilityIdentifier("preview-suggestion")
            .frame(width: 320, height: 52, alignment: .leading))
        let open = SearchPagePreviewAnchor(content: panelContent)
        coordinator.update(parent: open, anchor: anchor)
        await settleHosting()

        let host = try XCTUnwrap(coordinator.hostForTesting)
        XCTAssertTrue(host.superview === document)
        XCTAssertEqual(host.frame.minX, header.frame.minX, accuracy: 0.5)
        XCTAssertEqual(host.frame.minY, header.frame.maxY + 8, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(host.frame.height, 52)
        XCTAssertEqual(header.frame, headerFrameBefore)
        XCTAssertEqual((0..<table.numberOfRows).map { table.rect(ofRow: $0) }, rowFramesBefore)

        header.frame.origin.x += 44
        anchor.frame.size.width = 240
        await settleHosting()
        XCTAssertEqual(host.frame.minX, header.frame.minX, accuracy: 0.5,
            "A native ancestor can move without rebuilding the SwiftUI search field")
        XCTAssertEqual(host.frame.width, 240, accuracy: 0.5)
        header.frame = headerFrameBefore
        anchor.frame = header.bounds
        await settleHosting()

        let scrollY = CGFloat(36)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scrollY))
        scroll.reflectScrolledClipView(scroll.contentView)
        let offsetBeforeUpdate = scroll.contentView.bounds.origin
        let updated = SearchPagePreviewAnchor(content: AnyView(
            Button("Updated suggestion") {}
                .accessibilityIdentifier("preview-suggestion-updated")
                .frame(width: 320, height: 68, alignment: .leading)))
        coordinator.update(parent: updated, anchor: anchor)
        await settleHosting()

        XCTAssertEqual(scroll.contentView.bounds.origin, offsetBeforeUpdate)
        XCTAssertEqual(header.frame, headerFrameBefore)
        XCTAssertEqual((0..<table.numberOfRows).map { table.rect(ofRow: $0) }, rowFramesBefore)
        let updatedHost = try XCTUnwrap(coordinator.hostForTesting)
        let target = updatedHost.convert(NSPoint(x: updatedHost.bounds.midX, y: updatedHost.bounds.midY), to: document)
        let hit = try XCTUnwrap(document.hitTest(target))
        XCTAssertTrue(hit === updatedHost || hit.isDescendant(of: updatedHost), "Preview controls must receive hits above the table rows: hit=\(type(of: hit)), host=\(updatedHost.frame), point=\(target), documentFlipped=\(document.isFlipped)")

        coordinator.update(parent: closed, anchor: anchor)
        XCTAssertNil(coordinator.hostForTesting)
        XCTAssertFalse(document.subviews.contains { $0 === updatedHost })
        XCTAssertEqual(scroll.contentView.bounds.origin, offsetBeforeUpdate)
        XCTAssertEqual((0..<table.numberOfRows).map { table.rect(ofRow: $0) }, rowFramesBefore)
        XCTAssertNil(anchor.hitTest(NSPoint(x: 2, y: 2)), "Anchor must pass hit testing through to the header")
        header.frame.origin.x += 12
        await settleHosting()
        XCTAssertNil(coordinator.hostForTesting, "Frame observations must not remount a dismissed preview")
    }

    private func settleHosting() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(40))
    }
}

@MainActor
private final class PreviewFixtureDocument: NSView {
    private let usesFlippedCoordinates: Bool
    init(frame: NSRect, usesFlippedCoordinates: Bool = true) {
        self.usesFlippedCoordinates = usesFlippedCoordinates
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    override var isFlipped: Bool { usesFlippedCoordinates }
}

@MainActor
private final class PreviewRowsSource: NSObject, NSTableViewDataSource {
    let count: Int
    init(count: Int) { self.count = count }
    func numberOfRows(in tableView: NSTableView) -> Int { count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { "Result \(row)" }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 42))
        cell.textField = NSTextField(labelWithString: "Result \(row)")
        cell.addSubview(cell.textField!)
        return cell
    }
}
