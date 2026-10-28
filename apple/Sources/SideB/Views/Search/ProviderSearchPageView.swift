import SwiftUI
import AppKit
import SideBCore

/// A prepared section keeps occurrence payload lookup out of cell construction.
@MainActor final class ProviderSearchPreparedSection {
    let id: String
    let record: SearchSectionRecord
    let roles: ProviderSearchSectionRoles?
    let songs: [Int: SongItemRecord]
    let remaining: [Int]
    let measurementRevision: UInt
    init(record: SearchSectionRecord, position: Int, measurementRevision: UInt = 0) {
        self.measurementRevision = measurementRevision
        id = "\(position):\(record.id)"
        self.record = record
        roles = ProviderSearchProjection.roles(for: record)
        songs = ProviderSearchProjection.songsByItemIndex(in: record)
        let consumed = Set(([roles?.primaryIndex].compactMap { $0 }) + (roles?.relatedIndices ?? []))
        remaining = record.items.indices.filter { !consumed.contains($0) }
    }
}

enum ProviderSearchPageEntry {
    case heading(ProviderSearchPreparedSection)
    case principal(ProviderSearchPreparedSection)
    case actions(ProviderSearchPreparedSection)
    case carousel(ProviderSearchPreparedSection)
    case row(ProviderSearchPreparedSection, Int)
    case correction, loading, error, empty, more
}

/// Rebuild projections only on a received page, never on scroll, hover or playback.
@MainActor final class ProviderSearchPageSnapshot {
    private var sourceRevision: UInt?
    private var expansion: Set<String> = []
    private var footerIdentity: [String] = []
    private(set) var sections: [ProviderSearchPreparedSection] = []
    private(set) var entries: [ProviderSearchViewportEntry] = []
    private(set) var content: [AnyHashable: ProviderSearchPageEntry] = [:]
    private(set) var revision: UInt = 0
    private(set) var projectionCount = 0

    func prepare(page: SearchPageRecord?, revision: UInt, expanded: Set<String>, loading: Bool,
                 error: String?, loadingMore: Bool, localization: String) {
        let footer = [String(loading), error ?? "", String(loadingMore), localization]
        let changedPage = sourceRevision != revision
        guard changedPage || expansion != expanded || footerIdentity != footer else { return }
        if changedPage {
            sourceRevision = revision
            let previous = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0) })
            sections = (page?.sections ?? []).enumerated().map { position, record in
                let old = previous["\(position):\(record.id)"]
                return ProviderSearchPreparedSection(record: record, position: position,
                    measurementRevision: old?.record == record ? old!.measurementRevision : revision)
            }
            projectionCount += 1
        }
        expansion = expanded; footerIdentity = footer
        entries = []; content = [:]
        func append(_ key: String, kind: ProviderSearchViewportEntry.Kind, height: CGFloat? = nil,
                    measurementRevision: AnyHashable? = nil, _ value: ProviderSearchPageEntry) {
            entries.append(ProviderSearchViewportEntry(id: key, kind: kind, height: height,
                measurementRevision: measurementRevision ?? AnyHashable(self.revision &+ 1)))
            content[AnyHashable(key)] = value
        }
        if page?.correction != nil { append("correction", kind: .footer, .correction) }
        if loading && page == nil { append("loading", kind: .footer, height: 80, .loading) }
        for section in sections {
            let record = section.record
            let repeatsPrincipal = section.roles.map { record.title == record.items[$0.primaryIndex].title } ?? false
            if (!record.title.isEmpty && !repeatsPrincipal) || record.moreParams != nil || record.moreBrowseId != nil || record.moreQuery != nil {
                append("\(section.id):heading", kind: .heading, height: 44, .heading(section))
            }
            if section.roles != nil {
                append("\(section.id):principal", kind: .principal,
                    measurementRevision: AnyHashable([AnyHashable(section.measurementRevision),
                        AnyHashable(expanded.contains(section.id)), AnyHashable(localization)]), .principal(section))
            } else if !record.actions.isEmpty {
                append("\(section.id):actions", kind: .action, height: 48, .actions(section))
            }
            if record.layout == "carousel" {
                append("\(section.id):carousel", kind: .carousel, height: 232, .carousel(section))
            } else {
                for index in section.remaining {
                    append("\(section.id):row:\(index)", kind: .row, height: 58, .row(section, index))
                }
            }
        }
        if error != nil { append("error", kind: .footer, .error) }
        if page?.continuation != nil { append("more", kind: .footer, height: 64, .more) }
        if !loading && sections.isEmpty && error == nil { append("empty", kind: .footer, height: 80, .empty) }
        self.revision &+= 1
    }
}

