import SideBCore

extension BrowseCardRecord {
    /// A missing name is a UI fallback; real content names and route IDs stay raw.
    var displayTitle: String {
        guard title.isEmpty else { return title }
        switch kind {
        case "album": return L10n.text("metadata.album")
        case "playlist", "mix": return L10n.text("metadata.playlist")
        default: return L10n.text("common.untitled")
        }
    }
}
