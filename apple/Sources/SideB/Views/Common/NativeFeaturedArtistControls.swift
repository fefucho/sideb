import AppKit
import SideBCore

/// Separate transparent controls over the original glyphs; clipping never creates invisible hit targets.
final class NativeFeaturedArtistButton: NSButton, PlaybackSpaceControl {
    var creditKey = ""
    var activate: (() -> Void)?
    var menuAction: (() -> NSMenu)?
    var highlightChanged: (() -> Void)?
    private var hoverArea: NSTrackingArea?
    private(set) var isLinkHovered = false
    private(set) var isLinkFocused = false
    var showsLinkHighlight: Bool { isLinkHovered || isLinkFocused }
    func clearHighlight() { isLinkHovered = false; isLinkFocused = false }
    override init(frame: NSRect) {
        super.init(frame:frame); title = ""; isBordered = false; bezelStyle = .regularSquare
        target = self; action = #selector(pressed)
        setAccessibilityRole(.link)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func pressed() { activate?() }
    override func mouseDown(with event:NSEvent) { guard event.clickCount == 1 else { return }; super.mouseDown(with:event) }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.pointingHand) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event:NSEvent) { isLinkHovered = true; highlightChanged?() }
    override func mouseExited(with event:NSEvent) { isLinkHovered = false; highlightChanged?() }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { isLinkFocused = true; highlightChanged?(); refreshPlayerTitleMotion() }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { isLinkFocused = false; highlightChanged?(); refreshPlayerTitleMotion() }
        return accepted
    }
    override func menu(for event:NSEvent) -> NSMenu? { menuAction?() }
    override func accessibilityPerformShowMenu() -> Bool {
        guard let menu = menuAction?() else { return false };menu.popUp(positioning:nil,at:NSPoint(x:0,y:bounds.maxY),in:self);return true
    }
    override func keyDown(with event:NSEvent) { if event.keyCode == 109,event.modifierFlags.contains(.shift) { _ = accessibilityPerformShowMenu();return };if event.keyCode == 36 || event.keyCode == 49 { activate?() } else { super.keyDown(with:event) } }
}

final class NativeFeaturedArtistMenuAction: NSObject {
    let action: () -> Void
    init(_ action:@escaping ()->Void) { self.action = action }
    @objc func activateMenuItem() { action() }
}

