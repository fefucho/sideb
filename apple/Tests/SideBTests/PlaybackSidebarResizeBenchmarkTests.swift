import AppKit
import SideBCore
import SwiftUI
import XCTest
@testable import SideB

/// Arnes de medicion: costo por tick de cambiar el ancho vivo del panel Ahora suena (340...520) dentro de un
/// `NSHostingView` real de `FullscreenCanvas` en modo lateral. Imprime ms por tick; el limite es holgado (no es un test de rendimiento fino).
@MainActor
final class PlaybackSidebarResizeBenchmarkTests: XCTestCase {
    private func isolatedPlayer() -> (PlayerViewModel, UserDefaults, String, URL) {
        let suite = "ResizeBench.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
        let player = PlayerViewModel(rustCore: nil, audioService: audio, playbackStore: PlaybackStateStore(directory: directory))
        return (player, preferences, suite, directory)
    }

    private func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }

    func testLivePanelWidthCostPerTick() {
        let (player, preferences, suite, directory) = isolatedPlayer()
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        player.currentTrack = SongItemRecord(videoId: "bench", title: "Track", artists: "Artist", album: "Album", duration: "3:00",
            thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil, isVideo: false, isUpload: false, library: nil)
        player.playbackPresentation.presentSidebar()
        let model = PlaybackPanelResizeModel()
        let host = NSHostingView(rootView: FullscreenCanvas(viewModel: player, isSidebarExpanded: .constant(false), router: nil,
            lateralWidth: 380, lateralMaximum: 520, onResizeLateral: { _, _ in }, resizeModel: model))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 1300, height: 860)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        for _ in 0..<20 { spin() } // deja asentar la presentacion lateral
        var baseline: [Double] = []
        for _ in 0..<30 { // costo del bucle sin cambiar el ancho
            let t = ContinuousClock.now; spin(); host.layoutSubtreeIfNeeded(); baseline.append(ms(ContinuousClock.now - t))
        }
        var ticks: [Double] = []
        for i in 0..<120 {
            let width = 340 + CGFloat(i % 60) * 3
            let start = ContinuousClock.now
            model.update(width)
            spin(); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            ticks.append(ms(ContinuousClock.now - start))
        }
        let base = baseline.sorted()[baseline.count / 2]
        let sorted = ticks.sorted()
        print("RESIZE-BENCH panel: base(spin)=\(base)ms median=\(sorted[sorted.count / 2])ms p95=\(sorted[Int(Double(sorted.count) * 0.95)])ms max=\(sorted.last!)ms")
        XCTAssertLessThan(sorted[sorted.count / 2], 50)
    }

    private func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}
