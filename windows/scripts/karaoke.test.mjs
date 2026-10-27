import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import ts from 'typescript';
async function load(file){const source=await readFile(new URL('../src/lib/player/'+file,import.meta.url),'utf8');return import('data:text/javascript;base64,'+Buffer.from(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText).toString('base64'));}
const {prepareKaraoke,karaokeFocus,karaokeGapIndex,seekSeconds,KaraokeController}=await load('karaoke.ts');
const {KaraokeClock}=await load('karaoke-clock.ts');
const line=(text,timeMs,endTimeMs,extra={})=>({text,timeMs,endTimeMs,words:[],...extra});
const info=(lines,extra={})=>({provider:'TTML',isSynced:true,instrumental:false,lines,...extra});
const words=(text,start,end)=>[{text,startMs:start,endMs:end}];
const track={videoId:'same',title:'Song',artists:'Artist',duration:null};
const settle=()=>new Promise(resolve=>setTimeout(resolve,0));
function deferred(){let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return{resolve,reject,promise};}

test('Unicode text and native ranges survive reconciliation; mismatched detail falls back without losing text',()=>{
 const text='¡Sí! 👩🏽‍🚀 שלום';const doc=prepareKaraoke(info([line(text,3418,9000,{words:[{text:'¡Sí!',startMs:3418,endMs:4800},{text:'👩🏽‍🚀',startMs:5000,endMs:6000},{text:'שלום',startMs:6500,endMs:9000}]})]),10);
 assert.deepEqual(doc.lines[0].segments.map(s=>text.slice(s.start,s.end)),['¡Sí!','👩🏽‍🚀','שלום']);
 assert.equal(doc.lines[0].start,3418);assert.equal(seekSeconds(doc.lines[0].start,0),3.418);
 const invalid=prepareKaraoke(info([line('Hello!',100,400,{words:words('Hello',100,400)})]),10);
 const brokenCluster=prepareKaraoke(info([line('a\u0301',100,400,{words:[{text:'a',startMs:100,endMs:200},{text:'\u0301',startMs:200,endMs:400}]})]),10);assert.equal(brokenCluster.lines[0].segments,null);
 assert.equal(invalid.lines[0].segments,null);assert.equal(invalid.lines[0].text,'Hello!');
 assert.equal(seekSeconds(3418,NaN,100),3.318);assert.equal(seekSeconds(-1,200),null);assert.equal(seekSeconds(2000,200,NaN),null);
});

test('lead owns focus, overlapping background retains its own times and gaps follow all voices chronologically',()=>{
 const doc=prepareKaraoke(info([
  line('lead',0,1000,{groupId:'a',words:words('lead',0,1000)}),
  line('late',9000,10000,{groupId:'a',role:'background',words:words('late',9000,10000)}),
  line('next',3000,4000,{groupId:'b',words:words('next',3000,4000)}),
  line('last',16000,17000,{groupId:'c',words:words('last',16000,17000)}),
 ]),24);
 assert.deepEqual(doc.groups[0].indices,[0,1]);assert.equal(doc.lines[1].background,true);
 assert.equal(karaokeFocus(doc,9500),2);
 const between=doc.gaps.find(g=>g.start===10000&&g.end===16000);assert.ok(between);assert.equal(between.before,2);
 assert.equal(doc.gaps.at(-1).kind,'outro');assert.equal(doc.gaps.at(-1).before,3);
 assert.ok(!doc.gaps.some(g=>g.start===1000&&g.end===16000));
});

test('unknown bounds are uncertainty barriers, intro/outro require proven bounds and instrumental is a valid document',()=>{
 const timed=line('voice',6000,7000,{words:words('voice',6000,7000)});
 assert.equal(prepareKaraoke(info([timed,line('unknown',null,null)]),20).gaps.length,0);
 assert.deepEqual(prepareKaraoke(info([timed]),0).gaps.map(g=>g.kind),['intro']);
 const unknownEnd=prepareKaraoke(info([line('unbounded',6000,null)]),20);
 assert.deepEqual(unknownEnd.gaps.map(g=>g.kind),['intro']);
 const instrumental=prepareKaraoke(info([],{instrumental:true}),20);assert.equal(instrumental.instrumental,true);assert.equal(instrumental.gaps.length,0);
});

