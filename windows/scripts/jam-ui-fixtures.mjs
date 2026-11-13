// Shared fixtures of the Jam UI tests and screenshots: states, a recording fake of `JamActions` and a playback snapshot.
import {writable} from 'svelte/store';

export const emptyState=()=>({phase:'idle',runtime:{pluginAvailable:true,running:false,signedIn:true},messageKey:null,members:[],host:null,canControl:true,hostActive:true,current:null,queue:[],paused:false,sync:{status:'locked',offsetMs:12,manualOffsetMs:0},toasts:[],pendingExit:null,log:[]});
export const member=(name,extra={})=>({id:`id-${name}`,name,imageUrl:null,isHost:false,isMe:false,...extra});
export const track=(n,extra={})=>({key:`spotify:track:${n}#0`,uri:`spotify:track:${n}`,title:`Song ${n}`,artists:`Artist ${n}`,album:null,durationMs:200000+n*1000,status:'matched',matched:{videoId:`vid${n}`,title:`Song ${n}`,artists:`Artist ${n}`,thumbnail:null,durationSecs:200+n},corrected:false,...extra});
export const searching=n=>track(n,{status:'searching',matched:null});
export const unavailable=n=>track(n,{status:'unavailable',matched:null});
export const activeState=(extra={})=>({...emptyState(),phase:'active',members:[member('Valentina Rodríguez',{isHost:true}),member('Tomás',{isMe:true}),member('Joaquín'),member('Mei'),member('Ana'),member('Luis')],host:member('Valentina Rodríguez',{isHost:true}),current:track(1),queue:[track(2),searching(3),unavailable(4),track(5)],...extra});

/** Recording fake: every call lands in `calls` as `[name, ...args]`; `joinError` makes `join` reject. */
export function fakeJam(initial=emptyState()){
 const store=writable(initial),calls=[];
 const rec=name=>async(...args)=>{calls.push([name,...args]);};
 const actions={refreshStatus:rec('refreshStatus'),openLogin:rec('openLogin'),signOut:rec('signOut'),join:rec('join'),leave:rec('leave'),correctMatch:rec('correctMatch'),addSong:async(...a)=>{calls.push(['addSong',...a]);return true},moveQueue:rec('moveQueue'),removeQueue:rec('removeQueue'),setManualOffset:(...a)=>{calls.push(['setManualOffset',...a])},resync:(...a)=>{calls.push(['resync',...a])},dismissToast:(...a)=>{calls.push(['dismissToast',...a])},confirmExit:rec('confirmExit'),cancelExit:(...a)=>{calls.push(['cancelExit',...a])}};
 const searches=[];
 const searchSongs=async query=>{searches.push(query);return [{videoId:'alt1',title:'Song 1 (Live)',artists:'Artist 1',album:null,duration:'3:25',thumbnail:null,isVideo:false,artistId:null,albumId:null},{videoId:'alt2',title:'Song 1 (Video)',artists:'Artist 1',album:null,duration:'3:21',thumbnail:null,isVideo:true,artistId:null,albumId:null}]};
 return {store,calls,actions,searchSongs,searches,set:patch=>store.update(state=>({...state,...patch})),last:name=>calls.filter(call=>call[0]===name).at(-1)};
}

const entry=(n,videoId=`vid${n}`)=>({entryId:`e${n}`,videoId,title:`Song ${n}`,artists:`Artist ${n}`,thumbnail:null,duration:200+n});
/** Native playback mirroring the Jam: current (Song 1) + the matched upcoming tracks (2 and 5). */
export const jamPlayback=(extra={})=>({currentTrack:{videoId:'vid1',title:'Song 1',artists:'Artist 1'},isPlaying:true,isLoading:false,isEnded:false,isShuffle:false,isRepeat:false,position:30,duration:201,volume:70,error:null,generation:1,authGeneration:0,queue:{items:[entry(1),entry(2),entry(5)],currentIndex:0,source:{kind:'jam',id:null,title:null},revision:1,totalCount:3},...extra});
