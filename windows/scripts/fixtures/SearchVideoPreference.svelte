<script lang="ts">
 import {setContext} from 'svelte';
 import SearchView from '$lib/components/search/SearchView.svelte';
 import SearchVideoSettings from '$lib/components/settings/SearchVideoSettings.svelte';
 import {emptyProviderSearchData} from '$lib/search/provider';
 import {MENU_CONTEXT} from '$lib/menu/types';
 import type {SongDto,SearchSectionDto,SearchSuggestionEntryDto} from '$lib/types';
 let {onCall=()=>{}}:{onCall?:(...args:unknown[])=>void}=$props();
 setContext(MENU_CONTEXT,{open:(_event:unknown,target:unknown)=>onCall('menu',target)});
 const song=(title:string,video:boolean,occurrence:string):SongDto=>({videoId:'same',title,artists:'Artist',artistRuns:[{text:'Artist',id:'artist'}],artistId:'artist',album:null,albumId:null,duration:'3:45',thumbnail:null,isVideo:video,setVideoId:occurrence});
 const card=(kind:string,title:string)=>({kind,id:kind==='artist'?'artist':'same',title,subtitle:null,thumbnail:null,duration:null});
 const top:SearchSectionDto={id:'top',title:'Top',layout:'top',items:[card('artist','Principal artist'),card('video','Hidden video row'),card('song','Visible song one'),card('song','Visible song two')],
  songs:[song('Hidden video row',true,'video'),song('Visible song one',false,'one'),song('Visible song two',false,'two')],primaryItemIndex:0,relatedItemIndices:[1,2,3],moreQuery:null,moreParams:null,moreBrowseId:null,actions:[{title:'Provider action',playlistId:'p',params:null,videoId:null,browseId:null}]};
 const videos:SearchSectionDto={id:'videos',title:'Only videos section',layout:'list',items:[card('video','Video only card')],songs:[song('Video only card',true,'solo')],moreQuery:null,moreParams:null,moreBrowseId:null,actions:[]};
 let page=$state({chips:[],correction:null,sections:[top,videos],continuation:'next'});
 let data=$state({...emptyProviderSearchData(),query:'q',lastSearchedQuery:'q',hasSearched:true,page});
 const entries:SearchSuggestionEntryDto[]=[
  {id:'t',kind:'suggestion',query:'video games',runs:[{text:'video games',bold:false}],feedbackToken:null,card:null,song:null},
  {id:'h',kind:'history',query:'old video',runs:[{text:'old video',bold:false}],feedbackToken:'tok',card:null,song:null},
  {id:'m1',kind:'media',query:null,runs:[],feedbackToken:null,card:null,song:song('Suggested video',true,'s1')},
  {id:'m2',kind:'media',query:null,runs:[],feedbackToken:null,card:null,song:song('Suggested song',false,'s2')}];
</script>
<SearchVideoSettings />
<button data-append onclick={()=>data={...data,page:{...data.page,sections:[...data.page.sections,{...videos,id:'1:more',title:'More videos',items:[card('video','Appended video')],songs:[song('Appended video',true,'appended')]},{...top,id:'2:songs',title:'More songs',layout:'list',primaryItemIndex:null,relatedItemIndices:[],actions:[],items:[card('song','Appended song')],songs:[song('Appended song',false,'appended-song')]}],continuation:'after'}}}>Append</button>
<div style="height:720px">
 <SearchView {data} active backendReady currentTrackId={null} isPlaying={false} draftQuery="vid" preview={{query:'vid',associatedQuery:'vid',entries,results:null,isLoading:false,error:null}}
  onAction={(action:unknown)=>onCall('action',action)} onSelectParams={()=>{}} onLoadMore={()=>onCall('loadMore')} onMore={()=>{}} onSubmit={()=>{}} onRetry={()=>{}} onModeChange={()=>{}} onPlaySong={(item:SongDto)=>onCall('play',item)} onOpenAlbum={()=>{}} onDraftChange={()=>{}} onPreviewFocus={()=>{}} onPreviewDismiss={()=>{}} />
</div>