test('controller rejects duplicate-video occurrence and account races and never loads an inactive panel',async()=>{
 const a=deferred(),b=deferred(),c=deferred(),requests=[a,b,c],calls=[];let current;
 const controller=new KaraokeController(async(command,args)=>{calls.push({command,args});return requests.shift().promise;},state=>current=state);
 controller.setContext(track,'account1:entryA',0,false);assert.equal(calls.length,0);
 controller.setContext(track,'account1:entryA',0,true);controller.setContext(track,'account1:entryB',0,true);
 b.resolve(info([line('B',3418,7000)]));await settle();a.resolve(info([line('A',0,1000)]));await settle();assert.equal(current.document.lines[0].text,'B');
 controller.setContext(track,'account2:entryB',0,true);assert.equal(current.document,null);
 controller.setContext(track,'account2:entryB',0,false);c.resolve(info([line('stale account',0,1000)]));await settle();assert.equal(current.document,null);controller.dispose();
});

test('refresh and provisional metadata preserve current document, forced retry passes through the real RPC contract',async()=>{
 const calls=[];let current;const waiting=deferred();
 const controller=new KaraokeController(async(_,args)=>{calls.push(args);if(calls.length===1)return info([line('valid',3418,7000)]);if(calls.length===2)return waiting.promise;throw {message:'offline'};},s=>current=s);
 controller.setContext(track,'entry',0,true);await settle();
 controller.setContext(track,'entry',180.4,true);assert.equal(current.refreshing,true);assert.equal(current.document.lines[0].text,'valid');
 waiting.reject(new Error('timeout'));await settle();assert.equal(current.document.lines[0].text,'valid');assert.ok(current.error);
 await controller.retry();assert.equal(calls.at(-1).forceRefresh,true);assert.deepEqual(calls.map(c=>c.duration),[null,180.4,180.4]);
 controller.setContext(track,'entry',180.41,true);assert.equal(calls.length,3);controller.dispose();
});

test('instrumental result is ready rather than absence',async()=>{
 let current;const c=new KaraokeController(async()=>info([],{instrumental:true}),s=>current=s);c.setContext(track,'x',2,true);await settle();assert.equal(current.status,'ready');assert.equal(current.document.instrumental,true);c.dispose();
});

test('bounded audio projection freezes stale samples without rewinding and stops while paused or seeking',()=>{
 let now=0;const clock=new KaraokeClock(()=>now);clock.observe(3.418,true,false,'entry:1');
 now=100;assert.equal(clock.sample(),3518);now=300;assert.equal(clock.sample(),3668);now=900;assert.equal(clock.sample(),3668);
 clock.observe(8,false,false,'entry:2');now=2000;assert.equal(clock.sample(),8000);
 clock.observe(12,true,true,'entry:3');now=2300;assert.equal(clock.sample(),12000);clock.dispose();
});


test('prepared gap lookup and boundary index retain short voices and scale to 5000 lines',()=>{
 const text=Array.from({length:10},(_,i)=>`voice${i}`).join(' ');
 const source=Array.from({length:5000},(_,i)=>line(text,i*12000+6000,i*12000+6500,{words:Array.from({length:10},(_,word)=>({text:`voice${word}`,startMs:i*12000+6000+word*20,endMs:i*12000+6020+word*20}))}));
 const doc=prepareKaraoke(info(source),60010);
 assert.equal(doc.lines.length,5000);assert.equal(doc.groups.length,5000);assert.equal(doc.lines.reduce((total,line)=>total+line.segments.length,0),50000);
 assert.ok(doc.boundaries.includes(6020));assert.equal(doc.gapsByBefore.get(0)[0].index,0);
 for(const [index,gap] of doc.gaps.entries()){
   assert.equal(karaokeGapIndex(doc,gap.start),index);assert.equal(karaokeGapIndex(doc,gap.end-.01),index);
   assert.notEqual(karaokeGapIndex(doc,gap.end),index);
   assert.ok(doc.gapsByBefore.get(gap.before).some(item=>item.index===index&&item.gap===gap));
 }
 assert.equal(karaokeGapIndex(doc,NaN),-1);
});

