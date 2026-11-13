import type {BrowseCardDto,SearchSuggestionEntryDto,SongDto} from '../types';
import {ENTITY_KINDS,type SearchRecent,type SearchRecentStore} from './recents';
import {LOCAL_PREFIX} from './quickPresentation';

/** Record an artist, album or playlist the user opened; songs and queries are not recorded here. */
export function recordOpenedCard(store:Pick<SearchRecentStore,'recordEntity'>,card:BrowseCardDto){
 if((ENTITY_KINDS as readonly string[]).includes(card.kind))store.recordEntity(card);
}

/** Start playback for a search choice. The recent is recorded only once playback really starts (the store binds the
 * accepted generation); a rejected start leaves it unrecorded and reports the failure to the caller. */
export function startRecentSong(store:Pick<SearchRecentStore,'beginTrack'|'bindTrack'|'failTrack'>,song:SongDto,
 start:(song:SongDto,onAcceptedGeneration:(generation:number)=>void)=>Promise<void>):Promise<void> {
 const revision=store.beginTrack(song);
 return start(song,generation=>store.bindTrack(revision,generation)).catch(error=>{store.failTrack(revision);throw error;});
}

/** Side B's own recents shaped as suggestion entries so rows, keyboard order and activation are shared with the
 * provider's entries. Queries are never stored locally (the provider keeps that history). */
export function recentSuggestion(entry:SearchRecent):SearchSuggestionEntryDto|null {
 const id=LOCAL_PREFIX+entry.key;
 const base={id,kind:'history',query:null,runs:[],feedbackToken:null};
 if(entry.kind==='query')return {...base,query:entry.query,card:null,song:null};
 if(entry.kind==='track')return {...base,card:null,song:entry.track};
 return {...base,card:{kind:entry.card.kind,id:entry.card.id,title:entry.card.title,subtitle:entry.card.subtitle,thumbnail:entry.card.thumbnail,duration:null},song:null};
}
