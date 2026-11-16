import type { PlayerListen, PlayerRpc, PlayerUnlisten } from './controller';

/** Automix (PLAN-024). Rust owns the setting and the preparation; this only mirrors it. */
export type AutomixPhase = 'off' | 'idle' | 'preparing' | 'ready' | 'unavailable' | 'mixing';

export interface AutomixStatus {
  enabled: boolean;
  phase: AutomixPhase;
  /** "mix" | "cut" | "fade" once a transition exists. */
  kind: string | null;
  bpmFrom: number | null;
  bpmTo: number | null;
  bars: number | null;
  stemsModel: boolean | null;
  /** Stable code, translated in the UI (see `automixPresentation`). */
  reason: string | null;
  /** Second of the CURRENT song (its progress-bar axis) where the mix starts: `a_cut + overlap_start`. */
  markerSeconds: number | null;
}

export const offAutomix = (): AutomixStatus => ({ enabled: false, phase: 'off', kind: null, bpmFrom: null, bpmTo: null, bars: null, stemsModel: null, reason: null, markerSeconds: null });

const phases: readonly AutomixPhase[] = ['off', 'idle', 'preparing', 'ready', 'unavailable', 'mixing'];
const reasons = ['no-next', 'album', 'same-song', 'jam', 'repeat', 'unsupported-format', 'too-long', 'late', 'failed', 'load', 'resolve'] as const;
const kinds = ['mix', 'cut', 'fade'] as const;

/** Defensive: an old or malformed payload never breaks the UI, it reads as "off". */
export function normalizeAutomix(value: unknown): AutomixStatus {
  if (!value || typeof value !== 'object') return offAutomix();
  const raw = value as Partial<Record<keyof AutomixStatus, unknown>>;
  const enabled = raw.enabled === true;
  const phase = phases.includes(raw.phase as AutomixPhase) ? raw.phase as AutomixPhase : (enabled ? 'idle' : 'off');
  const number = (item: unknown) => typeof item === 'number' && Number.isFinite(item) && item > 0 ? item : null;
  return {
    // A Jam reports `unavailable` even with the preference off; only that case keeps a non-"off" phase.
    enabled, phase: enabled || phase === 'unavailable' ? phase : 'off',
    kind: kinds.includes(raw.kind as typeof kinds[number]) ? raw.kind as string : null,
    bpmFrom: number(raw.bpmFrom), bpmTo: number(raw.bpmTo),
    bars: typeof raw.bars === 'number' ? raw.bars : null,
    stemsModel: typeof raw.stemsModel === 'boolean' ? raw.stemsModel : null,
    reason: reasons.includes(raw.reason as typeof reasons[number]) ? raw.reason as string : null,
    markerSeconds: typeof raw.markerSeconds === 'number' && Number.isFinite(raw.markerSeconds) && raw.markerSeconds >= 0 ? raw.markerSeconds : null,
  };
}

export type AutomixTone = 'off' | 'neutral' | 'busy' | 'ready' | 'warning' | 'active';
export type Translate = (key: string, args?: string[]) => string;
export interface AutomixPresentation {
  /** The status sentence shared with Mac (`automix.status.*` / `automix.unavailable.*`). */
  text: string;
  tone: AutomixTone;
  /** Drives the pill's emphasis: on only when it is enabled and not blocked. */
  on: boolean;
}

/** Native reason code → the shared Mac key. `load` and `resolve` are failures with no wording of their own. */
const unavailableKey: Record<string, string> = {
  'no-next': 'noNextTrack', album: 'sameAlbum', 'same-song': 'sameTrack', jam: 'jam', repeat: 'repeatOne',
  'unsupported-format': 'unsupportedFormat', 'too-long': 'tooLong', late: 'tooLate', failed: 'failed', load: 'failed', resolve: 'failed',
};

/** A Jam forces Automix off in the UI without touching the saved preference (`enabled` is kept). */
export function automixWithJam(status: AutomixStatus, jamLive: boolean): AutomixStatus {
  if (!jamLive) return status;
  return { ...status, phase: 'unavailable', reason: 'jam', kind: null, markerSeconds: null };
}

export const automixBlockedByJam = (status: AutomixStatus): boolean => status.phase === 'unavailable' && status.reason === 'jam';

