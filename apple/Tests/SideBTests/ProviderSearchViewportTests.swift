import AppKit
import SwiftUI
import XCTest
@testable import SideB

@MainActor final class ProviderSearchViewportTests: XCTestCase {
    private func entries(_ count: Int) -> [ProviderSearchViewportEntry] {
        (0..<count).map { ProviderSearchViewportEntry(id: "entry-\($0)", kind: .row, height: 58) }
    }

    private func viewport(_ entries: [ProviderSearchViewportEntry], reset: String = "query", snapshot: Int = 1,
                          header: Bool = false) -> ProviderSearchViewport {
        ProviderSearchViewport(entries: entries, resetIdentity: AnyHashable(reset), snapshotRevision: AnyHashable(snapshot),
            scrollingHeader: header ? AnyView(TextField("Search", text: .constant("query"))) : nil,
            rowContent: { entry, width in
                AnyView(Text(String(describing: entry.id) + " · " + String(Int(width))).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12))
            })
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    func testMountedTrailingControlsFollowRepeatedWidthChangesWithoutScrolling() async throws {
        let parent = ProviderSearchViewport(entries: entries(40), resetIdentity: AnyHashable("resize"),
            snapshotRevision: AnyHashable(1), rowContent: { entry, width in
                AnyView(HStack {
                    Text(String(describing: entry.id))
                    Spacer(minLength: 0)
                    TrailingSearchControlProbe().frame(width: 32, height: 32)
                }.frame(width: width, height: 58))
            })
        let coordinator = parent.makeCoordinator()
        let scroll = coordinator.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: -2200, y: -1500, width: 700, height: 400),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.orderFrontRegardless()
        defer { coordinator.dismantle(); window.contentView = nil; window.close() }
        var nativeRightOutset: CGFloat?
        for width in [700.0, 960, 1512, 700, 1512, 960] {
            window.setContentSize(NSSize(width: width, height: 400))
            scroll.layoutSubtreeIfNeeded()
            coordinator.updateGeometryForTesting()
            for _ in 0..<4 {
                scroll.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            let table = try XCTUnwrap(coordinator.tableForTesting)
            let first = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: false))
            let button = try XCTUnwrap(descendants(first).compactMap { $0 as? NSButton }.first)
            let frame = button.convert(button.bounds, to: scroll.contentView)
            let rightEdge = scroll.contentView.bounds.maxX - 28
            // AppKit can give the probe its native fitting width beyond the
            // requested 32pt. Its measured outset must stay fixed through resize.
            if nativeRightOutset == nil { nativeRightOutset = frame.maxX - rightEdge }
            XCTAssertEqual(frame.maxX, rightEdge + (nativeRightOutset ?? 0), accuracy: 0.5)
            XCTAssertTrue(scroll.contentView.bounds.contains(frame))
            XCTAssertEqual(first.bounds.width, table.bounds.width, accuracy: 1)
            XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
        }
    }

    func testFullWidthHeaderAndRowsKeepTwentyEightPointMarginsAcrossSidebarSizes() async throws {
        let coordinator = viewport(entries(40), header: true).makeCoordinator()
        let scroll = coordinator.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: -2200, y: -1500, width: 1512, height: 700),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { coordinator.dismantle(); window.contentView = nil; window.close() }
        for scrollerStyle in [NSScroller.Style.overlay, .legacy] {
            scroll.scrollerStyle = scrollerStyle
            for width in [1512.0, 1800, 1270, 960, 700] {
                window.setContentSize(NSSize(width: width, height: 700))
                scroll.layoutSubtreeIfNeeded()
                coordinator.updateGeometryForTesting()
                await Task.yield()
                let table = try XCTUnwrap(coordinator.tableForTesting)
                let header = try XCTUnwrap(coordinator.headerForTesting)
                XCTAssertEqual(table.frame.minX, 28, accuracy: 0.5)
                XCTAssertEqual(table.frame.maxX, scroll.contentView.bounds.width - 28, accuracy: 0.5)
                XCTAssertEqual(header.frame.minX, table.frame.minX, accuracy: 0.5)
                XCTAssertEqual(header.frame.width, table.frame.width, accuracy: 0.5)
                XCTAssertEqual(table.tableColumns.first?.width ?? 0, table.frame.width, accuracy: 0.5)
            }
        }
    }

    func testFiveThousandRowsKeepOnlyViewportHostsMounted() async throws {
        var renderedIDs: [AnyHashable] = []
        let parent = ProviderSearchViewport(entries: entries(5_000), resetIdentity: AnyHashable("query"),
            snapshotRevision: AnyHashable(1),
            scrollingHeader: AnyView(TextField("Search", text: .constant("query"))),
            rowContent: { entry, width in
                renderedIDs.append(entry.id)
                return AnyView(Text(String(describing: entry.id) + " " + String(Int(width)))
                    .frame(maxWidth: .infinity, alignment: .leading))
            })
        let coordinator = parent.makeCoordinator()
        let scroll = coordinator.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        defer { coordinator.dismantle(); window.contentView = nil; window.close() }

        scroll.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        scroll.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))

        let table = try XCTUnwrap(coordinator.tableForTesting)
        XCTAssertEqual(table.numberOfRows, 5_000)
        let rowHosts = descendants(scroll).filter { String(describing: type(of: $0)).contains("ProviderSearchRowView") }
        XCTAssertLessThan(rowHosts.count, 40)
        XCTAssertGreaterThan(rowHosts.count, 0)
        XCTAssertTrue(renderedIDs.contains("entry-0"))

        let laterRect = try XCTUnwrap(coordinator.documentForTesting).convert(table.rect(ofRow: 4_500), from: table)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: laterRect.minY))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroll.layoutSubtreeIfNeeded()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))
        let visibleRows = table.rows(in: table.visibleRect)
        XCTAssertTrue(NSLocationInRange(4_500, visibleRows))
        XCTAssertTrue(renderedIDs.contains("entry-4500"))
        let scrolledHosts = descendants(scroll).filter { String(describing: type(of: $0)).contains("ProviderSearchRowView") }
        XCTAssertLessThan(scrolledHosts.count, 40)
    }

    func testAppendPreservesOffsetAndNewResetIdentityReturnsToTop() throws {
        let coordinator = viewport(entries(1_000)).makeCoordinator()
        let scroll = coordinator.makeScrollView()
        defer { coordinator.dismantle() }
        scroll.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        coordinator.updateGeometryForTesting()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 8_000))
        scroll.reflectScrolledClipView(scroll.contentView)
        let offset = scroll.contentView.bounds.minY

        coordinator.update(parent: viewport(entries(1_200), snapshot: 2))
        XCTAssertEqual(scroll.contentView.bounds.minY, offset, accuracy: 1)

        coordinator.update(parent: viewport(entries(20), reset: "different query", snapshot: 3))
        XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
    }

    func testDuplicateOccurrenceIDsStillProduceDistinctRows() throws {
        let repeated = [
            ProviderSearchViewportEntry(id: "same", kind: .row, height: 58),
            ProviderSearchViewportEntry(id: "same", kind: .row, height: 58)
        ]
        let coordinator = viewport(repeated).makeCoordinator()
        defer { coordinator.dismantle() }
        _ = coordinator.makeScrollView()
        XCTAssertEqual(try XCTUnwrap(coordinator.tableForTesting).numberOfRows, 2)
        XCTAssertEqual(coordinator.rowKeysForTesting.count, 2)
        XCTAssertNotEqual(coordinator.rowKeysForTesting[0], coordinator.rowKeysForTesting[1])
    }

    func testHeaderHostRemainsTheSameAcrossAppendAndQueryReset() {
        let coordinator = viewport(entries(40), header: true).makeCoordinator()
        _ = coordinator.makeScrollView()
        defer { coordinator.dismantle() }
        let originalHeader = coordinator.headerForTesting
        coordinator.update(parent: viewport(entries(80), snapshot: 2, header: true))
        XCTAssertTrue(coordinator.headerForTesting === originalHeader)
        coordinator.update(parent: viewport(entries(20), reset: "next query", snapshot: 3, header: true))
        XCTAssertTrue(coordinator.headerForTesting === originalHeader)
    }

    func testMountedRowMatchesPersistentHeaderColumnInWindow() async throws {
        let coordinator = viewport(entries(40), header: true).makeCoordinator()
        let scroll = coordinator.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        defer { coordinator.dismantle(); window.contentView = nil; window.close() }

        window.contentView?.layoutSubtreeIfNeeded()
        scroll.layoutSubtreeIfNeeded()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(150))

        let table = try XCTUnwrap(coordinator.tableForTesting)
        let document = try XCTUnwrap(coordinator.documentForTesting)
        let header = try XCTUnwrap(coordinator.headerForTesting)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: false))
        let cellFrame = document.convert(cell.frame, from: table)
        XCTAssertEqual(table.style, .plain)
        XCTAssertEqual(cellFrame.minX, header.frame.minX, accuracy: 1)
        XCTAssertEqual(cellFrame.width, header.frame.width, accuracy: 1)
    }

    func testWindowResizeUpdatesContentWidthAndExpansionRemeasuresStablePrincipal() async throws {
        for scrollerStyle in [NSScroller.Style.overlay, .legacy] {
            var expanded = false
            var renderedWidths: [CGFloat] = []
            var renderedIDs: [AnyHashable] = []
            let principal = ProviderSearchViewportEntry(id: "principal-occurrence", kind: .principal)
            func viewport(renderRevision: Int = 0) -> ProviderSearchViewport {
                ProviderSearchViewport(entries: [principal], resetIdentity: AnyHashable("query"),
                    snapshotRevision: AnyHashable(1), renderRevision: AnyHashable(renderRevision),
                    rowContent: { entry, width in
                        renderedWidths.append(width)
                        renderedIDs.append(entry.id)
                        return AnyView(Text("Principal").frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: expanded ? 420 : 250, alignment: .top))
                    })
            }

            let coordinator = viewport().makeCoordinator()
            let scroll = coordinator.makeScrollView()
            scroll.scrollerStyle = scrollerStyle
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 700),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = scroll
            window.makeKeyAndOrderFront(nil)
            defer { coordinator.dismantle(); window.contentView = nil; window.close() }

            scroll.layoutSubtreeIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
            await Task.yield()
            try await Task.sleep(for: .milliseconds(150))
            let table = try XCTUnwrap(coordinator.tableForTesting)
            let originalHeight = table.rect(ofRow: 0).height

            window.setContentSize(NSSize(width: 700, height: 700))
            window.contentView?.layoutSubtreeIfNeeded()
            scroll.layoutSubtreeIfNeeded()
            await Task.yield()
            try await Task.sleep(for: .milliseconds(200))

            let expectedWidth = scroll.contentView.bounds.width - 56
            XCTAssertTrue(renderedWidths.contains { abs($0 - expectedWidth) < 2 },
                "style=\(scrollerStyle), clip=\(scroll.contentView.bounds.width), rendered=\(renderedWidths)")
            XCTAssertEqual(table.bounds.width, expectedWidth, accuracy: 1)
            XCTAssertEqual(renderedIDs.last, principal.id)

            expanded = true
            coordinator.update(parent: viewport(renderRevision: 1))
            await Task.yield()
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertGreaterThan(table.rect(ofRow: 0).height, originalHeight + 100)
            XCTAssertEqual(renderedIDs.last, principal.id)
        }
    }

    func testAppendRetainsOffscreenPrincipalMeasurementUntilItsRevisionChanges() async throws {
        var expanded = false
        let principalID = "principal-stable"
        func entries(_ rowCount: Int, measurementRevision: Int = 0) -> [ProviderSearchViewportEntry] {
            [ProviderSearchViewportEntry(id: principalID, kind: .principal,
                                          measurementRevision: AnyHashable(measurementRevision))]
                + self.entries(rowCount)
        }
        func viewport(_ rows: [ProviderSearchViewportEntry], snapshot: Int) -> ProviderSearchViewport {
            ProviderSearchViewport(entries: rows, resetIdentity: AnyHashable("same-query"),
                snapshotRevision: AnyHashable(snapshot), rowContent: { entry, width in
                    if entry.id == AnyHashable(principalID) {
                        return AnyView(Text("Principal").frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: expanded ? 210 : 112, alignment: .top))
                    }
                    return AnyView(Text(String(describing: entry.id)).frame(maxWidth: .infinity, alignment: .leading))
                })
        }

        let firstPage = entries(1_000)
        let coordinator = viewport(firstPage, snapshot: 1).makeCoordinator()
        let scroll = coordinator.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        defer { coordinator.dismantle(); window.contentView = nil; window.close() }

        scroll.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(150))
        let table = try XCTUnwrap(coordinator.tableForTesting)
        XCTAssertEqual(table.rect(ofRow: 0).height, 112, accuracy: 2)

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 8_000))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroll.layoutSubtreeIfNeeded()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))
        let offsetBeforeAppend = scroll.contentView.bounds.minY
        let visibleRow = 140
        let visiblePositionBeforeAppend = table.rect(ofRow: visibleRow).minY - table.visibleRect.minY

        let appendedRows = entries(1_100)
        coordinator.update(parent: viewport(appendedRows, snapshot: 2))
        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(scroll.contentView.bounds.minY, offsetBeforeAppend, accuracy: 1)
        XCTAssertEqual(table.rect(ofRow: 0).height, 112, accuracy: 2)
        XCTAssertEqual(table.rect(ofRow: visibleRow).minY - table.visibleRect.minY,
                       visiblePositionBeforeAppend, accuracy: 1)

        expanded = true
        let expandedRows = entries(1_100, measurementRevision: 1)
        coordinator.update(parent: viewport(expandedRows, snapshot: 3))
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        scroll.layoutSubtreeIfNeeded()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(table.rect(ofRow: 0).height, 210, accuracy: 3)
    }
}

private struct TrailingSearchControlProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton { NSButton(title: "…", target: nil, action: nil) }
    func updateNSView(_ view: NSButton, context: Context) {}
}
