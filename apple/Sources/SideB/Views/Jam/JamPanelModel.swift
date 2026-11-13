import Foundation
import SideBCore

/// Plain-value picture of what the Jam panel shows. Views render this, never the controller, so
/// every state can be drawn from fixtures. Built on the main actor from `JamSessionController`.
struct JamPanelMember: Equatable, Identifiable {
    let id: Int
    let name: String?
    let imageURL: URL?
    let isHost: Bool
    let isMe: Bool
}

struct JamPanelTrack: Equatable {
    let title: String
    let artists: String
    let duration: String?
}

struct JamPanelVersion: Equatable, Identifiable {
    let id: String
    let title: String
    let artists: String
    let duration: String?
    let thumbnailURL: URL?
    let isVideo: Bool
    /// YouTube Music duration minus Spotify duration, in seconds.
    let durationDelta: Double?

    /// Catalog durations are whole seconds, so only a clear gap is worth a warning.
    var warnsAboutDuration: Bool { abs(durationDelta ?? 0) >= 2 }
}

enum JamSyncStatus: Equatable {
    case synced, adjusting, paused, hostInactive, searching, noMatch, waiting
}

/// Why a join failed: host-side reasons plus the plugin's own error codes.
enum JamFailureKind: String, CaseIterable {
    case pluginMissing, noSession, startFailed, authRequired, invalidLink, unavailable
    case network, notAllowed, jamNotFound, rateLimited, rejected, unsupported, unknown

    init(reason: String) { self = JamFailureKind(rawValue: reason) ?? .unknown }
    var messageKey: String { "jam.failure.\(rawValue)" }
    /// Failures the Spotify sign-in can fix.
    var needsSignIn: Bool { self == .noSession || self == .authRequired }
}

enum JamEndedKind: String, CaseIterable {
    case host, removed, connection, interrupted

    init(reason: String) {
        if reason == "CONNECTION_LOST" { self = .connection }
        else if reason.contains("KICKED") || reason.contains("REMOVED_YOU") { self = .removed }
        else if reason.contains("DELETED") || reason.contains("ENDED") { self = .host }
        else { self = .interrupted }
    }
    var messageKey: String { "jam.ended.reason.\(rawValue)" }
}

/// Whether a Jam can be started from here.
enum JamAccess: Equatable {
    case ready
    /// No Spotify session. The sign-in is the app's own (independent of the Canvas plugin); `loginFailed`
    /// is set when the last login ended without a usable session.
    case needsLogin(loginFailed: Bool)
    case pluginMissing
}

struct JamPanelInvite: Equatable, Identifiable {
    let id: String
    let token: String
    let link: String
    let senderName: String?
    let senderImageURL: URL?
    let participantCount: Int?

    var senderDisplayName: String? {
        guard let senderName, !senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return senderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct JamPanelSnapshot: Equatable {
    enum Stage: Equatable { case join, connecting, live }

    var stage: Stage = .join
    var access: JamAccess = .ready
    var failure: JamFailureKind?
    var ended: JamEndedKind?
    var invites: [JamPanelInvite] = []
    var members: [JamPanelMember] = []
    var hostName: String?
    var canControl = true
    var spotify: JamPanelTrack?
    var version: JamPanelVersion?
    var candidates: [JamPanelVersion] = []
    var status: JamSyncStatus = .waiting
    var nudgeMs: Double = 0
    var globalOffsetMs: Double = 0

    var hostDisplayName: String? {
        guard let hostName, !hostName.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return hostName
    }

    @MainActor
    static func make(controller: JamSessionController, access: JamAccess) -> JamPanelSnapshot {
        var snapshot = JamPanelSnapshot()
        snapshot.access = access
        snapshot.globalOffsetMs = controller.globalOffsetMs
        switch controller.phase {
        case .idle: break
        case .connecting: snapshot.stage = .connecting
        case .ended(let reason): snapshot.ended = JamEndedKind(reason: reason)
        case .failed(let reason): snapshot.failure = JamFailureKind(reason: reason)
        case .live:
            snapshot.stage = .live
            snapshot.members = controller.members.enumerated().map { index, member in
                JamPanelMember(id: index, name: member.name, imageURL: member.imageUrl.flatMap(URL.init(string:)),
                               isHost: member.isHost, isMe: member.isMe)
            }
            snapshot.hostName = controller.hostName
            snapshot.canControl = controller.canControl
            snapshot.spotify = controller.spotifyTrack.map {
                JamPanelTrack(title: $0.displayTitle, artists: $0.displayArtists, duration: $0.durationMs.map { Self.clock($0 / 1000) })
            }
            snapshot.version = controller.matched.map(Self.version)
            snapshot.candidates = controller.candidates.map(Self.version)
            snapshot.nudgeMs = controller.nudgeMs
            if controller.notice == "NO_HOST_ACTIVE_DEVICE" { snapshot.status = .hostInactive }
            else if controller.spotifyTrack == nil { snapshot.status = .waiting }
            else if controller.matched == nil { snapshot.status = controller.candidates.isEmpty ? .searching : .noMatch }
            else if controller.playback?.paused == true { snapshot.status = .paused }
            else if controller.isAdjusting { snapshot.status = .adjusting }
            else { snapshot.status = .synced }
        }
        if snapshot.stage == .join {
            snapshot.invites = controller.invites.map {
                JamPanelInvite(
                    id: $0.id,
                    token: $0.token,
                    link: $0.link,
                    senderName: $0.senderName,
                    senderImageURL: $0.senderImageUrl.flatMap(URL.init(string:)),
                    participantCount: $0.participantCount
                )
            }
        }
        return snapshot
    }

    private static func version(_ candidate: JamMatcher.Candidate) -> JamPanelVersion {
        JamPanelVersion(id: candidate.id, title: candidate.song.title, artists: candidate.song.artists,
                        duration: candidate.song.duration, thumbnailURL: candidate.song.thumbnail.flatMap(URL.init(string:)),
                        isVideo: candidate.song.isVideo, durationDelta: candidate.durationDelta)
    }

    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
