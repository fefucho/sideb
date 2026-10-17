import AppKit
import XCTest
@testable import SideB

@MainActor
final class NativeCollectionTraversalTests: XCTestCase {
    @MainActor private struct Fixture {
        let root: TraversalReadProbeView
        let probes: [TraversalReadProbeView]
        let scroll: NSScrollView
        var reads: Int { probes.reduce(0) { $0 + $1.subviewReads } }
        func resetReads() { probes.forEach { $0.subviewReads = 0 } }
    }

    private func fixture() -> Fixture {
        let root = TraversalReadProbeView(), branch = TraversalReadProbeView()
        let document = TraversalReadProbeView()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        root.addSubview(branch)
        branch.addSubview(scroll)
        scroll.documentView = document
        var probes = [root, branch, document]
        // Public, deterministic hierarchy representing cards and their controls.
        // No private AppKit orthogonal-scroller class or live window is required.
        for _ in 0..<20 {
            let card = TraversalReadProbeView()
            document.addSubview(card)
            probes.append(card)
            for _ in 0..<4 {
                let control = TraversalReadProbeView()
                card.addSubview(control)
                probes.append(control)
            }
        }
        return Fixture(root: root, probes: probes, scroll: scroll)
    }

    private func compositionalLayout() -> NSCollectionViewCompositionalLayout {
        NSCollectionViewCompositionalLayout { _, _ in nil }
    }

    private func restoreScrollerConfiguration(_ scroll: NSScrollView) {
        scroll.hasHorizontalScroller = true
        scroll.horizontalScroller = NSScroller(frame: NSRect(x: 0, y: 0, width: 100, height: 12))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.horizontalScrollElasticity = .none
        scroll.contentView.postsBoundsChangedNotifications = false
    }

    private func postBoundsChange(_ scroll: NSScrollView) {
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }

    func testFlowLayoutSkipsRepeatedTraversalAndLeavesNestedScrollOwnershipAlone() {
        let collection = HomeNativeCollectionView()
        collection.collectionViewLayout = NSCollectionViewFlowLayout()
        let fixture = fixture()
        collection.addSubview(fixture.root)
        restoreScrollerConfiguration(fixture.scroll)
        let originalScroller = fixture.scroll.horizontalScroller
        var viewportChanges = 0
        collection.onViewportMoved = { viewportChanges += 1 }
        fixture.resetReads()

        // Repeat the collection's subview hook to isolate its scanner from
        // AppKit's own layout traversal. The root is already a real child.
        for _ in 0..<50 { collection.didAddSubview(fixture.root) }
        print("Native traversal characterization: Flow, 50 hooks, \(fixture.probes.count) public probes, \(fixture.reads) subviews reads")
        XCTAssertEqual(fixture.reads, 0)
        XCTAssertTrue(fixture.scroll.hasHorizontalScroller)
        XCTAssertTrue(fixture.scroll.horizontalScroller === originalScroller)
        XCTAssertTrue(fixture.scroll.hasVerticalScroller)
        XCTAssertTrue(fixture.scroll.drawsBackground)
        XCTAssertEqual(fixture.scroll.horizontalScrollElasticity, .none)
        XCTAssertFalse(fixture.scroll.contentView.postsBoundsChangedNotifications)
        postBoundsChange(fixture.scroll)
        XCTAssertEqual(viewportChanges, 0)

        restoreScrollerConfiguration(fixture.scroll)
        let layoutScroller = fixture.scroll.horizontalScroller
        viewportChanges = 0
        fixture.resetReads()
        for _ in 0..<50 { collection.layout() }
        print("Native traversal characterization: Flow, 50 layout passes, \(fixture.probes.count) public probes, \(fixture.reads) subviews reads")
        XCTAssertEqual(fixture.reads, 0)
        XCTAssertTrue(fixture.scroll.hasHorizontalScroller)
        XCTAssertTrue(fixture.scroll.horizontalScroller === layoutScroller)
        XCTAssertTrue(fixture.scroll.hasVerticalScroller)
        XCTAssertTrue(fixture.scroll.drawsBackground)
        XCTAssertEqual(fixture.scroll.horizontalScrollElasticity, .none)
        XCTAssertFalse(fixture.scroll.contentView.postsBoundsChangedNotifications)
        viewportChanges = 0
        postBoundsChange(fixture.scroll)
        XCTAssertEqual(viewportChanges, 0)
        XCTAssertNil(collection.window)
    }

