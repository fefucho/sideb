import AppKit
import SwiftUI
import SideBCore
import XCTest
@testable import SideB

final class VolumeScrollPolicyTests: XCTestCase {
    private func input(_ y: Double, x: Double = 0, precise: Bool = true,
                       phase: VolumeScrollPolicy.Phase = .changed, time: Double = 1) -> VolumeScrollPolicy.Input {
        .init(x: x, y: y, precise: precise, phase: phase, timestamp: time)
    }

    func testDiscreteEventsUseOnePointWhateverDriverDeltaAndRetainFraction() {
        var policy = VolumeScrollPolicy()
        for delta in [0.1, 1, 120, Double.greatestFiniteMagnitude] {
            let result = policy.handle(input(delta, precise: false, phase: .none), zone: .capsule, value: 0.423)
            XCTAssertTrue(result.consume)
            XCTAssertEqual(result.steps, 1)
            XCTAssertEqual(VolumeScrollPolicy.adjusting(0.423, by: result.steps), 0.433, accuracy: 0.000001)
        }
        XCTAssertEqual(policy.handle(input(-120, precise: false, phase: .none), zone: .capsule, value: 0.423).steps, -1)
    }

    func testPreciseDistanceIsIndependentOfEventCount() {
        for chunks in [[40.0], [8,8,8,8,8], Array(repeating: 0.5, count: 80)] {
            var policy = VolumeScrollPolicy()
            var steps = 0
            for (index, delta) in chunks.enumerated() {
                steps += policy.handle(input(delta, phase: index == 0 ? .began : .changed), zone: .fullscreen, value: 0.42).steps
            }
            XCTAssertEqual(steps, 5)
        }
    }

    func testRemainderReversalJitterAndNoDebtAtLimit() {
        var policy = VolumeScrollPolicy()
        XCTAssertEqual(policy.handle(input(7, phase: .began), zone: .fullscreen, value: 0.42).steps, 0)
        XCTAssertEqual(policy.handle(input(-8), zone: .fullscreen, value: 0.42).steps, -1)
        XCTAssertEqual(policy.handle(input(-0.05, x: 0.02), zone: .fullscreen, value: 0.42).steps, 0)
        XCTAssertTrue(policy.handle(input(500), zone: .fullscreen, value: 1).consume)
        XCTAssertEqual(policy.handle(input(-8), zone: .fullscreen, value: 1).steps, -1)
        XCTAssertEqual(VolumeScrollPolicy.adjusting(0.01, by: -1), 0)
        XCTAssertEqual(VolumeScrollPolicy.adjusting(0, by: 1), 0.01)
    }

    func testHorizontalAmbiguousModifiedAndInvalidInputsStayOutside() {
        for event in [input(8, x: 8, phase: .began), input(2, x: 20, phase: .began),
                      input(.nan, phase: .began), input(.infinity, phase: .began),
                      .init(y: 8, phase: .began, modified: true)] {
            var policy = VolumeScrollPolicy()
            XCTAssertFalse(policy.handle(event, zone: .fullscreen, value: 0.42).consume)
            XCTAssertFalse(policy.handle(input(80), zone: .fullscreen, value: 0.42).consume)
        }
        var policy = VolumeScrollPolicy()
        XCTAssertEqual(policy.handle(input(.greatestFiniteMagnitude, phase: .began), zone: .fullscreen, value: 0.42).steps, 100)
        XCTAssertTrue(policy.handle(input(.infinity), zone: .fullscreen, value: 0.42).consume)
        XCTAssertEqual(policy.handle(input(80), zone: .fullscreen, value: 0.42).steps, 0)
    }

