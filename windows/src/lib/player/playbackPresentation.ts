/**
 * Presentation of the playback surface: bottom bar, lateral "Now Playing" panel or
 * fullscreen. UI state only; queue, clock and occurrences stay authoritative in the
 * native player. Port of the final macOS `PlaybackPresentationState`,
 * `PlaybackSidebarLayout` and `PlaybackBarShellLayout`.
 */
export type PlaybackMode = 'bar' | 'sidebar' | 'fullscreen';
export type SidebarPanel = 'lyrics' | 'artwork' | 'queue';
export type FullscreenPanel = 'queue' | 'lyrics' | 'related';

export interface PlaybackPresentation {
  readonly mode: PlaybackMode;
  /** Surface fullscreen returns to when it collapses. */
  readonly origin: 'bar' | 'sidebar';
  readonly sidebarPanel: SidebarPanel;
}

export const initialPresentation = (): PlaybackPresentation => ({ mode: 'bar', origin: 'bar', sidebarPanel: 'artwork' });

/** Fullscreen sections that correspond to a lateral section (artwork has no fullscreen twin). */
export const fullscreenPanelFor = (panel: SidebarPanel, current: FullscreenPanel): FullscreenPanel =>
  panel === 'lyrics' ? 'lyrics' : panel === 'queue' ? 'queue' : current;

/** Section the lateral panel shows after fullscreen collapses back into it. */
export const sidebarPanelFor = (panel: FullscreenPanel): SidebarPanel =>
  panel === 'lyrics' ? 'lyrics' : panel === 'queue' ? 'queue' : 'artwork';

export function presentSidebar(state: PlaybackPresentation, panel?: SidebarPanel): PlaybackPresentation {
  return { ...state, mode: 'sidebar', sidebarPanel: panel ?? state.sidebarPanel };
}

export function closeSidebar(state: PlaybackPresentation): PlaybackPresentation {
  return state.mode === 'sidebar' ? { ...state, mode: 'bar' } : state;
}

/** Trigger / shortcut semantics: the same section closes it, another section retargets it. */
export function toggleSidebar(state: PlaybackPresentation, panel?: SidebarPanel): PlaybackPresentation {
  return state.mode === 'sidebar' && (panel === undefined || panel === state.sidebarPanel)
    ? closeSidebar(state)
    : presentSidebar(state, panel);
}

export function selectSidebarPanel(state: PlaybackPresentation, panel: SidebarPanel): PlaybackPresentation {
  return state.sidebarPanel === panel ? state : { ...state, sidebarPanel: panel };
}

/**
 * Entering fullscreen remembers where it came from; leaving restores that origin. When
 * the origin is the lateral panel, the section the user was reading in fullscreen is kept.
 */
export function setFullscreen(state: PlaybackPresentation, presented: boolean, panel: FullscreenPanel = 'queue'): PlaybackPresentation {
  if (presented) {
    if (state.mode === 'fullscreen') return state;
    return { ...state, mode: 'fullscreen', origin: state.mode === 'sidebar' ? 'sidebar' : 'bar' };
  }
  if (state.mode !== 'fullscreen') return state;
  return state.origin === 'sidebar'
    ? { ...state, mode: 'sidebar', sidebarPanel: sidebarPanelFor(panel) }
    : { ...state, mode: 'bar' };
}

/** The bar (with its outer trigger) is visible everywhere except while the lateral panel owns the controls. */
export const showsBar = (mode: PlaybackMode): boolean => mode !== 'sidebar';

/**
 * Only one surface may hold the duplicated transport controls. Both bar and panel are
 * mounted during a transition, so the retiring one is made inert from the first frame.
 */
export function interactiveSurfaces(mode: PlaybackMode): { bar: boolean; sidebar: boolean } {
  return { bar: showsBar(mode), sidebar: mode === 'sidebar' };
}

// MARK: - Geometry

export const SIDEBAR = {
  idealWidth: 380,
  minWidth: 350,
  maxWidth: 420,
  inset: 6,
  radius: 16,
  padding: 20,
  headerHeight: 58,
  /** Smallest page width that justifies reserving room instead of overlaying. */
  minContent: 480,
  bar: { button: 44, margin: 20, gap: 16, maxWidth: 820 },
} as const;

const finite = (value: number, fallback = 0) => (Number.isFinite(value) ? value : fallback);
const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

export const sidebarWidth = (requested: number = SIDEBAR.idealWidth): number =>
  clamp(finite(requested, SIDEBAR.idealWidth), SIDEBAR.minWidth, SIDEBAR.maxWidth);

/** Panel width plus the outer separation on both sides. */
export const sidebarReserve = (width: number = SIDEBAR.idealWidth): number => sidebarWidth(width) + SIDEBAR.inset * 2;

