import type { SongDto, PlaybackStateDto } from '../types';
export type SearchOrigin = 'submit' | 'recentQuery' | 'preview' | 'filter' | 'refresh' | 'navigationRestore' | 'artistResolution';
export const recordsSearch = (origin: SearchOrigin) => origin === 'submit' || origin === 'recentQuery';
export type SearchRecent = {key:string;kind:'query';lastUsedAt:number;query:string} | {key:string;kind:'track';lastUsedAt:number;track:SongDto};
export interface RecentStorage {getItem(key:string):string|null;setItem(key:string,value:string):void}
export function normalizedQuery(query:string) { return query.trim().replace(/\s+/gu,' ').normalize('NFC'); }
function safeTrack(song:SongDto):SongDto {
 const nullable=(value:unknown)=>typeof value==='string'?value:null;
 const artistRuns=Array.isArray(song.artistRuns)?song.artistRuns.filter(run=>run&&typeof run.text==='string').map(run=>({text:run.text,id:nullable(run.id)})):[];
 return {videoId:song.videoId,title:song.title,artists:song.artists,artistRuns,thumbnail:nullable(song.thumbnail),album:nullable(song.album),albumId:nullable(song.albumId),artistId:nullable(song.artistId),duration:nullable(song.duration),isVideo:!!song.isVideo,isUpload:!!song.isUpload};
}

/** Synchronous serialized metadata writes. Playback intentions are scoped to one explicit activation. */
export class SearchRecentStore {
 private initialized=false; private account='guest'; private entries:SearchRecent[]=[]; private undone:SearchRecent[]|null=null;
 private intent:{song:SongDto;account:string;generation:number|null;revision:number}|null=null; private revision=0;
 public unavailableTrack:SongDto|null=null;
 constructor(private storage:RecentStorage,private publish:(entries:SearchRecent[],canUndo:boolean,unavailableTrack?:SongDto|null)=>void,private now=()=>Date.now()){}
 private key(){return `sideb.searchRecents.v1:${encodeURIComponent(this.account)}`;}
 private emit(){this.publish([...this.entries],!!this.undone,this.unavailableTrack);}
 setAccount(account:string){if(this.initialized&&account===this.account)return;this.initialized=true;this.account=account;this.intent=null;this.unavailableTrack=null;++this.revision;this.entries=[];this.undone=null;this.emit();try{const data=JSON.parse(this.storage.getItem(this.key())??'null');if(data?.version===1&&Array.isArray(data.entries)){const seen=new Set<string>();this.entries=data.entries.map((entry:any)=>entry?.kind==='query'&&typeof entry.query==='string'?{...entry,query:normalizedQuery(entry.query),key:`query:${normalizedQuery(entry.query).toLowerCase()}`}:entry?.kind==='track'&&typeof entry.track?.videoId==='string'?{...entry,key:`track:${entry.track.isUpload?'upload:':'youtube:'}${entry.track.videoId}`}:entry).sort((a:any,b:any)=>(b?.lastUsedAt??0)-(a?.lastUsedAt??0)).filter((entry:any)=>{if(!entry||typeof entry.key!=='string'||!Number.isFinite(entry.lastUsedAt)||seen.has(entry.key))return false;const valid=entry.kind==='query'?typeof entry.query==='string'&&normalizedQuery(entry.query).length>0:entry.kind==='track'&&typeof entry.track?.videoId==='string'&&entry.track.videoId.length>0&&typeof entry.track.title==='string'&&typeof entry.track.artists==='string';if(valid)seen.add(entry.key);return valid;}).map((entry:SearchRecent)=>entry.kind==='track'?{...entry,track:safeTrack(entry.track)}:entry).slice(0,50);}}catch{}this.emit();}
 private save(){try{this.storage.setItem(this.key(),JSON.stringify({version:1,entries:this.entries}));}catch{}this.emit();}
 private use(entry:SearchRecent){this.entries=[entry,...this.entries.filter(item=>item.key!==entry.key)].slice(0,50);this.undone=null;this.save();}
 recordQuery(query:string){query=normalizedQuery(query);if(query)this.use({key:`query:${query.toLowerCase()}`,kind:'query',query,lastUsedAt:this.now()});}
 beginTrack(song:SongDto,generation:number|null=null){const revision=++this.revision;this.unavailableTrack=null;this.intent={song:safeTrack(song),account:this.account,generation,revision};this.emit();return revision;}
 bindTrack(revision:number,generation:number){if(this.intent?.revision===revision)this.intent.generation=generation;}
 failTrack(revision?:number){if(this.intent && (revision===undefined||this.intent.revision===revision)){this.unavailableTrack=this.intent.song;this.intent=null;this.emit();}}
 cancelTrack(revision?:number){if(revision===undefined||this.intent?.revision===revision)this.intent=null;}
 confirmPlayback(state:Pick<PlaybackStateDto,'generation'|'currentTrack'|'isPlaying'|'isLoading'|'error'>){const intent=this.intent;if(!intent||intent.generation===null)return;if(state.generation<intent.generation)return;if(state.generation>intent.generation){this.intent=null;return;}if(state.error){this.failTrack();return;}if(intent.account===this.account&&state.currentTrack?.videoId===intent.song.videoId&&state.isPlaying&&!state.isLoading){this.intent=null;this.use({key:`track:${intent.song.isUpload?'upload:':'youtube:'}${intent.song.videoId}`,kind:'track',track:intent.song,lastUsedAt:this.now()});}}
 remove(key:string){if(this.unavailableTrack && key===`track:${this.unavailableTrack.isUpload?'upload:':'youtube:'}${this.unavailableTrack.videoId}`)this.unavailableTrack=null;this.undone=[...this.entries];this.entries=this.entries.filter(item=>item.key!==key);this.save();}
 clear(){this.undone=[...this.entries];this.entries=[];this.save();}
 undo(){if(!this.undone)return;const restored=this.undone;this.undone=null;this.entries=restored;this.save();}
}
