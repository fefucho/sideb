import AppKit
import SwiftUI
import Testing
@testable import SideB

/// Throwaway visual harness: writes one PNG per Jam panel state and appearance when
/// `JAM_UI_RENDER_DIR` is set. Without the variable it does nothing.
@MainActor
@Test func jamPanelRendersStates() throws {
    guard let dir = ProcessInfo.processInfo.environment["JAM_UI_RENDER_DIR"] else { return }
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    let members = [
        JamPanelMember(id: 0, name: "Valentina Rodríguez-Castellanos", imageURL: nil, isHost: true, isMe: false),
        JamPanelMember(id: 1, name: "Tomás", imageURL: nil, isHost: false, isMe: true),
        JamPanelMember(id: 2, name: "Joaquín", imageURL: nil, isHost: false, isMe: false),
        JamPanelMember(id: 3, name: "Mei", imageURL: nil, isHost: false, isMe: false),
        JamPanelMember(id: 4, name: "Ana", imageURL: nil, isHost: false, isMe: false),
        JamPanelMember(id: 5, name: "Bruno", imageURL: nil, isHost: false, isMe: false),
        JamPanelMember(id: 6, name: nil, imageURL: nil, isHost: false, isMe: false)
    ]
    let version = JamPanelVersion(id: "a", title: "Blinding Lights", artists: "The Weeknd", duration: "3:20", thumbnailURL: nil, isVideo: false, durationDelta: 0)
    let candidates = [
        version,
        JamPanelVersion(id: "b", title: "Blinding Lights (Official Video)", artists: "The Weeknd", duration: "4:22", thumbnailURL: nil, isVideo: true, durationDelta: 62),
        JamPanelVersion(id: "c", title: "Blinding Lights - Radio Edit with a very long title that must truncate", artists: "The Weeknd, Another Artist, Third Artist", duration: "3:03", thumbnailURL: nil, isVideo: false, durationDelta: -17)
    ]
    var live = JamPanelSnapshot()
    live.stage = .live
    live.members = members
    live.hostName = members[0].name
    live.spotify = JamPanelTrack(title: "Blinding Lights", artists: "The Weeknd", duration: "3:20")
    live.version = version
    live.candidates = candidates
    live.status = .synced

    var long = live
    long.spotify = JamPanelTrack(title: "Una canción con un título extraordinariamente largo que no cabe", artists: "Artista Uno, Artista Dos, Artista Tres, Artista Cuatro", duration: "10:02")
    long.version = JamPanelVersion(id: "z", title: "Una canción con un título extraordinariamente largo que no cabe (Live)", artists: "Artista Uno, Artista Dos, Artista Tres", duration: "11:40", thumbnailURL: nil, isVideo: true, durationDelta: 98)
    long.status = .adjusting
    var short = live; short.members = Array(members.prefix(2)); short.hostName = "Valentina"
    var noMatch = live; noMatch.version = nil; noMatch.status = .noMatch
    var searching = live; searching.version = nil; searching.candidates = []; searching.status = .searching
    var waiting = live; waiting.spotify = nil; waiting.version = nil; waiting.candidates = []; waiting.status = .waiting
    var noControl = live; noControl.canControl = false; noControl.status = .paused
    var inactive = live; inactive.status = .hostInactive
    var join = JamPanelSnapshot()
    var failed = join; failed.failure = .jamNotFound
    var noSession = join; noSession.access = .needsLogin(loginFailed: false); noSession.failure = .noSession
    var noSignIn = join; noSignIn.access = .needsLogin(loginFailed: true)
    var noPlugin = join; noPlugin.access = .pluginMissing
    var ended = join; ended.ended = .host
    var connecting = join; connecting.stage = .connecting
    var tuned = live; tuned.nudgeMs = 20; tuned.globalOffsetMs = -150
    join.globalOffsetMs = 0

    func states(_ s: JamPanelSnapshot, style: JamPanelView.Style = .popover, link: String = "", versions: Bool = false, sync: Bool = false) -> JamPanelContent {
        JamPanelContent(snapshot: s, style: style, link: link, showVersions: versions, showSync: sync)
    }
    let popover: [(String, JamPanelContent)] = [
        ("join", states(join)),
        ("join-link", states(join, link: "https://open.spotify.com/socialsession/AbCdEfGhIjKl123?si=xyz")),
        ("join-badlink", states(join, link: "hola esto no es un link")),
        ("join-failed", states(failed, link: "https://open.spotify.com/socialsession/Abc")),
        ("signin", states(noSession)),
        ("signin-failed", states(noSignIn)),
        ("plugin-missing", states(noPlugin)),
        ("ended", states(ended)),
        ("connecting", states(connecting)),
        ("live", states(live)),
        ("live-versions", states(live, versions: true)),
        ("live-sync", states(tuned, sync: true)),
        ("live-long", states(long)),
        ("live-two", states(short)),
        ("live-nomatch", states(noMatch, versions: true)),
        ("live-searching", states(searching)),
        ("live-waiting", states(waiting)),
        ("live-nocontrol", states(noControl)),
        ("live-inactive", states(inactive)),
        ("idle-sync", states(join, sync: true))
    ]
    let fullscreen: [(String, JamPanelContent)] = [
        ("fs-join", states(join, style: .fullscreen, link: "https://open.spotify.com/socialsession/AbCdEf")),
        ("fs-live", states(live, style: .fullscreen, versions: true)),
        ("fs-nocontrol", states(noControl, style: .fullscreen))
    ]

    for dark in [false, true] {
        for (name, view) in popover {
            try render(view, width: 340, dark: dark, fullscreen: false, to: "\(dir)/\(name)-\(dark ? "dark" : "light").png")
        }
    }
    for (name, view) in fullscreen {
        try render(view, width: 420, dark: true, fullscreen: true, to: "\(dir)/\(name).png")
    }
    let pill = JamBadgeContent(hostName: members[0].name, members: members, size: .regular, onTap: {})
    let compact = JamBadgeContent(hostName: "Valentina", members: Array(members.prefix(3)), size: .compact, onTap: {})
    let toasts = VStack(alignment: .leading, spacing: 12) {
        pill; compact
        JamToastView(message: JamActionMessage(key: "jam.action.added", args: ["Blinding Lights"]))
        JamToastView(message: JamActionMessage(key: "jam.action.stale", args: []))
        JamToastView(message: JamActionMessage(key: "jam.action.shuffleRepeatInert", args: []))
    }.padding(20)
    try render(toasts, width: 460, dark: true, fullscreen: true, to: "\(dir)/pills-toasts.png")
}

@MainActor
private func render<V: View>(_ view: V, width: CGFloat, dark: Bool, fullscreen: Bool, to path: String) throws {
    let backdrop: AnyView
    if fullscreen {
        backdrop = AnyView(ZStack {
            LinearGradient(colors: [Color(red: 0.42, green: 0.16, blue: 0.20), Color(red: 0.08, green: 0.07, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
            view
        })
    } else {
        backdrop = AnyView(view.background(Color(nsColor: .windowBackgroundColor)))
    }
    let host = NSHostingView(rootView: backdrop.environment(\.colorScheme, dark ? .dark : .light))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = NSRect(x: 0, y: 0, width: width, height: 2000)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = host.appearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    let height = ceil(host.fittingSize.height)
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    host.layoutSubtreeIfNeeded()
    // Give async images/menus a moment to settle.
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    rep.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: rep)
    try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
}
