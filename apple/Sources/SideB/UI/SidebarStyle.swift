import Foundation

/// One sidebar, with two presentations of the same collection.
/// Values saved by the earlier three-style experiment remain readable.
enum SidebarStyle: String, CaseIterable, Identifiable {
    case collection, covers

    static let preferenceKey = "sideb.sidebar.style.v1"
    static func resolve(_ rawValue: String) -> SidebarStyle { Self(rawValue: rawValue) ?? .collection }
    var id: String { rawValue }
    var alternate: SidebarStyle { self == .collection ? .covers : .collection }
    var title: String {
        switch self {
        case .collection: L10n.text("sidebar.layout.list")
        case .covers: L10n.text("sidebar.layout.grid")
        }
    }
    var switchLabel: String {
        switch self {
        case .collection: L10n.text("sidebar.layout.show_grid")
        case .covers: L10n.text("sidebar.layout.show_list")
        }
    }
}
