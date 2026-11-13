// Jam UI plumbing: the page provides the Jam (state store, actions, a small search) once and every
// surface reads it from context, so surfaces without a provider (tests, fixtures) simply show no Jam.
import { getContext, setContext } from 'svelte';
import type { Readable } from 'svelte/store';
import type { JamActions, JamViewState } from '$lib/jam/types';
import type { SongDto } from '$lib/types';

export interface JamUi {
  state: Readable<JamViewState>;
  actions: JamActions;
  /** Raw (never Jam-aware) YouTube Music song search used by the "pick another version" picker. */
  searchSongs: (query: string) => Promise<SongDto[]>;
}

export const JAM_UI_CONTEXT = Symbol('sideb.jam.ui');
export const provideJamUi = (ui: JamUi): void => { setContext(JAM_UI_CONTEXT, ui); };
export const useJamUi = (): JamUi | undefined => getContext<JamUi | undefined>(JAM_UI_CONTEXT);
