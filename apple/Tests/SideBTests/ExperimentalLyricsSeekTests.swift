import AppKit
import AVFoundation
import SwiftUI
import Testing
@testable import SideB

@Suite("Letras experimentales: seek y autoridad del reloj")
@MainActor
struct ExperimentalLyricsSeekTests {
    private var document: ExperimentalLyricsDocument {
        .init(provider: "fixture", instrumental: false, lines: [
            .init(startMS: 1000, endMS: 2000, text: "Primera", words: [
                .init(text: "Primera", startMS: 1000, endMS: 2000)
            ]),
            .init(startMS: 10000, endMS: 12000, text: "Segunda", words: [
                .init(text: "Segunda", startMS: 10000, endMS: 12000)
            ])
        ])
    }

    @Test("Positive and negative lyric offsets map to absolute audio seconds without requiring duration")
    func offsetAndUnknownDuration() {
        #expect(ExperimentalLyricsSeekTarget.audioSeconds(lineMS: 10000, offsetMS: 250, duration: 0) == 9.75)
        #expect(ExperimentalLyricsSeekTarget.audioSeconds(lineMS: 10000, offsetMS: -250, duration: .nan) == 10.25)
        #expect(ExperimentalLyricsSeekTarget.audioSeconds(lineMS: 100, offsetMS: 250, duration: 0) == 0)
        #expect(ExperimentalLyricsSeekTarget.audioSeconds(lineMS: 10000, offsetMS: -250, duration: 9) == 9)
        #expect(ExperimentalLyricsSeekTarget.audioSeconds(lineMS: .nan, offsetMS: 0, duration: 0) == nil)
        #expect(ExperimentalLyricsSeekTarget.audioSeconds(lineMS: 1000, offsetMS: .infinity, duration: 0) == nil)
        #expect(ExperimentalLyricsSeekTarget.audioSeconds(lineMS: -1, offsetMS: 0, duration: 0) == nil)
    }

    @Test("A lyric click updates focus once; without a real pending seek the next media sample remains authoritative")
    func previewHasNoInventedHold() {
        let player = AVPlayer()
        let clock = ExperimentalLyricsClock()
        clock.start(player: player, document: document)
        clock.notifySeek(toAudioSeconds: 10)
        #expect(clock.positionMS == 10000)
        #expect(clock.focusIndex == 1)
        #expect(clock.activeWordLineIndices == [1])
        clock.sample()
        #expect(clock.positionMS == 0)
        #expect(clock.focusIndex == 0)
        #expect(clock.activeWordLineIndices.isEmpty)
        clock.notifySeek(toAudioSeconds: .nan)
        #expect(clock.positionMS == 0)
        clock.stop()
    }

    @Test("Real pending seek freezes the preview through paused media samples, then completion returns to measured time")
    func pendingSeekAndCompletion() {
        let id = UUID()
        let player = AVPlayer()
        let clock = ExperimentalLyricsClock()
        clock.start(player: player, document: document, playbackIdentity: id)
        clock.reconcileSeek(.init(revision: 1, playbackID: id, phase: .pending, targetSeconds: 10, mediaSeconds: 0))
        clock.setVisible(true)
        clock.sample()
        #expect(player.timeControlStatus == .paused)
        #expect(clock.positionMS == 10000)
        #expect(clock.focusIndex == 1)
        clock.configure(animateWords: true, offsetMS: 250)
        #expect(clock.positionMS == 10000)
        #expect(clock.activeWordLineIndices == [1])
        clock.reconcileSeek(.init(revision: 2, playbackID: id, phase: .completed, targetSeconds: 10, mediaSeconds: 9.909))
        #expect(clock.positionMS == 9909)
        #expect(clock.focusIndex == 1)
        #expect(clock.activeWordLineIndices == [1]) // The user's +250 ms offset is still applied.
        clock.configure(animateWords: true, offsetMS: 0)
        clock.sample()
        #expect(clock.positionMS == 0)
        #expect(clock.focusIndex == 0)
        #expect(player.rate == 0 && player.currentItem == nil)
        clock.stop()
    }

    @Test("Forward and backward seeks recalculate exact word and wait boundaries, without a post-seek floor")
    func boundariesInBothDirections() {
        let id = UUID()
        let clock = ExperimentalLyricsClock()
        clock.start(player: AVPlayer(), document: document, duration: 20, playbackIdentity: id)
        let times: [Double] = [10, 12, 9.999, 1, 2, 0, 10]
        for (index, seconds) in times.enumerated() {
            clock.reconcileSeek(.init(revision: UInt64(index + 1), playbackID: id, phase: .completed, mediaSeconds: seconds))
            #expect(clock.positionMS == seconds * 1000)
            #expect(clock.focusIndex == document.focusIndex(at: seconds * 1000))
            #expect(clock.activeWordLineIndices == document.activeWordLineIndices(at: seconds * 1000))
            #expect(clock.activeInterludeID == clock.interludes.first { $0.contains(timeMS: seconds * 1000) }?.id)
        }
        clock.stop()
    }

