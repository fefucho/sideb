import type {BrowseCardDto,SearchSectionDto,SongDto} from '../types';
import {contentRating} from '../contentRating';

export interface SearchSectionRow {card:BrowseCardDto|null;song:SongDto|null;itemIndex:number|null;songIndex?:number|null}
export interface SearchSectionProjection {primary:SearchSectionRow|null;related:SearchSectionRow[];remaining:SearchSectionRow[];explicit:boolean}

/** YouTube omits the artist from the rows under an artist's top result (the artist is implied by the
 * card) and the core leaves it empty on purpose instead of guessing (#216). Those rows are that artist's
 * songs, so they inherit its name, id and link. A row that names its artist, or a principal that is not an
 * artist, is left untouched. Mirrors Apple `ProviderSearchProjection.inheritingArtist` (FIX-337). */
function principalArtist(section:SearchSectionDto):{name:string;id:string}|null {
 const index=section.primaryItemIndex;
 if(section.layout!=='top'||index==null)return null;
 const card=section.items[index];
 return card&&card.kind==='artist'?{name:card.title,id:card.id}:null;
}
export function inheritingArtist(song:SongDto,artist:{name:string;id:string}|null):SongDto {
 if(!artist||song.artists.trim()||song.artistRuns?.length)return song;
 return {...song,artists:artist.name,artistId:artist.id,artistRuns:[{text:artist.name,id:artist.id}]};
}

/** Match the Mac projection: media ordinal + ID first, then an unambiguous ID.
 * Never attach a duplicate payload to a different ordinal after a mismatch. Keep
 * unused DTO occurrences as standalone rows instead of silently dropping them. */
function providerRows(section:SearchSectionDto):SearchSectionRow[] {
 const artist=principalArtist(section);
 const payloads=new Map<string,{count:number;index:number}>();
 const payloadIds:string[]=[];
 section.songs.forEach((song,index)=>{
  const id=song.videoId;
  payloadIds.push(id);
  const previous=payloads.get(id);
  payloads.set(id,{count:(previous?.count??0)+1,index});
 });
 const usedSongs=new Set<number>();
 let mediaPosition=0;
 const rows:SearchSectionRow[]=section.items.map((card,itemIndex)=>{
  let songIndex=-1;
  if(['song','video'].includes(card.kind)){
   const ordinal=mediaPosition++;
   const payload=payloads.get(card.id);
   if(payloadIds[ordinal]===card.id&&!usedSongs.has(ordinal))songIndex=ordinal;
   else if(payload?.count===1&&!usedSongs.has(payload.index))songIndex=payload.index;
  }
  if(songIndex>=0)usedSongs.add(songIndex);
  const song=songIndex>=0?section.songs[songIndex]:null;
  const rating=contentRating(card);
  const rated=song && contentRating(song)==='unknown' && rating!=='unknown' && payloadIds[songIndex]===card.id ? {...song,contentRating:rating} : song;
  return {card,song:rated?inheritingArtist(rated,artist):rated,itemIndex,songIndex:songIndex>=0?songIndex:null};
 });
 section.songs.forEach((song,index)=>{if(!usedSongs.has(index))rows.push({card:null,song:inheritingArtist(song,artist),itemIndex:null,songIndex:index});});
 return rows;
}

// Provider controllers replace sections when content changes and preserve them on append.
// Playback changes never invalidate the occurrence payload projection.
const projections=new WeakMap<SearchSectionDto,SearchSectionProjection>();

/** Pair card/song occurrences and project only provider-declared principal relationships. */
export function projectSearchSection(section:SearchSectionDto):SearchSectionProjection {
 const cached=projections.get(section);if(cached)return cached;
 const rows=providerRows(section);
 const primaryIndex=section.primaryItemIndex;
 const relatedIndices=section.relatedItemIndices??[];
 const indices=[...(primaryIndex==null?[]:[primaryIndex]),...relatedIndices];
 const providerOrdered=relatedIndices.every((index,position)=>position===0||relatedIndices[position-1]<index);
 const primaryKind=primaryIndex==null?null:section.items[primaryIndex]?.kind;
 const supportedPrimary=primaryKind==null?Boolean(rows.find(row=>row.itemIndex===primaryIndex)?.song):['artist','album','song','video','playlist'].includes(primaryKind);
 const valid=section.layout==='top'&&primaryIndex!=null&&Number.isInteger(primaryIndex)&&primaryIndex>=0&&primaryIndex<section.items.length&&supportedPrimary&&
  relatedIndices.every(index=>Number.isInteger(index)&&index>primaryIndex&&index<section.items.length)&&
  new Set(indices).size===indices.length&&providerOrdered;
 if(!valid){const result={primary:null,related:[],remaining:rows,explicit:false};projections.set(section,result);return result;}
 const associated=new Set(indices);
 const primary=rows[primaryIndex]??null;
 const related=relatedIndices.map(index=>rows[index]);
 const result={primary,related,remaining:rows.filter(row=>row.itemIndex==null||!associated.has(row.itemIndex)),explicit:true};
 projections.set(section,result);return result;
}

/** Compatibility helper for callers that need the full provider sequence. */
export function searchSectionRows(section:SearchSectionDto):SearchSectionRow[]{
 return providerRows(section);
}
