import Foundation
import Testing
@testable import SideB

@MainActor
@Suite("Jam: incoming live invitations")
struct JamInviteTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "JamInviteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, suite)
    }

    private func decodeEvent(_ json: String) throws -> JamEvent {
        try JSONDecoder().decode(JamEvent.self, from: Data(json.utf8))
    }

    @Test("inviteAvailable event decodes into JamInvite with all metadata")
    func decodesInviteAvailableEvent() throws {
        let json = """
        {"type":"inviteAvailable","id":"inv-1","token":"5QaRAjTyChieQ3Z8fdSlqu","link":"https://open.spotify.com/socialsession/5QaRAjTyChieQ3Z8fdSlqu","senderName":"Valentina","senderImageUrl":"https://i.scdn.co/image/abc","sentAtMs":1700000000000,"participantCount":3}
        """
        let event = try decodeEvent(json)
        let invite = try #require(JamInvite(event: event))
        #expect(invite.id == "inv-1")
        #expect(invite.token == "5QaRAjTyChieQ3Z8fdSlqu")
        #expect(invite.link == "https://open.spotify.com/socialsession/5QaRAjTyChieQ3Z8fdSlqu")
        #expect(invite.senderName == "Valentina")
        #expect(invite.senderImageUrl == "https://i.scdn.co/image/abc")
        #expect(invite.sentAtMs == 1700000000000)
        #expect(invite.participantCount == 3)
    }

    @Test("inviteAvailable falls back to token for missing id/link and ignores invalid events")
    func decodesInviteFallbacksAndRejectsInvalid() throws {
        let minimal = try decodeEvent(#"{"type":"inviteAvailable","token":"tok123456789012345","senderName":"  ","senderImageUrl":""}"#)
        let invite = try #require(JamInvite(event: minimal))
        #expect(invite.id == "tok123456789012345")
        #expect(invite.link == "https://open.spotify.com/socialsession/tok123456789012345")
        #expect(invite.senderName == nil)
        #expect(invite.senderImageUrl == nil)

        let expired = try decodeEvent(#"{"type":"inviteExpired","id":"inv-9","token":"tok9"}"#)
        #expect(JamInvite(event: expired) == nil)
        #expect(expired.id == "inv-9")
        #expect(expired.token == "tok9")

        let noToken = try decodeEvent(#"{"type":"inviteAvailable","id":"inv-bad","token":""}"#)
        #expect(JamInvite(event: noToken) == nil)
    }

    @Test("Controller prepends new invites, updates in place, and does not re-pop auto-dismissed banner")
    func deduplicationAndBannerSuppression() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = JamSessionController(userDefaults: defaults)

        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-1","token":"tok1","link":"https://open.spotify.com/socialsession/tok1","senderName":"Ana","participantCount":2}"#))
        #expect(controller.invites.count == 1)
        #expect(controller.bannerInvite?.id == "inv-1")

        // Auto-dismissing the banner keeps the invite in Conexiones.
        controller.dismissBanner(id: "inv-1")
        #expect(controller.bannerInvite == nil)
        #expect(controller.invites.count == 1)

        // Updating the same invite refreshes metadata without duplicating or re-popping the banner.
        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-1","token":"tok1","link":"https://open.spotify.com/socialsession/tok1","senderName":"Ana","participantCount":4}"#))
        #expect(controller.invites.count == 1)
        #expect(controller.invites.first?.participantCount == 4)
        #expect(controller.bannerInvite == nil)

        // A second distinct invite prepends and shows in the banner.
        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-2","token":"tok2","link":"https://open.spotify.com/socialsession/tok2","senderName":"Tomás","participantCount":1}"#))
        #expect(controller.invites.map(\.id) == ["inv-2", "inv-1"])
        #expect(controller.bannerInvite?.id == "inv-2")
    }

    @Test("Controller ignores invites matching the active Jam token while connecting or live")
    func ignoresActiveJamToken() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = JamSessionController(userDefaults: defaults)

        controller.setPhaseForTesting(.connecting, activeJamToken: "activeTok")
        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-same","token":"activeTok","link":"https://open.spotify.com/socialsession/activeTok","senderName":"Ana"}"#))
        #expect(controller.invites.isEmpty)
        #expect(controller.bannerInvite == nil)

        controller.setPhaseForTesting(.live, activeJamToken: "activeTok")
        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-same","token":"activeTok","link":"https://open.spotify.com/socialsession/activeTok","senderName":"Ana"}"#))
        #expect(controller.invites.isEmpty)

        // Another Jam's invite is still accepted while live in a different Jam.
        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-other","token":"otherTok","link":"https://open.spotify.com/socialsession/otherTok","senderName":"Mei"}"#))
        #expect(controller.invites.map(\.id) == ["inv-other"])
    }

    @Test("Dismissing an invite removes it, persists across relaunch, and caps stored IDs at 50")
    func dismissalPersistenceAndCap() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        do {
            let controller = JamSessionController(userDefaults: defaults)
            for index in 1...55 {
                let id = "inv-\(index)"
                let token = "tok-\(index)"
                controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"\#(id)","token":"\#(token)","link":"https://open.spotify.com/socialsession/\#(token)"}"#))
                controller.dismissInvite(id: id)
            }
            #expect(controller.invites.isEmpty)
            #expect(controller.bannerInvite == nil)
            let saved = defaults.stringArray(forKey: "sideb.jam.dismissedInvites.v1") ?? []
            #expect(saved.count == 50)
            #expect(saved.first == "inv-6")
            #expect(saved.last == "inv-55")
        }

        // Relaunching with the same UserDefaults ignores the persisted last 50 dismissed IDs.
        let relaunched = JamSessionController(userDefaults: defaults)
        relaunched.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-55","token":"tok-55","link":"https://open.spotify.com/socialsession/tok-55"}"#))
        #expect(relaunched.invites.isEmpty)
        #expect(relaunched.bannerInvite == nil)

        // Evicted oldest ID (inv-1) is no longer blocked.
        relaunched.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-1","token":"tok-1","link":"https://open.spotify.com/socialsession/tok-1"}"#))
        #expect(relaunched.invites.map(\.id) == ["inv-1"])
        #expect(relaunched.bannerInvite?.id == "inv-1")
    }

    @Test("inviteExpired removes matching invite from invites and bannerInvite")
    func expirationClearsInvitesAndBanner() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = JamSessionController(userDefaults: defaults)

        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-1","token":"tok1","link":"https://open.spotify.com/socialsession/tok1","senderName":"Ana"}"#))
        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-2","token":"tok2","link":"https://open.spotify.com/socialsession/tok2","senderName":"Bruno"}"#))
        #expect(controller.bannerInvite?.id == "inv-2")

        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteExpired","id":"inv-2","token":"tok2"}"#))
        #expect(controller.invites.map(\.id) == ["inv-1"])
        #expect(controller.bannerInvite == nil)

        // Expiring by token alone also works.
        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteExpired","token":"tok1"}"#))
        #expect(controller.invites.isEmpty)
    }

    @Test("joinInvite clears banner and invite entry before starting join")
    func joinInviteClearsBannerAndEntry() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = JamSessionController(userDefaults: defaults)
        let player = PlayerViewModel(rustCore: nil)
        defer { player.audioService.stop() }

        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-1","token":"tok1","link":"https://open.spotify.com/socialsession/tok1","senderName":"Ana"}"#))
        let invite = try #require(controller.invites.first)
        controller.player = player
        controller.joinInvite(invite)

        #expect(controller.bannerInvite == nil)
        #expect(controller.invites.isEmpty)

        // Also verify direct joinInvite(_:player:) overload.
        controller.setPhaseForTesting(.idle, activeJamToken: nil)
        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-2","token":"tok2","link":"https://open.spotify.com/socialsession/tok2","senderName":"Tomás"}"#))
        let invite2 = try #require(controller.invites.first)
        controller.joinInvite(invite2, player: player)
        #expect(controller.bannerInvite == nil)
        #expect(controller.invites.isEmpty)
    }

    @Test("ConnectionsJamState populates pending invite count and host when not live")
    func connectionsStatePendingInvites() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = JamSessionController(userDefaults: defaults)

        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-1","token":"tok1","link":"https://open.spotify.com/socialsession/tok1","senderName":"Valentina","participantCount":3}"#))
        let state = ConnectionsJamState.current(controller)
        #expect(!state.isLive)
        #expect(state.pendingInviteCount == 1)
        #expect(state.latestInviteHostName == "Valentina")
        #expect(state.buttonHelpText == L10n.text("connections.inviteHelp", args: ["Valentina"]))
        #expect(state.buttonAccessibilityLabelText == L10n.text("connections.inviteHelp", args: ["Valentina"]))

        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-2","token":"tok2","link":"https://open.spotify.com/socialsession/tok2"}"#))
        let unknownHostState = ConnectionsJamState.current(controller)
        #expect(unknownHostState.pendingInviteCount == 2)
        #expect(unknownHostState.latestInviteHostName == nil)
        #expect(unknownHostState.buttonHelpText == L10n.text("connections.inviteHelpUnknown"))
        #expect(unknownHostState.buttonAccessibilityLabelText == L10n.text("connections.inviteHelpUnknown"))

        // When live, pending invite count is omitted from the bar state.
        controller.setPhaseForTesting(.live, activeJamToken: "liveTok")
        let liveState = ConnectionsJamState.current(controller)
        #expect(liveState.isLive)
        #expect(liveState.pendingInviteCount == 0)
        #expect(liveState.latestInviteHostName == nil)
    }

    @Test("JamPanelSnapshot maps controller invites when stage is join")
    func jamPanelSnapshotMapsInvites() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = JamSessionController(userDefaults: defaults)

        controller.handleWatchEvent(try decodeEvent(#"{"type":"inviteAvailable","id":"inv-1","token":"tok1","link":"https://open.spotify.com/socialsession/tok1","senderName":"Joaquín","senderImageUrl":"https://i.scdn.co/image/123","participantCount":2}"#))
        let snapshot = JamPanelSnapshot.make(controller: controller, access: .ready)
        #expect(snapshot.stage == .join)
        #expect(snapshot.invites.count == 1)
        #expect(snapshot.invites[0].id == "inv-1")
        #expect(snapshot.invites[0].token == "tok1")
        #expect(snapshot.invites[0].link == "https://open.spotify.com/socialsession/tok1")
        #expect(snapshot.invites[0].senderDisplayName == "Joaquín")
        #expect(snapshot.invites[0].senderImageURL == URL(string: "https://i.scdn.co/image/123"))
        #expect(snapshot.invites[0].participantCount == 2)
    }
}
