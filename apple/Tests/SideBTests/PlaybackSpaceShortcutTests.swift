import AppKit
import SwiftUI
import Testing
@testable import SideB

@Test @MainActor func spaceShortcutRespectsSwiftUIControlFocusPerWindowAndRestoresPlaybackOnBlur() {
    let registry = PlaybackSpaceFocusRegistry()
    // Opaque identities stand in for windows; this check creates no NSWindow.
    let firstWindow = NSObject()
    let secondWindow = NSObject()
    let firstID = ObjectIdentifier(firstWindow)
    let secondID = ObjectIdentifier(secondWindow)
    let scope = UUID()
    let responder = NSHostingView(rootView: EmptyView())

    #expect(PlaybackSpaceShortcut.canHandleSpace(responder: responder, windowID: firstID, focusRegistry: registry))
    registry.update(scope: scope, windowID: firstID, isFocused: true)
    #expect(!PlaybackSpaceShortcut.canHandleSpace(responder: responder, windowID: firstID, focusRegistry: registry))
    #expect(PlaybackSpaceShortcut.canHandleSpace(responder: responder, windowID: secondID, focusRegistry: registry))

    // Focus may leave the controls while the panel itself remains open.
    registry.update(scope: scope, windowID: firstID, isFocused: false)
    #expect(PlaybackSpaceShortcut.canHandleSpace(responder: responder, windowID: firstID, focusRegistry: registry))
    registry.update(scope: scope, windowID: firstID, isFocused: true)
    registry.update(scope: scope, windowID: nil, isFocused: false)
    #expect(PlaybackSpaceShortcut.canHandleSpace(responder: responder, windowID: firstID, focusRegistry: registry))
}

@Test @MainActor func spaceFocusScopeMovesBetweenWindowsWithoutLeavingAStaleCapture() {
    let registry = PlaybackSpaceFocusRegistry()
    let firstWindow = NSObject()
    let secondWindow = NSObject()
    let firstID = ObjectIdentifier(firstWindow)
    let secondID = ObjectIdentifier(secondWindow)
    let scope = UUID()
    registry.update(scope: scope, windowID: firstID, isFocused: true)
    registry.update(scope: scope, windowID: secondID, isFocused: true)
    #expect(!registry.preservesNativeSpace(in: firstID))
    #expect(registry.preservesNativeSpace(in: secondID))
    registry.update(scope: scope, windowID: nil, isFocused: true)
    #expect(!registry.preservesNativeSpace(in: secondID))

    let marker = PlaybackSpaceFocusView()
    marker.isControlFocused = true
    #expect(marker.window == nil)
    #expect(marker.hitTest(.zero) == nil)
    marker.clearScope()
}

@Test @MainActor func spaceShortcutRespectsEditableFocus() {
    let editor = NSTextView()
    editor.isEditable = true
    #expect(PlaybackSpaceShortcut.isEditingText(editor))

    editor.isEditable = false
    #expect(!PlaybackSpaceShortcut.isEditingText(editor))

    let field = NSTextField()
    field.isEditable = true
    #expect(PlaybackSpaceShortcut.isEditingText(field))

    field.isEditable = false
    #expect(!PlaybackSpaceShortcut.isEditingText(field))
    #expect(!PlaybackSpaceShortcut.isEditingText(NSButton()))
}

@Test @MainActor func spaceShortcutIgnoresModifiedKeys() throws {
    func event(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: " ", charactersIgnoringModifiers: " ",
            isARepeat: false, keyCode: keyCode
        ))
    }

    #expect(PlaybackSpaceShortcut.isPlainSpace(try event(keyCode: 49)))
    #expect(!PlaybackSpaceShortcut.isPlainSpace(try event(keyCode: 49, modifiers: .command)))
    #expect(!PlaybackSpaceShortcut.isPlainSpace(try event(keyCode: 49, modifiers: .option)))
    #expect(!PlaybackSpaceShortcut.isPlainSpace(try event(keyCode: 49, modifiers: .shift)))
    #expect(!PlaybackSpaceShortcut.isPlainSpace(try event(keyCode: 36)))
}

@Test @MainActor func spaceShortcutPreservesFocusedNativeMediaActions() {
    let windowID = ObjectIdentifier(NSObject())
    let registry = PlaybackSpaceFocusRegistry()
    #expect(!PlaybackSpaceShortcut.canHandleSpace(responder: NSButton(), windowID: windowID, focusRegistry: registry))
    #expect(!PlaybackSpaceShortcut.canHandleSpace(responder: NSSegmentedControl(), windowID: windowID, focusRegistry: registry))
    #expect(!PlaybackSpaceShortcut.canHandleSpace(responder: NativeTrackCreditField(), windowID: windowID, focusRegistry: registry))
}
