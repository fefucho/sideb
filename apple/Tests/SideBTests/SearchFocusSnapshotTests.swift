import AppKit
import XCTest
@testable import SideB

@MainActor
final class SearchFocusSnapshotTests: XCTestCase {
    func testSnapshotRestoresOwningFieldAndUTF16SelectionInsteadOfSharedEditor() throws {
        let window = makeWindow()
        defer { window.close() }
        let first = NSTextField(frame: CGRect(x: 0, y: 0, width: 200, height: 22))
        let next = NSTextField(frame: CGRect(x: 0, y: 50, width: 200, height: 22))
        first.stringValue = "A🧡B"
        window.contentView?.addSubview(first)
        window.contentView?.addSubview(next)
        XCTAssertTrue(window.makeFirstResponder(first))
        let shared = try XCTUnwrap(first.currentEditor() as? NSTextView)
        shared.setSelectedRange(NSRange(location: 1, length: 2))
        let snapshot = SearchFocusSnapshot(window: window)
        XCTAssertTrue(window.makeFirstResponder(next))
        XCTAssertTrue(next.currentEditor() === shared)
        XCTAssertFalse(snapshot.restoreIfUnclaimed(), "A newly focused control keeps its focus")
        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertTrue(snapshot.restoreIfUnclaimed())
        XCTAssertTrue(window.firstResponder === first.currentEditor())
        XCTAssertEqual((first.currentEditor() as? NSTextView)?.selectedRange(), NSRange(location: 1, length: 2))
    }

    func testSnapshotRejectsDetachedOrHiddenControl() {
        let window = makeWindow()
        defer { window.close() }
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 200, height: 22))
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        let snapshot = SearchFocusSnapshot(window: window)
        window.makeFirstResponder(nil)
        field.isHidden = true
        XCTAssertFalse(snapshot.restoreIfUnclaimed())
        field.isHidden = false
        field.removeFromSuperview()
        XCTAssertFalse(snapshot.restoreIfUnclaimed())
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: -2000, y: -2000, width: 400, height: 120),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }
}
