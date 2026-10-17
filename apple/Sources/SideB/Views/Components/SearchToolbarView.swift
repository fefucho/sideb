import AppKit

/// AppKit search control hosted by the navigation glass surface. Its owner drives
/// the outer width and calls `applyExpansionProgress(_:)` on each animation step.
final class NativeSearchBar: NSView, NSTextFieldDelegate {
    static let collapsedSize = NSSize(width: 42, height: 42)

    let iconButton = NSButton()
    let textField = SearchToolbarInputField()
    let closeButton = NSButton()

    var onToggleExpand: ((Bool) -> Void)?
    var onQueryChange: ((String) -> Void)?
    var onSubmit: ((String) -> Void)?
    var onMoveSelection: ((Int) -> Void)?
    var selectionLabel: String? {
        didSet {
            guard selectionLabel != oldValue else { return }
            textField.setAccessibilityHelp(selectionLabel)
        }
    }

    private(set) var isExpanded = false
    private var expansionProgress: CGFloat = 0
    private var hasFocusedForCurrentExpansion = false
    private var appliedLocalizationRevision: Int?
    private var controlsAreInteractive = false
    private var lastConfirmedQuery = ""
    private var deferredExternalQuery: String?
    private var isResettingSession = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = true

        iconButton.isBordered = false
        iconButton.setButtonType(.momentaryChange)
        iconButton.imagePosition = .imageOnly
        iconButton.focusRingType = .none
        iconButton.contentTintColor = .labelColor
        iconButton.target = self
        iconButton.action = #selector(toggleFromIcon)
        iconButton.image = Self.symbol("magnifyingglass", size: 16, label: L10n.text("search.spotlight.prompt_title"))
        iconButton.setAccessibilityLabel(L10n.text("search.spotlight.prompt_title"))
        addSubview(iconButton)

        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 14.5, weight: .regular)
        textField.textColor = .labelColor
        textField.usesSingleLineMode = true
        textField.delegate = self
        textField.alphaValue = 0
        textField.isHidden = true
        textField.setAccessibilityElement(false)
        textField.onEscape = { [weak self] in self?.requestCollapse() }
        textField.onConfirmedInput = { [weak self] in self?.acceptConfirmedInput() }
        addSubview(textField)

        closeButton.isBordered = false
        closeButton.setButtonType(.momentaryChange)
        closeButton.imagePosition = .imageOnly
        closeButton.focusRingType = .none
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeOrClear)
        closeButton.alphaValue = 0
        closeButton.isHidden = true
        closeButton.setAccessibilityElement(false)
        addSubview(closeButton)
        updateLocalization()
    }

    convenience init() { self.init(frame: NSRect(origin: .zero, size: Self.collapsedSize)) }
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { Self.collapsedSize }
    override var fittingSize: NSSize { Self.collapsedSize }

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        hasFocusedForCurrentExpansion = false
        setInteractiveVisibility(expanded || expansionProgress >= 0.12)
        if expanded {
            // Focus is semantic, independent of the glass morph. A zero-width
            // field can own its editor and receive typing before its first frame.
            hasFocusedForCurrentExpansion = focusField()
        } else {
            unfocusField()
        }
    }

    func applyExpansionProgress(_ progress: CGFloat) {
        let nextProgress = min(1, max(0, progress))
        if expansionProgress != nextProgress {
            expansionProgress = nextProgress
            let alpha = min(1, max(0, (expansionProgress - 0.22) / 0.68))
            if textField.alphaValue != alpha { textField.alphaValue = alpha }
            if closeButton.alphaValue != alpha { closeButton.alphaValue = alpha }
        }

        setInteractiveVisibility(isExpanded || expansionProgress >= 0.12)
        // Retry attachment without waiting for a display-link tick or progress.
        if isExpanded, !hasFocusedForCurrentExpansion {
            hasFocusedForCurrentExpansion = focusField()
        }
    }

    func setQuery(_ query: String) {
        if let editor = textField.currentEditor() as? NSTextView, editor.hasMarkedText() {
            // The model echoes the last confirmed value while candidates are being
            // composed. Only a different, explicit replacement is deferred; repeated
            // model updates must not erase marked text or reset its UTF-16 selection.
            guard query != lastConfirmedQuery, query != editor.string else { return }
            deferredExternalQuery = query
            return
        }
        applyQuery(query)
    }

    private func applyQuery(_ query: String) {
        guard displayedQuery != query || lastConfirmedQuery != query else { return }
        if let editor = textField.currentEditor() as? NSTextView {
            if editor.string != query {
                let selection = editor.selectedRange()
                editor.string = query
                let location = min(selection.location, query.utf16.count)
                editor.setSelectedRange(NSRange(location: location,
                    length: min(selection.length, query.utf16.count - location)))
            }
            // Setting stringValue while editing reconfigures the field editor even
            // for an echo. Let AppKit synchronize its cell when editing finishes.
        } else if textField.stringValue != query {
            textField.stringValue = query
        }
        lastConfirmedQuery = query
        updateCloseLabel(clearLabel: L10n.text("detail.search.clear"))
    }

    private var displayedQuery: String {
        (textField.currentEditor() as? NSTextView)?.string ?? textField.stringValue
    }

    private func acceptConfirmedInput() {
        guard !isResettingSession else { return }
        if let editor = textField.currentEditor() as? NSTextView {
            guard !editor.hasMarkedText(), !textField.isPerformingInput else { return }
        }
        let previousQuery = lastConfirmedQuery
        if let replacement = deferredExternalQuery {
            deferredExternalQuery = nil
            // A real external replacement takes precedence after the IME finishes.
            // Publish only the reconciled confirmed value, never intermediate marks.
            applyQuery(replacement)
        } else {
            lastConfirmedQuery = displayedQuery
        }
        updateCloseLabel(clearLabel: L10n.text("detail.search.clear"))
        if lastConfirmedQuery != previousQuery { onQueryChange?(lastConfirmedQuery) }
    }

    @discardableResult
    func focusField() -> Bool {
        guard let window else { return false }
        return window.makeFirstResponder(textField)
    }

    /// Explicitly re-arm focus, for example when ⌘F is pressed while already expanded.
    func requestFocus() {
        guard isExpanded else { return }
        setInteractiveVisibility(true)
        hasFocusedForCurrentExpansion = focusField()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            hasFocusedForCurrentExpansion = false
        } else if isExpanded, !hasFocusedForCurrentExpansion {
            setInteractiveVisibility(true)
            hasFocusedForCurrentExpansion = focusField()
        }
    }

    /// An account boundary is authoritative even when its empty query resembles
    /// a model echo during IME input. Discard candidates and deferred replacements
    /// quietly, then release focus; a later expansion acquires a fresh editor.
    func resetForSession(query: String) {
        isResettingSession = true
        defer { isResettingSession = false }
        deferredExternalQuery = nil
        let editor = textField.searchEditor
        editor.inputContext?.discardMarkedText()
        if editor.hasMarkedText() { editor.unmarkText() }
        editor.string = query
        editor.setSelectedRange(NSRange(location: query.utf16.count, length: 0))
        isExpanded = false
        unfocusField()
        // End-editing updates the cell, so assign after it has released the editor.
        textField.stringValue = query
        editor.string = query
        lastConfirmedQuery = query
        deferredExternalQuery = nil
        hasFocusedForCurrentExpansion = false
        selectionLabel = nil
        setInteractiveVisibility(false)
        updateCloseLabel(clearLabel: L10n.text("detail.search.clear"))
    }

    func unfocusField() {
        guard let window, let editor = textField.currentEditor(), window.firstResponder === editor else { return }
        _ = window.makeFirstResponder(nil)
    }

    func updateLocalization() {
        let revision = L10n.revision
        guard appliedLocalizationRevision != revision else { return }
        appliedLocalizationRevision = revision
        let searchLabel = L10n.text("search.spotlight.placeholder")
        let clearLabel = L10n.text("detail.search.clear")
        textField.placeholderString = L10n.text("search.spotlight.placeholder")
        textField.setAccessibilityLabel(searchLabel)
        iconButton.image = Self.symbol("magnifyingglass", size: 16, label: searchLabel)
        iconButton.setAccessibilityLabel(searchLabel)
        closeButton.image = Self.symbol("xmark.circle.fill", size: 16, label: clearLabel)
        updateCloseLabel(clearLabel: clearLabel)
    }

    override func layout() {
        super.layout()
        // Geometry follows the resized bounds independently of expansion progress.
        iconButton.frame = NSRect(x: 0, y: 0, width: 42, height: bounds.height)
        let closeWidth: CGFloat = 36
        closeButton.frame = NSRect(x: max(42, bounds.width - closeWidth), y: 0, width: closeWidth, height: bounds.height)
        // A borderless NSTextField draws/edits at the top of its bounds. Giving it
        // extra height centers its frame but raises the glyphs and caret. Size the
        // field to AppKit's natural cell line box so display, placeholder and field
        // editor share the same baseline, then center that box in the glass.
        let textHeight = textField.cell?.cellSize.height ?? textField.intrinsicContentSize.height
        textField.frame = NSRect(x: 40, y: (bounds.height - textHeight) / 2,
                                 width: max(0, bounds.width - 40 - closeWidth - 2), height: textHeight)
    }

    func controlTextDidChange(_ notification: Notification) {
        acceptConfirmedInput()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        acceptConfirmedInput()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Candidate navigation/confirmation/cancellation belongs to the input
        // manager. Returning false lets NSTextView handle it through AppKit.
        guard !textView.hasMarkedText() else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            requestCollapse()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let onSubmit {
                onSubmit(displayedQuery)
            } else {
                requestCollapse()
            }
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            onMoveSelection?(-1)
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            onMoveSelection?(1)
            return true
        }
        return false
    }

    private func setInteractiveVisibility(_ visible: Bool) {
        guard controlsAreInteractive != visible else { return }
        controlsAreInteractive = visible
        for control in [textField as NSView, closeButton as NSView] {
            if control.isHidden == visible { control.isHidden = !visible }
            control.setAccessibilityElement(visible)
        }
        closeButton.isEnabled = visible
        textField.isEnabled = visible
    }

    func requestCollapse() {
        guard isExpanded else { return }
        setExpanded(false)
        onToggleExpand?(false)
    }

    private func updateCloseLabel(clearLabel: String) {
        let label = displayedQuery.isEmpty ? L10n.text("common.closeEscape") : clearLabel
        closeButton.setAccessibilityLabel(label)
        closeButton.toolTip = label
    }

    @objc private func toggleFromIcon() {
        let expanded = !isExpanded
        setExpanded(expanded)
        onToggleExpand?(expanded)
    }

    @objc private func closeOrClear() {
        if !displayedQuery.isEmpty {
            if let editor = textField.currentEditor() as? NSTextView, editor.hasMarkedText() {
                deferredExternalQuery = ""
                editor.unmarkText()
            } else {
                setQuery("")
                onQueryChange?("")
            }
        } else {
            requestCollapse()
        }
    }

    private static func symbol(_ name: String, size: CGFloat, label: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .medium))
    }
}

