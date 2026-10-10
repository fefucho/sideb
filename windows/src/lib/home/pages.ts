import type { CollectionKind, HomeSettings } from './settings';
export function featuredSelectionKey(session: string, chip: string | null, kind: CollectionKind, settings: HomeSettings) {
  return JSON.stringify([session, chip, kind, kind === 'albums' ? settings.albumSources : settings.playlistSources]);
}
/** Preserve the actual anchor index while the column count changes, as HomeFeaturedView does. */
export function alignCollectionAnchor(anchor: number, previous: string[], next: string[]) {
  if (previous.length === next.length && previous.every((id,index)=>id === next[index])) return anchor;
  const index = next.indexOf(previous[anchor]);
  return index < 0 ? 0 : index;
}
/** Native scroll delta has the opposite sign to DOM deltaX; momentum phases aren't exposed by DOM. */
export class FeaturedWheelInput {
  private accumulated = 0; private handled = false; private timestamp = 0;
  consume(x:number,y:number,timestamp:number) {
    if (Math.abs(x)<=Math.abs(y)*1.4 || Math.abs(x)<=.5) return null;
    if (timestamp-this.timestamp>350) { this.accumulated=0; this.handled=false; }
    this.timestamp=timestamp;
    if(this.handled)return null;
    this.accumulated+=x;
    if(Math.abs(this.accumulated)<40)return null;
    this.handled=true;
    return this.accumulated>0?1:-1;
  }
}
