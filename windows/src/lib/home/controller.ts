import type { HomePageDto, HomeItemDto } from '../types';
import { sectionIdentity } from './presentation';

function sectionFingerprint(section: HomePageDto['sections'][number]) {
  return `${sectionIdentity(section)}|${JSON.stringify(section)}`;
}

type Rpc = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
export interface HomeData {
  page: HomePageDto | null;
  chipParams: string | null;
  loading: boolean;
  error: string | null;
  loadingMore: boolean;
  moreError: string | null;
  moreNotice: string | null;
}
export function emptyHomeData(): HomeData {
  return { page: null, chipParams: null, loading: false, error: null, loadingMore: false, moreError: null, moreNotice: null };
}
function message(error: unknown, fallback: string): string {
  if (error instanceof Error) return error.message;
  if (error && typeof error === 'object' && 'message' in error && typeof error.message === 'string') return error.message;
  return typeof error === 'string' ? error : fallback;
}

const MAX_SNAPSHOT_BYTES = 2_000_000;
/** Local storage is untrusted. Keep bounded display metadata, never opaque fields/cursors. */
function durablePage(value: unknown): HomePageDto | null {
  if (!value || typeof value !== 'object') return null;
  const page = value as Record<string, unknown>;
  if (!Array.isArray(page.sections) || !Array.isArray(page.chips)) return null;
  const str = (value: unknown) => typeof value === 'string' ? value.slice(0, 4096) : null;
  const sections: HomePageDto['sections'] = [];
  for (const section of page.sections.slice(0, 120)) {
    if (!section || typeof section.title !== 'string' || !Array.isArray(section.items)) return null;
    const items: HomeItemDto[] = [];
    for (const item of section.items.slice(0, 120)) {
      if (!item || typeof item.id !== 'string' || typeof item.kind !== 'string' || typeof item.title !== 'string') return null;
      const thumbnail = str(item.thumbnail);
      items.push({ id:str(item.id)!, kind:str(item.kind)!, title:str(item.title)!, subtitle:str(item.subtitle),
        thumbnail:thumbnail && /^https:\/\//i.test(thumbnail) && !/[?&](?:sig(?:nature)?|token|expire|auth|key)=/i.test(thumbnail) ? thumbnail : null,
        duration:str(item.duration), artists:str(item.artists), album:str(item.album), albumId:str(item.albumId), artistId:str(item.artistId),
        explicit:item.explicit === true, artistRuns:Array.isArray(item.artistRuns) ? item.artistRuns.slice(0, 32).flatMap((run: unknown) => {
          if (!run || typeof run !== 'object' || !('text' in run) || typeof run.text !== 'string') return [];
          return [{ text:str(run.text)!, id:'id' in run ? str(run.id) : null }];
        }) : [] });
    }
    sections.push({ title:str(section.title)!, format:str(section.format) ?? 'largeCards', items,
      moreBrowseId:str(section.moreBrowseId), moreParams:str(section.moreParams) });
  }
  return { chips:page.chips.slice(0, 100).flatMap(chip => chip && typeof chip.title === 'string' && typeof chip.params === 'string'
    ? [{ title:str(chip.title)!, params:str(chip.params)! }] : []), sections, continuation:null };
}

