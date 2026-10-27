<script lang="ts">
 import {t} from '$lib/i18n';
 import type {SearchSectionDto,SearchActionDto,SongDto,BrowseCardDto,AlbumCardDto} from '$lib/types';
 import {songFromSearchCard} from '$lib/search/songs';
 import type {SearchSectionRow} from '$lib/search/provider-rows';
 import ControlButton from '$lib/components/common/ControlButton.svelte';
 import ArtistCredits from '$lib/components/ArtistCredits.svelte';
 import MoreIcon from '$lib/components/common/MoreIcon.svelte';
 import {createMenuHandlers} from '$lib/menu/hooks';
 import {targetFromCard} from '$lib/menu/types';
 import {getContext} from 'svelte';
 import {MEDIA_CONTEXT,type MediaService} from '$lib/player/media';
 import MediaCard from '../common/MediaCard.svelte';
 import SearchSongRow from './SearchSongRow.svelte';
 import SearchRelatedResults from './SearchRelatedResults.svelte';
 interface Props {primary:SearchSectionRow;related:SearchSectionRow[];remaining:SearchSectionRow[];section:SearchSectionDto;currentTrackId:string|null;isPlaying:boolean;onAction:(action:SearchActionDto,section:SearchSectionDto)=>void;onPlaySong:(song:SongDto)=>void;onOpenArtist?:(id:string)=>void;onOpenAlbum:(album:AlbumCardDto)=>void;onOpenPlaylist?:(id:string)=>void;openCard:(card:BrowseCardDto)=>void;openAlbumForSong:(song:SongDto,id:string)=>void;expanded?:boolean;onExpandedChange?:(value:boolean)=>void}
 let {primary,related,remaining,section,currentTrackId,isPlaying,onAction,onPlaySong,onOpenArtist,onOpenAlbum,onOpenPlaylist,openCard,openAlbumForSong,expanded=$bindable(false),onExpandedChange}:Props=$props();
 const card=$derived(primary.card);
 const primarySong=$derived(primary.song??songFromSearchCard(card));
 const kind=$derived(card?.kind??(primary.song?'song':'other'));
 const media=getContext<MediaService|undefined>(MEDIA_CONTEXT);
 const hasPlayableProviderAction=$derived(section.actions.some(action=>Boolean(action.videoId||action.playlistId)));
 const showFallbackPlay=$derived(!hasPlayableProviderAction&&(primarySong!=null||(['album','playlist'].includes(card?.kind??'')&&media!=null)));
 const showOpenPrimary=$derived(Boolean(card&&(card.kind==='album'||(card.kind==='artist'&&onOpenArtist)||(card.kind==='playlist'&&onOpenPlaylist))));
 const hasActions=$derived(section.actions.length>0||showFallbackPlay||showOpenPrimary||Boolean(card||primarySong));
 const menu=createMenuHandlers()(()=>primarySong?{kind:'song',song:primarySong}:card?targetFromCard(card):null,()=>({view:'search_results'}));
 function activate(target:BrowseCardDto){if(target.kind==='artist')onOpenArtist?.(target.id);else if(target.kind==='album')onOpenAlbum({id:target.id,title:target.title,subtitle:target.subtitle,thumbnail:target.thumbnail});else if(target.kind==='playlist')onOpenPlaylist?.(target.id);else openCard(target);}
