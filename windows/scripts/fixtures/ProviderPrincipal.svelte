<script lang="ts">
 import {setContext} from 'svelte';
 import SearchPrincipal from '$lib/components/search/SearchPrincipal.svelte';
 import {MENU_CONTEXT} from '$lib/menu/types';
 import {MEDIA_CONTEXT,type MediaService} from '$lib/player/media';
 import type {SearchSectionDto,SongDto,BrowseCardDto} from '$lib/types';
 import type {SearchSectionRow} from '$lib/search/provider-rows';
 let {width=720,kind='artist',actions=true,actionType='playable',withMedia=false,openable=true,missingSong=false,onCall=()=>{}}=$props();
 setContext(MENU_CONTEXT,{open:(_event,target)=>onCall('menu',target)});
 if(withMedia)setContext(MEDIA_CONTEXT,{state:()=>({queue:{source:null,items:[],currentIndex:null},currentTrack:null,isPlaying:false,isShuffle:false}),pending:()=>null,activate:card=>onCall('activate',card),toggle:()=>{},rowActive:()=>false} as unknown as MediaService);
 const song:SongDto={videoId:'fixture',title:'Fixture',artists:'Artista principal',album:null,duration:null,thumbnail:null,isVideo:false,artistId:null,albumId:null};
 const principalCard:BrowseCardDto={kind,id:kind==='album'?'album-main':'artist-main',title:kind==='album'?'Álbum principal':'Artista principal',subtitle:'Descripción del proveedor',thumbnail:null,duration:null,artists:'Artista principal',artistId:'artist-credit'};
 const related=Array.from({length:5},(_,index)=>({kind:'song',id:`related-${index}`,title:`Canción relacionada ${index+1}`,subtitle:'Créditos',thumbnail:null,duration:'3:45'}));
 const section:SearchSectionDto={id:'top',title:'Principal',layout:'top',items:[principalCard,...related],songs:kind==='song'&&!missingSong?[song]:[],primaryItemIndex:0,relatedItemIndices:[1,2,3,4,5],moreQuery:null,moreParams:null,moreBrowseId:null,actions:actions?[{title:actionType==='browse'?'Abrir':'Mezclar',videoId:null,playlistId:actionType==='browse'?null:'radio',browseId:actionType==='browse'?'destination':null,params:'opaque'}]:[]};
 const rows:SearchSectionRow[]=related.map((card,itemIndex)=>({card,song:null,itemIndex:itemIndex+1}));
 const primary:SearchSectionRow={card:principalCard,song:kind==='song'&&!missingSong?song:null,itemIndex:0};
 const remaining:SearchSectionRow[]=[];
</script>
<div class="fixture" style:width={`${width}px`}><SearchPrincipal {primary} related={rows} {remaining} {section} currentTrackId={null} isPlaying={false} onAction={(item,source)=>onCall('action',item,source)} onPlaySong={item=>onCall('play',item)} onOpenArtist={openable?id=>onCall('artist',id):undefined} onOpenAlbum={item=>onCall('album',item)} onOpenPlaylist={openable?id=>onCall('playlist',id):undefined} openCard={item=>onCall('card',item)} openAlbumForSong={(item,id)=>onCall('song-album',item,id)}/></div>
<style>.fixture{max-width:100%;font-family:Segoe UI,sans-serif;color:white}</style>
