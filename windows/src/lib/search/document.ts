import type {SearchPageDto, SearchSectionDto} from '../types';
import {projectSearchSection, type SearchSectionProjection, type SearchSectionRow} from './provider-rows';

export type SearchDocumentEntry =
 | {kind:'heading';key:string;section:SearchSectionDto;showTitle:boolean}
 | {kind:'principal';key:string;section:SearchSectionDto;projection:SearchSectionProjection}
 | {kind:'actions';key:string;section:SearchSectionDto}
 | {kind:'row';key:string;section:SearchSectionDto;row:SearchSectionRow}
 | {kind:'carousel';key:string;section:SearchSectionDto;rows:SearchSectionRow[]};

const documents=new WeakMap<SearchPageDto,SearchDocumentEntry[]>();
const sectionEntries=new WeakMap<SearchSectionDto,Map<number,SearchDocumentEntry[]>>();
/** Flatten once per provider page. Stable occurrence keys survive append and playback. */
export function projectSearchDocument(page:SearchPageDto|null):SearchDocumentEntry[] {
 if(!page)return [];
 const cached=documents.get(page);if(cached)return cached;
 const entries:SearchDocumentEntry[]=[];
 page.sections.forEach((section,sectionIndex)=>{
  let variants=sectionEntries.get(section);
  if(!variants){variants=new Map();sectionEntries.set(section,variants);}
  let block=variants.get(sectionIndex);
  if(!block){
   block=[];
   const prefix=`section:${sectionIndex}:${section.id}`;
   const projection=projectSearchSection(section);
   const more=Boolean(section.moreParams||section.moreBrowseId||section.moreQuery);
   // A principal already displays its title. A remote "show all" stays accessible.
   if((!projection.explicit&&section.title.trim())||more)block.push({kind:'heading',key:`${prefix}:heading`,section,showTitle:!projection.explicit&&Boolean(section.title.trim())});
   if(projection.explicit)block.push({kind:'principal',key:`${prefix}:principal`,section,projection});
   else if(section.actions.length)block.push({kind:'actions',key:`${prefix}:actions`,section});
   if(section.layout==='carousel'&&projection.remaining.length)block.push({kind:'carousel',key:`${prefix}:carousel`,section,rows:projection.remaining});
   else projection.remaining.forEach(row=>block!.push({kind:'row',key:`${prefix}:${row.itemIndex==null?`song:${row.songIndex}`:`item:${row.itemIndex}`}`,section,row}));
   variants.set(sectionIndex,block);
  }
  entries.push(...block);
 });
 documents.set(page,entries);return entries;
}

export function estimateSearchEntryHeight(entry:SearchDocumentEntry,width:number):number {
 switch(entry.kind){
  case 'heading':return 44;
  case 'actions':return 56;
  case 'row':return 58;
  case 'carousel':return 248;
  case 'principal':{
   const artist=entry.projection.primary?.card?.kind==='artist';
   const related=Math.min(3,entry.projection.related.length)*58+(entry.projection.related.length>3?40:0);
   return 16+Math.max(112,artist&&width>=960?related:0)+(artist&&width>=960?0:related?related+20:0)+16+16;
  }
 }
}

export function searchEntryCanFocus(entry:SearchDocumentEntry,primaryOnly=false):boolean {
 if(primaryOnly&&(entry.kind==='heading'||entry.kind==='actions'))return false;
 if(entry.kind==='heading')return Boolean(entry.section.moreParams||entry.section.moreBrowseId||entry.section.moreQuery);
 if(entry.kind==='actions')return entry.section.actions.length>0;
 return true;
}
