<script lang="ts">
 import UpdateModal from '$lib/components/update/UpdateModal.svelte';
 import SpotlightSearch from '$lib/components/search/SpotlightSearch.svelte';
 import type {UpdaterController,UpdaterSnapshot} from '$lib/updater/controller';
 let open=$state(false);
 let snapshot:UpdaterSnapshot={state:{type:'idle'},currentVersion:'1.2.6',isModalOpen:false};
 const listeners=new Set<(value:UpdaterSnapshot)=>void>();
 function publish(state:UpdaterSnapshot['state'],isModalOpen=true){snapshot={...snapshot,state,isModalOpen};for(const callback of listeners)callback(snapshot);}
 const controller={getSnapshot:()=>snapshot,subscribe:(callback:(value:UpdaterSnapshot)=>void)=>{listeners.add(callback);return()=>listeners.delete(callback);},closeModal:()=>publish(snapshot.state,false),downloadAndInstall:()=>{},skipVersion:()=>{}} as unknown as UpdaterController;
 const available={type:'available',info:{version:'2.0.0',tagName:'v2.0.0',releaseNotes:'Fixture',downloadUrl:'https://example.test/update.exe'}} as const;
</script>
<button data-spotlight onclick={()=>open=true}>Spotlight</button>
<button data-update onclick={()=>publish(available)}>Updater</button>
<button data-installing onclick={()=>publish({type:'installing'})}>Installing</button>
<button data-finish onclick={()=>publish({type:'upToDate',version:'2.0.0'},false)}>Finish</button>
{#if open}<SpotlightSearch preview={{query:'',associatedQuery:'',results:null,entries:[],isLoading:false,error:null}} backendReady onQueryChange={()=>{}} onCommit={()=>{}} onDismiss={()=>open=false} onSelectCard={()=>{}} onPlaySong={()=>{}}/>{/if}
<UpdateModal {controller}/>