test('static viewport schedules real boundaries instead of polling every 16ms and stops at the projection horizon',()=>{
 const saved=Object.fromEntries(['document','setTimeout','clearTimeout','requestAnimationFrame','cancelAnimationFrame'].map(key=>[key,globalThis[key]]));
 let now=0,id=0;const scheduled=new Map();const frames=new Map();let calls=0;
 globalThis.document={hidden:false};globalThis.setTimeout=(fn,delay)=>{scheduled.set(++id,{fn,delay});return id;};globalThis.clearTimeout=id=>scheduled.delete(id);
 globalThis.requestAnimationFrame=fn=>{frames.set(++id,fn);return id;};globalThis.cancelAnimationFrame=id=>frames.delete(id);
 const clock=new KaraokeClock(()=>now);
 try{
  clock.setBoundaries([50,60,6000]);clock.observe(0,true,false,'entry');const stop=clock.subscribe(()=>{calls++;return false;});
  assert.equal(calls,1);assert.equal(scheduled.size,1);assert.equal([...scheduled.values()][0].delay,50);assert.equal(frames.size,0);
  let next=[...scheduled.values()][0];now=50;next.fn();assert.equal(calls,2);assert.equal([...scheduled.values()][0].delay,10);
  next=[...scheduled.values()][0];now=60;next.fn();assert.equal(calls,3);assert.equal(scheduled.size,0);
  clock.observe(5.9,true,false,'entry');assert.equal(Math.round([...scheduled.values()][0].delay),100);
  globalThis.document.hidden=true;clock.observe(6.1,true,false,'entry');assert.equal(scheduled.size,0);assert.equal(frames.size,0);
  globalThis.document.hidden=false;clock.observe(7,false,false,'entry');assert.equal(scheduled.size,0);
  clock.observe(7,true,true,'entry');assert.equal(scheduled.size,0);stop();
 }finally{clock.dispose();for(const [key,value] of Object.entries(saved)){if(value===undefined)delete globalThis[key];else globalThis[key]=value;}}
});


test('power saver bounds visible sweep callbacks to 30Hz even with a 120Hz animation source',()=>{
 const saved=Object.fromEntries(['document','requestAnimationFrame','cancelAnimationFrame'].map(key=>[key,globalThis[key]]));
 let now=0,id=0;const frames=new Map(),painted=[];
 globalThis.document={hidden:false};globalThis.requestAnimationFrame=fn=>{frames.set(++id,fn);return id;};globalThis.cancelAnimationFrame=id=>frames.delete(id);
 const clock=new KaraokeClock(()=>now);
 try{
   clock.setSlow(true);clock.observe(0,true,false,'entry');clock.subscribe(()=>{painted.push(now);return true;});
   for(let frame=1;frame<=24;frame++){
     now=frame*1000/120;const batch=[...frames.values()];frames.clear();for(const callback of batch)callback(now);
   }
   assert.ok(painted.length>3);assert.ok(painted.length<=7);
   for(let i=2;i<painted.length;i++)assert.ok(painted[i]-painted[i-1]>=1000/30-1e-8);
 }finally{clock.dispose();for(const [key,value] of Object.entries(saved)){if(value===undefined)delete globalThis[key];else globalThis[key]=value;}}
});
