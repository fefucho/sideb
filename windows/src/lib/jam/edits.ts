// Queue edits made from Side B, sent to the Jam (JamSessionController+Edits.swift). Nothing here
// changes the local queue: Spotify only acknowledges a request, so the change shows up when the
// next Jam state brings it back, and a request whose effect does not arrive in time is reported
// as not applied.
import type { JamCore } from './model';
import { editCommand, editIsSatisfied, editIsValid, identities, JamQueueMapping, type JamQueueEdit } from './queueMapping';

/** How long a command may take to show up in the Jam's state. */
const CONFIRMATION_MS = 3000;
const RESOLVE_MS = 8000;

export type EditOutcome = 'confirmed' | 'timedOut' | { failed: string };

export interface SongInfo {
  title: string;
  artists: string;
  album?: string | null;
  durationSecs?: number | null;
  videoId?: string | null;
}

export interface EditsApi {
  /** Called with every new Jam state: did the waiting edit show up? */
  onState(): void;
  onResolved(requestId: string, uri: string | null): void;
  removeAt(index: number): Promise<void>;
  moveTo(from: number, to: number): Promise<void>;
  removeEntry(entryId: string): Promise<void>;
  moveEntry(entryId: string, beforeEntryId: string | null): Promise<void>;
  /** Adds songs to the Jam: at the end, or inserted from `index`. Resolves with how many were applied. */
  addSongs(songs: SongInfo[], where: { atEnd: true } | { atEnd: false; index: number; anchored: boolean }): Promise<number>;
  stop(): void;
}

interface PendingEdit {
  requestId: string;
  edit: JamQueueEdit;
  old: string[];
  timer: unknown;
  resolve: (outcome: EditOutcome) => void;
}