/// One native viewport owns the header and recycled provider results.
struct ProviderSearchPageView: View {
    let page: SearchPageRecord?
    @Bindable var model: SearchViewModel
    var player: PlayerViewModel
    var router: NavigationRouter
    let core: SideBCore
    var scrollingHeader: AnyView? = nil
    @State private var expandedRelatedSections: Set<String> = []
    @State private var snapshot = ProviderSearchPageSnapshot()

    private var pageError: String? {
        model.partialErrors[.categories] ?? model.partialErrors[.global] ?? model.errorMessage
    }

    var body: some View {
        let _ = snapshot.prepare(page: page, revision: model.providerPageRevision, expanded: expandedRelatedSections,
            loading: model.isCommittedLoading || model.isMixedLoading,
            error: pageError, loadingMore: model.isLoadingMore, localization: String(L10n.revision))
        ProviderSearchViewport(entries: snapshot.entries, resetIdentity: AnyHashable(model.providerRequestIdentity),
            snapshotRevision: AnyHashable(snapshot.revision),
            renderRevision: AnyHashable([player.currentTrack?.videoId ?? "", String(player.isPlaying), String(describing: player.queueManager.context)]),
            scrollingHeader: scrollingHeader,
            rowContent: { entry, width in AnyView(content(entry, width: width)) },
            onActivate: { entry in
                switch snapshot.content[entry.id] {
                case .row(let section, let index):
                    let card = section.record.items[index]
                    if section.songs[index] != nil { play(card, index: index, section: section) }
                    else { open(card) }
                case .principal(let section):
                    if let index = section.roles?.primaryIndex {
                        let card = section.record.items[index]
                        if section.songs[index] != nil { play(card, index: index, section: section) }
                        else { open(card) }
                    }
                default: break
                }
            })
            .onChange(of: model.providerRequestIdentity) { _, _ in expandedRelatedSections = [] }
    }

    @ViewBuilder private func content(_ entry: ProviderSearchViewportEntry, width: CGFloat) -> some View {
        if let value = snapshot.content[entry.id] {
            switch value {
            case .heading(let section): sectionHeading(section.record)
            case .principal(let section): principal(section, width: width).padding(.vertical, 8)
            case .actions(let section): sectionActions(section.record)
            case .carousel(let section): carousel(section)
            case .row(let section, let index): row(section.record.items[index], index: index, section: section)
            case .correction:
                if let correction = page?.correction {
                    HStack(spacing: 12) {
                        Text(L10n.text(correction.applied ? "search.correction.showing" : "search.correction.suggested", args: [correction.query]))
                        Button(L10n.text(correction.applied ? "search.correction.original" : "search.correction.search")) {
                            model.searchProviderCorrection(original: correction.applied, core: core)
                        }.buttonStyle(.plain).foregroundStyle(AppTheme.accent)
                    }.font(.system(size: 13)).padding(.vertical, 12)
                }
            case .loading: ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            case .error:
                VStack(alignment: .leading, spacing: 8) {
                    Text(pageError ?? "").font(.system(size: 13)).foregroundStyle(.secondary)
                    Button(L10n.text("common.retry")) {
                        if page?.continuation != nil, model.partialErrors[.categories] != nil { model.loadMore(core: core) }
                        else { model.retryBlock(model.partialErrors[.categories] != nil ? .categories : .global, core: core) }
                    }.buttonStyle(SideBControlStyle(size: .utility))
                }.padding(.vertical, 12)
            case .empty: Text(L10n.text("search.empty.query", args: [model.committedQuery])).foregroundStyle(.secondary).padding(.vertical, 20)
            case .more:
                Button { model.loadMore(core: core) } label: {
                    HStack { if model.isLoadingMore { ProgressView().controlSize(.small) }; Text(L10n.text("search.provider.load_more")) }
                }.buttonStyle(SideBControlStyle()).disabled(model.isLoadingMore).padding(.vertical, 8)
            }
        }
    }

