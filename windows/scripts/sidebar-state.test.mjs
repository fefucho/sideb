import assert from 'node:assert/strict';
import {test} from 'node:test';
import path from 'node:path';
import {mountedSvelteEnvironment} from './helpers/mount-svelte.mjs';
const {root,moduleFor}=await mountedSvelteEnvironment('sidebar-state');
const mod=async name=>import(await moduleFor(path.join(root,'src/lib',name)));
const prefs=await mod('player/sidebarPreferences.ts');
const layout=await mod('player/sidebarLayout.ts');
const upcoming=await mod('player/sidebarUpcoming.ts');
const lyrics=await mod('player/sidebarLyrics.ts');
const policy=await mod('artwork/policy.ts');

test('sidebar bottom content defaults to the queue like macOS, validates storage and survives blocked storage',()=>{
 assert.equal(prefs.sidebarLyricsPreviewKey,'sideb.sidebar.lyricsPreview.v1');
 for(const raw of [undefined,null,'',{},true,'Lyrics','broken'])assert.equal(prefs.resolveSidebarBottomContent(raw),'queue');
 assert.equal(prefs.resolveSidebarBottomContent('lyrics'),'lyrics');
 const values=new Map(),storage={getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value)};
 let store=prefs.createSidebarPreferences(storage);const events=[];const stop=store.subscribe(value=>events.push(value));
 assert.equal(store.currentBottomContent(),'queue');assert.equal(values.size,0,'reading never mutates storage');
 store.setLyricsPreview(true);assert.equal(events.at(-1),'lyrics');assert.equal(values.get(prefs.sidebarLyricsPreviewKey),'lyrics');
 store=prefs.createSidebarPreferences(storage);assert.equal(store.currentBottomContent(),'lyrics','persists across reloads');
 store.setBottomContent('garbage');assert.equal(store.currentBottomContent(),'queue');assert.equal(values.get(prefs.sidebarLyricsPreviewKey),'queue');stop();
 const blocked=prefs.createSidebarPreferences({getItem(){throw Error('blocked');},setItem(){throw Error('blocked');}});
 assert.equal(blocked.currentBottomContent(),'queue');blocked.setLyricsPreview(true);assert.equal(blocked.currentBottomContent(),'lyrics');
});

test('cover geometry keeps the square card and the immersive portrait video as macOS',()=>{
 const card=layout.sidebarArtworkGeometry(380,628,false);
 assert.equal(card.cardSide,340);assert.equal(card.cardTop,58+Math.min(12,628-58-(340+16+68)));
 assert.equal(card.metadataTop,card.cardTop+card.cardSide+16);assert.equal(card.metadataWidth,card.cardSide);
 assert.deepEqual([card.videoWidth,card.videoHeight,card.videoTop],[340,340,card.cardTop]);
 const portrait=layout.sidebarArtworkGeometry(380,628,true);
 assert.deepEqual([portrait.videoWidth,portrait.videoHeight,portrait.videoTop,portrait.metadataWidth],[380,628,0,340]);
 assert.equal(portrait.metadataTop,628-16-68,'metadata anchors to the bottom over the faded video');
 const short=layout.sidebarArtworkGeometry(380,420,false);assert.equal(short.cardSide,420-58-12-16-68,'low panels shrink the card before anything else');
 assert.equal(layout.sidebarArtworkGeometry(NaN,-5,false).cardSide,0);
});

test('tall/square selection: a cover is portrait only with a ready taller-than-wide frame and motion allowed',()=>{
 assert.deepEqual(layout.sidebarArtworkPresentation(null,false),{showVideo:false,tall:false});
 assert.deepEqual(layout.sidebarArtworkPresentation({width:1080,height:1080},false),{showVideo:true,tall:false},'square fallback keeps the card');
 assert.deepEqual(layout.sidebarArtworkPresentation({width:1080,height:1440},false),{showVideo:true,tall:true});
 assert.deepEqual(layout.sidebarArtworkPresentation({width:1080,height:1440},true),{showVideo:false,tall:false},'reduced motion never leaves the poster');
 // Accepted/rejected media: orientation requested decides.
 const tall={width:1080,height:1440},extension={width:720,height:1280};
 assert.ok(policy.isTallArtworkVideo(tall));assert.ok(policy.isTallArtworkVideo({width:810,height:1080}));
 assert.ok(!policy.isTallArtworkVideo({width:1080,height:1920}),'16:9-ish portrait is not the Apple 3:4');
 assert.ok(!policy.isTallArtworkVideo({width:1080,height:1500}),'height above 1440 rejected');
 assert.ok(policy.isTallArtworkVideo(extension,true)&&!policy.isTallArtworkVideo(extension,false));
 assert.ok(policy.acceptsArtworkVideo(tall,{...tall,assetId:'a'},true));
 assert.ok(!policy.acceptsArtworkVideo(tall,{...tall,assetId:'a'},false),'tall is opt-in');
 assert.ok(policy.acceptsArtworkVideo({width:1080,height:1080},{width:1080,height:1080},true),'square fallback accepted when tall was requested');
 assert.ok(!policy.acceptsArtworkVideo(tall,{width:1080,height:1080},true),'decoded size must agree with the asset');
 assert.ok(!policy.acceptsArtworkVideo({width:1200,height:1200},{width:1200,height:1200},true));
 assert.ok(policy.acceptsArtworkVideo(extension,{...extension,assetId:'visual-extension:x'},true));
});

