import AppKit
import Observation

/// A pair of one-shot timers is reused throughout a burst; no work while idle.
@MainActor @Observable
final class VolumeScrollFeedback {
    private(set) var isVisible = false
    private(set) var contextRevision = 0
    var isCapsuleOpen = false
    var isDragging = false {
        didSet { if isDragging && !oldValue { cancel() } }
    }
    @ObservationIgnored private nonisolated(unsafe) var hideTimer: Timer?
    @ObservationIgnored private nonisolated(unsafe) var announcementTimer: Timer?
    @ObservationIgnored private var latestValue: Float = 0
    @ObservationIgnored var announce: (String) -> Void = { text in
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.low.rawValue])
    }
    static func percentage(_ value: Float, language: AppLanguage? = nil) -> String {
        let safe = value.isFinite ? min(1, max(0, value)) : 0
        return L10n.text("player.volumePercentage", args: [String(Int((safe * 100).rounded()))], language: language)
    }
    func receivedInput(in zone: VolumeScrollPolicy.Zone, value: Float, now: Date = Date()) {
        latestValue = value
        if zone == .fullscreen {
            isVisible = true
            if let hideTimer { hideTimer.fireDate = now.addingTimeInterval(0.9) }
            else {
                hideTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.hide() }
                }
            }
        }
        if let announcementTimer { announcementTimer.fireDate = now.addingTimeInterval(0.18) }
        else {
            announcementTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.announcementTimer = nil
                    self.announce(L10n.text("player.volumeValue", args: [Self.percentage(self.latestValue)]))
                }
            }
        }
    }
    func updateValue(_ value: Float) { latestValue = value }
    func hide() {
        hideTimer?.invalidate(); hideTimer = nil
        isVisible = false
    }
    func cancel() {
        contextRevision &+= 1
        clear()
    }
    func clear() {
        hide()
        announcementTimer?.invalidate(); announcementTimer = nil
    }
    deinit { hideTimer?.invalidate(); announcementTimer?.invalidate() }
}
