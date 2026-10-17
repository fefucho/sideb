import AppKit
import Testing
@testable import SideB

@Test @MainActor func searchToolbarRepeatedProgressKeepsCleanLayoutAndFrames() {
    let bar = NativeSearchBar(frame: NSRect(x: 0, y: 0, width: 298, height: 42))
    bar.applyExpansionProgress(0.8)
    bar.needsLayout = true
    bar.layoutSubtreeIfNeeded()
    #expect(!bar.needsLayout)
    let frames = [bar.iconButton.frame, bar.textField.frame, bar.closeButton.frame]
    let alpha = bar.textField.alphaValue

    for _ in 0..<30 {
        bar.applyExpansionProgress(0.8)
        #expect(!bar.needsLayout)
    }

    #expect([bar.iconButton.frame, bar.textField.frame, bar.closeButton.frame] == frames)
    #expect(bar.textField.alphaValue == alpha && bar.closeButton.alphaValue == alpha)
    // A fade at a fixed size also leaves geometry alone.
    bar.applyExpansionProgress(1)
    #expect(!bar.needsLayout)
    #expect(bar.textField.alphaValue == 1 && bar.closeButton.alphaValue == 1)

    bar.setFrameSize(NSSize(width: 400, height: 42))
    bar.applyExpansionProgress(1)
    bar.layoutSubtreeIfNeeded()
    #expect(bar.textField.frame.width == 322)
    #expect(bar.closeButton.frame.minX == 364)
}

@Test @MainActor func searchToolbarFocusRetriesAndRearmsAtIdenticalProgress() throws {
    let bar = NativeSearchBar(frame: NSRect(x: 0, y: 0, width: 298, height: 42))
    bar.setExpanded(true)
    // The initial expansion cannot focus until the control is attached.
    bar.applyExpansionProgress(1)
    #expect(bar.textField.currentEditor() == nil)

    let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 400, height: 120),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView?.addSubview(bar)
    let otherField = NSTextField(frame: NSRect(x: 0, y: 60, width: 200, height: 22))
    window.contentView?.addSubview(otherField)

    bar.applyExpansionProgress(1)
    let editor = try #require(bar.textField.currentEditor())
    #expect(window.firstResponder === editor)

    #expect(window.makeFirstResponder(otherField))
    let otherEditor = try #require(otherField.currentEditor())
    bar.applyExpansionProgress(1)
    #expect(window.firstResponder === otherEditor)
    bar.requestFocus()
    #expect(window.firstResponder === bar.textField.currentEditor())

    bar.setExpanded(false)
    #expect(window.makeFirstResponder(otherField))
    bar.setExpanded(true)
    bar.applyExpansionProgress(1)
    #expect(window.firstResponder === bar.textField.currentEditor())
    #expect(!window.isVisible)
}

