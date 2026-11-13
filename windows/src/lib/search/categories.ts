import type {BrowseCardDto,SearchPageDto,SearchSectionDto,SongDto} from '../types';
import {searchSectionRows} from './provider-rows';
import {songFromSearchCard} from './songs';

/** Apple-Music-style grouping of YouTube Music results. Mirrors Apple `ProviderSearchCategories` (FIX-332). */
export type SearchCategory='songs'|'artists'|'albums'|'playlists'|'videos'|'profiles'|'podcasts'|'episodes';
/** What a provider category chip returns; its `params` request that type alone (the same request «Show all» uses). */
export type ChipKind='songs'|'videos'|'albums'|'artists'|'communityPlaylists'|'episodes'|'profiles'|'featuredPlaylists'|'podcasts';

export const SEARCH_CATEGORIES:SearchCategory[]=['songs','artists','albums','playlists','videos','profiles','podcasts','episodes'];
const CHIP_KINDS:ChipKind[]=['songs','videos','albums','artists','communityPlaylists','episodes','profiles','featuredPlaylists','podcasts'];
const CORE_KINDS:ChipKind[]=['songs','artists','albums','featuredPlaylists','communityPlaylists'];

export const MAX_CATEGORY_ITEMS=20;
export const GRID_ROWS=3;
export const GRID_ROW_HEIGHT=58;
export const GRID_BOTTOM_GAP=8;
export const GRID_HEIGHT=GRID_ROWS*GRID_ROW_HEIGHT+GRID_BOTTOM_GAP;
export const CAROUSEL_HEIGHT=252;
export const LOADING_HEIGHT=72;
/** Columns follow the width, never the pixel: the grid always has `GRID_ROWS` rows so its height is constant. */
export function gridColumns(width:number):number {return width>=880?3:width>=560?2:1;}

export const categoryTitleKey:Record<SearchCategory,string>={songs:'search.filter.songs',artists:'search.filter.artists',albums:'search.filter.albums',playlists:'search.filter.playlists',videos:'search.filter.videos',profiles:'search.category.profiles',podcasts:'search.category.podcasts',episodes:'search.category.episodes'};
/** Songs and videos are rows (a grid of compact rows); everything else is a carousel of cards. */
export const categoryUsesGrid=(category:SearchCategory)=>category==='songs'||category==='videos';

export function chipKindOfTitle(title:string):ChipKind|null {
 switch(title.trim().toLowerCase()){
  case 'songs':return 'songs';case 'videos':return 'videos';case 'albums':return 'albums';case 'artists':return 'artists';
  case 'community playlists':return 'communityPlaylists';case 'episodes':return 'episodes';case 'profiles':return 'profiles';
  case 'featured playlists':return 'featuredPlaylists';case 'podcasts':return 'podcasts';default:return null;
 }
}
export function categoryOfChipKind(kind:ChipKind):SearchCategory {
 switch(kind){
  case 'communityPlaylists':case 'featuredPlaylists':return 'playlists';
  default:return kind as SearchCategory;
 }
}
/** Titles of provider shelves that already carry one category. */
export function categoryOfShelfTitle(title:string):SearchCategory|null {
 switch(title.trim().toLowerCase()){
  case 'songs':return 'songs';case 'videos':return 'videos';case 'albums':return 'albums';case 'artists':return 'artists';
  case 'featured playlists':case 'community playlists':case 'playlists':return 'playlists';
  case 'profiles':return 'profiles';case 'podcasts':return 'podcasts';case 'episodes':return 'episodes';default:return null;
 }
}
/** The type is not always in `kind`: profiles arrive as `artist` and podcasts as `playlist` (their subtitle
 * starts with the provider's type word) and a video can arrive as a `song` whose payload says `isVideo`. */
export function categoryOfCard(card:BrowseCardDto,song?:SongDto|null):SearchCategory|null {
 const subtitle=(card.subtitle??'').trim().toLowerCase();
 switch(card.kind){
  case 'song':return song?.isVideo?'videos':'songs';
  case 'video':return 'videos';
  case 'album':return 'albums';
  case 'artist':return subtitle.startsWith('profile')?'profiles':'artists';
  case 'playlist':return subtitle.startsWith('podcast')?'podcasts':'playlists';
  case 'episode':return 'episodes';
  default:return null;
 }
}

export interface CategoryInput {chipPages:Partial<Record<ChipKind,SearchPageDto>>;pending:ChipKind[]}
export const emptyCategoryInput=():CategoryInput=>({chipPages:{},pending:[]});