test('video suspension policy: a brief scroll suspends but only tab, motion or hero loss change eligibility',()=>{
 const at=(offset,upper=600)=>layout.heroScroll(offset,upper);
 assert.deepEqual(at(0),{offset:0,progress:0,quantized:0,heroVisible:true,motionActive:true});
 assert.equal(at(30).motionActive,true,'5 % of the hero keeps motion');assert.equal(at(31).motionActive,false);
 assert.equal(at(599).heroVisible,true);assert.equal(at(600).heroVisible,false);
 assert.equal(at(1e9).progress,1);assert.equal(at(-20).offset,0);assert.equal(at(NaN).offset,0);
 assert.equal(at(300).quantized,0.5);
 const suspended=(panelActive,scroll,reducedMotion=false)=>layout.sidebarMotionSuspended({panelActive,scroll,reducedMotion});
 assert.equal(suspended(true,at(0)),false);
 assert.equal(suspended(true,at(120)),true,'scrolling suspends playback');
 assert.equal(suspended(true,at(0)),false,'returning resumes the same player (no state kept in the policy)');
 assert.equal(suspended(false,at(0)),true,'another tab suspends');
 assert.equal(suspended(true,at(0),true),true,'reduced motion suspends');
});

test('footer and upcoming visibility follow the macOS thresholds',()=>{
 assert.equal(layout.showsUpcoming(839,'artwork'),false);assert.equal(layout.showsUpcoming(840,'artwork'),true);
 assert.equal(layout.showsUpcoming(900,'artwork',true),false,'portrait never shows it');assert.equal(layout.showsUpcoming(900,'lyrics'),false);
 assert.equal(layout.sidebarFooterHeight(628,'lyrics'),Math.min(240,Math.max(200,628*.24))+68+16);
 assert.equal(layout.sidebarFooterHeight(900,'artwork',true),Math.min(240,Math.max(200,900*.24)));
 assert.ok(layout.sidebarFooterHeight(900,'artwork',false)>=Math.min(240,Math.max(200,900*.24))+134);
 assert.equal(layout.progressToTransportSpacing(628),10+Math.max(0,Math.min(240,Math.max(200,628*.24))-194)/4);
});

const entry=(entryId,queueIndex,extra={})=>({entryId,queueIndex,videoId:'v'+entryId,title:'T'+entryId,artists:'A',thumbnail:null,duration:60,...extra});
test('up next shows at most the two next committed occurrences, never recommendations, and keeps duplicate identities',()=>{
 const queue={items:[entry('a',0),entry('b',1),entry('c',2),entry('d',3)],recommendations:[entry('r',0)],currentIndex:1,totalCount:4,source:null,revision:3};
 assert.deepEqual(upcoming.sidebarUpcomingPreview(queue).map(item=>[item.entry.entryId,item.queueIndex]),[['c',2],['d',3]]);
 assert.deepEqual(upcoming.sidebarUpcomingPreview({...queue,currentIndex:2}).map(item=>item.entry.entryId),['d']);
 assert.deepEqual(upcoming.sidebarUpcomingPreview({...queue,currentIndex:3}),[]);
 assert.deepEqual(upcoming.sidebarUpcomingPreview({...queue,currentIndex:null}),[]);
 assert.deepEqual(upcoming.sidebarUpcomingPreview(null),[]);
 const dup={items:[entry('x1',0,{videoId:'same'}),entry('x2',1,{videoId:'same'}),entry('x3',2,{videoId:'same'})],currentIndex:0,totalCount:3,source:null,revision:1};
 assert.deepEqual(upcoming.sidebarUpcomingPreview(dup).map(item=>item.entry.entryId),['x2','x3'],'same video, distinct occurrences');
 // Sparse window: items are a slice of a longer native queue.
 const sparse={items:[entry('p',40),entry('q',41),entry('s',43)],currentIndex:0,totalCount:100,source:null,revision:2};
 assert.deepEqual(upcoming.sidebarUpcomingPreview(sparse).map(item=>[item.entry.entryId,item.queueIndex]),[['q',41]],'a missing occurrence ends the preview, never invented');
 assert.equal(upcoming.formatSidebarDuration(75),'1:15');assert.equal(upcoming.formatSidebarDuration(3725),'1:02:05');assert.equal(upcoming.formatSidebarDuration(null),'');
});

