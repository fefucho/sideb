import SwiftUI

/// The Spotify Jam panel: join, participants, current match, version picker, leave and advanced
/// options. Hosted both in the Connections popover and as a fullscreen panel.
struct JamPanelView: View {
    enum Style { case popover, fullscreen }
    var player: PlayerViewModel
    var style: Style = .popover

    @State private var controller = JamSessionController.shared
    /// The Spotify login belongs to the app, not to the Canvas plugin: it works whether Canvas is installed or not.
    @State private var session = SpotifySession.shared
    /// Looked up once: it touches the file system.
    @State private var pluginAvailable = JamProcess.locateExecutable() != nil

    private var access: JamAccess {
        if !pluginAvailable { return .pluginMissing }
        if !session.hasCredential { return .needsLogin(loginFailed: session.loginFailed) }
        return .ready
    }

    var body: some View {
        JamPanelContent(snapshot: JamPanelSnapshot.make(controller: controller, access: access), style: style, actions: actions)
    }

    private var actions: JamPanelActions {
        JamPanelActions(
            join: { link in controller.join(link: link, player: player) },
            cancel: { controller.leave() },
            leave: { controller.leave() },
            choose: { id in if let candidate = controller.candidates.first(where: { $0.id == id }) { controller.choose(candidate) } },
            signIn: { session.signIn(providerName: SpotifySession.displayName) },
            signOut: signOut,
            openDebug: { JamDebugWindow.shared.show(player: player) },
            setNudge: { controller.nudgeMs = $0 },
            setGlobalOffset: { controller.globalOffsetMs = $0 })
    }

    /// Signs out of Spotify for every feature that shares the session; a running Jam ends first.
    private func signOut() {
        controller.leave()
        let session = session
        Task { try? await session.signOut() }
    }
}
