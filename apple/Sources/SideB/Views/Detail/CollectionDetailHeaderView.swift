import SwiftUI

/// Cabecera única de álbumes y playlists, alojada en el mismo scroll de sus canciones.
struct CollectionDetailHeaderView: View {
    let kind: String
    let title: String
    let thumbnail: String?
    let artworkSymbol: String
    var credit: String? = nil
    var creditFontSize: CGFloat = 19.2
    var onCredit: (() -> Void)? = nil
    var metadata: [String] = []
    var description: String? = nil
    let onExpandDescription: () -> Void
    let onPlay: () -> Void
    let onShuffle: () -> Void
    var showsSave = false
    var isSaved = false
    var onSave: (() -> Void)? = nil
    var additionalActions: AnyView? = nil
    @Binding var query: String
    var selectedOrder: DetailTrackOrder? = nil
    var canSort: ((DetailTrackOrder) -> Bool)? = nil
    var onSelectOrder: ((DetailTrackOrder) -> Void)? = nil
    var isCompletingCatalog = false
    var isPlaybackUnavailable = false
    var catalogError: String? = nil
    var onRetryCatalog: (() -> Void)? = nil

    @State private var isHoveringDescription = false
    @State private var isHoveringCredit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28.8) {
                    artwork
                    metadataView.frame(minWidth: 230, maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 24) {
                    artwork
                    metadataView
                }
            }
            toolbar
            if isCompletingCatalog {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text("detail.collection.preparingSongs"))
                        .font(.system(size: 14.4))
                        .foregroundStyle(.secondary)
                }
            }
            if let catalogError, !catalogError.isEmpty {
                HStack(spacing: 12) {
                    Text(catalogError).font(.system(size: 14.4)).foregroundStyle(.secondary)
                    if let onRetryCatalog {
                        Button(L10n.text("common.retry"), action: onRetryCatalog).buttonStyle(.plain)
                    }
                }
            }
            Divider().opacity(0.2)
        }
        .padding(.horizontal, 38.4)
        .padding(.top, 33.6)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var artwork: some View {
        Group {
            if let thumbnail, let url = URL(string: thumbnail) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 216, height: 216)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderArtwork
                }
            } else {
                placeholderArtwork
            }
        }
        .frame(width: 216, height: 216)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 19.2, y: 9.6)
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous)
            .fill(LinearGradient(
                colors: [Color.sidebAccent.opacity(0.30), Color.white.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay {
                Image(systemName: artworkSymbol)
                    .font(.system(size: 67.2))
                    .foregroundStyle(.white.opacity(0.85))
            }
    }

    private var metadataView: some View {
        VStack(alignment: .leading, spacing: 9.6) {
            Text(kind)
                .font(.system(size: 13.2, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1.44)
            Text(title)
                .font(.system(size: 38.4, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let credit, !credit.isEmpty {
                if let onCredit {
                    Button(action: onCredit) {
                        Text(credit).font(.system(size: creditFontSize, weight: .semibold))
                            .foregroundStyle(isHoveringCredit ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .mediaCardFocusControl()
                    .onHover { isHoveringCredit = $0 }
                } else {
                    Text(credit)
                        .font(.system(size: creditFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            if !metadata.isEmpty {
                Text(metadata.filter { !$0.isEmpty }.joined(separator: " • "))
                    .font(.system(size: 14.4))
                    .foregroundStyle(.secondary)
            }
            if let description, !description.isEmpty {
                Button(action: onExpandDescription) {
                    HStack(alignment: .bottom, spacing: 4.8) {
                        Text(description)
                            .font(.system(size: 14.4))
                            .foregroundStyle(isHoveringDescription ? .secondary : .tertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 744, alignment: .leading)
                        Text(L10n.text("detail.more"))
                            .font(.system(size: 13.2, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringDescription = $0 }
                .help(L10n.text("detail.description.readFullHint"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                actions(compact: false)
                Spacer(minLength: 16)
                searchAndOrder
            }
            HStack(spacing: 12) {
                actions(compact: true)
                Spacer(minLength: 12)
                searchAndOrder
            }
            VStack(alignment: .leading, spacing: 16) {
                actions(compact: true)
                HStack {
                    Spacer(minLength: 0)
                    searchAndOrder
                }
            }
        }
    }

    private func actions(compact: Bool) -> some View {
        HStack(spacing: 12) {
            actionButton(L10n.text("player.play"), symbol: "play.fill", compact: compact, action: onPlay)
                .disabled(isPlaybackUnavailable)
            actionButton(L10n.text("player.shuffle"), symbol: "shuffle", compact: compact, action: onShuffle)
                .disabled(isPlaybackUnavailable)
            if showsSave, let onSave {
                actionButton(L10n.text(isSaved ? "detail.collection.inLibrary" : "detail.collection.save"),
                             symbol: isSaved ? "bookmark.fill" : "bookmark",
                             compact: compact, action: onSave)
            }
            additionalActions
        }
        .fixedSize()
    }

    private func actionButton(_ title: String, symbol: String, compact: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7.2) {
                Image(systemName: symbol)
                if !compact { Text(title) }
            }
            .font(.system(size: 15.6, weight: .semibold))
            .padding(.horizontal, compact ? 14.4 : 19.2)
            .padding(.vertical, 9.6)
            .foregroundStyle(.primary)
            .compatGlass(interactive: true, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }

    private var searchAndOrder: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                CollectionSearchField(query: $query)
            }
            .font(.system(size: 14.4))
            .padding(.horizontal, 12)
            .padding(.vertical, 9.6)
            .frame(minWidth: 100, idealWidth: 220, maxWidth: 220)
            .compatGlass(interactive: true, in: Capsule())
            if let selectedOrder, let onSelectOrder {
                Menu {
                    ForEach(DetailTrackOrder.allCases, id: \.self) { order in
                        Button { onSelectOrder(order) } label: {
                            if order == selectedOrder {
                                Label(order.title, systemImage: "checkmark")
                            } else {
                                Text(order.title)
                            }
                        }
                        .disabled(!(canSort?(order) ?? true))
                        .help(order.title)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15.6, weight: .medium))
                        .frame(width: 36, height: 36)
                        .compatGlass(interactive: true, in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel(L10n.text("detail.sort.accessibility", args: [selectedOrder.title]))
                .help(L10n.text("detail.sort.accessibility", args: [selectedOrder.title]))
            }
        }
    }
}

/// Empty results belong to the songs area. Changing the filter must not resize
/// the artwork/actions row or the native search editor mounted in that header.
struct CollectionDetailEmptyResultsView: View {
    let query: String

    var body: some View {
        Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
             ? L10n.text("detail.collection.empty")
             : L10n.text("detail.collection.noResults", args: [query]))
            .font(.system(size: 14.4))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.horizontal, 38.4)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
