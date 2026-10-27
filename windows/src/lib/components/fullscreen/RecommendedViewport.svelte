<script lang="ts" generics="T extends {key:string}">
 import {onMount,tick,untrack,type Snippet} from 'svelte';
 import {recommendedOffsets,recommendedRange} from '$lib/player/recommended-viewport';
 interface Props {items:T[];size:(item:T)=>number;axis:'x'|'y';gap?:number;contextKey:string;initialOffset?:number;onOffset?:(offset:number)=>void;children:Snippet<[T,number]>;label:string}
 let {items,size,axis,gap=0,contextKey,initialOffset=0,onOffset,children,label}:Props=$props();
 const owner=$props.id();let root=$state<HTMLDivElement>();let mounted=$state(false),position=$state(0),extent=$state(600),focused=$state<string|null>(null),menu=$state<string|null>(null);
 const inset=$derived(axis==='x'?2:0);
 const offsets=$derived(recommendedOffsets(items,size,gap,inset));
 const total=$derived(Math.max(0,(offsets.at(-1)??0)-(items.length?gap:0)+inset));
 const range=$derived(recommendedRange(offsets,position,extent));
 const itemIndices=$derived(new Map(items.map((item,index)=>[item.key,index])));
 const visible=$derived.by(()=>{const indices=new Set<number>();for(let index=range.start;index<range.end;index++)indices.add(index);for(const key of [focused,menu]){const index=key===null?undefined:itemIndices.get(key);if(index!==undefined)indices.add(index);}return [...indices].sort((a,b)=>a-b);});
 let sync=()=>{},currentContext='',initialized=false;
 function entry(target:EventTarget|null):string|null{let element=target instanceof Element?target:null;while(element&&element!==root){if(element.getAttribute('data-rec-owner')===owner)return element.getAttribute('data-rec-entry');element=element.parentElement;}return null;}
 function rememberMenu(event:MouseEvent|KeyboardEvent){
  const target=event.target as Element;
  const keyboard=event instanceof KeyboardEvent&&(event.key==='ContextMenu'||event.shiftKey&&event.key==='F10');
  if(event.type==='contextmenu'||keyboard||target.closest('.menu,.more')){
   const key=entry(target),context=contextKey;
   queueMicrotask(()=>{if(root?.isConnected&&context===contextKey&&document.querySelector('[role="menu"]'))menu=key;});
  }
 }
 $effect(()=>{const context=contextKey,element=root;items; if(!element||!mounted)return;untrack(()=>{if(!initialized||context!==currentContext){const offset=initialized?0:initialOffset;initialized=true;currentContext=context;focused=null;menu=null;if(axis==='x')element.scrollLeft=offset;else element.scrollTop=offset;position=offset;void tick().then(()=>sync());}else void tick().then(()=>sync());});});
 onMount(()=>{mounted=true;});
 $effect(()=>{
  const element=root;if(!element||!mounted)return;
  let frame=0;
  const read=()=>{position=axis==='x'?element.scrollLeft:element.scrollTop;extent=(axis==='x'?element.clientWidth:element.clientHeight)||600;onOffset?.(position);};
  const schedule=()=>{if(!frame)frame=requestAnimationFrame(()=>{frame=0;read();});};sync=read;
  const resize=new ResizeObserver(schedule);resize.observe(element);
  const menus=new MutationObserver(()=>{if(menu&&!document.querySelector('[role="menu"]'))menu=null;});menus.observe(document.body,{childList:true,subtree:true});
  element.addEventListener('scroll',schedule,{passive:true});untrack(read);
  return()=>{cancelAnimationFrame(frame);resize.disconnect();menus.disconnect();element.removeEventListener('scroll',schedule);sync=()=>{};};
 });
 function focusOut(){queueMicrotask(()=>{if(!root?.contains(document.activeElement))focused=null;});}
 async function focusItem(index:number,last=false){
  const item=items[index],element=root;if(!item||!element)return;
  const context=contextKey;focused=item.key;
  const start=offsets[index],end=offsets[index+1]-gap;
  if(start<position){if(axis==='x')element.scrollLeft=start;else element.scrollTop=start;}
  else if(end>position+extent){if(axis==='x')element.scrollLeft=end-extent;else element.scrollTop=end-extent;}
  sync();await tick();
  if(context!==contextKey||!root?.isConnected)return;
  const node=[...element.querySelectorAll<HTMLElement>('[data-rec-owner]')].find(node=>node.dataset.recOwner===owner&&node.dataset.recEntry===item.key);
  const controls=[...node?.querySelectorAll<HTMLElement>('button:not(:disabled),[tabindex="0"]')??[]];
  (last?controls.at(-1):controls[0])?.focus({preventScroll:true});
 }
 function keydown(event:KeyboardEvent){
  if(event.key==='ContextMenu'||event.shiftKey&&event.key==='F10'){rememberMenu(event);return;}
  if(event.defaultPrevented||event.isComposing||event.altKey||event.ctrlKey||event.metaKey||document.querySelector('[role="menu"]'))return;
  const key=entry(event.target),index=key===null?undefined:itemIndices.get(key);if(index===undefined)return;
  const target=event.target as HTMLElement;
  if(axis==='x'&&(event.key==='ArrowRight'||event.key==='ArrowLeft')){
   const next=index+(event.key==='ArrowRight'?1:-1);
   if(next>=0&&next<items.length){event.preventDefault();event.stopPropagation();void focusItem(next,event.key==='ArrowLeft');}
  }else if(event.key==='Tab'){
   let node=target.parentElement;while(node&&node.dataset.recOwner!==owner)node=node.parentElement;
   const controls=[...node?.querySelectorAll<HTMLElement>('button:not(:disabled),[tabindex="0"]')??[]];
   const boundary=event.shiftKey?controls[0]:controls.at(-1),next=index+(event.shiftKey?-1:1);
   if(target===boundary&&next>=0&&next<items.length){event.preventDefault();void focusItem(next,event.shiftKey);}
  }
 }
</script>
<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<div class="recommended-viewport" class:horizontal={axis==='x'} bind:this={root} role="group" aria-label={label} data-rec-axis={axis} data-mounted-count={visible.length} onfocusin={event=>focused=entry(event.target)} onfocusout={focusOut} onclick={rememberMenu} oncontextmenu={rememberMenu} onkeydown={keydown}>
 <div class="virtual-content" style:width={axis==='x'?`${total}px`:'100%'} style:height={axis==='y'?`${total}px`:'100%'}>
  {#each visible as index (items[index].key)}<div class="recommended-entry" data-rec-owner={owner} data-rec-entry={items[index].key} style:width={axis==='x'?`${size(items[index])}px`:'100%'} style:height={axis==='y'?`${size(items[index])}px`:'100%'} style:transform={axis==='x'?`translateX(${offsets[index]}px)`:`translateY(${offsets[index]}px)`}>{@render children(items[index],index)}</div>{/each}
 </div>
</div>
<style>.recommended-viewport{position:relative;width:100%;height:100%;min-width:0;min-height:0;overflow-y:auto;overflow-x:hidden;overscroll-behavior:contain;overflow-anchor:none;scrollbar-width:thin;scrollbar-color:#ffffff40 transparent}.horizontal{overflow-x:auto;overflow-y:hidden;overscroll-behavior-x:contain;overscroll-behavior-y:auto;scrollbar-width:none}.horizontal::-webkit-scrollbar{display:none}.virtual-content{position:relative;min-width:0}.recommended-entry{position:absolute;inset:0 auto auto 0;box-sizing:border-box;min-width:0}</style>
