import type {BrowseCardDto,SearchPageDto,SearchSuggestionEntryDto,SongDto} from '../types';
import {categoryOfCard,categoryPage,emptyCategoryInput,type SearchCategory} from './categories';
import {projectSearchSection,searchSectionRows} from './provider-rows';

/** What the quick search shows, in the order the keyboard walks it. Mirrors Apple `QuickSearchPresentation` (FIX-333/336).
 *
 * Empty field: one «Recent» list, local entries first (opened artists/albums/playlists and played songs) completed
 * with the provider's own history, without duplicates. Typing: the top result, small groups per type and, last,
 * the text completions. The user's own history is for the empty field, never for typing. */
export type QuickStyle='recents'|'top'|'queries'|'media';
export interface QuickSection {id:string;title:string|null;style:QuickStyle;entries:SearchSuggestionEntryDto[]}
export interface QuickPresentation {sections:QuickSection[];entries:SearchSuggestionEntryDto[]}
export interface QuickTitles {recents:string;queries:string;top:string;category:(category:SearchCategory)=>string}

export const LOCAL_PREFIX='local:';
export const MAX_RECENTS=10;
export const MAX_LOCAL=8;
export const MAX_QUERIES=3;
const maxPerGroup=(category:SearchCategory)=>category==='songs'?4:3;
/** Categories worth a group in a dropdown; profiles, podcasts and episodes stay on the results page. */
const QUICK_CATEGORIES:SearchCategory[]=['songs','artists','albums','playlists','videos'];

export const isLocalEntry=(entry:SearchSuggestionEntryDto)=>entry.id.startsWith(LOCAL_PREFIX);
export const localKeyOf=(entry:SearchSuggestionEntryDto)=>isLocalEntry(entry)?entry.id.slice(LOCAL_PREFIX.length):null;
const isMedia=(entry:SearchSuggestionEntryDto)=>entry.kind==='media'||Boolean(entry.card||entry.song);

function normalizedQuery(query:string){return query.trim().replace(/\s+/gu,' ').normalize('NFC').toLowerCase();}
/** Identity used to drop a provider entry the user already has locally. */
function identity(entry:SearchSuggestionEntryDto):string|null {
 if(entry.song)return `song:${entry.song.videoId}`;
 if(entry.card)return entry.card.kind==='song'||entry.card.kind==='video'?`song:${entry.card.id}`:`${entry.card.kind}:${entry.card.id}`;
 const text=entry.query?normalizedQuery(entry.query):'';
 return text?`query:${text}`:null;
}
function categoryOfEntry(entry:SearchSuggestionEntryDto):SearchCategory|null {
 if(entry.song)return entry.song.isVideo?'videos':'songs';
 return entry.card?categoryOfCard(entry.card):null;
}
function mediaEntry(id:string,card:BrowseCardDto|null,song:SongDto|null):SearchSuggestionEntryDto {
 return {id,kind:'media',query:null,runs:[],feedbackToken:null,card,song};
}
const hidden=(card:BrowseCardDto|null,song:SongDto|null)=>card?.kind==='video'||song?.isVideo===true;

/** Top result and groups from a full provider search: the principal block, the songs related to it and the page's own
 * categories (shelves such as «Listen again» are not results). */
function pageSections(page:SearchPageDto,showVideos:boolean,titles:QuickTitles):QuickSection[] {
 const sections:QuickSection[]=[];const seen=new Set<string>();
 let related:SearchSuggestionEntryDto[]=[];
 const topSection=page.sections.find(section=>section.layout==='top');
 if(topSection){
  const projection=projectSearchSection(topSection);
  const primary=projection.primary;
  if(primary&&(primary.card||primary.song)&&(showVideos||!hidden(primary.card,primary.song))){
   const entry=mediaEntry(`page:${topSection.id}:${primary.itemIndex}`,primary.card,primary.song);
   const key=identity(entry);if(key)seen.add(key);
   sections.push({id:'top',title:titles.top,style:'top',entries:[entry]});
   related=projection.related.filter(row=>row.song&&(showVideos||!hidden(row.card,row.song))).map(row=>mediaEntry(`page:${topSection.id}:${row.itemIndex}`,row.card,row.song));
  }
 }
 const groups=new Map<SearchCategory,SearchSuggestionEntryDto[]>();const order:SearchCategory[]=[];
 for(const section of categoryPage(page,emptyCategoryInput(),()=>'').sections){
  if(!section.layout.startsWith('category-'))continue;
  const category=section.id.slice('category:'.length) as SearchCategory;
  if(!QUICK_CATEGORIES.includes(category))continue;
  order.push(category);
  groups.set(category,searchSectionRows(section).filter(row=>row.card&&(showVideos||!hidden(row.card,row.song))).map(row=>mediaEntry(`page:${section.id}:${row.itemIndex}`,row.card,row.song)));
 }
 if(related.length){if(!groups.has('songs'))order.unshift('songs');groups.set('songs',[...related,...(groups.get('songs')??[])]);}
 for(const category of order){
  const entries:SearchSuggestionEntryDto[]=[];
  for(const entry of groups.get(category)??[]){
   const key=identity(entry);
   if(key){if(seen.has(key))continue;seen.add(key);}
   entries.push(entry);
   if(entries.length===maxPerGroup(category))break;
  }
  if(entries.length)sections.push({id:`group:${category}`,title:titles.category(category),style:'media',entries});
 }
 return sections;
}

export function quickPresentation(options:{draft:string;local:SearchSuggestionEntryDto[];remote:SearchSuggestionEntryDto[];page?:SearchPageDto|null;showVideos?:boolean;titles:QuickTitles}):QuickPresentation {
 const {draft,local,remote,page=null,showVideos=true,titles}=options;
 const build=(sections:QuickSection[])=>({sections,entries:sections.flatMap(section=>section.entries)});
 if(!draft.trim()){
  const own=local.slice(0,MAX_LOCAL);
  const seen=new Set(own.map(identity).filter((key):key is string=>Boolean(key)));
  const list=[...own];
  for(const entry of remote){
   if(list.length>=MAX_RECENTS)break;
   const key=identity(entry);if(key&&seen.has(key))continue;if(key)seen.add(key);
   list.push(entry);
  }
  return build(list.length?[{id:'recents',title:titles.recents,style:'recents',entries:list}]:[]);
 }
 let sections=page?pageSections(page,showVideos,titles):[];
 if(!sections.length){
  const media=remote.filter(isMedia);
  if(media.length)sections.push({id:'top',title:titles.top,style:'top',entries:[media[0]]});
  const order:SearchCategory[]=[];const groups=new Map<SearchCategory,SearchSuggestionEntryDto[]>();const other:SearchSuggestionEntryDto[]=[];
  for(const entry of media.slice(1)){
   const category=categoryOfEntry(entry);
   if(!category){other.push(entry);continue;}
   if(!groups.has(category))order.push(category);
   const list=groups.get(category)??[];if(list.length<maxPerGroup(category))list.push(entry);groups.set(category,list);
  }
  for(const category of order)sections.push({id:`group:${category}`,title:titles.category(category),style:'media',entries:groups.get(category)!});
  if(other.length)sections.push({id:'group:other',title:null,style:'media',entries:other.slice(0,3)});
 }
 const completions=remote.filter(entry=>!isMedia(entry)&&entry.kind!=='history').slice(0,MAX_QUERIES);
 if(completions.length)sections.push({id:'queries',title:titles.queries,style:'queries',entries:completions});
 return build(sections);
}
