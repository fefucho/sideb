import type { SearchResultsDto, SearchSuggestionsDto } from '../types';
import type { SearchRpc } from './controller';

export interface SearchPreviewData {
  query: string;
  associatedQuery: string;
  results: SearchResultsDto | null;
  queries?: string[];
  entries?: import('../types').SearchSuggestionEntryDto[];
  isLoading: boolean;
  error: string | null;
}

export interface SearchPreviewScheduler {
  setTimeout(callback: () => void, delay: number): ReturnType<typeof setTimeout>;
  clearTimeout(timer: ReturnType<typeof setTimeout>): void;
}

export function emptySearchPreviewData(): SearchPreviewData {
  return { query: '', associatedQuery: '', results: null, queries: [], isLoading: false, error: null };
}

function errorMessage(error: unknown): string {
  if (error && typeof error === 'object' && 'message' in error && typeof error.message === 'string') return error.message;
  if (typeof error === 'string') return error;
  return 'No se pudieron cargar los resultados rápidos.';
}

/** Debounced, history-free search state used only by the quick preview. */
export class SearchPreviewController {
  private data = emptySearchPreviewData();
  private generation = 0;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private disposed = false;
  private cache = new Map<string, {at:number; value:SearchSuggestionsDto}>();

  constructor(private invoke: SearchRpc, private onChange: (data: SearchPreviewData) => void,
    private scheduler: SearchPreviewScheduler = {
      setTimeout: (callback, delay) => globalThis.setTimeout(callback, delay),
      clearTimeout: timer => globalThis.clearTimeout(timer),
    }) {}

  private emit() {
    if (!this.disposed) this.onChange({ ...this.data, queries:[...(this.data.queries??[])], results: this.data.results ? { ...this.data.results,
      top: [...this.data.results.top], topSongs: [...(this.data.results.topSongs ?? [])], songs: [...this.data.results.songs], albums: [...this.data.results.albums],
      artists: [...this.data.results.artists], playlists: [...this.data.results.playlists] } : null });
  }

  setQuery(query: string) {
    if (this.disposed) return;
    const trimmed = query.trim();
    if (query === this.data.query && (this.timer !== null || this.data.isLoading)) return;
    this.clearTimer();
    const generation = ++this.generation;
    const cached = this.cache.get(trimmed);
    if (cached && Date.now()-cached.at < 30_000) {
      this.data = {query,associatedQuery:trimmed,results:cached.value.results,queries:[...cached.value.queries],isLoading:false,error:null};
      this.emit(); return;
    }
    this.data = { ...this.data, query, error: null, isLoading: false };
    if (!trimmed) {
      this.data = emptySearchPreviewData();
      this.emit();
      return;
    }
    if (this.data.associatedQuery !== trimmed) {
      this.data = { ...this.data, associatedQuery: '', results: null, queries: [] };
    }
    this.emit();
    this.timer = this.scheduler.setTimeout(() => {
      this.timer = null;
      if (!this.disposed && generation === this.generation) void this.load(trimmed, generation);
    }, 250);
  }

  private async load(query: string, generation: number) {
    this.data = { ...this.data, isLoading: true, error: null };
    this.emit();
    try {
      const suggestions = await this.invoke<SearchSuggestionsDto>('search_suggestions', { query });
      if (this.disposed || generation !== this.generation) return;
      this.cache.delete(query);
      this.cache.set(query,{at:Date.now(),value:suggestions});
      while(this.cache.size>32)this.cache.delete(this.cache.keys().next().value!);
      this.data = { ...this.data, associatedQuery: query, results:suggestions.results, queries:[...suggestions.queries], isLoading: false, error: null };
    } catch (error) {
      if (this.disposed || generation !== this.generation) return;
      this.data = { ...this.data, associatedQuery: query, results: null, isLoading: false, error: errorMessage(error) };
    }
    this.emit();
  }

  /** Invalidates the current debounce/request while retaining the draft and preview. */
  cancel() {
    if (this.disposed) return;
    this.clearTimer();
    ++this.generation;
    if (this.data.isLoading) { this.data = { ...this.data, isLoading: false }; this.emit(); }
  }

  reset() {
    if (this.disposed) return;
    this.clearTimer();
    ++this.generation;
    this.cache.clear();
    this.data = emptySearchPreviewData();
    this.emit();
  }

  dispose() {
    if (this.disposed) return;
    this.clearTimer();
    ++this.generation;
    this.disposed = true;
  }

  private clearTimer() {
    if (this.timer !== null) this.scheduler.clearTimeout(this.timer);
    this.timer = null;
  }
}
