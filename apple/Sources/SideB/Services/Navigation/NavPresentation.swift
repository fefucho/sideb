import SwiftUI

/// The selected main destination follows only the history already visited.
enum MainNavigationDestination: Equatable {
    case home, explore, library, search

    static func selected(history: [PageDestination], currentIndex: Int, searchPresented: Bool) -> Self {
        if searchPresented { return .search }
        guard currentIndex >= 0 else { return .home }
        for page in history.prefix(currentIndex + 1).reversed() {
            switch page {
            case .home: return .home
            case .explore: return .explore
            case .library, .history: return .library
            case .search: return .search
            default: continue
            }
        }
        return .home
    }
}

enum NavPresentation {
    static func showsTopNavigation(sidebarExpanded: Bool, fullscreenPresented: Bool) -> Bool {
        !sidebarExpanded && !fullscreenPresented
    }

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.42, extraBounce: 0)
    }
}
