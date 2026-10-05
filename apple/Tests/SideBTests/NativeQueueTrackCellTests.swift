import Testing
import AppKit
import SideBCore
@testable import SideB

private func queueCellTrack(_ id: String = "song", album: String? = "Mr. Morale & The Big Steppers") -> SongItemRecord {
    SongItemRecord(videoId: id, title: "United In Grief", artists: "Kendrick Lamar", album: album,
                   duration: "4:15", thumbnail: nil, artistId: "artist", albumId: "album",
                   setVideoId: nil, isVideo: false, isUpload: false, library: nil, artistRuns: [])
}

@MainActor private func queueSubview<T: NSView>(_ cell: NativeQueueTrackCellView, _ id: String, as type: T.Type) throws -> T {
    try #require(cell.subviews.first { $0.accessibilityIdentifier() == id } as? T)
}

@MainActor private func configureQueueCell(_ cell: NativeQueueTrackCellView, track: SongItemRecord = queueCellTrack(), liked: Bool = false) {
    cell.configure(track: track, index: 0, isCurrentTrack: true, isPlaying: true, isLiked: liked,
                   hideAlbum: true, showAlbumInSubtitle: true, isReorderable: true, rowHeight: 46)
    cell.layoutSubtreeIfNeeded()
}

@Test @MainActor func nativeQueueCreditsRemainTogetherBelowTitleAcrossWidths() throws {
    let cell = NativeQueueTrackCellView(frame: NSRect(x: 0, y: 0, width: 576, height: 46))
    cell.translatesAutoresizingMaskIntoConstraints = false
    let widthConstraint = cell.widthAnchor.constraint(equalToConstant: 576)
    NSLayoutConstraint.activate([widthConstraint, cell.heightAnchor.constraint(equalToConstant: 46)])
    configureQueueCell(cell)
    let title = try queueSubview(cell, "NativeQueueTrackTitle", as: NSTextField.self)
    let credits = try queueSubview(cell, "NativeQueueTrackCredits", as: NSTextField.self)
    let album = try queueSubview(cell, "NativeQueueTrackAlbum", as: NSTextField.self)
    let dislike = try queueSubview(cell, "NativeQueueTrackDislike", as: NSButton.self)
    #expect(credits.stringValue == "Kendrick Lamar • Mr. Morale & The Big Steppers")
    #expect(album.isHidden)
    for width: CGFloat in [350, 576, 900] {
        widthConstraint.constant = width
        cell.setFrameSize(NSSize(width: width, height: 46))
        cell.layoutSubtreeIfNeeded()
        #expect(abs(title.frame.minX - credits.frame.minX) < 0.1)
        #expect(credits.frame.maxY < title.frame.minY)
        #expect(credits.frame.maxX <= dislike.frame.minX - 9)
        #expect(credits.frame.width > 100)
        for view in cell.subviews where !view.isHidden {
            #expect(view.frame.maxX <= width + 1, "width=\(width) id=\(view.accessibilityIdentifier() ?? String(describing: type(of: view))) frame=\(view.frame)")
        }
    }
    configureQueueCell(cell, track: queueCellTrack(album: nil))
    #expect(credits.stringValue == "Kendrick Lamar")
}

@Test @MainActor func nativeQueueHoverAndFocusRestoreVotesAndReorderWithoutPlayOverlay() throws {
    let cell = NativeQueueTrackCellView(frame: NSRect(x: 0, y: 0, width: 576, height: 46))
    configureQueueCell(cell)
    let like = try queueSubview(cell, "NativeQueueTrackLike", as: NSButton.self)
    let dislike = try queueSubview(cell, "NativeQueueTrackDislike", as: NSButton.self)
    let grip = try queueSubview(cell, "NativeQueueTrackReorderGrip", as: NSImageView.self)
    let duration = try queueSubview(cell, "NativeQueueTrackDuration", as: NSTextField.self)
    #expect(like.isHidden && dislike.isHidden && grip.isHidden && !duration.isHidden)
    #expect(cell.subviews.compactMap { $0 as? NSButton }.count == 2)
    cell.updateSelection(isSelected: true)
    #expect(like.isHidden && dislike.isHidden && grip.isHidden)
    cell.updateHover(isHovered: true)
    #expect(!like.isHidden && !dislike.isHidden && !grip.isHidden && duration.isHidden)
    cell.updateHover(isHovered: false)
    #expect(like.isHidden && dislike.isHidden && grip.isHidden && !duration.isHidden)
    cell.updateCreditFocus(true)
    #expect(!like.isHidden && !dislike.isHidden && !grip.isHidden && duration.isHidden)
    cell.updateCreditFocus(false)
    configureQueueCell(cell, liked: true)
    #expect(!like.isHidden && dislike.isHidden && grip.isHidden)
    #expect(like.accessibilityLabel() == "Quitar de Me gusta")
    #expect(like.contentTintColor == .white)
}

@Test @MainActor func nativeQueueVotesUseBoundTrackAndReuseClearsCallbacksAndState() async throws {
    let cell = NativeQueueTrackCellView(frame: NSRect(x: 0, y: 0, width: 576, height: 46))
    let like = try queueSubview(cell, "NativeQueueTrackLike", as: NSButton.self)
    let dislike = try queueSubview(cell, "NativeQueueTrackDislike", as: NSButton.self)
    var likes: [String] = [], dislikes: [String] = []
    cell.onLike = { likes.append($0.videoId) }
    cell.onDislike = { dislikes.append($0.videoId) }
    configureQueueCell(cell)
    cell.updateHover(isHovered: true)
    like.performClick(nil)
    dislike.performClick(nil)
    for _ in 0..<5 { await Task.yield() }
    #expect(likes == ["song"] && dislikes == ["song"])
    cell.prepareForReuse()
    #expect(cell.onLike == nil && cell.onDislike == nil)
    #expect(like.isHidden && dislike.isHidden)
    configureQueueCell(cell, track: queueCellTrack("other"))
    #expect(like.isHidden && dislike.isHidden)
    #expect(like.accessibilityLabel() == "Me gusta")
}
