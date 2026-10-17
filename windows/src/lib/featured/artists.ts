import type { BrowseCardDto, SongDto } from '$lib/types';
export type FeaturedTrack = Pick<SongDto,'videoId'|'title'|'artists'|'artistRuns'> & {artistId?:string|null;album?:string|null};
export const FEATURED_ARTIST_CONTEXT = Symbol('featured-artists');
export type Credit = { start: number; end: number; name: string; id?: string; provenance: 'provider'|'userChoice'|'inferred'|'unresolved'; evidence?: string };
export const normalizeArtist = (name: string) => name.normalize('NFKC').toLocaleLowerCase().replace(/\s+/gu,' ').trim();
export function featuredClauses(title: string): Credit[] {
  const result: Credit[] = [];
  const marker = /\b(?:feat\.?|ft\.?|featuring)\s+|(?<=[([])\s*(?:with|con)\s+/giu;
  for (const match of title.matchAll(marker)) {
    const start = match.index! + match[0].length;
    let end = title.slice(start).search(/[)\]]|\s+-\s+(?:remaster|live|version|edit|mix)\b|\s+\((?:remaster|live|version|edit|mix)\b/iu);
    end = end < 0 ? title.length : start + end;
    while(end > start && /\s/u.test(title[end-1])) end--;
    if(end > start && !result.some(c => start < c.end)) result.push({start,end,name:title.slice(start,end),provenance:'unresolved'});
  }
  return result;
}
function cuts(name: string): [number,number][] {
  return [...name.matchAll(/\s*(?:,|&|\/|\band\b|\by\b)\s*/giu)].map(m => [m.index!,m.index!+m[0].length]);
}
function similarity(a: string,b: string): number {
  if(a===b) return 1;
  // Approximate names may differ by a small typo, never by missing distinctive words.
  if(Math.abs(a.length-b.length)>2 || a.length<5 || a.split(' ').length!==b.split(' ').length) return 0;
  const row=Array.from({length:b.length+1},(_,i)=>i);
  for(let i=1;i<=a.length;i++){let previous=row[0];row[0]=i;for(let j=1;j<=b.length;j++){const old=row[j];row[j]=Math.min(row[j]+1,row[j-1]+1,previous+(a[i-1]===b[j-1]?0:1));previous=old;}}
  return row[b.length]<=Math.max(1,Math.floor(a.length*.1)) ? .8 : 0;
}
export function rankArtists(name:string,cards:BrowseCardDto[]): BrowseCardDto[] {
  const target=normalizeArtist(name),seen=new Set<string>();
  return cards.map((card,index)=>({card,index,score:similarity(target,normalizeArtist(card.title))})).filter(({card,score})=>{
    if(!['artist','artists'].includes(card.kind)||!card.id.trim()||!score||seen.has(card.id))return false;seen.add(card.id);return true;
  }).sort((a,b)=>b.score-a.score||a.index-b.index||a.card.id.localeCompare(b.card.id)).map(x=>x.card);
}
type Flight={task:Promise<Entry>;controller:AbortController;consumers:Set<symbol>};
type Entry={id?:string;time:number;provenance:Credit['provenance'];contextualComplete?:boolean};
export class FeaturedArtistService {
  private scope:string; private generation=0; private active=0; private waiters:(()=>void)[]=[];
  private cache=new Map<string,Entry>(); private flight=new Map<string,Flight>();
  private choices:Record<string,Entry>={};
  constructor(private options:{search:(query:string)=>Promise<BrowseCardDto[]>;scope:string;onSearch?:(name:string)=>void;storage?:Pick<Storage,'getItem'|'setItem'>}) {this.scope=options.scope;this.load();}
  resetScope(scope:string){if(scope===this.scope)return;this.scope=scope;this.generation++;this.cache.clear();for(const flight of this.flight.values())flight.controller.abort();this.flight.clear();this.load();}
  private storage(){return this.options.storage??(typeof localStorage==='undefined'?undefined:localStorage);}
  private load(){
    const read=(key:string,choices:boolean)=>{try{const parsed:unknown=JSON.parse(this.storage()?.getItem(key)??'{}');if(!parsed||typeof parsed!=='object'||Array.isArray(parsed))return {};
      return Object.fromEntries(Object.entries(parsed).filter(([,value])=>{const v=value as Partial<Entry>;return v&&typeof v==='object'&&typeof v.time==='number'&&Number.isFinite(v.time)&&(v.id===undefined||typeof v.id==='string'&&Boolean(v.id.trim()))&&(choices?v.provenance==='userChoice'&&Boolean(v.id):['inferred','unresolved'].includes(v.provenance??'')&&(v.contextualComplete===undefined||typeof v.contextualComplete==='boolean')&&v.time<=Date.now()&&Date.now()-v.time<(v.id?7*86400000:600000));}));}catch{return {};}};
    this.choices=read(`sideb.featured.choices.v1:${this.scope}`,true);this.cache=new Map(Object.entries(read(`sideb.featured.cache.v1:${this.scope}`,false)).slice(-500));
  }
  private saveCache(){try{this.storage()?.setItem(`sideb.featured.cache.v1:${this.scope}`,JSON.stringify(Object.fromEntries(this.cache)));}catch{}}
  private key(track:FeaturedTrack,name:string){return JSON.stringify(['ytmusic',this.scope,track.videoId,track.title,track.artists,track.album,normalizeArtist(name),'v1']);}
  known(track:FeaturedTrack,name:string):string|undefined {const normalized=normalizeArtist(name);return track.artistRuns?.find(r=>r.id&&normalizeArtist(r.text)===normalized)?.id??(track.artistId&&normalizeArtist(track.artists)===normalized?track.artistId:undefined);}
  choose(track:FeaturedTrack,name:string,id:string){if(!id.trim())return;this.choices[this.key(track,name)]={id,time:Date.now(),provenance:'userChoice'};try{this.storage()?.setItem(`sideb.featured.choices.v1:${this.scope}`,JSON.stringify(this.choices));}catch{/* Storage availability does not block navigation. */}}
  clearChoice(track:FeaturedTrack,name:string){delete this.choices[this.key(track,name)];try{this.storage()?.setItem(`sideb.featured.choices.v1:${this.scope}`,JSON.stringify(this.choices));}catch{}}
  get scopeRevision(){return this.generation;}
  async candidates(track:FeaturedTrack,name:string,target=name,signal?:AbortSignal){const generation=this.generation;await this.acquire();try{if(generation!==this.generation||signal?.aborted)return [];const cards=await this.options.search(name);return generation===this.generation&&!signal?.aborted?rankArtists(target,cards):[];}finally{this.release();}}
  private async acquire(){if(this.active>=2)await new Promise<void>(resolve=>this.waiters.push(resolve));else this.active++;}
  private release(){const next=this.waiters.shift();if(next)next();else this.active--;}
  private awaitFlight(key:string,flight:Flight,signal?:AbortSignal):Promise<Entry>{
    const token=Symbol();flight.consumers.add(token);
    return new Promise(resolve=>{
      let finished=false;
      const finish=(entry:Entry)=>{if(finished)return;finished=true;signal?.removeEventListener('abort',abort);flight.consumers.delete(token);
        if(!flight.consumers.size){flight.controller.abort();if(this.flight.get(key)===flight)this.flight.delete(key);}resolve(entry);};
      const abort=()=>finish({time:Date.now(),provenance:'unresolved'});
      signal?.addEventListener('abort',abort,{once:true});
      if(signal?.aborted)abort();else void flight.task.then(finish);
    });
  }
  async resolve(track:FeaturedTrack,name:string,budget?:{remaining:number},contextual=true,signal?:AbortSignal):Promise<Entry>{
    if(signal?.aborted)return {time:Date.now(),provenance:'unresolved'};
    const known=this.known(track,name);if(known){const existingKey=this.key(track,name);if(this.choices[existingKey])this.clearChoice(track,name);if(this.cache.delete(existingKey))this.saveCache();return {id:known,time:Date.now(),provenance:'provider'};}
    const key=this.key(track,name),chosen=this.choices[key];if(chosen)return chosen;
    const cached=this.cache.get(key),fresh=Boolean(cached&&Date.now()-cached.time<(cached.id?7*86400000:600000));if(cached&&fresh&&(cached.id||!contextual||cached.contextualComplete===true)){this.cache.delete(key);this.cache.set(key,cached);return cached;}
    const existing=this.flight.get(key);if(existing){
      const generation=this.generation,result=await this.awaitFlight(key,existing,signal);
      if(result.id||!contextual||result.contextualComplete||signal?.aborted||generation!==this.generation)return result;
      if(this.flight.get(key)===existing)this.flight.delete(key);
      return this.resolve(track,name,budget,contextual,signal);
    }
    if(budget&&budget.remaining<=0)return {time:Date.now(),provenance:'unresolved'};
    const skipExact=Boolean(cached&&fresh&&!cached.id);
    if(budget&&!skipExact)budget.remaining--;
    const generation=this.generation,controller=new AbortController(),sharedSignal=controller.signal;
    const task=(async()=>{let cards:BrowseCardDto[]=[],contextualComplete=!track.artists;try{cards=skipExact?[]:await this.candidates(track,name,name,sharedSignal);if(generation!==this.generation||sharedSignal.aborted)return {time:Date.now(),provenance:'unresolved' as const};if(contextual&&!cards.length&&(!budget||budget.remaining>0)&&track.artists){if(budget)budget.remaining--;contextualComplete=true;cards=await this.candidates(track,`${name} ${track.artists}`,name,sharedSignal);}}catch{}
      const entry:Entry={id:cards[0]?.id,time:Date.now(),provenance:cards.length?'inferred':'unresolved',contextualComplete:contextual&&contextualComplete};
      if(generation===this.generation&&!sharedSignal.aborted){this.cache.set(key,entry);while(this.cache.size>500)this.cache.delete(this.cache.keys().next().value!);this.saveCache();}return entry;})();
    const flight:Flight={task,controller,consumers:new Set()};this.flight.set(key,flight);return this.awaitFlight(key,flight,signal);
  }
  async title(track:FeaturedTrack,signal?:AbortSignal):Promise<Credit[]>{
    const generation=this.generation,budget={remaining:8},result:Credit[]=[];
    const solve=async(credit:Credit,depth:number):Promise<Credit[]>=>{
      if(signal?.aborted)return [];
      const fullKnown=this.known(track,credit.name);
      if(fullKnown)return [{...credit,id:fullKnown,provenance:'provider'}];
      const boundaries=cuts(credit.name).slice(0,5);
      // Complete provider coverage beats all inferred partition choices and needs no search.
      const knownPieces:Credit[]=[];let offset=0;
      while(offset<credit.name.length){
        const ends=[credit.name.length,...boundaries.filter(([left])=>left>offset).map(([left])=>left)].sort((a,b)=>b-a);
        const end=ends.find(end=>Boolean(this.known(track,credit.name.slice(offset,end))));
        if(end===undefined)break;
        knownPieces.push({start:credit.start+offset,end:credit.start+end,name:credit.name.slice(offset,end),id:this.known(track,credit.name.slice(offset,end)),provenance:'provider'});
        if(end===credit.name.length){offset=end;break;}offset=boundaries.find(([left])=>left===end)![1];
      }
      if(offset===credit.name.length&&knownPieces.length)return knownPieces;
      const whole=await this.resolve(track,credit.name,budget,false,signal);
      if(whole.id)return [{...credit,...whole,evidence:whole.provenance}];
      if(depth>=5)return [credit];
      // Longest contiguous compatible entity wins; bounded recursion preserves group names.
      for(const [left,right] of [...boundaries].reverse()){
        if(signal?.aborted)return [];
        const first=credit.name.slice(0,left).trim(),second=credit.name.slice(right).trim();if(!first||!second)continue;
        const firstEntry=await this.resolve(track,first,budget,false,signal);
        if(!firstEntry.id)continue;
        const trailing=await solve({start:credit.start+right,end:credit.end,name:second,provenance:'unresolved'},depth+1);
        if(trailing.some(c=>c.id))return [{start:credit.start,end:credit.start+left,name:first,...firstEntry},...trailing];
      }
      // Keep compound names intact when no partition has compatible evidence.
      return [credit];
    };
    for(const clause of featuredClauses(track.title)){result.push(...await solve(clause,0));if(result.length>=6)break;}return generation===this.generation?result.slice(0,6):[];
  }
  async open(track:FeaturedTrack,name:string,onOpenArtist?:(id:string)=>void,signal?:AbortSignal,titleOffset?:number){
    const generation=this.generation;let timer:ReturnType<typeof setTimeout>|undefined;
    const lookup=async()=>{let target=name;if(titleOffset!==undefined){const parts=await this.title(track,signal);target=parts.find(part=>titleOffset>=part.start&&titleOffset<part.end)?.name??name;}if(generation!==this.generation)return {resolved:{time:Date.now(),provenance:'unresolved' as const},target};const resolved=await this.resolve(track,target,undefined,true,signal);return {resolved,target};};
    const found=await Promise.race([lookup(),new Promise<{resolved:Entry;target:string}>(resolve=>timer=setTimeout(()=>resolve({resolved:{time:Date.now(),provenance:'unresolved'},target:name}),2000))]);
    clearTimeout(timer);if(signal?.aborted||generation!==this.generation)return;if(found.resolved.id)onOpenArtist?.(found.resolved.id);else this.options.onSearch?.(found.target);
  }
  search(name:string){this.options.onSearch?.(name);}
}

/** A correction belongs to the exact metadata, guest and account that opened it. */
export class FeaturedArtistPicker {
  private operation?:AbortController;
  private allowed=new Set<string>();
  private context?:{track:FeaturedTrack;name:string;identity:string;revision:number};
  constructor(private service:FeaturedArtistService,private current:()=>{track:FeaturedTrack;name:string}){}
  private identity(track:FeaturedTrack,name:string){return JSON.stringify([track,name]);}
  cancel(){this.operation?.abort();this.operation=undefined;this.context=undefined;this.allowed.clear();}
  private valid(){const live=this.current();return this.context?.revision===this.service.scopeRevision&&this.context.identity===this.identity(live.track,live.name);}
  async load(){
    this.cancel();const live=this.current(),operation=new AbortController();this.operation=operation;
    this.context={track:{...live.track,artistRuns:live.track.artistRuns?.map(run=>({...run}))},name:live.name,identity:this.identity(live.track,live.name),revision:this.service.scopeRevision};
    const result=await this.service.candidates(this.context.track,this.context.name,this.context.name,operation.signal);
    if(this.operation!==operation||operation.signal.aborted||!this.valid())return [];
    this.allowed=new Set(result.map(candidate=>candidate.id));return result;
  }
  choose(id:string){if(!this.valid()||!this.context||!this.allowed.has(id))return false;this.service.choose(this.context.track,this.context.name,id);this.cancel();return true;}
  reset(){if(!this.valid()||!this.context)return false;this.service.clearChoice(this.context.track,this.context.name);this.cancel();return true;}
}
