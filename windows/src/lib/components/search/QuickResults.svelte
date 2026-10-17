<script lang="ts">
  import {t} from '$lib/i18n';
  import type { BrowseCardDto, SearchResultsDto, SongDto } from '$lib/types';
  import type { SearchPreviewData } from '$lib/search/preview';
  import { suggestionProjection } from '$lib/search/projection';
  import { resolveSearchSong } from '$lib/search/songs';
  import SearchSongRow from './SearchSongRow.svelte';
  import MediaCard from '../common/MediaCard.svelte';
  interface Props {preview:SearchPreviewData;variant?:'spotlight'|'dropdown';onSelectCard:(card:BrowseCardDto)=>void;onPlaySong:(song:SongDto)=>void;onQuery?:(query:string)=>void}
  let {preview,variant='spotlight',onSelectCard,onPlaySong,onQuery}:Props=$props();
  const limits=$derived(variant==='spotlight'?{artists:5,songs:8,albums:5,playlists:5}:{artists:2,songs:3,albums:2,playlists:2});
  type Section={key:'top'|'artists'|'songs'|'albums'|'playlists';label:string};
  const labels=$derived({top:$t('search.category.top_result'),artists:$t('search.filter.artists'),songs:$t('search.filter.songs'),albums:$t('search.filter.albums'),playlists:$t('search.filter.playlists')});
  function sections(results:SearchResultsDto):Section[]{return (['top','songs','artists','albums','playlists'] as Section['key'][]).filter(key=>results[key].length).map(key=>({key,label:labels[key]}));}
  function open(kind:string,id:string){onSelectCard({kind,id,title:'',subtitle:null,thumbnail:null,duration:null});}
</script>
{#if preview.query.trim()&&!preview.error&&(!preview.results||preview.associatedQuery!==preview.query.trim())}
  <div class="state" role="status">{$t('search.loading.quick')}</div>
{:else if preview.error}<div class="state" role="status"><strong>{$t('search.error.quick')}</strong><span>{preview.error}</span></div>
{:else if preview.results&&preview.associatedQuery===preview.query.trim()}
  {@const results=suggestionProjection(preview.results,variant==='spotlight'?8:6)}{@const categories=sections(results)}
  {#if preview.queries?.length}<section class="query-suggestions" aria-label={$t('search.suggestions.title')}><h3>{$t('search.suggestions.title')}</h3>{#each preview.queries.slice(0,3) as query,index (`${index}:${query}`)}<button type="button" class="query-suggestion" data-search-primary onclick={()=>onQuery?.(query)}><span aria-hidden="true">⌕</span><span>{query}</span><span aria-hidden="true">↵</span></button>{/each}</section>{/if}
  {#each categories as section (section.key)}<section class="category" aria-label={section.label}>{#if section.key!=='top'}<h3>{section.label}</h3>{/if}
    {#if section.key==='songs'}{#each results.songs.slice(0,limits.songs) as song,index (`${song.videoId}:${song.setVideoId??index}`)}<SearchSongRow spotlight {song} onPlay={onPlaySong} onOpenArtist={id=>open('artist',id)} onOpenAlbum={id=>open('album',id)}/>{/each}
    {:else}{@const cards=section.key==='top'?results.top:results[section.key].slice(0,limits[section.key])}{#each cards as card,index (`${card.kind}:${card.id}:${index}`)}{#if ['song','video'].includes(card.kind)}{@const song=resolveSearchSong(card,preview.results)}{#if song}<SearchSongRow spotlight {song} onPlay={onPlaySong} onOpenArtist={id=>open('artist',id)} onOpenAlbum={id=>open('album',id)}/>{/if}{:else}<MediaCard {card} layout="compact" onOpen={()=>onSelectCard(card)} onOpenArtist={id=>open('artist',id)} onOpenAlbum={id=>open('album',id)}/>{/if}{/each}{/if}

  </section>{/each}

  {#if !categories.length&&!preview.queries?.length}<div class="state">{$t('search.empty.quick')}</div>{/if}
{/if}
<style>.query-suggestions{border-bottom:1px solid #ffffff18;padding-bottom:10px;margin-bottom:10px}.query-suggestions h3{margin:0 10px 6px;font-size:12px;color:#aaa;font-weight:500}.query-suggestions button{display:flex;align-items:center;gap:12px;min-height:44px;width:100%;padding:8px 10px;border:0;border-radius:8px;color:inherit;background:transparent;text-align:left;font:inherit;font-size:14px;cursor:pointer}.query-suggestions button:hover{background:#ffffff0c}.query-suggestions button span:nth-child(2){flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.query-suggestions button:focus-visible{outline:2px solid var(--sideb-highlight);outline-offset:-2px}.category :global(.compact){box-sizing:border-box;min-height:58px;padding:7px 10px;height:58px}.category :global(.compact h3){font-size:14px}.category :global(.compact .credits),.category :global(.compact p){font-size:12px}.category{display:flex;flex-direction:column;gap:4px;margin-bottom:14px;}.category h3{margin:0 4px 3px;color:#aaa;font-size:11px;font-weight:700;letter-spacing:.5px;text-transform:uppercase;}.state{display:flex;flex-direction:column;gap:8px;padding:18px 10px;color:#bbb;font-size:13px;}</style>
