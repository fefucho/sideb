import AppKit
import AVFoundation
import SideBCore
import SwiftUI

struct AnimatedArtworkSurfaceStyle: Equatable {
    var cornerRadius: CGFloat = 0
    var bottomFade: CGFloat = 0
}

/// The native child is its own lifecycle/observation boundary; video never publishes frame times.
struct AnimatedArtworkView: View {
    let track: SongItemRecord?
    let sessionID: UUID
    let core: SideBCore?
    let isPlaying: Bool
    let isPresented: Bool
    let isFlipped: Bool
    var audioDuration: Double? = nil
    var preferTall: Bool = false
    var suspended: Bool = false
    var prepareWhilePaused: Bool = false
    var surfaceStyle = AnimatedArtworkSurfaceStyle()
    var onFrameUnavailable: (() -> Void)? = nil
    var onFirstFrame: ((CGSize) -> Void)? = nil
    var onPreviewResolved: ((NSImage) -> Void)? = nil
    var onAssetResolved: ((CGSize) -> Void)? = nil
    @AppStorage(HomeAppearance.animatedArtworkKey, store: HomeAppearance.preferences) private var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = VisualProviderHost.shared.revision
        AnimatedArtworkSurface(track: track, sessionID: sessionID, core: core,
                               audioDuration: audioDuration, preferTall: preferTall,
                               onAssetResolved: onAssetResolved, onFrameUnavailable: onFrameUnavailable, onFirstFrame: onFirstFrame,
                               onPreviewResolved: onPreviewResolved, style: surfaceStyle,
                               policy: AnimatedArtworkPolicy(enabled: enabled, presented: isPresented,
                                                             playing: isPlaying, flipped: isFlipped,
                                                             constrained: reduceMotion, suspended: suspended, prepareWhilePaused: prepareWhilePaused))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct AnimatedArtworkSurface: NSViewRepresentable {
    let track: SongItemRecord?
    let sessionID: UUID
    let core: SideBCore?
    let audioDuration: Double?
    let preferTall: Bool
    let onAssetResolved: ((CGSize) -> Void)?
    let onFrameUnavailable: (() -> Void)?
    let onFirstFrame: ((CGSize) -> Void)?
    let onPreviewResolved: ((NSImage) -> Void)?
    let style: AnimatedArtworkSurfaceStyle
    let policy: AnimatedArtworkPolicy

    func makeNSView(context: Context) -> ArtworkSurface { ArtworkSurface() }

    func updateNSView(_ view: ArtworkSurface, context: Context) {
        view.configure(track: track, sessionID: sessionID, core: core, policy: policy, audioDuration: audioDuration,
                       preferTall: preferTall, onAssetResolved: onAssetResolved,
                       onFrameUnavailable: onFrameUnavailable, onFirstFrame: onFirstFrame, onPreviewResolved: onPreviewResolved, style: style)
    }

    static func dismantleNSView(_ view: ArtworkSurface, coordinator: ()) { view.detach() }

    @MainActor
    final class ArtworkSurface: NSView {
        private let controller = AnimatedArtworkController()
        private let fadeMask = CAGradientLayer()
        private var style = AnimatedArtworkSurfaceStyle()
        private var track: SongItemRecord?
        private var sessionID = UUID()
        private var core: SideBCore?
        private var audioDuration: Double?
        private var preferTall = false
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
            controller.layer.cornerRadius = style.cornerRadius
            controller.layer.masksToBounds = true
            if style.bottomFade > 0 {
                let start = 1 - min(1, max(0, style.bottomFade))
                fadeMask.frame = controller.layer.bounds
                fadeMask.startPoint = CGPoint(x: 0.5, y: 1)
                fadeMask.endPoint = CGPoint(x: 0.5, y: 0)
                fadeMask.colors = [NSColor.black.cgColor, NSColor.black.cgColor,
                                   NSColor.black.withAlphaComponent(0.88).cgColor,
                                   NSColor.black.withAlphaComponent(0.45).cgColor, NSColor.clear.cgColor]
                fadeMask.locations = [0, NSNumber(value: Double(start)),
                    NSNumber(value: Double(start + (1-start)*0.3)),
                    NSNumber(value: Double(start + (1-start)*0.7)), 1]
                controller.layer.mask = fadeMask
            } else { controller.layer.mask = nil }
            CATransaction.commit()
        }

        func configure(track: SongItemRecord?, sessionID: UUID, core: SideBCore?, policy: AnimatedArtworkPolicy,
                       audioDuration: Double?, preferTall: Bool = false, onAssetResolved: ((CGSize) -> Void)? = nil,
                       onFrameUnavailable: (() -> Void)? = nil, onFirstFrame: ((CGSize) -> Void)? = nil, onPreviewResolved: ((NSImage) -> Void)? = nil,
                       style: AnimatedArtworkSurfaceStyle = .init()) {
            self.track = track
            self.sessionID = sessionID
            self.core = core
            self.audioDuration = audioDuration
            self.preferTall = preferTall
            controller.onAssetResolved = onAssetResolved
            controller.onFrameUnavailable = onFrameUnavailable
            controller.onFirstFrame = onFirstFrame
            controller.onPreviewResolved = onPreviewResolved
            self.style = style
            needsLayout = true
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
                         .NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification,
                         .visualProviderWillChange] {
                observations.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        if name == .visualProviderWillChange {
                            if self?.preferTall == true { self?.controller.detach() }
                        }
                        else { self?.updatePolicy() }
                    }
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
            let host = VisualProviderHost.shared
            let providerSalt = preferTall ? host.identitySalt : nil
            let identity = track.map { AnimatedArtworkIdentity(track: $0, sessionID: sessionID, visualProviderSalt: providerSalt) }
            guard let core, let track else {
                controller.update(identity: nil, policy: policy, fetch: nil, release: nil)
                return
            }
            // The optional executable returns only a private local asset; core audio remains independent.
            let audioDuration = audioDuration
            let preferTall = preferTall
            let fingerprint = AnimatedArtworkRequestFingerprint(track: track, storefront: "us", audioDuration: audioDuration, preferTall: preferTall || providerSalt != nil)
            let cachePath = AnimatedArtworkManager.shared.cacheDirectory.path
            controller.update(identity: identity, policy: policy, fingerprint: fingerprint, fetch: { id, preferHevc in
                try await VisualProviderRouting.resolve(verticalPlayer: preferTall, extensionEnabled: providerSalt != nil, primary: {
                    let request = AnimatedArtworkRequest(videoId: track.videoId, title: track.title,
                        artists: AnimatedArtworkIdentity.principalArtist(track), album: track.album, albumId: track.albumId,
                        durationSecs: ExperimentalLyricsRequest.effectiveDurationSeconds(metadata: track.duration, audioDuration: audioDuration),
                        storefront: "us", preferHevc: preferHevc, preferTall: preferTall)
                    return try await core.prepareAnimatedArtwork(request: request, requestId: id, cacheDir: cachePath)
                }, secondary: {
                    try await host.prepare(track: track, duration: fingerprint.duration, requestID: id)
                })
            }, release: { id in
                host.release(id)
                core.cancelAnimatedArtwork(requestId: id)
            })
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
