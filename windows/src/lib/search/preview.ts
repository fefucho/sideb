import type { SearchResultsDto } from '../types';
import type { SearchRpc } from './controller';

export interface SearchPreviewData {
  query: string;
  associatedQuery: string;
  results: SearchResultsDto | null;
  isLoading: boolean;
  error: string | null;
}

export interface SearchPreviewScheduler {
  setTimeout(callback: () => void, delay: number): ReturnType<typeof setTimeout>;
  clearTimeout(timer: ReturnType<typeof setTimeout>): void;
}

export function emptySearchPreviewData(): SearchPreviewData {
  return { query: '', associatedQuery: '', results: null, isLoading: false, error: null };
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

  constructor(private invoke: SearchRpc, private onChange: (data: SearchPreviewData) => void,
    private scheduler: SearchPreviewScheduler = {
      setTimeout: (callback, delay) => globalThis.setTimeout(callback, delay),
      clearTimeout: timer => globalThis.clearTimeout(timer),
    }) {}

  private emit() {
    if (!this.disposed) this.onChange({ ...this.data, results: this.data.results ? { ...this.data.results,
      top: [...this.data.results.top], topSongs: [...(this.data.results.topSongs ?? [])], songs: [...this.data.results.songs], albums: [...this.data.results.albums],
      artists: [...this.data.results.artists], playlists: [...this.data.results.playlists] } : null });
  }

  setQuery(query: string) {
    if (this.disposed) return;
    const trimmed = query.trim();
    if (query === this.data.query && (this.timer !== null || this.data.isLoading
      || this.data.associatedQuery === trimmed && this.data.results !== null)) return;
    if (trimmed && this.data.associatedQuery === trimmed && this.data.results !== null) {
      this.data = { ...this.data, query, error: null, isLoading: false };
      this.emit();
      return;
    }
    this.clearTimer();
    const generation = ++this.generation;
    this.data = { ...this.data, query, error: null, isLoading: false };
    if (!trimmed) {
      this.data = emptySearchPreviewData();
      this.emit();
      return;
    }
    if (this.data.associatedQuery !== trimmed) {
      this.data = { ...this.data, associatedQuery: '', results: null };
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
      const results = await this.invoke<SearchResultsDto>('search_all', { query, recordHistory: false });
      if (this.disposed || generation !== this.generation) return;
      this.data = { ...this.data, associatedQuery: query, results, isLoading: false, error: null };
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