final class SearchToolbarInputField: NSTextField {
    var onEscape: (() -> Void)?
    var onConfirmedInput: (() -> Void)?
    fileprivate let searchEditor = SearchToolbarFieldEditor()
    var isPerformingInput: Bool { searchEditor.inputDepth > 0 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = SearchToolbarInputCell(textCell: "")
        isEditable = true
        isSelectable = true
        searchEditor.isFieldEditor = true
        searchEditor.onConfirmedInput = { [weak self] in self?.onConfirmedInput?() }
    }

    required init?(coder: NSCoder) { nil }

    override func cancelOperation(_ sender: Any?) {
        if let editor = currentEditor() as? NSTextView, editor.hasMarkedText() {
            super.cancelOperation(sender)
            return
        }
        onEscape?()
    }
}

/// A dedicated editor makes `unmarkText` observable even when accepting a
/// candidate does not change the string and therefore emits no textDidChange.
private final class SearchToolbarInputCell: NSTextFieldCell {
    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        (controlView as? SearchToolbarInputField)?.searchEditor
    }
}

private final class SearchToolbarFieldEditor: NSTextView {
    var onConfirmedInput: (() -> Void)?
    private(set) var inputDepth = 0

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        inputDepth += 1
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        finishInput()
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        inputDepth += 1
        super.insertText(string, replacementRange: replacementRange)
        finishInput()
    }

    override func unmarkText() {
        inputDepth += 1
        super.unmarkText()
        finishInput()
    }

    private func finishInput() {
        inputDepth -= 1
        if inputDepth == 0, !hasMarkedText() { onConfirmedInput?() }
    }
}
