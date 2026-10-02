import type { AlbumDetailDto, ArtistDetailDto, BrowseCardDto } from '../types';

export type CatalogRpc = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
export type CatalogTarget = { id: string; params: string | null; title: string };
export interface CatalogData {
  album: AlbumDetailDto | null;
  albumId: string | null;
  albumLoading: boolean;
  albumError: string | null;
  artist: ArtistDetailDto | null;
  artistId: string | null;
  artistLoading: boolean;
  artistError: string | null;
  items: BrowseCardDto[];
  target: CatalogTarget | null;
  loading: boolean;
  error: string | null;
}

export function emptyCatalogData(): CatalogData {
  return { album: null, albumId: null, albumLoading: false, albumError: null,
    artist: null, artistId: null, artistLoading: false, artistError: null,
    items: [], target: null, loading: false, error: null };
}

function errorMessage(error: unknown, fallback: string): string {
  if (error && typeof error === 'object' && 'message' in error && typeof error.message === 'string') return error.message;
  if (typeof error === 'string') return error;
  return fallback;
}
function cloneAlbum(album: AlbumDetailDto | null): AlbumDetailDto | null {
  return album ? { ...album, items: album.items.map((item) => ({ ...item })),
    sections: album.sections.map((section) => ({ ...section, items: section.items.map((item) => ({ ...item })) })) } : null;
}
function cloneArtist(artist: ArtistDetailDto | null): ArtistDetailDto | null {
  return artist ? { ...artist, topSongs: artist.topSongs.map((item) => ({ ...item })),
    sections: artist.sections.map((section) => ({ ...section, items: section.items.map((item) => ({ ...item })) })) } : null;
}
function cloneData(data: CatalogData): CatalogData {
  return { ...data, album: cloneAlbum(data.album), artist: cloneArtist(data.artist),
    items: data.items.map((item) => ({ ...item })), target: data.target ? { ...data.target } : null };
}

/** Loads catalog destinations without coupling request lifetime to Svelte component state. */
export class CatalogController {
  private value = emptyCatalogData();
  private publish: (data: CatalogData) => void;
  private requestVersion = 0;
  private identity = 0;

  constructor(private rpc: CatalogRpc, publish: (data: CatalogData) => void) {
    this.publish = publish;
    this.emit();
  }

  get data(): CatalogData { return cloneData(this.value); }
  get identityVersion(): number { return this.identity; }
  captureIdentity(): number { return this.identity; }
  isCurrentIdentity(version: number): boolean { return version === this.identity; }

  private emit() { this.publish(this.data); }
  private cancelPending() {
    ++this.requestVersion;
    this.identity++;
    this.value.albumLoading = false;
    this.value.artistLoading = false;
    this.value.loading = false;
  }
  private startRequest() { return ++this.requestVersion; }
  private isCurrent(request: number) { return request === this.requestVersion; }

  /** Invalidates in-flight detail/grid loads but preserves already loaded view snapshots. */
  invalidate() {
    this.cancelPending();
    this.emit();
  }

  reset() {
    this.cancelPending();
    this.value = emptyCatalogData();
    this.emit();
  }

  /** Restored snapshots never retain loading flags for requests that have been invalidated. */
  restore(data: CatalogData) {
    this.cancelPending();
    this.value = { ...cloneData(data), albumLoading: false, artistLoading: false, loading: false };
    this.emit();
  }

  async openAlbum(id: string): Promise<void> {
    const browseId = id.trim();
    if (!browseId) return;
    this.cancelPending();
    const request = this.startRequest();
    this.value = { ...this.value, album: null, albumId: browseId, albumLoading: true, albumError: null };
    this.emit();
    try {
      const album = await this.rpc<AlbumDetailDto>('get_album', { browseId });
      if (this.isCurrent(request)) { this.value = { ...this.value, album: cloneAlbum(album) }; this.emit(); }
    } catch (error) {
      if (this.isCurrent(request)) { this.value = { ...this.value, albumError: errorMessage(error, 'Error al cargar el detalle del álbum.') }; this.emit(); }
    } finally {
      if (this.isCurrent(request)) { this.value = { ...this.value, albumLoading: false }; this.emit(); }
    }
  }

  async openArtist(id: string): Promise<void> {
    const browseId = id.trim();
    if (!browseId) return;
    this.cancelPending();
    const request = this.startRequest();
    this.value = { ...this.value, artist: null, artistId: browseId, artistLoading: true, artistError: null };
    this.emit();
    try {
      const artist = await this.rpc<ArtistDetailDto>('get_artist', { browseId });
      if (this.isCurrent(request)) { this.value = { ...this.value, artist: cloneArtist(artist) }; this.emit(); }
    } catch (error) {
      if (this.isCurrent(request)) { this.value = { ...this.value, artistError: errorMessage(error, 'No se pudo cargar el artista.') }; this.emit(); }
    } finally {
      if (this.isCurrent(request)) { this.value = { ...this.value, artistLoading: false }; this.emit(); }
    }
  }

  async openGrid(id: string, params: string | null, title: string): Promise<void> {
    const browseId = id.trim();
    if (!browseId) return;
    this.cancelPending();
    const request = this.startRequest();
    this.value = { ...this.value, items: [], target: { id: browseId, params, title }, loading: true, error: null };
    this.emit();
    try {
      const items = await this.rpc<BrowseCardDto[]>('get_browse_grid', { browseId, params });
      if (this.isCurrent(request)) { this.value = { ...this.value, items: items.map((item) => ({ ...item })) }; this.emit(); }
    } catch (error) {
      if (this.isCurrent(request)) { this.value = { ...this.value, error: errorMessage(error, 'No se pudo cargar la sección.') }; this.emit(); }
    } finally {
      if (this.isCurrent(request)) { this.value = { ...this.value, loading: false }; this.emit(); }
    }
  }

  updateAlbum(update: (album: AlbumDetailDto) => AlbumDetailDto): void {
    if (!this.value.album) return;
    this.value = { ...this.value, album: cloneAlbum(update(cloneAlbum(this.value.album)!)) };
    this.emit();
  }

  updateArtist(update: (artist: ArtistDetailDto) => ArtistDetailDto): void {
    if (!this.value.artist) return;
    this.value = { ...this.value, artist: cloneArtist(update(cloneArtist(this.value.artist)!)) };
    this.emit();
  }
}
