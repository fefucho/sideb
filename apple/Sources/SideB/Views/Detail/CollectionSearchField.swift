import AppKit
import SwiftUI

/// Borderless native input inside the shared glass capsule, with window-scoped dismissal.
struct CollectionSearchField: NSViewRepresentable {
    @Binding var query: String

    func makeCoordinator() -> Coordinator { Coordinator(query: $query) }

    func makeNSView(context: Context) -> CollectionSearchControl {
        let control = CollectionSearchControl()
        control.field.delegate = context.coordinator
        context.coordinator.field = control.field
        control.clearButton.target = context.coordinator
        control.clearButton.action = #selector(Coordinator.clearSearch(_:))
        control.field.stringValue = query
        control.updateClearVisibility(query: query)
        return control
    }

    func updateNSView(_ control: CollectionSearchControl, context: Context) {
        context.coordinator.query = $query
        context.coordinator.synchronize(field: control.field, query: query)
        control.updateClearVisibility(query: query)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CollectionSearchControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 180, height: 20)
    }

    static func dismantleNSView(_ control: CollectionSearchControl, coordinator: Coordinator) {
        let field = control.field
        field.stopMonitoring()
        if let editor = field.currentEditor(), field.window?.firstResponder === editor {
            field.window?.makeFirstResponder(nil)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var query: Binding<String>
        weak var field: CollectionSearchTextField?

        init(query: Binding<String>) { self.query = query }

        @objc func clearSearch(_ sender: NSButton) {
            guard let field else { return }
            synchronize(field: field, query: "")
            query.wrappedValue = ""
        }

        func synchronize(field: CollectionSearchTextField, query: String) {
            // Keep the live editor and control value in sync when the clear button
            // changes the binding during editing. This avoids leaving stale text in
            // the window's shared field editor until the next focus transition.
            if let editor = field.currentEditor() as? NSTextView, editor.string != query {
                editor.string = query
                editor.setSelectedRange(NSRange(location: query.utf16.count, length: 0))
            }
            if field.stringValue != query { field.stringValue = query }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            query.wrappedValue = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}

/// Text and clear action share a stable native lifetime inside the glass capsule.
final class CollectionSearchControl: NSView {
    let field = CollectionSearchTextField()
    let clearButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        clearButton.isBordered = false
        clearButton.setButtonType(.momentaryChange)
        clearButton.focusRingType = .none
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Borrar búsqueda")
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.setAccessibilityLabel("Borrar búsqueda")
        clearButton.toolTip = "Borrar búsqueda"
        addSubview(field)
        addSubview(clearButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        field.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - 24), height: bounds.height)
        clearButton.frame = NSRect(x: max(0, bounds.width - 16), y: (bounds.height - 16) / 2, width: 16, height: 16)
    }

    func updateClearVisibility(query: String) {
        let visible = !query.isEmpty
        clearButton.alphaValue = visible ? 1 : 0
        clearButton.isEnabled = visible
        clearButton.setAccessibilityElement(visible)
    }
}

final class CollectionSearchTextField: NSTextField {
    private var clickMonitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = CollectionSearchTextFieldCell(textCell: "")
        isEditable = true; isSelectable = true
        isBezeled = false; drawsBackground = false; focusRingType = .none
        font = .systemFont(ofSize: 14.4); textColor = .labelColor
        placeholderString = "Buscar canciones"
        usesSingleLineMode = true
        setAccessibilityLabel("Buscar canciones en esta colección")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let eventWindow = event.window {
                self?.releaseFocusIfClickedOutside(in: eventWindow, at: event.locationInWindow)
            }
            return event
        }
    }

    func releaseFocusIfClickedOutside(in eventWindow: NSWindow, at point: NSPoint) {
        let editingControl: NSView = (superview as? CollectionSearchControl) ?? self
        guard let window, eventWindow === window,
              let editor = currentEditor(), window.firstResponder === editor,
              !editingControl.bounds.contains(editingControl.convert(point, from: nil)) else { return }
        window.makeFirstResponder(nil)
    }

    func stopMonitoring() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    deinit { if let clickMonitor { NSEvent.removeMonitor(clickMonitor) } }
}

/// AppKit asks the cell for its editor before focus/placeholder drawing. The
/// begin-editing notification arrives after typing, too late to prevent a flash.
final class CollectionSearchTextFieldCell: NSTextFieldCell {
    private let searchEditor: NSTextView = {
        let editor = CollectionSearchFieldEditor()
        editor.isFieldEditor = true
        editor.drawsBackground = false
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? { searchEditor }

    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj)
        editor.drawsBackground = false
        return editor
    }
}

/// Hosting environments can reapply the editor attributes after cell setup.
/// This editor belongs exclusively to the transparent collection search field.
final class CollectionSearchFieldEditor: NSTextView {
    override var drawsBackground: Bool {
        get { false }
        set { super.drawsBackground = false }
    }
}
