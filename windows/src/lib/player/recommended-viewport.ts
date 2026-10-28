import type { BrowseCardDto, SongDto } from '../types';
import type { RecommendedData } from './recommendations';

export interface RecommendedOccurrence { index:number; song:SongDto }
export interface RecommendedColumn { key:string; songs:RecommendedOccurrence[]; artist?:BrowseCardDto }
export interface RecommendedShelf { kind:'artist'|'album'|'similar'|'relatedArtists'; name:string|null; browseId:string|null; columns:RecommendedColumn[] }
const projections=new WeakMap<RecommendedData,RecommendedShelf[]>();
/** Provider sequence and duplicate occurrences remain intact. No playback state is projected. */
export function recommendedShelves(data:RecommendedData):RecommendedShelf[]{
 const cached=projections.get(data);if(cached)return cached;
 const columns=(songs:SongDto[])=>{const result:RecommendedColumn[]=[];for(let index=0;index<songs.length;index+=3)result.push({key:String(index/3),songs:songs.slice(index,index+3).map((song,offset)=>({index:index+offset,song}))});return result;};
 const shelves:RecommendedShelf[]=[
  {kind:'artist',name:data.artistName,browseId:data.artistBrowseId,columns:columns(data.artistSongs)},
  {kind:'album',name:data.albumTitle,browseId:data.albumBrowseId,columns:columns(data.albumSongs)},
  {kind:'similar',name:null,browseId:null,columns:columns(data.similarSongs)},
  {kind:'relatedArtists',name:null,browseId:null,columns:data.relatedArtists.map((artist,index)=>({key:String(index),songs:[],artist}))},
 ];
 const result=shelves.filter(shelf=>shelf.columns.length);projections.set(data,result);return result;
}
export function recommendedOffsets<T>(items:T[],size:(item:T)=>number,gap:number,inset=0){const result=[inset];for(const item of items)result.push(result.at(-1)!+size(item)+gap);return result;}
export function recommendedRange(offsets:number[],position:number,extent:number,overscan=0){
 const count=offsets.length-1;if(!count)return {start:0,end:0};
 let low=0,high=count;const top=Math.max(0,position-overscan);
 while(low<high){const middle=(low+high)>>>1;if(offsets[middle+1]<=top)low=middle+1;else high=middle;}
 const start=Math.min(low,count-1);low=start;high=count;const edge=position+extent+overscan;
 while(low<high){const middle=(low+high)>>>1;if(offsets[middle]<edge)low=middle+1;else high=middle;}
 return {start,end:Math.max(start+1,low)};
}
