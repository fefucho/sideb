import AppKit
import SwiftUI
import Testing
@testable import SideB

@Test @MainActor func collectionSearchReleasesFocusOutsideAndOnEscapeWithoutChangingTheFilter() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let field = CollectionSearchTextField(frame: NSRect(x: 20, y: 60, width: 200, height: 22))
    field.stringValue = "Kendrick"
    window.contentView?.addSubview(field)
    #expect(field.focusRingType == .none && !field.isBezeled)
    #expect(window.makeFirstResponder(field))
    let editor = try #require(field.currentEditor() as? NSTextView)
    #expect(window.firstResponder === editor)
    field.releaseFocusIfClickedOutside(in: window, at: NSPoint(x: 50, y: 70))
    #expect(window.firstResponder === editor)
    field.releaseFocusIfClickedOutside(in: window, at: NSPoint(x: 300, y: 120))
    #expect(window.firstResponder !== editor)
    #expect(field.stringValue == "Kendrick")

    #expect(window.makeFirstResponder(field))
    let nextEditor = try #require(field.currentEditor() as? NSTextView)
    let coordinator = CollectionSearchField.Coordinator(query: .constant("Kendrick"))
    #expect(coordinator.control(field, textView: nextEditor,
                                doCommandBy: #selector(NSResponder.cancelOperation(_:))))
    #expect(window.firstResponder !== nextEditor)
    #expect(field.stringValue == "Kendrick")
    #expect(!window.isVisible)
}

@Test @MainActor func collectionSearchHasATransparentEditorBeforeTypingWithoutAffectingOtherFields() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }

    let field = CollectionSearchTextField(frame: NSRect(x: 20, y: 60, width: 200, height: 22))
    window.contentView?.addSubview(field)
    let otherField = NSTextField(frame: NSRect(x: 20, y: 110, width: 200, height: 22))
    window.contentView?.addSubview(otherField)
    #expect(window.makeFirstResponder(otherField))
    let otherEditor = try #require(otherField.currentEditor() as? NSTextView)
    let otherBackground = otherEditor.drawsBackground
    #expect(window.makeFirstResponder(field))
    let editor = try #require(field.currentEditor() as? CollectionSearchFieldEditor)
    #expect(editor.string.isEmpty && !editor.drawsBackground)
    // Model attributes being reapplied after setup by a hosting environment.
    editor.drawsBackground = true
    #expect(!editor.drawsBackground)
    #expect(window.makeFirstResponder(otherField))
    #expect(otherField.currentEditor() === otherEditor && otherEditor !== editor)
    #expect(otherEditor.drawsBackground == otherBackground)
    #expect(window.makeFirstResponder(field))
    #expect(field.currentEditor() === editor && !editor.drawsBackground)
    #expect(!window.isVisible)
}

@Test @MainActor func collectionSearchSynchronizesClearIntoTheLiveEditor() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }

    var query = "Kendrick"
    let field = CollectionSearchTextField(frame: NSRect(x: 20, y: 60, width: 200, height: 22))
    field.stringValue = query
    window.contentView?.addSubview(field)
    #expect(window.makeFirstResponder(field))
    let editor = try #require(field.currentEditor() as? NSTextView)
    let coordinator = CollectionSearchField.Coordinator(query: Binding(get: { query }, set: { query = $0 }))

    query = ""
    coordinator.synchronize(field: field, query: query)
    #expect(field.stringValue.isEmpty)
    #expect(editor.string.isEmpty)
    #expect(window.firstResponder === editor)
    #expect(!window.isVisible)
}
