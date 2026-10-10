import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const compile = text => ts.transpileModule(text,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const url = text => `data:text/javascript;base64,${Buffer.from(text).toString('base64')}`;
const module = async (file, replacements={}) => {let source=compile(await readFile(new URL(`../src/lib/${file}.ts`,import.meta.url),'utf8'));for(const [path,ref] of Object.entries(replacements)) source=source.replaceAll(`'${path}'`,JSON.stringify(ref));return url(source);};
const settingsUrl=await module('home/settings'), presentationUrl=await module('home/presentation'),playerUrl=await module('player/controller');
const { defaults, decodeSettings, categoryKey, orderCategories, accountSettingsKey, missingHomeSources }=await import(settingsUrl);
const songMetadataUrl=await module('home/songMetadata');
const { projectHome, featuredCapacity, featuredLayout, visibleSignature }=await import(await module('home/featured',{'./settings':settingsUrl,'./presentation':presentationUrl,'./songMetadata':songMetadataUrl}));
const { sourceActive, occurrenceActive, mediaRequestCurrent, mediaKey }=await import(await module('player/media',{'../home/settings':settingsUrl,'./controller':playerUrl}));
const { prepareCollectionPlayback, emptyPlaybackData }=await import(playerUrl);
const { HomeController }=await import(await module('home/controller',{'./presentation':presentationUrl}));
const metadataUrl=await module('home/collectionMetadata');
const { metadataFor, durationSeconds, providerDuration }=await import(metadataUrl);
const { FeaturedMetadataController }=await import(await module('home/metadata',{'./collectionMetadata':metadataUrl}));
const { samplePalette, choosePalette, hueDistance, ambientColor, neutral, collectionAmbientFrame }=await import(await module('home/ambient'));
const { alignCollectionAnchor, featuredSelectionKey, FeaturedWheelInput }=await import(await module('home/pages'));
const item=(id,kind='album')=>({id,kind,title:id,subtitle:null,thumbnail:null,duration:null,artists:null,artistId:null,albumId:null,album:null,artistRuns:[],explicit:false});
const section=(title,items)=>({title,items,format:'largeCards',moreBrowseId:null,moreParams:null});
const albumPage=(count)=>[section('Albums for you',Array.from({length:count},(_,i)=>item(`album-${i}`)))];
const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject};};
const settle=()=>new Promise(resolve=>setTimeout(resolve,0));

test('ambient geometry follows the collection at scroll and elastic boundaries',()=>{
 for(const [top,height,scroll,viewport,expected] of [
  [32,262,0,800,{top:0,height:434,visible:true}],
  [-118,262,150,800,{top:-150,height:434,visible:true}],
  [-568,262,600,800,{top:-600,height:434,visible:false}],
  [52,262,-20,800,{top:0,height:454,visible:true}],
  [32,350,0,800,{top:0,height:522,visible:true}],
 ])assert.deepEqual(collectionAmbientFrame(top,height,scroll,viewport),expected);
});

test('first enabled source fills all six pages; repeated collections belong to the first source',()=>{
 const sections=[section('Albums for you',Array.from({length:14},(_,i)=>item(`a${i}`))),section('Listen again',[item('a0'),item('later')])];
 const p=projectHome(sections,null,defaults(),'albums',2);
 assert.deepEqual(p.collections.map(i=>i.id),Array.from({length:12},(_,i)=>`a${i}`));
 assert.deepEqual(p.shelves.flatMap(s=>s.items.map(i=>i.record.id)),['later','a12','a13']);
});
test('disabled named families cannot return through Other Home; all disabled is empty',()=>{
 const s=defaults();s.albumSources=s.albumSources.map(row=>({...row,enabled:row.source==='otherHome'}));
 assert.deepEqual(projectHome([...albumPage(20),section('Unknown',[item('unknown')])],null,s,'albums',2).collections.map(i=>i.id),['unknown']);
 s.albumSources=s.albumSources.map(row=>({...row,enabled:false}));assert.equal(projectHome(albumPage(20),null,s,'albums',2).collections.length,0);
});
test('12/24/36 distinct exposed collections; narrowing returns displaced items to shelves',()=>{
 for(const capacity of [2,4,6]){const p=projectHome(albumPage(40),null,defaults(),'albums',capacity);assert.equal(p.collections.length,6*capacity);assert.equal(p.shelves[0].items.length,40-6*capacity);}
 assert.equal(featuredCapacity(600),2);assert.equal(featuredCapacity(1600),4);assert.equal(featuredCapacity(2400),6);
});
test('hiding a category does not remove its featured candidates or Speed Dial',()=>{
 const s=defaults();s.hiddenCategoryKeys=['recommended-albums','quick-picks'];
 const p=projectHome([...albumPage(18),section('Quick picks',[item('song','song')])],null,s,'albums',2);
 assert.equal(p.collections.length,12);assert.equal(p.songs[0].id,'song');assert.equal(p.shelves.length,0);assert.equal(p.categories.length,2);
});
test('song pages stop at 27, prioritize quick picks and dedupe by video ID',()=>{
 const p=projectHome([section('Unknown',Array.from({length:30},(_,i)=>item(`song${i}`,'song'))),section('Quick picks',[item('seed','song'),item('song0','song')])],null,defaults(),'albums',2);
 assert.equal(p.songs.length,27);assert.deepEqual(p.songs.slice(0,2).map(s=>s.id),['seed','song0']);assert.equal(new Set(p.songs.map(s=>s.id)).size,27);
});

