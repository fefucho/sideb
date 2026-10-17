/** App defaults, pending calibration with real Windows mice and Precision Touchpads.
 * deltaMode expresses units, never hardware identity. The quiet interval is an
 * app transaction boundary, not evidence that fingers left the trackpad. */
export const VOLUME_SCROLL_QUIET_MS = 180;
export const VOLUME_FEEDBACK_MS = 900;
export type VolumeScrollSurface = 'bar' | 'fullscreen';
export interface VolumeScrollContext {
  revision: string; enabled: boolean; blocked: boolean; value: number;
}
export interface VolumeWheelSample {
  x: number; y: number; mode: number; at: number;
  surface: VolumeScrollSurface | null; cancelable: boolean; defaultPrevented: boolean;
  modified: boolean; momentum?: boolean;
}
export interface VolumeScrollOutput {
  consume: boolean; delta: number; feedback: boolean; cancelled: boolean;
}
const idle = (cancelled = false): VolumeScrollOutput => ({consume:false,delta:0,feedback:false,cancelled});

/** Pure ownership/accumulation policy. The adapter must confirm preventDefault
 * succeeded before applying delta or publishing feedback. */
export class VolumeScrollPolicy {
  private burst: {at:number; revision:string; surface:VolumeScrollSurface|null; owned:boolean; draining:boolean; remainder:number; direction:number} | null = null;
  cancel(): void { if(this.burst) { this.burst.draining = true; this.burst.remainder = 0; } }
  reset(): void { this.burst = null; }
  get tracking(): boolean { return !!this.burst?.owned && !this.burst.draining; }
  recent(at:number): boolean { return this.tracking && at-this.burst!.at <= VOLUME_FEEDBACK_MS; }
  leave(surface:VolumeScrollSurface|null): boolean {
    if(!this.tracking || surface===this.burst!.surface) return false;
    this.cancel(); return true;
  }
  wheel(sample: VolumeWheelSample, context: VolumeScrollContext): VolumeScrollOutput {
    if(this.burst && sample.at-this.burst.at > VOLUME_SCROLL_QUIET_MS) this.burst = null;
    const units = [100, 3, 1][sample.mode];
    const vertical = Number.isFinite(sample.x) && Number.isFinite(sample.y) && sample.y !== 0 && Math.abs(sample.y) > Math.abs(sample.x)*1.25 && units !== undefined;
    const eligible = context.enabled && !context.blocked && sample.surface !== null && !sample.modified && vertical && sample.cancelable && !sample.defaultPrevented && sample.momentum !== true;
    if(!this.burst) this.burst = {at:sample.at,revision:context.revision,surface:sample.surface,owned:eligible,draining:false,remainder:0,direction:0};
    const burst = this.burst; burst.at = sample.at;
    if(!burst.owned) return idle();
    if(burst.revision !== context.revision || !context.enabled || context.blocked || sample.surface !== burst.surface || sample.modified || sample.defaultPrevented || !sample.cancelable) this.cancel();
    // A prior consumer, zoom/pinch or inactive window retains its own input.
    if(sample.defaultPrevented || sample.modified || !sample.cancelable || !context.enabled) return idle(true);
    if(burst.draining) return {consume:true,delta:0,feedback:false,cancelled:true};
    // Modern runtimes expose momentum; older runtimes process indistinguishable
    // inertia as regular input. false does not signal a new physical contact.
    if(sample.momentum === true) return {consume:true,delta:0,feedback:false,cancelled:false};
    if(!vertical) { this.cancel(); return {consume:true,delta:0,feedback:false,cancelled:true}; }
    const direction = sample.y < 0 ? 1 : -1;
    if(direction !== burst.direction) burst.remainder = 0;
    burst.direction = direction;
    burst.remainder = Math.min(100,burst.remainder + Math.min(100,Math.abs(sample.y)/units));
    const steps = Math.floor(burst.remainder + 1e-9);
    burst.remainder = Math.max(0,burst.remainder-steps);
    const value = Number.isFinite(context.value) ? Math.min(100,Math.max(0,context.value)) : 0;
    const room = direction > 0 ? 100-value : value;
    // The controller clamps the actual intent, preserving fractional percentages.
    // Drop remainder/excess at endpoints so reversal never repays old debt.
    const delta = room <= 0 ? 0 : direction*steps;
    if(steps >= room) burst.remainder = 0;
    return {consume:true,delta,feedback:true,cancelled:false};
  }
}

/** The topmost element from elementFromPoint is authoritative, not a retained
 * WheelEvent target behind a panel/overlay. All reserved ancestors are excluded. */
export function volumeScrollSurface(target: EventTarget | null): VolumeScrollSurface | null {
  if(!(target instanceof Element)) return null;
  if(target.closest('[data-volume-excluded],[data-volume-dragging],[inert],[role="dialog"],[role="menu"]')) return null;
  const surface = target.closest<HTMLElement>('[data-volume-scroll]');
  const kind = surface?.dataset.volumeScroll;
  if(kind !== 'bar' && kind !== 'fullscreen') return null;
  if(kind === 'fullscreen' && target.closest('input,textarea,select,a,[contenteditable="true"],[role="slider"],button:not([data-volume-scroll-control])')) return null;
  return kind;
}

/** No polling at rest. ACKs update the displayed value without extending the
 * visual timeout; announcements wait for a quiet interval instead of each step. */
export class VolumeScrollFeedback {
  private hide: ReturnType<typeof setTimeout> | null = null;
  private announce: ReturnType<typeof setTimeout> | null = null;
  private visible = false;
  constructor(private hooks: {value:()=>number;visible:(visible:boolean)=>void;announce:(value:number|null)=>void},
    private clock: {set:typeof setTimeout;clear:typeof clearTimeout} = {set:setTimeout,clear:clearTimeout}) {}
  input(): void {
    this.visible = true; this.hooks.visible(true);
    if(this.hide !== null) this.clock.clear(this.hide);
    this.hide = this.clock.set(()=>{this.hide=null;this.visible=false;this.hooks.visible(false);},VOLUME_FEEDBACK_MS);
    this.confirmedChanged();
  }
  confirmedChanged(): void {
    if(!this.visible) return;
    if(this.announce !== null) this.clock.clear(this.announce);
    this.announce = this.clock.set(()=>{this.announce=null;this.hooks.announce(this.hooks.value());},VOLUME_SCROLL_QUIET_MS);
  }
  cancel(): void {
    if(this.hide !== null) this.clock.clear(this.hide);
    if(this.announce !== null) this.clock.clear(this.announce);
    this.hide=null;this.announce=null;this.visible=false;
    this.hooks.visible(false);this.hooks.announce(null);
  }
}