@Test @MainActor func searchToolbarEscapeCollapsesWithoutChangingQueryOrSubmitting() {
    let bar = NativeSearchBar()
    bar.setQuery("Radiohead")
    bar.setExpanded(true)
    var requestedExpansion: Bool?
    var submitted: String?
    bar.onToggleExpand = { requestedExpansion = $0 }
    bar.onSubmit = { submitted = $0 }

    let handled = bar.control(bar.textField, textView: NSTextView(),
                              doCommandBy: #selector(NSResponder.cancelOperation(_:)))

    #expect(handled)
    #expect(!bar.isExpanded)
    #expect(requestedExpansion == false)
    #expect(bar.textField.stringValue == "Radiohead")
    #expect(submitted == nil)
}

@Test @MainActor func searchToolbarClearButtonClearsNonemptyQueryWithoutCollapsing() {
    let bar = NativeSearchBar()
    bar.setExpanded(true)
    bar.setQuery("Björk")
    bar.applyExpansionProgress(0.8)
    var queries: [String] = []
    var requestedExpansion: Bool?
    bar.onQueryChange = { queries.append($0) }
    bar.onToggleExpand = { requestedExpansion = $0 }

    bar.closeButton.performClick(nil)

    #expect(bar.textField.stringValue.isEmpty)
    #expect(queries == [""])
    #expect(bar.isExpanded)
    #expect(requestedExpansion == nil)
}

@Test @MainActor func searchToolbarClearButtonClosesWhenQueryIsEmpty() {
    let bar = NativeSearchBar()
    bar.setExpanded(true)
    bar.applyExpansionProgress(0.8)
    var requestedExpansion: Bool?
    bar.onToggleExpand = { requestedExpansion = $0 }

    bar.closeButton.performClick(nil)

    #expect(!bar.isExpanded)
    #expect(requestedExpansion == false)
}

@Test @MainActor func searchToolbarRoutesSingleLineSubmissionAndVerticalArrowsToOwner() {
    let bar = NativeSearchBar()
    bar.setQuery("Massive Attack")
    bar.setExpanded(true)
    var submissions: [String] = []
    var movements: [Int] = []
    var requestedExpansion: Bool?
    bar.onSubmit = { submissions.append($0) }
    bar.onMoveSelection = { movements.append($0) }
    bar.onToggleExpand = { requestedExpansion = $0 }
    let editor = NSTextView()

    let enterHandled = bar.control(bar.textField, textView: editor,
                                   doCommandBy: #selector(NSResponder.insertNewline(_:)))
    let upHandled = bar.control(bar.textField, textView: editor,
                                doCommandBy: #selector(NSResponder.moveUp(_:)))

    let downHandled = bar.control(bar.textField, textView: editor,
                                  doCommandBy: #selector(NSResponder.moveDown(_:)))
    let leftHandled = bar.control(bar.textField, textView: editor,
                                  doCommandBy: #selector(NSResponder.moveLeft(_:)))

    #expect(enterHandled && upHandled && downHandled)
    #expect(!leftHandled)
    #expect(submissions == ["Massive Attack"])
    #expect(movements == [-1, 1])
    #expect(bar.isExpanded)
    #expect(requestedExpansion == nil)
}


@Test @MainActor func searchToolbarEmptySubmitKeepsOwnerInControlAndLegacyEnterStillCloses() {
    let bar = NativeSearchBar()
    bar.setExpanded(true)
    var submissions: [String] = []
    var collapses = 0
    bar.onSubmit = { submissions.append($0) }
    bar.onToggleExpand = { if !$0 { collapses += 1 } }

    #expect(bar.control(bar.textField, textView: NSTextView(),
                        doCommandBy: #selector(NSResponder.insertNewline(_:))))
    #expect(submissions == [""])
    #expect(bar.isExpanded && collapses == 0)

    bar.onSubmit = nil
    #expect(bar.control(bar.textField, textView: NSTextView(),
                        doCommandBy: #selector(NSResponder.insertNewline(_:))))
    #expect(!bar.isExpanded && collapses == 1)
}

@Test @MainActor func searchToolbarNativePlaceholderLineAndCaretAreCenteredAtNaturalFontHeight() throws {
    for fontSize: CGFloat in [11, 14.5, 18, 24] {
        let (bar, window, editor) = try makeEditingSearchToolbar()
        defer { window.close() }
        bar.unfocusField()
        bar.textField.font = .systemFont(ofSize: fontSize)
        bar.setQuery("")
        bar.needsLayout = true
        bar.layoutSubtreeIfNeeded()
        let cell = try #require(bar.textField.cell)
        let placeholderRect = bar.textField.convert(cell.titleRect(forBounds: bar.textField.bounds), to: bar)
        #expect(abs(placeholderRect.midY - bar.bounds.midY) < 0.01)
        #expect(bar.textField.frame.height == cell.cellSize.height)
        let placeholderFrame = bar.textField.frame

        bar.setQuery("Agjp 日本 😀")
        #expect(bar.focusField())
        let textContainer = try #require(editor.textContainer)
        let layoutManager = try #require(editor.layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let line = layoutManager.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
        let editorLine = editor.convert(line.offsetBy(dx: editor.textContainerOrigin.x,
                                                       dy: editor.textContainerOrigin.y), to: bar)
        #expect(abs(editorLine.midY - bar.bounds.midY) < 0.01)
        #expect(bar.textField.frame == placeholderFrame)
        let caretScreen = editor.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
        let caret = bar.convert(window.convertFromScreen(caretScreen), from: nil)
        #expect(abs(caret.midY - bar.bounds.midY) < 0.01)
        #expect(caret.height <= bar.textField.frame.height)
        #expect(bar.bounds.contains(editorLine))
    }
}

@Test @MainActor func searchToolbarCompositionPublishesOnlyCommittedTextAndLeavesIMECommandsAlone() throws {
    let (bar, window, editor) = try makeEditingSearchToolbar()
    defer { window.close() }
    var queries: [String] = []
    var submissions: [String] = []
    var movements: [Int] = []
    bar.onQueryChange = { queries.append($0) }
    bar.onSubmit = { submissions.append($0) }
    bar.onMoveSelection = { movements.append($0) }

    editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                         replacementRange: NSRange(location: NSNotFound, length: 0))
    bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: bar.textField))
    #expect(editor.hasMarkedText())
    #expect(queries.isEmpty)
    for selector in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)),
                     #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:))] {
        #expect(!bar.control(bar.textField, textView: editor, doCommandBy: selector))
    }
    #expect(bar.isExpanded && submissions.isEmpty && movements.isEmpty)

    // Accepting unchanged candidates can call unmarkText without a didChange.
    editor.unmarkText()
    bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: bar.textField))
    #expect(queries == ["に"])
    editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(submissions == ["に"])
    #expect(bar.isExpanded)
}

