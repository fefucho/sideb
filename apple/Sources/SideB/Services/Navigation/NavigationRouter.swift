import SwiftUI

// MARK: - PageDestination

enum PageDestination: Equatable, Hashable {
    case home
    case explore(ExploreRoute)
    case search(query: String?)
    case album(browseId: String)
    case artist(browseId: String)
    case catalog(browseId: String, params: String?, title: String)
    case playlist(browseId: String)
    case library
    case history

    var asMenuOrigin: MenuOrigin {
        switch self {
        case .home: return .home
        case .explore: return .recommendations
        case .search: return .search
        case .album(let browseId): return .album(browseId: browseId)
        case .artist(let browseId): return .artist(channelId: browseId)
        case .catalog(let browseId, _, _): return .artist(channelId: browseId)
        case .playlist(let browseId): return .playlist(id: browseId)
        case .library: return .library
        case .history: return .history
        }
    }
}

// MARK: - NavigationRouter

@MainActor
@Observable
final class NavigationRouter {
    var history: [PageDestination] = [.home]
    var currentIndex: Int = 0
    
    var currentPage: PageDestination {
        guard currentIndex >= 0, currentIndex < history.count else { return .home }
        return history[currentIndex]
    }
    
    var canGoBack: Bool {
        currentIndex > 0
    }
    
    var canGoForward: Bool {
        currentIndex < history.count - 1
    }
    
    func navigate(to destination: PageDestination) {
        // Evitar apilar destinos idénticos consecutivos en el historial
        guard destination != currentPage else { return }
        
        // Si estábamos en medio del historial y navegamos, truncamos el futuro
        if currentIndex < history.count - 1 {
            history.removeSubrange((currentIndex + 1)...)
        }
        history.append(destination)
        currentIndex = history.count - 1
    }
    
    func goBack() {
        guard canGoBack else { return }
        currentIndex -= 1
    }
    
    func goForward() {
        guard canGoForward else { return }
        currentIndex += 1
    }
    
    // Trigger reactivo para refrescar la página activa (e.g. Inicio)
    var refreshTrigger: Int = 0
    
    func refreshHome() {
        refreshTrigger &+= 1
    }
}
