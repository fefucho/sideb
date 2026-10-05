import AppKit
import SwiftUI
import Testing
@testable import SideB

@Test @MainActor func collectionWindowBackgroundCoversTitlebarAndSidebarAndFollowsScroll() {
    let canvas = NSRect(x: 0, y: 0, width: 1200, height: 800)
    let viewport = NSRect(x: 242, y: 72, width: 958, height: 728)
    let initial = CollectionBackgroundController.frame(canvas: canvas, viewport: viewport, headerHeight: 340, scrollOffset: 0)
    #expect(initial == NSRect(x: 0, y: 0, width: 1200, height: 552))
    let scrolled = CollectionBackgroundController.frame(canvas: canvas, viewport: viewport, headerHeight: 340, scrollOffset: 150)
    #expect(scrolled == NSRect(x: 0, y: -150, width: 1200, height: 552))
    let bounced = CollectionBackgroundController.frame(canvas: canvas, viewport: viewport, headerHeight: 340, scrollOffset: -20)
    #expect(bounced == NSRect(x: 0, y: 0, width: 1200, height: 572))
    let collapsedViewport = NSRect(x: 0, y: 72, width: 1200, height: 728)
    #expect(CollectionBackgroundController.frame(canvas: canvas, viewport: collapsedViewport,
                                                headerHeight: 340, scrollOffset: 0) == initial)
}

@Test @MainActor func collectionWindowBackgroundUsesNativeGeometryAndRejectsOldPagesAndAccounts() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let root = CollectionBackgroundCanvas(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    window.contentView = root
    let canvas = CollectionBackgroundCanvas(frame: root.bounds)
    root.addSubview(canvas)
    // The viewport reaches the top edge. Its initial toolbar clearance is part
    // of the scrolling header, so content can pass underneath the window toolbar.
    let scroll = NSScrollView(frame: NSRect(x: 242, y: 0, width: 958, height: 800))
    scroll.automaticallyAdjustsContentInsets = false
    root.addSubview(scroll)
    let table = NativeTrackTableViewInternal(frame: NSRect(x: 0, y: 0, width: 958, height: 2000))
    table.headerView = nil
    scroll.documentView = table
    let controller = CollectionBackgroundController()
    let oldOwner = UUID(), newOwner = UUID()
    var visibility: [Bool] = []
    controller.activate(identity: "account1:album:a", enabled: true, reduceMotion: true, scenePhase: .active)
    controller.register(owner: oldOwner, identity: "account1:album:a", document: table, headerHeight: 412) {
        visibility.append($0)
        return AnyView(Color.red)
    }
    // The document may register before the background is attached by SwiftUI.
    controller.attach(canvas)
    let host = try #require(controller.host)
    #expect(host.superview === canvas)
    #expect(host.frame == NSRect(x: 0, y: 0, width: 1200, height: 552))
    #expect(canvas.convert(scroll.contentView.bounds, from: scroll.contentView).minY == 0)
    #expect(host.hitTest(NSPoint(x: 50, y: 50)) == nil)
    #expect(canvas.hitTest(NSPoint(x: 50, y: 50)) == nil)
    #expect(visibility.last == true)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
    controller.updateGeometry()
    #expect(controller.host === host)
    #expect(host.frame.minY == -600)
    #expect(visibility.last == false)
    scroll.contentView.scroll(to: .zero)
    // Changing account/page removes the previous artwork before a new request resolves.
    controller.activate(identity: "account2:playlist:b", enabled: true, reduceMotion: true, scenePhase: .active)
    #expect(controller.host == nil && host.superview == nil)
    controller.register(owner: oldOwner, identity: "account1:album:a", document: table, headerHeight: 340) { _ in AnyView(Color.red) }
    #expect(controller.host == nil)
    controller.register(owner: newOwner, identity: "account2:playlist:b", document: table, headerHeight: 400) {
        visibility.append($0)
        return AnyView(Color.blue)
    }
    let nextHost = try #require(controller.host)
    controller.unregister(owner: oldOwner)
    #expect(controller.host === nextHost)
    controller.activate(identity: "account2:playlist:b", enabled: false, reduceMotion: true, scenePhase: .active)
    #expect(nextHost.isHidden && visibility.last == false)
    controller.activate(identity: "account2:playlist:b", enabled: true, reduceMotion: true, scenePhase: .active)
    #expect(!nextHost.isHidden && visibility.last == true)
    // Native resize uses the entire shell width, not the table's column width.
    canvas.frame.size.width = 1000
    controller.updateGeometry()
    #expect(nextHost.frame.width == 1000)
    controller.activate(identity: nil, enabled: true, reduceMotion: true, scenePhase: .active)
    #expect(controller.host == nil)
    controller.unregister(owner: newOwner)
    controller.detach(canvas)
}
