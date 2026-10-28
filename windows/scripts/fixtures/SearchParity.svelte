<script lang="ts">
 import {setContext} from 'svelte';
 import SearchView from '$lib/components/search/SearchView.svelte';
 import {emptyProviderSearchData} from '$lib/search/provider';
 import {MENU_CONTEXT} from '$lib/menu/types';
 import type {SongDto,SearchSectionDto,SearchSuggestionEntryDto} from '$lib/types';
 let {count=5000,kind='song',onCall=()=>{}}:{count?:number;kind?:string;onCall?:(...args:unknown[])=>void}=$props();
 let active=$state(true),menu=$state(false),draft=$state('homecoming');
 let scrollElement=$state<HTMLElement|null>();
 let playing=$state(false);
 setContext(MENU_CONTEXT,{open:(_event:unknown,target:unknown)=>{menu=true;onCall('menu',target);}});
 function song(index:number):SongDto{return {videoId:`same-${index%77}`,title:`Resultado ${index}`,artists:'Artista principal',artistRuns:[{text:'Artista principal',id:'artist'}],artistId:'artist',album:'Álbum de prueba',albumId:'album',duration:'3:45',thumbnail:null,isVideo:false,setVideoId:`occurrence-${index}`};}
 function section(offset:number,length:number):SearchSectionDto{return {id:`list-${offset}`,title:offset?'Más canciones':'Canciones',layout:'list',items:[],songs:Array.from({length},(_,index)=>song(index+offset)),actions:[],moreQuery:null,moreParams:null,moreBrowseId:null};}
 const primary=kind==='song'?song(-1):null;
 const principal:SearchSectionDto={id:'top',title:'Resultado principal',layout:'top',items:[{id:primary?.videoId??`${kind}-main`,title:kind==='song'?'Homecoming':kind==='album'?'Álbum principal':'Artista principal',kind,subtitle:'Créditos del proveedor',artists:'Artista principal',artistId:'artist',thumbnail:null,duration:null}],songs:primary?[primary]:[],primaryItemIndex:0,relatedItemIndices:[],actions:[{title:'Mezclar',playlistId:'provider-playlist',params:'opaque',videoId:null,browseId:null}],moreQuery:null,moreParams:null,moreBrowseId:null};
 let data=$state({...emptyProviderSearchData(),query:'homecoming',lastSearchedQuery:'homecoming',hasSearched:true,page:{chips:['Todo','Canciones','Vídeos','Artistas','Álbumes','Playlists','Biblioteca','Podcasts'].map((title,index)=>({id:`chip-${index}`,title,params:`opaque-${index}`,selected:index===0})),correction:null,sections:[principal,section(0,count)],continuation:'next'}});
 const entries:SearchSuggestionEntryDto[]=[...Array.from({length:6},(_,index)=>({id:`query-${index}`,kind:'history',query:`Homecoming ${index}`,runs:[{text:`Homecoming ${index}`,bold:false}],feedbackToken:`remove-${index}`,card:null,song:null})),...Array.from({length:2},(_,index)=>({id:`music-${index}`,kind:'media',query:null,runs:[],feedbackToken:null,card:null,song:song(index)}))];
</script>
<div class="test-controls">
 <button data-append onclick={()=>data={...data,page:{...data.page,sections:[...data.page.sections,section(count,100)]}}}>Append</button>
 <button data-active onclick={()=>active=!active}>Active</button>
 <button data-playback onclick={()=>playing=!playing}>Playback</button>
 <button data-document onclick={()=>data={...data,lastSearchedQuery:'other',query:'other',page:{...data.page,sections:[section(10000,100)]}}}>New query</button>
 <button data-outside onclick={()=>onCall('outside')}>Outside</button>
</div>
<div class="search-fixture" style:height="720px">
 <SearchView {data} {active} bind:contentScrollElement={scrollElement} backendReady currentTrackId="same-0" isPlaying={playing} draftQuery={draft} preview={{query:draft,associatedQuery:draft.trim(),entries,results:null,isLoading:false,error:null}} onAction={(action,source)=>onCall('action',action,source)} onSelectParams={params=>onCall('params',params)} onLoadMore={()=>onCall('loadMore')} onMore={source=>onCall('more',source)} onSubmit={(query,mode)=>onCall('submit',query,mode)} onRetry={()=>{}} onModeChange={()=>{}} onPlaySong={track=>onCall('play',track)} onOpenAlbum={album=>onCall('album',album)} onOpenArtist={id=>onCall('artist',id)} onOpenPlaylist={id=>onCall('playlist',id)} onDraftChange={query=>draft=query} onPreviewFocus={()=>onCall('focus')} onPreviewDismiss={()=>onCall('dismiss')} onRemoveSuggestion={token=>onCall('remove',token)}/>
</div>
{#if menu}<div role="menu"><button role="menuitem" onclick={()=>menu=false}>Close menu</button></div>{/if}
<style>.search-fixture{width:100%;min-width:0;font-family:Segoe UI,sans-serif;color:white;background:#1b1b1e}.test-controls{display:flex;gap:8px;padding:8px}</style>