    @Test("Failed, cancelled and superseded seeks release the fixed target; stale revisions or occurrences cannot replace it")
    func cancellationAndOldCallbacks() {
        let id = UUID()
        let clock = ExperimentalLyricsClock()
        let player = AVPlayer()
        clock.start(player: player, document: document, playbackIdentity: id)
        clock.reconcileSeek(.init(revision: 3, playbackID: id, phase: .pending, targetSeconds: 10))
        clock.reconcileSeek(.init(revision: 2, playbackID: id, phase: .completed, mediaSeconds: 1))
        clock.reconcileSeek(.init(revision: 99, playbackID: UUID(), phase: .completed, mediaSeconds: 1))
        clock.reconcileSeek(.init(revision: 99, phase: .completed, mediaSeconds: 1))
        #expect(clock.positionMS == 10000)
        clock.reconcileSeek(.init(revision: 4, playbackID: id, phase: .failed, targetSeconds: 10, mediaSeconds: 1.5))
        #expect(clock.positionMS == 1500)
        #expect(clock.activeWordLineIndices == [0])
        clock.sample()
        #expect(clock.positionMS == 0)
        clock.reconcileSeek(.init(revision: 5, playbackID: id, phase: .pending, targetSeconds: 10))
        clock.reconcileSeek(.init(revision: 6, phase: .cancelled, mediaSeconds: 0))
        #expect(clock.positionMS == 0)
        clock.reconcileSeek(.init(revision: 5, playbackID: id, phase: .completed, mediaSeconds: 10))
        #expect(clock.positionMS == 0)
        clock.stop()
        clock.reconcileSeek(.init(revision: 100, playbackID: id, phase: .pending, targetSeconds: 10))
        clock.notifySeek(toAudioSeconds: 10)
        #expect(clock.positionMS == 0 && clock.focusIndex == nil)
    }

    @Test("A new occurrence ignores old pending callbacks and a same-occurrence refresh preserves a real pending target")
    func lifecycleOwnership() {
        let first = UUID()
        let second = UUID()
        let clock = ExperimentalLyricsClock()
        let player = AVPlayer()
        let pending = AudioPlayerSeekSnapshot(revision: 7, playbackID: first, phase: .pending, targetSeconds: 10)
        clock.start(player: player, document: document, playbackIdentity: first, seekSnapshot: pending)
        #expect(clock.positionMS == 10000)
        clock.start(player: player, document: document, duration: 20, playbackIdentity: first, seekSnapshot: pending)
        #expect(clock.positionMS == 10000 && clock.focusIndex == 1)
        clock.start(player: player, document: document, playbackIdentity: second, seekSnapshot: pending)
        #expect(clock.positionMS == 0 && clock.focusIndex == 0)
        clock.reconcileSeek(.init(revision: 8, playbackID: first, phase: .completed, mediaSeconds: 10))
        #expect(clock.positionMS == 0)
        clock.stop()
    }

    @Test("Paused, buffering, hidden and seek-in-flight states never create an animation pulse")
    func pendingPulsePolicy() {
        for (visible, playing, seeking) in [(true, false, false), (false, true, false), (true, true, true)] {
            #expect(!ExperimentalLyricsClock.shouldPulse(visible: visible, playing: playing,
                animateWords: true, hasChangingWord: true, hasChangingInterlude: true, seeking: seeking))
        }
    }
}

@Suite("Letras experimentales: prioridad del scroll manual")
struct ExperimentalLyricsFollowTests {
    @Test("Manual scroll cancels pending resize and focus requests; a lyric click resumes tracking")
    func clickResumesTracking() throws {
        var state = ExperimentalLyricsFollowState()
        let firstRequest = state.beginRequest()
        let beforeManual = try #require(firstRequest)
        state.userScrolled()
        #expect(!state.canApply(beforeManual))
        #expect(state.beginRequest() == nil)
        state.resume()
        #expect(state.isFollowing)
        let clickRequest = state.beginRequest()
        let clicked = try #require(clickRequest)
        #expect(state.canApply(clicked))
        #expect(!state.canApply(beforeManual))
        state.userScrolled()
        #expect(!state.canApply(clicked))
    }

    @Test("A refresh preserves manual reading; a new occurrence resumes and invalidates old layout requests")
    func refreshAndOccurrence() throws {
        var state = ExperimentalLyricsFollowState()
        state.userScrolled()
        state.documentChanged(newOccurrence: false)
        #expect(!state.isFollowing && state.beginRequest() == nil)
        state.documentChanged(newOccurrence: true)
        #expect(state.isFollowing)
        let oldRequest = state.beginRequest()
        let oldSize = try #require(oldRequest)
        let newRequest = state.beginRequest()
        let newSize = try #require(newRequest)
        #expect(!state.canApply(oldSize) && state.canApply(newSize))
        state.documentChanged(newOccurrence: false)
        #expect(!state.canApply(newSize) && state.isFollowing)
    }
}