    private func principal(_ section: ProviderSearchPreparedSection, width: CGFloat) -> some View {
        let roles = section.roles!
        let record = section.record
        return ProviderSearchPrincipalView(section: record, roles: roles, width: width,
            isExpanded: expandedRelatedSections.contains(section.id), actions: record.actions,
            onAction: { activate($0, section: section) },
            row: { index in AnyView(row(record.items[index], index: index, section: section)) },
            onToggleRelated: {
                if expandedRelatedSections.contains(section.id) { expandedRelatedSections.remove(section.id) }
                else { expandedRelatedSections.insert(section.id) }
            }, onPlay: { index in play(record.items[index], index: index, section: section) },
            onOpen: { open(record.items[roles.primaryIndex]) },
            menuProvider: { moreMenu(index: roles.primaryIndex, section: section) },
            onOpenArtist: { id, name in
                if let id { router.navigate(to: .artist(browseId: id)) }
                else { router.navigate(to: .search(query: name)) }
            },
            onOpenAlbum: section.songs[roles.primaryIndex]?.albumId.map { id in { router.navigate(to: .album(browseId: id)) } },
            primarySongPayload: section.songs[roles.primaryIndex])
    }

    private func sectionHeading(_ section: SearchSectionRecord) -> some View {
        HStack {
            if !section.title.isEmpty { Text(section.title).font(.system(size: 18, weight: .semibold)) }
            Spacer(minLength: 8)
            if section.moreParams != nil || section.moreBrowseId != nil || section.moreQuery != nil {
                Button(L10n.text("search.provider.show_all")) { openMore(section) }.buttonStyle(SideBControlStyle(size: .utility))
            }
        }.padding(.top, 4)
    }

    private func sectionActions(_ section: SearchSectionRecord) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { ForEach(Array(section.actions.enumerated()), id: \.offset) { _, action in
                Button(action.title) { activate(action, section: section) }.buttonStyle(SideBControlStyle())
            } }
        }.frame(height: 40)
    }

    private func carousel(_ section: ProviderSearchPreparedSection) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 16) {
                ForEach(Array(section.record.items.enumerated()), id: \.offset) { index, card in
                    ProviderSearchCarouselCard(card: ProviderSearchProjection.displayCard(card, song: section.songs[index]),
                        isActive: MediaPlaybackIdentity.isCollectionActive(kind: card.kind, id: card.id, context: player.queueManager.context),
                        isPlaying: player.isPlaying,
                        onOpen: {
                            if section.songs[index] != nil { play(card, index: index, section: section) }
                            else { open(card) }
                        }, onPlay: { play(card, index: index, section: section) },
                        menuProvider: { moreMenu(index: index, section: section) })
                        .frame(width: 160)
                }
            }.padding(.vertical, 6)
        }
    }

    @ViewBuilder private func row(_ card: BrowseCardRecord, index: Int, section: ProviderSearchPreparedSection) -> some View {
        if let song = section.songs[index] {
            QuickResultSongRow(song: song,
                onFeatured: { id, name in
                    if let id { router.navigate(to: .artist(browseId: id)) }
                    else { router.navigate(to: .search(query: name)) }
                }, onArtist: song.artistId.map { id in { router.navigate(to: .artist(browseId: id)) } },
                onAlbum: song.albumId.map { id in { router.navigate(to: .album(browseId: id)) } },
                menuProvider: { AppContextMenuFactory.shared.buildSongNSMenu(song: song, player: player,
                    router: router, core: core, origin: .search) }, onSelect: { player.activateMediaRadio(song) })
                .songContextMenu(song: song, player: player, router: router, core: core, origin: .search)
        } else {
            QuickResultCardRow(card: card,
                isActive: MediaPlaybackIdentity.isCollectionActive(kind: card.kind, id: card.id, context: player.queueManager.context),
                isPlaying: player.isPlaying,
                onPlay: ["album", "playlist"].contains(card.kind) ? { player.activateMediaCollection(id: card.id, kind: card.kind) } : nil,
                menuProvider: { moreMenu(index: index, section: section) }, onSelect: { open(card) })
                .browseCardContextMenu(card: card, player: player, router: router, core: core, origin: .search)
        }
    }

    private func play(_ card: BrowseCardRecord, index: Int, section: ProviderSearchPreparedSection) {
        if let song = section.songs[index] { player.activateMediaRadio(song) }
        else if ["album", "playlist"].contains(card.kind) { player.activateMediaCollection(id: card.id, kind: card.kind) }
    }

    private func moreMenu(index: Int, section: ProviderSearchPreparedSection) -> NSMenu? {
        let card = section.record.items[index], factory = AppContextMenuFactory.shared
        if let song = section.songs[index] { return factory.buildSongNSMenu(song: song, player: player, router: router, core: core, origin: .search) }
        switch card.kind {
        case "artist": return factory.buildArtistNSMenu(channelId: card.id, name: card.title, thumbnail: card.thumbnail,
            radioPlaylistId: nil, origin: .search, player: player, router: router, core: core)
        case "album": return factory.buildAlbumNSMenu(browseId: card.id, playlistId: nil, title: card.title,
            artist: card.subtitle, thumbnail: card.thumbnail, origin: .search, player: player, router: router, core: core)
        case "playlist": return factory.buildPlaylistNSMenu(id: card.id, title: card.title, subtitle: card.subtitle,
            thumbnail: card.thumbnail, origin: .search, player: player, router: router, core: core)
        default: return nil
        }
    }

    private func open(_ card: BrowseCardRecord) {
        switch card.kind {
        case "artist": router.navigate(to: .artist(browseId: card.id))
        case "album": router.navigate(to: .album(browseId: card.id))
        case "playlist": router.navigate(to: .playlist(browseId: card.id))
        default: break
        }
    }

    private func openMore(_ section: SearchSectionRecord) {
        if let id = section.moreBrowseId { router.navigate(to: .catalog(browseId: id, params: section.moreParams, title: section.title)) }
        else { model.openProviderSection(section, core: core) }
    }

    private func activate(_ action: SearchActionRecord, section: ProviderSearchPreparedSection) { activate(action, section: section.record) }
    private func activate(_ action: SearchActionRecord, section: SearchSectionRecord) {
        if action.videoId != nil || action.playlistId != nil {
            let primaryIndex = ProviderSearchProjection.roles(for: section)?.primaryIndex ?? 0
            player.activateProviderSearchAction(action, title: section.title,
                source: section.items.indices.contains(primaryIndex) ? section.items[primaryIndex] : nil)
        } else if let id = action.browseId {
            if action.params != nil { router.navigate(to: .catalog(browseId: id, params: action.params, title: section.title)) }
            else if id.hasPrefix("MPRE") { router.navigate(to: .album(browseId: id)) }
            else if id.hasPrefix("UC") { router.navigate(to: .artist(browseId: id)) }
            else { router.navigate(to: .catalog(browseId: id, params: nil, title: section.title)) }
        }
    }
}

