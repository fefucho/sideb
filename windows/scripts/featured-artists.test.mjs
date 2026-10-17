import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import ts from 'typescript';
const source=await readFile(new URL('../src/lib/featured/artists.ts',import.meta.url),'utf8');
const output=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {FeaturedArtistService,featuredClauses,rankArtists,normalizeArtist}=await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const fixtures=JSON.parse(await readFile(new URL('../../docs/fixtures/featured-artists.json',import.meta.url),'utf8'));
const track=(title,videoId='one')=>({videoId,title,artists:'Main',artistId:'main',album:'Album',artistRuns:[]});
const card=(name,id=name)=>({kind:'artist',title:name,id});
const storage=()=>{const values=new Map();return {getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value)};};
const tick=()=>new Promise(resolve=>setTimeout(resolve,0));
for(const fixture of fixtures)test(`shared corpus: ${fixture.title}`,async()=>{
 assert.deepEqual(featuredClauses(fixture.title).map(c=>c.name),fixture.clauses);
 let queries=0;const service=new FeaturedArtistService({scope:'test',storage:storage(),search:async name=>{queries++;return fixture.names.filter(n=>normalizeArtist(n)===normalizeArtist(name)).map(n=>card(n));}});
 const credits=await service.title(track(fixture.title));assert.deepEqual(credits.map(c=>c.name),fixture.names);assert.ok(queries<=8,`${queries} queries`);
 for(const credit of credits)assert.equal(fixture.title.slice(credit.start,credit.end),credit.name);
});
test('provider partitions require no query and preserve groups, punctuation and original metadata',async()=>{
 let queries=0;const song=track('Tema (feat. Earth, Wind & Fire & Kanye West)');song.artistRuns=[{text:'Earth, Wind & Fire',id:'group'},{text:'Kanye West',id:'kanye'}];
 const before=JSON.stringify(song),service=new FeaturedArtistService({scope:'test',storage:storage(),search:async()=>{queries++;return [];}});
 assert.deepEqual((await service.title(song)).map(c=>[c.name,c.id,c.provenance]),[['Earth, Wind & Fire','group','provider'],['Kanye West','kanye','provider']]);assert.equal(queries,0);assert.equal(JSON.stringify(song),before);
});
test('homonyms choose provider order automatically; distinct-word omissions, non-artists and empty IDs fail',()=>{
 assert.deepEqual(rankArtists('Joe Fox',[card('Joe','wrong'),{...card('Joe Fox','album'),kind:'album'},card('Joe Fox',''),card('Joe Fox','second'),card('Joe Fox','first'),card('Joe Fox','second')]).map(c=>c.id),['second','first']);
 assert.deepEqual(rankArtists('Earth, Wind & Fire',[card('Earth','bad')]),[]);
});
test('context query evaluates results against guest name',async()=>{
 const calls=[];const service=new FeaturedArtistService({scope:'test',storage:storage(),search:async q=>{calls.push(q);return q==='Guest Main'?[card('Main','wrong'),card('Guest','guest')]:[];}});
 assert.equal((await service.resolve(track('Title'),'Guest')).id,'guest');assert.deepEqual(calls,['Guest','Guest Main']);
});
test('explicit correction persists for context, provider wins later and positive cache survives restart',async()=>{
 const disk=storage(),song=track('Title');let calls=0;const options={scope:'account-a',storage:disk,search:async()=>{calls++;return [card('Guest','inferred')];}};
 let service=new FeaturedArtistService(options);assert.equal((await service.resolve(song,'Guest')).id,'inferred');service=new FeaturedArtistService(options);assert.equal((await service.resolve(song,'Guest')).id,'inferred');assert.equal(calls,1);
 service.choose(song,'Guest','chosen');service=new FeaturedArtistService(options);assert.equal((await service.resolve(song,'Guest')).provenance,'userChoice');
 assert.equal((await service.resolve({...song,videoId:'two'},'Guest')).id,'inferred');song.artistRuns=[{text:'Guest',id:'real'}];assert.equal((await service.resolve(song,'Guest')).id,'real');
 service.resetScope('account-b');assert.equal((await service.resolve(track('Title'),'Guest')).id,'inferred');
});
test('bounded concurrency, shared in-flight requests and stale session never navigate',async()=>{
 let active=0,maximum=0;const releases=[];const service=new FeaturedArtistService({scope:'a',storage:storage(),search:async q=>{active++;maximum=Math.max(maximum,active);await new Promise(resolve=>releases.push(resolve));active--;return [card(q,q)];}});
 const first=service.resolve(track('Title'),'Guest');const duplicate=service.resolve(track('Title'),'Guest');const others=Array.from({length:5},(_,i)=>service.resolve(track('Title'),'Other '+i));await tick();assert.equal(active,2);
 while(releases.length||active){releases.splice(0).forEach(resolve=>resolve());await tick();}
 await Promise.all([first,duplicate,...others]);assert.equal(maximum,2);
 let release;service['options'].search=async()=>{await new Promise(resolve=>release=resolve);return [card('Late','late')];};let navigated=false;const opening=service.open(track('Title'),'Late',()=>navigated=true);await tick();service.resetScope('b');release();await opening;assert.equal(navigated,false);
});
test('cancelled and timeout clicks have no late navigation; incompatible names open search',async()=>{
 let release;const searches=[],service=new FeaturedArtistService({scope:'a',storage:storage(),onSearch:name=>searches.push(name),search:async()=>{await new Promise(resolve=>release=resolve);return [card('Guest','guest')];}});
 let navigated=false;const abort=new AbortController();const opening=service.open(track('Title'),'Guest',()=>navigated=true,abort.signal);await tick();abort.abort();release();await opening;assert.equal(navigated,false);assert.deepEqual(searches,[]);
 service['options'].search=async()=>[];await service.open(track('Title'),'Unknown',()=>navigated=true);assert.deepEqual(searches,['Unknown']);
 service['options'].search=async()=>{await new Promise(resolve=>release=resolve);return [card('Timeout','timeout')];};const timed=service.open(track('Title'),'Timeout',()=>navigated=true);await timed;assert.equal(navigated,false);assert.deepEqual(searches,['Unknown','Timeout']);release();await tick();assert.equal(navigated,false);
});
test('corrupt persisted data does not become a destination',async()=>{
 const disk=storage();disk.setItem('sideb.featured.choices.v1:a','[]');disk.setItem('sideb.featured.cache.v1:a','null');const service=new FeaturedArtistService({scope:'a',storage:disk,search:async()=>[]});assert.equal((await service.resolve(track('Title'),'Guest')).id,undefined);
});
test('first click resolves the guest under the original title offset before hover finishes',async()=>{
 const title='Tema (feat. Joe Fox & Kanye West)',opened=[],service=new FeaturedArtistService({scope:'test',storage:storage(),search:async name=>['Joe Fox','Kanye West'].includes(name)?[card(name)]:[]});
 await service.open(track(title),'Joe Fox & Kanye West',id=>opened.push(id),undefined,title.indexOf('Kanye')+2);assert.deepEqual(opened,['Kanye West']);
});

