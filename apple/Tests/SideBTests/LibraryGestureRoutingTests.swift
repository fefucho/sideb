import AppKit
import SwiftUI
import Testing
import SideBCore
@testable import SideB

private final class LibraryGestureFixtureCore: SideBCore, @unchecked Sendable {
    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) { super.init(unsafeFromRawPointer: pointer) }
    init() { super.init(noPointer: .init()) }
    override func isLoggedIn() -> Bool { true }
    override func getLibraryPlaylists() async throws -> [BrowseCardRecord] { Self.cards("playlist") }
    override func getLibraryAlbums() async throws -> [BrowseCardRecord] { Self.cards("album") }
    override func getLibraryArtists() async throws -> [BrowseCardRecord] { [] }
    static func cards(_ kind: String) -> [BrowseCardRecord] {
        (0..<6).map { BrowseCardRecord(kind: kind, id: "\(kind)\($0)", title: "Collection \($0)", subtitle: nil, thumbnail: nil, duration: nil) }
    }
}

@Test @MainActor func libraryHorizontalSectionsOwnScrollWithoutCapturingHistoryUnderFullscreen() async throws {
    let suite = "LibraryGestureRouting.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let core = LibraryGestureFixtureCore()
    let library = LibraryViewModel(preferences: defaults)
    library.configureAccount(identity: "fixture")
    await library.ensureSelectedPageTab(core: core)
    let account = AccountViewModel(); account.isLoggedIn = true
    let player = PlayerViewModel(), router = NavigationRouter()
    let view = LibraryView(rustCore: core, playerViewModel: player, libraryViewModel: library, accountViewModel: account, router: router)
    let host = NSHostingView(rootView: view)
    host.sizingOptions = []
    host.frame = NSRect(x:0,y:0,width:730,height:780)
    // SwiftUI's nested scroll documents finish their geometry in a mounted,
    // displayed window. A detached host leaves zero-sized document ancestors.
    let window = NSWindow(contentRect:host.frame,styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func horizontalMarkers() -> [WindowGestureRegionView] {
        descendants(host).compactMap { $0 as? WindowGestureRegionView }.filter {
            if case .horizontalContent = $0.region { return true }; return false
        }
    }
    for _ in 0..<6 { await Task.yield(); host.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
    let markers = horizontalMarkers()
    #expect(markers.count >= 3) // Categories, playlists and albums have independent scroll ownership.
    #expect(markers.allSatisfy { $0.bounds.width > 0 && $0.bounds.height > 0 })
    for marker in markers where marker.bounds.width > 0 && marker.bounds.height > 0 {
        let point = marker.convert(NSPoint(x:marker.bounds.midX,y:marker.bounds.midY),to:host)
        if host.bounds.contains(point) {
            #expect(WindowGestureRegions.horizontalContentOwnsHistoryGesture(at:point,in:host))
        }
    }
    #expect(!WindowGestureRegions.horizontalContentOwnsHistoryGesture(at:NSPoint(x:5,y:5),in:host))
    player.isFullscreenPresented = true
    host.rootView = view
    for _ in 0..<6 { await Task.yield(); host.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
    #expect(!horizontalMarkers().isEmpty)
    #expect(horizontalMarkers().allSatisfy { !$0.isRegionActive })
}
