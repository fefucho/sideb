import AppKit
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class ControlLayoutTests: XCTestCase {
    private let panels = [
        SideBControlSegment(id: "queue", title: "Cola", symbol: "list.bullet"),
        SideBControlSegment(id: "lyrics", title: "Letras", symbol: "quote.bubble"),
        SideBControlSegment(id: "related", title: "Relacionado", symbol: "music.note.list")
    ]

    private func host<V: View>(_ content: V) -> NSHostingView<some View> {
        NSHostingView(rootView: content.preferredColorScheme(.dark))
    }

    func testSelectingLongCategoryDoesNotReflowItsNeighbour() {
        for title in ["Canciones", "Listas de reproducción", "Playlists"] {
            let resting = host(Button {} label: { SideBControlLabel(title: title, symbol: "music.note.list") }
                .buttonStyle(SideBControlStyle(size: .category)).fixedSize())
            let selected = host(Button {} label: { SideBControlLabel(title: title, symbol: "music.note.list") }
                .buttonStyle(SideBControlStyle(size: .category, selected: true)).fixedSize())
            XCTAssertEqual(resting.fittingSize.width, selected.fittingSize.width, accuracy: 0.5)
            XCTAssertEqual(resting.fittingSize.height, selected.fittingSize.height, accuracy: 0.5)
            XCTAssertEqual(resting.fittingSize.height, 48, accuracy: 0.5)
        }
    }

    func testSegmentedControlFitsNarrowPanelAndKeepsHeightWhenResized() throws {
        // A real SwiftUI proposal exercises the native host: labels give way before clipping.
        for width in [CGFloat(420), 160, 260, 420] {
            let root = host(SideBSegmentedControl(segments: panels, selection: "queue", onSelect: { _ in })
                .background(ControlFrameProbe()).frame(maxWidth: .infinity, alignment: .leading))
            root.sizingOptions = []
            root.frame = NSRect(x: 0, y: 0, width: width, height: 40)
            root.layoutSubtreeIfNeeded()
            let probe = try XCTUnwrap(descendants(root).first { $0.identifier?.rawValue == "control-frame-probe" })
            let native = try XCTUnwrap(descendants(root).compactMap { $0 as? NativePanelSegmentHost }.first)
            XCTAssertTrue(native.bar.bounds.contains(native.bar.control.frame))
            XCTAssertLessThanOrEqual(probe.frame.width, width + 0.5)
            XCTAssertGreaterThan(probe.frame.width, 100)
            XCTAssertEqual(probe.frame.height, 40, accuracy: 0.5)
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    func testNativeSelectorKeepsLabelsSelectionAndLatestActionAcrossResizeAndDisabledState() throws {
        var actions: [String] = []
        let view = SideBSegmentedControl(segments: panels, selection: "queue") { actions.append("old:\($0)") }
        let coordinator = view.makeCoordinator()
        let native = view.makeNativeHost(coordinator: coordinator)
        let control = native.bar.control
        let action = try XCTUnwrap(control.action)
        XCTAssertEqual(control.segmentStyle, .automatic)
        XCTAssertEqual(control.segmentDistribution, .fillProportionally)
        if #available(macOS 26.0, *) {
            XCTAssertFalse(descendants(native).contains { $0 is NSGlassEffectView },
                           "The system tab bezel must not be nested inside a second glass surface")
        }
        XCTAssertNil(control.selectedSegmentBezelColor, "AppKit owns the topbar's neutral selection lens")
        XCTAssertEqual(native.fittingSize.height, 40)
        for width in [CGFloat(420), 160, 420] {
            native.frame = NSRect(x: 0, y: 0, width: native.bar.width(fitting: width), height: 40)
            native.needsLayout = true
            native.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(control.frame.height, SideBControlMetrics.groupHeight)
            XCTAssertEqual(control.frame.height, try XCTUnwrap(control.cell).cellSize.height, accuracy: 0.5,
                           "The thicker bezel must use its native size without stretching")
            XCTAssertTrue(native.bar.bounds.contains(control.frame))
            XCTAssertGreaterThanOrEqual(control.frame.width + 0.5, try XCTUnwrap(control.cell).cellSize.width,
                                        "The native lens needs its fitting width, including in icon-only mode")
            XCTAssertEqual(control.toolTip(forSegment: 2), "Relacionado")
            XCTAssertEqual(control.label(forSegment: 2), width == 160 ? "" : "Relacionado")
            XCTAssertEqual(control.selectedSegment, 0)
        }
        control.selectedSegment = 1
        control.sendAction(action, to: control.target)
        XCTAssertEqual(actions, ["old:lyrics"])
        let updated = SideBSegmentedControl(segments: panels, selection: "related") { actions.append("new:\($0)") }
        updated.updateNativeHost(native, coordinator: coordinator, enabled: false)
        XCTAssertTrue(native.bar.control === control)
        XCTAssertEqual(control.selectedSegment, 2)
        control.sendAction(action, to: control.target)
        XCTAssertEqual(actions, ["old:lyrics"], "Disabled controls also reject stale delivered actions")
        updated.updateNativeHost(native, coordinator: coordinator)
        control.selectedSegment = 0
        control.sendAction(action, to: control.target)
        XCTAssertEqual(actions, ["old:lyrics", "new:queue"])
    }

    func testNativeSelectorKeyboardWrapsSkipsDisabledAndKeepsOneFirstResponder() throws {
        var actions: [String] = []
        let view = SideBSegmentedControl(segments: panels, selection: "queue") { actions.append($0) }
        let coordinator = view.makeCoordinator()
        let native = view.makeNativeHost(coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = native
        let control = native.bar.control
        XCTAssertTrue(window.makeFirstResponder(control))
        for code: UInt16 in [123, 115, 124, 119] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            control.keyDown(with: event)
            XCTAssertTrue(window.firstResponder === control)
        }
        XCTAssertEqual(actions, ["related", "queue", "lyrics", "related"])
        control.setEnabled(false, forSegment: 1)
        let left = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 123))
        control.keyDown(with: left)
        XCTAssertEqual(actions.last, "queue")
    }

}

private struct ControlFrameProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier("control-frame-probe")
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
