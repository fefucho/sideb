import Testing
@testable import SideB

@Suite("ContentEdgeFrame Tests")
struct ContentEdgeFrameTests {
    @Test func fadeFractionIsClampedAndZeroWithoutRoom() {
        #expect(ContentEdgeFrameMetrics.fadeFraction(width: 0, fade: 28) == 0)
        #expect(ContentEdgeFrameMetrics.fadeFraction(width: 800, fade: 0) == 0)
        #expect(abs(ContentEdgeFrameMetrics.fadeFraction(width: 700, fade: 28) - 0.04) < 0.0001)
        #expect(ContentEdgeFrameMetrics.fadeFraction(width: 40, fade: 28) == 0.5)
    }

    @Test func contentFrameMatchesThePanelRadiusAndInset() {
        #expect(ShellLayout.contentCornerRadius == ShellLayout.sidebarCornerRadius)
        #expect(ShellLayout.contentFrameInset == ShellLayout.sidebarInset)
    }

    @Test func contentBorderStyleResolvesWithSubtleDefaultAndNeverDimsInHighContrast() {
        #expect(ContentBorderStyle.resolve(nil) == .subtle)
        #expect(ContentBorderStyle.resolve("garbage") == .subtle)
        #expect(ContentBorderStyle.resolve("none") == .none)
        #expect(ContentBorderStyle.none.strokeOpacity(highContrast: true) == 0)
        for style in [ContentBorderStyle.subtle, .strong] {
            #expect(style.strokeOpacity(highContrast: true) > style.strokeOpacity(highContrast: false))
        }
        #expect(ContentBorderStyle.strong.strokeOpacity(highContrast: false) > ContentBorderStyle.subtle.strokeOpacity(highContrast: false))
    }
}
