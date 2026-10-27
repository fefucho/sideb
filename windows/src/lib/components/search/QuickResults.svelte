<script lang="ts">
 import {t} from '$lib/i18n';
 import type {BrowseCardDto,SongDto} from '$lib/types';
 import type {SearchPreviewData} from '$lib/search/preview';
 import {visibleSearchSuggestions} from '$lib/search/suggestions';
 import SearchSongRow from './SearchSongRow.svelte';
 import MediaCard from '../common/MediaCard.svelte';
 interface Props {preview:SearchPreviewData;variant?:'spotlight'|'dropdown';onSelectCard:(card:BrowseCardDto)=>void;onPlaySong:(song:SongDto)=>void;onQuery?:(query:string)=>void;onRemoveSuggestion?:(token:string)=>void}
 let {preview,onSelectCard,onPlaySong,onQuery,onRemoveSuggestion}:Props=$props();
 const entries=$derived(visibleSearchSuggestions(preview.entries??[],preview.query));
 function open(kind:string,id:string){onSelectCard({kind,id,title:'',subtitle:null,thumbnail:null,duration:null});}
</script>
{#if preview.isLoading}<div class="state" role="status">{$t('search.loading.quick')}</div>{/if}
{#if preview.error}<div class="state" role="status">{preview.error}</div>{/if}
{#if preview.associatedQuery===preview.query.trim()}
 {#each entries as entry,index (`${entry.id}:${index}`)}
  {#if entry.kind==='media'}
   {#if entry.song}<SearchSongRow spotlight song={entry.song} onPlay={onPlaySong} onOpenArtist={id=>open('artist',id)} onOpenAlbum={id=>open('album',id)}/>
   {:else if entry.card}<MediaCard card={entry.card} layout="compact" onOpen={()=>onSelectCard(entry.card!)} onOpenArtist={id=>open('artist',id)} onOpenAlbum={id=>open('album',id)}/>{/if}
  {:else}<div class="query-suggestions"><button type="button" class="query-suggestion" data-search-primary onclick={()=>onQuery?.(entry.query??entry.runs.map(run=>run.text).join(''))}><span aria-hidden="true">{entry.kind==='history'?'◷':'⌕'}</span><span>{#each entry.runs as run}{#if run.bold}<strong>{run.text}</strong>{:else}{run.text}{/if}{/each}</span></button>{#if entry.feedbackToken&&onRemoveSuggestion}<button type="button" aria-label={$t('search.provider.remove_history')} onclick={()=>onRemoveSuggestion?.(entry.feedbackToken!)}>×</button>{/if}</div>{/if}
 {/each}
 {#if !preview.isLoading&&!preview.error&&!entries.length}<div class="state">{$t('search.empty.quick')}</div>{/if}
{/if}
<style>.query-suggestions{border-bottom:1px solid #ffffff18;padding-bottom:10px;margin-bottom:10px}.query-suggestions button{display:flex;align-items:center;gap:12px;min-height:44px;width:100%;padding:8px 10px;border:0;border-radius:8px;color:inherit;background:transparent;text-align:left;font:inherit;font-size:14px;cursor:pointer}.query-suggestions button:hover{background:#ffffff0c}.query-suggestions button span:nth-child(2){flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.query-suggestions button:focus-visible{outline:2px solid var(--sideb-highlight);outline-offset:-2px}.state{display:flex;flex-direction:column;gap:8px;padding:18px 10px;color:#bbb;font-size:13px;}

.query-suggestions{display:flex;margin-bottom:2px;padding-bottom:0;border:0}.query-suggestions .query-suggestion{flex:1}.query-suggestions>button:last-child:not(.query-suggestion){width:40px}</style>
