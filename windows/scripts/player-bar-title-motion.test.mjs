import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
import {Window} from 'happy-dom';
const source=await readFile(new URL('../src/lib/player/title-motion.ts',import.meta.url),'utf8');
const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {titleMotion}=await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
function setup({width=150,full=450,reduced=false,foreground=true}={}){
 const dom=new Window();for(const key of ['document','HTMLElement','Node'])globalThis[key]=dom[key]??dom.document;globalThis.window=dom;globalThis.document=dom.document;
 document.hasFocus=()=>foreground;
 const media=new dom.EventTarget();media.matches=reduced;dom.matchMedia=()=>media;
 const observers=[];globalThis.ResizeObserver=class{constructor(fn){this.fn=fn;observers.push(this)}observe(){}disconnect(){this.disconnected=true}};
 globalThis.IntersectionObserver=class{constructor(fn){this.fn=fn;observers.push(this)}observe(){}disconnect(){this.disconnected=true}};
 const viewport=document.createElement('span');viewport.innerHTML='<span class="title-parts"><button>Guest</button></span>';document.body.append(viewport);const content=viewport.firstElementChild;
 Object.defineProperty(viewport,'clientWidth',{get:()=>width});Object.defineProperty(content,'scrollWidth',{get:()=>full});
 const animations=[];content.animate=(frames,options)=>{const animation={frames,options,currentTime:0,playState:'running',pause(){this.playState='paused'},play(){this.playState='running'},cancel(){this.playState='idle'}};animations.push(animation);return animation};
 const action=titleMotion(viewport,{enabled:true,key:'a'});
 return {dom,viewport,content,animations,observers,action,media,resize:w=>{width=w;observers[0].fn()}};
}
test('measured overflow uses initial hold, constant-speed travel and end hold',()=>{
 const f=setup();const a=f.animations[0];assert.equal(a.options.duration,14800);assert.equal(a.options.iterations,Infinity);assert.equal(a.frames[2].transform,'translateX(-300px)');assert.equal(a.frames[1].offset,1000/14800);assert.equal(a.frames[2].offset,13500/14800);f.action.destroy();
});
test('hover freezes the visible time and leaving resumes; a menu extends the pause',()=>{
 const f=setup();const a=f.animations[0];a.currentTime=2345;f.viewport.dispatchEvent(new f.dom.Event('mouseenter'));assert.equal(a.playState,'paused');assert.equal(a.currentTime,2345);
 f.action.update({enabled:true,key:'a',paused:true});f.viewport.dispatchEvent(new f.dom.Event('mouseleave'));assert.equal(a.playState,'paused');f.action.update({enabled:true,key:'a',paused:false});assert.equal(a.playState,'running');assert.equal(a.currentTime,2345);assert.equal(f.animations.length,1);f.action.destroy();
});
test('resize and title identity restart but equivalent updates retain animation',()=>{
 const f=setup();f.action.update({enabled:true,key:'a'});assert.equal(f.animations.length,1);f.resize(180);assert.equal(f.animations[0].playState,'idle');assert.equal(f.animations.length,2);f.action.update({enabled:true,key:'b'});assert.equal(f.animations.length,3);assert.equal(f.animations[2].currentTime,0);f.action.destroy();
});
test('short titles and Reduce Motion have no animation; changing preference cancels',()=>{
 const short=setup({full:150});assert.equal(short.animations.length,0);short.action.destroy();const reduced=setup({reduced:true});assert.equal(reduced.animations.length,0);reduced.action.destroy();const f=setup();f.media.matches=true;f.media.dispatchEvent(new f.dom.Event('change'));assert.equal(f.animations[0].playState,'idle');assert.equal(f.animations.length,1);f.action.destroy();
});
test('background/hidden surfaces pause without creating timers; teardown cancels and disconnects',()=>{
 const f=setup({foreground:false});const a=f.animations[0];assert.equal(a.playState,'paused');f.dom.dispatchEvent(new f.dom.Event('focus'));assert.equal(a.playState,'running');f.observers[1].fn([{isIntersecting:false}]);assert.equal(a.playState,'paused');f.observers[1].fn([{isIntersecting:true}]);assert.equal(a.playState,'running');
 f.dom.dispatchEvent(new f.dom.Event('blur'));assert.equal(a.playState,'paused');f.action.destroy();assert.equal(a.playState,'idle');assert.ok(f.observers.every(o=>o.disconnected));f.dom.dispatchEvent(new f.dom.Event('focus'));assert.equal(a.playState,'idle');
});
