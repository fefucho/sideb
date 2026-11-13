import { resolveContentRatingImport } from './helpers/content-rating-module.mjs';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
async function module(file,replace=source=>source){const source=replace(await readFile(new URL(`../src/lib/search/${file}.ts`,import.meta.url),'utf8'));return `data:text/javascript;base64,${Buffer.from(resolveContentRatingImport(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText)).toString('base64')}`;}
const rowsUrl=await module('provider-rows');
const songsUrl=await module('songs');
const categoriesUrl=await module('categories',s=>s.replace("from './provider-rows'",`from '${rowsUrl}'`).replace("from './songs'",`from '${songsUrl}'`));
const {categoryPage,fetchTargets,emptyCategoryInput,categoryOfCard,chipKindOfTitle,gridColumns,GRID_HEIGHT}=await import(categoriesUrl);
const {quickPresentation,localKeyOf}=await import(await module('quickPresentation',s=>s.replace("from './categories'",`from '${categoriesUrl}'`).replace("from './provider-rows'",`from '${rowsUrl}'`)));

const card=(kind,id,title=`T ${id}`,subtitle=`S ${id}`)=>({kind,id,title,subtitle,thumbnail:null,duration:null});
const song=(id,artists='A',extra={})=>({videoId:id,title:`T-${id}`,artists,album:null,duration:'3:00',thumbnail:null,isVideo:false,artistId:null,albumId:null,...extra});
const section=(id,{title='',layout='list',items=[],songs=[],primary=null,related=[]}={})=>({id,title,layout,items,songs,primaryItemIndex:primary,relatedItemIndices:related,moreQuery:null,moreParams:null,moreBrowseId:null,actions:[]});
const chips=titles=>titles.map(title=>({id:title,title,params:`params-${title}`,selected:false}));
const titles={recents:'Recent',queries:'Searches',top:'Top',category:c=>c};
const kendrick=()=>({chips:chips(['Songs','Artists','Videos','Albums','Community playlists','Profiles','Featured playlists','Podcasts']),correction:null,continuation:'more',sections:[
 section('top',{layout:'top',items:[card('artist','UCk','Kendrick Lamar','Artist • 132M'),card('song','s0','N95')],songs:[song('s0','')],primary:0,related:[1]}),
 section('listen',{title:'Listen again',items:[card('song','s1','Money Trees'),card('song','s2','DNA.')],songs:[song('s1'),song('s2')]}),
 section('mixed',{items:[card('artist','UC1','Travis Scott','Artist • 95M'),card('album','MPRE1','GNX','Album • Kendrick Lamar'),card('album','MPRE2','DAMN.','Album • Kendrick Lamar'),
  card('artist','UC2','Ukoon$','Profile • @Patee67'),card('playlist','VL1','Super Bowl Set','Playlist • x'),card('playlist','MPSP1','AllHitsPodcast','Podcast')]}),
]});

test('classification: profiles are not artists, podcasts are not playlists, a video sent as a song is a video',()=>{
 assert.equal(categoryOfCard(card('artist','a','x','Profile • @x')),'profiles');
 assert.equal(categoryOfCard(card('playlist','p','x','Podcast')),'podcasts');
 assert.equal(categoryOfCard(card('song','v'),song('v','A',{isVideo:true})),'videos');
 assert.equal(categoryOfCard(card('song','s'),song('s')),'songs');
 assert.equal(chipKindOfTitle(' Community Playlists '),'communityPlaylists');
});

test('the mixed list is grouped by type, the principal stays first and personalized shelves are dropped',()=>{
 const result=categoryPage(kendrick(),emptyCategoryInput(),c=>c);
 assert.deepEqual(result.sections.map(s=>s.id),['top','category:artists','category:albums','category:playlists','category:profiles','category:podcasts']);
 assert.equal(result.sections[0].primaryItemIndex,0);
 assert.equal(result.continuation,null);
 assert.deepEqual(result.sections[1].items.map(c=>c.title),['Travis Scott']);
 assert.deepEqual(result.sections[4].items.map(c=>c.title),['Ukoon$']);
 assert.deepEqual(result.sections[5].items.map(c=>c.title),['AllHitsPodcast']);
 assert.ok(!result.sections.flatMap(s=>s.items).some(c=>c.title==='Money Trees'),'«Listen again» is not a result');
 assert.equal(result.sections[1].layout,'category-carousel');
});

test('section order follows the provider chips and pending categories get a placeholder',()=>{
 const result=categoryPage(kendrick(),{chipPages:{},pending:['songs']},c=>c);
 assert.deepEqual(result.sections.map(s=>s.id).slice(0,3),['top','category:songs','category:artists']);
 assert.equal(result.sections[1].layout,'category-loading');
 assert.equal(result.sections[1].items.length,0);
});

test('a fetched category replaces its mixed items and keeps occurrence payloads for repeated ids',()=>{
 const songsPage={chips:[],correction:null,continuation:null,sections:[section('s',{title:'Songs',items:[card('song','same','First'),card('song','same','Second')],songs:[song('same','A',{setVideoId:'one'}),song('same','A',{setVideoId:'two'})]})]};
 const result=categoryPage(kendrick(),{chipPages:{songs:songsPage},pending:[]},c=>c);
 const songs=result.sections.find(s=>s.id==='category:songs');
 assert.equal(songs.layout,'category-grid');
 assert.deepEqual(songs.items.map(c=>c.title),['First','Second']);
 assert.deepEqual(songs.songs.map(s=>s.setVideoId),['one','two']);
 assert.equal(songs.moreParams,'params-Songs','the heading action is the chip search');
});