/** What the pill and the settings row say, in the active language, from the shared texts. */
export function automixPresentation(status: AutomixStatus, tr: Translate): AutomixPresentation {
  const blocked = (reason: string | null, on = status.enabled): AutomixPresentation => ({
    text: tr(`automix.unavailable.${unavailableKey[reason ?? 'failed'] ?? 'failed'}`), tone: 'warning', on });
  if (automixBlockedByJam(status)) return blocked('jam', false);
  if (!status.enabled) return { text: tr('automix.status.off'), tone: 'off', on: false };
  switch (status.phase) {
    case 'preparing': return { text: tr('automix.status.preparing'), tone: 'busy', on: true };
    case 'ready':
    case 'mixing': {
      if (!status.kind) break;
      const kind = tr(`automix.kind.${status.kind}`);
      const bpm = status.bpmTo ?? status.bpmFrom;
      if (status.phase === 'mixing') return { text: tr('automix.status.mixing', [kind]), tone: 'active', on: true };
      return { text: bpm ? tr('automix.status.ready', [kind, `${Math.round(bpm)}`]) : tr('automix.status.readyNoBpm', [kind]), tone: 'ready', on: true };
    }
    case 'unavailable': return blocked(status.reason);
    case 'idle': if (status.reason) return blocked(status.reason); break;
    default: break;
  }
  return { text: tr('automix.status.idle'), tone: 'neutral', on: true };
}

/**
 * Where the mix starts on the progress bar (0…1), or null when it does not fit: no valid duration, or the mix
 * would start at the end or after. Same rule as the Mac `AutomixProgressMarker`.
 */
export function automixMarkerFraction(seconds: number | null | undefined, duration: number): number | null {
  if (typeof seconds !== 'number' || !Number.isFinite(seconds) || seconds < 0) return null;
  if (!Number.isFinite(duration) || duration <= 0 || seconds >= duration) return null;
  return seconds / duration;
}

/** Geometry over a bar of `width`: the tick and the tinted stretch from it to the end (they add up to the width). */
export function automixMarkerLayout(seconds: number | null | undefined, duration: number, width: number): { tickX: number; segmentWidth: number } | null {
  const fraction = automixMarkerFraction(seconds, duration);
  if (fraction === null || !Number.isFinite(width) || width <= 0) return null;
  const tickX = width * fraction;
  return { tickX, segmentWidth: width - tickX };
}

export interface AutomixSnapshot { status: AutomixStatus; pending: boolean; error: string | null }

/** Mirrors the native Automix status (`automix-status-changed`) and sends the setting. */
export class AutomixController {
  private status = offAutomix();
  private pending = false;
  private error: string | null = null;
  private revision = 0;
  private connected = false;
  private unlisten: PlayerUnlisten | null = null;
  private disposed = false;

  constructor(private rpc: PlayerRpc, private listen: PlayerListen, private publish: (snapshot: AutomixSnapshot) => void) {
    this.emit();
  }

  get snapshot(): AutomixSnapshot { return { status: this.status, pending: this.pending, error: this.error }; }
  private emit() { this.publish(this.snapshot); }

  async connect(): Promise<void> {
    if (this.connected || this.disposed) return;
    this.connected = true;
    try {
      const unlisten = await this.listen<unknown>('automix-status-changed', event => this.accept(event.payload));
      if (this.disposed) { await unlisten(); return; }
      this.unlisten = unlisten;
    } catch { /* The button just stays on its last known state. */ }
    try { this.accept(await this.rpc('get_automix_status')); } catch { /* Same. */ }
  }

  private accept(payload: unknown) {
    // An event that races an in-flight toggle must not undo the user's choice mid-request.
    if (this.pending) return;
    this.status = normalizeAutomix(payload);
    this.emit();
  }

  async setEnabled(enabled: boolean): Promise<void> {
    if (this.pending) return;
    const revision = ++this.revision;
    this.pending = true;
    this.error = null;
    this.emit();
    try {
      const next = normalizeAutomix(await this.rpc('set_automix_enabled', { enabled }));
      if (revision === this.revision) this.status = next;
    } catch (cause) {
      const message = cause && typeof cause === 'object' && 'message' in cause && typeof cause.message === 'string' ? cause.message : null;
      this.error = message ?? 'No se pudo cambiar Automix.';
    } finally {
      if (revision === this.revision) this.pending = false;
      this.emit();
    }
  }

  toggle(): Promise<void> { return this.setEnabled(!this.status.enabled); }

  async dispose(): Promise<void> {
    this.disposed = true;
    const unlisten = this.unlisten;
    this.unlisten = null;
    try { await unlisten?.(); } catch { /* Best effort. */ }
  }
}
