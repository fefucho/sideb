import type {SearchSuggestionEntryDto} from '../types';

/** A suggestion is a video when its card or its playable payload says so; text queries always stay. */
export function suggestionAllowed(entry:SearchSuggestionEntryDto,showVideos:boolean):boolean {
 return showVideos||(entry.card?.kind!=='video'&&entry.song?.isVideo!==true);
}

/** Presentation policy only: provider DTOs, tokens and entity order remain untouched.
 * Videos are filtered first (preference), then the short completion list limit applies. */
export function visibleSearchSuggestions(entries:SearchSuggestionEntryDto[],query:string,showVideos=true):SearchSuggestionEntryDto[] {
 const allowed=showVideos?entries:entries.filter(entry=>suggestionAllowed(entry,false));
 if(!query.trim())return allowed;
 let textCount=0;
 return allowed.filter(entry=>entry.kind==='media'||textCount++<3);
}
