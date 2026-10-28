import SwiftUI
import SideBCore

struct FeaturedArtistLink: View {
    let track: SongItemRecord
    let name: String
    var destinationID: String? = nil
    let onNavigate: (String?, String) -> Void
    var hoverColor: Color = .primary
    @State private var operation: Task<Void,Never>?
    @Environment(\.sideBPageIsActive) private var pageIsActive
    @State private var selectionTask: Task<Void,Never>?
    @State private var selectionContext: SelectionContext?
    private struct SelectionContext { let track:SongItemRecord;let name:String;let identity:String;let revision:Int }
    private var identity:String { String(reflecting:track) + "\u{0}" + name }
    private func validSelection(_ context:SelectionContext) -> Bool { context.identity == identity && context.revision == FeaturedArtistResolver.shared.scopeRevision }
    @State private var busy = false
    @State private var selecting = false
    @State private var loadingCandidates = false
    @State private var candidates: [FeaturedArtistCandidate] = []
    @State private var hovered = false
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: open) {
            Text(name)
                .modifier(FeaturedArtistHighlight(active:hovered || focused, color:hoverColor))
        }
            .buttonStyle(.plain)
            .focused($focused)
            .onHover { inside in
                guard hovered != inside else { return }
                hovered = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .accessibilityAddTraits(.isLink)
            .help(L10n.text("featured.open", args:[name]))
            .contextMenu {
                Button(L10n.text("featured.open",args:[name]),action:open)
                Button(L10n.text("featured.change")) { correct() }
                Button(L10n.text("featured.search")) { cancel(); onNavigate(nil,name) }
            }
            .popover(isPresented:$selecting) {
                VStack(alignment:.leading,spacing:8) {
                    Text(L10n.text("featured.change")).font(.headline)
                    ForEach(candidates,id: \.id) { candidate in
                        Button { guard let context = selectionContext,validSelection(context) else { cancel();return }; FeaturedArtistResolver.shared.choose(context.track,name:context.name,id:candidate.id); cancel(); onNavigate(candidate.id,context.name) } label: {
                            VStack(alignment:.leading) { Text(candidate.name); if let subtitle = candidate.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) } }
                        }.buttonStyle(.plain)
                    }
                    if candidates.isEmpty { Text(L10n.text(loadingCandidates ? "featured.searching" : "featured.noMatches")) }
                    Button(L10n.text("featured.search")) { selecting = false; onNavigate(nil,name) }
                    Button(L10n.text("featured.reset")) { guard let context = selectionContext,validSelection(context) else { cancel();return }; FeaturedArtistResolver.shared.choose(context.track,name:context.name,id:nil); cancel() }
                }.padding(16).frame(minWidth:240)
            }
            .overlay(alignment:.topLeading) {
                if busy { HStack { Text(L10n.text("featured.searching")); Button(L10n.text("common.cancel"),action:cancel) }.font(.caption).padding(8).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius:8)).offset(y:24).fixedSize() }
            }
            .onDisappear { if hovered { NSCursor.pop(); hovered = false }; cancel() }
            .onChange(of:identity) { _,_ in cancel() }
            .onChange(of:pageIsActive) { _, active in
                if !active { if hovered { NSCursor.pop(); hovered = false }; focused = false; cancel() }
            }
    }
    private func open() {
        guard pageIsActive else { return }
        cancel()
        // Recheck provider/user correction at interaction time; a cached rendered ID is only presentation.
        busy = true
        operation = Task { @MainActor in
            await FeaturedArtistResolver.shared.open(track,name:name,onNavigate:onNavigate)
            if !Task.isCancelled { busy = false }
        }
    }
    private func correct() {
        selectionTask?.cancel();candidates = [];selecting = true;loadingCandidates = true
        let context = SelectionContext(track:track,name:name,identity:identity,revision:FeaturedArtistResolver.shared.scopeRevision)
        selectionContext = context
        selectionTask = Task { @MainActor in
            let found = await FeaturedArtistResolver.shared.candidates(context.track,name:context.name)
            guard !Task.isCancelled,validSelection(context),selectionContext?.identity == context.identity else { return }
            candidates = found;loadingCandidates = false
        }
    }
    private func cancel() { operation?.cancel(); operation = nil;selectionTask?.cancel();selectionTask = nil;selectionContext = nil;candidates = [];selecting = false;loadingCandidates = false; busy = false }
}
private struct FeaturedArtistHighlight: ViewModifier {
    let active: Bool
    let color: Color
    @ViewBuilder func body(content:Content) -> some View {
        if active { content.foregroundStyle(color) }
        else { content }
    }
}
/// One native text layout preserves kerning, truncation and a hit target per visible name.
struct FeaturedTrackTitle: View {
    let track: SongItemRecord
    let font: Font
    let color: Color
    var pointSize: CGFloat = 14
    var scrollsOnOverflow = false
    let onNavigate: (String?,String)->Void
    var body: some View {
        Group {
            if scrollsOnOverflow {
                ScrollingFeaturedNativeTitle(track:track,color:color,pointSize:pointSize,onNavigate:onNavigate)
            } else {
                FeaturedNativeTitle(track:track,color:color,pointSize:pointSize,onNavigate:onNavigate)
            }
        }
        .frame(height:ceil(pointSize * 1.4))
        .help(track.title + "\n" + ContentRatingMetadata.label(track.contentRating))
    }
}
private struct FeaturedNativeTitle: NSViewRepresentable {
    @Environment(\.sideBPageIsActive) private var pageIsActive
    let track: SongItemRecord
    let color: Color
    let pointSize: CGFloat
    let onNavigate:(String?,String)->Void
    func makeNSView(context:Context) -> NativeTrackActionField {
        let field = NativeTrackActionField(frame:.zero)
        field.isEditable = false; field.isSelectable = false; field.isBezeled = false; field.drawsBackground = false
        field.maximumNumberOfLines = 1; field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        return field
    }
    func updateNSView(_ field:NativeTrackActionField,context:Context) {
        field.setFeaturedVisible(pageIsActive)
        field.font = .systemFont(ofSize:pointSize,weight:pointSize > 20 ? .bold : .semibold)
        field.textColor = NSColor(color)
        field.configureFeatured(track:track,isTitle:true,onNavigate:onNavigate)
        field.prefetchFeatured()
    }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:NativeTrackActionField,context:Context) -> CGSize? {
        CGSize(width:proposal.width ?? nsView.intrinsicContentSize.width,height:ceil(pointSize * 1.4))
    }
    static func dismantleNSView(_ field:NativeTrackActionField,coordinator:()) { field.clearFeatured() }
}
private struct ScrollingFeaturedNativeTitle: NSViewRepresentable {
    @Environment(\.sideBPageIsActive) private var pageIsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let track: SongItemRecord
    let color: Color
    let pointSize: CGFloat
    let onNavigate:(String?,String)->Void
    func makeNSView(context:Context) -> NativePlayerTitleViewport {
        let viewport = NativePlayerTitleViewport(frame:.zero)
        let field = viewport.field
        field.isEditable = false; field.isSelectable = false; field.isBezeled = false; field.drawsBackground = false
        field.maximumNumberOfLines = 1; field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        return viewport
    }
    func updateNSView(_ viewport:NativePlayerTitleViewport,context:Context) {
        let field = viewport.field
        field.setFeaturedVisible(pageIsActive)
        field.font = .systemFont(ofSize:pointSize,weight:pointSize > 20 ? .bold : .semibold)
        field.textColor = NSColor(color)
        field.configureFeatured(track:track,isTitle:true,onNavigate:onNavigate)
        field.prefetchFeatured()
        viewport.configure(identity:track.videoId + "\u{0}" + track.title, enabled:true, reduceMotion:reduceMotion, active:pageIsActive)
    }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:NativePlayerTitleViewport,context:Context) -> CGSize? {
        CGSize(width:proposal.width ?? nsView.field.intrinsicContentSize.width,height:ceil(pointSize * 1.4))
    }
    static func dismantleNSView(_ viewport:NativePlayerTitleViewport,coordinator:()) { viewport.tearDown() }
}
