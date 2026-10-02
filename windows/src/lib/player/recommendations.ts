import type { AlbumDetailDto, ArtistDetailDto, BrowseCardDto, PlaybackTrackDto, SongDto } from '../types';

export type RecommendationsRpc = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
export interface RecommendedData {
  loadedVideoId: string;
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
function identity(track: PlaybackTrackDto | null): string {
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

/** Lazy recommendations only; playback and the native queue remain authoritative. */
export class RecommendationsController {
  private track: PlaybackTrackDto | null = null;
  private state = emptyRecommendationsSnapshot();
  private revision = 0;
  private reloadCount = 0;
  private loadedIdentity = '';
  private pending: Promise<void> | null = null;

  constructor(private rpc: RecommendationsRpc, private publish: (snapshot: RecommendationsSnapshot) => void) { this.emit(); }
  get snapshot(): RecommendationsSnapshot { return { ...this.state, data: this.state.data ? cloneData(this.state.data) : null }; }
  private emit() { this.publish(this.snapshot); }

  setTrack(track: PlaybackTrackDto | null): void {
    const changed = identity(track) !== identity(this.track);
    this.track = track ? { ...track, artistRuns: track.artistRuns?.map(run => ({ ...run })) } : null;
    if (changed) {
      this.revision++; this.pending = null; this.loadedIdentity = ''; this.reloadCount = 0;
      this.state = emptyRecommendationsSnapshot(); this.emit();
    } else if (this.state.data && track) {
      // Radio can enrich display metadata without changing the song or issuing more requests.
      let enriched = false;
      if (!this.state.data.artistName && track.artists) { this.state.data.artistName = track.artists; enriched = true; }
      if (!this.state.data.albumTitle && track.album) { this.state.data.albumTitle = track.album; enriched = true; }
      if (enriched) this.emit();
    }
  }

  load(forceRefresh = false): Promise<void> {
    if (!this.track?.videoId.trim()) return Promise.resolve();
    const key = identity(this.track);
    if (!forceRefresh && this.pending) return this.pending;
    // An error is retried explicitly; playback progress must not repeatedly hit the provider.
    if (!forceRefresh && this.loadedIdentity === key) return Promise.resolve();
    const track = { ...this.track };
    const revision = ++this.revision;
    this.reloadCount = forceRefresh ? this.reloadCount + 1 : 0;
    const rotation = this.reloadCount;
    this.state = { ...this.state, loading: true, error: null }; this.emit();
    const load = this.fetch(track, revision, key, rotation);
    this.pending = load;
    return load;
  }

  private async fetch(track: PlaybackTrackDto, revision: number, key: string, rotation: number): Promise<void> {
    const requests = await Promise.allSettled([
      this.rpc<SongDto[]>('get_related_tracks', { videoId: track.videoId }),
      this.rpc<BrowseCardDto[]>('get_related_artists', { videoId: track.videoId }),
      track.artistId ? this.rpc<ArtistDetailDto>('get_artist', { browseId: track.artistId }) : Promise.resolve(null),
      track.albumId ? this.rpc<AlbumDetailDto>('get_album', { browseId: track.albumId }) : Promise.resolve(null),
    ]);
    if (revision !== this.revision || identity(this.track) !== key) return;
    const [similarResult, artistsResult, artistResult, albumResult] = requests;
    const previous = this.state.data?.loadedVideoId === track.videoId ? this.state.data : null;
    const artist = artistResult.status === 'fulfilled' ? artistResult.value : null;
    const album = albumResult.status === 'fulfilled' ? albumResult.value : null;
    let similarSongs = (similarResult.status === 'fulfilled' ? similarResult.value : previous?.similarSongs ?? []).filter(song => song.videoId !== track.videoId);
    if (rotation && similarSongs.length > 4) {
      const offset = (rotation * 4) % similarSongs.length;
      similarSongs = [...similarSongs.slice(offset), ...similarSongs.slice(0, offset)];
    }
    const related = artistsResult.status === 'fulfilled' ? artistsResult.value.filter(card => card.kind.toLowerCase() === 'artist') : previous?.relatedArtists ?? [];
    const data: RecommendedData = {
      loadedVideoId: track.videoId,
      artistName: artist?.name || previous?.artistName || this.track?.artists || null,
      artistBrowseId: track.artistId ?? null,
      artistSongs: (artist?.topSongs ?? (artistResult.status === 'rejected' ? previous?.artistSongs : []) ?? []).filter(song => song.videoId !== track.videoId)
        .map(song => artistSong(song, artist, track.artistId ?? null)),
      albumTitle: album?.title || previous?.albumTitle || this.track?.album || null,
      albumBrowseId: track.albumId ?? null,
      albumSongs: (album?.items ?? (albumResult.status === 'rejected' ? previous?.albumSongs : []) ?? []).filter(song => song.videoId !== track.videoId)
        .map(song => albumSong(song, album, track.albumId ?? null)),
      similarSongs,
      relatedArtists: related.length ? related : artistFallback(artist),
    };
    // Partial failures retain usable shelves. Provider exception text may contain URLs, so use a public message.
    const error = requests.some(result => result.status === 'rejected')
      ? 'No se pudieron cargar todas las recomendaciones. Podés reintentar.' : null;
    this.loadedIdentity = key; this.pending = null;
    this.state = { loading: false, error, data }; this.emit();
  }

  reset(): void {
    this.revision++; this.pending = null; this.track = null; this.loadedIdentity = ''; this.reloadCount = 0;
    this.state = emptyRecommendationsSnapshot(); this.emit();
  }
  dispose(): void { this.reset(); }
}
