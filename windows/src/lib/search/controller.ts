import type { AlbumCardDto, BrowseCardDto, SearchResultsDto, SongDto } from '../types';

export type SearchMode = 'all' | 'songs' | 'videos' | 'albums' | 'artists' | 'playlists';
export type SearchRpc = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
export type SearchPartialError = 'global' | 'songs' | 'videos' | 'categories';

export interface SearchData {
  query: string;
  mode: SearchMode;
  lastSearchedQuery: string;
  songs: SongDto[];
  albums: AlbumCardDto[];
  top: BrowseCardDto[];
  topSongs: SongDto[];
  artists: BrowseCardDto[];
  playlists: BrowseCardDto[];
  videos: SongDto[];
  mixedResults?: SearchResultsDto | null;
  isLoading: boolean;
  error: string | null;
  partialErrors: Partial<Record<SearchPartialError, string>>;
  hasSearched: boolean;
  hasSearchedSongs: boolean;
  hasSearchedAlbums: boolean;
  hasSearchedArtists: boolean;
  hasSearchedPlaylists: boolean;
  hasSearchedVideos: boolean;
}

export function emptySearchData(): SearchData {
  return { query: '', mode: 'all', lastSearchedQuery: '', songs: [], albums: [], top: [], topSongs: [], artists: [], playlists: [], videos: [],
    mixedResults: null, isLoading: false, error: null, partialErrors: {}, hasSearched: false, hasSearchedSongs: false, hasSearchedAlbums: false,
    hasSearchedArtists: false, hasSearchedPlaylists: false, hasSearchedVideos: false };
}

function errorMessage(error: unknown) {
  if (error && typeof error === 'object' && 'message' in error && typeof error.message === 'string') return error.message;
  if (typeof error === 'string') return error;
  return 'Error al consultar el catálogo.';
}

const albumCard = (card: BrowseCardDto): AlbumCardDto => ({ id: card.id, title: card.title, subtitle: card.subtitle, thumbnail: card.thumbnail });

type CachedBase = { mixed: SearchResultsDto; songs: SongDto[]; videos: SongDto[] };

/** Search requests are guarded by account epoch and revision; each failed section leaves successful sections usable. */
export class SearchController {
  private data = emptySearchData();
  private generation = 0;
  private revision = 0;
  private activeHistory: boolean | null = null;
  private mixedResults: SearchResultsDto | null = null;
  private filteredSongs: SongDto[] = [];
  private filteredVideos: SongDto[] = [];
  private caches = new Map<string, Map<string, CachedBase>>();
  private categoryCaches = new Map<string, BrowseCardDto[]>();

  constructor(private rpc: SearchRpc, private publish: (data: SearchData) => void) {}

  private emit() {
    this.publish({ ...this.data, songs: [...this.data.songs], albums: [...this.data.albums], top: [...this.data.top], topSongs: [...this.data.topSongs],
      artists: [...this.data.artists], playlists: [...this.data.playlists], videos: [...this.data.videos], partialErrors: { ...this.data.partialErrors },
      mixedResults: this.mixedResults ? { ...this.mixedResults, top: [...this.mixedResults.top], topSongs: [...(this.mixedResults.topSongs ?? [])], songs: [...this.mixedResults.songs],
        albums: [...this.mixedResults.albums], artists: [...this.mixedResults.artists], playlists: [...this.mixedResults.playlists] } : null });
  }

  private context(recordHistory: boolean) { return `${this.generation}:${recordHistory ? 'account' : 'anonymous'}`; }
  private cache(recordHistory: boolean) {
    const key = this.context(recordHistory);
    let cache = this.caches.get(key);
    if (!cache) { cache = new Map(); this.caches.set(key, cache); }
    return cache;
  }

  private baseKey(query: string) { return query; }

  private categoryKey(query: string, mode: SearchMode, recordHistory = false) {
    return `${this.context(recordHistory)}\u0000${mode}\u0000${query}`;
  }

  setQuery(query: string) {
    if (query !== this.data.query) {
      ++this.revision;
      this.activeHistory = null;
      this.mixedResults = null;
      this.filteredSongs = [];
      this.filteredVideos = [];
      this.data = { ...emptySearchData(), query, mode: this.data.mode };
      this.emit();
    }
  }

