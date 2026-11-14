import Testing
import CoreGraphics
@testable import SideB

@Suite("ToolbarSidebarInset Tests")
struct ToolbarSidebarInsetTests {
    @Test func horizontalsShiftWithLeftInsetAndKeepRightInset() {
        for inset: CGFloat in [0, 252, 360] {
            for right: CGFloat in [0, 392] {
                let h = ShellLayout.toolbarHorizontals(minX: 0, midX: 600, maxX: 1200, sidebarLeadingInset: inset, playbackTrailingInset: right)
                #expect(h.leading == inset + 18)
                #expect(h.trailing == 1200 - 18 - right)
                #expect(h.centerX == 600 + inset / 2 - right / 2)
            }
        }
    }

    @Test func expandedSearchStartsAfterSidebarEdgeAndNeverOverIt() {
        for inset: CGFloat in [252, 360] {
            let h = ShellLayout.toolbarHorizontals(minX: 0, midX: 600, maxX: 1200, sidebarLeadingInset: inset, playbackTrailingInset: 0)
            let frames = NavigationClusterFrames.make(bounds: CGRect(x: 0, y: 0, width: 1200, height: 100),
                center: CGPoint(x: h.centerX, y: 40), leading: h.leading, trailing: h.trailing,
                sidebarProgress: 1, searchProgress: 0, reduceMotion: true, windowTop: 0)
            #expect(frames.search.minX == inset + 18)
            #expect(frames.history.maxX == h.trailing)
        }
        // Colapsada: vuelve a su sitio actual.
        let closed = ShellLayout.toolbarHorizontals(minX: 0, midX: 600, maxX: 1200, sidebarLeadingInset: 0, playbackTrailingInset: 0)
        #expect(closed.leading == 18)
    }

    @MainActor @Test func insetModelIgnoresTransitionWidthsAndCollapses() {
        let model = NavigationSidebarInsetModel()
        model.report(columnWidth: 80) // animacion de apertura: se ignora
        #expect(model.inset == 0)
        model.report(columnWidth: 252.4)
        #expect(model.inset == 252)
        model.isExpanded = false
        #expect(model.inset == 0)
        model.isExpanded = true
        model.report(columnWidth: 360)
        #expect(model.inset == 360)
    }
}
