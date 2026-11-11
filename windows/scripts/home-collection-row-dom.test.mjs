import assert from 'node:assert/strict';import {test} from 'node:test';import {spawnSync} from 'node:child_process';import {fileURLToPath} from 'node:url';import path from 'node:path';
if(!process.execArgv.includes('--conditions=browser')){
 test('Home collection row mounts panel cards with finish, actions, detail requests and anchor',()=>{const {NODE_TEST_CONTEXT,...env}=process.env;const r=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});assert.equal(r.status,0,r.stdout+r.stderr)});
}else{
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('home-collection-row-dom');
 globalThis.IntersectionObserver=class{observe(){}unobserve(){}disconnect(){}};
 Object.defineProperty(globalThis,'ResizeObserver',{configurable:true,value:class{constructor(fn){this.fn=fn}observe(){}unobserve(){}disconnect(){}}});
 Object.defineProperty(dom.HTMLElement.prototype,'clientWidth',{configurable:true,get(){return globalThis.__clientWidth??1056}});
 Object.defineProperty(dom.HTMLElement.prototype,'scrollWidth',{configurable:true,get(){return 6000}});
 const calls=[],visible=[],anchors=[];globalThis.__row={calls,visible,anchors};
 const source=`<script>
  import {setContext} from 'svelte';
  import {MENU_CONTEXT} from '$lib/menu/types';
  import HomeCollectionRow from '$lib/components/home/HomeCollectionRow.svelte';
  let panelStyle=$state('tinted'),cardWidth=$state(232),count=$state(4),anchor=$state(0),collections=$state(globalThis.__albums());
  const metadata={'album|a0':{title:'Meta Title',artists:'Meta Artist',artistId:'UCmeta',summary:'Álbum • 2020'}};
  setContext(MENU_CONTEXT,{open:(_event,target)=>globalThis.__row.calls.push(['menu',target.kind])});
  globalThis.__harness={style:v=>panelStyle=v,width:(w,c)=>{cardWidth=w;count=c},anchor:()=>anchor,setAnchor:v=>anchor=v,list:v=>collections=v};
 </script><HomeCollectionRow {collections} {metadata} label="Álbumes" session="s1" {panelStyle} {cardWidth} {count} {anchor}
  onAnchor={i=>{anchor=i;globalThis.__row.anchors.push(i)}} onVisible={items=>globalThis.__row.visible.push(items.map(i=>i.id))}
  onOpen={item=>globalThis.__row.calls.push(['open',item.id])} onOpenArtist={id=>globalThis.__row.calls.push(['artist',id])} />`;
 globalThis.__albums=()=>Array.from({length:12},(_,i)=>({kind:'album',id:`a${i}`,title:`Album ${i}`,subtitle:`Álbum • Artist ${i} • 2020`,thumbnail:`https://lh3.googleusercontent.com/cover${i}=w544-h544`,duration:null,artists:`Artist ${i}`,albumId:null,artistId:`UC${i}`,album:null,artistRuns:[{id:`UC${i}`,text:`Artist ${i}`}],explicit:false}));
 const Harness=(await import(await moduleFor(path.join(root,'src/lib/components/home/RowHarness.svelte'),source))).default;
 const settle=async()=>{flushSync();await tick();await new Promise(r=>setTimeout(r,45));flushSync();await tick()};
 test('panel cards, finishes, actions, detail requests and anchor',async()=>{
  const target=document.createElement('div');document.body.append(target);let app;flushSync(()=>app=mount(Harness,{target}));await settle();
  const scroller=target.querySelector('[data-horizontal-scroll]');
  assert.equal(scroller.getAttribute('role'),'region');assert.equal(scroller.getAttribute('aria-label'),'Álbumes');assert.equal(scroller.getAttribute('tabindex'),'0');
  const cards=[...target.querySelectorAll('.item article.media-card.panel')];assert.equal(cards.length,12,'every collection is a panel card');
  assert.ok(target.querySelector('.item').getAttribute('style').includes('232px'));
  const first=cards[0];
  assert.ok(first.querySelector('.badge').textContent.trim().length>0,'type label');
  assert.equal(first.querySelector('h3').textContent.trim(),'Meta Title');assert.match(first.querySelector('.credits').textContent,/Meta Artist/);assert.match(first.querySelector('.summary').textContent,/\S/);
  assert.match(cards[1].querySelector('h3').textContent,/Album 1/);assert.match(cards[1].querySelector('.credits').textContent,/Artist 1/);
  // Acabado: tinted pinta la carátula pequeña detrás; white no.
  assert.ok(first.classList.contains('tinted'));const wash=first.querySelector('.wash');assert.ok(wash,'tinted draws the wash');assert.equal(wash.getAttribute('aria-hidden'),'true');assert.match(wash.getAttribute('style'),/cover0=w32-h32/);
  globalThis.__harness.style('white');await settle();
  assert.ok(!target.querySelector('.panel.tinted')&&!target.querySelector('.wash'),'white has neither the class nor the wash');
  globalThis.__harness.style('tinted');await settle();assert.ok(target.querySelector('.wash'));
  // Acciones.
  first.querySelector('button.primary').click();assert.deepEqual(calls.at(-1),['open','a0']);
  const art=first.querySelector('.credits button');art.click();assert.deepEqual(calls.at(-1),['artist','UCmeta']);
  first.dispatchEvent(new dom.MouseEvent('contextmenu',{bubbles:true,cancelable:true}));assert.deepEqual(calls.at(-1),['menu','album']);
  calls.length=0;const menu=first.querySelector('button.menu');assert.ok(menu.getAttribute('aria-label').includes('Meta Title'));menu.click();assert.deepEqual(calls.at(-1),['menu','album']);
  assert.equal(first.querySelector('button.play'),null,'Play only exists with a media service or onPlay');
  // Se pide toda la fila, con el área visible (cuatro) primero, y sin repetir al no haber cambios.
  const rest=(...first)=>[...first,...Array.from({length:12},(_,i)=>'a'+i).filter(id=>!first.includes(id))];
  assert.deepEqual(visible.at(-1),rest('a0','a1','a2','a3'));const reported=visible.length;
  scroller.dispatchEvent(new dom.Event('scroll'));await settle();assert.equal(visible.length,reported,'an unchanged set is not reported again');
  // Desplazar informa ancla y reordena el pedido (entre dos tarjetas: count + 1 a la vista).
  scroller.scrollLeft=600;scroller.dispatchEvent(new dom.Event('scroll'));await settle();
  assert.deepEqual(visible.at(-1),rest('a2','a3','a4','a5','a6'));assert.equal(anchors.at(-1),2);assert.equal(globalThis.__harness.anchor(),2);
  scroller.scrollLeft=2*256;scroller.dispatchEvent(new dom.Event('scroll'));await settle();assert.deepEqual(visible.at(-1),rest('a2','a3','a4','a5'));
  // Cambiar el ancho de tarjeta conserva la colección ancla.
  globalThis.__clientWidth=900;globalThis.__harness.width(264,3);await settle();
  assert.equal(globalThis.__harness.anchor(),2);assert.equal(scroller.scrollLeft,2*288,'the row stays on the same collection');
  assert.deepEqual(visible.at(-1),rest('a2','a3','a4'));
  // El padre mueve el ancla (p. ej. al volver a Inicio o al cambiar la lista).
  globalThis.__harness.setAnchor(7);await settle();assert.equal(scroller.scrollLeft,7*288);assert.equal(globalThis.__harness.anchor(),7);
  globalThis.__harness.list(globalThis.__albums().slice(4));globalThis.__harness.setAnchor(3);await settle();assert.equal(scroller.scrollLeft,3*288);assert.equal(visible.at(-1)[0],'a7');
  await unmount(app);target.remove();
 });
 test('a restored anchor mounts on that collection without asking for the start',async()=>{
  globalThis.__clientWidth=1056;visible.length=0;anchors.length=0;const target=document.createElement('div');document.body.append(target);
  const Restored=(await import(await moduleFor(path.join(root,'src/lib/components/home/RowRestored.svelte'),source.replace('anchor=$state(0)','anchor=$state(5)')))).default;
  let app;flushSync(()=>app=mount(Restored,{target}));await settle();
  assert.equal(target.querySelector('[data-horizontal-scroll]').scrollLeft,5*256);assert.ok(visible.every(ids=>ids[0]==='a5'),'the restored zone is requested first');
  await unmount(app);target.remove();
 });
}
