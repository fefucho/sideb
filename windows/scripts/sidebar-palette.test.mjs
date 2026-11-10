import assert from 'node:assert/strict';
import {test} from 'node:test';
import path from 'node:path';
import {mountedSvelteEnvironment} from './helpers/mount-svelte.mjs';
const {root,moduleFor}=await mountedSvelteEnvironment('sidebar-palette');
const P=await import(await moduleFor(path.join(root,'src/lib/player/sidebarPalette.ts')));
const side=24;
const fill=(rowColor)=>{const out=[];for(let row=0;row<side;row++)for(let col=0;col<side;col++)out.push(...rowColor(row));return out;};
const uniform=c=>fill(()=>c);
const chroma=c=>Math.max(c.red,c.green,c.blue)-Math.min(c.red,c.green,c.blue);
const luminance=c=>{const l=v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4;return .2126*l(c.red)+.7152*l(c.green)+.0722*l(c.blue);};

test('top and bottom bands give a red→blue vertical gradient',()=>{
 const palette=P.paletteFromRgba(fill(row=>row<5?[220,20,20,255]:row>=19?[20,20,220,255]:[40,40,40,255]),side);
 assert.ok(palette.isChromatic);
 assert.ok(palette.primary.red>palette.primary.blue+.08&&palette.primary.red>palette.primary.green+.08);
 assert.ok(palette.secondary.blue>palette.secondary.red+.04&&palette.secondary.blue>palette.secondary.green+.04);
});
test('a uniform cover equals the whole-cover palette; a transparent band falls back to it',()=>{
 const pixels=uniform([220,100,30,255]);
 const bands=P.paletteFromRgba(pixels,side),global=P.paletteFromTints(P.tintsFromRgba(pixels));
 assert.equal(bands.isChromatic,global.isChromatic);
 for(const key of ['primary','secondary'])for(const c of ['red','green','blue'])assert.ok(Math.abs(bands[key][c]-global[key][c])<.001);
 const green=P.paletteFromRgba(fill(row=>row<5?[0,0,0,0]:[34,188,92,255]),side);
 assert.ok(green.isChromatic&&green.primary.green>green.primary.red&&green.primary.green>green.primary.blue);
 assert.ok(green.secondary.green>green.secondary.red&&green.secondary.green>green.secondary.blue);
});
test('empty, invalid, transparent or mismatched buffers are neutral charcoal without blue bias',()=>{
 for(const input of [[],[120,50,20],[0,0]])assert.deepEqual(P.paletteFromRgba(input),P.neutralSidebarPalette);
 assert.deepEqual(P.paletteFromRgba(Array.from({length:64},()=>[100,100,100,0]).flat()),P.neutralSidebarPalette);
 assert.deepEqual(P.paletteFromRgba([120,50,20,255],24),P.neutralSidebarPalette);
 const n=P.neutralSidebarPalette;assert.ok(n.primary.red===n.primary.blue&&n.secondary.red===n.secondary.blue);
});
test('monochrome artwork stays achromatic',()=>{
 const mono=P.paletteFromRgba(fill(row=>{const s=60+row*4;return [s,s,s,255];}),side);
 assert.ok(!mono.isChromatic);
 for(const key of ['primary','secondary']){assert.ok(Math.abs(mono[key].red-mono[key].blue)<1e-4&&Math.abs(mono[key].red-mono[key].green)<1e-4);}
});
test('white controls stay legible: luminance is clamped for extreme bright covers',()=>{
 const palette=P.paletteFromRgba(fill(row=>row<5?[255,255,0,255]:row>=19?[0,255,255,255]:[255,255,255,255]),side);
 assert.ok(palette.isChromatic);
 assert.ok(luminance(palette.primary)<=.1101&&luminance(palette.secondary)<=.0651);
 assert.ok((1.05)/(luminance(palette.primary)+.05)>6&&(1.05)/(luminance(palette.secondary)+.05)>6);
 for(const surface of [P.sidebarTopSurface(palette),P.sidebarBottomSurface(palette)])assert.ok(luminance(surface)<=.1151);
});
test('yellow stays warm amber instead of olive; muted earthy covers keep a gentle saturation',()=>{
 const yellow=P.paletteFromRgba(uniform([235,200,40,255]),side);
 assert.ok(yellow.isChromatic&&yellow.primary.red>yellow.primary.green&&yellow.secondary.red>yellow.secondary.green&&yellow.primary.green>yellow.primary.blue);
 const beige=P.paletteFromRgba(uniform([200,184,153,255]),side);
 assert.ok(beige.isChromatic&&chroma(beige.primary)<.20&&chroma(beige.primary)>=.05);
});
test('sidebar surface is a vertical gradient (top→bottom) over the #121214 base and relaxes under reduced transparency/contrast',()=>{
 const palette=P.paletteFromRgba(fill(row=>row<12?[200,60,40,255]:[30,60,200,255]),side);
 const css=P.sidebarPaletteCss(palette);
 assert.match(css.background,/^linear-gradient\(180deg, rgb\(\d+ \d+ \d+\), rgb\(\d+ \d+ \d+\)\), rgb\(18 18 20\)$/);
 assert.notEqual(css.top,css.bottom,'top and bottom are distinct, not one flat block');
 const calm=P.sidebarPaletteCss(palette,{reduceTransparency:true});assert.notEqual(calm.top,css.top);
 assert.equal(P.rgbCss({red:1.4,green:-.2,blue:.5}),'rgb(255 0 128)');assert.equal(P.rgbCss({red:.5,green:.5,blue:.5},.28),'rgb(128 128 128 / 0.28)');
});
test('palette controller: a newer cover supersedes a slower older one and an unreadable cover resets to neutral',async()=>{
 const published=[];const waits=new Map();
 const controller=new P.SidebarPaletteController(p=>published.push(p),url=>new Promise(resolve=>waits.set(url,resolve)));
 const first=controller.update('a'),second=controller.update('b');
 waits.get('b')(uniform([20,80,220,255]));await second;waits.get('a')(uniform([220,20,20,255]));await first;
 assert.equal(published.length,1);assert.ok(published[0].primary.blue>published[0].primary.red,'late A cannot overwrite B');
 const third=controller.update('c');waits.get('c')(null);await third;assert.deepEqual(published.at(-1),P.neutralSidebarPalette);
 await controller.update(null);assert.deepEqual(published.at(-1),P.neutralSidebarPalette);
 const again=controller.update('b');await again;assert.equal(published.at(-1).primary.blue>published.at(-1).primary.red,true,'cached cover resolves without loading');
 controller.dispose();
});
