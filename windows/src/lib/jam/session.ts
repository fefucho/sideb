// Jam session: state machine, plugin events, view state and actions. The pieces it composes live
// next to it: matching.ts (lookups), mirror.ts (native queue), sync.ts (position), guard.ts
// (Jam-aware RPC), edits.ts (queue edits and Spotify resolution).
import { writable } from 'svelte/store';
import type { Jam, JamDeps } from './index';
import { createEdits } from './edits';
import { createGuard } from './guard';
import { createMatching } from './matching';
import { createMirror } from './mirror';
import {
  livePositionSeconds, rpcCode, viewToMatched,
  type Anchor, type JamCore, type JamData
} from './model';
import { identities } from './queueMapping';
import { createSync } from './sync';
import {
  emptyJamState, JAM_EVENT, JAM_LOGIN_EVENT,
  type JamActions, type JamInvite, type JamMember, type JamPluginEvent, type JamPluginMember, type JamPluginTrack, type JamRuntimeStatus,
  type JamScheduler, type JamTrackView, type JamViewState
} from './types';

const LOG_LIMIT = 250;
const TOAST_LIMIT = 5;
const TOAST_LIFETIME_MS = 12000;
const TOAST_DEDUPE_MS = 3000;
/// A position report that moves the Jam's timeline by more than this is a seek by someone.
const JUMP_SECONDS = 0.6;
const RESULT_LIFETIME_MS = 15000;
/// `authRequired` this many times within the window is no longer a token renewal in progress.
const AUTH_MAX_FAILURES = 3;
const AUTH_WINDOW_MS = 60_000;
const BANNER_LIFETIME_MS = 10_000;
const DISMISSED_INVITES_KEY = 'sideb.jam.dismissedInvites.v1';
const MAX_DISMISSED_INVITES = 50;

const defaultScheduler: JamScheduler = {
  setTimeout: (callback, ms) => globalThis.setTimeout(callback, ms),
  clearTimeout: handle => globalThis.clearTimeout(handle as ReturnType<typeof setTimeout>)
};

/** Plugin error codes and the i18n keys they map to; anything else becomes `jam.error.generic`. */
const PLUGIN_ERRORS: Record<string, string> = {
  authRequired: 'jam.error.authRequired', invalidLink: 'jam.error.linkInvalid', jamNotFound: 'jam.error.notFound', network: 'jam.error.connection',
  notAllowed: 'jam.error.notAllowed', rateLimited: 'jam.error.rateLimited', rejected: 'jam.error.rejected', unavailable: 'jam.error.unavailable',
  unsupported: 'jam.error.unsupported'
};
const HOST_ERRORS: Record<string, string> = {
  JAM_PLUGIN_MISSING: 'jam.error.pluginMissing',
  JAM_NOT_SIGNED_IN: 'jam.error.notSignedIn',
  JAM_START_FAILED: 'jam.error.startFailed'
};

export const errorKey = (code: string) => Object.hasOwn(PLUGIN_ERRORS, code) ? PLUGIN_ERRORS[code] : 'jam.error.generic';

/** Message key for a Jam that ended; `reason` is the plugin's raw reason. */
export function endedKey(reason: string | null | undefined): string {
  const text = (reason ?? '').toUpperCase();
  if (text.includes('KICK') || text.includes('REMOVED')) return 'jam.ended.removed';
  if (text.includes('CONNECTION')) return 'jam.ended.connection';
  if (text.includes('DELETED') || text.includes('ENDED')) return 'jam.ended.host';
  return 'jam.ended.interrupted';
}

const trackText = (track: JamPluginTrack) => ({ title: track.title ?? track.uri, artists: track.artists.join(', ') });

