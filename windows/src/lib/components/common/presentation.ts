/** Presentation visibility is independent of playback and geometric intersection.
 * The root excludes its covered shell while fullscreen panels remain foreground.
 */
export const PRESENTATION_CONTEXT = Symbol('presentation');
export interface PresentationService {
  active(element: Element | undefined): boolean;
}
