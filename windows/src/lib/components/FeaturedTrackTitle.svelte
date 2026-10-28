<script lang="ts">
  import {getContext,onDestroy} from 'svelte';

  import {FEATURED_ARTIST_CONTEXT,featuredClauses,type Credit,type FeaturedArtistService,type FeaturedTrack} from '$lib/featured/artists';
  import FeaturedArtistLink from './FeaturedArtistLink.svelte';
  import { t } from '$lib/i18n';
  import { contentRating } from '$lib/contentRating';
  import {titleMotion,type TitleMotionOptions} from '$lib/player/title-motion';
  let {track,onOpenArtist,onPlay,prefetch=false,scrollTitle=false}: {track:FeaturedTrack;onOpenArtist?:(id:string)=>void;onPlay?:(event:MouseEvent)=>void;prefetch?:boolean;scrollTitle?:boolean}=$props();
  let interactionPaused=$state(false);
  function motion(node:HTMLElement,options:TitleMotionOptions){if(options.enabled)return titleMotion(node,options);return {};}
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
<span class="featured-title" class:scroll-title={scrollTitle} use:motion={{enabled:scrollTitle,key:JSON.stringify([track.videoId,track.title,parts]),paused:interactionPaused}} title={`${track.title} · ${$t(contentRating(track)==='explicit'?'home.explicit_content':contentRating(track)==='clean'?'content.clean':'content.unknown')}`} onmouseenter={()=>{void load();hovered=true;}} onmouseleave={()=>{hovered=false;void load();}} onfocusin={()=>void load()}>
  <span class="title-parts">{#each parts as part,index (index)}{#if part.credit}<FeaturedArtistLink {track} name={part.text} id={part.credit.id} titleStart={part.credit.start} provenance={part.credit.provenance} {onOpenArtist} portal={scrollTitle} onInteractionChange={scrollTitle?value=>interactionPaused=value:undefined}/>{:else if onPlay}<button class="title-text song-title" type="button" onclick={onPlay}>{part.text}</button>{:else}<span>{part.text}</span>{/if}{/each}</span>
</span>
<style>.featured-title{display:flex;align-items:center;gap:6px;max-width:100%;min-width:0;overflow:hidden;white-space:nowrap;color:inherit;font:inherit}.title-parts{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.title-text{display:inline;border:0;padding:0;background:none;color:inherit;font:inherit;white-space:pre;text-align:left;cursor:pointer}
.scroll-title{width:100%;overflow:clip}.scroll-title .title-parts{display:block;flex:none;min-width:max-content;overflow:visible;text-overflow:clip;white-space:nowrap}@media(prefers-reduced-motion:reduce){.scroll-title{overflow:hidden}}</style>
