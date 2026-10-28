import SwiftUI
import AppKit
import SideBCore

/// The provider-marked block gets its own visual hierarchy. Related rows remain occurrences
/// from the same section and never pull items from a later shelf.
struct ProviderSearchPrincipalView: View {
    let section: SearchSectionRecord
    let roles: ProviderSearchSectionRoles
    let width: CGFloat
    let isExpanded: Bool
    let actions: [SearchActionRecord]
    let onAction: (SearchActionRecord) -> Void
    let row: (Int) -> AnyView
    let onToggleRelated: () -> Void
    let onPlay: (Int) -> Void
    let onOpen: () -> Void
    let menuProvider: () -> NSMenu?
    var onOpenArtist: ((String?, String) -> Void)? = nil
    var onOpenAlbum: (() -> Void)? = nil
    var primarySongPayload: SongItemRecord? = nil
    @State private var menuLocation = ProviderPrincipalMenuLocation()

    private var primary: BrowseCardRecord { section.items[roles.primaryIndex] }
    private var related: [Int] { isExpanded ? roles.relatedIndices : Array(roles.relatedIndices.prefix(3)) }
    private var artist: Bool { primary.kind == "artist" }
    private var primaryActivationLabel: String {
        ["song", "video"].contains(primary.kind)
            ? L10n.text("player.playNamedTrack", args: [primary.title])
            : L10n.text("detail.openNamed", args: [primary.title])
    }
    private func activatePrimary() {
        if ["song", "video"].contains(primary.kind) {
            onPlay(roles.primaryIndex)
        } else {
            onOpen()
        }
    }
    private var artworkSize: CGFloat {
        switch primary.kind {
        case "artist", "album": 96
        case "song", "video": 80
        default: 96
        }
    }
    private var primarySong: SongItemRecord? {
        primarySongPayload ?? ProviderSearchProjection.song(for: roles.primaryIndex, in: section)
    }
    private var hasPlayableProviderAction: Bool {
        actions.contains { $0.videoId != nil || $0.playlistId != nil }
    }
    private var layout: ProviderSearchPrincipalLayout {
        ProviderSearchProjection.principalLayout(kind: primary.kind, hasRelated: !roles.relatedIndices.isEmpty, width: width)
    }

    var body: some View {
        Group {
            if layout == .artistSplit {
                let contentWidth = width - 32 - 24
                HStack(alignment: .center, spacing: 24) {
                    identity.frame(width: contentWidth * 0.44, alignment: .leading)
                    relatedContent.frame(width: contentWidth * 0.56, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    identity
                    if !roles.relatedIndices.isEmpty { relatedContent }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.7))
        .overlay { NativeContextMenuOverlay(menuProvider: menuProvider) }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var identity: some View {
        if artist && width < 680 {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    artwork(size: artworkSize, circle: true).frame(width: artworkSize, height: artworkSize)
                    titleAndMetadata.frame(maxWidth: .infinity, alignment: .leading)
                }
                actionGroup.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if artist || layout == .artistSplit {
            HStack(alignment: .center, spacing: 16) {
                artwork(size: artworkSize, circle: artist).frame(width: artworkSize, height: artworkSize)
                VStack(alignment: .leading, spacing: 12) {
                    titleAndMetadata
                    actionGroup.frame(maxWidth: 320, alignment: .leading)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: .center, spacing: 16) {
                artwork(size: artworkSize, circle: false).frame(width: artworkSize, height: artworkSize)
                titleAndMetadata.frame(maxWidth: .infinity, alignment: .leading)
                actionGroup.frame(maxWidth: 320, alignment: .trailing)
            }
        }
    }

    private var titleAndMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: activatePrimary) {
                Text(primary.title).font(.system(size: 24, weight: artist ? .semibold : .medium)).foregroundStyle(.primary)
                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).accessibilityLabel(primaryActivationLabel)
            if let song = primarySong {
                ContentRatedMetadata(rating: song.contentRating, fontSize: 13) {
                    HStack(spacing: 5) {
                        if let onOpenArtist {
                            TrackArtistLinks(track: song, font: .system(size: 13), color: .secondary,
                                hoverColor: .primary, onNavigate: onOpenArtist)
                        } else {
                            Text(song.artists).lineLimit(2)
                        }
                        if let album = song.album, !album.isEmpty {
                            Text("·").foregroundStyle(.tertiary)
                            if let onOpenAlbum {
                                Button(album, action: onOpenAlbum).buttonStyle(.plain)
                                    .foregroundStyle(.secondary).lineLimit(2)
                            } else { Text(album).lineLimit(2) }
                        }
                        if let duration = song.duration, !duration.isEmpty {
                            Text("·").foregroundStyle(.tertiary)
                            Text(duration).monospacedDigit().fixedSize()
                        }
                    }
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else if let subtitle = primary.subtitle, !subtitle.isEmpty {
                ContentRatedMetadata(rating: primary.kind == "album" ? primary.contentRating : .unknown, fontSize: 13) {
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ContentRatedMetadata(rating: primary.kind == "album" ? primary.contentRating : .unknown, fontSize: 13) {
                    Text(kindLabel).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionGroup: some View {
        ProviderPrincipalActionFlow(spacing: 8, rowSpacing: 8) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                Button(action.title) { onAction(action) }.buttonStyle(SideBControlStyle())
            }
            if !hasPlayableProviderAction && ["song", "video", "album", "playlist"].contains(primary.kind) {
                Button { onPlay(roles.primaryIndex) } label: {
                    SideBControlLabel(title: L10n.text("player.play"), symbol: "play.fill")
                }.buttonStyle(SideBControlStyle(prominent: true))
            }
            if artist || ["album", "playlist"].contains(primary.kind) {
                Button(action: onOpen) {
                    SideBControlLabel(title: L10n.text("home.open"), symbol: "arrow.up.right")
                }.buttonStyle(SideBControlStyle())
                    .accessibilityLabel(L10n.text("detail.openNamed", args: [primary.title]))
            }
            Button {
                guard let menu = menuProvider() else { return }
                menuLocation.show(menu)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: SideBControlMetrics.utilityHeight, height: SideBControlMetrics.utilityHeight)
                    .contentShape(Circle())
            }.buttonStyle(SideBControlStyle(size: .utility, iconOnly: true))
                .accessibilityLabel(L10n.text("common.moreOptionsFor", args: [primary.title]))
                .background(ProviderPrincipalMenuAnchor(location: menuLocation))
        }
        .frame(maxWidth: 320, alignment: artist ? .leading : .trailing)
    }

    private var relatedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("search.provider.related"))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(related, id: \.self) { index in row(index) }
            if roles.relatedIndices.count > 3 {
                Button(L10n.text(isExpanded ? "search.provider.hide_related" : "search.provider.show_related",
                                 args: isExpanded ? [] : [String(roles.relatedIndices.count)]), action: onToggleRelated)
                    .buttonStyle(SideBControlStyle(size: .utility))
                    .padding(.top, 4)
            }
        }
    }

    private var kindLabel: String {
        switch primary.kind {
        case "artist": L10n.text("search.filter.artists")
        case "album": L10n.text("metadata.album")
        case "song", "video": L10n.text("metadata.song")
        default: primary.kind.capitalized
        }
    }

    @ViewBuilder private func artwork(size: CGFloat, circle: Bool) -> some View {
        Button(action: activatePrimary) {
        if let thumb = primary.thumbnail,
           let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: Int(size * 2)) {
            CachedAsyncImage(url: url, targetSize: CGSize(width: size, height: size)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { artworkPlaceholder(circle: circle) }
                .frame(width: size, height: size).clipShape(circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous)))
                .overlay {
                    if circle { Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.7) }
                    else { RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.7) }
                }
        } else { artworkPlaceholder(circle: circle).frame(width: size, height: size) }
        }.buttonStyle(.plain).accessibilityLabel(primaryActivationLabel)
    }

    private func artworkPlaceholder(circle: Bool) -> some View {
        ZStack {
            if circle { Circle().fill(Color.white.opacity(0.06)) }
            else { RoundedRectangle(cornerRadius: AppTheme.artworkThumbnailRadius).fill(Color.white.opacity(0.06)) }
            Image(systemName: primary.kind == "artist" ? "person.fill" : primary.kind == "album" ? "opticaldisc" : "music.note")
                .font(.system(size: 28)).foregroundStyle(.secondary)
        }
    }
}

