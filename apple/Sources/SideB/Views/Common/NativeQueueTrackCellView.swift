import AppKit
import SideBCore

final class NativeQueueTrackCellView: NSTableCellView, NativeTrackCellPresenting {
    private let indexLabel = NSTextField(labelWithString: "")
    private let playingIconView = NSImageView()
    private let artworkImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let albumLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let reorderHandleImageView = NSImageView()

    private let likeButton = HomeFocusTrackingButton()
    private let dislikeButton = HomeFocusTrackingButton()

    private var currentVideoId: String?
    private var imageFetchTask: Task<Void, Never>?
    private var imageRequestID: UUID?
    private var boundTrack: SongItemRecord?
    private var includesAlbumInSubtitle = false
    private var isReorderable: Bool = false
    private var isLiked: Bool = false
    private var isCurrentTrack = false
    private var isPointerHovered = false
    private var isCreditFocused = false

    var onLike: ((SongItemRecord) -> Void)?
    var onDislike: ((SongItemRecord) -> Void)?

    private var artworkWidthConstraint: NSLayoutConstraint?
    private var artworkHeightConstraint: NSLayoutConstraint?
    private var likeButtonWidthConstraint: NSLayoutConstraint?
    private var likeButtonHeightConstraint: NSLayoutConstraint?
    private var dislikeButtonWidthConstraint: NSLayoutConstraint?
    private var dislikeButtonHeightConstraint: NSLayoutConstraint?
    private var reorderHandleWidthConstraint: NSLayoutConstraint?
    private var reorderHandleHeightConstraint: NSLayoutConstraint?
    private var playingIconWidthConstraint: NSLayoutConstraint?
    private var playingIconHeightConstraint: NSLayoutConstraint?
    private var titleTrailingWithAlbum: NSLayoutConstraint?
    private var titleTrailingNoAlbum: NSLayoutConstraint?
    private var subtitleTrailingWithAlbum: NSLayoutConstraint?
    private var subtitleTrailingNoAlbum: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageFetchTask?.cancel()
        imageFetchTask = nil
        imageRequestID = nil
        currentVideoId = nil
        boundTrack = nil
        artworkImageView.image = nil
        isLiked = false
        isCurrentTrack = false
        isReorderable = false
        isPointerHovered = false
        isCreditFocused = false
        onLike = nil
        onDislike = nil
        likeButton.isHidden = true
        dislikeButton.isHidden = true
        likeButton.alphaValue = 0
        dislikeButton.alphaValue = 0
        reorderHandleImageView.isHidden = true
        durationLabel.isHidden = false
    }

    private func setupViews() {
        wantsLayer = true

        // 1. Índice / Icono
        indexLabel.font = .systemFont(ofSize: 12, weight: .regular)
        indexLabel.textColor = .secondaryLabelColor
        indexLabel.alignment = .right
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        indexLabel.setAccessibilityIdentifier("NativeQueueTrackIndex")
        addSubview(indexLabel)

        playingIconView.imageScaling = .scaleProportionallyDown
        playingIconView.contentTintColor = .white
        playingIconView.translatesAutoresizingMaskIntoConstraints = false
        playingIconView.isHidden = true
        addSubview(playingIconView)

        let playW = playingIconView.widthAnchor.constraint(equalToConstant: 14)
        let playH = playingIconView.heightAnchor.constraint(equalToConstant: 14)
        self.playingIconWidthConstraint = playW
        self.playingIconHeightConstraint = playH

        // 2. Artwork (Dinámico: 36x36, 40x40 o 48x48)
        artworkImageView.wantsLayer = true
        artworkImageView.layer?.cornerRadius = AppTheme.artworkThumbnailRadius
        artworkImageView.layer?.masksToBounds = true
        artworkImageView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        artworkImageView.imageScaling = .scaleProportionallyUpOrDown
        artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        artworkImageView.setAccessibilityIdentifier("NativeQueueTrackArtwork")
        artworkImageView.setAccessibilityLabel(L10n.text("detail.track.artwork"))
        addSubview(artworkImageView)

        // 3. Título y Subtítulo
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setAccessibilityIdentifier("NativeQueueTrackTitle")
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.setAccessibilityIdentifier("NativeQueueTrackCredits")
        addSubview(subtitleLabel)

        // 4. Álbum (Columna separada opcional para vistas de Playlist/Álbum)
        albumLabel.font = .systemFont(ofSize: 12, weight: .regular)
        albumLabel.textColor = .secondaryLabelColor
        albumLabel.lineBreakMode = .byTruncatingTail
        albumLabel.maximumNumberOfLines = 1
        albumLabel.translatesAutoresizingMaskIntoConstraints = false
        albumLabel.setAccessibilityIdentifier("NativeQueueTrackAlbum")
        addSubview(albumLabel)

        // 5. Botones Interactivos Like & Dislike
        dislikeButton.bezelStyle = .regularSquare
        dislikeButton.isBordered = false
        dislikeButton.imagePosition = .imageOnly
        dislikeButton.imageScaling = .scaleProportionallyDown
        dislikeButton.image = NSImage(systemSymbolName: "hand.thumbsdown", accessibilityDescription: L10n.text("queue.track.dislikeRemove"))
        dislikeButton.contentTintColor = NSColor.white.withAlphaComponent(0.65)
        dislikeButton.alphaValue = 0.0
        dislikeButton.target = self
        dislikeButton.action = #selector(onDislikeClicked)
        dislikeButton.toolTip = L10n.text("queue.track.dislikeRemove")
        dislikeButton.setAccessibilityIdentifier("NativeQueueTrackDislike")
        dislikeButton.setAccessibilityLabel(L10n.text("queue.track.dislikeRemoveAX"))
        dislikeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dislikeButton)

        let dislikeW = dislikeButton.widthAnchor.constraint(equalToConstant: 22)
        let dislikeH = dislikeButton.heightAnchor.constraint(equalToConstant: 22)
        self.dislikeButtonWidthConstraint = dislikeW
        self.dislikeButtonHeightConstraint = dislikeH

        likeButton.bezelStyle = .regularSquare
        likeButton.isBordered = false
        likeButton.imagePosition = .imageOnly
        likeButton.imageScaling = .scaleProportionallyDown
        likeButton.image = NSImage(systemSymbolName: "heart", accessibilityDescription: L10n.text("detail.track.like"))
        likeButton.contentTintColor = NSColor.white.withAlphaComponent(0.65)
        likeButton.alphaValue = 0.0
        likeButton.target = self
        likeButton.action = #selector(onLikeClicked)
        likeButton.toolTip = L10n.text("detail.track.like")
        likeButton.setAccessibilityIdentifier("NativeQueueTrackLike")
        likeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(likeButton)
        for button in [likeButton, dislikeButton] {
            button.onFocusChanged = { [weak self] in
                Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self else { return }
                    self.updateCreditFocus(self.containsKeyboardFocus)
                }
            }
        }

        let likeW = likeButton.widthAnchor.constraint(equalToConstant: 22)
        let likeH = likeButton.heightAnchor.constraint(equalToConstant: 22)
        self.likeButtonWidthConstraint = likeW
        self.likeButtonHeightConstraint = likeH

        // 6. Duración y Grip Handle de Reordenamiento
        durationLabel.font = .systemFont(ofSize: 12, weight: .regular)
        durationLabel.textColor = .tertiaryLabelColor
        durationLabel.alignment = .center
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.setAccessibilityIdentifier("NativeQueueTrackDuration")
        addSubview(durationLabel)

        reorderHandleImageView.imageScaling = .scaleProportionallyDown
        reorderHandleImageView.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: L10n.text("detail.track.reorder"))
        reorderHandleImageView.contentTintColor = NSColor.white.withAlphaComponent(0.45)
        reorderHandleImageView.translatesAutoresizingMaskIntoConstraints = false
        reorderHandleImageView.isHidden = true
        reorderHandleImageView.setAccessibilityIdentifier("NativeQueueTrackReorderGrip")
        reorderHandleImageView.setAccessibilityLabel(L10n.text("queue.track.reorderSong"))
        addSubview(reorderHandleImageView)

        let reorderW = reorderHandleImageView.widthAnchor.constraint(equalToConstant: 18)
        let reorderH = reorderHandleImageView.heightAnchor.constraint(equalToConstant: 16)
        self.reorderHandleWidthConstraint = reorderW
        self.reorderHandleHeightConstraint = reorderH

        // Constraints de tamaño de artwork
        let artW = artworkImageView.widthAnchor.constraint(equalToConstant: 48)
        let artH = artworkImageView.heightAnchor.constraint(equalToConstant: 48)
        self.artworkWidthConstraint = artW
        self.artworkHeightConstraint = artH

        // Constraints condicionales para cuando hay columna de álbum separada vs compacta
        let tWithAlbum = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: albumLabel.leadingAnchor, constant: -14)
        let tNoAlbum = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: dislikeButton.leadingAnchor, constant: -12)
        let sWithAlbum = subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: albumLabel.leadingAnchor, constant: -14)
        let sNoAlbum = subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: dislikeButton.leadingAnchor, constant: -12)

        self.titleTrailingWithAlbum = tWithAlbum
        self.titleTrailingNoAlbum = tNoAlbum
        self.subtitleTrailingWithAlbum = sWithAlbum
        self.subtitleTrailingNoAlbum = sNoAlbum

        NSLayoutConstraint.activate([
            // Índice
            indexLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            indexLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            indexLabel.widthAnchor.constraint(equalToConstant: 24),

            playingIconView.centerXAnchor.constraint(equalTo: indexLabel.centerXAnchor),
            playingIconView.centerYAnchor.constraint(equalTo: indexLabel.centerYAnchor),
            playW,
            playH,

            // Artwork
            artworkImageView.leadingAnchor.constraint(equalTo: indexLabel.trailingAnchor, constant: 10),
            artworkImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            artW,
            artH,

            // Título
            titleLabel.leadingAnchor.constraint(equalTo: artworkImageView.trailingAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1.5),

            // Subtítulo (Artista • Álbum)
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1.5),

            // Álbum separado (opcional)
            albumLabel.trailingAnchor.constraint(equalTo: dislikeButton.leadingAnchor, constant: -16),
            albumLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            albumLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 160),

            // Botón Dislike
            dislikeButton.trailingAnchor.constraint(equalTo: likeButton.leadingAnchor, constant: -6),
            dislikeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dislikeW,
            dislikeH,

            // Botón Like
            likeButton.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -8),
            likeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            likeW,
            likeH,

            // Duración
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 44),

            // Handle Reordenar (mismo centro que la duración)
            reorderHandleImageView.centerXAnchor.constraint(equalTo: durationLabel.centerXAnchor),
            reorderHandleImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            reorderW,
            reorderH,

            // Activación inicial sin álbum separado
            tNoAlbum,
            sNoAlbum
        ])
    }

    @objc private func onLikeClicked() {
        guard let track = boundTrack else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onLike?(track)
        }
    }

    @objc private func onDislikeClicked() {
        guard let track = boundTrack else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onDislike?(track)
        }
    }

    func updateHover(isHovered: Bool) {
        isPointerHovered = isHovered
        updateActionVisibility()
    }

    func updateSelection(isSelected: Bool) {
        // Selection highlights belong to the table and do not reveal floating actions.
    }

    func updateCreditFocus(_ isFocused: Bool) {
        isCreditFocused = isFocused
        updateActionVisibility()
    }

    func refreshLocalization() {
        if let track = boundTrack, track.artists.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if includesAlbumInSubtitle, let album = track.displayAlbum, !album.isEmpty {
                subtitleLabel.stringValue = "\(track.displayArtist) • \(album)"
            } else {
                subtitleLabel.stringValue = track.displayArtist
            }
            subtitleLabel.setAccessibilityLabel(subtitleLabel.stringValue)
        }
        let like = L10n.text(isLiked ? "detail.track.unlike" : "detail.track.like")
        let dislike = L10n.text("queue.track.dislikeRemove")
        likeButton.toolTip = like
        likeButton.setAccessibilityLabel(like)
        dislikeButton.toolTip = dislike
        dislikeButton.setAccessibilityLabel(L10n.text("queue.track.dislikeRemoveAX"))
        artworkImageView.setAccessibilityLabel(L10n.text("detail.track.artwork"))
        reorderHandleImageView.setAccessibilityLabel(L10n.text("queue.track.reorderSong"))
        reorderHandleImageView.toolTip = L10n.text("queue.track.reorderSong")
    }

    var containsKeyboardFocus: Bool {
        var responder = window?.firstResponder
        while let current = responder {
            guard let view = current as? NSView else { return false }
            if view === self { return true }
            responder = view.superview
        }
        return false
    }

    private func updateActionVisibility() {
        let controlsAreActive = isPointerHovered || isCreditFocused || containsKeyboardFocus
        durationLabel.isHidden = isReorderable && controlsAreActive
        reorderHandleImageView.isHidden = !(isReorderable && controlsAreActive)
        likeButton.isHidden = false
        dislikeButton.isHidden = !controlsAreActive
        likeButton.alphaValue = 1
        dislikeButton.alphaValue = controlsAreActive ? 0.70 : 0
    }

    func configure(
        track: SongItemRecord,
        index: Int,
        isCurrentTrack: Bool,
        isPlaying: Bool,
        isLiked: Bool,
        hideAlbum: Bool,
        showAlbumInSubtitle: Bool,
        isReorderable: Bool,
        rowHeight: CGFloat
    ) {
        imageFetchTask?.cancel()
        imageFetchTask = nil
        imageRequestID = nil
        self.boundTrack = track
        includesAlbumInSubtitle = showAlbumInSubtitle
        self.currentVideoId = track.videoId
        self.isReorderable = isReorderable
        self.isLiked = isLiked
        self.isCurrentTrack = isCurrentTrack
        isPointerHovered = false
        isCreditFocused = containsKeyboardFocus

        let isCompact = rowHeight <= 48.0
        let isLarge = rowHeight >= 60.0

        let titleFontSize: CGFloat = isCompact ? 13.0 : (isLarge ? 14.0 : 13.5)
        let subtitleFontSize: CGFloat = isCompact ? 11.5 : (isLarge ? 12.0 : 12.0)

        // 1. Estado de reproducción e índice
        if isCurrentTrack {
            indexLabel.isHidden = true
            playingIconView.isHidden = false
            let symbolName = isPlaying ? "speaker.wave.3.fill" : "speaker.fill"
            let iconPtSize: CGFloat = isCompact ? 11.5 : 13.0
            let iconConfig = NSImage.SymbolConfiguration(pointSize: iconPtSize, weight: .semibold)
            playingIconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(iconConfig)
            titleLabel.textColor = .labelColor
            titleLabel.font = .systemFont(ofSize: titleFontSize, weight: .semibold)
        } else {
            indexLabel.isHidden = false
            playingIconView.isHidden = true
            indexLabel.stringValue = "\(index + 1)"
            indexLabel.font = .systemFont(ofSize: subtitleFontSize, weight: .regular)
            titleLabel.textColor = .labelColor
            titleLabel.font = .systemFont(ofSize: titleFontSize, weight: .medium)
        }

        // 2. Metadatos
        titleLabel.stringValue = track.title

        if showAlbumInSubtitle, let album = track.displayAlbum, !album.isEmpty {
            subtitleLabel.stringValue = "\(track.displayArtist) • \(album)"
        } else {
            subtitleLabel.stringValue = track.displayArtist
        }
        subtitleLabel.setAccessibilityLabel(subtitleLabel.stringValue)
        subtitleLabel.font = .systemFont(ofSize: subtitleFontSize, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor

        let usesSeparateAlbum = !hideAlbum && !showAlbumInSubtitle
        albumLabel.stringValue = usesSeparateAlbum ? (track.displayAlbum ?? "") : ""
        albumLabel.font = .systemFont(ofSize: subtitleFontSize, weight: .regular)
        albumLabel.isHidden = !usesSeparateAlbum

        if usesSeparateAlbum {
            titleTrailingNoAlbum?.isActive = false
            subtitleTrailingNoAlbum?.isActive = false
            titleTrailingWithAlbum?.isActive = true
            subtitleTrailingWithAlbum?.isActive = true
        } else {
            titleTrailingWithAlbum?.isActive = false
            subtitleTrailingWithAlbum?.isActive = false
            titleTrailingNoAlbum?.isActive = true
            subtitleTrailingNoAlbum?.isActive = true
        }

        updatePlaybackDuration(nil)
        durationLabel.font = .systemFont(ofSize: subtitleFontSize, weight: .regular)

        // 3. Botones Like & Dislike adaptativos
        let buttonSize: CGFloat = isCompact ? 18.0 : (isLarge ? 22.0 : 20.0)
        likeButtonWidthConstraint?.constant = buttonSize
        likeButtonHeightConstraint?.constant = buttonSize
        dislikeButtonWidthConstraint?.constant = buttonSize
        dislikeButtonHeightConstraint?.constant = buttonSize

        let buttonSymbolPtSize: CGFloat = isCompact ? 12.0 : (isLarge ? 14.0 : 13.0)
        let buttonSymbolConfig = NSImage.SymbolConfiguration(pointSize: buttonSymbolPtSize, weight: .regular)

        let heartSymbol = isLiked ? "heart.fill" : "heart"
        likeButton.image = NSImage(systemSymbolName: heartSymbol, accessibilityDescription: L10n.text(isLiked ? "detail.track.unlike" : "detail.track.like"))?.withSymbolConfiguration(buttonSymbolConfig)
        likeButton.contentTintColor = isLiked ? .white : NSColor.white.withAlphaComponent(0.65)
        likeButton.setAccessibilityLabel(L10n.text(isLiked ? "detail.track.unlike" : "detail.track.like"))

        dislikeButton.image = NSImage(systemSymbolName: "hand.thumbsdown", accessibilityDescription: L10n.text("queue.track.dislikeRemove"))?.withSymbolConfiguration(buttonSymbolConfig)
        dislikeButton.contentTintColor = NSColor.white.withAlphaComponent(0.65)
        updateActionVisibility()

        // Handle de reordenar
        let handleW: CGFloat = isCompact ? 16.0 : 18.0
        let handleH: CGFloat = isCompact ? 14.0 : 16.0
        reorderHandleWidthConstraint?.constant = handleW
        reorderHandleHeightConstraint?.constant = handleH
        let handleConfig = NSImage.SymbolConfiguration(pointSize: isCompact ? 12.0 : 13.5, weight: .regular)
        reorderHandleImageView.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: L10n.text("detail.track.reorder"))?.withSymbolConfiguration(handleConfig)
        reorderHandleImageView.isHidden = true

        // Icono de reproducción
        let playIconSize: CGFloat = isCompact ? 12.0 : 14.0
        playingIconWidthConstraint?.constant = playIconSize
        playingIconHeightConstraint?.constant = playIconSize

        // 4. Adaptación de tamaño de carátula según altura de fila
        let artSize: CGFloat = isLarge ? 48.0 : (isCompact ? 36.0 : 40.0)
        artworkWidthConstraint?.constant = artSize
        artworkHeightConstraint?.constant = artSize
        artworkImageView.layer?.cornerRadius = AppTheme.artworkThumbnailRadius

        // 5. Restablecer acciones después de actualizar el tamaño y estado.
        updateActionVisibility()

        // 6. Miniatura Desacoplada (0ms de impacto en SwiftUI)
        loadThumbnail(for: track, targetSize: CGSize(width: artSize, height: artSize))
    }

    /// Catalog cards can omit duration even after the player has resolved the stream.
    /// This is display-only; voting callbacks retain the original bound occurrence.
    func updatePlaybackDuration(_ duration: String?) {
        let catalogDuration = boundTrack?.duration?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let catalogDuration, !catalogDuration.isEmpty {
            durationLabel.stringValue = catalogDuration
        } else {
            durationLabel.stringValue = isCurrentTrack ? (duration ?? "—:—") : ""
        }
    }

    private func loadThumbnail(for track: SongItemRecord, targetSize: CGSize) {
        imageFetchTask?.cancel()
        imageFetchTask = nil
        let requestID = UUID()
        imageRequestID = requestID

        guard let thumbUrlString = track.thumbnail,
              let url = ImageURLHelper.optimizedThumbnailURL(from: thumbUrlString, targetPixelSize: Int(targetSize.width * 2))
        else {
            artworkImageView.image = nil
            return
        }

        // Fast-path en RAM: lectura sincrónica de memoria sin esperas ni tareas
        if let cached = ImageCache.shared.imageFromMemoryCache(for: url, targetSize: targetSize) {
            artworkImageView.image = cached
            imageRequestID = nil
            return
        }

        // Carga en segundo plano fuera de SwiftUI
        artworkImageView.image = nil
        let expectedVideoId = track.videoId
        imageFetchTask = Task(priority: .utility) { @MainActor [weak self] in
            let loaded = await ImageCache.shared.image(for: url, targetSize: targetSize)
            guard !Task.isCancelled else { return }
            guard let self,
                  self.currentVideoId == expectedVideoId,
                  self.imageRequestID == requestID else { return }
            self.artworkImageView.image = loaded
            self.imageRequestID = nil
            self.imageFetchTask = nil
        }
    }
}
