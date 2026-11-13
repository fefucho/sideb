<script lang="ts">
 import {t} from '$lib/i18n';
 import type {BrowseCardDto,SearchSuggestionEntryDto,SongDto} from '$lib/types';
 import type {SearchPreviewData} from '$lib/search/provider-preview';
 import {suggestionAllowed} from '$lib/search/suggestions';
 import {searchPreferences} from '$lib/search/searchPreferences';
 import {categoryTitleKey} from '$lib/search/categories';
 import {isLocalEntry,localKeyOf,quickPresentation} from '$lib/search/quickPresentation';
 import SearchSongRow from './SearchSongRow.svelte';
 import MediaCard from '../common/MediaCard.svelte';
 interface Props {preview:SearchPreviewData;variant?:'spotlight'|'dropdown';onSelectCard:(card:BrowseCardDto)=>void;onPlaySong:(song:SongDto)=>void;onQuery?:(query:string)=>void;onRemoveSuggestion?:(token:string)=>void;
  /** Recents kept by Side B (opened artists/albums/playlists and played songs), already shaped as suggestion entries. */
  local?:SearchSuggestionEntryDto[];canUndoRecents?:boolean;onRemoveLocal?:(key:string)=>void;onClearRecents?:()=>void;onUndoRecents?:()=>void}
 let {preview,onSelectCard,onPlaySong,onQuery,onRemoveSuggestion,local=[],canUndoRecents=false,onRemoveLocal,onClearRecents,onUndoRecents}:Props=$props();
 const text=$derived(preview.query.trim());
 const settled=$derived(preview.associatedQuery===text);
 // The provider's entries only count once they belong to what is typed; local recents are shown at once.
 const remote=$derived(settled?(preview.entries??[]).filter(entry=>suggestionAllowed(entry,$searchPreferences)):[]);
 const presentation=$derived(quickPresentation({draft:preview.query,local:$searchPreferences?local:local.filter(entry=>suggestionAllowed(entry,false)),remote,
  page:preview.pageQuery===text?preview.page??null:null,showVideos:$searchPreferences,
  titles:{recents:$t('search.quick.recents'),queries:$t('search.quick.queries'),top:$t('search.quick.top'),category:category=>$t(categoryTitleKey[category])}}));
 function open(kind:string,id:string){onSelectCard({kind,id,title:'',subtitle:null,thumbnail:null,duration:null});}
 function queryText(entry:SearchSuggestionEntryDto){return entry.query??entry.runs.map(run=>run.text).join('');}
 function remove(entry:SearchSuggestionEntryDto){const key=localKeyOf(entry);if(key!==null)onRemoveLocal?.(key);else if(entry.feedbackToken)onRemoveSuggestion?.(entry.feedbackToken);}
 const removable=(entry:SearchSuggestionEntryDto)=>(isLocalEntry(entry)&&Boolean(onRemoveLocal))||(Boolean(entry.feedbackToken)&&Boolean(onRemoveSuggestion));
