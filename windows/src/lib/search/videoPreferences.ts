import type {SearchPageDto,SearchSectionDto,SongDto} from '../types';
import {searchSectionRows} from './provider-rows';
import {songFromSearchCard} from './songs';

const sections=new WeakMap<SearchSectionDto,SearchSectionDto|null>();
const pages=new WeakMap<SearchPageDto,SearchPageDto>();

/** Remove video occurrences from one section, preserving every other payload object.
 * Payloads pair with cards by media ordinal (see provider-rows), so the kept payloads are
 * re-aligned 1:1 with the kept media cards; duplicate IDs never cross-wire. A card without a payload
 * receives its card-derived song only to keep that alignment. Roles are remapped by occurrence;
 * provider actions of an altered section are dropped because they may target hidden media.
 * Returns the same object when nothing is hidden and null when nothing remains. */
export function filterSearchSection(section:SearchSectionDto,showVideos:boolean):SearchSectionDto|null {
 if(showVideos)return section;
 if(sections.has(section))return sections.get(section)!;
 const rows=searchSectionRows(section);
 const keptIndices:number[]=[];
 const payloads:SongDto[]=[];
 const standalone:SongDto[]=[];
 let removed=false;
 for(const row of rows){
  if(row.itemIndex==null){ // payload without a card of its own
   if(row.song?.isVideo)removed=true;else if(row.song)standalone.push(row.song);
   continue;
  }
  const card=section.items[row.itemIndex];
  if(card.kind==='video'||row.song?.isVideo===true){removed=true;continue;}
  keptIndices.push(row.itemIndex);
  if(['song','video'].includes(card.kind)){
   const song=row.song??songFromSearchCard(card);
   if(song)payloads.push(song);
  }
 }
 let result:SearchSectionDto|null=section;
 if(removed){
  if(!keptIndices.length&&!standalone.length)result=null;
  else{
   const remap=new Map(keptIndices.map((index,position)=>[index,position]));
   const mapped=(index:number|null|undefined)=>index==null?undefined:remap.get(index);
   const primary=mapped(section.primaryItemIndex);
   result={...section,items:keptIndices.map(index=>section.items[index]),songs:[...payloads,...standalone],
    primaryItemIndex:primary??null,
    relatedItemIndices:(section.relatedItemIndices??[]).flatMap(index=>{const next=mapped(index);return next==null?[]:[next];}),
    actions:[]};
  }
 }
 sections.set(section,result);
 return result;
}

/** Page projection. Sections are cached by identity so an appended continuation reuses earlier work;
 * the continuation token, chips and correction are original provider data. */
export function filterSearchPage(page:SearchPageDto|null,showVideos:boolean):SearchPageDto|null {
 if(!page||showVideos)return page;
 const cached=pages.get(page);if(cached)return cached;
 let changed=false;
 const next:SearchSectionDto[]=[];
 for(const section of page.sections){
  const filtered=filterSearchSection(section,false);
  if(filtered!==section)changed=true;
  if(filtered)next.push(filtered);
 }
 const result=changed?{...page,sections:next}:page;
 pages.set(page,result);return result;
}