@MainActor final class NativeFeaturedArtistOverlay: NSObject, NSPopoverDelegate {
    weak var field: NativeTrackActionField?
    var track: SongItemRecord?
    var onNavigate: ((String?,String)->Void)?
    var credits: [FeaturedCredit] = []
    var buttons: [NativeFeaturedArtistButton] = []
    var lookup: Task<Void,Never>?
    var clickTask: Task<Void,Never>?
    private var configuredScope = -1
    private var configuredLanguage = -1
    private var configuredSuffix = ""
    private var configuredText = ""
    private var isVisible = true
    var identity: UInt64 = 0
    var resolvedIdentity: UInt64 = 0
    var isTitle = false
    var hovered = false
    var pending: [FeaturedCredit]?
    private var normalText: NSAttributedString?
    private var highlightedText: NSAttributedString?
    private var busyPopover: NSPopover?
    private var busyCancel: NativeFeaturedArtistMenuAction?
    private var closingBusy = false
    private var menuActions: [NativeFeaturedArtistMenuAction] = []
    private struct LayoutKey: Equatable {
        let text: String
        let origin: CGRect
        let font: NSFont
        let lineBreakMode: NSLineBreakMode
        let alignment: NSTextAlignment
        let maximumLines: Int
        let flipped: Bool
        let credits: [FeaturedCredit]
        let languageRevision: Int
    }
    private var lastLayout: LayoutKey?
    private(set) var measurementCount = 0
    init(field:NativeTrackActionField) { self.field = field; super.init() }
    func configure(track:SongItemRecord,isTitle:Bool,suffix:String = "",onNavigate:@escaping (String?,String)->Void) {
        self.onNavigate = onNavigate
        let scope = FeaturedArtistResolver.shared.scopeRevision
        if self.track == track, self.isTitle == isTitle, configuredScope == scope,
           configuredLanguage == L10n.revision, configuredSuffix == suffix {
            if let field, field.stringValue != configuredText {
                restoreHighlight()
                field.stringValue = configuredText
            }
            rebuild()
            return
        }
        identity &+= 1
        lookup?.cancel(); lookup = nil; clickTask?.cancel(); clickTask = nil
        closeBusy(); credits = []; pending = nil; resolvedIdentity = 0
        configuredScope = scope
        configuredLanguage = L10n.revision
        configuredSuffix = suffix
        self.track = track; self.isTitle = isTitle
        guard let field else { return }
        restoreHighlight()
        if isTitle {
            configuredText = track.title + suffix
            if field.stringValue != configuredText { field.stringValue = configuredText }
            if credits.isEmpty { credits = FeaturedArtistParser.clauses(track.title) }
        } else {
            let runs = track.displayArtistRuns
            let text = runs.map(\.text).joined() + suffix
            configuredText = text
            if field.stringValue != text { field.stringValue = text }
            credits = []
            var location = 0
            for run in runs {
                let length = (run.text as NSString).length
                if !run.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !["&",",","and","y","/","·","•"].contains(run.text.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()) {
                    credits.append(FeaturedCredit(range:NSRange(location:location,length:length),name:run.text,destinationID:run.id,provenance:run.id == nil ? "unresolved" : "provider"))
                }
                location += length
            }
        }
        rebuild()
    }
    func setHovered(_ value:Bool) {
        guard isVisible else { return }
        hovered = value
        if !value, let pending { credits = pending; self.pending = nil; rebuild() }
        if value { prefetch() }
    }
    func prefetch() {
        guard isVisible, isTitle, lookup == nil, resolvedIdentity != identity, let track else { return }
        let expected = identity
        lookup = Task { @MainActor [weak self] in
            let result = await FeaturedArtistResolver.shared.title(track)
            guard !Task.isCancelled,let self,self.identity == expected else { return }
            if self.hovered { self.pending = result } else { self.credits = result; self.rebuild() }
            self.resolvedIdentity = expected; self.lookup = nil
        }
    }
    func rebuild() {
        guard isVisible, let field else { return }
        defer { (field as? NativeFeaturedLayoutObserver)?.featuredLayoutDidChange() }
        let text = field.stringValue as NSString, font = field.font ?? .systemFont(ofSize:14)
        let origin = field.cell?.titleRect(forBounds:field.bounds) ?? field.bounds
        let key = LayoutKey(text: field.stringValue, origin: origin, font: font,
            lineBreakMode: field.lineBreakMode, alignment: field.alignment,
            maximumLines: field.maximumNumberOfLines, flipped: field.isFlipped,
            credits: credits, languageRevision: L10n.revision)
        guard key != lastLayout else { return }
        lastLayout = key
        guard !credits.isEmpty else {
            restoreHighlight()
            buttons.forEach { $0.removeFromSuperview() }
            buttons = []
            return
        }
        guard origin.width > 0,origin.height > 0 else { buttons.forEach { $0.isHidden = true };return }
        let existing = Dictionary(uniqueKeysWithValues:buttons.map { ($0.creditKey,$0) })
        var nextButtons:[NativeFeaturedArtistButton] = []
        measurementCount += 1
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = field.lineBreakMode; paragraph.alignment = field.alignment
        let storage = NSTextStorage(string:field.stringValue,attributes:[.font:font,.paragraphStyle:paragraph])
        let layout = NSLayoutManager(), container = NSTextContainer(size:origin.size)
        container.lineFragmentPadding = 0; container.maximumNumberOfLines = field.maximumNumberOfLines; container.lineBreakMode = field.lineBreakMode
        layout.addTextContainer(container); storage.addLayoutManager(layout); layout.ensureLayout(for:container)
        let visible = layout.glyphRange(for:container)
        for credit in credits where NSMaxRange(credit.range) <= text.length {
            let glyphs = layout.glyphRange(forCharacterRange:credit.range,actualCharacterRange:nil)
            guard NSIntersectionRange(glyphs,visible) == glyphs,glyphs.length > 0 else { continue }
            var visibleRects:[CGRect] = [], truncated = false
            layout.enumerateLineFragments(forGlyphRange:glyphs) { _,_,_,lineGlyphs,_ in
                let clipped = layout.truncatedGlyphRange(inLineFragmentForGlyphAt:lineGlyphs.location)
                if clipped.location != NSNotFound, NSIntersectionRange(clipped,glyphs).length > 0 { truncated = true; return }
                let intersection = NSIntersectionRange(lineGlyphs,glyphs)
                if intersection.length > 0 { visibleRects.append(layout.boundingRect(forGlyphRange:intersection,in:container)) }
            }
            // A name wrapping across lines stays readable, but does not get a hit region over unrelated glyphs.
            guard !truncated,visibleRects.count == 1,let rect = visibleRects.first,rect.width > 0 else { continue }
            let buttonFrame = CGRect(x:origin.minX+rect.minX,y:field.isFlipped ? origin.minY+rect.minY : origin.maxY-rect.maxY,width:rect.width,height:rect.height)
            guard origin.contains(buttonFrame) else { continue }
            let button = existing[credit.id] ?? NativeFeaturedArtistButton(frame:buttonFrame)
            button.frame = buttonFrame;button.creditKey = credit.id;button.isHidden = false
            button.setAccessibilityLabel(L10n.text("featured.open",args:[credit.name]))
            button.toolTip = L10n.text(credit.provenance == "inferred" ? "featured.suggested" : "featured.open",args:[credit.name])
            button.highlightChanged = { [weak self] in self?.updateHighlight() }
            button.activate = { [weak self] in self?.open(credit) }
            button.menuAction = { [weak self] in self?.menu(credit) ?? NSMenu() }
            if button.superview !== field { field.addSubview(button) };nextButtons.append(button)
        }
        buttons.filter { old in !nextButtons.contains(where: { $0 === old }) }.forEach { $0.removeFromSuperview() }
        buttons = nextButtons
        updateHighlight()
    }

