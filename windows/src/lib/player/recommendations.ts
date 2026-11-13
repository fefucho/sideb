import type { AlbumDetailDto, ArtistDetailDto, BrowseCardDto, PlaybackTrackDto, SongDto } from '../types';

export type RecommendationsRpc = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
export interface RecommendedData {
  loadedVideoId: string;
  contextKey?: string;
  requestIdentity?: string;
  artistName: string | null;
  artistBrowseId: string | null;
  artistSongs: SongDto[];
  albumTitle: string | null;
  albumBrowseId: string | null;
  albumSongs: SongDto[];
  similarSongs: SongDto[];
  relatedArtists: BrowseCardDto[];
}
export interface RecommendationsSnapshot { loading: boolean; error: string | null; data: RecommendedData | null }
export const emptyRecommendationsSnapshot = (): RecommendationsSnapshot => ({ loading: false, error: null, data: null });
const cloneSong = (song: SongDto): SongDto => ({ ...song, artistRuns: song.artistRuns?.map(run => ({ ...run })) });
function cloneData(data: RecommendedData): RecommendedData {
  return { ...data, artistSongs: data.artistSongs.map(cloneSong), albumSongs: data.albumSongs.map(cloneSong),
    similarSongs: data.similarSongs.map(cloneSong), relatedArtists: data.relatedArtists.map(card => ({ ...card, artistRuns: card.artistRuns?.map(run => ({ ...run })) })) };
}
export function recommendationIdentity(track: PlaybackTrackDto | null): string {
  return track ? JSON.stringify([track.videoId, track.artistId ?? null, track.albumId ?? null]) : '';
}
function artistFallback(detail: ArtistDetailDto | null): BrowseCardDto[] {
  if (!detail) return [];
  let cards: BrowseCardDto[] = [];
  for (const section of detail.sections) {
    if (/fans|similares|similar|like/i.test(section.title)) cards.push(...section.items.filter(card => card.kind.toLowerCase() === 'artist'));
    else if (!cards.length) cards.push(...section.items.filter(card => card.kind.toLowerCase() === 'artist'));
  }
  return cards;
}
function artistSong(song: SongDto, detail: ArtistDetailDto | null, artistId: string | null): SongDto {
  const result = cloneSong(song);
  result.artistId ||= artistId;
  // Only a matching single-artist name can safely reuse that endpoint as an individual credit.
  if (!result.artistRuns?.length && detail?.name && result.artists === detail.name && artistId) {
    result.artistRuns = [{ text: detail.name, id: artistId }];
  }
  return result;
}
function albumSong(song: SongDto, detail: AlbumDetailDto | null, albumId: string | null): SongDto {
  const result = cloneSong(song);
  result.albumId ||= detail?.browseId || albumId;
  result.album ||= detail?.title || null;
  result.artistId ||= detail?.artistId || null;
  if (!result.artistRuns?.length && detail?.artist && (!result.artists || result.artists === detail.artist)) {
    result.artists ||= detail.artist;
    result.artistRuns = detail.artistRuns?.map(run => ({ ...run })) ?? [];
  }
  return result;
}

export interface RecommendationContext {
  artistId?: string | null;
  albumId?: string | null;
}

/** Lazy recommendations only; playback and the native queue remain authoritative. */
export class RecommendationsController {
  private track: PlaybackTrackDto | null = null;
  private context: RecommendationContext = {};
  private state = emptyRecommendationsSnapshot();
  private revision = 0;
  private reloadCount = 0;
  private loadedIdentity = '';
  private pending: Promise<void> | null = null;
  private contextRevision=0;

  constructor(private rpc: RecommendationsRpc, private publish: (snapshot: RecommendationsSnapshot) => void) { this.emit(); }
  get snapshot(): RecommendationsSnapshot { return { ...this.state, data: this.state.data ? cloneData(this.state.data) : null }; }
  private emit() { this.publish(this.snapshot); }
  private effectiveContext(track: PlaybackTrackDto | null, context: RecommendationContext) {
    return {
      artistId: track?.artistId || context.artistId || null,
      albumId: track?.albumId || context.albumId || null,
    };
  }
  private effectiveIdentity(track: PlaybackTrackDto | null, context: RecommendationContext): string {
    if (!track) return '';
    const resolved = this.effectiveContext(track, context);
    return JSON.stringify([track.videoId, resolved.artistId, resolved.albumId]);
  }

  setTrack(track: PlaybackTrackDto | null, context: RecommendationContext = {}): void {
    const nextContext: RecommendationContext = {
      artistId: context.artistId ?? null,
      albumId: context.albumId ?? null,
    };
    const changed = this.effectiveIdentity(track, nextContext) !== this.effectiveIdentity(this.track, this.context)
      || recommendationIdentity(track) !== recommendationIdentity(this.track);
    this.track = track ? { ...track, artistRuns: track.artistRuns?.map(run => ({ ...run })) } : null;
    this.context = nextContext;
    if (changed) {
      this.contextRevision++;this.revision++; this.pending = null; this.loadedIdentity = ''; this.reloadCount = 0;
      this.state = emptyRecommendationsSnapshot(); this.emit();
    } else if (this.state.data && track) {
      // Radio can enrich display metadata without changing the song or issuing more requests.
      let enriched = false;
      if (!this.state.data.artistName && track.artists) { this.state.data.artistName = track.artists; enriched = true; }
      if (!this.state.data.albumTitle && track.album) { this.state.data.albumTitle = track.album; enriched = true; }
      if (enriched) this.emit();
    }
  }

