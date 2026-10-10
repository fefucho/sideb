import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import ts from 'typescript';
const compile=source=>ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const url=source=>`data:text/javascript;base64,${Buffer.from(compile(source)).toString('base64')}`;
const ambient=url(await readFile(new URL('../src/lib/home/ambient.ts',import.meta.url),'utf8'));
const {annotationPalette,annotationTint,annotationText}=await import(url((await readFile(new URL('../src/lib/genius/highlight.ts',import.meta.url),'utf8')).replace("'../home/ambient'",JSON.stringify(ambient))));
const pixels=rgb=>Array.from({length:32*32},()=>[...rgb,255]).flat();
test('artwork colors follow a cover and contrast changes hue without using fixed red',()=>{
  const blue=annotationPalette(pixels([35,80,210])),green=annotationPalette(pixels([50,180,80]));
  assert.notDeepEqual(blue.artwork,green.artwork);assert.notDeepEqual(blue.artwork,blue.contrast);
  assert.equal(annotationTint(blue,'artwork'),blue.artwork.join(' '));
  assert.equal(annotationTint(blue,'contrast'),blue.contrast.join(' '));
  assert.equal(annotationTint(blue,'neutral'),'255 255 255');
});
test('missing/transparent/black/white cover yields a stable neutral fallback',()=>{
  const fallback=annotationPalette();
  for(const input of [[],pixels([0,0,0]),pixels([255,255,255]),Array(4096).fill(0)])assert.deepEqual(annotationPalette(input),fallback);
});
test('active cover, neutral and missing-cover tints preserve lyric text contrast on the dark playback background',()=>{
  const luminance=rgb=>{const [r,g,b]=rgb.map(v=>{const s=v/255;return s<=.04045?s/12.92:((s+.055)/1.055)**2.4;});return .2126*r+.7152*g+.0722*b;};
  for(const input of [[],...[[240,240,15],[230,30,30],[20,220,30],[20,30,240],[220,30,210]].map(pixels)])for(const mode of ['artwork','contrast','neutral']){
    const tint=annotationTint(annotationPalette(input),mode,true).split(' ').map(Number);
    const composite=tint.map(v=>v*.48+48*.52);assert.ok((luminance([244,244,245])+.05)/(luminance(composite)+.05)>=4.5);
  }
});
test('unpainted whitespace keeps exact lyric text including accents, HTML-looking text and NBSP',()=>{
  for(const value of ['  Línea con acentos  ','\t<verse> & texto\u00a0','\n\t  ','sin espacios','A\nB']){
    const {before,text,after}=annotationText(value);assert.equal(before+text+after,value);assert.equal(text.trim(),text);
  }
});