    private func updateHighlight() {
        guard isVisible, let field else { return }
        let active = buttons.filter { !$0.isHidden && $0.showsLinkHighlight }
        guard !active.isEmpty else {
            restoreHighlight()
            return
        }
        if normalText == nil { normalText = field.attributedStringValue }
        guard let normalText else { return }
        let highlighted = NSMutableAttributedString(attributedString:normalText)
        for button in active {
            guard let credit = credits.first(where: { $0.id == button.creditKey }), NSMaxRange(credit.range) <= highlighted.length else { continue }
            let base = (normalText.attribute(.foregroundColor,at:credit.range.location,effectiveRange:nil) as? NSColor) ?? field.textColor ?? .labelColor
            let rgb = base.usingColorSpace(.deviceRGB) ?? .white
            let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
            let color: NSColor = luminance > 0.85 ? .white.withAlphaComponent(0.75) : .labelColor
            highlighted.addAttribute(.foregroundColor,value:color,range:credit.range)
        }
        // Change only the original glyph color. No underline, halo, or extra geometry.
        if !field.attributedStringValue.isEqual(to:highlighted) { field.attributedStringValue = highlighted }
        highlightedText = highlighted
    }

    private func restoreHighlight() {
        // A cell may already have new text/color when it is rebound. Restore only
        // our own last presentation, never overwrite the caller's fresh values.
        if let field, let normalText, let highlightedText, field.attributedStringValue.isEqual(to:highlightedText) {
            field.attributedStringValue = normalText
        }
        normalText = nil
        highlightedText = nil
    }

