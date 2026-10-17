import AppKit

/// Capture the editor's owning control: AppKit may reuse its NSTextView elsewhere.
@MainActor
struct SearchFocusSnapshot {
    private(set) weak var window: NSWindow?
    private weak var target: NSResponder?
    private let selection: NSRange?

    init(window: NSWindow?) {
        self.window = window
        if let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor {
            target = editor.delegate as? NSResponder
            selection = editor.selectedRange()
        } else {
            target = window?.firstResponder
            selection = nil
        }
    }

    /// The caller also checks active window, route, session and search presentation.
    @discardableResult
    func restoreIfUnclaimed() -> Bool {
        guard let window, let target else { return false }
        if let view = target as? NSView {
            guard view.window === window, !view.isHiddenOrHasHiddenAncestor else { return false }
        } else if target !== window { return false }

        if let current = window.firstResponder as? NSTextView, current.isFieldEditor {
            if let owner = current.delegate as? NSView, owner.window === window,
               !owner.isHiddenOrHasHiddenAncestor { return false }
        } else if let current = window.firstResponder as? NSView,
                  current.window === window, !current.isHiddenOrHasHiddenAncestor {
            return false
        }
        guard window.makeFirstResponder(target) else { return false }
        if let selection, let field = target as? NSTextField, let editor = field.currentEditor() as? NSTextView {
            let count = (editor.string as NSString).length
            let location = min(selection.location, count)
            editor.setSelectedRange(NSRange(location: location, length: min(selection.length, count - location)))
        }
        return true
    }
}
