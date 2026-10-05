import AppKit
import SideBCore

/// Queue uses its own legacy controls while other lists retain common media interactions.
enum TrackTablePresentation: Equatable {
    case standard
    case queue
    case collectionAlbum
    case collectionPlaylist
}

/// Shared lifecycle for the recycled table cells; presentation and actions remain separate.
@MainActor
protocol NativeTrackCellPresenting: AnyObject {
    func configure(track: SongItemRecord, index: Int, isCurrentTrack: Bool, isPlaying: Bool,
                   isLiked: Bool, hideAlbum: Bool, showAlbumInSubtitle: Bool,
                   isReorderable: Bool, rowHeight: CGFloat)
    func updateHover(isHovered: Bool)
    func updateSelection(isSelected: Bool)
    func updateCreditFocus(_ isFocused: Bool)
    var containsKeyboardFocus: Bool { get }
}