/** Owns Home requests and continuations; views only render the published snapshot. */
export class HomeController {
  private data = emptyHomeData();
  private request = 0;
  private usedTokens = new Set<string>();
  private snapshots = new Map<string, HomePageDto>();
  private accepted: { page:HomePageDto; chipParams:string|null } | null = null;
  private storage: Pick<Storage, 'getItem' | 'setItem'> | undefined;
  private storageKey: string | null = null;
  constructor(private rpc: Rpc, private publish: (data: HomeData) => void,
    private signature: (page: HomePageDto, chip: string | null) => string = page => JSON.stringify(page.sections),
    private shouldPreload: (page: HomePageDto) => boolean = () => true) {}
  private emit() { this.publish({ ...this.data }); }
  setSession(key: string, storage?: Pick<Storage, 'getItem' | 'setItem'>) {
    if (this.storageKey === key) return;
    this.reset(); this.storageKey = key; this.storage = storage;
    try {
      const raw = storage?.getItem(`${key}.feed.v1`), saved = raw && raw.length <= MAX_SNAPSHOT_BYTES ? JSON.parse(raw) : null;
      const page = saved?.version === 1 ? durablePage(saved) : null;
      if (page) {
        this.data.page = page; this.accepted = { page, chipParams:null }; this.emit();
      }
    } catch { /* Corrupt optional snapshots never block the network. */ }
  }
  private remember() {
    const page = this.data.page; if(!page)return;
    const key = this.data.chipParams ?? '';
    this.snapshots.delete(key); this.snapshots.set(key, page);
    while(this.snapshots.size > 4)this.snapshots.delete(this.snapshots.keys().next().value!);
    if(this.data.chipParams === null && this.storageKey) {
      // Provider cursors are request state, never durable data.
      try {
        const durable = durablePage(page);
        if (durable) {
          const raw = JSON.stringify({ version:1, chips:durable.chips, sections:durable.sections });
          if (raw.length <= MAX_SNAPSHOT_BYTES) this.storage?.setItem(`${this.storageKey}.feed.v1`, raw);
        }
      } catch { /* Optional cache. */ }
    }
  }
  reset() {
    ++this.request;
    this.usedTokens.clear();
    this.snapshots.clear(); this.storageKey = null; this.storage = undefined;
    this.accepted = null;
    this.data = emptyHomeData();
    this.emit();
  }
  async load(chipParams: string | null = null) {
    const previous = this.accepted ?? { page:this.data.page, chipParams:this.data.chipParams }; this.remember();
    const request = ++this.request;
    this.usedTokens.clear();
    this.data = { ...this.data, page: this.snapshots.get(chipParams ?? '') ?? (chipParams === this.data.chipParams ? this.data.page : null), chipParams, loading: true, error: null, loadingMore: false, moreError: null, moreNotice: null };
    this.emit();
    try {
      const page = await this.rpc<HomePageDto>('get_home_page', { chipParams });
      if (request !== this.request) return;
      this.data.page = page; this.accepted = { page, chipParams }; this.remember();
    } catch (error) {
      if (request !== this.request) return;
      this.data.error = message(error, 'No se pudo cargar la página de inicio.');
      if(chipParams !== previous.chipParams) { this.data.page = previous.page; this.data.chipParams = previous.chipParams; }
    } finally {
      if (request === this.request) { this.data.loading = false; this.emit(); }
    }
    // Preserve the existing bounded preload of the unfiltered feed.
    if (request === this.request && !this.data.error && this.data.page?.continuation && chipParams === null && this.shouldPreload(this.data.page)) {
      const started = Date.now();
      for (let page = 0; page < 3 && Date.now() - started < 12000; page++) {
        if (request !== this.request || !this.shouldPreload(this.data.page!) || !await this.loadMore(request, 1)) break;
      }
    }
  }
  async loadMore(expectedRequest = this.request, budget = 3): Promise<boolean> {
    let token = this.data.page?.continuation;
    if (!token || this.data.loading || this.data.loadingMore || expectedRequest !== this.request || this.usedTokens.has(token)) return false;
    this.data.loadingMore = true;
    this.data.moreError = null;
    this.data.moreNotice = null;
    this.emit();
    try {
      const before = this.signature(this.data.page!, this.data.chipParams);
      for (let attempt = 0; attempt < budget && token; attempt++) {
        const page: HomePageDto = await this.rpc<HomePageDto>('get_home_continuation', { token });
        if (expectedRequest !== this.request || this.data.page?.continuation !== token) return false;
        this.usedTokens.add(token);
        const existing = new Set(this.data.page.sections.map(sectionFingerprint));
        const fresh = page.sections.filter(section => {
          const key = sectionFingerprint(section);
          if (existing.has(key)) return false;
          existing.add(key);
          return true;
        });
        const continuation: string | null = page.continuation && !this.usedTokens.has(page.continuation) ? page.continuation : null;
        this.data.page = { ...this.data.page, sections: [...this.data.page.sections, ...fresh], continuation };
        this.accepted = { page:this.data.page, chipParams:this.data.chipParams };
        this.remember();
        token = continuation;
        if (this.signature(this.data.page, this.data.chipParams) !== before) break;
      }
      if (this.signature(this.data.page!, this.data.chipParams) === before && token)
        this.data.moreNotice = 'Esta tanda no trajo recomendaciones visibles nuevas. Podés cargar la siguiente.';
      return Boolean(token);
    } catch (error) {
      if (expectedRequest === this.request) this.data.moreError = message(error, 'No se pudieron cargar más recomendaciones.');
      return false;
    } finally {
      if (expectedRequest === this.request) { this.data.loadingMore = false; this.emit(); }
    }
  }
}
