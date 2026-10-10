import type { BrowseCardDto } from '../types';
import { category, type ExploreRoute } from './catalog';

export interface ChartCountryDto { code: string; title: string }
export interface ChartsPageDto { selectedCountry: string | null; countries: ChartCountryDto[]; items: BrowseCardDto[] }
export interface ChartSection { code: string; items: BrowseCardDto[]; error: string | null }
export interface ExploreData {
  route: ExploreRoute; items: BrowseCardDto[]; sections: ChartSection[]; countries: ChartCountryDto[];
  detectedCountry: string | null; regionMessage: string | null; isLoading: boolean; error: string | null; scrollTop: number;
}
export const emptyExploreData = (): ExploreData => ({route:'discover',items:[],sections:[],countries:[],detectedCountry:null,regionMessage:null,isLoading:false,error:null,scrollTop:0});
export type ExploreRpc = <T>(command: string,args?: Record<string,unknown>) => Promise<T>;

export function uniqueCards(items: BrowseCardDto[]): BrowseCardDto[] {
  const seen = new Set<string>();
  return items.filter(item => {
    const key = `${item.kind}:${item.id}`;
    if (!item.id.trim() || !item.title.trim() || !['album','playlist','artist','song','video'].includes(item.kind) || seen.has(key)) return false;
    seen.add(key); return true;
  });
}
function clone(data: ExploreData): ExploreData {
  return {...data, items:[...data.items], countries:data.countries.map(c=>({...c})), sections:data.sections.map(s=>({...s,items:[...s.items]}))};
}
/** Session-scoped, bounded caches. All publications and cache writes require the current route revision. */
export class ExploreController {
  private data = emptyExploreData();
  private revision = 0;
  private sources = new Map<string,BrowseCardDto[]>();
  private regions = new Map<string,ChartsPageDto>();
  private detection: {country:string|null; at:number} | null = null;
  constructor(private rpc: ExploreRpc,private publish:(data:ExploreData)=>void,private now:()=>number=Date.now) {}
  private emit() { this.publish(clone(this.data)); }
  private remember<T>(cache:Map<string,T>,key:string,value:T) { cache.delete(key); cache.set(key,value); while(cache.size>8) cache.delete(cache.keys().next().value!); return value; }
  capture() { return clone(this.data); }
  setScrollTop(offset:number) { this.data.scrollTop=Math.max(0,offset); }
  restore(snapshot:ExploreData) { ++this.revision; this.data=clone({...snapshot,isLoading:false}); this.emit(); if(snapshot.isLoading) void this.navigate(snapshot.route); }
  invalidate() { ++this.revision; this.data={...this.data,isLoading:false}; this.emit(); }
  reset() { ++this.revision; this.sources.clear(); this.regions.clear(); this.detection=null; this.data=emptyExploreData(); this.emit(); }
  async navigate(route: ExploreRoute, force=false) {
    const revision=++this.revision;
    const current=()=>revision===this.revision;
    const sameRoute=route===this.data.route;
    this.data={...emptyExploreData(),route,detectedCountry:this.detection?.country??null,countries:[...this.data.countries],items:sameRoute?this.data.items:[],scrollTop:sameRoute?this.data.scrollTop:0};
    if(route==='charts'||route.startsWith('country:')) { await this.loadCharts(route,force,current); return; }
    const selection=route.startsWith('category:')?category(route.slice(9)):null;
    const releases=route==='discover'||route==='releases';
    if(!releases&&!selection) { this.emit(); return; }
    const key=releases?'releases':`playlists:${selection!.query}`;
    const cached=this.sources.get(key);
    if(cached) this.data.items=[...this.remember(this.sources,key,cached)];
    if(cached&&!force) { this.emit(); return; }
    this.data.isLoading=true; this.emit();
    try {
      const result=await this.rpc<BrowseCardDto[]>(releases?'get_browse_grid':'search_cards',releases?{browseId:'FEmusic_new_releases_albums',params:null}:{query:selection!.query,category:'playlists'});
      if(!current()) return;
      this.data.items=this.remember(this.sources,key,uniqueCards(result));
    } catch { if(!current())return; this.data.error='explore.error.load_music'; }
    if(current()) { this.data.isLoading=false; this.emit(); }
  }
  private async page(code:string,force:boolean,current:()=>boolean) {
    const cached=this.regions.get(code);
    const page=cached&&!force?cached:await this.rpc<ChartsPageDto>('get_charts',{countryCode:code});
    if(!current()) throw new Error('stale');
    if(page.selectedCountry!==code) throw new Error('country not confirmed');
    const normalized={...page,items:uniqueCards(page.items),countries:page.countries.filter(c=>/^[A-Z]{2}$/.test(c.code))};
    return this.remember(this.regions,code,normalized);
  }
  private async loadCharts(route:ExploreRoute,force:boolean,current:()=>boolean) {
    const overview=route==='charts'; const code=overview?'ZZ':route.slice(8).toUpperCase();
    this.data.isLoading=true; this.emit();
    // Detection and Global are independent. Failure detecting the network never hides usable Global charts.
    const needsDetection=overview&&(force||!this.detection||this.now()-this.detection.at>=600000);
    const detect=needsDetection
      ? this.rpc<string|null>('detect_music_country').catch(()=>null) : Promise.resolve(this.detection?.country??null);
    const pageResult=this.page(code,force,current).then(page=>({page,error:false as const}),()=>({page:null,error:true as const}));
    const [country,result]=await Promise.all([detect,pageResult]);
    if(!current())return;
    if(needsDetection) this.detection={country:country&&/^[A-Z]{2}$/.test(country)?country:null,at:this.now()};
    if(overview) this.data.detectedCountry=this.detection?.country??null;
    if(result.page) {
      this.data.countries=result.page.countries; this.data.sections=[{code,items:result.page.items,error:null}]; this.emit();
      const region=this.data.detectedCountry;
      if(overview&&region&&region!=='ZZ') {
        if(result.page.countries.some(c=>c.code===region)) {
          try { const local=await this.page(region,force,current); if(!current())return; this.data.sections.push({code:region,items:local.items,error:null}); }
          catch { if(!current())return; this.data.sections.push({code:region,items:[],error:'explore.error.load_charts'}); }
        } else this.data.regionMessage='explore.region.unsupported';
      } else if(overview&&!region) this.data.regionMessage='explore.region.detect_failed';
    } else this.data.error='explore.error.load_charts';
    this.data.isLoading=false; this.emit();
  }
}