</script>
{#if preview.isLoading&&!presentation.entries.length}<div class="state" role="status">{$t('search.loading.quick')}</div>{/if}
{#if preview.error}<div class="state" role="status">{preview.error}</div>{/if}
<div class="quick">
{#each presentation.sections as section (section.id)}
 <section class="group" class:top={section.style==='top'} aria-label={section.title??undefined}>
  {#if section.title}<header><h4>{section.title}</h4>{#if section.style==='recents'}{#if canUndoRecents}<button type="button" class="action" onclick={()=>onUndoRecents?.()}>{$t('common.undo')}</button>{:else if local.length}<button type="button" class="action" title={$t('search.recents.clear')} onclick={()=>onClearRecents?.()}>{$t('search.quick.clear')}</button>{/if}{/if}</header>{/if}
  {#each section.entries as entry,index (`${entry.id}:${index}`)}
   <div class="qrow" class:media={Boolean(entry.song||entry.card)}>
   {#if entry.song}<SearchSongRow spotlight song={entry.song} onPlay={onPlaySong} onOpenArtist={id=>open('artist',id)} onOpenAlbum={id=>open('album',id)}/>
   {:else if entry.card}<MediaCard card={entry.card} layout="compact" onOpen={()=>onSelectCard(entry.card!)} onOpenArtist={id=>open('artist',id)} onOpenAlbum={id=>open('album',id)}/>
   {:else}<button type="button" class="query-suggestion" data-search-primary onclick={()=>onQuery?.(queryText(entry))}><span aria-hidden="true">{entry.kind==='history'?'◷':'⌕'}</span><span>{#if entry.runs.length}{#each entry.runs as run}{#if run.bold}<strong>{run.text}</strong>{:else}{run.text}{/if}{/each}{:else}{entry.query}{/if}</span></button>{/if}
   {#if removable(entry)}<button type="button" class="remove" aria-label={$t(isLocalEntry(entry)?'search.recents.remove':'search.provider.remove_history')} onclick={()=>remove(entry)}>×</button>{/if}
   </div>
  {/each}
 </section>
{/each}
</div>
{#if !preview.isLoading&&!preview.error&&settled&&text&&!presentation.entries.length}<div class="state">{$t('search.empty.quick')}</div>{/if}
<style>
 .quick{display:flex;flex-direction:column;gap:6px}
 .group{display:flex;flex-direction:column}
 .group header{display:flex;align-items:center;justify-content:space-between;padding:6px 10px 3px}
 .group h4{margin:0;color:#aaa;font-size:10px;font-weight:600;letter-spacing:.06em;text-transform:uppercase}
 .action{border:0;background:transparent;color:var(--sideb-accent,#d9696f);font:inherit;font-size:11px;cursor:pointer;padding:2px 4px}
 .action:hover{text-decoration:underline}
 .action:focus-visible,.remove:focus-visible,.query-suggestion:focus-visible{outline:2px solid var(--sideb-highlight);outline-offset:-2px}
 .qrow{position:relative}
 .query-suggestion{display:flex;align-items:center;gap:10px;min-height:32px;width:100%;padding:4px 10px;border:0;border-radius:8px;color:inherit;background:transparent;text-align:left;font:inherit;font-size:13px;cursor:pointer}
 .query-suggestion:hover{background:#ffffff0c}
 .query-suggestion span:first-child{width:22px;text-align:center;color:#aaa;font-size:12px}
 .query-suggestion span:nth-child(2){flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
 /* The remove cross only shows on hover or focus so rows stay clean. */
 .remove{position:absolute;right:6px;top:50%;transform:translateY(-50%);display:grid;place-items:center;width:24px;height:24px;padding:0;border:0;border-radius:6px;background:transparent;color:#bbb;font-size:15px;line-height:1;cursor:pointer;opacity:0}
 .media .remove{right:40px}
 .qrow:hover .remove,.qrow:focus-within .remove{opacity:1}
 .remove:hover{background:#ffffff18;color:#fff}
 /* Quick-search density: 32 px artwork and 40 px rows (the results page keeps 44/58). */
 .quick :global(.song-row){min-height:40px;padding:4px 8px}
 .quick :global(.song-row .play){width:32px;height:32px}
 .quick :global(.song-row .credits){margin-top:1px}
 .quick :global(.media-card.compact){height:44px}
 .quick :global(.media-card.compact .art){width:32px;height:32px}
 .quick :global(.media-card.compact .compact-menu){top:8px}
 /* The best result keeps the full-size row on a soft surface. */
 .top .qrow{border-radius:10px;background:#ffffff0f}
 .top :global(.song-row){min-height:58px;padding:7px 10px}.top :global(.song-row .play){width:44px;height:44px}
 .top :global(.media-card.compact){height:56px}.top :global(.media-card.compact .art){width:44px;height:44px}
 .state{display:flex;flex-direction:column;gap:8px;padding:18px 10px;color:#bbb;font-size:13px;}
</style>
