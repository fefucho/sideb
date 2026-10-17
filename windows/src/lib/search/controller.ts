import type { SearchOrigin } from './recents';
import type { AlbumCardDto, BrowseCardDto, SearchResultsDto, SearchCatalogDto, SearchCorrectionDto, SongDto } from '../types';

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
  correction?: SearchCorrectionDto | null;
  ignoreSpelling?: boolean;
  mixedResults?: SearchResultsDto | null;
  isLoading: boolean;
  error: string | null;
  partialErrors: Partial<Record<SearchPartialError, string>>;
  pendingBlocks?: SearchPartialError[];
  hasSearched: boolean;
  hasSearchedSongs: boolean;
  hasSearchedAlbums: boolean;
  hasSearchedArtists: boolean;
  hasSearchedPlaylists: boolean;
  hasSearchedVideos: boolean;
}

export function emptySearchData(): SearchData {
  return { query: '', mode: 'all', lastSearchedQuery: '', songs: [], albums: [], top: [], topSongs: [], artists: [], playlists: [], videos: [],
    mixedResults: null, pendingBlocks: [], isLoading: false, error: null, partialErrors: {}, hasSearched: false, hasSearchedSongs: false, hasSearchedAlbums: false,
    hasSearchedArtists: false, hasSearchedPlaylists: false, hasSearchedVideos: false };
}

function errorMessage(error: unknown) {
  if (error && typeof error === 'object' && 'message' in error && typeof error.message === 'string') return error.message;
  if (typeof error === 'string') return error;
  return 'Error al consultar el catálogo.';
}

const albumCard = (card: BrowseCardDto): AlbumCardDto => ({ id: card.id, title: card.title, subtitle: card.subtitle, thumbnail: card.thumbnail });

type Cached<T> = {at:number; value:T};

