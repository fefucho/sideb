<script lang="ts">
 import {setContext} from 'svelte';
 import SearchView from '$lib/components/search/SearchView.svelte';
 import {emptyProviderSearchData} from '$lib/search/provider';
 import {MENU_CONTEXT} from '$lib/menu/types';
 import type {SongDto,SearchSectionDto,SearchPageDto} from '$lib/types';
 let {filtered=false,onCall=()=>{}}:{filtered?:boolean;onCall?:(...args:unknown[])=>void}=$props();
 setContext(MENU_CONTEXT,{open:(_event:unknown,target:unknown)=>onCall('menu',target)});
 const song=(id:string,artists='A'):SongDto=>({videoId:id,title:`Song ${id}`,artists,artistRuns:artists?[{text:artists,id:'u'}]:[],artistId:artists?'u':null,album:null,albumId:null,duration:'3:00',thumbnail:null,isVideo:false,setVideoId:`occ-${id}`});
 const card=(kind:string,id:string,title:string,subtitle:string|null=null)=>({kind,id,title,subtitle,thumbnail:null,duration:null});
 const section=(id:string,rest:Partial<SearchSectionDto>):SearchSectionDto=>({id,title:'',layout:'list',items:[],songs:[],moreQuery:null,moreParams:null,moreBrowseId:null,actions:[],...rest});
 const chips=['Songs','Artists','Albums'].map(title=>({id:title,title,params:`params-${title}`,selected:false}));
 const page:SearchPageDto={chips,correction:null,continuation:'next',sections:[
  section('top',{layout:'top',items:[card('artist','UCk','Kendrick Lamar','Artist'),card('song','r1','Related one')],songs:[song('r1','')],primaryItemIndex:0,relatedItemIndices:[1]}),
  section('listen',{title:'Listen again',items:[card('song','l1','Personal pick')],songs:[song('l1')]}),
  section('mixed',{items:[card('artist','UC2','Travis Scott','Artist'),card('album','MPRE1','GNX','Album'),card('album','MPRE2','DAMN.','Album')]}),
 ]};
 const songsPage:SearchPageDto={chips:[],correction:null,continuation:null,sections:[section('s',{items:Array.from({length:12},(_,i)=>card('song',`s${i}`,`Song s${i}`)),songs:Array.from({length:12},(_,i)=>song(`s${i}`))})]};
 let data=$state({...emptyProviderSearchData(),query:'kendrick',lastSearchedQuery:'kendrick',params:filtered?'chip-params':null,hasSearched:true,page,
  categories:{chipPages:{songs:songsPage},pending:['featuredPlaylists']}});
</script>
<div style="height:900px">
 <SearchView {data} active backendReady currentTrackId={null} isPlaying={false} draftQuery="kendrick" preview={{query:'',associatedQuery:'',entries:[],results:null,isLoading:false,error:null}}
  onAction={()=>{}} onSelectParams={()=>{}} onLoadMore={()=>onCall('loadMore')} onMore={(source:unknown)=>onCall('more',source)} onSubmit={()=>{}} onRetry={()=>{}} onModeChange={()=>{}} onPlaySong={(item:SongDto)=>onCall('play',item)} onOpenAlbum={()=>{}} onDraftChange={()=>{}} onPreviewFocus={()=>{}} onPreviewDismiss={()=>{}} />
</div>