    func testOutsideContactNeverAdoptsHoverAndOwnedContactDrainsAfterLeaving() {
        var policy = VolumeScrollPolicy()
        XCTAssertFalse(policy.handle(input(8, phase: .began), zone: nil, value: 0.42).consume)
        XCTAssertFalse(policy.handle(input(80), zone: .fullscreen, value: 0.42).consume)
        XCTAssertFalse(policy.handle(.init(y: 80, momentum: .changed), zone: .fullscreen, value: 0.42).consume)
        XCTAssertEqual(policy.handle(input(8, phase: .began), zone: .fullscreen, value: 0.42).steps, 1)
        XCTAssertTrue(policy.handle(input(8), zone: nil, value: 0.43).consume)
        XCTAssertEqual(policy.handle(input(80), zone: .fullscreen, value: 0.43).steps, 0)
        XCTAssertTrue(policy.handle(.init(phase: .ended), zone: nil, value: 0.43).consume)
        let momentum = policy.handle(.init(y: 80, momentum: .changed), zone: nil, value: 0.43)
        XCTAssertTrue(momentum.consume)
        XCTAssertEqual(momentum.steps, 0)
        _ = policy.handle(.init(momentum: .ended), zone: nil, value: 0.43)
        XCTAssertEqual(policy.handle(input(-8, phase: .began), zone: .fullscreen, value: 0.43).steps, -1)
    }

    func testFinishedAndExpiredContactsDoNotNeedPointerTreeWalks() {
        var policy = VolumeScrollPolicy()
        _ = policy.handle(input(1, precise: false, phase: .none, time: 1), zone: .capsule, value: 0.42)
        XCTAssertFalse(policy.requiresPointerValidation(at: 1.01))
        XCTAssertTrue(policy.isOwned) // Still drains its own momentum.
        _ = policy.handle(input(8, phase: .began, time: 2), zone: .fullscreen, value: 0.42)
        XCTAssertTrue(policy.requiresPointerValidation(at: 2.01))
        _ = policy.handle(.init(phase: .ended, timestamp: 2.02), zone: .fullscreen, value: 0.42)
        XCTAssertFalse(policy.requiresPointerValidation(at: 2.03))
        _ = policy.handle(input(8, phase: .none, time: 3), zone: .fullscreen, value: 0.42)
        XCTAssertTrue(policy.requiresPointerValidation(at: 3.1))
        XCTAssertFalse(policy.requiresPointerValidation(at: 3.2))
    }

    func testUnphasedPreciseContactExpiresAfterInactivityAndCancellationDrains() {
        var policy = VolumeScrollPolicy()
        XCTAssertFalse(policy.handle(input(8, phase: .none, time: 1), zone: nil, value: 0.42).consume)
        XCTAssertFalse(policy.handle(input(8, phase: .none, time: 1.1), zone: .fullscreen, value: 0.42).consume)
        XCTAssertEqual(policy.handle(input(8, phase: .none, time: 1.3), zone: .fullscreen, value: 0.42).steps, 1)
        policy.invalidate()
        XCTAssertTrue(policy.handle(input(8, phase: .none, time: 1.4), zone: .fullscreen, value: 0.42).consume)
        XCTAssertEqual(policy.handle(input(8, phase: .none, time: 1.4), zone: .fullscreen, value: 0.42).steps, 0)
        XCTAssertEqual(policy.handle(input(8, phase: .none, time: 1.7), zone: .fullscreen, value: 0.42).steps, 1)
        XCTAssertTrue(policy.handle(.init(phase: .cancelled), zone: .fullscreen, value: 0.42).finished)
    }
}