  removeSong(videoId:string) {
    if(!this.state.data)return;
    for(const field of ['artistSongs','albumSongs','similarSongs'] as const)this.state.data[field]=this.state.data[field].filter(song=>song.videoId!==videoId);
    this.emit();
  }
  load(forceRefresh = false): Promise<void> {
    if (!this.track?.videoId.trim()) return Promise.resolve();
    const effectiveKey = this.effectiveIdentity(this.track, this.context);
    if (!forceRefresh && this.pending) return this.pending;
    // An error is retried explicitly; playback progress must not repeatedly hit the provider.
    if (!forceRefresh && this.loadedIdentity === effectiveKey) return Promise.resolve();
    const track = { ...this.track };
    const context = { ...this.context };
    const requestKey = recommendationIdentity(track);
    const revision = ++this.revision;
    this.reloadCount = forceRefresh ? this.reloadCount + 1 : 0;
    const rotation = this.reloadCount;
    this.state = { ...this.state, loading: true, error: null }; this.emit();
    const load = this.fetch(track, context, revision, requestKey, effectiveKey, rotation);
    this.pending = load;
    return load;
  }

  private async fetch(
    track: PlaybackTrackDto,
    context: RecommendationContext,
    revision: number,
    requestKey: string,
    effectiveKey: string,
    rotation: number,
  ): Promise<void> {
    const resolved = this.effectiveContext(track, context);
    const contextKey = JSON.stringify([this.contextRevision, requestKey]);
    const isCurrent = () => revision === this.revision && this.effectiveIdentity(this.track, this.context) === effectiveKey;
    const baseData = (): RecommendedData => {
      const existing = this.state.data?.loadedVideoId === track.videoId ? this.state.data : null;
      if (existing) {
        return {
          ...existing,
          contextKey,
          requestIdentity: requestKey,
          artistBrowseId: resolved.artistId,
          albumBrowseId: resolved.albumId,
        };
      }
      return {
        loadedVideoId: track.videoId,
        contextKey,
        requestIdentity: requestKey,
        artistName: this.track?.artists || null,
        artistBrowseId: resolved.artistId,
        artistSongs: [],
        albumTitle: this.track?.album || null,
        albumBrowseId: resolved.albumId,
        albumSongs: [],
        similarSongs: [],
        relatedArtists: [],
      };
    };
    const commitShelf = (update: (data: RecommendedData) => void) => {
      if (!isCurrent()) return;
      const next = baseData();
      update(next);
      this.state = { ...this.state, data: next };
      this.emit();
    };

    let artistRelatedFallback: BrowseCardDto[] = [];
    let artistCardsFulfilled: BrowseCardDto[] | null = null;

    const similarPromise = this.rpc<SongDto[]>('get_related_tracks', { videoId: track.videoId }).then(items => {
      let similarSongs = items.filter(song => song.videoId !== track.videoId);
      if (rotation && similarSongs.length > 4) {
        const offset = (rotation * 4) % similarSongs.length;
        similarSongs = [...similarSongs.slice(offset), ...similarSongs.slice(0, offset)];
      }
      commitShelf(data => { data.similarSongs = similarSongs; });
    });

    const artistsPromise = this.rpc<BrowseCardDto[]>('get_related_artists', { videoId: track.videoId }).then(cards => {
      const related = cards.filter(card => card.kind.toLowerCase() === 'artist');
      artistCardsFulfilled = related;
      commitShelf(data => {
        data.relatedArtists = related.length ? related : artistRelatedFallback;
      });
    });

    const artistPromise = (resolved.artistId
      ? this.rpc<ArtistDetailDto>('get_artist', { browseId: resolved.artistId })
      : Promise.resolve(null)).then(artist => {
      if (!artist) return;
      artistRelatedFallback = artistFallback(artist);
      const artistSongs = artist.topSongs
        .filter(song => song.videoId !== track.videoId)
        .map(song => artistSong(song, artist, resolved.artistId));
      commitShelf(data => {
        if (artist.name) data.artistName = artist.name;
        data.artistSongs = artistSongs;
        if (!(artistCardsFulfilled?.length) && !data.relatedArtists.length && artistRelatedFallback.length) {
          data.relatedArtists = artistRelatedFallback;
        }
      });
    });

    const albumPromise = (resolved.albumId
      ? this.rpc<AlbumDetailDto>('get_album', { browseId: resolved.albumId })
      : Promise.resolve(null)).then(album => {
      if (!album) return;
      const albumSongs = album.items
        .filter(song => song.videoId !== track.videoId)
        .map(song => albumSong(song, album, resolved.albumId));
      commitShelf(data => {
        if (album.title) data.albumTitle = album.title;
        data.albumSongs = albumSongs;
      });
    });

    const requests = await Promise.allSettled([similarPromise, artistsPromise, artistPromise, albumPromise]);
    if (!isCurrent()) return;
    const data = baseData();
    // Partial failures retain usable shelves. Provider exception text may contain URLs, so use a public message.
    const error = requests.some(result => result.status === 'rejected')
      ? 'No se pudieron cargar todas las recomendaciones. Podés reintentar.' : null;
    this.loadedIdentity = effectiveKey; this.pending = null;
    this.state = { loading: false, error, data }; this.emit();
  }

  /** Stop accepting a hidden panel's requests without losing useful cached shelves. */
  suspend(): void {
    if(!this.pending&&!this.state.loading)return;
    ++this.revision;this.pending=null;
    this.state={...this.state,loading:false};this.emit();
  }
  reset(): void {
    this.contextRevision++;this.revision++; this.pending = null; this.track = null; this.context = {}; this.loadedIdentity = ''; this.reloadCount = 0;
    this.state = emptyRecommendationsSnapshot(); this.emit();
  }
  dispose(): void { this.reset(); }
}
