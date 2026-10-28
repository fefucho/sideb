export interface SearchViewportItem {key:string}
export interface SearchViewportAnchor {key:string;offset:number}

/** Geometry is independent of Svelte. Scroll uses binary searches, never a scan of rows. */
export class SearchViewportGeometry {
 offsets:number[]=[0];
 keys:string[]=[];
 indices=new Map<string,number>();
 private measurements=new Map<string,number>();
 private estimates:number[]=[];
 private context='';
 private content=new Map<string,{item:SearchViewportItem;revision:number}>();
 private contexts:string[]=[];
 private measurementKey(key:string){return `${this.context}\0${key}\0${this.content.get(key)?.revision??0}`;}
 setItems<T extends SearchViewportItem>(items:T[],width:number,style:string,estimate:(item:T,width:number)=>number){
  this.context=`${Math.round(width)}:${style}`;
  // Retain a few recent widths for sidebar toggles, bound live-resize cache growth.
  if(!this.contexts.includes(this.context)){
   this.contexts.push(this.context);
   if(this.contexts.length>4){const removed=this.contexts.shift()!;for(const key of this.measurements.keys())if(key.startsWith(`${removed}\0`))this.measurements.delete(key);}
  }
  const nextContent=new Map<string,{item:SearchViewportItem;revision:number}>();
  for(const item of items){const previous=this.content.get(item.key);nextContent.set(item.key,{item,revision:previous&&previous.item!==item?previous.revision+1:previous?.revision??0});}
  this.content=nextContent;
  for(const key of this.measurements.keys()){
   const [,itemKey,version]=key.split('\0');
   if(this.content.get(itemKey)?.revision!==Number(version))this.measurements.delete(key);
  }
  this.keys=items.map(item=>item.key);
  this.indices=new Map(this.keys.map((key,index)=>[key,index]));
  this.estimates=items.map(item=>estimate(item,width));
  this.rebuild();
 }
 private rebuild(){
  const offsets=[0];
  this.keys.forEach((key,index)=>offsets.push(offsets[index]+(this.measurements.get(this.measurementKey(key))??this.estimates[index])));
  this.offsets=offsets;
 }
 get total(){return this.offsets[this.keys.length]??0;}
 indexAt(offset:number){
  let low=0,high=this.keys.length;
  while(low<high){const middle=(low+high)>>>1;if(this.offsets[middle+1]<=offset)low=middle+1;else high=middle;}
  return Math.min(low,Math.max(0,this.keys.length-1));
 }
 range(top:number,height:number,overscan=320){
  if(!this.keys.length)return {start:0,end:0};
  const start=this.indexAt(Math.max(0,top-overscan));
  let low=start,high=this.keys.length;
  const edge=top+height+overscan;
  while(low<high){const middle=(low+high)>>>1;if(this.offsets[middle]<edge)low=middle+1;else high=middle;}
  return {start,end:Math.max(start+1,low)};
 }
 anchor(top:number):SearchViewportAnchor|null{
  if(!this.keys.length)return null;
  const index=this.indexAt(Math.max(0,top));return {key:this.keys[index],offset:top-this.offsets[index]};
 }
 position(anchor:SearchViewportAnchor|null){
  if(!anchor)return null;const index=this.indices.get(anchor.key);return index==null?null:this.offsets[index]+anchor.offset;
 }
 measure(changes:Map<string,number>){
  let changed=false;
  for(const [key,height] of changes){
   if(!this.indices.has(key)||!Number.isFinite(height)||height<=0)continue;
   const cacheKey=this.measurementKey(key);
   const index=this.indices.get(key)!;
   const previous=this.measurements.get(cacheKey)??this.estimates[index];
   if(Math.abs(previous-height)>.5){this.measurements.set(cacheKey,height);changed=true;}
  }
  if(changed)this.rebuild();
  return changed;
 }
 clear(){this.measurements.clear();this.contexts=[];this.rebuild();}
}