</script>
{#snippet principalActions()} <div class="actions">{#each section.actions as action,index (`${action.title}:${index}`)}<ControlButton type="button" onclick={()=>onAction(action,section)}>{action.title}</ControlButton>{/each}{#if showFallbackPlay}<ControlButton class="fallback-play" emphasis="prominent" type="button" onclick={()=>primarySong?onPlaySong(primarySong):card&&media?.activate(card)}>{$t('player.play')}</ControlButton>{/if}{#if showOpenPrimary}<ControlButton class="open-primary" type="button" onclick={()=>card&&activate(card)}>{$t('home.open')}</ControlButton>{/if}<ControlButton class="more" size="utility" iconOnly type="button" aria-label={$t('common.moreOptionsFor',[card?.title??primarySong?.title??''])} onclick={menu.onContextMenu} onkeydown={menu.onKeyDown}><MoreIcon/></ControlButton></div>{/snippet}
<section class="principal" class:artist={kind==='artist'} class:has-related={related.length>0} class:has-actions={hasActions} aria-label={$t('search.category.top_result')}>
 <div class="identity">
  {#if primarySong}<div class="hero-song"><SearchSongRow hideMenu inlineDuration song={primarySong} {currentTrackId} {isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={id=>openAlbumForSong(primarySong!,id)}/></div>
  {:else if card}<article class="hero-card" class:artist={kind==='artist'} oncontextmenu={menu.onContextMenu}>
   <button class="cover" type="button" data-search-primary aria-label={$t('home.open')+' '+card.title} onclick={()=>activate(card)} onkeydown={menu.onKeyDown}>{#if card.thumbnail}<img src={card.thumbnail} alt="" loading="lazy"/>{:else}<span aria-hidden="true">♫</span>{/if}</button>
   <div class="copy"><div class="text"><button class="hero-title" type="button" data-search-primary onclick={()=>activate(card)} onkeydown={menu.onKeyDown}>{card.title}</button>
    {#if card.kind==='artist'}{#if card.subtitle}<p class="description">{card.subtitle}</p>{/if}
    {:else}<div class="credits"><ArtistCredits artistRuns={card.artistRuns} artists={card.artists??card.subtitle} artistId={card.artistId} {onOpenArtist} album={card.album} albumId={card.albumId} onOpenAlbum={id=>onOpenAlbum({id,title:card.album??'',subtitle:card.artists??null,thumbnail:card.thumbnail})}/></div>{#if card.duration}<p class="metadata">{card.duration}</p>{/if}{/if}
   </div>{#if kind==='artist'&&hasActions}<div class="artist-actions">{@render principalActions()}</div>{/if}</div>
  </article>
  {/if}
 </div>
 {#if kind!=='artist'&&hasActions}{@render principalActions()}{/if}
 {#if related.length}<SearchRelatedResults rows={related} {section} {currentTrackId} {isPlaying} {onPlaySong} {onOpenArtist} {onOpenAlbum} {onOpenPlaylist} {openCard} {openAlbumForSong} bind:expanded {onExpandedChange}/>{/if}
 {#if remaining.length}<div class="remaining" aria-label={$t('search.provider.other_results')}>
  {#each remaining as row,index (`${row.itemIndex??'song'}:${index}`)}
   {#if row.song}{@const song=row.song}<SearchSongRow {song} {currentTrackId} {isPlaying} onPlay={onPlaySong} {onOpenArtist} onOpenAlbum={id=>openAlbumForSong(song,id)}/>
   {:else if row.card}{@const item=row.card}<MediaCard card={item} layout="compact" onOpen={()=>activate(item)} {onOpenArtist} onOpenAlbum={id=>onOpenAlbum({id,title:item.album??'',subtitle:item.artists??null,thumbnail:item.thumbnail})}/>{/if}
  {/each}
 </div>{/if}
</section>
<style>
 .principal{display:grid;grid-template-columns:minmax(0,1fr);gap:16px;box-sizing:border-box;width:100%;padding:16px;margin:0;border:1px solid rgb(255 255 255 / 8%);border-radius:14px;background:rgb(255 255 255 / 3.5%)}
 .identity{display:flex;min-width:0;flex-direction:column;justify-content:center;gap:12px}
 .hero-card{display:flex;align-items:center;gap:16px;box-sizing:border-box;min-height:96px;min-width:0}
 .hero-card .cover{display:grid;place-items:center;width:96px;height:96px;flex:none;overflow:hidden;padding:0;border:0;border-radius:10px;background:#ffffff10;color:#ddd;cursor:pointer}
 .hero-card .cover img{width:100%;height:100%;object-fit:cover}.hero-card .copy{min-width:0;flex:1}.hero-card.artist .copy{display:flex;flex-direction:column;gap:12px}.artist-actions{max-width:320px;min-width:0}
 .hero-title{display:block;max-width:100%;padding:0;border:0;background:none;color:#f8f8fa;text-align:left;font:inherit;font-size:24px;font-weight:500;line-height:29px;overflow-wrap:anywhere;cursor:pointer}
 .hero-card .credits,.hero-card .description,.hero-card .metadata{margin:8px 0 0;color:#d4d4da;font-size:13px;line-height:18px;overflow-wrap:anywhere}.hero-card .description,.hero-card .metadata{color:#aaa}
 .hero-card.artist .cover{border-radius:50%}.hero-card.artist .hero-title{font-weight:600}
 .hero-song :global(.song-row){min-height:80px;gap:16px;padding:0}.hero-song :global(.play){width:80px;height:80px;border-radius:10px}.hero-song :global(.title){font-size:24px;font-weight:500;line-height:29px;white-space:normal}.hero-song :global(.credits){font-size:13px;white-space:normal}
 .actions{display:flex;min-width:0;align-items:center;align-content:center;flex-wrap:wrap;gap:8px}.actions :global(.sideb-control){max-width:100%}
 .remaining{display:flex;min-width:0;flex-direction:column;gap:0;padding-top:12px;border-top:1px solid rgb(255 255 255 / 8%)}
 @container (min-width:480px){.principal:not(.artist).has-actions{grid-template-columns:minmax(0,1fr) auto;align-items:center;column-gap:16px}.principal:not(.artist) .identity{grid-column:1}.principal:not(.artist).has-actions .actions{grid-column:2;grid-row:1;max-width:320px;justify-content:flex-end}.principal :global(.related),.principal .remaining{grid-column:1/-1}}
 @container (min-width:960px){.artist.has-related{grid-template-columns:minmax(0,.44fr) minmax(0,.56fr);align-items:center;column-gap:24px;row-gap:12px}.artist.has-related .identity{grid-column:1;grid-row:1}.artist.has-related :global(.related){grid-column:2;grid-row:1}.artist.has-related .remaining{grid-column:1/-1}}
 @container (max-width:679px){.hero-card.artist{display:grid;grid-template-columns:96px minmax(0,1fr);gap:12px 16px}.hero-card.artist .cover{grid-column:1;grid-row:1}.hero-card.artist .copy{display:contents}.hero-card.artist .text{grid-column:2;grid-row:1}.artist-actions{grid-column:1/-1;max-width:100%}.actions{justify-content:flex-start}.hero-song :global(.duration){display:none}}
</style>