    func testCompositionalStillConfiguresRetiledScrollersAndObservesEachClipOnlyOnce() {
        let collection = HomeNativeCollectionView()
        collection.collectionViewLayout = compositionalLayout()
        let fixture = fixture()
        collection.addSubview(fixture.root)
        var viewportChanges = 0
        collection.onViewportMoved = { viewportChanges += 1 }
        for _ in 0..<3 {
            // AppKit may reset these values while retiling orthogonal shelves.
            restoreScrollerConfiguration(fixture.scroll)
            collection.didAddSubview(fixture.root)
            XCTAssertFalse(fixture.scroll.hasHorizontalScroller)
            XCTAssertNil(fixture.scroll.horizontalScroller)
            XCTAssertFalse(fixture.scroll.hasVerticalScroller)
            XCTAssertFalse(fixture.scroll.drawsBackground)
            XCTAssertEqual(fixture.scroll.horizontalScrollElasticity, .allowed)
            XCTAssertTrue(fixture.scroll.contentView.postsBoundsChangedNotifications)
            viewportChanges = 0
            postBoundsChange(fixture.scroll)
            XCTAssertEqual(viewportChanges, 1)
        }
        fixture.root.removeFromSuperview()
        viewportChanges = 0
        postBoundsChange(fixture.scroll)
        XCTAssertEqual(viewportChanges, 0)
    }

    func testNilToCompositionalToFlowRetiresObserversWithoutTraversingFlowChildren() {
        let collection = HomeNativeCollectionView()
        collection.collectionViewLayout = nil
        let fixture = fixture()
        collection.addSubview(fixture.root)
        restoreScrollerConfiguration(fixture.scroll)
        var viewportChanges = 0
        collection.onViewportMoved = { viewportChanges += 1 }
        fixture.resetReads()
        collection.didAddSubview(fixture.root)
        XCTAssertEqual(fixture.reads, 0)
        postBoundsChange(fixture.scroll)
        XCTAssertEqual(viewportChanges, 0)

        collection.needsLayout = false
        collection.collectionViewLayout = compositionalLayout()
        XCTAssertTrue(collection.needsLayout, "The new layout must rearm observers after the setter retires old ones")
        // A layout can adopt an existing subtree rather than adding a new one.
        collection.layoutSubtreeIfNeeded()
        XCTAssertFalse(fixture.scroll.hasHorizontalScroller)
        viewportChanges = 0
        postBoundsChange(fixture.scroll)
        XCTAssertEqual(viewportChanges, 1)

        collection.collectionViewLayout = NSCollectionViewFlowLayout()
        viewportChanges = 0
        postBoundsChange(fixture.scroll)
        XCTAssertEqual(viewportChanges, 0)
        restoreScrollerConfiguration(fixture.scroll)
        fixture.resetReads()
        for _ in 0..<50 { collection.didAddSubview(fixture.root) }
        XCTAssertEqual(fixture.reads, 0)
        XCTAssertTrue(fixture.scroll.hasHorizontalScroller)
        fixture.resetReads()
        collection.willRemoveSubview(fixture.root)
        print("Native traversal characterization: Flow removal hook, \(fixture.probes.count) public probes, \(fixture.reads) subviews reads")
        XCTAssertEqual(fixture.reads, 0)
        fixture.resetReads()
        fixture.root.removeFromSuperview()
        // Real removal also includes AppKit's own hierarchy teardown. Report
        // that separately instead of attributing its reads to our cleanup hook.
        print("Native traversal characterization: Flow real removal including AppKit, \(fixture.reads) subviews reads")
        XCTAssertNil(fixture.root.superview)
        viewportChanges = 0
        postBoundsChange(fixture.scroll)
        XCTAssertEqual(viewportChanges, 0)
    }

    func testTransitionLayoutKeepsConservativeScrollerHandlingThenReleasesItOnFlow() {
        let collection = HomeNativeCollectionView()
        let transition = NSCollectionViewTransitionLayout(currentLayout: NSCollectionViewFlowLayout(),
                                                          nextLayout: compositionalLayout())
        collection.collectionViewLayout = transition
        let fixture = fixture()
        collection.addSubview(fixture.root)
        restoreScrollerConfiguration(fixture.scroll)
        collection.didAddSubview(fixture.root)
        XCTAssertFalse(fixture.scroll.hasHorizontalScroller)
        XCTAssertTrue(fixture.scroll.contentView.postsBoundsChangedNotifications)
        var viewportChanges = 0
        collection.onViewportMoved = { viewportChanges += 1 }
        postBoundsChange(fixture.scroll)
        XCTAssertEqual(viewportChanges, 1)
        collection.collectionViewLayout = NSCollectionViewFlowLayout()
        viewportChanges = 0
        postBoundsChange(fixture.scroll)
        XCTAssertEqual(viewportChanges, 0)
    }
}

@MainActor private final class TraversalReadProbeView: NSView {
    var subviewReads = 0
    override var subviews: [NSView] {
        get { subviewReads += 1; return super.subviews }
        set { super.subviews = newValue }
    }
}
