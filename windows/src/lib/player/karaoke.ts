import type { PlaybackTrackDto } from '../types';
export interface KaraokeWord { text: string; startMs: number; endMs: number }
export interface KaraokeLine { timeMs: number | null; endTimeMs: number | null; text: string; words: KaraokeWord[]; translation?: string | null; role?: string | null; agent?: string | null; groupId?: string | null; section?: string | null }
export interface KaraokeLyrics { provider: string; isSynced: boolean; instrumental: boolean; lines: KaraokeLine[] }
export interface PreparedLine extends KaraokeLine { start: number | null; end: number | null; segments: { start: number; end: number; word: KaraokeWord }[] | null; background: boolean }
export interface KaraokeGap { start:number; end:number; anchor:number|null; before:number; kind: 'intro'|'interlude'|'outro' }
export interface KaraokeDocument { provider: string; instrumental: boolean; lines: PreparedLine[]; groups: { anchor: number; indices: number[]; start: number | null }[]; gaps: KaraokeGap[]; gapsByBefore: Map<number, { gap: KaraokeGap; index: number }[]>; boundaries: number[]; timeline: {anchor:number;start:number}[]; ordinals: Map<number,number>; hasWords: boolean; hasTiming: boolean; hasTranslations: boolean }
const time = (n: unknown): number | null => typeof n === 'number' && Number.isFinite(n) && n >= 0 ? n : null;
export function seekSeconds(ms: number | null, duration: number, offset = 0): number | null {
  if (ms === null || !Number.isFinite(ms) || ms < 0 || !Number.isFinite(offset)) return null;
  const seconds = Math.max(0, (ms - offset) / 1000);
  return Number.isFinite(duration) && duration > 0 ? Math.min(seconds, duration) : seconds;
}
export function prepareKaraoke(info: KaraokeLyrics, duration: number): KaraokeDocument {
  const segmenter=typeof Intl.Segmenter==='function'?new Intl.Segmenter(undefined,{granularity:'grapheme'}):null;
  const lines: PreparedLine[] = info.lines.map(line => {
    const words = line.words ?? [];
    const boundaries=new Set<number>([0,line.text.length]);
    if(segmenter)for(const part of segmenter.segment(line.text))boundaries.add(part.index);
    else {let index=0;for(const char of line.text){boundaries.add(index);index+=char.length;}}
    let cursor = 0, previous = -Infinity;
    const segments: NonNullable<PreparedLine['segments']> = [];
    let valid = words.length > 0;
    for (const word of words) {
      const start = line.text.indexOf(word.text, cursor);
      if (!word.text || time(word.startMs) === null || time(word.endMs) === null || word.endMs <= word.startMs || word.startMs < previous || start < 0 || !boundaries.has(start) || !boundaries.has(start+word.text.length) || /\S/u.test(line.text.slice(cursor, start))) { valid = false; break; }
      segments.push({ start, end: start + word.text.length, word }); cursor = start + word.text.length; previous = word.startMs;
    }
    if (/\S/u.test(line.text.slice(cursor))) valid = false;
    const validWords = words.filter(w => time(w.startMs) !== null && time(w.endMs) !== null && w.endMs > w.startMs);
    const start = time(line.timeMs) ?? (validWords.length ? Math.min(...validWords.map(w => w.startMs)) : null);
    const ends = [time(line.endTimeMs), ...validWords.map(w => w.endMs)].filter((n): n is number => n !== null && start !== null && n > start);
    return { ...line, words, start, end: ends.length ? Math.max(...ends) : time(line.endTimeMs), segments: valid ? segments : null, background: line.role?.trim().toLowerCase() === 'background' };
  });
  const memberships: number[][] = [], ids = new Map<string, number>();
  lines.forEach((line, i) => { const id = line.groupId?.trim(); if (id && ids.has(id)) memberships[ids.get(id)!].push(i); else { if (id) ids.set(id, memberships.length); memberships.push([i]); } });
  const groups = memberships.map(indices => {
    const leads=indices.filter(i=>!lines[i].background);
    const backgrounds=indices.filter(i=>lines[i].background).sort((a,b)=>(lines[a].start??Infinity)-(lines[b].start??Infinity)||a-b);
    const anchor=leads[0]??backgrounds[0];
    const starts=indices.map(i=>lines[i].start).filter((n):n is number=>n!==null);
    return {anchor,indices:[...leads,...backgrounds],start:lines[leads[0]]?.start??(starts.length?Math.min(...starts):null)};
  });
  const anchors = new Map(groups.flatMap(g=>g.indices.map(i=>[i,g.anchor] as const)));
  const coverage: {start: number; end: number; anchor: number}[] = [];
  let uncertain = false;
  lines.forEach((line, index) => {
    if (!line.text.trim()) return;
    const anchor = anchors.get(index)!;
    for (const word of line.words) { if (time(word.startMs)!==null && time(word.endMs)!==null && word.endMs>word.startMs) coverage.push({start:word.startMs,end:word.endMs,anchor}); }
    if (line.segments) return;
    const knownStart=time(line.timeMs),knownEnd=time(line.endTimeMs);
    if (knownStart !== null) coverage.push({start: knownStart, end: knownEnd!==null&&knownEnd>knownStart?knownEnd:Infinity, anchor});
    else if (knownEnd !== null&&knownEnd>0) coverage.push({start: 0, end: knownEnd, anchor});
    else uncertain = true;
  });
  coverage.sort((a,b) => a.start - b.start || b.end - a.end);
  const merged: typeof coverage = [];
  for (const interval of coverage) { const last = merged.at(-1); if (last && interval.start <= last.end) { if (interval.end > last.end) {last.end = interval.end; last.anchor = interval.anchor;} } else merged.push({...interval}); }
  // For unsorted provider rows, find the earliest display ordinal with a start
  // at/after each gap's end without scanning all groups for every interlude.
  const starts=groups.flatMap((group,ordinal)=>group.start===null?[]:[{start:group.start,ordinal}]).sort((a,b)=>a.start-b.start);
  const earliest=starts.map(item=>item.ordinal);
  for(let i=earliest.length-2;i>=0;i--)earliest[i]=Math.min(earliest[i],earliest[i+1]);
  const before=(end:number)=>{let lo=0,hi=starts.length;while(lo<hi){const mid=(lo+hi)>>>1;if(starts[mid].start<end)lo=mid+1;else hi=mid;}return earliest[lo]??groups.length;};
  const gaps: KaraokeDocument['gaps'] = [];
  const gap = (start: number, end: number, anchor: number | null) => { if (Number.isFinite(start) && Number.isFinite(end) && end - start >= 5000) {
    const kind = anchor===null ? 'intro' : end===duration*1000 ? 'outro' : 'interlude';
    const next = kind==='intro'?0:kind==='outro'?groups.length:before(end);
    gaps.push({start,end,anchor,kind,before:next<0?groups.length:next});
  } };
  if (!uncertain && !info.instrumental && merged.length) { gap(0, merged[0].start, null); for (let i=1;i<merged.length;i++) gap(merged[i-1].end,merged[i].start,merged[i-1].anchor); if (duration > 0) gap(merged.at(-1)!.end,duration*1000,merged.at(-1)!.anchor); }
  const timeline = groups.filter((g):g is typeof g & {start:number}=>g.start!==null&&Number.isFinite(g.start)).map(g=>({anchor:g.anchor,start:g.start})).sort((a,b)=>a.start-b.start||a.anchor-b.anchor);
  const ordinals = new Map(groups.map((g,i)=>[g.anchor,i]));
  const gapsByBefore: KaraokeDocument['gapsByBefore'] = new Map();
  gaps.forEach((gap,index)=>{const list=gapsByBefore.get(gap.before)??[];list.push({gap,index});gapsByBefore.set(gap.before,list);});
  const boundaries = [...new Set([...lines.flatMap(line=>[line.start,line.end,...line.words.flatMap(word=>[word.startMs,word.endMs])]),...gaps.flatMap(gap=>[gap.start,gap.end])].filter((n):n is number=>time(n)!==null))].sort((a,b)=>a-b);
  return {provider:info.provider,instrumental:info.instrumental,lines,groups,gaps,gapsByBefore,boundaries,timeline,ordinals,hasWords:lines.some(l=>!!l.segments),hasTiming:info.isSynced && lines.some(l=>l.start!==null),hasTranslations:lines.some(l=>!!l.translation?.trim())};
}
export function karaokeFocus(document: KaraokeDocument, ms: number): number | null {
  if (!document.hasTiming) return null;
  const timeline=document.timeline;
  if(!timeline.length)return null;
  let lo=0,hi=timeline.length;
  while(lo<hi){const mid=(lo+hi)>>>1;if(timeline[mid].start<=ms)lo=mid+1;else hi=mid;}
  return timeline[Math.max(0,lo-1)].anchor;
}
/** Gaps are disjoint and chronological after the union of every voice. */
export function karaokeGapIndex(document: KaraokeDocument, ms: number): number {
  let lo=0,hi=document.gaps.length;
  while(lo<hi){const mid=(lo+hi)>>>1;if(document.gaps[mid].start<=ms)lo=mid+1;else hi=mid;}
  const index=lo-1;
  return index>=0&&ms<document.gaps[index].end?index:-1;
}
export interface KaraokeState { occurrence: string | null; status: 'idle'|'loading'|'ready'|'empty'|'error'; refreshing: boolean; document: KaraokeDocument | null; error: string | null }
type Rpc = <T>(command:string,args?:Record<string,unknown>)=>Promise<T>;
export class KaraokeController {
  private revision=0; private signature=''; private track:PlaybackTrackDto|null=null; private duration=0; private active=false; private forceNext=false;
  state:KaraokeState={occurrence:null,status:'idle',refreshing:false,document:null,error:null};
  constructor(private rpc:Rpc,private publish:(state:KaraokeState)=>void){}
  setContext(track:PlaybackTrackDto|null, occurrence:string, duration:number, active:boolean) {
    const signature=JSON.stringify([track?.videoId,track?.title,track?.artists,track?.album,Number.isFinite(duration)&&duration>0?Math.round(duration):null]);
    const changedOccurrence=this.state.occurrence!==occurrence;
    const changed=changedOccurrence||signature!==this.signature;
    this.track=track;this.duration=duration;this.signature=signature;
    if (changedOccurrence) {++this.revision;this.state={occurrence,status:'idle',refreshing:false,document:null,error:null};this.publish(this.state);}
    if (!active) {if(this.active) {++this.revision;this.state={...this.state,refreshing:false,status:this.state.document?'ready':'idle'};this.publish(this.state);}this.active=false;return;}
    const resumed=!this.active;this.active=true;
    if(track && (changed || resumed || this.forceNext)) { const force=this.forceNext;this.forceNext=false;void this.load(force); }
  }
  retry(){if(!this.active){this.forceNext=true;return Promise.resolve();}return this.load(true);}
  dispose(){++this.revision;this.active=false;}
  private async load(forceRefresh:boolean) {
    const track=this.track;if(!track||!this.active)return;
    const revision=++this.revision;
    this.state={...this.state,status:this.state.document?'ready':'loading',refreshing:true,error:null};this.publish(this.state);
    try {
      const info=await this.rpc<KaraokeLyrics|null>('get_karaoke_lyrics',{videoId:track.videoId,title:track.title,artists:track.artists,album:track.album??null,duration:this.duration>0?this.duration:null,forceRefresh});
      if(revision!==this.revision||!this.active)return;
      const document=info && (info.instrumental||info.lines.length)?prepareKaraoke(info,this.duration):null;
      this.state={...this.state,status:document||this.state.document?'ready':'empty',document:document??this.state.document,refreshing:false};
    }catch(error){if(revision!==this.revision||!this.active)return;this.state={...this.state,status:this.state.document?'ready':'error',refreshing:false,error:error instanceof Error?error.message:String(error)};}
    this.publish(this.state);
  }
}
