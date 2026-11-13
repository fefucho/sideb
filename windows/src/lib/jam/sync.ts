// Position matching for the Jam mirror (JamSessionController+Sync.swift): a short correction
// window after a real change, then the audio is left alone. Decisions live in `JamSyncEngine`;
// this file measures with `jam_clock`, applies the engine's action and reports.
import { jamIdOf, livePositionSeconds, nativeEntry, rpcCode, type JamCore, type SyncApi } from './model';
import { JamSyncEngine, summaryText, type SyncAction } from './syncEngine';
import { JAM_QUEUE_SOURCE_KIND, type JamClock, type JamSyncStatus } from './types';

const ADJUSTING_INTERVAL_MS = 100;
const LOCKED_INTERVAL_MS = 250;
const PAUSED_INTERVAL_MS = 500;
/** Minimum gap between pause/resume calls the sync itself issues. */
const TRANSPORT_COOLDOWN_MS = 1000;
/** The player stayed on another track this long while the Jam is elsewhere: go silent. */
const MISMATCH_SILENCE_MS = 4000;
/** A paused target is reached by seeking; give up after this many tries. */
const PAUSED_SEEK_TRIES = 3;
const PAUSED_TOLERANCE_S = 0.05;
/** Offset updates reach the view at most this often. */
const PUBLISH_INTERVAL_MS = 500;