@MainActor private final class ProviderPrincipalMenuLocation {
    weak var anchor: NSView?
    func show(_ menu: NSMenu) {
        guard let anchor, anchor.window != nil else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: anchor.bounds.maxX, y: anchor.bounds.maxY), in: anchor)
    }
}

private struct ProviderPrincipalMenuAnchor: NSViewRepresentable {
    let location: ProviderPrincipalMenuLocation
    func makeNSView(context: Context) -> NSView {
        let view = ProviderPrincipalPassthroughView()
        location.anchor = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { location.anchor = view }
}

private final class ProviderPrincipalPassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct ProviderPrincipalActionFlow: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let naturalWidth = subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width + spacing }
        let proposedWidth = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? naturalWidth
        let placement = layout(subviews, width: proposedWidth)
        return CGSize(width: placement.width, height: placement.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = layout(subviews, width: bounds.width)
        for (index, point) in placement.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                  anchor: .topLeading, proposal: ProposedViewSize(placement.sizes[index]))
        }
    }

    private func layout(_ subviews: Subviews, width: CGFloat) -> (points: [CGPoint], sizes: [CGSize], width: CGFloat, height: CGFloat) {
        var sizes: [CGSize] = []
        for subview in subviews {
            let naturalSize = subview.sizeThatFits(.unspecified)
            let itemWidth = min(max(0, width), naturalSize.width)
            sizes.append(subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)))
        }
        let geometry = ProviderPrincipalActionFlowGeometry.layout(sizes: sizes, width: width,
            spacing: spacing, rowSpacing: rowSpacing)
        return (geometry.points, geometry.sizes, geometry.width, geometry.height)
    }
}

enum ProviderPrincipalActionFlowGeometry {
    static func layout(sizes: [CGSize], width: CGFloat, spacing: CGFloat,
                       rowSpacing: CGFloat) -> (points: [CGPoint], sizes: [CGSize], width: CGFloat, height: CGFloat) {
        guard !sizes.isEmpty else { return ([], [], 0, 0) }
        var points: [CGPoint] = []
        var rowIndices: [Int] = []
        var rowY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var x: CGFloat = 0
        var usedWidth: CGFloat = 0
        var rowHeights: [CGFloat] = []

        for (index, size) in sizes.enumerated() {
            if x > 0, x + size.width > width {
                rowHeights.append(rowHeight)
                rowY += rowHeight + rowSpacing
                x = 0
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: rowY))
            rowIndices.append(rowHeights.count)
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
            if index == sizes.count - 1 { rowHeights.append(rowHeight) }
        }

        for index in points.indices {
            points[index].y += (rowHeights[rowIndices[index]] - sizes[index].height) / 2
        }
        return (points, sizes, min(max(0, width), usedWidth),
                rowHeights.reduce(0, +) + CGFloat(max(0, rowHeights.count - 1)) * rowSpacing)
    }
}