test('sample lyrics: classic lyrics belong to the exact occurrence, source choice is read, centering is immediate until settled',()=>{
 const playback={generation:2,currentTrack:{videoId:'v'},queue:{items:[{entryId:'e1'}],currentIndex:0}};
 const state=scope=>({status:'ready',trackKey:JSON.stringify(['v',2,JSON.stringify(scope)]),lyrics:{provider:'x',isSynced:true,lines:[]},error:null});
 assert.ok(lyrics.currentClassicLyrics(state([1,'e1']),playback,1));
 assert.equal(lyrics.currentClassicLyrics(state([2,'e1']),playback,1),null,'another account');
 assert.equal(lyrics.currentClassicLyrics(state([1,'e2']),playback,1),null,'another queue entry');
 assert.equal(lyrics.currentClassicLyrics({...state([1,'e1']),trackKey:'{'},playback,1),null);
 assert.equal(lyrics.lyricsOccurrence(1,playback),JSON.stringify([1,'e1',2,'v']));
 assert.deepEqual(lyrics.readLyricSources({getItem:()=>JSON.stringify({v:'lrclib'})}),{v:'lrclib'});
 assert.deepEqual(lyrics.readLyricSources({getItem:()=>'[]'}),{});assert.deepEqual(lyrics.readLyricSources({getItem(){throw Error('x');}}),{});
 const plan=lyrics.lyricsCenterPlan;
 let state1=plan(null,{occurrence:'o',layout:'l'},false);assert.deepEqual(state1,{animate:false,centered:true},'first positioning of a mount does not travel');
 const settled={occurrence:'o',layout:'l',centered:true};
 assert.equal(plan(settled,{occurrence:'o',layout:'l'},false).animate,true,'later line changes animate');
 assert.equal(plan(settled,{occurrence:'o',layout:'l2'},false).animate,false,'height/font/doc changes re-center immediately');
 assert.equal(plan(settled,{occurrence:'o2',layout:'l'},false).animate,false,'a new occurrence starts at the active line');
 assert.equal(plan(settled,{occurrence:'o',layout:'l'},true).animate,false,'reduced motion never animates');
});

test('media limits are separated by origin: the provider never loosens Apple and vice versa',()=>{
 const ext={assetId:'visual-extension:r'},apple={assetId:'apple-1'};
 const accepts=(w,h,origin)=>policy.acceptsArtworkVideo({width:w,height:h},{width:w,height:h,...origin},true);
 assert.ok(accepts(1080,1920,ext)&&accepts(720,1280,ext)&&accepts(405,720,ext),'provider: ~9:16, 720–1920 px tall');
 assert.ok(!accepts(1080,1921,ext),'provider 1921 px rejected');assert.ok(!accepts(400,719,ext),'provider below 720 px rejected');
 assert.ok(!accepts(1080,1440,ext),'an Apple 3:4 video is not a valid provider video');
 assert.ok(accepts(1080,1440,apple),'Apple 3:4 accepted');
 assert.ok(!accepts(1080,1920,apple)&&!accepts(720,1280,apple),'a 9:16 video never passes as Apple\'s');
 assert.ok(!accepts(810,1441,apple)&&!accepts(1080,1441,apple),'Apple stays <=1440 px');
 assert.ok(accepts(1080,1080,ext)&&accepts(1080,1080,apple),'square is valid for either origin');
 assert.ok(!policy.acceptsArtworkVideo({width:720,height:1280},{width:720,height:1280,assetId:'visual-extension:r'},false),'tall requires the vertical player');
 assert.ok(policy.acceptsArtworkFrameRate(60,'apple')&&!policy.acceptsArtworkFrameRate(60.1,'apple')&&policy.acceptsArtworkFrameRate(60.1,'visual-extension:r')&&!policy.acceptsArtworkFrameRate(61,'visual-extension:r'));
 assert.ok(policy.isVisualProviderAsset('visual-extension:x')&&!policy.isVisualProviderAsset('x'));
});
test('identity: the provider salt makes the sidebar key per track and reacts to configuration changes',()=>{
 const t={videoId:'v1',albumId:'AL',album:'A',artists:'Z'},next={...t,videoId:'v2'};
 assert.equal(policy.animatedArtworkAlbumKey(t),policy.animatedArtworkAlbumKey(next));
 assert.notEqual(policy.animatedArtworkAlbumKey(t,'s1'),policy.animatedArtworkAlbumKey(next,'s1'));
 assert.notEqual(policy.animatedArtworkAlbumKey(t,'s1'),policy.animatedArtworkAlbumKey(t,'s2'));
 assert.equal(policy.animatedArtworkAlbumKey(t,null),policy.animatedArtworkAlbumKey(t));
});