test('Speed Dial exposes safe playback credits while retaining the raw provider snapshot',()=>{
 const original={...item('frank','song'),subtitle:'Frank Ocean • 337M plays',artists:'Frank Ocean',album:'337M plays'};
 const sections=[section('Quick picks',[original])];
 const p=projectHome(sections,null,defaults(),'albums',2);
 assert.equal(p.songs[0].artists,'Frank Ocean');assert.equal(p.songs[0].album,null);
 assert.equal(p.songs[0].subtitle,original.subtitle);assert.equal(sections[0].items[0].album,'337M plays');
});
test('playlist VL/LM canonical dedupe and source kind remain independent',()=>{
 const p=projectHome([section('Mixes for you',[item('VLLM','playlist'),item('LM','playlist'),item('x','album')])],null,defaults(),'playlists',2);
 assert.deepEqual(p.collections.map(i=>i.id),['VLLM']);
});
test('supplementary recent albums use album IDs and stored album art, never video art',()=>{
 const s=defaults();s.albumSources=s.albumSources.map(row=>({...row,enabled:row.source==='recentAlbums'}));
 const p=projectHome([],null,s,'albums',2,[{...item('album'),'thumbnail':'album-art'}],[],[{items:[{albumId:'album',album:'Album',artists:'Artist',artistId:'a',thumbnail:'video-art'},{albumId:null,album:'Fake',artists:'A',artistId:null}]}]);
 assert.equal(p.collections.length,1);assert.equal(p.collections[0].thumbnail,'album-art');
});
test('settings decoding migrates missing fields, ignores invalid sources and uses defaults for future versions',()=>{
 const s=decodeSettings({albumSources:[{source:'recommendedAlbums',enabled:false},{source:'recommendedAlbums',enabled:true},{source:'libraryPlaylists',enabled:true}],hiddenCategoryKeys:['gone','gone',3]});
 assert.equal(s.albumSources[0].enabled,false);assert.equal(s.albumSources.length,1);assert.deepEqual(s.hiddenCategoryKeys,['gone']);assert.deepEqual(decodeSettings({version:9,albumSources:[]}),defaults());
 assert.equal(categoryKey(' ÁLBUMES PARA TI '),'recommended-albums');
});
test('custom ordering keeps absent keys and new categories at the end without reactivating hidden ones',()=>{
 const s=orderCategories({...defaults(),categoryOrder:['gone','custom:b'],hiddenCategoryKeys:['custom:c']},['custom:b','custom:a']);
 assert.deepEqual(s.categoryOrder,['custom:b','custom:a','gone']);
 const p=projectHome([section('C',[item('c','artist')]),section('A',[item('a','artist')]),section('B',[item('b','artist')]),section('D',[item('d','artist')])],null,s,'albums',2);
 assert.deepEqual(p.shelves.map(s=>s.title),['B','A','D']);assert.ok(s.hiddenCategoryKeys.includes('custom:c'));
});
test('account preference keys are hashed and isolated',async()=>{const a=await accountSettingsKey('account:a@example.com'),b=await accountSettingsKey('account:b@example.com');assert.notEqual(a,b);assert.ok(!a.includes('example'));assert.match(a,/v1\.[a-f0-9]{64}$/);});
test('radio stays on its seed after advancing; radio does not activate album metadata',()=>{
 const state={...emptyPlaybackData(),currentTrack:{videoId:'advanced',albumId:'album'},queue:{items:[],source:{kind:'radio',id:'seed'},currentIndex:null,revision:4}};
 assert.equal(sourceActive(state,'song','seed'),true);assert.equal(sourceActive(state,'song','advanced'),false);assert.equal(sourceActive(state,'album','album'),false);
 state.queue.source={kind:'playlist',id:'LM'};assert.equal(sourceActive(state,'playlist','VLLM'),true);
});
test('exact duplicate occurrence remains identifiable after shuffle and reordering',()=>{
 const songs=[{videoId:'same',title:'A',artists:'',duration:null,thumbnail:null,setVideoId:'first'},{videoId:'same',title:'A',artists:'',duration:null,thumbnail:null,setVideoId:'second'}];
 const prepared=prepareCollectionPlayback(songs,1,{kind:'playlist',id:'VLLM',title:'Likes'});
 const entries=prepared.options.queueItems;
 const state={...emptyPlaybackData(),currentTrack:prepared.song,isShuffle:true,queue:{items:[entries[1],entries[0]],currentIndex:0,source:{kind:'playlist',id:'LM'},revision:1}};
 assert.equal(occurrenceActive(state,songs[1],1,'playlist','LM'),true);assert.equal(occurrenceActive(state,songs[0],0,'playlist','LM'),false);
});
test('manual feed click crosses hidden and repeated pages, then stops on visible change',async()=>{
 let data,calls=0;const settings=defaults();settings.hiddenCategoryKeys=['custom:hidden'];settings.albumSources=settings.albumSources.map(r=>({...r,enabled:false}));
 const signature=page=>visibleSignature(projectHome(page.sections,'chip',settings,'albums',2));
 const first={chips:[],sections:[section('Hidden',[item('hidden','artist')])],continuation:'t0'};
 const home=new HomeController(async command=>command==='get_home_page'?first:{chips:[],sections:[calls++<2?first.sections[0]:section('Visible',[item('visible','artist')])],continuation:`t${calls}`},next=>data=next,signature);
 await home.load('chip');await home.loadMore();assert.equal(calls,3);assert.equal(data.moreNotice,null);assert.equal(data.page.sections.length,2);
});
test('no visible change respects three-request budget; an error keeps continuation for retry',async()=>{
 let data,calls=0,fail=false;const home=new HomeController(async command=>{if(command==='get_home_page')return {chips:[],sections:[],continuation:'t0'};if(fail){fail=false;throw Error('retry');}return {chips:[],sections:[],continuation:`t${++calls}`};},next=>data=next,()=>'',()=>false);
 await home.load();await home.loadMore();assert.equal(calls,3);assert.ok(data.moreNotice);fail=true;await home.loadMore();assert.equal(data.page.continuation,'t3');assert.equal(data.moreError,'retry');await home.loadMore();assert.equal(calls,6);
});
test('metadata holds max two requests, rejects old account and only fetches first playlist page',async()=>{
 let output,active=0,max=0;const requests=[];
 const controller=new FeaturedMetadataController((command,args)=>{assert.ok(['get_album','get_playlist'].includes(command));active++;max=Math.max(max,active);const d=deferred();requests.push({d,args});return d.promise.finally(()=>active--);},data=>output=data);
 controller.visible([item('a'),item('b'),item('c','playlist')]);assert.equal(requests.length,2);controller.reset();controller.visible([item('new','playlist')]);
 requests[0].d.resolve({artist:'old',artistId:'old',items:[]});requests[1].d.resolve({artist:'old',artistId:'old',items:[]});await settle();assert.equal(requests.length,3);requests[2].d.resolve({subtitle:'Owner',items:[{}],continuation:'more'});await settle();assert.equal(max,2);assert.deepEqual(Object.keys(output),['playlist|new']);assert.equal(output['playlist|new'].summary,'Playlist');assert.equal(output['playlist|new'].artists,'Owner');
});
test('small blue accent survives earth tones; selected colors separate similar art families',()=>{
 const pixels=[];for(let i=0;i<900;i++)pixels.push(112,79,49,255);for(let i=0;i<24;i++)pixels.push(20,65,215,255);
 const colors=samplePalette(pixels);assert.ok(colors.some(([r,g,b])=>b>r*2));const palette=choosePalette(colors);assert.ok(hueDistance(...palette)>.1);
 const warm=choosePalette([[160,90,40],[140,75,30]]);assert.ok(hueDistance(...warm)>.1);
});
test('metadata shares requests for the same visible page and evicts details beyond six',async()=>{
 const requests=[];let output;const controller=new FeaturedMetadataController((_command,args)=>{const d=deferred();requests.push({d,args});return d.promise;},data=>output=data);
 const items=[item('a'),item('b'),item('c')];controller.visible(items);controller.visible(items);assert.equal(requests.length,2);
 for(let i=0;i<2;i++)requests[i].d.resolve({artist:'A',artistId:null,items:[{duration:'3:20'}]});await settle();assert.equal(requests.length,3);requests[2].d.resolve({artist:'C',artistId:null,items:[]});await settle();assert.deepEqual(Object.keys(output).sort(),['album|a','album|b','album|c']);
 controller.visible([item('d'),item('e'),item('f'),item('g'),item('h'),item('i')]);
 for(let i=3;i<9;i++){await settle();requests[i].d.resolve({artist:'new',artistId:null,items:[]});}await settle();
 controller.visible([item('a')]);assert.equal(requests.length,10);controller.visible([]);requests[9].d.resolve({artist:'hidden',artistId:null,items:[]});await settle();assert.deepEqual(output,{});
});