export function chipParams(page:SearchPageDto):Partial<Record<ChipKind,string>> {
 const result:Partial<Record<ChipKind,string>>={};
 for(const chip of page.chips){
  const kind=chipKindOfTitle(chip.title);
  if(kind&&chip.params&&result[kind]==null)result[kind]=chip.params;
 }
 return result;
}

interface Entry {card:BrowseCardDto;song:SongDto|null}
/** Items of the provider's own page grouped by type, keeping their order. Titled shelves that are not a known
 * category («Listen again», personalized strips) are not search results and are skipped. */
function mixedBuckets(page:SearchPageDto):Map<SearchCategory,Entry[]> {
 const result=new Map<SearchCategory,Entry[]>();
 for(const section of page.sections){
  if(section.layout==='top')continue;
  const title=section.title.trim();
  if(title&&!categoryOfShelfTitle(title))continue;
  for(const row of searchSectionRows(section)){
   if(!row.card)continue;
   const category=categoryOfCard(row.card,row.song);
   if(!category)continue;
   const list=result.get(category)??[];list.push({card:row.card,song:row.song});result.set(category,list);
  }
 }
 return result;
}

/** Chip requests to run, in the provider's chip order: the core categories plus those already present. */
export function fetchTargets(page:SearchPageDto,showVideos:boolean):{kind:ChipKind;params:string}[] {
 const params=chipParams(page);
 const present=new Set(mixedBuckets(page).keys());
 const wanted=new Set<ChipKind>(CORE_KINDS);
 if(showVideos)wanted.add('videos');
 for(const kind of CHIP_KINDS)if(present.has(categoryOfChipKind(kind)))wanted.add(kind);
 if(!showVideos)wanted.delete('videos');
 const seen=new Set<ChipKind>();const result:{kind:ChipKind;params:string}[]=[];
 for(const chip of page.chips){
  const kind=chipKindOfTitle(chip.title);
  const value=kind?params[kind]:undefined;
  if(!kind||!wanted.has(kind)||seen.has(kind)||!value)continue;
  seen.add(kind);result.push({kind,params:value});
 }
 return result;
}

function fetched(kinds:ChipKind[],category:SearchCategory,input:CategoryInput):Entry[]|null {
 const loaded=kinds.map(kind=>input.chipPages[kind]).filter((page):page is SearchPageDto=>Boolean(page));
 if(!loaded.length)return null;
 const result:Entry[]=[];const seen=new Set<string>();
 for(const page of loaded)for(const section of page.sections)for(const row of searchSectionRows(section)){
  if(!row.card||categoryOfCard(row.card,row.song)!==category)continue;
  // Playlists come from two chips; the same playlist must not appear twice.
  if(category!=='songs'&&category!=='videos'){const key=`${row.card.kind}:${row.card.id}`;if(seen.has(key))continue;seen.add(key);}
  result.push({card:row.card,song:row.song});
 }
 return result;
}

/** The page in category form: the principal block first, then one section per category.
 * Section order is the provider's chip order, its own ranking of the categories for this query. */
export function categoryPage(page:SearchPageDto,input:CategoryInput,title:(category:SearchCategory)=>string):SearchPageDto {
 const tops=page.sections.filter(section=>section.layout==='top');
 const mixed=mixedBuckets(page);const params=chipParams(page);
 const order:SearchCategory[]=[];
 for(const chip of page.chips){const kind=chipKindOfTitle(chip.title);if(kind){const category=categoryOfChipKind(kind);if(!order.includes(category))order.push(category);}}
 for(const category of SEARCH_CATEGORIES)if(!order.includes(category))order.push(category);
 const sections:SearchSectionDto[]=[];
 for(const category of order){
  const kinds=CHIP_KINDS.filter(kind=>categoryOfChipKind(kind)===category);
  const pending=kinds.some(kind=>input.pending.includes(kind));
  const entries=fetched(kinds,category,input)??mixed.get(category)??[];
  if(!entries.length&&!pending)continue;
  const capped=entries.slice(0,MAX_CATEGORY_ITEMS);
  const showAll=kinds.map(kind=>params[kind]).find(Boolean)??null;
  sections.push({id:`category:${category}`,title:title(category),
   layout:capped.length?(categoryUsesGrid(category)?'category-grid':'category-carousel'):'category-loading',
   items:capped.map(entry=>entry.card),
   songs:capped.filter(entry=>entry.card.kind==='song'||entry.card.kind==='video').map(entry=>entry.song??songFromSearchCard(entry.card)!),
   primaryItemIndex:null,relatedItemIndices:[],moreQuery:null,moreParams:capped.length?showAll:null,moreBrowseId:null,actions:[]});
 }
 return {chips:page.chips,correction:page.correction,sections:[...tops,...sections],continuation:null};
}
