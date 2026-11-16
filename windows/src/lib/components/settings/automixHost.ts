import type { AutomixController, AutomixSnapshot } from '$lib/player/automix';

/** Lets the Automix section of Settings reach the page's controller without threading props through Home. */
export const AUTOMIX_HOST_CONTEXT = Symbol('automix-host');
export interface AutomixHost {
  readonly snapshot: AutomixSnapshot;
  readonly controller: AutomixController;
}