@MainActor
final class VolumeScrollIntegrationTests: XCTestCase {
    private func track(_ id: String = "volume-track") -> SongItemRecord {
        SongItemRecord(videoId: id, title: "Track", artists: "Artist", album: nil, duration: "2:00",
                       thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil,
                       isVideo: false, isUpload: false, library: nil)
    }
    private func isolatedPlayer() -> (PlayerViewModel, UserDefaults, String, URL) {
        let suite = "VolumeScrollTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
        let player = PlayerViewModel(rustCore: nil, audioService: audio, playbackStore: PlaybackStateStore(directory: directory))
        player.volumeScroll.announce = { _ in }
        return (player, preferences, suite, directory)
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func coordinator(_ player: PlayerViewModel, fullscreen: Bool, dismissed: @escaping () -> Void = {}) -> WindowNavigationCoordinator {
        let result = WindowNavigationCoordinator(performHaptic: {})
        result.setup(router: NavigationRouter(), presentation: WindowGesturePresentation(), isFullscreenPresented: fullscreen,
                     canHandleGestures: true, reduceMotion: true, volumePlayer: player, onDismissFullscreen: dismissed)
        return result
    }

    func testRealFullscreenMarkersShieldRetainedPageAndExcludePanelAndMetadata() throws {
        let (player, preferences, suite, directory) = isolatedPlayer()
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        player.currentTrack = track()
        player.isFullscreenPresented = true
        let host = NSHostingView(rootView: ZStack {
            Color.clear.windowGestureRegion(.volumeFullscreen) // A retained volume surface must not capture through the scene.
            FullscreenCanvas(viewModel: player, isSidebarExpanded: .constant(false), router: nil)
        })
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 800)
        host.layoutSubtreeIfNeeded()
        let markers = descendants(host).compactMap { $0 as? WindowGestureRegionView }
        let scene = try XCTUnwrap(markers.first { $0.region == .volumeExcluded })
        let panel = try XCTUnwrap(markers.first { $0.region == .verticalContent && $0.isRegionActive })
        let metadata = try XCTUnwrap(markers.first { $0.region == .excluded && $0.bounds.height < 200 })
        func center(_ marker: NSView) -> NSPoint { marker.convert(NSPoint(x: marker.bounds.midX, y: marker.bounds.midY), to: host) }
        let point = scene.convert(NSPoint(x: 20, y: 20), to: host)
        XCTAssertNil(WindowGestureRegions.volumeZone(at: point, in: host))
        XCTAssertNil(WindowGestureRegions.volumeZone(at: center(panel), in: host))
        XCTAssertNil(WindowGestureRegions.volumeZone(at: center(metadata), in: host))
        // Placeholder is a volume surface too, with no artwork/network prerequisite.
        let layout = FullscreenSidebarGeometry(canvasSize: host.bounds.size, progress: 0).metrics
        let artworkPoint = NSPoint(x: layout.horizontalPadding + layout.leftWidth / 2,
                                  y: layout.topPadding + layout.availableContentHeight / 2 - layout.metadataHeight / 2)
        XCTAssertEqual(WindowGestureRegions.volumeZone(at: artworkPoint, in: host), .fullscreen)
        player.volume = 0.42
        var dismissed = 0
        let adapter = coordinator(player, fullscreen: true) { dismissed += 1 }
        let backgroundZone = WindowGestureRegions.volumeZone(at: point, in: host)
        let artworkZone = WindowGestureRegions.volumeZone(at: artworkPoint, in: host)
        XCTAssertFalse(adapter.handleVolumeInput(.init(y: 8, phase: .began, timestamp: 1), zone: backgroundZone, enabled: true))
        XCTAssertFalse(adapter.handleVolumeInput(.init(y: 80, phase: .changed, timestamp: 1.01), zone: artworkZone, enabled: true))
        XCTAssertEqual(player.volume, 0.42, accuracy: 0.000001)
        XCTAssertFalse(player.volumeScroll.isVisible)
        XCTAssertTrue(adapter.scrollContext(at: point, in: host, enabled: true).allowsFullscreenDismissal)
        XCTAssertFalse(adapter.scrollContext(at: artworkPoint, in: host, enabled: true).allowsFullscreenDismissal)
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 8, phase: .began, timestamp: 2), zone: artworkZone, enabled: true))
        XCTAssertEqual(player.volume, 0.43, accuracy: 0.000001)
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 80, phase: .changed, timestamp: 2.01), zone: backgroundZone, enabled: true))
        XCTAssertFalse(player.volumeScroll.isVisible)
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 80, phase: .changed, timestamp: 2.02), zone: artworkZone, enabled: true))
        XCTAssertEqual(player.volume, 0.43, accuracy: 0.000001)
        XCTAssertEqual(dismissed, 0)
        XCTAssertTrue(player.isFullscreenPresented)
        player.dismissFullscreen()
        XCTAssertFalse(player.isFullscreenPresented)
        XCTAssertFalse(player.volumeScroll.isVisible)
        adapter.detach()
    }

    func testFullscreenPullAndClosingSurviveVolumeHoverCancellation() {
        for cancelWhileClosing in [false, true] {
            let (player, preferences, suite, directory) = isolatedPlayer()
            defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
            player.currentTrack = track(); player.isFullscreenPresented = true; player.volume = 0.42
            let router = NavigationRouter()
            var completions: [() -> Void] = []
            let presentation = WindowGesturePresentation(animateSettlement: { _, update, complete in
                update(); completions.append(complete)
            })
            var closed = 0
            let adapter = WindowNavigationCoordinator(performHaptic: {}, interactionIsAllowed: { true })
            func configure() {
                adapter.setup(router: router, presentation: presentation, isFullscreenPresented: true,
                    canHandleGestures: true, reduceMotion: true, volumePlayer: player,
                    onDismissFullscreen: { closed += 1 })
            }
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
            let background = WindowGestureRegionView(frame: root.bounds)
            background.region = .volumeExcluded; root.addSubview(background)
            let point = NSPoint(x: 50, y: 650)
            configure()
            // Follow the monitor's real ordering: volume declines, then navigation owns the contact.
            XCTAssertFalse(adapter.handleVolumeInput(.init(y: -200, phase: .began, timestamp: 1), zone: nil, enabled: true))
            XCTAssertEqual(adapter.handleScrollInput(.init(deltaY: 200, phase: .began), enabled: true) {
                adapter.scrollContext(at: point, in: root, enabled: true)
            }.disposition, .consume)
            XCTAssertEqual(presentation.fullscreenStage, .pulling)
            XCTAssertTrue(presentation.fullscreenArmed)
            if cancelWhileClosing {
                XCTAssertFalse(adapter.handleVolumeInput(.init(phase: .ended, timestamp: 1.01), zone: nil, enabled: true))
                XCTAssertEqual(adapter.handleScrollInput(.init(phase: .ended), enabled: true) {
                    XCTFail("The release must keep the captured owner"); return .init(mode: .fullscreen)
                }.commit, .dismissFullscreen)
            }
            let previousStage = presentation.fullscreenStage
            let previousOffset = presentation.fullscreenOffset
            player.volumeScroll.cancel() // Canvas onHover(false) while it slides under the pointer.
            configure() // SwiftUI updates the bridge because the volume context revision changed.
            XCTAssertEqual(presentation.fullscreenStage, previousStage)
            XCTAssertEqual(presentation.fullscreenOffset, previousOffset)
            if !cancelWhileClosing {
                XCTAssertFalse(adapter.handleVolumeInput(.init(phase: .ended, timestamp: 1.01), zone: nil, enabled: true))
                XCTAssertEqual(adapter.handleScrollInput(.init(phase: .ended), enabled: true) {
                    XCTFail("Hover cancellation must not start a new navigation contact"); return .init(mode: .fullscreen)
                }.commit, .dismissFullscreen)
            }
            XCTAssertEqual(presentation.fullscreenStage, .closing)
            XCTAssertEqual(completions.count, 1)
            completions.first?()
            XCTAssertEqual(closed, 1)
            XCTAssertEqual(presentation.fullscreenStage, .idle)
            XCTAssertEqual(player.volume, 0.42)
            adapter.detach()
        }
    }

    func testVolumeHoverCancellationStillDrainsItsOwnContactAfterBridgeUpdate() {
        let (player, preferences, suite, directory) = isolatedPlayer()
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        player.currentTrack = track(); player.isFullscreenPresented = true; player.volume = 0.42
        let router = NavigationRouter()
        let presentation = WindowGesturePresentation()
        let adapter = WindowNavigationCoordinator(performHaptic: {})
        func configure() {
            adapter.setup(router: router, presentation: presentation, isFullscreenPresented: true,
                canHandleGestures: true, reduceMotion: true, volumePlayer: player,
                onDismissFullscreen: { XCTFail("A volume contact must not dismiss fullscreen") })
        }
        configure()
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 8, phase: .began, timestamp: 1), zone: .fullscreen, enabled: true))
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 8, phase: .changed, timestamp: 1.001), zone: .fullscreen, enabled: true))
        XCTAssertEqual(player.volume, 0.43, accuracy: 0.000001)
        player.volumeScroll.cancel()
        configure()
        XCTAssertEqual(player.volume, 0.44, accuracy: 0.000001) // Flush only the last owned frame.
        XCTAssertFalse(player.volumeScroll.isVisible)
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 80, phase: .changed, timestamp: 1.01), zone: .fullscreen, enabled: true))
        XCTAssertTrue(adapter.handleVolumeInput(.init(phase: .ended, timestamp: 1.02), zone: nil, enabled: true))
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 80, momentum: .changed, timestamp: 1.03), zone: .fullscreen, enabled: true))
        XCTAssertEqual(player.volume, 0.44, accuracy: 0.000001)
        XCTAssertFalse(player.volumeScroll.isVisible)
        XCTAssertEqual(presentation.fullscreenStage, .idle)
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 8, phase: .began, timestamp: 2), zone: .fullscreen, enabled: true))
        XCTAssertTrue(adapter.handleVolumeInput(.init(phase: .ended, timestamp: 2.01), zone: .fullscreen, enabled: true))
        XCTAssertEqual(player.volume, 0.45, accuracy: 0.000001)
        adapter.detach()
    }

    func testVolumeSceneNeverFallsBackToOldPullEvenForAmbiguousOrModifiedInput() {
        let (player, preferences, suite, directory) = isolatedPlayer()
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        player.currentTrack = track(); player.isFullscreenPresented = true
        let adapter = coordinator(player, fullscreen: true)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let scene = WindowGestureRegionView(frame: root.bounds); scene.region = .volumeFullscreen; root.addSubview(scene)
        let point = NSPoint(x: 200, y: 200)
        let context = adapter.scrollContext(at: point, in: root, enabled: true)
        XCTAssertFalse(context.allowsFullscreenDismissal)
        XCTAssertFalse(adapter.handleVolumeInput(.init(x: 10, y: 10, phase: .began, timestamp: 1), zone: .fullscreen, enabled: true))
        let ambiguous = adapter.handleScrollInput(.init(deltaX: 10, deltaY: 10, phase: .began), enabled: true) { context }
        XCTAssertNil(ambiguous.commit)
        XCTAssertNil(adapter.handleScrollInput(.init(deltaY: 400, phase: .changed), enabled: true) { context }.commit)
        XCTAssertNil(adapter.handleScrollInput(.init(phase: .ended), enabled: true) { context }.commit)
        XCTAssertTrue(player.isFullscreenPresented)
        adapter.detach()
    }

    func testForegroundResolutionAndOverflowingCapsule() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        @discardableResult func marker(_ region: WindowGestureRegion, _ rect: NSRect, in parent: NSView) -> WindowGestureRegionView {
            let result = WindowGestureRegionView(frame: rect); result.region = region; parent.addSubview(result); return result
        }
        marker(.excluded, root.bounds, in: root)
        let scene = NSView(frame: root.bounds); root.addSubview(scene)
        marker(.volumeFullscreen, scene.bounds, in: scene)
        marker(.verticalContent, NSRect(x: 500, y: 100, width: 350, height: 500), in: scene)
        XCTAssertEqual(WindowGestureRegions.volumeZone(at: NSPoint(x: 200, y: 200), in: root), .fullscreen)
        XCTAssertNil(WindowGestureRegions.volumeZone(at: NSPoint(x: 600, y: 200), in: root))
        let player = NSView(frame: NSRect(x: 100, y: 20, width: 700, height: 74)); root.addSubview(player)
        marker(.excluded, player.bounds, in: player)
        let slot = NSView(frame: NSRect(x: 600, y: 20, width: 32, height: 32)); player.addSubview(slot)
        let capsule = marker(.volumeCapsule, NSRect(x: -120, y: -2, width: 152, height: 36), in: slot)
        let point = capsule.convert(NSPoint(x: 30, y: 18), to: root)
        XCTAssertEqual(WindowGestureRegions.volumeZone(at: point, in: root), .capsule)
        capsule.isRegionActive = false
        XCTAssertNil(WindowGestureRegions.volumeZone(at: point, in: root))
        capsule.isRegionActive = true
        let front = marker(.excluded, root.bounds, in: root)
        XCTAssertNil(WindowGestureRegions.volumeZone(at: point, in: root))
        front.isHidden = true
        XCTAssertEqual(WindowGestureRegions.volumeZone(at: point, in: root), .capsule)
    }

    func testAdapterMaintainsPanelAndVolumeOwnershipAndFlushesLastFrame() {
        let (player, preferences, suite, directory) = isolatedPlayer()
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        player.currentTrack = track(); player.isFullscreenPresented = true; player.volume = 0.42
        let adapter = coordinator(player, fullscreen: true)
        XCTAssertFalse(adapter.handleVolumeInput(.init(y: 8, phase: .began, timestamp: 1), zone: nil, enabled: true))
        XCTAssertFalse(adapter.handleVolumeInput(.init(y: 80, phase: .changed, timestamp: 1.01), zone: .fullscreen, enabled: true))
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 8, phase: .began, timestamp: 2), zone: .fullscreen, enabled: true))
        XCTAssertEqual(player.volume, 0.43, accuracy: 0.000001)
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 8, phase: .changed, timestamp: 2.001), zone: .fullscreen, enabled: true))
        XCTAssertEqual(player.volume, 0.43, accuracy: 0.000001) // Coalesced until frame/terminal.
        XCTAssertTrue(adapter.handleVolumeInput(.init(phase: .ended, timestamp: 2.002), zone: .fullscreen, enabled: true))
        XCTAssertEqual(player.volume, 0.44, accuracy: 0.000001)
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 100, momentum: .changed), zone: nil, enabled: true))
        XCTAssertEqual(player.volume, 0.44, accuracy: 0.000001)
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 8, phase: .began, timestamp: 3), zone: .fullscreen, enabled: true))
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 8, phase: .changed, timestamp: 3.01), zone: nil, enabled: true))
        XCTAssertFalse(player.volumeScroll.isVisible)
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 80, phase: .changed, timestamp: 3.02), zone: .fullscreen, enabled: true))
        XCTAssertEqual(player.volume, 0.45, accuracy: 0.000001)
        adapter.detach()
    }

    func testCapsuleShowsCoverFeedbackInFullscreenAndTrackDragModalCancel() {
        let (player, preferences, suite, directory) = isolatedPlayer()
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        player.currentTrack = track(); player.isFullscreenPresented = true; player.volume = 0.42
        let adapter = coordinator(player, fullscreen: true)
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 1, precise: false, timestamp: 1), zone: .capsule, enabled: true))
        XCTAssertTrue(player.volumeScroll.isVisible)
        player.currentTrack = track("new-track")
        XCTAssertFalse(player.volumeScroll.isVisible)
        adapter.handleVolumeInput(.init(y: 8, phase: .began, timestamp: 2), zone: .fullscreen, enabled: true)
        player.volumeScroll.isDragging = true
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 80, phase: .changed, timestamp: 2.01), zone: .capsule, enabled: true))
        XCTAssertEqual(player.volume, 0.44, accuracy: 0.000001)
        XCTAssertFalse(player.volumeScroll.isVisible)
        player.volumeScroll.isDragging = false
        adapter.handleVolumeInput(.init(y: 8, phase: .began, timestamp: 3), zone: .fullscreen, enabled: true)
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 80, phase: .changed, timestamp: 3.1), zone: .fullscreen, enabled: false))
        XCTAssertFalse(player.volumeScroll.isVisible)
        XCTAssertEqual(player.volume, 0.45, accuracy: 0.000001)
        adapter.detach()
    }

    func testRealPlayerCapsulePreservesSlotAndNativeAXAtOnePercent() async throws {
        let (player, preferences, suite, directory) = isolatedPlayer()
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        player.volume = 0.01
        let host = NSHostingView(rootView: PlayerBarView(viewModel: player, isVolumeExpanded: true).windowGestureRegion(.excluded))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 820, height: 74)
        let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 820, height: 74),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        let marker = try XCTUnwrap(descendants(host).compactMap { $0 as? WindowGestureRegionView }.first { $0.region == .volumeCapsule })
        let frame = marker.convert(marker.bounds, to: host)
        XCTAssertEqual(frame.height, 36, accuracy: 0.5)
        XCTAssertGreaterThan(frame.width, 32)
        XCTAssertEqual(WindowGestureRegions.volumeZone(at: NSPoint(x: frame.minX + 20, y: frame.midY), in: host), .capsule)
        XCTAssertTrue(player.volumeScroll.isCapsuleOpen)
        let slider = try XCTUnwrap(descendants(host).compactMap { $0 as? VolumeAccessibilityView }.first)
        XCTAssertNil(slider.hitTest(.zero))
        XCTAssertTrue(slider.isAccessibilityElement())
        XCTAssertEqual(slider.accessibilityRole(), .slider)
        XCTAssertEqual(slider.accessibilityLabel(), L10n.text("player.volume"))
        XCTAssertEqual((slider.accessibilityValue() as? NSNumber)?.floatValue, 0.01)
        XCTAssertEqual(slider.accessibilityValueDescription(), VolumeScrollFeedback.percentage(0.01))
        XCTAssertEqual(PlayerVolumePresentation.muteAction(volume: player.volume), "player.mute")
        XCTAssertEqual(PlayerVolumePresentation.icon(volume: player.volume), "speaker.wave.1.fill")
        XCTAssertTrue(window.makeFirstResponder(slider))
        XCTAssertEqual(slider.focusRingType, .exterior)
        XCTAssertEqual(slider.focusRingMaskBounds, slider.bounds)
        for modifiers: NSEvent.ModifierFlags in [[], .command, .control, .option, .shift] {
            let previous = player.volume
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: 126))
            slider.keyDown(with: event)
            XCTAssertEqual(player.volume, modifiers.isEmpty ? previous + 0.01 : previous, accuracy: 0.000001)
        }
        player.volume = 0.01
        XCTAssertTrue(slider.accessibilityPerformIncrement())
        XCTAssertEqual(player.volume, 0.02, accuracy: 0.000001)
        XCTAssertTrue(slider.accessibilityPerformDecrement())
        XCTAssertEqual(player.volume, 0.01, accuracy: 0.000001)
        player.toggleMute()
        XCTAssertEqual(player.volume, 0)
        XCTAssertEqual(PlayerVolumePresentation.muteAction(volume: player.volume), "player.unmute")
        XCTAssertEqual(PlayerVolumePresentation.icon(volume: player.volume), "speaker.slash.fill")
        XCTAssertEqual(host.frame.size, CGSize(width: 820, height: 74))
        host.rootView = PlayerBarView(viewModel: player, isVolumeExpanded: false).windowGestureRegion(.excluded)
        window.contentView = nil
        await Task.yield()
        XCTAssertFalse(player.volumeScroll.isCapsuleOpen)
    }

    func testPendingFrameNeverOverwritesLaterMuteSliderOrAXAssignment() {
        let (player, preferences, suite, directory) = isolatedPlayer()
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let adapter = coordinator(player, fullscreen: false)
        for laterValue: Float in [0, 0.75, 0.43] {
            player.volume = 0.42
            adapter.handleVolumeInput(.init(y: 8, phase: .began, timestamp: 10), zone: .capsule, enabled: true)
            adapter.handleVolumeInput(.init(y: 8, phase: .changed, timestamp: 10.001), zone: .capsule, enabled: true)
            if laterValue == 0 { player.toggleMute() } else { player.volume = laterValue }
            adapter.handleVolumeInput(.init(phase: .ended, timestamp: 10.002), zone: .capsule, enabled: true)
            XCTAssertEqual(player.volume, laterValue, accuracy: 0.000001)
        }
        adapter.detach()
    }

    func testNewPlaybackGenerationOfSameTrackCancelsFeedback() {
        let (player, preferences, suite, directory) = isolatedPlayer()
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        player.currentTrack = track(); player.isFullscreenPresented = true
        let adapter = coordinator(player, fullscreen: true)
        adapter.handleVolumeInput(.init(y: -8, phase: .began, timestamp: 1), zone: .fullscreen, enabled: true)
        XCTAssertTrue(player.volumeScroll.isVisible)
        player.playSongNow(track(), deferStreamResolution: true)
        XCTAssertFalse(player.volumeScroll.isVisible)
        let volume = player.volume
        XCTAssertTrue(adapter.handleVolumeInput(.init(y: 80, phase: .changed, timestamp: 1.01), zone: .fullscreen, enabled: true))
        XCTAssertEqual(player.volume, volume)
        adapter.detach()
    }

    func testAudioSanitizesAndRestoresEveryPositiveVolumeIncludingWheelZero() {
        let suite = "VolumeAudioTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
        for value: Float in [0.01, 0.05, 0.42, 1] {
            audio.volume = value; audio.toggleMute()
            XCTAssertEqual(audio.volume, 0)
            let restored = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
            restored.toggleMute()
            XCTAssertEqual(restored.volume, value)
            audio.toggleMute()
            XCTAssertEqual(audio.volume, value)
        }
        audio.volume = 0.01
        audio.volume = VolumeScrollPolicy.adjusting(audio.volume, by: -1)
        XCTAssertEqual(audio.volume, 0)
        audio.toggleMute(); XCTAssertEqual(audio.volume, 0.01)
        audio.volume = 0
        audio.volume = VolumeScrollPolicy.adjusting(audio.volume, by: 1)
        XCTAssertEqual(audio.volume, 0.01)
        for invalid: Float in [.nan, .infinity, -.infinity] {
            audio.volume = invalid
            XCTAssertEqual(audio.volume, 0.01)
            XCTAssertEqual(audio.avPlayer.volume, 0.01)
        }
        audio.volume = 5; XCTAssertEqual(audio.volume, 1)
        audio.volume = -5; XCTAssertEqual(audio.volume, 0)
        preferences.set(0.01, forKey: "test.previousVolume")
        let legacy = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
        legacy.toggleMute(); XCTAssertEqual(legacy.volume, 0.01)
        preferences.set(-1, forKey: "test.previousVolume")
        preferences.set(0, forKey: "test.volume")
        let invalidPrevious = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
        invalidPrevious.toggleMute(); XCTAssertEqual(invalidPrevious.volume, 0.75)
    }

    func testFeedbackRearmsHidesCancelsAndDoesNotRetainOwner() async {
        let feedback = VolumeScrollFeedback()
        var announcements: [String] = []
        feedback.announce = { announcements.append($0) }
        feedback.receivedInput(in: .fullscreen, value: 0.42)
        XCTAssertTrue(feedback.isVisible)
        try? await Task.sleep(for: .milliseconds(550))
        feedback.receivedInput(in: .fullscreen, value: 0.43)
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(feedback.isVisible)
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(feedback.isVisible)
        XCTAssertEqual(announcements.last, L10n.text("player.volumeValue", args: [VolumeScrollFeedback.percentage(0.43)]))
        feedback.receivedInput(in: .fullscreen, value: 0.5)
        let count = announcements.count
        feedback.cancel()
        try? await Task.sleep(for: .milliseconds(220))
        XCTAssertFalse(feedback.isVisible)
        XCTAssertEqual(announcements.count, count)
        weak var released: VolumeScrollFeedback?
        do {
            let temporary = VolumeScrollFeedback(); released = temporary
            temporary.receivedInput(in: .fullscreen, value: 0.5)
        }
        XCTAssertNil(released)
        XCTAssertEqual(VolumeScrollFeedback.percentage(0.01, language: .es), "1 %")
        XCTAssertEqual(VolumeScrollFeedback.percentage(0.01, language: .en), "1%")
        XCTAssertEqual(VolumeScrollFeedback.percentage(.nan, language: .en), "0%")
    }
}