test('featured and community playlists merge without duplicates',()=>{
 const pages=ids=>({chips:[],correction:null,continuation:null,sections:[section('p',{items:ids.map(id=>card('playlist',id,`PL ${id}`,'Playlist • x'))})]});
 const result=categoryPage(kendrick(),{chipPages:{featuredPlaylists:pages(['a','b']),communityPlaylists:pages(['b','c'])},pending:[]},c=>c);
 assert.deepEqual(result.sections.find(s=>s.id==='category:playlists').items.map(c=>c.id),['b','c','a']);
});

test('chip requests: the core categories plus those already present, in provider order, videos only when shown',()=>{
 const targets=fetchTargets(kendrick(),true);
 assert.deepEqual(targets.map(t=>t.kind),['songs','artists','videos','albums','communityPlaylists','profiles','featuredPlaylists','podcasts']);
 assert.equal(targets[0].params,'params-Songs');
 assert.ok(!fetchTargets(kendrick(),false).some(t=>t.kind==='videos'));
});

test('the grid always has three rows; only the number of columns follows the width',()=>{
 assert.equal(gridColumns(1098),3);assert.equal(gridColumns(618),2);assert.equal(gridColumns(400),1);
 assert.equal(GRID_HEIGHT,3*58+8);
});

// ---- quick search presentation (FIX-333/336 parity) ----
const history=(id,text)=>({id,kind:'history',query:text,runs:[{text,bold:false}],feedbackToken:'t',card:null,song:null});
const completion=(id,text)=>({id,kind:'text',query:text,runs:[{text,bold:false}],feedbackToken:null,card:null,song:null});
const media=(id,c,s=null)=>({id,kind:'media',query:null,runs:[],feedbackToken:null,card:c,song:s});
const localOf=(key,c)=>({id:`local:${key}`,kind:'history',query:null,runs:[],feedbackToken:null,card:c,song:null});

test('empty field: local recents first, then the provider history without duplicates, capped',()=>{
 const local=[localOf('entity:album:b1',card('album','b1')),localOf('entity:artist:a1',card('artist','a1')),{id:'local:query:adhd',kind:'history',query:'adhd',runs:[],feedbackToken:null,card:null,song:null}];
 const result=quickPresentation({draft:'  ',local,remote:[history('r-adhd','ADHD'),history('r-drake','drake'),media('r-a1',card('artist','a1')),media('r-album',card('album','x'))],titles});
 assert.deepEqual(result.sections.map(s=>s.id),['recents']);
 assert.deepEqual(result.entries.map(e=>e.id),['local:entity:album:b1','local:entity:artist:a1','local:query:adhd','r-drake','r-album']);
 assert.equal(localKeyOf(result.entries[0]),'entity:album:b1');
 assert.equal(localKeyOf(result.entries[3]),null);
 const many=Array.from({length:12},(_,i)=>localOf(`k${i}`,card('artist',`a${i}`)));
 assert.equal(quickPresentation({draft:'',local:many,remote:Array.from({length:5},(_,i)=>history(`r${i}`,`q${i}`)),titles}).entries.length,10);
 assert.deepEqual(quickPresentation({draft:'',local:[],remote:[],titles}).sections,[]);
});

test('typing without a full search yet: top result, groups, then only completions (history is dropped)',()=>{
 const remote=[media('top',card('song','s1')),completion('q1','kend'),media('a1',card('artist','a1')),media('s2',card('song','s2')),media('s3',card('song','s3')),media('s4',card('song','s4')),media('s5',card('song','s5')),media('s6',card('song','s6')),
  media('b1',card('album','b1')),history('h1','kendrick lamar'),completion('q2','kendrick h'),completion('q3','kendrick l'),completion('q4','kendrick x')];
 const result=quickPresentation({draft:'kend',local:[],remote,page:null,titles});
 assert.deepEqual(result.sections.map(s=>s.id),['top','group:artists','group:songs','group:albums','queries']);
 assert.deepEqual(result.sections[2].entries.map(e=>e.id),['s2','s3','s4','s5'],'four songs; the top result is not repeated');
 assert.deepEqual(result.sections[4].entries.map(e=>e.id),['q1','q2','q3']);
 assert.ok(!result.entries.some(e=>e.id==='h1'),'own history is for the empty field');
 assert.deepEqual(quickPresentation({draft:'kend',local:[],remote:[],titles}).sections,[]);
});

test('a full search fills the top result and several songs, artists and albums; the principal artist is inherited',()=>{
 const result=quickPresentation({draft:'kanye',local:[],remote:[media('top',card('artist','UCk')),completion('c1','kanye west'),history('h1','kanye west runaway')],page:kendrick(),titles});
 assert.deepEqual(result.sections.map(s=>s.id),['top','group:songs','group:artists','group:albums','group:playlists','queries']);
 assert.equal(result.sections[0].entries[0].card.title,'Kendrick Lamar');
 assert.deepEqual(result.sections[1].entries.map(e=>e.song?.videoId),['s0'],'the principal\'s related songs');
 assert.equal(result.sections[1].entries[0].song.artists,'Kendrick Lamar','a row without artist under an artist card is that artist\'s');
 assert.deepEqual(result.sections[2].entries.map(e=>e.card.title),['Travis Scott']);
 assert.ok(!result.entries.some(e=>e.card?.title==='Money Trees'),'«Listen again» is not a result');
 assert.deepEqual(result.sections.at(-1).entries.map(e=>e.id),['c1'],'completions only');
});

test('hidden videos are not shown, not even from the full search',()=>{
 const page=kendrick();
 page.sections[0].items[1]=card('video','s0','A video');page.sections[0].songs[0]=song('s0','',{isVideo:true});
 const result=quickPresentation({draft:'kanye',local:[],remote:[],page,showVideos:false,titles});
 assert.ok(!result.entries.some(e=>e.song?.videoId==='s0'||e.card?.kind==='video'));
});
