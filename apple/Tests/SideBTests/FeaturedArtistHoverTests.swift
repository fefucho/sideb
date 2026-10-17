import AppKit
import Testing
import SideBCore
@testable import SideB

@Test @MainActor func featuredNativeHoverChangesDrawingWithoutChangingHitTargetOrPlaying() throws {
    let field = NativeTrackActionField(frame:NSRect(x:0,y:0,width:400,height:24))
    field.font = .systemFont(ofSize:14)
    field.textColor = .white
    field.maximumNumberOfLines = 1
    field.lineBreakMode = .byTruncatingTail
    let track = SongItemRecord(videoId:"hover",title:"Song (feat. Guest)",artists:"Main",album:nil,duration:nil,thumbnail:nil,artistId:nil,albumId:nil,setVideoId:nil,isVideo:false,isUpload:false,library:nil,artistRuns:[])
    field.configureFeatured(track:track,isTitle:true) { _,_ in }
    let button = try #require(field.subviews.compactMap { $0 as? NativeFeaturedArtistButton }.first)
    var activations = 0
    button.activate = { activations += 1 }
    let originalFrame = button.frame
    func rendered() -> Data? {
        let image = NSImage(size:field.bounds.size)
        image.lockFocus()
        NSColor.clear.setFill();field.bounds.fill()
        field.draw(field.bounds)
        image.unlockFocus()
        return image.tiffRepresentation
    }
    let event = try #require(NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,trackingNumber:0,userData:nil))
    let normal = try #require(rendered())
    let originalText = field.attributedStringValue
    button.mouseEntered(with:event)
    #expect(button.showsLinkHighlight)
    #expect(rendered() != normal)
    let guest = (field.stringValue as NSString).range(of:"Guest")
    let changed = field.attributedStringValue
    #expect((changed.attribute(.foregroundColor,at:guest.location,effectiveRange:nil) as? NSColor) != .white)
    #expect(changed.attribute(.underlineStyle,at:guest.location,effectiveRange:nil) == nil)
    #expect(changed.attribute(.backgroundColor,at:guest.location,effectiveRange:nil) == nil)
    #expect(changed.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor == originalText.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor)
    #expect(button.frame == originalFrame)
    #expect(activations == 0)
    // A regular data refresh while hovered must keep the original resting color.
    field.configureFeatured(track:track,isTitle:true) { _,_ in }
    button.mouseExited(with:event)
    #expect(!button.showsLinkHighlight)
    #expect(rendered() == normal)
    #expect(field.attributedStringValue.isEqual(to:originalText))
    button.mouseEntered(with:event)
    field.stringValue = "Fresh value"
    field.clearFeatured()
    #expect(field.stringValue == "Fresh value")
}

@Test @MainActor func featuredNativeKeyboardFocusHasSameHighlightAsHover() {
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:200,height:80),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false
    let button = NativeFeaturedArtistButton(frame:NSRect(x:10,y:10,width:90,height:20))
    window.contentView?.addSubview(button)
    #expect(window.makeFirstResponder(button))
    #expect(button.isLinkFocused && button.showsLinkHighlight)
    #expect(window.makeFirstResponder(nil))
    #expect(!button.isLinkFocused && !button.showsLinkHighlight)
    window.close()
}
