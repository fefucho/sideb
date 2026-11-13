// Public surface of the Jam feature for the app shell. Signatures are the contract with the UI
// (windows/plans/PLAN-028-spotify-jam.md); the logic lives in ./session and its siblings.
import type { Readable } from 'svelte/store';
import type { PlayerListen, PlayerRpc } from '../player/controller';
import type { PlaybackStateDto } from '../types';
import { createSession } from './session';
import type { JamActions, JamScheduler, JamViewState } from './types';

export * from './types';

export interface JamDeps {
  /** Raw Tauri invoke. */
  rpc: PlayerRpc;
  listen: PlayerListen;
  /** Epoch ms; defaults to `Date.now`. */
  now?: () => number;
  /** Timers; defaults to the global ones. Injected by tests. */
  schedule?: JamScheduler;
}

export interface Jam {
  state: Readable<JamViewState>;
  actions: JamActions;
  /**
   * Jam-aware RPC for every controller that sends playback or queue commands. Outside a Jam it is
   * the raw RPC. Inside one, transport and queue edits go to the Jam and anything that would start
   * other music is held until the user confirms leaving (`state.pendingExit`).
   */
  rpc: PlayerRpc;
  /** Feed every playback snapshot the app receives. */
  onPlaybackState(state: PlaybackStateDto): void;
  destroy(): void;
}

export function createJam(deps: JamDeps): Jam {
  return createSession(deps);
}