  setMode(mode: SearchMode) {
    if (mode === this.data.mode) return;
    const pending = this.data.isLoading;
    const query = this.data.query.trim();
    ++this.revision;
    this.activeHistory = null;
    this.data = { ...this.data, mode, isLoading: false };
    if (mode === 'all' && this.mixedResults) {
      this.data.top = [...this.mixedResults.top];
      this.data.topSongs = [...(this.mixedResults.topSongs ?? [])];
      this.data.albums = this.mixedResults.albums.map(albumCard);
      this.data.artists = [...this.mixedResults.artists];
      this.data.playlists = [...this.mixedResults.playlists];
      this.data.songs = [...this.filteredSongs];
      this.data.videos = [...this.filteredVideos];
    }
    this.emit();
    if (pending && query) { void this.execute(query, mode, false); return; }
    if (query && this.data.lastSearchedQuery === query) {
      if (mode === 'all' && !this.mixedResults) void this.execute(query, mode, false);
      else void this.loadMode(query, mode);
    }
  }

  /** Invalidates pending replies when leaving search or changing account context. */
  invalidate() {
    ++this.revision;
    this.activeHistory = null;
    this.data = { ...this.data, isLoading: false };
    this.emit();
  }

  reset() {
    ++this.generation;
    ++this.revision;
    this.activeHistory = null;
    this.mixedResults = null;
    this.filteredSongs = [];
    this.filteredVideos = [];
    this.caches.clear();
    this.categoryCaches.clear();
    this.data = emptySearchData();
    this.emit();
  }

  restore(snapshot: SearchData) {
    ++this.revision;
    this.data = { ...emptySearchData(), ...snapshot, isLoading: false, partialErrors: { ...snapshot.partialErrors },
      songs: [...snapshot.songs], albums: [...snapshot.albums], top: [...snapshot.top], topSongs: [...(snapshot.topSongs ?? [])], artists: [...snapshot.artists],
      playlists: [...snapshot.playlists], videos: [...snapshot.videos] };
    this.mixedResults = snapshot.mixedResults ? { ...snapshot.mixedResults, top: [...snapshot.mixedResults.top], topSongs: [...(snapshot.mixedResults.topSongs ?? [])], songs: [...snapshot.mixedResults.songs],
      albums: [...snapshot.mixedResults.albums], artists: [...snapshot.mixedResults.artists], playlists: [...snapshot.mixedResults.playlists] } : null;
    this.filteredSongs = [...snapshot.songs];
    this.filteredVideos = [...snapshot.videos];
    this.emit();
    if (snapshot.isLoading && snapshot.lastSearchedQuery) void this.execute(snapshot.lastSearchedQuery, snapshot.mode, false);
  }

