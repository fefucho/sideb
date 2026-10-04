import AppKit
import WebKit

/// Native media links handle Space as activation rather than as the global playback shortcut.
protocol PlaybackSpaceControl: AnyObject {}

/// Routes an unmodified Space key to playback while the app is active and text is not being edited.
@MainActor
final class PlaybackSpaceShortcut {
    private weak var player: PlayerViewModel?
    private nonisolated(unsafe) var eventMonitor: Any?

    func install(player: PlayerViewModel) {
        self.player = player
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window = event.window, window.isKeyWindow,
              let player, player.currentTrack != nil,
              Self.isPlainSpace(event),
              Self.canHandleSpace(responder: window.firstResponder, windowID: ObjectIdentifier(window)) else {
            return event
        }

        // A held key sends repeats. Consume them without alternating playback repeatedly.
        if !event.isARepeat { player.togglePlayPause() }
        return nil
    }

    static func isPlainSpace(_ event: NSEvent) -> Bool {
        event.keyCode == 49 &&
        event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }

    static func canHandleSpace(responder: NSResponder?, windowID: ObjectIdentifier,
                               focusRegistry: PlaybackSpaceFocusRegistry? = nil) -> Bool {
        !isEditingText(responder) && !(responder is NSButton) && !(responder is NSSegmentedControl) &&
            !(responder is PlaybackSpaceControl) && !(focusRegistry ?? .shared).preservesNativeSpace(in: windowID)
    }

    static func isEditingText(_ responder: NSResponder?) -> Bool {
        switch responder {
        case let textView as NSTextView:
            return textView.isEditable
        case let textField as NSTextField:
            return textField.isEditable
        case is WKWebView:
            // The Google login page owns keyboard input inside its web content.
            return true
        default:
            return false
        }
    }
}

/// Explicit SwiftUI focus scopes avoid guessing whether an NSHostingView's
/// first responder belongs to a focused button or to the page beneath it.
@MainActor
final class PlaybackSpaceFocusRegistry {
    static let shared = PlaybackSpaceFocusRegistry()
    private var scopes: [UUID: ObjectIdentifier] = [:]

    func update(scope: UUID, windowID: ObjectIdentifier?, isFocused: Bool) {
        if isFocused, let windowID { scopes[scope] = windowID }
        else { scopes.removeValue(forKey: scope) }
    }

    func preservesNativeSpace(in windowID: ObjectIdentifier) -> Bool {
        scopes.values.contains(windowID)
    }
}

/// A noninteractive marker whose lifetime and window attachment bound the scope.
final class PlaybackSpaceFocusView: NSView {
    private let scope = UUID()
    var isControlFocused = false {
        didSet { updateScope() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScope()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func clearScope() {
        PlaybackSpaceFocusRegistry.shared.update(scope: scope, windowID: nil, isFocused: false)
    }

    private func updateScope() {
        PlaybackSpaceFocusRegistry.shared.update(scope: scope, windowID: window.map(ObjectIdentifier.init),
                                                 isFocused: isControlFocused)
    }
}
