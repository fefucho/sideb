import type {SearchSuggestionEntryDto} from '../types';

/** Presentation policy only: provider DTOs, tokens and entity order remain untouched. */
export function visibleSearchSuggestions(entries:SearchSuggestionEntryDto[],query:string):SearchSuggestionEntryDto[] {
 if(!query.trim())return entries;
 let textCount=0;
 return entries.filter(entry=>entry.kind==='media'||textCount++<3);
}