@Test @MainActor func searchToolbarIMEInsertionCommitsOnceWithoutSubmitting() throws {
    let (bar, window, editor) = try makeEditingSearchToolbar()
    defer { window.close() }
    var queries: [String] = []
    var submissions: [String] = []
    bar.onQueryChange = { queries.append($0) }
    bar.onSubmit = { submissions.append($0) }
    editor.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0),
                         replacementRange: NSRange(location: NSNotFound, length: 0))
    editor.insertText("日本", replacementRange: editor.markedRange())

    #expect(!editor.hasMarkedText())
    #expect(queries == ["日本"])
    #expect(submissions.isEmpty)
    #expect(bar.isExpanded)
}

@Test @MainActor func searchToolbarQueryEchoPreservesUTF16SelectionAndMarkedCandidates() throws {
    let (bar, window, editor) = try makeEditingSearchToolbar()
    defer { window.close() }
    bar.setQuery("A😀B")
    let selection = NSRange(location: 1, length: 2)
    editor.setSelectedRange(selection)
    for _ in 0..<20 {
        bar.setQuery("A😀B")
        bar.applyExpansionProgress(1)
    }
    #expect(editor.selectedRange() == selection)
    #expect(window.firstResponder === editor)
    editor.setMarkedText("日本", selectedRange: NSRange(location: 1, length: 0), replacementRange: selection)
    let markedRange = editor.markedRange()
    let markedSelection = editor.selectedRange()
    for _ in 0..<20 {
        bar.setQuery("A😀B") // Last confirmed value echoed by the model.
        bar.setQuery(editor.string)
        bar.applyExpansionProgress(1)
    }
    #expect(editor.string == "A日本B")
    #expect(editor.hasMarkedText())
    #expect(editor.markedRange() == markedRange)
    #expect(editor.selectedRange() == markedSelection)
}

@Test @MainActor func searchToolbarDefersOnlyLatestExternalReplacementUntilIMEFinishes() throws {
    let (bar, window, editor) = try makeEditingSearchToolbar()
    defer { window.close() }
    bar.setQuery("draft")
    var queries: [String] = []
    bar.onQueryChange = { queries.append($0) }
    editor.setMarkedText("日本", selectedRange: NSRange(location: 1, length: 0),
                         replacementRange: NSRange(location: 0, length: 5))
    let selection = editor.selectedRange()
    bar.setQuery("first external")
    bar.setQuery("latest 😀")
    bar.setQuery("draft") // A model echo cannot overwrite a pending real replacement.
    #expect(editor.hasMarkedText() && editor.string == "日本")
    #expect(editor.selectedRange() == selection && queries.isEmpty)

    editor.unmarkText()
    #expect(editor.string == "latest 😀")
    // AppKit can move the caret to the candidate's end when it unmarks. The
    // replacement retains that position instead of selecting/jumping to its end.
    #expect(editor.selectedRange().location <= "日本".utf16.count)
    #expect(editor.selectedRange().length == 0)
    #expect(queries == ["latest 😀"])
}

@Test @MainActor func searchToolbarClearDuringCompositionCancelsCandidatesWithoutIntermediatePreview() throws {
    let (bar, window, editor) = try makeEditingSearchToolbar()
    defer { window.close() }
    bar.setQuery("draft")
    var queries: [String] = []
    bar.onQueryChange = { queries.append($0) }
    editor.setMarkedText("日本", selectedRange: NSRange(location: 1, length: 0),
                         replacementRange: NSRange(location: 0, length: 5))
    bar.closeButton.performClick(nil)
    #expect(!editor.hasMarkedText())
    #expect(editor.string.isEmpty)
    #expect(queries == [""])
    #expect(bar.isExpanded)
}

@Test @MainActor func searchToolbarSelectionAccessibilityHelpUpdatesWithoutChangingInputLabel() {
    let bar = NativeSearchBar()
    let inputLabel = bar.textField.accessibilityLabel()
    bar.selectionLabel = "Selected: Björk, artist"
    #expect(bar.textField.accessibilityHelp() == "Selected: Björk, artist")
    #expect(bar.textField.accessibilityLabel() == inputLabel)
    bar.selectionLabel = nil
    #expect(bar.textField.accessibilityHelp() == nil)
}

