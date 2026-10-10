<script lang="ts">
  import {t} from '$lib/i18n';
  import type { BrowseCardDto, SearchResultsDto, SongDto } from '$lib/types';
  import type { SearchPreviewData } from '$lib/search/preview';
  import { resolveSearchSong, relatedTopSongs } from '$lib/search/songs';
  import SearchSongRow from './SearchSongRow.svelte';
  import MediaCard from '../common/MediaCard.svelte';
  interface Props {preview:SearchPreviewData;variant?:'spotlight'|'dropdown';onSelectCard:(card:BrowseCardDto)=>void;onPlaySong:(song:SongDto)=>void}
  let {preview,variant='spotlight',onSelectCard,onPlaySong}:Props=$props();
  const limits=$derived(variant==='spotlight'?{artists:5,songs:8,albums:5,playlists:5}:{artists:2,songs:3,albums:2,playlists:2});
  type Section={key:'top'|'artists'|'songs'|'albums'|'playlists';label:string};
  const labels=$derived({top:$t('search.category.top_result'),artists:$t('search.filter.artists'),songs:$t('search.filter.songs'),albums:$t('search.filter.albums'),playlists:$t('search.filter.playlists')});
  function sections(results:SearchResultsDto):Section[]{const primary=results.top[0]?.kind;const order:Section['key'][]=['top',...(primary==='song'?['songs','artists','albums','playlists']:primary==='album'?['albums','songs','artists','playlists']:['artists','songs','albums','playlists']) as Section['key'][]];return order.filter(key=>results[key].length).map(key=>({key,label:labels[key]}));}
  function open(kind:string,id:string){onSelectCard({kind,id,title:'',subtitle:null,thumbnail:null,duration:null});}
</script>
{#if preview.query.trim()&&!preview.error&&(!preview.results||preview.associatedQuery!==preview.query.trim())}
  <div class="state" role="status">{$t('search.loading.quick')}</div>
{:else if preview.error}<div class="state" role="status"><strong>{$t('search.error.quick')}</strong><span>{preview.error}</span></div>
{:else if preview.results&&preview.associatedQuery===preview.query.trim()}
  {@const results=preview.results}{@const categories=sections(results)}
  {#each categories as section (section.key)}<section class="category" aria-label={section.label}><h3>{section.label}</h3>
    {#if section.key==='songs'}{#each results.songs.slice(0,limits.songs) as song,index (`${song.videoId}:${song.setVideoId??index}`)}<SearchSongRow {song} onPlay={onPlaySong} onOpenArtist={id=>open('artist',id)} onOpenAlbum={id=>open('album',id)}/>{/each}
    {:else}{@const cards=section.key==='top'?results.top.slice(0,1):results[section.key].slice(0,limits[section.key])}{#each cards as card,index (`${card.kind}:${card.id}:${index}`)}{#if ['song','video'].includes(card.kind)}{@const song=resolveSearchSong(card,results)}{#if song}<SearchSongRow {song} onPlay={onPlaySong} onOpenArtist={id=>open('artist',id)} onOpenAlbum={id=>open('album',id)}/>{/if}{:else}<MediaCard {card} layout="compact" onOpen={()=>onSelectCard(card)} onOpenArtist={id=>open('artist',id)} onOpenAlbum={id=>open('album',id)}/>{/if}{/each}{/if}
    {#if section.key==='top'}{#each relatedTopSongs(results) as song (song.videoId)}<SearchSongRow {song} onPlay={onPlaySong} onOpenArtist={id=>open('artist',id)} onOpenAlbum={id=>open('album',id)}/>{/each}{/if}
  </section>{/each}
  {#if !categories.length}<div class="state">{$t('search.empty.quick')}</div>{/if}
{/if}
<style>.category{display:flex;flex-direction:column;gap:4px;margin-bottom:14px;}.category h3{margin:0 4px 3px;color:#aaa;font-size:11px;font-weight:700;letter-spacing:.5px;text-transform:uppercase;}.state{display:flex;flex-direction:column;gap:8px;padding:18px 10px;color:#bbb;font-size:13px;}</style>