/**
 * Width taken from the page. When the page would fall below the useful minimum the panel
 * overlays instead: tables and navigation are neither squeezed nor expelled.
 */
export function contentReserve(input: { windowWidth: number; leftReserve: number; presented: boolean; width?: number }): number {
  const reserve = sidebarReserve(input.width);
  return input.presented && finite(input.windowWidth) - finite(input.leftReserve) - reserve >= SIDEBAR.minContent ? reserve : 0;
}

/** Height of the panel: window minus titlebar (window controls stay reachable) and both insets. */
export const panelHeight = (windowHeight: number, titlebarHeight: number): number =>
  Math.max(0, finite(windowHeight) - finite(titlebarHeight) - SIDEBAR.inset * 2);

// Footer/up-next geometry is shared with the side player contents (W4) and has a single definition.
export { showsUpcoming, sidebarFooterHeight as footerHeight, progressToTransportSpacing } from './sidebarLayout';

/** Bottom bar width: symmetric room on both sides keeps it centered while the outer trigger fits at the right. */
export const barWidth = (contentWidth: number): number =>
  Math.max(0, Math.min(SIDEBAR.bar.maxWidth, finite(contentWidth) - 2 * (SIDEBAR.bar.margin + SIDEBAR.bar.button + SIDEBAR.bar.gap)));

// MARK: - One shared transition progress (0 = bar, 1 = panel)

export const TRANSITION_MS = 380;
export const REDUCED_TRANSITION_MS = 160;

/**
 * Critically damped response (no overshoot) normalized to end exactly at 1: the "high damping,
 * no visible bounce" spring of the design, as a plain easing for the shared progress tween.
 */
export function dampedEase(t: number): number {
  const x = clamp(finite(t), 0, 1);
  if (x === 0 || x === 1) return x;
  const w = 9;
  const raw = (v: number) => 1 - (1 + w * v) * Math.exp(-w * v);
  return raw(x) / raw(1);
}

/** Retargeting from mid-flight takes time proportional to the distance left, never restarts from 0. */
export function retargetDuration(current: number, target: number, reduced: boolean): number {
  const full = reduced ? REDUCED_TRANSITION_MS : TRANSITION_MS;
  return Math.max(1, Math.round(full * clamp(Math.abs(finite(target) - finite(current)), 0, 1)));
}

/** Minimal surface of `svelte/motion` Tween used to drive the shared progress. */
export interface ProgressTween {
  readonly current: number;
  readonly target: number;
  set(value: number, options: { duration: number }): Promise<unknown>;
}

/**
 * Points the shared progress at the destination of `mode`. There is one progress value and one
 * destination; calling this again mid-flight retargets from the current value (reversal), so there
 * are no chained timers, callbacks or independent booleans that could show both surfaces.
 */
export function syncProgress(tween: ProgressTween, mode: PlaybackMode, reduced: boolean): void {
  const target = mode === 'sidebar' ? 1 : 0;
  if (tween.target === target) return; // already there, or already travelling there
  // Freeze at the animated position first: the running task would otherwise advance one more frame
  // towards the old destination before the new one takes over.
  if (tween.current !== tween.target) void tween.set(tween.current, { duration: 0 });
  void tween.set(target, { duration: retargetDuration(tween.current, target, reduced) });
}

export interface SurfaceStyle { opacity: number; x: number; y: number; scale: number }

const phase = (p: number, from: number, to: number) => clamp((p - from) / (to - from), 0, 1);
const smooth = (v: number) => v * v * (3 - 2 * v);

/** Opening: the bar drops ~20px, shrinks to 0.97 and fades in the first stretch. Reduced motion: opacity only. */
export function barSurface(progress: number, reduced: boolean): SurfaceStyle {
  const p = clamp(finite(progress), 0, 1);
  if (reduced) return { opacity: 1 - p, x: 0, y: 0, scale: 1 };
  return { opacity: 1 - smooth(phase(p, 0, 0.45)), x: 0, y: 20 * p, scale: 1 - 0.03 * p };
}

/** Opening: the panel enters from the right over ~32px with progressive opacity, overlapping the bar. */
export function panelSurface(progress: number, reduced: boolean): SurfaceStyle {
  const p = clamp(finite(progress), 0, 1);
  if (reduced) return { opacity: p, x: 0, y: 0, scale: 1 };
  return { opacity: smooth(phase(p, 0.1, 0.7)), x: 32 * (1 - p), y: 0, scale: 1 };
}

export const surfaceTransform = (style: SurfaceStyle): string =>
  style.x === 0 && style.y === 0 && style.scale === 1
    ? 'none'
    : `translate3d(${style.x.toFixed(2)}px, ${style.y.toFixed(2)}px, 0) scale(${style.scale.toFixed(4)})`;