    static func usesPointerOffset(_ type:NSEvent.EventType?) -> Bool { type == .leftMouseDown || type == .leftMouseUp }
    private func open(_ credit:FeaturedCredit) {
        guard isVisible, let track,let onNavigate else { return };clickTask?.cancel()
        let expected = identity, revision = FeaturedArtistResolver.shared.scopeRevision
        var offset = credit.range.location
        if isTitle,Self.usesPointerOffset(NSApp.currentEvent?.type),let field,let window = field.window {
            let point = field.convert(window.mouseLocationOutsideOfEventStream,from:nil)
            let origin = field.cell?.titleRect(forBounds:field.bounds) ?? field.bounds
            let text = NSTextStorage(string:field.stringValue,attributes:[.font:field.font ?? .systemFont(ofSize:14)])
            let layout = NSLayoutManager(),container = NSTextContainer(size:origin.size)
            container.lineFragmentPadding = 0; container.maximumNumberOfLines = field.maximumNumberOfLines
            layout.addTextContainer(container);text.addLayoutManager(layout)
            let local = NSPoint(x:point.x-origin.minX,y:field.isFlipped ? point.y-origin.minY : origin.maxY-point.y)
            offset = layout.characterIndex(for:local,in:container,fractionOfDistanceBetweenInsertionPoints:nil)
        }
        let titleOffset = isTitle ? offset : nil
        showBusy()
        clickTask = Task { @MainActor [weak self] in
            guard FeaturedArtistResolver.shared.scopeRevision == revision else { return }
            await FeaturedArtistResolver.shared.open(track,name:credit.name,onNavigate:{ [weak self] id,name in guard !Task.isCancelled, let self, self.isVisible, self.identity == expected else { return };self.closeBusy();onNavigate(id,name) },titleOffset:titleOffset)
        }
    }
    private func showBusy() {
        closeBusy()
        guard let field,field.window != nil else { return }
        let controller = NSViewController()
        let stack = NSStackView(); stack.orientation = .horizontal; stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top:10,left:12,bottom:10,right:12)
        let label = NSTextField(labelWithString:L10n.text("featured.searching"))
        let cancel = NSButton(title:L10n.text("common.cancel"),target:nil,action:nil)
        let action = NativeFeaturedArtistMenuAction { [weak self] in self?.clickTask?.cancel();self?.closeBusy() }
        busyCancel = action;cancel.target = action;cancel.action = #selector(NativeFeaturedArtistMenuAction.activateMenuItem)
        stack.addArrangedSubview(label);stack.addArrangedSubview(cancel)
        stack.frame = CGRect(x:0,y:0,width:300,height:44);controller.view = stack
        let popover = NSPopover();popover.contentViewController = controller;popover.behavior = .transient;popover.delegate = self
        busyPopover = popover;popover.show(relativeTo:field.bounds,of:field,preferredEdge:.maxY)
    }
    private func closeBusy() { closingBusy = true;busyPopover?.close();busyPopover = nil;busyCancel = nil;closingBusy = false }
    func popoverWillClose(_ notification:Notification) { if !closingBusy { clickTask?.cancel();busyPopover = nil;busyCancel = nil } }
    private func menu(_ credit:FeaturedCredit) -> NSMenu {
        let menu = NSMenu(); menuActions = []
        let expectedIdentity = identity, expectedRevision = FeaturedArtistResolver.shared.scopeRevision
        func add(_ title:String,_ action:@escaping ()->Void) { let target = NativeFeaturedArtistMenuAction { [weak self] in guard let self,self.identity == expectedIdentity,FeaturedArtistResolver.shared.scopeRevision == expectedRevision else { return };action() }; menuActions.append(target); let item = NSMenuItem(title:title,action:#selector(NativeFeaturedArtistMenuAction.activateMenuItem),keyEquivalent:""); item.target = target; menu.addItem(item) }
        add(L10n.text("featured.open",args:[credit.name])) { [weak self] in self?.open(credit) }
        add(L10n.text("featured.search")) { [weak self] in self?.clickTask?.cancel(); self?.onNavigate?(nil,credit.name) }
        add(L10n.text("featured.change")) { [weak self] in
            guard let self,let track = self.track else { return }
            Task { @MainActor [weak self] in
                let revision = FeaturedArtistResolver.shared.scopeRevision, expected = self?.identity
                let candidates = await FeaturedArtistResolver.shared.candidates(track,name:credit.name)
                guard revision == FeaturedArtistResolver.shared.scopeRevision, let self,self.identity == expected, let field = self.field else { return }
                let picker = NSMenu()
                for candidate in candidates {
                    let target = NativeFeaturedArtistMenuAction { [weak self] in guard let self,self.identity == expected,revision == FeaturedArtistResolver.shared.scopeRevision else { return }; FeaturedArtistResolver.shared.choose(track,name:credit.name,id:candidate.id); self.onNavigate?(candidate.id,credit.name) }
                    self.menuActions.append(target)
                    let item = NSMenuItem(title:"\(candidate.name) · \(candidate.subtitle ?? candidate.id)",action:#selector(NativeFeaturedArtistMenuAction.activateMenuItem),keyEquivalent:"");item.target = target;picker.addItem(item)
                }
                if candidates.isEmpty { picker.addItem(withTitle:L10n.text("featured.noMatches"),action:nil,keyEquivalent:"") }
                picker.popUp(positioning:nil,at:NSPoint(x:0,y:field.bounds.maxY),in:field)
            }
        }
        add(L10n.text("featured.reset")) { [weak self] in guard let track = self?.track else { return }; FeaturedArtistResolver.shared.choose(track,name:credit.name,id:nil) }
        return menu
    }
    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        if visible {
            buttons.forEach { $0.clearHighlight(); $0.isHidden = false }
            rebuild()
            return
        }
        let resolved = resolvedIdentity == identity
        identity &+= 1
        if resolved { resolvedIdentity = identity }
        lookup?.cancel(); lookup = nil
        clickTask?.cancel(); clickTask = nil
        closeBusy(); hovered = false; restoreHighlight()
        buttons.forEach { $0.clearHighlight(); $0.isHidden = true }
        if let pending { credits = pending; self.pending = nil }
    }
    func clear() { restoreHighlight();lookup?.cancel();clickTask?.cancel();closeBusy();lookup = nil;clickTask = nil;identity &+= 1;resolvedIdentity = 0;track = nil;credits = [];pending = nil;lastLayout = nil;buttons.forEach { $0.removeFromSuperview() };buttons = [] }
}
