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
    func find(in view: NSView) -> T? {
        if view.accessibilityIdentifier() == id, let match = view as? T { return match }
        return view.subviews.lazy.compactMap { find(in: $0) }.first
    }
    return try #require(find(in: cell))
}

@MainActor private func configureQueueCell(_ cell: NativeQueueTrackCellView, track: SongItemRecord = queueCellTrack(), liked: Bool = false, current: Bool = false, playing: Bool = true) {
    cell.configure(track: track, index: 0, isCurrentTrack: current, isPlaying: playing, isLiked: liked,
                   hideAlbum: true, showAlbumInSubtitle: true, isReorderable: true, rowHeight: 46)
    cell.layoutSubtreeIfNeeded()
}

@Suite(.serialized)
@MainActor
struct NativeQueueTrackCellTests {
@Test @MainActor func nativeQueueCreditsRemainTogetherBelowTitleAcrossWidths() throws {
    let cell = NativeQueueTrackCellView(frame: NSRect(x: 0, y: 0, width: 576, height: 46))
    cell.translatesAutoresizingMaskIntoConstraints = false
    let widthConstraint = cell.widthAnchor.constraint(equalToConstant: 576)
    NSLayoutConstraint.activate([widthConstraint, cell.heightAnchor.constraint(equalToConstant: 46)])
    configureQueueCell(cell, current: true)
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
        let titleRect = cell.convert(title.bounds, from: title)
        let creditsRect = cell.convert(credits.bounds, from: credits)
        #expect(abs(titleRect.minX - creditsRect.minX) < 0.1)
        #expect(creditsRect.maxY < titleRect.minY)
        #expect(creditsRect.maxX <= dislike.frame.minX - 9)
        #expect(creditsRect.width > 100)
        for view in cell.subviews where !view.isHidden {
            #expect(view.frame.maxX <= width + 1, "width=\(width) id=\(view.accessibilityIdentifier() ?? String(describing: type(of: view))) frame=\(view.frame)")
        }
        if let directory = ProcessInfo.processInfo.environment["SIDEB_PRESENTATION_QA"] {
            func invalidate(_ view: NSView) {
                view.needsDisplay = true
                view.subviews.forEach(invalidate)
            }
            for hovered in [false, true] {
                cell.updateHover(isHovered: hovered)
                invalidate(cell)
                let bitmap = try #require(cell.bitmapImageRepForCachingDisplay(in: cell.bounds))
                cell.cacheDisplay(in: cell.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: directory)
                    .appendingPathComponent("queue-\(Int(width))-\(hovered ? "hover" : "normal").png"))
            }
            cell.updateHover(isHovered: false)
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
    #expect(!like.isHidden && dislike.isHidden && grip.isHidden && !duration.isHidden)
    #expect(cell.subviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden }.count == 1)
    cell.updateSelection(isSelected: true)
    #expect(!like.isHidden && dislike.isHidden && grip.isHidden)
    cell.updateHover(isHovered: true)
    #expect(!like.isHidden && !dislike.isHidden && !grip.isHidden && duration.isHidden)
    cell.updateHover(isHovered: false)
    #expect(!like.isHidden && dislike.isHidden && grip.isHidden && !duration.isHidden)
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
    #expect(!like.isHidden && dislike.isHidden)
    #expect(like.accessibilityLabel() == "Me gusta")
}

@Test @MainActor func nativeQueueCurrentTrackKeepsLikeVisibleAcrossPauseAndReuse() throws {
    let cell = NativeQueueTrackCellView(frame: NSRect(x: 0, y: 0, width: 576, height: 46))
    let like = try queueSubview(cell, "NativeQueueTrackLike", as: NSButton.self)
    let duration = try queueSubview(cell, "NativeQueueTrackDuration", as: NSTextField.self)
    for playing in [true, false] {
        configureQueueCell(cell, current: true, playing: playing)
        #expect(!like.isHidden && like.alphaValue == 1)
        #expect(!duration.isHidden && duration.stringValue == "4:15")
        cell.updateHover(isHovered: true)
        cell.updateHover(isHovered: false)
        cell.updateCreditFocus(true)
        cell.updateCreditFocus(false)
        #expect(!like.isHidden && !duration.isHidden)
        #expect(like.accessibilityLabel() == "Me gusta")
    }
    cell.prepareForReuse()
    configureQueueCell(cell, track: queueCellTrack("next"))
    #expect(!like.isHidden && like.alphaValue == 1)
    configureQueueCell(cell, liked: true, current: true)
    #expect(!like.isHidden && like.accessibilityLabel() == "Quitar de Me gusta")
}


@Test @MainActor func nativeQueueProposalsShareGeometryAndSwapDurationForPlusOnlyOnHover() async throws {
    let pending = NativeQueueTrackCellView(frame: NSRect(x: 0, y: 0, width: 576, height: 46))
    let proposal = NativeQueueTrackCellView(frame: pending.frame)
    configureQueueCell(pending)
    proposal.configure(track: queueCellTrack("recommendation"), index: 0, isCurrentTrack: false, isPlaying: false,
        isLiked: false, hideAlbum: true, showAlbumInSubtitle: true, isReorderable: false, rowHeight: 46)
    var additions = 0
    proposal.setAddToQueueAction { additions += 1 }
    let plus = try queueSubview(proposal, "NativeQueueTrackAddToQueue", as: NSButton.self)
    let duration = try queueSubview(proposal, "NativeQueueTrackDuration", as: NSTextField.self)
    let grip = try queueSubview(pending, "NativeQueueTrackReorderGrip", as: NSImageView.self)
    let proposalGrip = try queueSubview(proposal, "NativeQueueTrackReorderGrip", as: NSImageView.self)
    #expect(plus.isHidden && !duration.isHidden)
    for width: CGFloat in [350, 576, 900] {
        for cell in [pending, proposal] {
            cell.setFrameSize(NSSize(width: width, height: 46))
            cell.layoutSubtreeIfNeeded()
        }
        for id in ["NativeQueueTrackArtwork", "NativeQueueTrackTitle", "NativeQueueTrackCredits", "NativeQueueTrackLike", "NativeQueueTrackDislike", "NativeQueueTrackDuration"] {
            let a = try queueSubview(pending, id, as: NSView.self)
            let b = try queueSubview(proposal, id, as: NSView.self)
            let ar = pending.convert(a.bounds, from: a), br = proposal.convert(b.bounds, from: b)
            #expect(abs(ar.minX - br.minX) < 0.1, "Alignment: \(id)")
            #expect(abs(ar.midY - br.midY) < 0.1)
            #expect(abs(ar.width - br.width) < 0.1)
        }
        proposal.updateHover(isHovered: true)
        pending.updateHover(isHovered: true)
        #expect(!plus.isHidden && duration.isHidden && proposalGrip.isHidden && !grip.isHidden)
        #expect(abs(plus.frame.midX - grip.frame.midX) < 0.1)
        // AppKit uses optical alignment insets for buttons and image views.
        let plusAlignment = plus.alignmentRect(forFrame: plus.frame)
        let gripAlignment = grip.alignmentRect(forFrame: grip.frame)
        #expect(abs(plusAlignment.midY - gripAlignment.midY) < 0.1)
        proposal.updateHover(isHovered: false)
        #expect(plus.isHidden && !duration.isHidden)
    }
    proposal.updateCreditFocus(true)
    #expect(!plus.isHidden && duration.isHidden)
    plus.performClick(nil)
    for _ in 0..<5 { await Task.yield() }
    #expect(additions == 1)
    proposal.prepareForReuse()
    proposal.updateHover(isHovered: true)
    #expect(plus.isHidden)
    configureQueueCell(proposal)
    proposal.updateHover(isHovered: true)
    #expect(plus.isHidden && !proposalGrip.isHidden)
}
}
