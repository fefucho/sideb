import AppKit
import SwiftUI

/// The drawn rail stays in SwiftUI; this native accessibility peer provides a
/// stable adjustable control and keyboard focus without intercepting its drag.
@MainActor
final class VolumeAccessibilityView: NSView {
    weak var player: PlayerViewModel?
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { L10n.text("player.volume") }
    override func accessibilityValue() -> Any? { NSNumber(value: player?.volume ?? 0) }
    override func accessibilityValueDescription() -> String? { VolumeScrollFeedback.percentage(player?.volume ?? 0) }
    override func accessibilityMinValue() -> Any? { NSNumber(value: 0) }
    override func accessibilityMaxValue() -> Any? { NSNumber(value: 1) }
    override func setAccessibilityValue(_ value: Any?) {
        guard let number = value as? NSNumber, let player else { return }
        let previous = player.volume
        player.volume = number.floatValue
        if player.volume != previous { NSAccessibility.post(element: self, notification: .valueChanged) }
    }
    override func accessibilityHelp() -> String? {
        L10n.text("player.volumeScrollHelp", args: [VolumeScrollFeedback.percentage(player?.volume ?? 0)])
    }
    override func accessibilityPerformIncrement() -> Bool { adjust(by: 1) }
    override func accessibilityPerformDecrement() -> Bool { adjust(by: -1) }
    private func adjust(by steps: Int) -> Bool {
        guard let player else { return false }
        let previous = player.volume
        player.volume = VolumeScrollPolicy.adjusting(player.volume, by: steps)
        if player.volume != previous { NSAccessibility.post(element: self, notification: .valueChanged) }
        return true
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 3), xRadius: 6, yRadius: 6).fill()
    }
    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 124, 126: _ = adjust(by: 1)
        case 123, 125: _ = adjust(by: -1)
        default: super.keyDown(with: event)
        }
    }
}

struct VolumeAccessibilityControl: NSViewRepresentable {
    let player: PlayerViewModel
    func makeNSView(context: Context) -> VolumeAccessibilityView {
        let view = VolumeAccessibilityView()
        view.focusRingType = .exterior
        view.player = player
        return view
    }
    func updateNSView(_ view: VolumeAccessibilityView, context: Context) {
        view.player = player
    }
}

enum PlayerVolumePresentation {
    static func muteAction(volume: Float) -> String { volume == 0 ? "player.unmute" : "player.mute" }
    static func icon(volume: Float) -> String {
        if volume == 0 { return "speaker.slash.fill" }
        if volume < 0.33 { return "speaker.wave.1.fill" }
        if volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
