import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';

export interface AnimatedArtworkRuntimeState {
  visible: boolean;
  minimized: boolean;
  cloaked: boolean;
  powerSaver: boolean;
  memoryPressure: boolean;
}
export const initialAnimatedArtworkRuntimeState: AnimatedArtworkRuntimeState = {
  visible: true, minimized: false, cloaked: false, powerSaver: false, memoryPressure: false,
};
/** A single subscription for the mounted fullscreen owner; no focus heuristic or timer. */
export function observeAnimatedArtworkRuntime(publish: (state: AnimatedArtworkRuntimeState) => void): () => void {
  let disposed = false;
  let revision = 0;
  let unlisten: (() => void) | undefined;
  void listen<AnimatedArtworkRuntimeState>('animated-artwork-runtime-changed', event => {
    revision++;
    if (!disposed) publish(event.payload);
  }).then(async stop => {
    if (disposed) { stop(); return; }
    unlisten = stop;
    const captured = revision;
    const state = await invoke<AnimatedArtworkRuntimeState>('get_animated_artwork_runtime_state');
    if (!disposed && captured === revision) publish(state);
  }).catch(() => {});
  return () => { disposed = true; unlisten?.(); };
}
