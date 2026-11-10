import { readable, derived, type Readable } from 'svelte/store';
import { visualProviderApi, type VisualProviderApi } from './api';
import type { VisualProviderState } from './types';

/**
 * Live provider state. Subscribing starts one query + one event listener; the last unsubscribe
 * stops them. `null` until the host answers (or when it is unavailable, e.g. in a browser preview).
 */
export function createVisualProviderStore(api: VisualProviderApi = visualProviderApi): Readable<VisualProviderState | null> {
  return readable<VisualProviderState | null>(null, set => {
    let active = true;
    let latestRevision = -1;
    const apply = (state: VisualProviderState) => {
      if (!active || state.revision < latestRevision) return;
      latestRevision = state.revision;
      set(state);
    };
    let unlisten: (() => void) | undefined;
    api.onChanged(apply).then(stop => { if (active) unlisten = stop; else stop(); }).catch(() => undefined);
    api.state().then(apply).catch(() => undefined);
    return () => { active = false; unlisten?.(); };
  });
}

export const visualProviderState = createVisualProviderStore();
/** True when the provider is installed, signed in and switched on: the sidebar may use it as a fallback. */
export const visualProviderEnabled = derived(visualProviderState, state => !!state?.enabled && !!state.installed && state.hasCredential);
/** Per-track identity component (Apple's `visualProviderSalt`); changes whenever the configuration changes. */
export const visualProviderIdentitySalt = derived(visualProviderState, state => state?.identitySalt ?? null);
