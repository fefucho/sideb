import assert from 'node:assert/strict';
import {test} from 'node:test';
import path from 'node:path';
import {mountedSvelteEnvironment} from './helpers/mount-svelte.mjs';

const {root,moduleFor}=await mountedSvelteEnvironment('search-video-preferences');
const lib=file=>path.join(root,'src/lib',file);
const {createSearchPreferences,showVideosKey,resolveShowVideos}=await import(await moduleFor(lib('search/searchPreferences.ts')));
const {filterSearchSection,filterSearchPage}=await import(await moduleFor(lib('search/videoPreferences.ts')));
const {visibleSearchSuggestions}=await import(await moduleFor(lib('search/suggestions.ts')));
const {projectSearchDocument}=await import(await moduleFor(lib('search/document.ts')));
const {projectSearchSection,searchSectionRows}=await import(await moduleFor(lib('search/provider-rows.ts')));

const song=(video,occurrence,id='same')=>({videoId:id,setVideoId:occurrence,title:occurrence,artists:'Artist',album:null,duration:null,thumbnail:null,isVideo:video,artistId:null,albumId:null,library:{addToken:'token-'+occurrence}});
const card=(kind,id='same',title=kind)=>({kind,id,title,subtitle:null,thumbnail:null,duration:null});
// Mirrors the Swift fixture: artist principal, a video, then two songs, all sharing one video ID.
const mixed=(extra={})=>({id:'mixed',title:'Results',layout:'top',items:[card('artist','artist','Artist'),card('video'),card('song'),card('song')],
 songs:[song(true,'video'),song(false,'first'),song(false,'second')],primaryItemIndex:0,relatedItemIndices:[1,2,3],moreQuery:'query',moreParams:'opaque',moreBrowseId:null,
 actions:[{title:'Play',params:'opaque',kind:'play'}],...extra});

test('preference defaults to showing videos, persists, and survives unavailable storage',()=>{
 for(const raw of [undefined,null,'',true,'true','broken',{},0])assert.equal(resolveShowVideos(raw),true);
 for(const raw of [false,'false'])assert.equal(resolveShowVideos(raw),false);
 const values=new Map(),storage={getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value)};
 let prefs=createSearchPreferences(storage);const events=[];const stop=prefs.subscribe(value=>events.push(value));
 assert.equal(prefs.currentShowVideos(),true);assert.equal(values.size,0,'reading does not mutate storage');
 prefs.setShowVideos(false);assert.equal(events.at(-1),false);assert.equal(values.get(showVideosKey),'false');assert.equal(showVideosKey,'sideb.search.showVideos.v1');
 assert.equal(createSearchPreferences(storage).currentShowVideos(),false);
 prefs.setShowVideos(true);assert.equal(createSearchPreferences(storage).currentShowVideos(),true);stop();
 const blocked=createSearchPreferences({getItem(){throw Error('blocked');},setItem(){throw Error('blocked');}});
 assert.equal(blocked.currentShowVideos(),true);blocked.setShowVideos(false);assert.equal(blocked.currentShowVideos(),false);
});

test('showing videos keeps the exact provider objects',()=>{
 const section=mixed(),page={chips:[],correction:null,sections:[section],continuation:'next'};
 assert.equal(filterSearchSection(section,true),section);assert.equal(filterSearchPage(page,true),page);
 assert.equal(filterSearchPage(null,false),null);
});

test('hiding videos keeps duplicate-ID payloads per occurrence, remaps roles and drops actions of altered blocks',()=>{
 const section=mixed(),original=structuredClone(section);
 const filtered=filterSearchSection(section,false);
 assert.deepEqual(filtered.items.map(item=>item.kind),['artist','song','song']);
 assert.deepEqual(filtered.songs.map(item=>item.setVideoId),['first','second']);
 assert.equal(filtered.songs[0],section.songs[1],'payload objects are reused, not rebuilt');
 assert.equal(filtered.primaryItemIndex,0);assert.deepEqual(filtered.relatedItemIndices,[1,2]);
 assert.equal(filtered.moreParams,'opaque');assert.equal(filtered.moreQuery,'query');assert.deepEqual(filtered.actions,[]);
 const rows=searchSectionRows(filtered);
 assert.deepEqual(rows.map(row=>row.song?.setVideoId??null),[null,'first','second']);
 const projection=projectSearchSection(filtered);
 assert.equal(projection.explicit,true);assert.equal(projection.primary.card.kind,'artist');
 assert.deepEqual(projection.related.map(row=>row.song.setVideoId),['first','second']);
 assert.deepEqual(section,original,'the source DTO is never mutated');
 assert.equal(filterSearchSection(section,false),filtered,'projection is cached per DTO');
});

test('a video principal clears the role instead of promoting another item',()=>{
 const filtered=filterSearchSection(mixed({primaryItemIndex:1,relatedItemIndices:[2,3]}),false);
 assert.equal(filtered.primaryItemIndex,null);assert.deepEqual(filtered.relatedItemIndices,[1,2]);
 const projection=projectSearchSection(filtered);
 assert.equal(projection.explicit,false);assert.deepEqual(projection.remaining.map(row=>row.song?.setVideoId??null),[null,'first','second']);
});

test('payload ordinals stay aligned when a kept card has no payload or the payload shifts',()=>{
 // The second song has no payload of its own; the fallback keeps later ordinals from stealing the next payload.
 const section={id:'s',title:'',layout:'list',items:[card('video'),card('song','a'),card('song','b'),card('song','c')],songs:[song(true,'v'),song(false,'a-occ','a'),song(false,'c-occ','c')],moreQuery:null,moreParams:null,moreBrowseId:null,actions:[]};
 const filtered=filterSearchSection(section,false);
 const rows=searchSectionRows(filtered);
 assert.deepEqual(rows.map(row=>[row.card?.id??null,row.song?.setVideoId??null]),[['a','a-occ'],['b',null],['c','c-occ']]);
});