export function createSync(core: JamCore): SyncApi {
  const engine = new JamSyncEngine();
  let timer: unknown = null;
  let running = false;
  let inTick = false;
  let lastTransport = -Infinity;
  let lastSeekAt = -Infinity;
  let pausedSeekTries = 0;
  let mismatchSince: number | null = null;
  let lastPublish = -Infinity;
  let lockStatus: JamSyncStatus = 'locked';

  function setStatus(status: JamSyncStatus, offsetMs: number | null, force = false): void {
    const changed = status !== core.d.syncStatus;
    core.d.syncStatus = status;
    core.d.offsetMs = offsetMs;
    const now = core.now();
    if (!changed && !force && now - lastPublish < PUBLISH_INTERVAL_MS) return;
    lastPublish = now;
    core.patch({ sync: { ...core.view().sync, status, offsetMs: offsetMs === null ? null : Math.round(offsetMs) } });
  }

  function begin(): void {
    core.d.syncHold = false;
    engine.begin();
    pausedSeekTries = 0;
    setStatus('adjusting', core.d.offsetMs, true);
  }

  function transportReady(): boolean {
    const now = core.now();
    if (now - lastTransport < TRANSPORT_COOLDOWN_MS) return false;
    lastTransport = now;
    return true;
  }

  function pauseLocal(): void {
    if (core.d.playback && !core.d.playback.isPlaying) return;
    if (!transportReady()) return;
    void core.raw('pause_playback').catch(() => {});
  }

  /**
   * The native entry ids are opaque (fresh on every load), so "is the player on our track" comes
   * from the video plus the snapshot's `sourceOccurrenceId`. A snapshot that does not know the
   * clock's entry yet (it lags right after an end-of-file advance) is trusted when the video matches.
   */
  function playerIsOnJamEntry(clock: JamClock, videoId: string): boolean {
    if (clock.videoId !== videoId) return false;
    const playback = core.d.playback;
    if (!playback) return true;
    const known = nativeEntry(playback, clock.entryId);
    if (known) return playback.queue.source?.kind === JAM_QUEUE_SOURCE_KIND && jamIdOf(known) !== null;
    return true;
  }

  function manualOffsetSeconds(): number {
    return core.view().sync.manualOffsetMs / 1000;
  }

  async function applySeek(clock: JamClock, seconds: number): Promise<void> {
    lastSeekAt = core.now();
    if (!clock.entryId) return;
    try {
      await core.raw('seek_playback_identified', {
        seconds: Math.max(0, seconds), expectedGeneration: clock.generation, expectedAuthGeneration: clock.authGeneration, expectedEntryId: clock.entryId
      });
    } catch (error) {
      core.note(`sync: seek failed (${rpcCode(error)})`);
    }
  }

  const setSpeed = (speed: number) => core.raw('jam_set_speed', { speed }).catch(error => core.note(`sync: speed failed (${rpcCode(error)})`));

  async function tick(): Promise<void> {
    const token = core.d.token;
    const { anchor, track } = core.d;
    if (!anchor || !track) return;
    const match = core.matching.matchOf(track.uri);
    if (!match) { setStatus('idle', null); return; }
    let clock: JamClock;
    try {
      clock = await core.raw<JamClock>('jam_clock');
    } catch {
      return;
    }
    if (!core.isCurrent(token) || core.d.anchor !== anchor || core.d.track !== track) return;
    const now = core.now();
    // The sample is taken at `atEpochMs`: the target is read at that same instant, so IPC latency cancels out.
    const target = livePositionSeconds(anchor, clock.atEpochMs) + manualOffsetSeconds();

    // The player has to be on this Jam track's equivalent; anything else is not ours to correct.
    if (!playerIsOnJamEntry(clock, match.view.videoId)) {
      if (core.mirror.busy() || clock.isLoading) { mismatchSince = null; setStatus('idle', null); return; }
      mismatchSince ??= now;
      if (clock.isPlaying && now - mismatchSince >= MISMATCH_SILENCE_MS) pauseLocal();
      setStatus('idle', null);
      return;
    }
    mismatchSince = null;
    if (clock.isLoading) return;

    const duration = core.d.playback?.duration ?? 0;
    const paused = anchor.paused || core.d.locallyPaused;
    if (paused) {
      if (clock.isPlaying && transportReady()) void core.raw('pause_playback').catch(() => {});
      const gap = clock.positionSecs - target;
      if (!core.d.locallyPaused && engine.isAdjusting && Math.abs(gap) > PAUSED_TOLERANCE_S && pausedSeekTries < PAUSED_SEEK_TRIES && now - lastSeekAt > 1000) {
        pausedSeekTries += 1;
        await applySeek(clock, target);
      } else if (Math.abs(gap) <= PAUSED_TOLERANCE_S || pausedSeekTries >= PAUSED_SEEK_TRIES) {
        engine.cancel();
        setStatus('locked', gap * 1000);
        return;
      }
      setStatus(engine.isAdjusting ? 'adjusting' : 'locked', gap * 1000);
      return;
    }
    // This version is shorter than the Jam's: stay silent until the Jam moves on.
    if (duration > 0 && target >= duration - 0.4) {
      if (clock.isPlaying) pauseLocal();
      setStatus('idle', null);
      return;
    }
    if (!clock.isPlaying) {
      if (transportReady()) {
        await core.raw('resume_playback').catch(() => {});
        begin();
      }
      return;
    }
    if (core.d.syncHold) { setStatus('idle', (clock.positionSecs - target) * 1000); return; }

    const drift = clock.positionSecs - target;
    engine.setItem(match.view.videoId);
    const action: SyncAction = engine.tick(drift, now / 1000, clock.isPlaying && !clock.isLoading);
    if (engine.didReopen) core.note(`sync: sustained drift of ${Math.round(drift * 1000)} ms, adjusting again`);
    switch (action.kind) {
      case 'seek':
        core.note(`sync: seek (drift ${Math.round(drift * 1000)} ms, compensation ${Math.round(action.compensation * 1000)} ms)`);
        await applySeek(clock, livePositionSeconds(anchor, core.now()) + manualOffsetSeconds() + action.compensation);
        break;
      case 'setRate':
        core.note(`sync: rate ${action.rate.toFixed(2)} (drift ${Math.round(drift * 1000)} ms)`);
        await setSpeed(action.rate);
        break;
      case 'lock':
        if (clock.speed !== 1) await setSpeed(1);
        if (engine.lastSummary) core.note(`sync: locked, ${summaryText(engine.lastSummary)}`);
        break;
      default:
        break;
    }
    if (action.kind === 'lock') lockStatus = engine.lastSummary?.reason === 'hardCap' ? 'gaveUp' : 'locked';
    setStatus(engine.isAdjusting ? 'adjusting' : lockStatus, drift * 1000, action.kind !== 'none');
  }

  function loop(): void {
    timer = null;
    if (!running) return;
    const run = async () => {
      if (inTick) return;
      inTick = true;
      try { await tick(); } catch (error) { core.note(`sync: tick error (${error instanceof Error ? error.message : 'failed'})`); } finally { inTick = false; }
    };
    void run().finally(() => {
      if (!running) return;
      const anchored = core.d.anchor;
      const delay = anchored?.paused || core.d.locallyPaused ? PAUSED_INTERVAL_MS : engine.isAdjusting ? ADJUSTING_INTERVAL_MS : LOCKED_INTERVAL_MS;
      timer = core.sched.setTimeout(loop, delay);
    });
  }

  return {
    begin,
    pauseLocal,
    start() {
      if (running) return;
      running = true;
      timer = core.sched.setTimeout(loop, ADJUSTING_INTERVAL_MS);
    },
    stop() {
      running = false;
      if (timer !== null) core.sched.clearTimeout(timer);
      timer = null;
      engine.cancel();
      mismatchSince = null;
      lockStatus = 'locked';
    }
  };
}
