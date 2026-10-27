<script lang="ts" generics="T extends SearchViewportItem">
 import {onMount,tick,untrack,type Snippet} from 'svelte';
 import {SearchViewportGeometry,type SearchViewportItem} from '$lib/search/viewport';
 interface Props {items:T[];estimate:(item:T,width:number)=>number;canFocus?:(item:T,primaryOnly:boolean)=>boolean;children:Snippet<[T,number]>;scrollElement?:HTMLElement|null;active?:boolean;documentKey:string;styleKey?:string}
 let {items,estimate,canFocus=()=>true,children,scrollElement=null,active=true,documentKey,styleKey=''}:Props=$props();
 let host:HTMLDivElement;
 let mounted=$state(false);
 let snapshot=$state(untrack(()=>items));
 let width=$state(1000);
 let top=$state(0);
 let viewport=$state(800);
 let revision=$state(0);
 let focusKey=$state<string|null>(null);
 let menuKey=$state<string|null>(null);
 let requestedKey=$state<string|null>(null);
 let currentDocument=untrack(()=>documentKey);
 const geometry=new SearchViewportGeometry();
 untrack(()=>geometry.setItems(snapshot,width,styleKey,estimate));
 const range=$derived.by(()=>{revision;return geometry.range(top,viewport);});
 const total=$derived.by(()=>{revision;return geometry.total;});
 const visible=$derived.by(()=>{
  revision;
  const indices=new Set<number>();
  for(let index=range.start;index<range.end;index++)indices.add(index);
  for(const key of [focusKey,menuKey,requestedKey]){const index=key==null?undefined:geometry.indices.get(key);if(index!=null)indices.add(index);}
  return [...indices].sort((a,b)=>a-b).map(index=>({item:snapshot[index],index,offset:geometry.offsets[index]}));
 });
 let rowObserver:ResizeObserver|null=null;
 let scheduleMeasurements=()=>{};
 let sync=()=>{};
 const rowNodes=new Map<string,HTMLDivElement>();

 function root(){return scrollElement??host?.closest<HTMLElement>('.results-scroll')??null;}
 function restore(anchor:ReturnType<SearchViewportGeometry['anchor']>,previousTop:number){
  const next=geometry.position(anchor),scroll=root();
  if(scroll&&next!=null&&Math.abs(next-previousTop)>.5)scroll.scrollTop+=next-previousTop;
 }
 $effect(()=>{
  if(!active)return;
  const next=items,nextWidth=width,nextStyle=styleKey,nextDocument=documentKey;
  untrack(()=>{
   const changedDocument=currentDocument!==nextDocument;
   const anchor=changedDocument?null:geometry.anchor(top),previousTop=top;
   if(changedDocument){
    geometry.clear();focusKey=null;menuKey=null;requestedKey=null;currentDocument=nextDocument;
    const scroll=root();if(scroll)scroll.scrollTop=0;top=0;
   }
   snapshot=next;geometry.setItems(next,nextWidth,nextStyle,estimate);
   revision++;
   restore(anchor,previousTop);
   void tick().then(()=>{sync();scheduleMeasurements();});
  });
 });

 function measureRow(node:HTMLDivElement,key:string){
  rowNodes.set(key,node);rowObserver?.observe(node);scheduleMeasurements();
  return {destroy(){rowObserver?.unobserve(node);rowNodes.delete(key);}};
 }
 onMount(()=>{mounted=true;});
 $effect(()=>{
  if(!mounted||!active)return;
  scrollElement;
  const scroll=root();if(!scroll)return;
  let frame=0,measureFrame=0;
  let pending=new Map<string,number>();
  const readPosition=()=>{
   const bounds=host.getBoundingClientRect(),scrollBounds=scroll.getBoundingClientRect();
   width=Math.max(1,bounds.width||scroll.clientWidth||1000);
   top=scrollBounds.top-bounds.top;viewport=scroll.clientHeight||800;
  };
  const schedule=()=>{if(!frame)frame=requestAnimationFrame(()=>{frame=0;readPosition();});};
  const flushMeasurements=()=>{
   measureFrame=0;
   const anchor=geometry.anchor(top),previousTop=top;
   if(geometry.measure(pending)){revision++;restore(anchor,previousTop);readPosition();}
   pending=new Map();
  };
  scheduleMeasurements=()=>{
   for(const [key,node] of rowNodes){const height=node.getBoundingClientRect().height;if(height>0)pending.set(key,height);}
   if(!measureFrame)measureFrame=requestAnimationFrame(flushMeasurements);
  };
  rowObserver=new ResizeObserver(entries=>{
   for(const entry of entries){const node=entry.target as HTMLDivElement;const key=node.dataset.searchEntry;if(key)pending.set(key,entry.borderBoxSize?.[0]?.blockSize??node.getBoundingClientRect().height);}
   if(!measureFrame)measureFrame=requestAnimationFrame(flushMeasurements);
  });
  for(const node of rowNodes.values())rowObserver.observe(node);
  const sizeObserver=new ResizeObserver(schedule);sizeObserver.observe(host);sizeObserver.observe(scroll);
  const menuObserver=new MutationObserver(()=>{
   if(menuKey&&!document.querySelector('[role="menu"]'))menuKey=null;
  });
  menuObserver.observe(document.body,{childList:true,subtree:true});
  scroll.addEventListener('scroll',schedule,{passive:true});window.addEventListener('resize',schedule);
  sync=readPosition;readPosition();scheduleMeasurements();
  return ()=>{
   cancelAnimationFrame(frame);cancelAnimationFrame(measureFrame);
   rowObserver?.disconnect();rowObserver=null;sizeObserver.disconnect();menuObserver.disconnect();
   scroll.removeEventListener('scroll',schedule);window.removeEventListener('resize',schedule);
   sync=()=>{};scheduleMeasurements=()=>{};
  };
 });
 function focused(event:FocusEvent){
  if(!active)return;
  const target=event.target as HTMLElement;focusKey=target.closest<HTMLElement>('[data-search-entry]')?.dataset.searchEntry??null;
 }
 function blurred(){queueMicrotask(()=>{if(!host.contains(document.activeElement))focusKey=null;});}
 function rememberMenu(event:MouseEvent){
  const target=event.target as HTMLElement;
  if(event.type==='contextmenu'||target.closest('.more,.compact-menu')){
   const key=target.closest<HTMLElement>('[data-search-entry]')?.dataset.searchEntry??null;
   queueMicrotask(()=>{if(active&&document.querySelector('[role="menu"]'))menuKey=key;});
  }
 }
 function rememberKeyboardMenu(event:KeyboardEvent){
  if(!active||!(event.key==='ContextMenu'||event.shiftKey&&event.key==='F10'))return;
  const target=event.target as HTMLElement;
  const key=target.closest<HTMLElement>('[data-search-entry]')?.dataset.searchEntry??null;
  // Capture before a row's menu handler prevents the event, then keep the owner
  // mounted when the popup takes focus away from its original control.
  menuKey=key;
  void tick().then(()=>{menuKey=active&&document.querySelector('[role="menu"]')?key:null;});
 }
 async function focusEntry(index:number,backward=false,primaryOnly=false){
  const item=snapshot[index];if(!item)return;
  requestedKey=item.key;
  const scroll=root();
  const start=geometry.offsets[index],end=geometry.offsets[index+1];
  if(scroll){if(start<top)scroll.scrollTop+=start-top;else if(end>top+viewport)scroll.scrollTop+=end-top-viewport;}
  sync();await tick();
  const node=rowNodes.get(item.key);
  const controls=[...node?.querySelectorAll<HTMLElement>('button:not(:disabled),[tabindex="0"]')??[]];
  const primary=controls.find(control=>control.hasAttribute('data-search-primary'));
  (primaryOnly?primary:backward?controls.at(-1):controls[0])?.focus({preventScroll:true});
  requestedKey=null;
 }
 function keydown(event:KeyboardEvent){
  if(!active||event.defaultPrevented||event.isComposing||event.altKey||event.ctrlKey||event.metaKey||document.querySelector('[role="menu"]'))return;
  const target=event.target as HTMLElement;
  const row=target.closest<HTMLElement>('[data-search-entry]');
  const index=row?.dataset.searchEntry?geometry.indices.get(row.dataset.searchEntry):undefined;
  if(index==null)return;
  const nextFocusable=(step:number,primaryOnly=false)=>{let next=index+step;while(next>=0&&next<snapshot.length&&!canFocus(snapshot[next],primaryOnly))next+=step;return next;};
  if((event.key==='ArrowDown'||event.key==='ArrowUp')&&target.matches('[data-search-primary]')){
   const step=event.key==='ArrowDown'?1:-1;
   const next=nextFocusable(step,true);
   if(next>=0&&next<snapshot.length){event.preventDefault();void focusEntry(next,step<0,true);}
  }else if(event.key==='Tab'){
   const controls=[...row!.querySelectorAll<HTMLElement>('button:not(:disabled),[tabindex="0"]')];
   const boundary=event.shiftKey?controls[0]:controls.at(-1),next=nextFocusable(event.shiftKey?-1:1);
   if(target===boundary&&next>=0&&next<snapshot.length){event.preventDefault();void focusEntry(next,event.shiftKey);}
  }
 }
</script>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions (delegates events from the mounted row controls) -->
<div class="search-viewport" bind:this={host} style:height={`${total}px`} data-mounted-count={visible.length} role="group" onfocusin={focused} onfocusout={blurred} onkeydowncapture={rememberKeyboardMenu} onkeydown={keydown} onclick={rememberMenu} oncontextmenu={rememberMenu}>
 {#each visible as entry (entry.item.key)}
  <div class="search-entry" data-search-entry={entry.item.key} style:transform={`translateY(${entry.offset}px)`} use:measureRow={entry.item.key}>
   {@render children(entry.item,entry.index)}
  </div>
 {/each}
</div>

<style>
 .search-viewport{position:relative;min-width:0;overflow-anchor:none;}
 .search-entry{position:absolute;inset:0 0 auto;box-sizing:border-box;min-width:0;display:flow-root;}
</style>