@MainActor private func makeEditingSearchToolbar() throws -> (NativeSearchBar, NSWindow, NSTextView) {
    let bar = NativeSearchBar(frame: NSRect(x: 0, y: 0, width: 298, height: 42))
    let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 400, height: 120),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView?.addSubview(bar)
    bar.layoutSubtreeIfNeeded()
    bar.setExpanded(true)
    bar.applyExpansionProgress(1)
    return (bar, window, try #require(bar.textField.currentEditor() as? NSTextView))
}


@Test @MainActor func searchToolbarExternalReplacementRetainsAndClampsUTF16Selection() throws {
    let (bar, window, editor) = try makeEditingSearchToolbar()
    defer { window.close() }
    bar.setQuery("A😀BCDE")
    editor.setSelectedRange(NSRange(location: 1, length: 2))
    bar.setQuery("Z😀XX")
    #expect(editor.selectedRange() == NSRange(location: 1, length: 2))
    editor.setSelectedRange(NSRange(location: 4, length: 1))
    bar.setQuery("Hi")
    #expect(editor.string == "Hi")
    #expect(editor.selectedRange() == NSRange(location: 2, length: 0))
}

@Test @MainActor func searchToolbarOpeningOwnsTypingBeforeFirstMorphFrameAtZeroFieldWidth() throws {
    let bar = NativeSearchBar()
    let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 400, height: 120),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let previousField = NSTextField(frame: NSRect(x: 0, y: 60, width: 200, height: 22))
    previousField.stringValue = "previous page"
    window.contentView?.addSubview(previousField)
    window.contentView?.addSubview(bar)
    bar.layoutSubtreeIfNeeded()
    #expect(window.makeFirstResponder(previousField))
    var queries: [String] = []
    bar.onQueryChange = { queries.append($0) }

    bar.setExpanded(true)
    let editor = try #require(bar.textField.currentEditor() as? NSTextView)
    #expect(window.firstResponder === editor)
    #expect(bar.frame.size == NativeSearchBar.collapsedSize)
    #expect(bar.textField.frame.width == 0 && bar.textField.alphaValue == 0)
    #expect(!bar.textField.isHidden && bar.textField.isEnabled)
    editor.insertText("😀", replacementRange: editor.selectedRange())
    #expect(queries == ["😀"])
    #expect(editor.string == "😀" && previousField.stringValue == "previous page")

    // Unchanged progress never reclaims focus; an explicit repeated shortcut does.
    #expect(window.makeFirstResponder(previousField))
    let previousEditor = try #require(previousField.currentEditor())
    for _ in 0..<20 { bar.applyExpansionProgress(0) }
    #expect(window.firstResponder === previousEditor)
    bar.requestFocus()
    #expect(window.firstResponder === bar.textField.currentEditor())
    #expect(bar.frame.size == NativeSearchBar.collapsedSize)
    #expect(bar.textField.frame.width == 0 && bar.textField.alphaValue == 0)
}

@Test @MainActor func searchToolbarAttachmentFocusesAnExpandedEditorWithoutAnimationTick() throws {
    let bar = NativeSearchBar()
    bar.layoutSubtreeIfNeeded()
    bar.setExpanded(true)
    #expect(bar.textField.currentEditor() == nil)
    let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 400, height: 120),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView?.addSubview(bar)
    let editor = try #require(bar.textField.currentEditor() as? NSTextView)
    #expect(window.firstResponder === editor)
    #expect(bar.frame.size == NativeSearchBar.collapsedSize)
    editor.insertText("before animation", replacementRange: editor.selectedRange())
    #expect(editor.string == "before animation")
}

@Test @MainActor func searchToolbarSessionResetDiscardsCompositionAndDeferredQueryWithoutPublishing() throws {
    let (bar, window, editor) = try makeEditingSearchToolbar()
    defer { window.close() }
    var queries: [String] = []
    bar.onQueryChange = { queries.append($0) }
    bar.selectionLabel = "Old account result"
    editor.setMarkedText("日本", selectedRange: NSRange(location: 1, length: 0),
                         replacementRange: NSRange(location: NSNotFound, length: 0))
    bar.setQuery("old external replacement")

    bar.resetForSession(query: "")

    #expect(queries.isEmpty)
    #expect(!editor.hasMarkedText())
    #expect(editor.string.isEmpty && bar.textField.stringValue.isEmpty)
    #expect(bar.textField.currentEditor() == nil)
    #expect(!bar.isExpanded)
    #expect(bar.selectionLabel == nil && bar.textField.accessibilityHelp() == nil)

    bar.setExpanded(true)
    let reopenedEditor = try #require(bar.textField.currentEditor() as? NSTextView)
    #expect(window.firstResponder === reopenedEditor)
    #expect(reopenedEditor.string.isEmpty)
    reopenedEditor.insertText("new account", replacementRange: reopenedEditor.selectedRange())
    #expect(queries == ["new account"])
    #expect(reopenedEditor.string == "new account")
}
