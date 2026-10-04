import SwiftUI
import AppKit
import SideBCore

// MARK: - QuickResultCardRow

struct QuickResultCardRow: View {
    let card: BrowseCardRecord
    var isHero: Bool = false
    var isActive: Bool = false
    var isPlaying: Bool = false
    var isLoading: Bool = false
    var onPlay: (() -> Void)? = nil
    var menuProvider: (() -> NSMenu?)? = nil
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    private var isArtist: Bool {
        card.kind.lowercased() == "artist"
    }
    
    var body: some View {
        let isCollection = ["album", "playlist"].contains(card.kind.lowercased())
        let activationLabel = isArtist || isCollection ? "Abrir \(card.title)" : "Reproducir \(card.title)"
        let artwork = Group {
            if let thumb = card.thumbnail,
               let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: isHero ? 120 : 96) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: isHero ? 48 : 38, height: isHero ? 48 : 38)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderIcon
                }
                .frame(width: isHero ? 48 : 38, height: isHero ? 48 : 38)
                .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)))
                .overlay(isArtist
                    ? AnyView(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                    : AnyView(RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)))
            } else {
                placeholderIcon
            }
        }
        HStack(spacing: 12) {
            if isCollection, let onPlay {
                MediaArtworkControls(
                    isCollection: true,
                    isActive: isActive,
                    isPlaying: isPlaying,
                    isLoading: isLoading,
                    showsIndicator: isActive,
                    accessibilityTitle: card.title,
                    onOpen: onSelect,
                    onPlay: onPlay,
                    menuProvider: menuProvider
                ) { artwork }
                    .frame(width: isHero ? 48 : 38, height: isHero ? 48 : 38)
            } else if let onPlay, !isArtist {
                MediaArtworkControls(
                    isCollection: false,
                    accessibilityTitle: card.title,
                    onOpen: onSelect,
                    onPlay: onPlay,
                    menuProvider: menuProvider
                ) { artwork }
                    .frame(width: isHero ? 48 : 38, height: isHero ? 48 : 38)
            } else {
                Button(action: onSelect) { artwork }
                    .buttonStyle(.plain)
                    .mediaCardFocusControl()
            }

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.system(size: isHero ? 14 : 13, weight: isHero ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(kindDisplayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isHero ? .primary : .secondary)
                        
                        if let sub = card.subtitle, !sub.isEmpty {
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            
                            Text(sub)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .mediaCardFocusControl()
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
                
                if isHero {
                    Text("Mejor resultado")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }
                
            if isArtist || isCollection {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary.opacity(0.6))
                    .padding(.trailing, 4)
            }
        }
            .padding(.horizontal, 10)
            .padding(.vertical, isHero ? 8 : 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        .mediaCardActivation(label: activationLabel, action: onSelect)
        .mediaCardSurface()
        .onHover { isHovered = $0 }
    }
    
    private var kindDisplayName: String {
        switch card.kind.lowercased() {
        case "artist": return "Artista"
        case "album": return "Álbum"
        case "playlist": return "Playlist"
        case "song": return "Canción"
        default: return card.kind.capitalized
        }
    }
    
    private var placeholderIcon: some View {
        ZStack {
            if isArtist {
                Circle().fill(Color.white.opacity(0.06))
                Image(systemName: "person.fill")
                    .font(.system(size: isHero ? 16 : 14))
                    .foregroundStyle(.secondary)
            } else {
                RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous).fill(Color.white.opacity(0.06))
                Image(systemName: card.kind == "album" ? "opticaldisc" : "music.note")
                    .font(.system(size: isHero ? 16 : 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: isHero ? 48 : 38, height: isHero ? 48 : 38)
    }
}

// MARK: - QuickResultSongRow

struct QuickResultSongRow: View {
    let song: SongItemRecord
    var onArtist: (() -> Void)? = nil
    var onAlbum: (() -> Void)? = nil
    var menuProvider: (() -> NSMenu?)? = nil
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            MediaArtworkControls(
                isCollection: false,
                accessibilityTitle: song.title,
                onOpen: onSelect,
                onPlay: onSelect,
                menuProvider: menuProvider
            ) {
                if let thumb = song.thumbnail,
                   let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 96) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 38, height: 38)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { quickSongPlaceholder }
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                } else {
                    quickSongPlaceholder
                }
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2.5) {
                Text(song.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .allowsHitTesting(false)

                HStack(spacing: 4) {
                    Text("Canción").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary.opacity(0.8))
                        .allowsHitTesting(false)
                    Text("•").font(.system(size: 10)).foregroundStyle(.tertiary).allowsHitTesting(false)
                    if let onArtist {
                        Button(action: onArtist) {
                            Text(song.artists).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .mediaCardFocusControl()
                    } else {
                        Text(song.artists).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    if let album = song.album, !album.isEmpty, let onAlbum {
                        Text("•").font(.system(size: 10)).foregroundStyle(.tertiary)
                        Button(action: onAlbum) {
                            Text(album).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .mediaCardFocusControl()
                    } else if let album = song.album, !album.isEmpty {
                        Text("•").font(.system(size: 10)).foregroundStyle(.tertiary).allowsHitTesting(false)
                        Text(album).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).allowsHitTesting(false)
                    }
                }
                if let duration = song.duration {
                    Text(duration).font(.system(size: 10)).foregroundStyle(.tertiary).allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isHovered ? Color.white.opacity(0.08) : Color.clear))
        .contentShape(Rectangle())
        .mediaCardActivation(label: "Reproducir \(song.title)", action: onSelect)
        .mediaCardSurface()
        .onHover { isHovered = $0 }
    }

    private var quickSongPlaceholder: some View {
        RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(width: 38, height: 38)
            .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
    }
}