/** Account resets and request revisions discard obsolete replies; HTTP work may still finish. */
export class SearchController {
  private data = emptySearchData();
  private generation = 0;
  private revision = 0;
  private mixedResults: SearchResultsDto | null = null;
  private cache = new Map<string, Cached<SearchCatalogDto>>();
  private categories = new Map<string, Cached<SongDto[] | BrowseCardDto[]>>();
  constructor(private rpc: SearchRpc, private publish: (data: SearchData) => void) {}
  private emit() {
    const mixed=this.mixedResults;
    this.publish({...this.data,top:[...this.data.top],topSongs:[...this.data.topSongs],songs:[...this.data.songs],videos:[...this.data.videos],albums:[...this.data.albums],artists:[...this.data.artists],playlists:[...this.data.playlists],
      mixedResults:mixed?{...mixed,top:[...mixed.top],topSongs:[...(mixed.topSongs??[])],songs:[...mixed.songs],albums:[...mixed.albums],artists:[...mixed.artists],playlists:[...mixed.playlists]}:null,
      partialErrors:{...this.data.partialErrors},pendingBlocks:[...(this.data.pendingBlocks??[])]});
  }
  private key(query:string, mode='all',ignoreSpelling=this.data.ignoreSpelling??false) {return `${this.generation}:${ignoreSpelling}:${mode}:${query}`;}
  private get<T>(cache:Map<string,Cached<T>>,key:string):T|undefined {const entry=cache.get(key);if(!entry)return;if(Date.now()-entry.at>=60_000){cache.delete(key);return;}return entry.value;}
  private put<T>(cache:Map<string,Cached<T>>,key:string,value:T) {cache.delete(key);cache.set(key,{at:Date.now(),value});while(cache.size>32)cache.delete(cache.keys().next().value!);}
  private applyMixed(catalog:SearchCatalogDto) {
    const mixed=catalog.results;this.mixedResults=mixed;
    this.data={...this.data,correction:catalog.correction,top:[...mixed.top],topSongs:[...(mixed.topSongs??[])],songs:mixed.songs.filter(song=>!song.isVideo),albums:mixed.albums.map(albumCard),artists:[...mixed.artists],playlists:[...mixed.playlists],videos:mixed.songs.filter(song=>song.isVideo)};
  }
  setQuery(query:string) {
    if(query===this.data.query)return;
    ++this.revision;this.mixedResults=null;this.data={...emptySearchData(),query,mode:this.data.mode};this.emit();
  }
  setMode(mode:SearchMode) {
    if(mode===this.data.mode)return;
    const pending=this.data.isLoading;const query=this.data.lastSearchedQuery;
    ++this.revision;this.data={...this.data,mode,isLoading:false,pendingBlocks:[],partialErrors:{}};
    if(mode==='all'&&this.mixedResults)this.applyMixed({results:this.mixedResults,correction:this.data.correction??null});
    this.emit();
    if(!query)return;
    if(pending||!this.mixedResults){void this.execute(query,mode,'filter',this.data.ignoreSpelling);return;}
    if(mode!=='all')void this.loadMode(query,mode);
  }
  invalidate() {++this.revision;this.data={...this.data,isLoading:false,pendingBlocks:[]};this.emit();}
  reset() {++this.generation;++this.revision;this.mixedResults=null;this.cache.clear();this.categories.clear();this.data=emptySearchData();this.emit();}
  restore(snapshot:SearchData) {
    ++this.revision;this.data={...emptySearchData(),...snapshot,isLoading:false,pendingBlocks:[],partialErrors:{...snapshot.partialErrors}};
    this.mixedResults=snapshot.mixedResults??null;this.emit();
    if(snapshot.isLoading&&snapshot.lastSearchedQuery)void this.execute(snapshot.lastSearchedQuery,snapshot.mode,'navigationRestore',snapshot.ignoreSpelling);
  }
  async execute(targetQuery:string, mode:SearchMode=this.data.mode, origin:SearchOrigin|boolean='submit',ignoreSpelling=false) {
    const recordHistory=typeof origin==='boolean'?origin:origin==='submit'||origin==='recentQuery';
    const query=targetQuery.trim();if(!query)return;
    if(this.data.isLoading&&this.data.lastSearchedQuery===query&&this.data.mode===mode&&this.data.ignoreSpelling===ignoreSpelling&&this.activeHistory===recordHistory)return;
    const revision=++this.revision,generation=this.generation;const current=()=>revision===this.revision&&generation===this.generation;
    this.activeHistory=recordHistory;this.mixedResults=null;
    this.data={...emptySearchData(),query,mode,lastSearchedQuery:query,ignoreSpelling,isLoading:true,hasSearched:true,pendingBlocks:['global']};this.emit();
    try {
      // Explicit submissions always reach the provider so the query is recorded once.
      const key=this.key(query,'all',ignoreSpelling);
      const catalog=(!recordHistory&&this.get(this.cache,key))||await this.rpc<SearchCatalogDto>('search_catalog',{query,recordHistory,ignoreSpelling});
      if(!current())return;
      this.put(this.cache,key,catalog);this.applyMixed(catalog);this.data.pendingBlocks=[];this.data.isLoading=false;this.emit();
      if(mode!=='all')await this.loadMode(query,mode);
    }catch(error){if(current()){this.data.error=errorMessage(error);this.data.partialErrors.global=this.data.error;this.data.pendingBlocks=[];this.data.isLoading=false;this.emit();if(mode!=='all')await this.loadMode(query,mode);}}
    finally{if(current())this.activeHistory=null;}
  }
  private activeHistory:boolean|null=null;
  async retryBlock(block:SearchPartialError) {
    const query=this.data.lastSearchedQuery;if(!query)return;
    if(block==='global'){await this.execute(query,this.data.mode,'refresh',this.data.ignoreSpelling);return;}
    await this.loadMode(query,block==='categories'?this.data.mode:block);
  }
  private async loadMode(query:string,mode:SearchMode) {
    if(mode==='all')return;
    const revision=this.revision,generation=this.generation;const current=()=>revision===this.revision&&generation===this.generation;
    const block:SearchPartialError=mode==='songs'||mode==='videos'?mode:'categories';
    const key=this.key(query,mode);const cached=this.get(this.categories,key);
    const apply=(items:SongDto[]|BrowseCardDto[])=>{
      if(mode==='songs'){this.data.songs=items as SongDto[];this.data.hasSearchedSongs=true;}
      if(mode==='videos'){this.data.videos=items as SongDto[];this.data.hasSearchedVideos=true;}
      if(mode==='albums'){this.data.albums=(items as BrowseCardDto[]).map(albumCard);this.data.hasSearchedAlbums=true;}
      if(mode==='artists'){this.data.artists=items as BrowseCardDto[];this.data.hasSearchedArtists=true;}
      if(mode==='playlists'){this.data.playlists=items as BrowseCardDto[];this.data.hasSearchedPlaylists=true;}
    };
    if(this.data.ignoreSpelling && this.mixedResults) {
      // Exact spelling has only the provider's mixed response: category endpoints may correct it again.
      const mixed=this.mixedResults;
      if(mode==='songs'||mode==='videos') {
        const seen=new Set<string>();
        apply([...(mixed.topSongs??[]),...mixed.songs].filter(song=>{
          if(Boolean(song.isVideo)!==(mode==='videos')||seen.has(song.videoId))return false;
          seen.add(song.videoId);return true;
        }));
      } else {
        const seen=new Set<string>();const kind=mode==='artists'?'artist':mode==='albums'?'album':'playlist';
        apply([...mixed.top,...mixed[mode]].filter(card=>{if(card.kind!==kind||seen.has(card.id))return false;seen.add(card.id);return true;}));
      }
      this.emit();return;
    }
    if(cached){apply(cached);this.emit();return;}
    this.data.isLoading=true;this.data.pendingBlocks=[block];delete this.data.partialErrors[block];this.emit();
    // Provider correction also governs category requests unless the user chose the original spelling.
    const providerQuery=this.data.correction?.applied?this.data.correction.query:query;
    try {
      const items=await this.rpc<SongDto[]|BrowseCardDto[]>(mode==='songs'?'search_songs':mode==='videos'?'search_videos':'search_cards',mode==='songs'||mode==='videos'?{query:providerQuery}:{query:providerQuery,category:mode});
      if(!current())return;this.put(this.categories,key,items);apply(items);
    }catch(error){if(current())this.data.partialErrors[block]=errorMessage(error);}
    finally{if(current()){this.data.isLoading=false;this.data.pendingBlocks=[];this.emit();}}
  }
}