  async execute(targetQuery: string, mode: SearchMode = this.data.mode, recordHistory = true) {
    const query = targetQuery.trim();
    if (!query) return;
    if (this.data.isLoading && this.data.lastSearchedQuery === query && this.data.mode === mode && this.activeHistory === recordHistory) return;
    const generation = this.generation;
    const revision = ++this.revision;
    const current = () => generation === this.generation && revision === this.revision;
    const cache = this.cache(recordHistory);
    const cached = cache.get(this.baseKey(query));
    this.activeHistory = recordHistory;
    this.mixedResults = null;
    this.filteredSongs = [];
    this.filteredVideos = [];
    this.data = { ...emptySearchData(), query, mode, lastSearchedQuery: query, isLoading: true, hasSearched: true,
      hasSearchedSongs: true, hasSearchedVideos: true, hasSearchedAlbums: mode === 'albums',
      hasSearchedArtists: mode === 'artists', hasSearchedPlaylists: mode === 'playlists' };
    if (cached) {
      this.mixedResults = cached.mixed;
      this.filteredSongs = [...cached.songs];
      this.filteredVideos = [...cached.videos];
      this.data.top = [...cached.mixed.top];
      this.data.topSongs = [...(cached.mixed.topSongs ?? [])];
      this.data.songs = [...cached.songs];
      this.data.albums = cached.mixed.albums.map(albumCard);
      this.data.artists = [...cached.mixed.artists];
      this.data.playlists = [...cached.mixed.playlists];
      this.data.videos = [...cached.videos];
      if (['albums', 'artists', 'playlists'].includes(mode)) {
        const cards = this.categoryCaches.get(this.categoryKey(query, mode));
        if (cards) {
          if (mode === 'albums') this.data.albums = [...cards] as AlbumCardDto[];
          if (mode === 'artists') this.data.artists = [...cards];
          if (mode === 'playlists') this.data.playlists = [...cards];
        } else { this.data.isLoading = true; this.emit(); void this.loadMode(query, mode); return; }
      }
      this.data.isLoading = false;
      this.activeHistory = null;
      this.emit();
      return;
    }
    this.emit();

    // The mixed query records history once. Filtered requests never add another history entry.
    const globalPromise = this.rpc<SearchResultsDto>('search_all', { query, recordHistory });
    const songsPromise = this.rpc<SongDto[]>('search_songs', { query });
    const videosPromise = this.rpc<SongDto[]>('search_videos', { query });
    const categoryPromise = ['albums', 'artists', 'playlists'].includes(mode)
      ? this.rpc<BrowseCardDto[]>('search_cards', { query, category: mode })
      : null;
    const basePromise = Promise.allSettled([globalPromise, songsPromise, videosPromise]);
    const categorySettledPromise = categoryPromise ? Promise.allSettled([categoryPromise]) : Promise.resolve([]);
    const [baseResults, categoryResults] = await Promise.all([basePromise, categorySettledPromise]);
    const [globalResult, songsResult, videosResult] = baseResults;
    const categoryResult = categoryResults[0];
    if (!current()) return;
    const errors: SearchData['partialErrors'] = {};
    let global: SearchResultsDto | null = null;
    if (globalResult.status === 'fulfilled') global = globalResult.value;
    else { errors.global = errorMessage(globalResult.reason); this.data.error = errors.global; }
    if (global) {
      this.mixedResults = global;
      this.data.top = global.top;
      this.data.topSongs = [...(global.topSongs ?? [])];
      this.data.songs = global.songs;
      this.data.albums = global.albums.map(albumCard);
      this.data.artists = global.artists;
      this.data.playlists = global.playlists;
    }
    if (songsResult.status === 'fulfilled') { this.data.songs = songsResult.value; this.filteredSongs = [...songsResult.value]; }
    else {
      errors.songs = errorMessage(songsResult.reason);
      if (global) { this.data.songs = global.songs; this.filteredSongs = [...global.songs]; }
    }
    if (videosResult.status === 'fulfilled') { this.data.videos = videosResult.value; this.filteredVideos = [...videosResult.value]; }
    else errors.videos = errorMessage(videosResult.reason);
    if (categoryPromise && categoryResult) {
      if (categoryResult.status === 'fulfilled') {
        this.categoryCaches.set(this.categoryKey(query, mode), [...categoryResult.value]);
        if (mode === 'albums') this.data.albums = categoryResult.value as AlbumCardDto[];
        if (mode === 'artists') this.data.artists = categoryResult.value;
        if (mode === 'playlists') this.data.playlists = categoryResult.value;
      } else errors.categories = errorMessage(categoryResult.reason);
    }
    this.data.partialErrors = errors;
    this.data.hasSearched = true;
    this.data.hasSearchedSongs = true;
    this.data.hasSearchedVideos = true;
    if (mode === 'albums') this.data.hasSearchedAlbums = true;
    if (mode === 'artists') this.data.hasSearchedArtists = true;
    if (mode === 'playlists') this.data.hasSearchedPlaylists = true;
    if (!Object.keys(errors).length && global) cache.set(this.baseKey(query), { mixed: global, songs: [...this.filteredSongs], videos: [...this.filteredVideos] });
    this.data.isLoading = false;
    this.activeHistory = null;
    this.emit();
  }

  private async loadMode(query: string, mode: SearchMode) {
    if (mode === 'all' || mode === 'songs' || mode === 'videos') return;
    const generation = this.generation;
    const revision = this.revision;
    const cacheKey = this.categoryKey(query, mode);
    const cached = this.categoryCaches.get(cacheKey);
    if (cached) {
      if (mode === 'albums') { this.data.albums = [...cached] as AlbumCardDto[]; this.data.hasSearchedAlbums = true; }
      if (mode === 'artists') { this.data.artists = [...cached]; this.data.hasSearchedArtists = true; }
      if (mode === 'playlists') { this.data.playlists = [...cached]; this.data.hasSearchedPlaylists = true; }
      this.emit();
      return;
    }
    this.data.isLoading = true;
    this.emit();
    try {
      const result = await this.rpc<BrowseCardDto[]>('search_cards', { query, category: mode });
      if (generation !== this.generation || revision !== this.revision) return;
      this.categoryCaches.set(cacheKey, [...result]);
      const errors = { ...this.data.partialErrors }; delete errors.categories; this.data.partialErrors = errors;
      if (mode === 'albums') { this.data.albums = result as AlbumCardDto[]; this.data.hasSearchedAlbums = true; }
      if (mode === 'artists') { this.data.artists = result; this.data.hasSearchedArtists = true; }
      if (mode === 'playlists') { this.data.playlists = result; this.data.hasSearchedPlaylists = true; }
    } catch (error) {
      if (generation !== this.generation || revision !== this.revision) return;
      this.data.partialErrors = { ...this.data.partialErrors, categories: errorMessage(error) };
    } finally {
      if (generation === this.generation && revision === this.revision) { this.data.isLoading = false; this.emit(); }
    }
  }
}
