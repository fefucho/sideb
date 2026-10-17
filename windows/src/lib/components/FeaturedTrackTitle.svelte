<script lang="ts">
  import {getContext,onDestroy} from 'svelte';

  import {FEATURED_ARTIST_CONTEXT,featuredClauses,type Credit,type FeaturedArtistService,type FeaturedTrack} from '$lib/featured/artists';
  import FeaturedArtistLink from './FeaturedArtistLink.svelte';
  let {track,onOpenArtist,onPlay,prefetch=false}: {track:FeaturedTrack;onOpenArtist?:(id:string)=>void;onPlay?:(event:MouseEvent)=>void;prefetch?:boolean}=$props();
  const service=getContext<FeaturedArtistService|undefined>(FEATURED_ARTIST_CONTEXT);
  let credits=$state<Credit[]>([]),snapshot=$state(''),hovered=$state(false);
  const trackKey=()=>JSON.stringify([track.videoId,track.title,track.artists,track.artistRuns,track.artistId,track.album,service?.scopeRevision]);
  const current=$derived(snapshot===trackKey()?credits:featuredClauses(track.title));
  const parts=$derived.by(()=>{const result:{text:string;credit?:Credit}[]=[];let start=0;for(const credit of current){if(credit.start>start)result.push({text:track.title.slice(start,credit.start)});result.push({text:track.title.slice(credit.start,credit.end),credit});start=credit.end;}if(start<track.title.length)result.push({text:track.title.slice(start)});return result;});
  let resolving='';let lookup:AbortController|undefined;
  onDestroy(()=>lookup?.abort());
  async function load(){const key=trackKey();if(resolving===key||snapshot===key||!service)return;resolving=key;lookup?.abort();const operation=new AbortController();lookup=operation;const result=await service.title(track,operation.signal);if(trackKey()===key&&!hovered&&!operation.signal.aborted){credits=result;snapshot=key;}if(resolving===key)resolving='';}
  $effect(()=>{trackKey();lookup?.abort();resolving='';if(prefetch)void load();});
</script>
<!-- svelte-ignore a11y_no_static_element_interactions -->
<span class="featured-title" title={track.title} onmouseenter={()=>{void load();hovered=true;}} onmouseleave={()=>{hovered=false;void load();}} onfocusin={()=>void load()}>
  {#each parts as part,index (index)}{#if part.credit}<FeaturedArtistLink {track} name={part.text} id={part.credit.id} titleStart={part.credit.start} provenance={part.credit.provenance} {onOpenArtist}/>{:else if onPlay}<button class="title-text song-title" type="button" onclick={onPlay}>{part.text}</button>{:else}<span>{part.text}</span>{/if}{/each}
</span>
<style>.featured-title{display:block;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:inherit;font:inherit}.title-text{display:inline;border:0;padding:0;background:none;color:inherit;font:inherit;white-space:pre;text-align:left;cursor:pointer}</style>
