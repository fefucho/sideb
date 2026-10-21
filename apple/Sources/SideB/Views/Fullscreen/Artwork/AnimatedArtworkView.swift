import AppKit
import AVFoundation
import SideBCore
import SwiftUI

/// The native child is its own lifecycle/observation boundary; video never publishes frame times.
struct AnimatedArtworkView: View {
    let track: SongItemRecord?
    let sessionID: UUID
    let core: SideBCore?
    let isPlaying: Bool
    let isPresented: Bool
    let isFlipped: Bool
    var audioDuration: Double? = nil
    @AppStorage(HomeAppearance.animatedArtworkKey, store: HomeAppearance.preferences) private var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AnimatedArtworkSurface(track: track, sessionID: sessionID, core: core,
                               audioDuration: audioDuration,
                               policy: AnimatedArtworkPolicy(enabled: enabled, presented: isPresented,
                                                             playing: isPlaying, flipped: isFlipped,
                                                             constrained: reduceMotion))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct AnimatedArtworkSurface: NSViewRepresentable {
    let track: SongItemRecord?
    let sessionID: UUID
    let core: SideBCore?
    let audioDuration: Double?
    let policy: AnimatedArtworkPolicy

    func makeNSView(context: Context) -> ArtworkSurface { ArtworkSurface() }

    func updateNSView(_ view: ArtworkSurface, context: Context) {
        view.configure(track: track, sessionID: sessionID, core: core, policy: policy, audioDuration: audioDuration)
    }

    static func dismantleNSView(_ view: ArtworkSurface, coordinator: ()) { view.detach() }

    @MainActor
    final class ArtworkSurface: NSView {
        private let controller = AnimatedArtworkController()
        private var track: SongItemRecord?
        private var sessionID = UUID()
        private var core: SideBCore?
        private var audioDuration: Double?
        private var inputPolicy = AnimatedArtworkPolicy()
        private var observations: [NSObjectProtocol] = []
        private var memorySource: DispatchSourceMemoryPressure?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.addSublayer(controller.layer)
            setAccessibilityElement(false)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            controller.layer.frame = bounds
            CATransaction.commit()
        }

        func configure(track: SongItemRecord?, sessionID: UUID, core: SideBCore?, policy: AnimatedArtworkPolicy,
                       audioDuration: Double?) {
            self.track = track
            self.sessionID = sessionID
            self.core = core
            self.audioDuration = audioDuration
            inputPolicy = policy
            updatePolicy()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else {
                updatePolicy()
                return
            }
            let center = NotificationCenter.default
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                observations.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        if note.name == NSWindow.willCloseNotification { self?.controller.detach() }
                        else { self?.updatePolicy() }
                    }
                })
            }
            for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification,
                         .NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
                observations.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updatePolicy() }
                })
            }
            let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.controller.memoryPressure() }
            }
            source.resume()
            memorySource = source
            updatePolicy()
        }

        private func updatePolicy() {
            var policy = inputPolicy
            policy.visible = window.map {
                $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) && !NSApp.isHidden
            } ?? false
            let process = ProcessInfo.processInfo
            policy.constrained = policy.constrained || process.isLowPowerModeEnabled
                || process.thermalState == .serious || process.thermalState == .critical
            let identity = track.map { AnimatedArtworkIdentity(track: $0, sessionID: sessionID) }
            guard let core, let track else {
                controller.update(identity: nil, policy: policy, fetch: nil, release: nil)
                return
            }
            // No web requests or signed URLs enter this view; Rust owns lookup, cache and leases.
            let audioDuration = audioDuration
            let fingerprint = AnimatedArtworkRequestFingerprint(track: track, storefront: "us", audioDuration: audioDuration)
            let cachePath = AnimatedArtworkManager.shared.cacheDirectory.path
            controller.update(identity: identity, policy: policy, fingerprint: fingerprint, fetch: { id, preferHevc in
                let request = AnimatedArtworkRequest(videoId: track.videoId, title: track.title,
                    artists: AnimatedArtworkIdentity.principalArtist(track), album: track.album, albumId: track.albumId,
                    durationSecs: ExperimentalLyricsRequest.effectiveDurationSeconds(metadata: track.duration, audioDuration: audioDuration),
                    storefront: "us", preferHevc: preferHevc)
                return try await core.prepareAnimatedArtwork(request: request, requestId: id, cacheDir: cachePath)
            }, release: { id in core.cancelAnimatedArtwork(requestId: id) })
        }

        func detach() {
            stopObserving()
            controller.detach()
            controller.layer.removeFromSuperlayer()
            core = nil
            track = nil
        }

        private func stopObserving() {
            observations.forEach(NotificationCenter.default.removeObserver)
            observations.removeAll()
            memorySource?.cancel()
            memorySource = nil
        }
    }
}
