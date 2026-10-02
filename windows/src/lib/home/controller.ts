import type { HomePageDto } from '../types';
import { sectionIdentity } from './presentation';

type Rpc = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
export interface HomeData {
  page: HomePageDto | null;
  chipParams: string | null;
  loading: boolean;
  error: string | null;
  loadingMore: boolean;
  moreError: string | null;
}
export function emptyHomeData(): HomeData {
  return { page: null, chipParams: null, loading: false, error: null, loadingMore: false, moreError: null };
}
function message(error: unknown, fallback: string): string {
  if (error instanceof Error) return error.message;
  if (error && typeof error === 'object' && 'message' in error && typeof error.message === 'string') return error.message;
  return typeof error === 'string' ? error : fallback;
}

/** Owns Home requests and continuations; views only render the published snapshot. */
export class HomeController {
  private data = emptyHomeData();
  private request = 0;
  private usedTokens = new Set<string>();
  constructor(private rpc: Rpc, private publish: (data: HomeData) => void) {}
  private emit() { this.publish({ ...this.data }); }
  reset() {
    ++this.request;
    this.usedTokens.clear();
    this.data = emptyHomeData();
    this.emit();
  }
  async load(chipParams: string | null = null) {
    const request = ++this.request;
    this.usedTokens.clear();
    this.data = { ...this.data, chipParams, loading: true, error: null, loadingMore: false, moreError: null };
    this.emit();
    try {
      const page = await this.rpc<HomePageDto>('get_home_page', { chipParams });
      if (request !== this.request) return;
      this.data.page = page;
    } catch (error) {
      if (request !== this.request) return;
      this.data.error = message(error, 'No se pudo cargar la página de inicio.');
    } finally {
      if (request === this.request) { this.data.loading = false; this.emit(); }
    }
    // Preserve the existing bounded preload of the unfiltered feed.
    if (request === this.request && !this.data.error && this.data.page?.continuation && chipParams === null) {
      const started = Date.now();
      for (let page = 0; page < 3 && Date.now() - started < 12000; page++) {
        if (request !== this.request || !await this.loadMore(request)) break;
      }
    }
  }
  async loadMore(expectedRequest = this.request): Promise<boolean> {
    const token = this.data.page?.continuation;
    if (!token || this.data.loading || this.data.loadingMore || expectedRequest !== this.request || this.usedTokens.has(token)) return false;
    this.data.loadingMore = true;
    this.data.moreError = null;
    this.emit();
    try {
      const page = await this.rpc<HomePageDto>('get_home_continuation', { token });
      if (expectedRequest !== this.request || this.data.page?.continuation !== token) return false;
      this.usedTokens.add(token);
      const existing = new Set(this.data.page.sections.map(sectionIdentity));
      const fresh = page.sections.filter(section => {
        const key = sectionIdentity(section);
        if (existing.has(key)) return false;
        existing.add(key);
        return true;
      });
      const continuation = page.continuation && !this.usedTokens.has(page.continuation) ? page.continuation : null;
      this.data.page = { ...this.data.page, sections: [...this.data.page.sections, ...fresh], continuation };
      return Boolean(continuation);
    } catch (error) {
      if (expectedRequest === this.request) this.data.moreError = message(error, 'No se pudieron cargar más recomendaciones.');
      return false;
    } finally {
      if (expectedRequest === this.request) { this.data.loadingMore = false; this.emit(); }
    }
  }
}
