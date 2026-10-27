import type { SearchResultsDto, SearchSuggestionsPageDto, SearchSuggestionEntryDto } from '../types';
import type { SearchRpc } from './controller';

export interface SearchPreviewData {
  query: string;
  associatedQuery: string;
  results: SearchResultsDto | null;
  queries?: string[];
  entries?: SearchSuggestionEntryDto[];
  isLoading: boolean;
  error: string | null;
}

export interface SearchPreviewScheduler {
  setTimeout(callback: () => void, delay: number): ReturnType<typeof setTimeout>;
  clearTimeout(timer: ReturnType<typeof setTimeout>): void;
}

export function emptySearchPreviewData(): SearchPreviewData {
  return { query: '', associatedQuery: '', results: null, queries: [], entries: [], isLoading: false, error: null };
}

function errorMessage(error: unknown): string {
  if (error && typeof error === 'object' && 'message' in error && typeof error.message === 'string') return error.message;
  if (typeof error === 'string') return error;
  return 'No se pudieron cargar los resultados rápidos.';
}

/** Debounced, history-free search state used only by the quick preview. */
export class ProviderPreviewController {
  private data = emptySearchPreviewData();
  private generation = 0;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private disposed = false;
  private accountRevision=0;
  private removedTokens=new Set<string>();

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
    this.data = { ...this.data, query, error: null, isLoading: false };
    if (this.data.associatedQuery !== trimmed) {
      this.data = { ...this.data, associatedQuery: '', results: null, queries: [], entries: [] };
    }
    this.emit();
    this.timer = this.scheduler.setTimeout(() => {
      this.timer = null;
      if (!this.disposed && generation === this.generation) void this.load(trimmed, generation);
    }, 150);
  }

  private async load(query: string, generation: number) {
    this.data = { ...this.data, isLoading: true, error: null };
    this.emit();
    try {
      const suggestions = await this.invoke<SearchSuggestionsPageDto>('search_suggestions_page', { query });
      if (this.disposed || generation !== this.generation) return;
      this.data = { ...this.data, associatedQuery: query, results:null, entries:suggestions.entries.filter(entry=>!entry.feedbackToken||!this.removedTokens.has(entry.feedbackToken)), queries:[], isLoading: false, error: null };
    } catch (error) {
      if (this.disposed || generation !== this.generation) return;
      this.data = { ...this.data, associatedQuery: query, results: null, isLoading: false, error: errorMessage(error) };
    }
    this.emit();
  }

  async remove(token:string) {
    const accountRevision=this.accountRevision;
    try { await this.invoke('remove_search_suggestion',{token});
      if(this.disposed||accountRevision!==this.accountRevision)return;
      this.removedTokens.add(token);
      this.data={...this.data,entries:this.data.entries?.filter(entry=>entry.feedbackToken!==token)};this.emit();
    } catch(error) {if(!this.disposed&&accountRevision===this.accountRevision){this.data={...this.data,error:errorMessage(error)};this.emit();}}
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
    ++this.accountRevision;this.removedTokens.clear();
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
