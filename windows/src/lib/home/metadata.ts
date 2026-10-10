import type { AlbumDetailDto, HomeItemDto, PlaylistDetailDto } from '../types';
import { metadataFor, type CollectionDetail, type FeaturedMetadata } from './collectionMetadata';
export type { FeaturedMetadata } from './collectionMetadata';
type Rpc = <T>(command: string, args: Record<string, unknown>) => Promise<T>;
/** One session's visible page, two requests in flight, and six cached details per collection kind. */
export class FeaturedMetadataController {
  private generation = 0; private active = 0;
  private visibleItems = new Map<string, HomeItemDto>(); private inFlight = new Set<string>();
  private albums = new Map<string, CollectionDetail>(); private playlists = new Map<string, CollectionDetail>(); private pending: HomeItemDto[] = [];
  constructor(private rpc: Rpc, private publish: (data: Record<string, FeaturedMetadata>) => void) {}
  private cache(item: HomeItemDto) { return item.kind === 'album' ? this.albums : this.playlists; }
  reset() { this.generation++; this.visibleItems.clear(); this.albums.clear(); this.playlists.clear(); this.pending = []; this.publish({}); }
  visible(items: HomeItemDto[]) {
    this.visibleItems.clear();
    for (const item of items.filter(item => ['album','playlist'].includes(item.kind) && item.id).slice(0,6)) {
      const key = `${item.kind}|${item.id}`; if (!this.visibleItems.has(key)) this.visibleItems.set(key,item);
    }
    this.pending = [...this.visibleItems.values()].filter(item => !this.cache(item).has(item.id) && !this.inFlight.has(`${this.generation}|${item.kind}|${item.id}`));
    for (const item of this.visibleItems.values()) { const cache=this.cache(item), value=cache.get(item.id); if (value) { cache.delete(item.id); cache.set(item.id,value); } }
    this.emit(); this.pump();
  }
  private emit() { this.publish(Object.fromEntries([...this.visibleItems].flatMap(([key,item]) => { const detail=this.cache(item).get(item.id); return detail ? [[key,metadataFor(item,detail)]] : []; }))); }
  private pump() {
    while (this.active < 2 && this.pending.length) {
      const item = this.pending.shift()!; const generation = this.generation;
      const key = `${item.kind}|${item.id}`; const requestKey = `${generation}|${key}`;
      this.inFlight.add(requestKey);
      this.active++;
      void this.fetch(item).then(value => {
        if (generation !== this.generation || !this.visibleItems.has(key)) return;
        const cache=this.cache(item); cache.set(item.id, value);
        while (cache.size > 6) cache.delete(cache.keys().next().value!);
        this.emit();
      }).catch(() => { /* Feed metadata remains valid when enrichment is unavailable. */ }).finally(() => { this.inFlight.delete(requestKey); this.active--; this.pump(); });
    }
  }
  private async fetch(item: HomeItemDto): Promise<CollectionDetail> {
    if (item.kind === 'album') {
      return this.rpc<AlbumDetailDto>('get_album', { browseId: item.id });
    }
    return this.rpc<PlaylistDetailDto>('get_playlist', { playlistId: item.id });
  }
}
