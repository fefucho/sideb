import { resolveContentRatingImport } from './helpers/content-rating-module.mjs';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
async function module(file){const source=await readFile(new URL(`../src/lib/search/${file}.ts`,import.meta.url),'utf8');return `data:text/javascript;base64,${Buffer.from(resolveContentRatingImport(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText)).toString('base64')}`;}
const {projectSearchSection,searchSectionRows,inheritingArtist}=await import(await module('provider-rows'));
const card=(kind,id,title)=>({kind,id,title,subtitle:null,thumbnail:null,duration:null});
const song=(id,artists='',runs)=>({videoId:id,title:`T-${id}`,artists,artistRuns:runs,album:null,duration:'3:00',thumbnail:null,isVideo:false,artistId:null,albumId:null});
const top=(primary,songs)=>({id:'top',title:'',layout:'top',items:[primary,card('song','a','No artist'),card('song','b','Own artist')],songs,primaryItemIndex:0,relatedItemIndices:[1,2],moreQuery:null,moreParams:null,moreBrowseId:null,actions:[]});

// YouTube drops the artist from the rows under an artist's top result; the UI must not leave them blank.
test('songs under an artist top result inherit that artist, with its link', ()=>{
 const projection=projectSearchSection(top(card('artist','UCk','Kanye West'),[song('a'),song('b','Someone Else')]));
 const [inherited,own]=projection.related;
 assert.equal(inherited.song.artists,'Kanye West');
 assert.equal(inherited.song.artistId,'UCk');
 assert.deepEqual(inherited.song.artistRuns,[{text:'Kanye West',id:'UCk'}]);
 assert.equal(own.song.artists,'Someone Else','a row that names its artist keeps it');
});

test('only an artist card implies the artist; a song principal inherits nothing', ()=>{
 const projection=projectSearchSection(top(card('song','p','A song'),[song('a'),song('b','Someone Else')]));
 assert.equal(projection.related[0].song.artists,'');
});

test('credits given as runs are not overwritten and unpaired payloads are completed too', ()=>{
 const section=top(card('artist','UCk','Kanye West'),[song('a','',[{text:'Pusha T',id:'UCp'}])]);
 section.songs.push(song('orphan'));
 const rows=searchSectionRows(section);
 assert.equal(rows.find(row=>row.song?.videoId==='a').song.artists,'','explicit runs mean the row names its artists');
 assert.equal(rows.find(row=>row.song?.videoId==='orphan').song.artists,'Kanye West');
});

test('the helper leaves the song object alone when there is nothing to inherit', ()=>{
 const named=song('x','Named');
 assert.equal(inheritingArtist(named,{name:'Other',id:'u'}),named);
 assert.equal(inheritingArtist(song('y'),null).artists,'');
});