/// A provider carousel retains its card geometry and occurrence-specific actions.
private struct ProviderSearchCarouselCard: View {
    let card: BrowseCardRecord
    let isActive: Bool
    let isPlaying: Bool
    let onOpen: () -> Void
    let onPlay: () -> Void
    let menuProvider: () -> NSMenu?

    private var artist: Bool { card.kind == "artist" }
    private var collection: Bool { ["album", "playlist"].contains(card.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if artist {
                Button(action: onOpen) { artwork }.buttonStyle(.plain).mediaCardFocusControl()
            } else {
                MediaArtworkControls(isCollection: collection, isActive: collection && isActive,
                    isPlaying: collection && isActive && isPlaying, showsIndicator: collection && isActive,
                    accessibilityTitle: card.title, onOpen: onOpen, onPlay: onPlay,
                    menuProvider: menuProvider) { artwork }
                    .frame(width: 160, height: 160)
            }
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    if let subtitle = card.subtitle, !subtitle.isEmpty {
                        ContentRatedMetadata(rating: card.contentRating, fontSize: 12) {
                            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    } else if card.contentRating != .unknown {
                        ContentRatingBadge(rating: card.contentRating, fontSize: 12)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }.buttonStyle(.plain).mediaCardFocusControl()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .mediaCardSurface()
        .overlay { NativeContextMenuOverlay(menuProvider: menuProvider) }
    }

    private var artwork: some View {
        Group {
            if let thumbnail = card.thumbnail,
               let url = ImageURLHelper.optimizedThumbnailURL(from: thumbnail, targetPixelSize: 360) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 160, height: 160)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { placeholder }
            } else { placeholder }
        }
        .frame(width: 160, height: 160)
        .clipShape(artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: AppTheme.artworkCardRadius)))
    }

    private var placeholder: some View {
        ZStack {
            Color.white.opacity(0.06)
            Image(systemName: artist ? "person.fill" : collection ? "opticaldisc" : "music.note")
                .font(.system(size: 38)).foregroundStyle(.secondary)
        }
    }
}