test('sections made only of videos disappear, action-only blocks stay, and untouched blocks keep identity',()=>{
 const videosOnly={...mixed(),items:[card('video')],songs:[song(true,'video')],primaryItemIndex:null,relatedItemIndices:[]};
 const actionOnly={...mixed(),items:[],songs:[],primaryItemIndex:null,relatedItemIndices:[]};
 const songsOnly={...mixed(),items:[card('song')],songs:[song(false,'only')],primaryItemIndex:null,relatedItemIndices:[]};
 const standaloneVideo={...mixed(),items:[card('song','a')],songs:[song(false,'a-occ','a'),song(true,'extra-video','x')],primaryItemIndex:null,relatedItemIndices:[]};
 assert.equal(filterSearchSection(videosOnly,false),null);
 assert.equal(filterSearchSection(actionOnly,false),actionOnly);
 assert.equal(filterSearchSection(songsOnly,false),songsOnly,'nothing hidden keeps the original object and its actions');
 assert.deepEqual(filterSearchSection(standaloneVideo,false).songs.map(item=>item.setVideoId),['a-occ']);
 const page={chips:[{id:'1',title:'Songs',params:'p',selected:true}],correction:{query:'q'},sections:[videosOnly,songsOnly,mixed()],continuation:'next'};
 const filtered=filterSearchPage(page,false);
 assert.equal(filtered.sections.length,2);assert.equal(filtered.sections[0],songsOnly);
 assert.equal(filtered.continuation,'next');assert.equal(filtered.chips,page.chips);assert.equal(filtered.correction,page.correction);
 assert.equal(filterSearchPage(page,false),filtered,'one projection per page and preference');
 // Reactivating returns the raw page: videos are back without any refetch.
 assert.equal(filterSearchPage(page,true),page);assert.equal(page.sections.length,3);
 const untouched={chips:[],correction:null,sections:[songsOnly],continuation:null};assert.equal(filterSearchPage(untouched,false),untouched);
});

test('a continuation appends and reuses earlier projections; its token is retained when it only has videos',()=>{
 const first=mixed(),videosOnly={...mixed({id:'1:more'}),items:[card('video','v2')],songs:[song(true,'v2','v2')],primaryItemIndex:null,relatedItemIndices:[]};
 const page1={chips:[],correction:null,sections:[first],continuation:'t1'};
 const filtered1=filterSearchPage(page1,false);
 const page2={...page1,sections:[...page1.sections,videosOnly],continuation:'t2'};
 const filtered2=filterSearchPage(page2,false);
 assert.equal(filtered2.sections.length,1);assert.equal(filtered2.sections[0],filtered1.sections[0],'append reuses the first block');
 assert.equal(filtered2.continuation,'t2');
});

test('document projection exposes no hidden payload through rows, principal or actions',()=>{
 const page={chips:[],correction:null,continuation:null,sections:[mixed(),{...mixed({id:'list',layout:'list',primaryItemIndex:null,relatedItemIndices:[]}),items:[card('video','a'),card('song','a'),card('video','b')],songs:[song(true,'va','a'),song(false,'sa','a'),song(true,'vb','b')]}]};
 const entries=projectSearchDocument(filterSearchPage(page,false));
 const songs=entries.flatMap(entry=>entry.kind==='principal'?[entry.projection.primary,...entry.projection.related,...entry.projection.remaining]:entry.kind==='row'?[entry.row]:entry.kind==='carousel'?entry.rows:[]).map(row=>row.song).filter(Boolean);
 assert.deepEqual(songs.map(item=>item.setVideoId),['first','second','sa']);
 assert.equal(songs.some(item=>item.isVideo),false);
 assert.equal(entries.some(entry=>entry.kind==='actions'),false,'altered blocks omit provider actions');
 assert.equal(projectSearchDocument(filterSearchPage(page,true)).filter(entry=>entry.kind==='actions').length,1,'reactivating restores the provider action');
});

test('suggestions drop video cards and payloads (including remote history rows) but keep text queries',()=>{
 const text=(id,kind='suggestion')=>({id,kind,query:id,runs:[{text:id,bold:false}],feedbackToken:kind==='history'?'tok-'+id:null,card:null,song:null});
 const media=(id,extra)=>({id,kind:'media',query:null,runs:[],feedbackToken:null,card:null,song:null,...extra});
 const entries=[text('video games'),media('v1',{song:song(true,'v')}),media('v2',{card:card('video','v2')}),media('song',{song:song(false,'s')}),
  media('artist',{card:card('artist','a')}),text('past','history'),media('both',{card:card('song','x'),song:song(true,'x-occ','x')}),text('t2'),text('t3'),text('t4')];
 assert.equal(visibleSearchSuggestions(entries,'',true).length,entries.length);
 const hidden=visibleSearchSuggestions(entries,'',false);
 assert.deepEqual(hidden.map(entry=>entry.id),['video games','song','artist','past','t2','t3','t4']);
 assert.equal(hidden.find(entry=>entry.id==='past').feedbackToken,'tok-past','tokens of kept rows are untouched');
 // The short completion limit applies after the video filter, so media is not displaced by hidden rows.
 assert.deepEqual(visibleSearchSuggestions(entries,'vid',false).map(entry=>entry.id),['video games','song','artist','past','t2']);
 assert.deepEqual(visibleSearchSuggestions(entries,'vid',true).map(entry=>entry.id),['video games','v1','v2','song','artist','past','both','t2']);
 assert.equal(visibleSearchSuggestions(entries,'vid').length,8,'default keeps videos');
});
