import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import ts from 'typescript';
const compile=source=>`data:text/javascript;base64,${Buffer.from(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText).toString('base64')}`;
const catalogSource=await readFile(new URL('../src/lib/explore/catalog.ts',import.meta.url),'utf8');
const catalogUrl=compile(catalogSource);
const {genres,moods}=await import(catalogUrl);
const source=(await readFile(new URL('../src/lib/explore/controller.ts',import.meta.url),'utf8')).replace("'./catalog'",JSON.stringify(catalogUrl));
const {ExploreController}=await import(compile(source));
const {resolveSearchSong,relatedTopSongs}=await import(compile(await readFile(new URL('../src/lib/search/songs.ts',import.meta.url),'utf8')));
const card=(id,kind='album')=>({kind,id,title:id,subtitle:null,duration:null,thumbnail:null});
const page=(code,items=[card(code)],countries=['ZZ','UY','JP'])=>({selectedCountry:code,items,countries:countries.map(code=>({code,title:code}))});
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return{promise,resolve};};
function setup(rpc,now){let data;const controller=new ExploreController(rpc,next=>data=next,now);return{controller,get data(){return data;}};}

test('Apple category contract: 16 genres, eight moments and exact stable provider queries',async()=>{
  assert.equal(genres.length,16);assert.equal(moods.length,8);assert.equal(new Set([...genres,...moods].map(x=>x.id)).size,24);
  const apple=await readFile(new URL('../../apple/Sources/SideB/Models/ExploreCatalog.swift',import.meta.url),'utf8');
  for(const item of [...genres,...moods])assert.match(apple,new RegExp(`id: "${item.id}"[^\n]+query: "${item.query}"`));
  let args;const ctx=setup(async(_,a)=>{args=a;return[card('p','playlist')];});await ctx.controller.navigate('category:focus');assert.deepEqual(args,{query:'música para concentrarse',category:'playlists'});
});
test('release and category cache dedupes kind + ID, validates rows and shares releases preview',async()=>{
  let count=0;const ctx=setup(async()=>{count++;return[card('x'),card('x'),card('x','playlist'),card('','album'),card('bad','unknown')];});
  await ctx.controller.navigate('discover');await ctx.controller.navigate('releases');assert.equal(count,1);assert.deepEqual(ctx.data.items.map(x=>x.kind),['album','playlist']);
  await ctx.controller.navigate('releases',true);assert.equal(count,2);
});
test('late replies after navigation and account reset cannot replace data or poison cache',async()=>{
  const late=deferred();let calls=0;const ctx=setup(async(_,args)=>{calls++;return args?.category? [card('focus','playlist')]:late.promise;});
  const pending=ctx.controller.navigate('releases');await ctx.controller.navigate('category:focus');late.resolve([card('old')]);await pending;assert.equal(ctx.data.items[0].id,'focus');
  const old=deferred();const reset=setup(async()=>old.promise);const request=reset.controller.navigate('releases');reset.controller.reset();old.resolve([card('old')]);await request;assert.equal(reset.data.items.length,0);
  assert.equal(calls,2);
});
test('Global survives detection failure; selected countries must be confirmed',async()=>{
  const ctx=setup(async(command)=>{if(command==='detect_music_country')throw Error();return page('ZZ');});await ctx.controller.navigate('charts');assert.equal(ctx.data.sections[0].code,'ZZ');assert.equal(ctx.data.regionMessage,'explore.region.detect_failed');assert.equal(ctx.data.error,null);
  const mismatch=setup(async()=>page('US'));await mismatch.controller.navigate('country:UY');assert.equal(mismatch.data.sections.length,0);assert.equal(mismatch.data.error,'explore.error.load_charts');
});
test('detection expires in ten minutes, refresh redetects and regional failure preserves Global',async()=>{
  let now=0,detect=0;let selected='UY';const ctx=setup(async(command,args)=>{if(command==='detect_music_country'){detect++;return selected;}if(args.countryCode==='UY')throw Error();return page(args.countryCode);},()=>now);
  await ctx.controller.navigate('charts');assert.equal(ctx.data.sections[0].code,'ZZ');assert.equal(ctx.data.sections[1].error,'explore.error.load_charts');
  now=599999;await ctx.controller.navigate('charts');assert.equal(detect,1);now=600000;selected='JP';await ctx.controller.navigate('charts');assert.equal(detect,2);assert.equal(ctx.data.sections[1].code,'JP');
  await ctx.controller.navigate('charts',true);assert.equal(detect,3);
});
test('region selection isolates replies and LRU evicts ninth region/source',async()=>{
  const pending=deferred();const calls=[];const ctx=setup(async(command,args)=>{calls.push(args);if(args.countryCode==='UY')return pending.promise;return page(args.countryCode);});
  const uy=ctx.controller.navigate('country:UY');await ctx.controller.navigate('country:JP');pending.resolve(page('UY'));await uy;assert.equal(ctx.data.sections[0].code,'JP');
  for(const code of ['AA','BB','CC','DD','EE','FF','GG','HH','II'])await ctx.controller.navigate(`country:${code}`);
  const before=calls.length;await ctx.controller.navigate('country:AA');assert.equal(calls.length,before+1);
  let sourceCalls=0;const sources=setup(async()=>{sourceCalls++;return[card('x')];});for(const item of genres.slice(0,9))await sources.controller.navigate(`category:${item.id}`);await sources.controller.navigate(`category:${genres[0].id}`);assert.equal(sourceCalls,10);
});
test('snapshot restores route and related SongDto preserves action tokens/credits exactly',async()=>{
  const ctx=setup(async()=>[card('x')]);await ctx.controller.navigate('releases');ctx.controller.setScrollTop(520);const saved=ctx.controller.capture();await ctx.controller.navigate('genres');ctx.controller.restore(saved);assert.equal(ctx.data.route,'releases');assert.equal(ctx.data.items[0].id,'x');assert.equal(ctx.data.scrollTop,520);
  const real={videoId:'a',title:'A',setVideoId:'occurrence',library:{addToken:'private-test'},artistRuns:[{text:'Guest',browseId:'artist'}]};
  const results={top:[card('artist','artist')],topSongs:[real,{videoId:'b'},{videoId:'c'},{videoId:'d'}],songs:[]};
  assert.equal(resolveSearchSong(card('a','song'),results),real);assert.equal(relatedTopSongs(results).length,3);assert.equal(relatedTopSongs(results)[0],real);assert.equal(resolveSearchSong(card('missing','song'),results),null);
});
