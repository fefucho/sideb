<script lang="ts">
  import {getContext,onDestroy} from 'svelte';
  import {t} from '$lib/i18n';
  import type {BrowseCardDto} from '$lib/types';
  import {FEATURED_ARTIST_CONTEXT,FeaturedArtistPicker,type FeaturedArtistService,type FeaturedTrack} from '$lib/featured/artists';
  let {track,name,id,onOpenArtist,titleStart,provenance}: {track:FeaturedTrack;name:string;id?:string|null;onOpenArtist?:(id:string)=>void;titleStart?:number;provenance?:'provider'|'userChoice'|'inferred'|'unresolved'}=$props();
  const service=getContext<FeaturedArtistService|undefined>(FEATURED_ARTIST_CONTEXT);
  let busy=$state(false),menu=$state(false),candidates=$state<BrowseCardDto[]>([]),selection=$state(false);
  let request:AbortController|undefined;
  const picker=service?new FeaturedArtistPicker(service,()=>({track,name})):undefined;
  let correctionRevision=0;
  function close(){correctionRevision++;request?.abort();picker?.cancel();busy=false;menu=false;selection=false;candidates=[];}
  onDestroy(close);
  $effect(()=>{JSON.stringify([track,name]);close();});
  async function open(event:MouseEvent){event.stopPropagation();request?.abort();const operation=new AbortController();request=operation;if(!service){if(id)onOpenArtist?.(id);return;}busy=true;let offset=titleStart;
    if(offset!==undefined&&event.detail>0){const doc=document as Document&{caretRangeFromPoint?:(x:number,y:number)=>Range|null};const caret=doc.caretRangeFromPoint?.(event.clientX,event.clientY);if(caret?.startContainer.parentElement?.closest('.featured-link')===event.currentTarget)offset+=caret.startOffset;}
    await service?.open(track,name,onOpenArtist,operation.signal,offset);if(request===operation)busy=false;}
  async function correct(){const revision=++correctionRevision;selection=true;candidates=[];const found=await picker?.load()??[];if(revision===correctionRevision)candidates=found;}

</script>
<button type="button" role="link" class="featured-link" class:title-credit={titleStart!==undefined} aria-label={$t('featured.open',[name])} title={$t(provenance==='inferred'?'featured.suggested':'featured.open',[name])} onclick={open} onkeydown={event=>{if(event.key==='Escape'){close();}if(event.key==='Enter'||event.key===' '){event.stopPropagation();}}} oncontextmenu={event=>{event.preventDefault();event.stopPropagation();picker?.cancel();candidates=[];menu=true;selection=false;}} ondragstart={event=>event.preventDefault()}>{name}</button>
{#if busy}<span class="pending" role="status">{$t('featured.searching')} <button type="button" onclick={event=>{event.stopPropagation();request?.abort();busy=false;}}>{$t('common.cancel')}</button></span>{/if}
{#if menu}
  <div class="match-menu" role="dialog" aria-label={$t('featured.change')}>
    <button type="button" onclick={open}>{$t('featured.open',[name])}</button>
    <button type="button" onclick={event=>{event.stopPropagation();void correct();}}>{$t('featured.change')}</button>
    <button type="button" onclick={event=>{event.stopPropagation();request?.abort();service?.search(name);menu=false;}}>{$t('featured.search')}</button>
    {#if selection}{#each candidates as candidate (candidate.id)}<button type="button" onclick={event=>{event.stopPropagation();if(picker?.choose(candidate.id))onOpenArtist?.(candidate.id);close();}}>{candidate.title} · {candidate.subtitle??candidate.id}</button>{/each}
      {#if !candidates.length}<span>{$t('featured.noMatches')}</span>{/if}
      <button type="button" onclick={event=>{event.stopPropagation();picker?.reset();close();}}>{$t('featured.reset')}</button>
    {/if}
    <button type="button" onclick={event=>{event.stopPropagation();close();}}>{$t('common.cancel')}</button>
  </div>
{/if}
<style>
.featured-link{display:inline;padding:0;border:0;background:none;color:inherit;font:inherit;white-space:pre;cursor:pointer;text-align:left}.featured-link:hover,.featured-link:focus-visible{color:#fff;text-decoration:none}.featured-link.title-credit:hover,.featured-link.title-credit:focus-visible{opacity:.75}.featured-link:focus-visible{outline:2px solid var(--sideb-highlight,#d06c70);outline-offset:1px}.pending,.match-menu{position:fixed;z-index:1000;background:#24242b;color:#fff;padding:10px;border-radius:8px;font:12px system-ui;white-space:normal;box-shadow:0 8px 25px #0008}.match-menu{display:flex;flex-direction:column;max-width:320px;gap:6px}.match-menu button,.pending button{background:none;border:0;color:inherit;padding:6px;text-align:left;cursor:pointer}
</style>
