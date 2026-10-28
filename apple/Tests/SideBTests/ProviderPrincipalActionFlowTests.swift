import SwiftUI
import AppKit
import Testing
@testable import SideB

struct ProviderPrincipalActionFlowTests {
    @Test @MainActor func hostedLayoutActuallyCentersControlsAfterWrapping() async throws {
        let sizes = [CGSize(width: 48, height: 40), CGSize(width: 32, height: 32),
                     CGSize(width: 40, height: 40), CGSize(width: 32, height: 32)]
        let views = sizes.map { _ in NSView() }
        let host = NSHostingView(rootView: ProviderPrincipalActionFlow {
            ForEach(sizes.indices, id: \.self) { index in
                ActionFrameProbe(view: views[index]).frame(width: sizes[index].width, height: sizes[index].height)
            }
        }.frame(width: 90))
        let window = NSWindow(contentRect: NSRect(x: -2200, y: -1500, width: 90, height: 100),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let frames = views.map { $0.convert($0.bounds, to: host) }
        #expect(abs(frames[0].midY - frames[1].midY) < 0.5)
        #expect(abs(frames[2].midY - frames[3].midY) < 0.5)
        #expect(abs(frames[0].midY - frames[2].midY) >= 48)
        #expect(views.map { $0.bounds.size } == sizes)
    }

    @Test func centersNativeFortyAndThirtyTwoPointControlsOnOneRow() {
        let nativeSizes = [CGSize(width: 72, height: 40), CGSize(width: 32, height: 32)]
        let result = ProviderPrincipalActionFlowGeometry.layout(sizes: nativeSizes, width: 120,
            spacing: 8, rowSpacing: 8)

        #expect(result.sizes == nativeSizes)
        #expect(result.points[0].y == 0)
        #expect(result.points[1].y == 4)
        #expect(result.points[0].y + result.sizes[0].height / 2 ==
                result.points[1].y + result.sizes[1].height / 2)
        #expect(result.height == 40)
    }

    @Test func wrapsControlsAndCentersEachRowsNativeHeights() {
        let nativeSizes = [
            CGSize(width: 48, height: 40), CGSize(width: 32, height: 32),
            CGSize(width: 40, height: 40), CGSize(width: 32, height: 32)
        ]
        let result = ProviderPrincipalActionFlowGeometry.layout(sizes: nativeSizes, width: 90,
            spacing: 8, rowSpacing: 8)

        #expect(result.sizes == nativeSizes)
        #expect(result.points.map(\.y) == [0, 4, 48, 52])
        for row in [[0, 1], [2, 3]] {
            let centers = row.map { result.points[$0].y + result.sizes[$0].height / 2 }
            #expect(centers[0] == centers[1])
        }
        #expect(result.height == 88)
    }
}

private struct ActionFrameProbe: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ view: NSView, context: Context) {}
}
