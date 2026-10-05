import AppKit
import SideBCore

enum CollectionTrackMetrics {
    static let rowHeight: CGFloat = 58
    static let artworkSize: CGFloat = 44
    static let playButtonSize: CGFloat = 32
    static let actionButtonSize: CGFloat = 28
}

/// A single geometry contract for detail rows and playlist column labels.
struct CollectionTrackColumnLayout: Equatable {
    let index: CGRect
    let artwork: CGRect
    let song: CGRect
    let artist: CGRect
    let album: CGRect
    let duration: CGRect
    let like: CGRect
    let menu: CGRect

    static func make(width: CGFloat, height: CGFloat, showsAlbum: Bool) -> Self {
        let inset: CGFloat = 24
        let actionSize = CollectionTrackMetrics.actionButtonSize
        let menu = CGRect(x: width - inset - actionSize, y: (height - actionSize) / 2,
                          width: actionSize, height: actionSize)
        let like = CGRect(x: menu.minX - 8 - actionSize, y: menu.minY, width: actionSize, height: actionSize)
        let duration = CGRect(x: like.minX - 16 - 72, y: (height - 20) / 2, width: 72, height: 20)
        let index = CGRect(x: inset, y: (height - 20) / 2, width: 20, height: 20)
        let artworkSize = CollectionTrackMetrics.artworkSize
        let artwork = CGRect(x: index.maxX + 12, y: (height - artworkSize) / 2,
                             width: artworkSize, height: artworkSize)
        let start = artwork.maxX + 14
        let space = max(0, duration.minX - 14 - start)
        let gap: CGFloat = showsAlbum ? 12 : 14
        let available = max(0, space - gap * (showsAlbum ? 2 : 1))
        let songWidth = available * (showsAlbum ? 0.47 : 0.64)
        let artistWidth = available * (showsAlbum ? 0.26 : 0.36)
        let song = CGRect(x: start, y: (height - 26) / 2, width: songWidth, height: 26)
        let artist = CGRect(x: song.maxX + gap, y: (height - 24) / 2, width: artistWidth, height: 24)
        let album = CGRect(x: artist.maxX + gap, y: artist.minY,
                           width: showsAlbum ? available - songWidth - artistWidth : 0, height: 24)
        return Self(index: index, artwork: artwork, song: song, artist: artist, album: album,
                    duration: duration, like: like, menu: menu)
    }
}

final class NativeCollectionColumnsCellView: NSTableCellView {
    private let labels = ["Canción", "Artista", "Álbum", "Duración"].map { NSTextField(labelWithString: $0) }
    override init(frame: NSRect) {
        super.init(frame: frame)
        for label in labels {
            label.font = .systemFont(ofSize: 13.5, weight: .semibold)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        setAccessibilityLabel("Canción, artista, álbum y duración")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let geometry = CollectionTrackColumnLayout.make(width: bounds.width, height: bounds.height, showsAlbum: true)
        let songStart = geometry.artwork.minX
        labels[0].frame = CGRect(x: songStart, y: geometry.artist.minY, width: geometry.song.maxX - songStart, height: 24)
        labels[1].frame = geometry.artist
        labels[2].frame = geometry.album
        labels[3].frame = geometry.duration
        labels[3].alignment = .right
    }
}

/// Shared album/playlist row; capabilities decide whether the album column is present.
final class NativeCollectionTrackCellView: NSTableCellView, NativeTrackCellPresenting {
    private let showsAlbum: Bool
    private let indexLabel = NSTextField(labelWithString: "")
    private let playingIcon = NSImageView()
    let artwork = NativeTrackActionImageView(frame: .zero)
    let title = NativeTrackActionField(frame: .zero)
    let artist = NativeTrackCreditField(frame: .zero)
    let album = NativeTrackCreditField(frame: .zero)
    private let duration = NSTextField(labelWithString: "")
    private let playButton = HomeFocusTrackingButton()
    private let likeButton = HomeFocusTrackingButton()
    private let menuButton = HomeFocusTrackingButton()
    private let grip = NSImageView()
    private var track: SongItemRecord?
    private var hovered = false
    private var focused = false
    private var reorderable = false
    private var requestID = UUID()
    private var imageTask: Task<Void, Never>?
    var onPlay: (() -> Void)?
    var onLike: ((SongItemRecord) -> Void)?
    var onMenu: ((NSButton) -> Void)?
    var onArtist: ((SongItemRecord) -> Void)?
    var onAlbum: ((SongItemRecord) -> Void)?
    var onSelectionMouseDown: ((NSEvent) -> Void)?
    var onCreditFocusChanged: ((Bool) -> Void)?

