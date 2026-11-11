import type { SidebarCollapseMode } from '$lib/appearance/preferences';

export type EffectiveSidebarMode = 'expanded' | 'icons' | 'hidden';
export interface NavigationPresentationInput { collapseMode: SidebarCollapseMode; collapsed: boolean; fullscreen: boolean }
export interface NavigationPresentation {
  /** Column that actually occupies space: 253/60 px (+12 floating) or none. */
  sidebar: EffectiveSidebarMode;
  /** Search, destinations and history capsules. Hidden while the player is fullscreen. */
  showTopNav: boolean;
  /** Control that brings the sidebar back; stays reachable (compact) in player fullscreen. */
  showReopen: boolean;
  /** Height of the draggable strip: 28 + 42 + 8 with the capsules, the native 32 px otherwise. */
  titlebarHeight: number;
}

export const NATIVE_TITLEBAR_HEIGHT = 32;
export const TOPNAV_TITLEBAR_HEIGHT = 78;

/** Single derivation of every layout state; callers never keep loose flags that could contradict it. */
export function deriveNavigationPresentation({ collapseMode, collapsed, fullscreen }: NavigationPresentationInput): NavigationPresentation {
  if (!collapsed) return { sidebar: 'expanded', showTopNav: false, showReopen: false, titlebarHeight: NATIVE_TITLEBAR_HEIGHT };
  if (collapseMode === 'icons') return { sidebar: 'icons', showTopNav: false, showReopen: false, titlebarHeight: NATIVE_TITLEBAR_HEIGHT };
  const showTopNav = !fullscreen;
  return { sidebar: 'hidden', showTopNav, showReopen: true, titlebarHeight: showTopNav ? TOPNAV_TITLEBAR_HEIGHT : NATIVE_TITLEBAR_HEIGHT };
}