export function createEdits(core: JamCore): EditsApi {
  let pending: PendingEdit | null = null;
  let claimed = false;
  const resolving = new Map<string, { resolve: (uri: string | null) => void; timer: unknown }>();
  const known = new Map<string, string>();

  const queueUris = () => core.d.queue.map(track => track.uri);

  function finish(outcome: EditOutcome, requestId?: string): void {
    const edit = pending;
    if (!edit || (requestId !== undefined && edit.requestId !== requestId)) return;
    pending = null;
    core.sched.clearTimeout(edit.timer);
    core.forgetResult(edit.requestId);
    edit.resolve(outcome);
  }

  async function perform(edit: JamQueueEdit): Promise<EditOutcome> {
    const old = queueUris();
    if (!core.isLive()) return { failed: 'jam.notice.notLive' };
    if (!editIsValid(edit, old)) return { failed: 'jam.notice.notApplied' };
    const requestId = core.newId('edit');
    const outcome = new Promise<EditOutcome>(resolve => {
      pending = { requestId, edit, old, resolve, timer: core.sched.setTimeout(() => finish('timedOut', requestId), CONFIRMATION_MS) };
    });
    core.expectResult(requestId, (ok, detail) => {
      if (!ok) finish({ failed: detail === 'stale' ? 'jam.notice.stale' : 'jam.notice.rejected' }, requestId);
    });
    core.note(`queue: ${edit.action} (revision ${core.d.queueRevision ?? '?'})`);
    void core.send(editCommand(edit, core.d.queueRevision, requestId)).then(sent => { if (!sent) finish({ failed: 'jam.notice.notApplied' }, requestId); });
    return outcome;
  }

  /** Common preconditions; claims the single edit slot (a second edit would index a queue that is about to change). */
  function claim(): boolean {
    if (!core.isLive()) { core.toast('jam.notice.notLive'); return false; }
    if (!core.view().canControl) { core.toast('jam.notice.noControl'); return false; }
    if (claimed || pending) { core.toast('jam.notice.busy'); return false; }
    claimed = true;
    return true;
  }

  function report(outcome: EditOutcome): void {
    if (!core.isLive()) return;
    if (outcome === 'timedOut') core.toast('jam.notice.notApplied');
    else if (outcome !== 'confirmed') core.toast(outcome.failed);
  }

  async function run(edit: JamQueueEdit): Promise<void> {
    if (!claim()) return;
    try { report(await perform(edit)); } finally { claimed = false; }
  }

  /** Spotify URI of a YouTube Music song: known from a Jam match, cached, or asked of the plugin. */
  async function spotifyEquivalent(song: SongInfo): Promise<string | null> {
    if (song.videoId) {
      for (const [uri, state] of core.d.matches) if (state.kind === 'matched' && state.match.view.videoId === song.videoId) return uri;
    }
    const cacheKey = `${song.title}|${song.artists}`;
    const cached = known.get(cacheKey);
    if (cached) return cached;
    const requestId = core.newId('resolve');
    // Many rows carry no duration: say so instead of sending 0.
    const durationMs = song.durationSecs && song.durationSecs > 0 ? Math.round(song.durationSecs * 1000) : null;
    const uri = await new Promise<string | null>(resolve => {
      const timer = core.sched.setTimeout(() => { if (resolving.delete(requestId)) { core.note('resolve: plugin did not answer'); resolve(null); } }, RESOLVE_MS);
      resolving.set(requestId, { resolve, timer });
      void core.send({ type: 'resolve', requestId, title: song.title, artist: song.artists, album: song.album ?? null, durationMs })
        .then(sent => { if (!sent && resolving.delete(requestId)) { core.sched.clearTimeout(timer); resolve(null); } });
    });
    if (uri) known.set(cacheKey, uri);
    return uri;
  }

  return {
    onState() {
      if (pending && editIsSatisfied(pending.edit, pending.old, queueUris())) finish('confirmed');
    },
    onResolved(requestId, uri) {
      const waiter = resolving.get(requestId);
      if (!waiter) return;
      resolving.delete(requestId);
      core.sched.clearTimeout(waiter.timer);
      if (!uri) core.note('resolve: no confident Spotify match');
      waiter.resolve(uri);
    },
    removeAt: index => run({ action: 'remove', index }),
    moveTo: (from, to) => run({ action: 'move', from, to }),
    async removeEntry(entryId) {
      const ids = identities(core.d.track?.uri ?? null, queueUris());
      const index = ids.queue.findIndex(item => item.entryId === entryId);
      if (ids.current?.entryId === entryId) { core.toast('jam.notice.removeCurrent'); return; }
      if (index < 0) { core.toast('jam.notice.notEditable'); return; }
      await run({ action: 'remove', index });
    },
    async moveEntry(entryId, beforeEntryId) {
      const ids = identities(core.d.track?.uri ?? null, queueUris());
      const from = ids.queue.findIndex(item => item.entryId === entryId);
      const before = beforeEntryId === null ? null : ids.queue.findIndex(item => item.entryId === beforeEntryId);
      if (from < 0 || before === -1) { core.toast('jam.notice.notEditable'); return; }
      const mapping = new JamQueueMapping(core.d.queue.map(track => core.matching.matchOf(track.uri) !== null));
      const move = mapping.moveBefore(from, before);
      if (move) await run({ action: 'move', ...move });
    },
    async addSongs(songs, where) {
      if (!claim()) return 0;
      const token = core.d.token;
      try {
        const found: { uri: string; title: string }[] = [];
        const missing: string[] = [];
        for (const song of songs) {
          const uri = await spotifyEquivalent(song);
          if (!core.isCurrent(token)) return 0;
          if (uri) found.push({ uri, title: song.title }); else missing.push(song.title);
        }
        if (!found.length) {
          if (missing.length === 1) core.toast('jam.notice.noSpotifyMatch', { title: missing[0] });
          else core.toast('jam.notice.noSpotifyMatchMany', { count: String(missing.length) });
          return 0;
        }
        // Re-anchor to where the neighbour is now: the queue may have moved while resolving.
        let base = 0;
        if (!where.atEnd) {
          const neighbour = where.anchored ? core.d.queue[where.index]?.uri : undefined;
          base = neighbour === undefined ? Math.min(where.index, core.d.queue.length) : core.d.queue.findIndex(track => track.uri === neighbour);
          if (base < 0) base = Math.min(where.index, core.d.queue.length);
        }
        let done = 0;
        for (const [offset, item] of found.entries()) {
          const edit: JamQueueEdit = where.atEnd ? { action: 'add', uri: item.uri } : { action: 'insert', uri: item.uri, index: base + offset };
          const outcome = await perform(edit);
          if (outcome !== 'confirmed') { report(outcome); return done; }
          done += 1;
        }
        if (missing.length) core.toast('jam.notice.partialAdded', { done: String(done), total: String(songs.length) });
        else if (found.length === 1) core.toast(where.atEnd ? 'jam.notice.added' : 'jam.notice.inserted', { title: found[0].title });
        else core.toast(where.atEnd ? 'jam.notice.addedMany' : 'jam.notice.insertedMany', { count: String(found.length) });
        return done;
      } finally {
        claimed = false;
      }
    },
    stop() {
      finish({ failed: 'jam.notice.notLive' });
      for (const [, waiter] of resolving) { core.sched.clearTimeout(waiter.timer); waiter.resolve(null); }
      resolving.clear();
      claimed = false;
    }
  };
}
