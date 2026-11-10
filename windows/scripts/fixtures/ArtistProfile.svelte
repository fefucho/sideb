<script lang="ts">
 import {setContext} from 'svelte';
 import ArtistDetailView from '$lib/components/detail/ArtistDetailView.svelte';
 import {MENU_CONTEXT} from '$lib/menu/types';
 import type {ArtistDetailDto,BrowseCardDto,SongDto} from '$lib/types';
 let {sections=24,cards=120,onCall=()=>{}}:{sections?:number;cards?:number;onCall?:(...args:unknown[])=>void}=$props();
 setContext(MENU_CONTEXT,{open:(_event:unknown,target:unknown)=>onCall('menu',target)});
 const card=(section:number,index:number):BrowseCardDto=>({kind:index%3===0?'video':'album',id:`c-${index%40}`,title:`Card ${section}-${index}`,subtitle:'Artist',thumbnail:null,duration:null});
 const song=(index:number):SongDto=>({videoId:`s${index}`,title:`Song ${index}`,artists:'Artist',album:null,duration:null,thumbnail:null,isVideo:false,artistId:null,albumId:null});
 let artist=$state<ArtistDetailDto>({channelId:'artist',name:'Artist',thumbnail:null,description:null,subscribers:null,monthlyListeners:null,subscribed:false,radioPlaylistId:null,topSongs:[song(1)],topSongsId:null,
  sections:Array.from({length:sections},(_,section)=>({title:`Shelf ${section}`,items:Array.from({length:cards},(_,index)=>card(section,index)),moreBrowseId:section%2?`MPRE${section}`:null,moreParams:null}))});
</script>
<div class="content-column" data-page-scroll style="height:800px;overflow-y:auto">
 <ArtistDetailView {artist} isLoading={false} error={null} currentTrackId={null} isPlaying={false} loggedIn={false} onRetry={()=>{}} onPlay={()=>{}} onStartRadio={async()=>{}} onToggleSubscription={async()=>{}}
  onOpenAlbum={id=>onCall('album',id)} onOpenArtist={id=>onCall('artist',id)} onOpenCatalog={(...args)=>onCall('catalog',...args)} onPlaySong={item=>onCall('play',item.id)} />
</div>
