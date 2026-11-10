// Run: node queue-recommendations.check.mjs /absolute/path/to/playwright/index.mjs
const { chromium } = await import(process.argv[2] || 'playwright');
import assert from 'node:assert/strict';
const browser=await chromium.launch({channel:'chrome',headless:true});
const page=await browser.newPage({viewport:{width:728,height:1000},colorScheme:'dark'});
const errors=[];page.on('pageerror',e=>errors.push(e.message));
let passed=0;const check=(name,fn)=>{fn();passed++;console.log('PASS '+name)};
const command=(a,p)=>page.evaluate(([a,p])=>window.queueDemo.dispatch(a,p),[a,p]);
const state=()=>page.evaluate(()=>window.queueDemo.getState());
const tracks=s=>s.pending.map(x=>x.track);
const unique=s=>{const ids=[s.current,...s.pending,...s.recs,...s.history].filter(Boolean).map(x=>x.id);assert.equal(new Set(ids).size,ids.length)};
try{
await page.goto(new URL('./queue-recommendations.html',import.meta.url).href);
let s=await state();check('playlist starts with two pending and separate reserve',()=>{assert.deepEqual(tracks(s),['b','c']);assert.equal(s.recs.length,3);unique(s)});
const first=s.recs[0].id,last=s.recs[1].id;
await page.locator('#recommendations button[data-action="enqueueNext"]').first().click();
s=await command('enqueueEnd',last);check('next and end yield X B C Y before recommendations',()=>{assert.deepEqual(tracks(s),['r1','b','c','r2']);assert.equal(s.recs[0].track,'r3');unique(s)});
let heard=[];for(let i=0;i<5;i++){s=await command('next');heard.push(s.current.track);unique(s)}check('play order after A is X B C Y R3',()=>assert.deepEqual(heard,['r1','b','c','r2','r3']));
s=await command('scenario','radio');const r2=s.recs[0].id,r3=s.recs[1].id;await command('enqueueNext',r2);s=await command('enqueueEnd',r3);check('radio manual selections lead reserve',()=>{assert.deepEqual(tracks(s),['r2','r3']);assert.deepEqual(s.recs.map(x=>x.track),['b']);unique(s)});
await command('scenario','radio');s=await command('next');check('radio promotes exactly one recommendation',()=>{assert.equal(s.current.track,'r2');assert.equal(s.recs.length,2);assert.equal(s.pending.length,0);assert.equal(s.history.length,1);unique(s)});
s=await command('previous');check('previous follows real playback',()=>{assert.equal(s.current.track,'r1');assert.deepEqual(tracks(s),['r2']);unique(s)});
s=await command('scenario','playlist');s=await command('play',s.recs[1].id);check('play recommendation preserves chosen pending',()=>{assert.equal(s.current.track,'r2');assert.deepEqual(tracks(s),['b','c']);assert.equal(s.current.origin,'manual');assert.equal(s.recs.length,2);assert.equal(s.recs[0].track,'r1');unique(s)});
s=await command('scenario','playlist');const old=s.recs[0].id;s=await command('enqueueNext',old);check('choosing a recommendation creates manual occurrence',()=>{assert.notEqual(s.pending[0].id,old);assert.equal(s.pending[0].origin,'manual');unique(s)});
s=await command('enqueueEnd',s.current.id);s=await command('enqueueEnd',s.current.id);check('intentional duplicates retain distinct identities',()=>{assert.equal(tracks(s).filter(t=>t==='a').length,2);unique(s)});
s=await command('scenario','playlist');const original=tracks(s);s=await command('shuffle');check('shuffle changes source order',()=>assert.notDeepEqual(tracks(s),original));s=await command('shuffle');check('shuffle off restores source',()=>assert.deepEqual(tracks(s),original));
await command('repeat');s=await state();const current=s.current.id;s=await command('eof');check('repeat EOF retains current',()=>assert.equal(s.current.id,current));s=await command('next');check('repeat manual next advances',()=>assert.equal(s.current.track,'b'));
await command('next');s=await command('next');check('repeat manual wrap does not duplicate identities',()=>unique(s));
s=await command('scenario','playlist');const proposal=s.recs[0];s=await command('like',proposal.id);check('like does not enqueue',()=>{assert.equal(s.pending.length,2);assert.equal(s.recs.length,3);assert.ok(s.likes.includes(proposal.track))});s=await command('like',proposal.id);check('like toggles off',()=>assert.ok(!s.likes.includes(proposal.track)));
s=await command('remove',proposal.id);check('remove recommendation does not dislike',()=>{assert.equal(s.recs.length,2);assert.equal(s.dislikes.length,0)});
s=await command('scenario','playlist');const bid=s.pending[0].id,cid=s.pending[1].id;await command('move',{id:cid,before:bid});s=await state();check('manual reorder by occurrence',()=>assert.deepEqual(tracks(s),['c','b']));
await page.locator('#pending .song').first().focus();await page.keyboard.press('Shift+F10');const menuVisible=await page.locator('#menu').isVisible();check('keyboard opens actual contextual actions',()=>assert.equal(menuVisible,true));await page.locator('#menu button[data-action="moveToEnd"]').first().click();s=await state();check('context menu moves chosen song to end',()=>assert.deepEqual(tracks(s),['b','c']));
await command('scenario','playlist');await page.locator('#recommendations button[data-action="enqueueNext"]').first().focus();await page.keyboard.press('Enter');
let active=await page.evaluate(()=>({id:document.activeElement.dataset.entry,action:document.activeElement.dataset.action,state:window.queueDemo.getState()}));check('keyboard focus follows recommendation into queue',()=>{assert.equal(active.id,active.state.pending[0].id);assert.equal(active.action,'play')});
await page.locator('#recommendations .song').first().focus();await page.keyboard.press('Shift+F10');await page.locator('#menu button[data-action="remove"]').click();active=await page.evaluate(()=>({id:document.activeElement.dataset.entry,state:window.queueDemo.getState()}));check('focus after removal goes to surviving neighbor',()=>assert.equal(active.id,active.state.recs[0].id));
await page.locator('#pending .song').first().focus();const movingID=await page.locator('#pending .row').first().getAttribute('data-entry');await page.keyboard.press('Alt+ArrowDown');const focusedID=await page.evaluate(()=>document.activeElement.dataset.entry);check('keyboard reorder retains occurrence focus',()=>assert.equal(focusedID,movingID));
await command('scenario','playlist');await page.locator('#recommendations .row').first().dragTo(page.locator('#pending .row').first());s=await state();check('drag recommendation to chosen queue promotes at target',()=>{assert.deepEqual(tracks(s),['r1','b','c']);assert.equal(s.recs.length,2);assert.equal(s.pending[0].origin,'manual');unique(s)});
s=await command('scenario','playlist');const copyID=s.pending[0].id;s=await command('enqueueNext',copyID);check('play next on chosen song creates another occurrence',()=>{assert.deepEqual(tracks(s),['b','b','c']);assert.notEqual(s.pending[0].id,copyID);unique(s)});
s=await command('moveToEnd',copyID);check('move command repositions existing occurrence without copy',()=>{assert.deepEqual(tracks(s),['b','c','b']);assert.equal(s.pending.filter(x=>x.id===copyID).length,1);unique(s)});
s=await command('scenario','radio');await command('next');await command('repeat');s=await state();const excluded=s.current.id;s=await command('dislike',excluded);check('dislike current promotes reserve instead of repeating previous',()=>{assert.equal(s.current.track,'r3');assert.equal(s.recs.length,1);assert.ok(!s.history.some(x=>x.id===excluded));unique(s)});
const note=await page.locator('#recommendations-note').textContent();check('repeat explains why automatic recommendations wait',()=>assert.match(note,/Desactivá repetir/));
s=await command('scenario','radio');for(const rec of s.recs)await command('remove',rec.id);s=await command('remove',s.current.id);check('remove final current stops without replaying history',()=>{assert.equal(s.current,null);assert.equal(s.paused,true);unique(s)});
s=await command('scenario','playlist');const pinned=s.pending[0].id;await command('moveToEnd',pinned);await command('shuffle');s=await command('shuffle');check('shuffle off preserves manually moved collection occurrence',()=>{assert.deepEqual(tracks(s),['c','b']);assert.equal(s.pending[1].id,pinned);unique(s)});
for(const width of [728,480,390,320]){await page.setViewportSize({width,height:1100});await command('scenario','playlist');const bounds=await page.evaluate(()=>{const root=document.getElementById('queue-proposal');const b=root.getBoundingClientRect();return{scroll:document.documentElement.scrollWidth,width:innerWidth,right:b.right,bottom:b.bottom}});check('layout fits '+width+'px',()=>{assert.ok(bounds.scroll<=width,JSON.stringify(bounds));assert.ok(bounds.right<=width+1)})}
check('no runtime errors',()=>assert.deepEqual(errors,[]));console.log('TOTAL '+passed+' passed');
}finally{await browser.close()}