function extractJamToken(link: string): string | null {
  const trimmed = link.trim();
  if (!trimmed) return null;
  const marker = 'socialsession';
  const index = trimmed.indexOf(marker);
  if (index >= 0) {
    let rest = trimmed.slice(index + marker.length);
    while (rest.startsWith('/') || rest.startsWith(':')) rest = rest.slice(1);
    const token = rest.split(/[?#/\s]/, 1)[0];
    return token ? token : null;
  }
  return !/[/:?\s]/.test(trimmed) ? trimmed : null;
}

function parseInvite(event: Extract<JamPluginEvent, { type: 'inviteAvailable' }>): JamInvite | null {
  const token = event.token?.trim() ?? '';
  if (!token) return null;
  const id = event.id?.trim() || token;
  const link = event.link?.trim() || `https://open.spotify.com/socialsession/${token}`;
  const senderName = event.senderName?.trim() || null;
  const senderImageUrl = event.senderImageUrl?.trim() || null;
  const sentAtMs = typeof event.sentAtMs === 'number' && Number.isFinite(event.sentAtMs) ? event.sentAtMs : null;
  const participantCount = typeof event.participantCount === 'number' && Number.isFinite(event.participantCount) ? event.participantCount : null;
  return { id, token, link, senderName, senderImageUrl, sentAtMs, participantCount };
}

function loadDismissedInvites(): string[] {
  try {
    const raw = globalThis.localStorage?.getItem(DISMISSED_INVITES_KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((item): item is string => typeof item === 'string' && item.length > 0).slice(-MAX_DISMISSED_INVITES);
  } catch {
    return [];
  }
}

function saveDismissedInvites(ids: string[]): void {
  try {
    globalThis.localStorage?.setItem(DISMISSED_INVITES_KEY, JSON.stringify(ids));
  } catch {
    // Storage unavailable (tests, restricted environment).
  }
}

export function createSession(deps: JamDeps): Jam {
  const raw = deps.rpc;
  const now = deps.now ?? (() => Date.now());
  const sched = deps.schedule ?? defaultScheduler;

  let view: JamViewState = emptyJamState();
  const store = writable(view);
  const patch = (partial: Partial<JamViewState>) => { view = { ...view, ...partial }; store.set(view); };

  const d: JamData = {
    token: 0, track: null, queue: [], queueRevision: null, anchor: null, matches: new Map(), overrides: new Map(), playback: null,
    locallyPaused: false, syncHold: false, offsetMs: null, syncStatus: 'idle'
  };
  let tokenSeq = 0;
  let idSeq = 0;
  let toastSeq = 0;
  let destroyed = false;
  let authFailures: number[] = [];
  let activeInviteToken: string | null = null;
  let bannerTimer: unknown = null;
  const shownBannerIds = new Set<string>();
  const dismissedOrder = loadDismissedInvites();
  let dismissedIds = new Set<string>(dismissedOrder);
  const unlisten: Array<() => void | Promise<void>> = [];
  const lastToast = new Map<string, number>();
  const results = new Map<string, { handler: (ok: boolean, detail: string | null) => void; timer: unknown }>();

  const clearBannerTimer = () => {
    if (bannerTimer !== null) {
      sched.clearTimeout(bannerTimer);
      bannerTimer = null;
    }
  };
  const showInviteBanner = (invite: JamInvite) => {
    clearBannerTimer();
    patch({ inviteBanner: invite });
    const id = invite.id;
    bannerTimer = sched.setTimeout(() => {
      bannerTimer = null;
      if (!destroyed && view.inviteBanner?.id === id) patch({ inviteBanner: null });
    }, BANNER_LIFETIME_MS);
  };
  const markInviteDismissed = (id: string) => {
    const existing = dismissedOrder.indexOf(id);
    if (existing >= 0) dismissedOrder.splice(existing, 1);
    dismissedOrder.push(id);
    if (dismissedOrder.length > MAX_DISMISSED_INVITES) {
      dismissedOrder.splice(0, dismissedOrder.length - MAX_DISMISSED_INVITES);
    }
    dismissedIds = new Set(dismissedOrder);
    saveDismissedInvites(dismissedOrder);
  };

  const phaseIs = (...phases: JamViewState['phase'][]) => phases.includes(view.phase);
  const inSession = () => phaseIs('joining', 'active', 'reconnecting');

  const core: JamCore = {
    raw, now, sched, d,
    isLive: () => phaseIs('active', 'reconnecting'),
    isCurrent: token => token === d.token && inSession(),
    view: () => view,
    patch,
    publishTracks,
    note(line) {
      const stamp = new Date(now()).toISOString().slice(11, 19);
      patch({ log: [...view.log, `${stamp}  ${line}`].slice(-LOG_LIMIT) });
    },
    toast(key, values) {
      const dedupe = `${key}|${values ? JSON.stringify(values) : ''}`;
      const at = now();
      if (at - (lastToast.get(dedupe) ?? -Infinity) < TOAST_DEDUPE_MS) return;
      lastToast.set(dedupe, at);
      const id = ++toastSeq;
      patch({ toasts: [{ key, ...(values ? { values } : {}), id }, ...view.toasts].slice(0, TOAST_LIMIT) });
      sched.setTimeout(() => dismissToast(id), TOAST_LIFETIME_MS);
    },
    async send(message) {
      try {
        await raw('jam_send', { message });
        return true;
      } catch (error) {
        core.note(`send ${String(message.action ?? message.type)} failed (${rpcCode(error)})`);
        return false;
      }
    },
    expectResult(requestId, handler) {
      const timer = sched.setTimeout(() => results.delete(requestId), RESULT_LIFETIME_MS);
      results.set(requestId, { handler, timer });
    },
    forgetResult(requestId) {
      const entry = results.get(requestId);
      if (entry) sched.clearTimeout(entry.timer);
      results.delete(requestId);
    },
    newId: prefix => `${prefix}-${++idSeq}`,
    mirror: undefined as never, sync: undefined as never, matching: undefined as never
  };
  core.matching = createMatching(core);
  core.mirror = createMirror(core);
  core.sync = createSync(core);
  const edits = createEdits(core);
  const guard = createGuard(core, edits, {
    onPendingChange: reasonKey => patch({ pendingExit: reasonKey ? { reasonKey } : null })
  });

  function dismissToast(id: number): void {
    if (view.toasts.some(toast => toast.id === id)) patch({ toasts: view.toasts.filter(toast => toast.id !== id) });
  }

  function publishTracks(): void {
    const ids = identities(d.track?.uri ?? null, d.queue.map(track => track.uri));
    const build = (track: JamPluginTrack, key: string): JamTrackView => {
      const state = d.matches.get(track.uri);
      const text = trackText(track);
      return {
        key, uri: track.uri, title: text.title, artists: text.artists, album: track.album, durationMs: track.durationMs,
        status: core.matching.statusOf(track.uri), matched: state?.kind === 'matched' ? { ...state.match.view } : null,
        corrected: state?.kind === 'matched' ? state.corrected : false, addedByPerson: track.provider === 'queue'
      };
    };
    patch({
      current: d.track && ids.current ? build(d.track, ids.current.key) : null,
      queue: d.queue.map((track, index) => build(track, ids.queue[index].key))
    });
  }

  function mapMembers(members: JamPluginMember[]): Pick<JamViewState, 'members' | 'host'> {
    const mapped: JamMember[] = members.map((member, index) => ({
      id: member.id ?? `${member.name ?? 'member'}-${index}`, name: member.name ?? '', imageUrl: member.imageUrl ?? null,
      isHost: !!member.isHost, isMe: !!member.isCurrentUser
    }));
    return { members: mapped, host: mapped.find(member => member.isHost) ?? null };
  }

  function resetData(): void {
    d.token = ++tokenSeq;
    d.track = null;
    d.queue = [];
    d.queueRevision = null;
    d.anchor = null;
    d.matches = new Map();
    d.locallyPaused = false;
    d.syncHold = false;
    d.offsetMs = null;
    d.syncStatus = 'idle';
    authFailures = [];
  }

  function stopWork(): void {
    core.sync.stop();
    core.mirror.stop();
    edits.stop();
    core.matching.reset();
    for (const entry of results.values()) sched.clearTimeout(entry.timer);
    results.clear();
    guard.clearPending();
  }

  /** Ends the session: nothing more is synced, the speed goes back to 1 and the runtime leaves. Playback stays as it is. */
  async function endSession(phase: 'idle' | 'ended' | 'error', messageKey: string | null): Promise<void> {
    if (!inSession()) return;
    stopWork();
    resetData();
    activeInviteToken = null;
    patch({
      phase, messageKey, members: [], host: null, canControl: false, hostActive: false, current: null, queue: [], paused: true,
      sync: { status: 'idle', offsetMs: null, manualOffsetMs: view.sync.manualOffsetMs }, pendingExit: null
    });
    core.note(`session ${phase}${messageKey ? ` (${messageKey})` : ''}`);
    await raw('jam_set_speed', { speed: 1 }).catch(() => {});
    await raw('jam_leave').catch(() => {});
  }

  // MARK: Plugin events

  function applyState(event: Extract<JamPluginEvent, { type: 'state' }>): void {
    const previousUri = d.track?.uri ?? null;
    const previousQueue = d.queue.map(track => track.uri);
    const next: Anchor = { positionMs: event.positionMs, atLocalMs: event.atLocalMs, paused: event.paused, durationMs: event.durationMs };
    const at = now();
    // Re-anchor only on a real change: another track, pause/resume or a jump (seek). A report that
    // merely restates the same timeline keeps the anchor, so jitter never moves the target.
    let realChange = true;
    if (d.anchor && (event.track?.uri ?? null) === previousUri && d.anchor.paused === next.paused
      && Math.abs(livePositionSeconds(d.anchor, at) - livePositionSeconds(next, at)) < JUMP_SECONDS) {
      d.anchor.durationMs = next.durationMs;
      realChange = false;
    } else {
      d.anchor = next;
    }
    if (event.paused !== view.paused) core.note(event.paused ? 'jam paused' : 'jam playing');
    d.track = event.track;
    d.queue = event.queue ?? [];
    d.queueRevision = event.queueRevision ?? null;
    const trackChanged = (event.track?.uri ?? null) !== previousUri;
    const queueChanged = d.queue.length !== previousQueue.length || d.queue.some((track, index) => track.uri !== previousQueue[index]);
    if (trackChanged && event.track) core.note(`jam track: ${trackText(event.track).title} - ${trackText(event.track).artists}`);
    patch({ ...(phaseIs('joining', 'reconnecting') ? { phase: 'active' as const, messageKey: null } : {}), paused: event.paused, hostActive: event.paused ? view.hostActive : true });
    core.matching.pump();
    publishTracks();
    if (trackChanged) core.mirror.onTrackChange();
    else if (queueChanged) core.mirror.onQueueChange();
    if (realChange) core.sync.begin();
    edits.onState();
  }

  function handleEvent(event: JamPluginEvent): void {
    if (destroyed) return;
    if (event.type === 'inviteAvailable') {
      const invite = parseInvite(event);
      if (!invite) return;
      if (inSession() && activeInviteToken === invite.token) return;
      if (dismissedIds.has(invite.id)) return;
      const existingIndex = view.invites.findIndex(item => item.id === invite.id || item.token === invite.token);
      const invites = existingIndex >= 0
        ? view.invites.map((item, idx) => idx === existingIndex ? invite : item)
        : [invite, ...view.invites];
      if (view.inviteBanner?.id === invite.id) {
        patch({ invites, inviteBanner: invite });
      } else {
        patch({ invites });
      }
      if (!shownBannerIds.has(invite.id)) {
        shownBannerIds.add(invite.id);
        showInviteBanner(invite);
      }
      return;
    }
    if (event.type === 'inviteExpired') {
      const expiredId = event.id?.trim() || null;
      const expiredToken = event.token?.trim() || null;
      if (!expiredId && !expiredToken) return;
      const matches = (item: JamInvite) =>
        (expiredId !== null && item.id === expiredId) ||
        (expiredToken !== null && item.token === expiredToken);
      const invites = view.invites.filter(item => !matches(item));
      const bannerMatches = view.inviteBanner !== null && matches(view.inviteBanner);
      if (bannerMatches) clearBannerTimer();
      if (invites.length !== view.invites.length || bannerMatches) {
        patch({ invites, ...(bannerMatches ? { inviteBanner: null } : {}) });
      }
      return;
    }
    if (!inSession()) return;
    switch (event.type) {
      case 'joined':
        core.note(`joined (control ${event.canControl}, host active ${event.hostActive})`);
        patch({ ...mapMembers(event.members ?? []), canControl: event.canControl, hostActive: event.hostActive, phase: 'active', messageKey: null });
        core.sync.start();
        break;
      case 'state':
        if (view.phase === 'joining') core.sync.start();
        applyState(event);
        break;
      case 'members':
        patch(mapMembers(event.members ?? []));
        break;
      case 'session':
        core.note(`jam: ${event.reason ?? '?'}`);
        break;
      case 'notice':
        core.note(`notice: ${event.code}`);
        if (event.code === 'NO_HOST_ACTIVE_DEVICE') {
          patch({ hostActive: false });
          core.toast('jam.notice.noHostDevice');
        }
        break;
      case 'commandResult': {
        core.note(`command ${event.action}: ${event.ok ? 'accepted' : `failed ${event.detail ?? ''}`}`);
        const entry = event.requestId ? results.get(event.requestId) : undefined;
        if (entry && event.requestId) {
          core.forgetResult(event.requestId);
          entry.handler(event.ok, event.detail);
        }
        break;
      }
      case 'resolved':
        edits.onResolved(event.requestId, event.uri);
        break;
      case 'ended':
        void endSession('ended', endedKey(event.reason));
        break;
      case 'error':
        core.note(`error: ${event.code}${event.retryable ? ' (retrying)' : ''}`);
        // The runtime renews the token itself on authRequired: transient unless it keeps repeating.
        if (event.code === 'authRequired') {
          authFailures = [...authFailures.filter(at => now() - at < AUTH_WINDOW_MS), now()];
          if (authFailures.length >= AUTH_MAX_FAILURES) { void endSession('error', errorKey('authRequired')); break; }
        }
        if (event.retryable || event.code === 'authRequired') {
          if (view.phase !== 'reconnecting') {
            patch({ phase: 'reconnecting' });
            core.toast('jam.notice.reconnecting');
          }
        } else {
          void endSession('error', errorKey(event.code));
        }
        break;
      case 'exited':
        void (view.phase === 'joining' ? endSession('error', 'jam.error.startFailed') : endSession('ended', 'jam.ended.interrupted'));
        break;
    }
  }

  // MARK: Actions

  async function refreshStatus(): Promise<void> {
    try {
      const runtime = await raw<JamRuntimeStatus>('jam_status');
      if (runtime.signedIn === false && (view.invites.length > 0 || view.inviteBanner !== null)) {
        clearBannerTimer();
        shownBannerIds.clear();
        patch({ runtime, invites: [], inviteBanner: null });
      } else {
        patch({ runtime });
      }
      if (runtime.pluginAvailable && runtime.signedIn === true) {
        void raw('jam_start_invite_watch').catch(() => {});
      }
    } catch {
      // Keep the last known status.
    }
  }

  async function joinInternal(link: string, knownToken: string | null): Promise<void> {
    if (inSession()) return;
    resetData();
    core.matching.reset();
    clearBannerTimer();
    activeInviteToken = knownToken;
    const trimmedLink = link.trim();
    const remainingInvites = view.invites.filter(item => !(knownToken && item.token === knownToken) && item.link !== trimmedLink);
    const token = d.token;
    patch({
      ...emptyJamState(), runtime: view.runtime, phase: 'joining',
      sync: { status: 'idle', offsetMs: null, manualOffsetMs: view.sync.manualOffsetMs },
      invites: remainingInvites, inviteBanner: null
    });
    core.note('joining');
    try {
      await raw('jam_join', { link });
    } catch (error) {
      if (!core.isCurrent(token)) return;
      const code = rpcCode(error);
      core.note(`join failed (${code})`);
      await endSession('error', HOST_ERRORS[code] ?? 'jam.error.generic');
    }
  }

  function join(link: string): Promise<void> {
    return joinInternal(link, extractJamToken(link));
  }

  const actions: JamActions = {
    refreshStatus,
    async openLogin(title) {
      try { await raw('jam_open_spotify_login', { title }); } catch { /* the login window failed to open */ }
      await refreshStatus();
    },
    async signOut() {
      // Signing out does not stop a running Jam: leave first.
      await endSession('idle', null);
      clearBannerTimer();
      shownBannerIds.clear();
      activeInviteToken = null;
      patch({ invites: [], inviteBanner: null });
      try { await raw('jam_spotify_sign_out'); } catch { /* already signed out */ }
      await refreshStatus();
    },
    join,
    async joinInvite(invite) {
      if (view.inviteBanner?.id === invite.id || view.inviteBanner?.token === invite.token) {
        clearBannerTimer();
        patch({ inviteBanner: null });
      }
      if (inSession()) return;
      patch({ invites: view.invites.filter(item => item.id !== invite.id && item.token !== invite.token) });
      await joinInternal(invite.link, invite.token);
    },
    dismissInvite(id) {
      markInviteDismissed(id);
      const invites = view.invites.filter(item => item.id !== id);
      const bannerMatches = view.inviteBanner?.id === id;
      if (bannerMatches) clearBannerTimer();
      if (invites.length !== view.invites.length || bannerMatches) {
        patch({ invites, ...(bannerMatches ? { inviteBanner: null } : {}) });
      }
    },
    dismissInviteBanner(id) {
      if (view.inviteBanner?.id !== id) return;
      clearBannerTimer();
      patch({ inviteBanner: null });
    },
    leave: () => endSession('idle', null),
    async correctMatch(key, song) {
      if (!core.isLive()) return;
      const ids = identities(d.track?.uri ?? null, d.queue.map(track => track.uri));
      const index = ids.queue.findIndex(item => item.key === key);
      const uri = ids.current?.key === key ? d.track?.uri : index >= 0 ? d.queue[index].uri : undefined;
      if (!uri) return;
      core.matching.setCorrected(uri, viewToMatched(song));
      core.note(`match corrected by hand: ${song.title}`);
      publishTracks();
      if (uri === d.track?.uri) core.mirror.loadCurrent(true);
      else core.mirror.onQueueChange();
    },
    async addSong(song, index) {
      const where = index === undefined ? { atEnd: true as const } : { atEnd: false as const, index, anchored: true };
      return (await edits.addSongs([{ title: song.title, artists: song.artists, album: song.album ?? null, durationSecs: song.durationSecs ?? null }], where)) === 1;
    },
    moveQueue: (from, to) => edits.moveTo(from, to),
    removeQueue: index => edits.removeAt(index),
    setManualOffset(ms) {
      patch({ sync: { ...view.sync, manualOffsetMs: ms } });
      if (core.isLive()) core.sync.begin();
    },
    resync() {
      if (!core.isLive()) return;
      core.note('resync requested');
      core.matching.retryExhausted();
      core.sync.begin();
    },
    dismissToast,
    async confirmExit() {
      const call = guard.takePending();
      patch({ pendingExit: null });
      if (!call) return;
      await endSession('idle', null);
      try {
        await raw(call.command, call.args);
      } catch (error) {
        core.note(`${call.command} after leaving failed (${rpcCode(error)})`);
      }
    },
    cancelExit() {
      guard.clearPending();
      if (view.pendingExit) patch({ pendingExit: null });
    }
  };

  // Always listening; invite events apply anytime, session events while a session is in progress.
  const subscribe = (event: string, handler: (payload: never) => void) => {
    void deps.listen<never>(event, e => handler(e.payload)).then(
      stop => { if (destroyed) void stop(); else unlisten.push(stop); },
      () => {}
    );
  };
  subscribe(JAM_EVENT, payload => handleEvent(payload as JamPluginEvent));
  subscribe(JAM_LOGIN_EVENT, () => { void refreshStatus(); });

  return {
    state: { subscribe: store.subscribe },
    actions,
    rpc: guard.rpc,
    onPlaybackState(state) {
      d.playback = state;
      if (core.isLive()) core.mirror.onPlayback(state);
    },
    destroy() {
      if (destroyed) return;
      clearBannerTimer();
      activeInviteToken = null;
      void endSession('idle', null);
      destroyed = true;
      for (const stop of unlisten.splice(0)) void stop();
    }
  };
}
