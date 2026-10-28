<script>
  import AlbumDetailView from '$lib/components/detail/AlbumDetailView.svelte';
  import PlaylistDetailView from '$lib/components/detail/PlaylistDetailView.svelte';
  import {setLanguage} from '$lib/i18n';
  import {setContext} from 'svelte';
  import {MENU_CONTEXT} from '$lib/menu/types';

  let {mode='playlist', width=730, locale='es', artwork=null, paginated=false, session='collection-fixture', onAction=()=>{}}=$props();
  setContext(MENU_CONTEXT,{open:(_event,target)=>onAction('menu',target.kind)});
  let configured=$state({});
  export function configure(value){configured={...configured,...value};}
  const options=$derived({...{mode,width,locale,artwork,paginated},...configured});
  $effect(()=>setLanguage(options.locale));
  const items=Array.from({length:24},(_,index)=>({videoId:index<3?'duplicate':'track-'+index,setVideoId:'occurrence-'+index,title:index<3?'Coincidencia repetida':'Canción '+index,artists:'Artista invitado de nombre largo',artistId:'artist',album:'Álbum de prueba con un título largo',albumId:'album',thumbnail:null,duration:'3:45',isVideo:false}));
  const album=$derived({browseId:'fixture-album',playlistId:'fixture-album-playlist',title:'Álbum de prueba con un título largo para comprobar la adaptación al espacio disponible',artist:'Artista principal con un nombre largo',artistId:'artist',thumbnail:options.artwork,subtitle:'Álbum • 2026',description:'Descripción completa de la colección para verificar el acceso a más información.',items,sections:[]});
  const playlist=$derived({id:options.mode==='liked'?'LM':'fixture-'+options.mode,title:'Colección de prueba con un título largo para comprobar la adaptación al espacio disponible',subtitle:'Crédito del proveedor con un nombre largo',thumbnail:options.artwork,description:'Descripción completa de la colección para verificar el acceso a más información.',items,continuation:options.paginated?'fixture-next':null,owned:options.mode==='owned',sort:'default'});
  const common={session,currentTrackId:null,isPlaying:false,loggedIn:true,onRetry:()=>onAction('retry'),onPlay:(...args)=>onAction('play',args),onOpenArtist:id=>onAction('artist',id),onOpenAlbum:id=>onAction('album',id),onToggleLibrary:async()=>onAction('save')};
</script>
<div class="collection-fixture" style:width={`${options.width}px`} data-mode={options.mode}>
  {#if options.mode==='album'}
    <AlbumDetailView {...common} {album} isLoading={false} error={null} onOpenCatalog={()=>{}} />
  {:else}
    <PlaylistDetailView {...common} {playlist} loading={false} loadingMore={false} error={null} likedIds={new Set()} pendingIds={new Set()} onLoadMore={()=>onAction('load')} onComplete={async()=>onAction('complete')} onToggleLike={track=>onAction('like',track.setVideoId)} onToggleSaved={()=>{}} onLogin={()=>{}} onOpenMenu={()=>onAction('menu')} onRemoveTrack={track=>onAction('remove',track.setVideoId)} onMoveTrack={(...args)=>onAction('move',args)} />
  {/if}
</div>
<style>
  .collection-fixture {max-width:100%;min-width:0;color:#f7f7f8;font-family:inherit;}
</style>