    init(showsAlbum: Bool) {
        self.showsAlbum = showsAlbum
        super.init(frame: .zero)
        wantsLayer = true
        for (view, identifier) in [(indexLabel, "Index"), (playingIcon, "Playing"), (artwork, "Artwork"),
                                   (title, "Song"), (artist, "Artist"), (album, "Album"),
                                   (duration, "Duration"), (playButton, "Play"), (likeButton, "Like"),
                                   (menuButton, "Menu"), (grip, "Grip")] as [(NSView, String)] {
            view.setAccessibilityIdentifier("CollectionTrack\(identifier)")
            addSubview(view)
        }
        for field in [indexLabel, title, artist, album, duration] {
            field.isEditable = false; field.isSelectable = false
            field.isBezeled = false; field.drawsBackground = false
            field.maximumNumberOfLines = 1; field.lineBreakMode = .byTruncatingTail
            field.font = .systemFont(ofSize: 13.5)
            field.textColor = .secondaryLabelColor
        }
        title.textColor = .labelColor
        title.font = .systemFont(ofSize: 15.5, weight: .medium)
        duration.alignment = .right
        indexLabel.alignment = .right
        artwork.wantsLayer = true
        artwork.layer?.cornerRadius = AppTheme.artworkThumbnailRadius
        artwork.layer?.masksToBounds = true
        artwork.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        artwork.imageScaling = .scaleProportionallyUpOrDown
        artwork.onActivate = { [weak self] in self?.onPlay?() }
        title.onActivate = { [weak self] in self?.onPlay?() }
        for view in [title, artist, album] {
            view.onSelectionMouseDown = { [weak self] in self?.onSelectionMouseDown?($0) }
        }
        artwork.onSelectionMouseDown = { [weak self] in self?.onSelectionMouseDown?($0) }
        for field in [artist, album] {
            field.showsHoverHighlight = true
            field.onFocusChanged = { [weak self] value in
                self?.updateCreditFocus(value)
                self?.onCreditFocusChanged?(value)
            }
        }
        for button in [playButton, likeButton, menuButton] {
            button.bezelStyle = .regularSquare; button.isBordered = false
            button.imagePosition = .imageOnly; button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = .white
            button.target = self
            button.onFocusChanged = { [weak self] in
                Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self else { return }
                    self.updateCreditFocus(self.containsKeyboardFocus)
                }
            }
        }
        playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Reproducir canción")?
            .withSymbolConfiguration(.init(pointSize: 15.5, weight: .semibold))
        playButton.wantsLayer = true
        playButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
        playButton.layer?.cornerRadius = 8
        playButton.action = #selector(playClicked)
        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Más opciones")?
            .withSymbolConfiguration(.init(pointSize: 15.5, weight: .semibold))
        menuButton.action = #selector(menuClicked)
        menuButton.setAccessibilityLabel("Más opciones de la canción")
        likeButton.action = #selector(likeClicked)
        grip.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Arrastrar para reordenar")?
            .withSymbolConfiguration(.init(pointSize: 15.5, weight: .regular))
        grip.contentTintColor = NSColor.white.withAlphaComponent(0.45)
        playingIcon.contentTintColor = .white
        album.isHidden = !showsAlbum
        updateControls()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let g = CollectionTrackColumnLayout.make(width: bounds.width, height: bounds.height, showsAlbum: showsAlbum)
        indexLabel.frame = g.index
        playingIcon.frame = CGRect(x: g.index.midX - 8, y: g.index.midY - 8, width: 16, height: 16)
        artwork.frame = g.artwork; title.frame = g.song; artist.frame = g.artist; album.frame = g.album
        duration.frame = g.duration; likeButton.frame = g.like; menuButton.frame = g.menu
        let playSize = CollectionTrackMetrics.playButtonSize
        playButton.frame = CGRect(x: g.artwork.midX - playSize / 2, y: g.artwork.midY - playSize / 2,
                                  width: playSize, height: playSize)
        grip.frame = CGRect(x: g.duration.midX - 8, y: g.duration.midY - 8, width: 16, height: 16)
    }
    func configure(track: SongItemRecord, index: Int, isCurrentTrack: Bool, isPlaying: Bool,
                   isLiked: Bool, hideAlbum: Bool, showAlbumInSubtitle: Bool, isReorderable: Bool, rowHeight: CGFloat) {
        self.track = track
        reorderable = isReorderable
        indexLabel.stringValue = "\(index + 1)"
        indexLabel.isHidden = isCurrentTrack; playingIcon.isHidden = !isCurrentTrack
        playingIcon.image = NSImage(systemSymbolName: isPlaying ? "speaker.wave.3.fill" : "speaker.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15.5, weight: .semibold))
        title.stringValue = track.title
        title.font = .systemFont(ofSize: 15.5, weight: isCurrentTrack ? .semibold : .medium)
        artist.configureLink(label: track.displayArtist, destinationExists: track.artistId != nil || track.artistRuns.contains { $0.id != nil }) { [weak self] in
            guard let self, let track = self.track else { return }; self.onArtist?(track)
        } fallback: { [weak self] in self?.onPlay?() }
        album.configureLink(label: track.displayAlbum ?? "", destinationExists: track.albumId != nil) { [weak self] in
            guard let self, let track = self.track else { return }; self.onAlbum?(track)
        } fallback: { [weak self] in self?.onPlay?() }
        album.isHidden = !showsAlbum
        duration.stringValue = track.duration ?? "—"
        likeButton.image = NSImage(systemSymbolName: isLiked ? "heart.fill" : "heart", accessibilityDescription: "Me gusta")?
            .withSymbolConfiguration(.init(pointSize: 15.5, weight: .regular))
        likeButton.contentTintColor = isLiked ? .white : NSColor.white.withAlphaComponent(0.65)
        likeButton.setAccessibilityLabel(isLiked ? "Quitar de Me gusta" : "Me gusta")
        updateControls(); needsLayout = true
        loadArtwork(track)
    }
    func updateHover(isHovered: Bool) { hovered = isHovered; updateControls() }
    func updateSelection(isSelected: Bool) { }
    func updateCreditFocus(_ isFocused: Bool) { focused = isFocused; updateControls() }
    var containsKeyboardFocus: Bool {
        var view = window?.firstResponder as? NSView
        while let current = view {
            if current === self { return true }
            view = current.superview
        }
        return false
    }
    private func updateControls() {
        playButton.isHidden = !(hovered || focused)
        grip.isHidden = !(reorderable && (hovered || focused))
        duration.isHidden = !grip.isHidden
    }
    @objc private func playClicked() { onPlay?() }
    @objc private func menuClicked() { onMenu?(menuButton) }
    @objc private func likeClicked() {
        guard let track, let action = onLike else { return }
        DispatchQueue.main.async { action(track) }
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel(); imageTask = nil; requestID = UUID(); track = nil
        artwork.image = nil; hovered = false; focused = false; reorderable = false
        onPlay = nil; onLike = nil; onMenu = nil; onArtist = nil; onAlbum = nil
        onSelectionMouseDown = nil; onCreditFocusChanged = nil
        updateControls()
    }
    private func loadArtwork(_ track: SongItemRecord) {
        imageTask?.cancel(); imageTask = nil; requestID = UUID()
        guard let source = track.thumbnail,
              let url = ImageURLHelper.optimizedThumbnailURL(from: source, targetPixelSize: 88) else { artwork.image = nil; return }
        let size = CGSize(width: CollectionTrackMetrics.artworkSize, height: CollectionTrackMetrics.artworkSize)
        if let cached = ImageCache.shared.imageFromMemoryCache(for: url, targetSize: size) { artwork.image = cached; return }
        artwork.image = nil
        let request = requestID
        imageTask = Task { @MainActor [weak self] in
            let image = await ImageCache.shared.image(for: url, targetSize: size)
            guard !Task.isCancelled, let self, self.requestID == request else { return }
            self.artwork.image = image; self.imageTask = nil
        }
    }
}