test('title-only negative cannot suppress contextual click, including after cache restart',async()=>{
 const disk=storage(),queries=[],opened=[],searches=[],song=track('Title (feat. Guest)');
 const options={scope:'context',storage:disk,search:async q=>{queries.push(q);return q==='Guest Main'?[card('Guest','guest')]:[];},onSearch:name=>searches.push(name)};
 let service=new FeaturedArtistService(options);await service.title(song);service=new FeaturedArtistService(options);
 await service.open(song,'Guest',id=>opened.push(id));assert.deepEqual(opened,['guest']);assert.deepEqual(searches,[]);assert.deepEqual(queries,['Guest','Guest Main']);
});
test('contextual click promotes a simultaneous title-only flight; complete negatives remain cached',async()=>{
 const queries=[];let release;const service=new FeaturedArtistService({scope:'context',storage:storage(),search:async q=>{queries.push(q);if(queries.length===1)await new Promise(r=>release=r);return q==='Guest Main'?[card('Guest','guest')]:[];}});
 const song=track('Title (feat. Guest)'),prefetch=service.title(song);await tick();const click=service.resolve(song,'Guest');release();await prefetch;assert.equal((await click).id,'guest');assert.deepEqual(queries,['Guest','Guest Main']);
 const negative=new FeaturedArtistService({scope:'negative',storage:storage(),search:async q=>{queries.push(q);return [];}});await negative.resolve(song,'Missing');const count=queries.length;await negative.resolve(song,'Missing');assert.equal(queries.length,count);
});
test('fresh partial negatives spend only the contextual attempt; expired partials repeat exact lookup',async()=>{
 const queries=[],song=track('Title (feat. Guest)'),service=new FeaturedArtistService({scope:'budget',storage:storage(),search:async q=>{queries.push(q);return q==='Guest Main'?[card('Guest','guest')]:[];}});
 await service.title(song);const budget={remaining:1};assert.equal((await service.resolve(song,'Guest',budget)).id,'guest');assert.equal(budget.remaining,0);assert.deepEqual(queries,['Guest','Guest Main']);
 const expired=new FeaturedArtistService({scope:'expired',storage:storage(),search:async q=>{queries.push(q);return q==='Guest Main'?[card('Guest','guest')]:[];}});
 await expired.title(song);for(const value of expired['cache'].values())value.time=Date.now()-600001;
 const oldCount=queries.length;assert.equal((await expired.resolve(song,'Guest')).id,'guest');assert.deepEqual(queries.slice(oldCount),['Guest','Guest Main']);
});