// Expected behavior follows the named Apple tests, not a second copy of the TypeScript implementation.
test('Mac featured priorities: songs keep Listen Again/Forgotten/Library before generic and videos stay in shelves',()=>{
 const rows=[section('Generic',[item('generic','song'),item('shared','playlist')]),section('From your library',[item('library','song')]),section('Forgotten favorites',[item('forgotten','song')]),section('Listen again',[item('recent','song')]),section('Quick picks',[item('pick','song'),item('shared','song'),item('clip','video')])];
 const p=projectHome(rows,null,defaults(),'albums',2);
 assert.deepEqual(p.songs.map(i=>i.id),['pick','shared','recent','forgotten','library','generic']);
 assert.deepEqual(p.shelves.flatMap(s=>s.items.map(i=>i.record.id)),['clip','shared']);
});
test('Mac preference decoding keeps explicit empty/subset rules; only missing fields receive defaults',()=>{
 const p=decodeSettings({albumSources:[],playlistSources:[{source:'otherHome',enabled:false}],categoryOrder:['','a','a'],hiddenCategoryKeys:['','b']});
 assert.deepEqual(p.albumSources,[]);assert.deepEqual(p.playlistSources,[{source:'otherHome',enabled:false}]);assert.deepEqual(p.categoryOrder,['a']);assert.deepEqual(p.hiddenCategoryKeys,['b']);assert.equal(decodeSettings({}).albumSources.length,8);
});
test('Mac categories preserve first alias title, custom/provider order and real chip identity',()=>{
 const rows=[section(' B ',[item('b','artist')]),section('Álbumes para ti',[item('a')]),section('Albums for you',[item('c')]),section('Empty',[])];
 const s={...defaults(),categoryOrderMode:'custom',categoryOrder:['recommended-albums','custom:b']};
 const p=projectHome(rows,'chip',s,'albums',2);assert.deepEqual(p.categories.map(i=>i.title),['Álbumes para ti',' B ','Empty']);assert.ok(p.shelves[0].id.startsWith('chip|'));
});
test('Mac recent album fallback accepts missing album title and keeps real artist links',()=>{
 const s={...defaults(),albumSources:[{source:'recentAlbums',enabled:true}]};
 const p=projectHome([],null,s,'albums',2,[],[],[{items:[{albumId:'a',album:null,artists:'Artist',artistId:'UCartist',artistRuns:[{text:'Artist',id:'UCartist'}]},{albumId:'a',album:'Repeated',artists:'',artistId:null}]}]);
 assert.equal(p.collections.length,1);assert.equal(p.collections[0].title,'Álbum');assert.equal(p.collections[0].thumbnail,null);assert.equal(p.collections[0].artistRuns[0].id,'UCartist');
});
test('Mac ambient thumbnails use two distinct collection covers before two distinct song covers',()=>{
 const rows=[section('Albums for you',[{...item('a'),thumbnail:'a'},{...item('b'),thumbnail:'a'},{...item('c'),thumbnail:'b'}]),section('Quick picks',[{...item('s','song'),thumbnail:'s'},{...item('t','song'),thumbnail:'s'},{...item('u','song'),thumbnail:'t'}])];
 assert.deepEqual(projectHome(rows,null,defaults(),'albums',2).artwork,['a','b','s','t']);
});
test('Mac HomeFeaturedLayout matches 1100/1512/1920 capacities and gives absent dial space back',()=>{
 for(const [width,columns]of [[1100,1],[1512,2],[1920,3]]){const layout=featuredLayout(width,27,6);assert.equal(layout.columns,columns);assert.equal(layout.songWidth,448);assert.equal(layout.cardHeight,212);}
 assert.equal(featuredLayout(1100,0,20).capacity,4);assert.equal(featuredLayout(1920,9,1).capacity,2);assert.equal(featuredLayout(899,9,20).wide,false);assert.equal(featuredLayout(900,9,20).wide,true);
});
test('Mac pages keep exact anchor through narrowing/widening and category changes do not reset featured pages',()=>{
 const ids=['a','b','c','d','e','f'];let anchor=alignCollectionAnchor(2,ids,ids);
 assert.equal(Math.floor(anchor/4),0);anchor=alignCollectionAnchor(anchor,ids,ids);assert.equal(Math.floor(anchor/2),1);
 assert.equal(alignCollectionAnchor(2,ids,['new',...ids]),3);assert.equal(alignCollectionAnchor(2,ids,['a']),0);
 const base=defaults(),changed={...base,categoryOrderMode:'youtube',hiddenCategoryKeys:['quick-picks']};
 assert.equal(featuredSelectionKey('a',null,'albums',base),featuredSelectionKey('a',null,'albums',changed));
 assert.notEqual(featuredSelectionKey('a',null,'albums',base),featuredSelectionKey('b',null,'albums',base));
 assert.notEqual(featuredSelectionKey('a',null,'albums',base),featuredSelectionKey('a',null,'albums',{...base,albumSources:[]}));
});
test('Mac horizontal wheel pages once per gesture and vertical motion passes through',()=>{
 const wheel=new FeaturedWheelInput();assert.equal(wheel.consume(5,30,1000),null);assert.equal(wheel.consume(25,1,1100),null);assert.equal(wheel.consume(25,1,1200),1);assert.equal(wheel.consume(100,1,1300),null);assert.equal(wheel.consume(-50,0,1700),-1);
});
test('Mac preload stops as soon as all enabled named sources arrive and ignores supplemental sources',async()=>{
 const settings={...defaults(),albumSources:[{source:'recommendedAlbums',enabled:true},{source:'recentAlbums',enabled:true}]};let data,calls=0;
 const home=new HomeController(async command=>command==='get_home_page'?{sections:[],chips:[],continuation:'a'}:{sections:albumPage(2),chips:[],continuation:`p${++calls}`},next=>data=next,undefined,page=>missingHomeSources(page.sections.map(s=>s.title),settings,'albums'));
 await home.load();assert.equal(calls,1);assert.equal(data.page.continuation,'p1');
 assert.equal(missingHomeSources([], {...settings,albumSources:[{source:'otherHome',enabled:true},{source:'libraryAlbums',enabled:true}]},'albums'),false);
 assert.equal(missingHomeSources(['ÁLBUMES PARA TI'],settings,'albums'),false);
});
test('Mac album metadata title/year/count/duration and unloaded artist cleanup',()=>{
 const album={title:'Blonde',artist:'Frank Ocean',artistId:'UCfrank',subtitle:'2016',secondSubtitle:null,items:[...Array(16).fill({duration:'3:32'}),{duration:'3:28'}]};
 assert.deepEqual(metadataFor(item('a'),album),{title:'Blonde',artists:'Frank Ocean',artistId:'UCfrank',summary:'Álbum • 2016 • 17 canciones • 1 h'});
 assert.equal(metadataFor({...item('a'),subtitle:'Álbum · 2016 · Travis Scott',artists:'Álbum • Travis Scott'}).artists,'Travis Scott');
 assert.equal(metadataFor({...item('a'),subtitle:'Álbum · 2016'}).summary,'Álbum • 2016');
 assert.equal(metadataFor({...item('a'),artists:'The 1975 • Song Hour'}).artists,'The 1975 • Song Hour');
});
test('Mac album metadata does not invent malformed totals and uses provider summary for empty/incomplete rows',()=>{
 assert.equal(metadataFor(item('a'),{subtitle:'2016',items:[{duration:'1:60'},{duration:'-5'}]}).summary,'Álbum • 2016 • 2 canciones');
 assert.equal(metadataFor(item('a'),{subtitle:'2016',secondSubtitle:'17 songs • 1 hour',items:[]}).summary,'Álbum • 2016 • 17 canciones • 1 h');
 assert.equal(metadataFor(item('a'),{secondSubtitle:'2 songs • 1 hour',items:[{duration:'3:00'},{duration:null}]}).summary,'Álbum • 2 canciones • 1 h');
 for(const invalid of ['1:60','1:99:00','-5','3:','1.5','1:01:60'])assert.equal(durationSeconds(invalid),null);
 assert.equal(durationSeconds('90'),90);assert.equal(durationSeconds('1:02:03'),3723);assert.equal(providerDuration('A 1975 concert • 1 h 5 min',false),'1 h 5 min');assert.equal(providerDuration('1975',false),null);
});
test('Mac playlist metadata never treats partial rows as catalog total, but accepts explicit provider totals',()=>{
 const record={...item('p','playlist'),subtitle:'Playlist • 2026 • Creator'};
 const detail={title:'Detail title',subtitle:null,items:[{duration:'3:00'},{duration:'4:00'}],continuation:'next'};
 assert.deepEqual(metadataFor(record,detail),{title:'Detail title',artists:'Creator',artistId:null,summary:'Playlist'});
 assert.equal(metadataFor({...record,artists:'Home creator',artistId:'UCowner'},{...detail,subtitle:'Other creator • 2,000 songs • 4 hours'}).summary,'Playlist • 2000 canciones • 4 h');
 assert.equal(metadataFor(record,{...detail,continuation:null}).summary,'Playlist • 2 canciones • 7 min');
});
test('Mac playlist creator link uses only real UC channel IDs and avoids years/views as artists',()=>{
 const value=metadataFor({...item('p','playlist'),artists:'Playlist • 2026 • Creator • 20K views',artistId:'browse-not-channel',artistRuns:[{text:'Creator',id:'UCcreator'}]});
 assert.equal(value.artists,'Creator');assert.equal(value.artistId,'UCcreator');assert.equal(value.summary,'Playlist');
 assert.equal(metadataFor({...item('p','playlist'),subtitle:'2026 • 3000 views'}).artists,null);
});
test('Mac metadata caches six per kind and refreshes item fallback without refetching a detail',async()=>{
 let output,calls=0;const model=new FeaturedMetadataController(async(command)=>{calls++;return command==='get_album'?{title:'Album',artist:null,artistId:null,items:[]}:{title:'Playlist',subtitle:null,continuation:null,items:[]};},value=>output=value);
 model.visible([item('a')]);await settle();model.visible([item('p','playlist')]);await settle();model.visible([{...item('a'),artists:'Refreshed artist'}]);
 assert.equal(calls,2);assert.equal(output['album|a'].artists,'Refreshed artist');
});
test('Mac sampler rejects gray/black/white/transparent/malformed pixels, while supported blue remains',()=>{
 assert.deepEqual(samplePalette([12,34,56]),[]);assert.deepEqual(samplePalette([220,40,35,0]),[]);
 const pixels=[];for(let i=0;i<900;i++)pixels.push(126,126,126,255);for(let i=0;i<100;i++)pixels.push(7,7,7,255);for(let i=0;i<24;i++)pixels.push(34,116,218,255);
 const [tint]=samplePalette(pixels);assert.ok(tint[2]>tint[1]*1.7);assert.ok(tint[1]>tint[0]*1.7);
 const gray=Array.from({length:32},()=>[128,128,128,255]).flat();assert.deepEqual(samplePalette(gray),[]);assert.deepEqual(choosePalette([]),neutral.map(ambientColor));
});
test('Mac source playback survives navigation but rejects later playback, EOF generation and account',()=>{
 const captured={play:1,session:2,navigation:3,generation:4};
 assert.equal(mediaRequestCurrent(captured,{...captured,navigation:5},true),true);
 assert.equal(mediaRequestCurrent(captured,{...captured,navigation:5}),false);
 for(const field of ['play','session','generation'])assert.equal(mediaRequestCurrent(captured,{...captured,[field]:captured[field]+1},true),false);
 const state={...emptyPlaybackData(),currentTrack:{videoId:'track'},queue:{source:{kind:'mix',id:'LM'},items:[],currentIndex:null}};
 assert.equal(sourceActive(state,'playlist','VLLM'),true);assert.equal(sourceActive(state,'mix','LM'),true);assert.equal(sourceActive(state,'song',''),false);
 assert.equal(mediaKey({kind:'mix',id:'VLLM'}),mediaKey({kind:'playlist',id:'LM'}));
});
