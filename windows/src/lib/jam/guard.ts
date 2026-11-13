// Jam-aware RPC. Outside a Jam it is the raw RPC. Inside one, transport and queue edits go to the
// Jam (the audio only changes when the new `state` comes back), anything that would start other
// music is held until the user confirms leaving, and shuffle/repeat are inert. Calls made by the
// Jam itself use the raw RPC and never pass through here.
import type { PlayerRpc } from '../player/controller';
import type { PlaybackStateDto, QueueEntryDto } from '../types';
import type { EditsApi } from './edits';
import { jamIdOf, nativeEntry, type JamCore } from './model';
import { identities } from './queueMapping';

export interface PendingCall {
  command: string;
  args: Record<string, unknown> | undefined;
}

export interface GuardApi {
  rpc: PlayerRpc;
  /** The held call, if any; clears it. */
  takePending(): PendingCall | null;
  clearPending(): void;
}

type Args = Record<string, unknown>;

const EXIT_REASONS: Record<string, string> = {
  play_song: 'jam.exit.playOther',
  start_song_radio: 'jam.exit.radio',
  start_source_radio: 'jam.exit.source',
  queue_recommendation_action: 'jam.exit.recommendation'
};

export function createGuard(core: JamCore, edits: EditsApi, hooks: { onPendingChange(reasonKey: string | null): void }): GuardApi {
  let held: PendingCall | null = null;
  const state = () => core.raw<PlaybackStateDto>('get_playback_state');

  /** Sends a transport command; on refusal runs `fallback` (local behaviour) or shows why nothing happened. */
  async function transport(action: string, extra: Args, fallback?: () => Promise<unknown>): Promise<void> {
    const refused = () => {
      if (fallback) { core.toast('jam.notice.localOnly'); void fallback().catch(() => {}); } else core.toast('jam.notice.rejected');
    };
    if (!core.view().canControl) {
      if (fallback) { core.toast('jam.notice.localOnly'); await fallback().catch(() => {}); } else core.toast('jam.notice.noControl');
      return;
    }
    const requestId = core.newId('cmd');
    core.expectResult(requestId, ok => { if (!ok) refused(); });
    if (!await core.send({ type: 'command', action, requestId, ...extra })) {
      core.forgetResult(requestId);
      refused();
    }
  }

  function hold(command: string, args: Args | undefined): void {
    held = { command, args };
    hooks.onPendingChange(EXIT_REASONS[command] ?? 'jam.exit.playOther');
  }

  async function playSong(args: Args): Promise<void> {
    if (args.preserveQueue) {
      // Native ids are opaque: the Jam occurrence comes from `sourceOccurrenceId` in the snapshot.
      const items = core.d.playback?.queue.items ?? [];
      const wanted = (args.queueEntryId as string | null | undefined) ?? items[Number(args.queueCurrentIndex)]?.entryId;
      const jamId = jamIdOf(nativeEntry(core.d.playback, wanted));
      if (jamId) {
        const currentIndex = core.d.playback?.queue.currentIndex ?? -1;
        const target = items.findIndex((entry: QueueEntryDto) => entry.entryId === wanted);
        if (target === currentIndex) return;
        const ids = identities(core.d.track?.uri ?? null, core.d.queue.map(track => track.uri));
        const jamIndex = ids.queue.findIndex(item => item.entryId === jamId);
        if (target === currentIndex + 1 && jamIndex >= 0) {
          // The immediate next row of the app: as many `next` as Jam tracks it skips over (unmatched ones).
          for (let step = 0; step <= jamIndex; step += 1) await transport('next', {});
        } else core.toast('jam.notice.notAvailable');
        return;
      }
    }
    hold('play_song', args);
  }

  const handlers: Record<string, (args: Args) => Promise<void>> = {
    pause_playback: () => transport('pause', {}, async () => {
      core.d.locallyPaused = true;
      await core.raw('pause_playback');
    }),
    resume_playback: async () => {
      if (core.d.locallyPaused) {
        // Local-only pause: the Jam did not pause, so a `resume` command would change nothing.
        core.d.locallyPaused = false;
        core.sync.begin();
        if (!core.d.anchor?.paused) { await core.raw('resume_playback').catch(() => {}); return; }
      }
      await transport('resume', {}, async () => {
        core.d.locallyPaused = false;
        await core.raw('resume_playback');
        core.sync.begin();
      });
    },
    next_track: () => transport('next', {}),
    previous_track: () => transport('previous', {}),
    seek_playback_identified: async args => {
      const seconds = Number(args.seconds);
      if (!Number.isFinite(seconds) || seconds < 0) { await core.raw('seek_playback_identified', args); return; }
      // The Jam's position is the local one minus the user's trim.
      const positionMs = Math.max(0, Math.round(seconds * 1000 - core.view().sync.manualOffsetMs));
      await transport('seek', { positionMs }, async () => {
        core.d.syncHold = true;
        await core.raw('seek_playback_identified', args);
      });
    },
    // Edits wait for the Jam to confirm them (seconds): they run on their own and report by toast.
    remove_queue_entry: async args => {
      const jamId = jamIdOf(nativeEntry(core.d.playback, String(args.entryId ?? '')));
      if (jamId) void edits.removeEntry(jamId); else core.toast('jam.notice.notEditable');
    },
    move_queue_entry: async args => {
      const jamId = jamIdOf(nativeEntry(core.d.playback, String(args.entryId ?? '')));
      const beforeNative = (args.beforeEntryId as string | null | undefined) ?? null;
      const before = beforeNative === null ? null : jamIdOf(nativeEntry(core.d.playback, beforeNative));
      if (jamId && (beforeNative === null || before)) void edits.moveEntry(jamId, before); else core.toast('jam.notice.notEditable');
    },
    enqueue_tracks: async args => {
      const items = (args.items as QueueEntryDto[] | undefined) ?? [];
      const songs = items.map(item => ({ title: item.title, artists: item.artists, album: item.album ?? null, durationSecs: item.duration, videoId: item.videoId }));
      const atEnd = args.position !== 'next';
      void edits.addSongs(songs, atEnd ? { atEnd: true } : { atEnd: false, index: 0, anchored: false });
    },
    play_song: playSong,
    start_song_radio: async args => hold('start_song_radio', args),
    start_source_radio: async args => hold('start_source_radio', args),
    queue_recommendation_action: async args => hold('queue_recommendation_action', args),
    set_shuffle: async () => core.toast('jam.notice.shuffleRepeat'),
    set_repeat: async () => core.toast('jam.notice.shuffleRepeat')
  };

  const rpc = (async (command: string, args?: Args) => {
    const handler = Object.hasOwn(handlers, command) && core.isLive() ? handlers[command] : null;
    if (!handler) return core.raw(command, args);
    // Held and rejected calls leave the audio and queue as they are and answer with the current state.
    await handler(args ?? {});
    return state();
  }) as PlayerRpc;

  return {
    rpc,
    takePending() {
      const call = held;
      held = null;
      return call;
    },
    clearPending() {
      held = null;
    }
  };
}
