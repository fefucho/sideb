import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
if(!process.execArgv.includes('--conditions=browser')){
 test('Jam panel, Connections button, queue rows, exit dialog, toasts and debug panel',()=>{
  const {NODE_TEST_CONTEXT,...env}=process.env;
  const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});assert.equal(result.status,0,result.stdout+result.stderr);
 });
}else{
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('jam-ui-components');
 Object.defineProperty(dom.HTMLElement.prototype,'offsetParent',{configurable:true,get(){return this.parentElement;}});
 const Harness=(await import(await moduleFor(path.join(root,'scripts/fixtures/JamHarness.svelte')))).default;
 const JamInviteBanner=(await import(await moduleFor(path.join(root,'src/lib/components/jam/JamInviteBanner.svelte')))).default;
 const fx=await import('./jam-ui-fixtures.mjs');
 const settle=async()=>{for(let i=0;i<3;i++){flushSync();await tick();await Promise.resolve();}flushSync();await new Promise(r=>setTimeout(r,5));flushSync();};
 const sleep=ms=>new Promise(r=>setTimeout(r,ms));
 async function render(mode,state,extra={}){
  const jam=fx.fakeJam(state),host=document.createElement('div');document.body.append(host);
  const calls=[];
  const app=mount(Harness,{target:host,props:{store:jam.store,actions:jam.actions,searchSongs:jam.searchSongs,mode,calls,...extra}});await settle();
  return {jam,host,calls,q:s=>host.querySelector(s),qa:s=>[...host.querySelectorAll(s)],text:()=>host.textContent.replace(/\s+/g,' ').trim(),async done(){await unmount(app);host.remove();for(const node of document.body.querySelectorAll('.flyout'))node.remove();}};
 }
 const type=(input,value)=>{input.value=value;input.dispatchEvent(new Event('input',{bubbles:true}));flushSync();};
 const key=(target,name,init={})=>{const event=new KeyboardEvent('keydown',{key:name,bubbles:true,cancelable:true,...init});target.dispatchEvent(event);flushSync();return event;};

 // MARK: Panel by phase
 test('panel signed out offers the Spotify sign-in and nothing else',async()=>{
  const view=await render('panel',{...fx.emptyState(),runtime:{pluginAvailable:true,running:false,signedIn:false}});
  assert.equal(view.q('[data-jam-title]').textContent,'Spotify Jam');
  const card=view.q('[data-jam-access="needsLogin"]');assert.ok(card);assert.ok(card.textContent.includes('Iniciá sesión en Spotify'));
  assert.equal(view.q('[data-jam-link]'),null,'no link field before signing in');
  assert.ok(view.jam.last('refreshStatus'),'the panel refreshes the runtime status when it appears');
  view.q('[data-jam-signin]').click();await settle();assert.deepEqual(view.jam.last('openLogin'),['openLogin','Iniciá sesión en Spotify']);
  view.jam.set({phase:'error',messageKey:'jam.error.notSignedIn'});await settle();
  assert.ok(view.q('[data-jam-message]').textContent.includes('No hay una sesión de Spotify'));assert.ok(view.q('[data-jam-access="needsLogin"]').textContent.includes('No se pudo completar el inicio de sesión'));
  await view.done();
 });
 test('panel without the plugin explains it',async()=>{
  const view=await render('panel',{...fx.emptyState(),runtime:{pluginAvailable:false,running:false,signedIn:null}});
  assert.ok(view.q('[data-jam-access="pluginMissing"]').textContent.includes('Falta el plugin de Jam'));assert.equal(view.q('[data-jam-link]'),null);await view.done();
 });
 test('idle panel joins with the pasted link, validates it and explains why Join is off',async()=>{
  const view=await render('panel',fx.emptyState());
  const join=view.q('[data-jam-join]'),input=view.q('[data-jam-link]');
  assert.equal(join.disabled,true);assert.ok(view.text().includes('Sesión de Spotify activa'));assert.ok(view.q('[data-jam-paste]'),'Paste shows while the field is empty');
  type(input,'  https://example.com/nope  ');await settle();assert.ok(view.text().includes('No parece un link de invitación de Spotify Jam.'));assert.equal(view.q('[data-jam-clear]')!==null,true);
  type(input,'https://open.spotify.com/socialsession/abc');await settle();assert.ok(!view.text().includes('No parece un link'));assert.equal(join.disabled,false);
  join.click();await settle();assert.deepEqual(view.jam.last('join'),['join','https://open.spotify.com/socialsession/abc']);
  key(input,'Enter');await settle();assert.equal(view.jam.calls.filter(call=>call[0]==='join').length,2,'Enter submits too');
  view.q('[data-jam-clear]').click();await settle();assert.equal(input.value,'');assert.equal(join.disabled,true);
  await view.done();
 });
 test('joining shows the connecting card and Cancel leaves',async()=>{
  const view=await render('panel',{...fx.emptyState(),phase:'joining'});
  assert.ok(view.q('[data-jam-access="connecting"]').textContent.includes('Conectando con el Jam'));assert.equal(view.q('[data-jam-link]'),null);
  view.q('[data-jam-cancel]').click();await settle();assert.ok(view.jam.last('leave'));await view.done();
 });
 test('active panel shows host, participants, both versions, status and leaves',async()=>{
  const view=await render('panel',fx.activeState());
  assert.equal(view.q('[data-jam-title]').textContent,'Jam de Valentina Rodríguez');assert.equal(view.q('[data-jam-participants]').textContent,'6 participantes');
  const pairing=view.q('[data-jam-pairing]');assert.ok(pairing.textContent.includes('En Spotify'));assert.ok(pairing.textContent.includes('En YouTube Music'));assert.ok(pairing.textContent.includes('Song 1'));assert.ok(view.q('[data-jam-match]'));
  assert.equal(view.q('[data-jam-status]').dataset.jamStatus,'synced');assert.ok(view.q('[data-jam-status]').textContent.includes('Sincronizado'));
  assert.equal(view.qa('.member').length,4);assert.ok(view.q('[data-jam-members]').textContent.includes('y 2 más'));assert.ok(view.q('.tag.host').textContent.includes('Anfitrión'));assert.ok(view.q('.member.me .tag').textContent.includes('Vos'));
  assert.equal(view.q('[data-jam-nocontrol]'),null);assert.equal(view.q('[data-jam-link]'),null);
  view.q('[data-jam-leave]').click();await settle();assert.ok(view.jam.last('leave'));
  view.jam.set({canControl:false,paused:true});await settle();assert.ok(view.q('[data-jam-nocontrol]'));assert.equal(view.q('[data-jam-status]').dataset.jamStatus,'paused');
  view.jam.set({hostActive:false});await settle();assert.equal(view.q('[data-jam-status]').dataset.jamStatus,'hostInactive');
  view.jam.set({current:null});await settle();assert.ok(view.text().includes('Esperando que suene algo en el Jam.'));
  view.jam.set({current:fx.searching(1),hostActive:true,paused:false});await settle();assert.ok(view.text().includes('Buscando la versión en YouTube Music…'));assert.equal(view.q('[data-jam-status]').dataset.jamStatus,'searching');
  view.jam.set({current:fx.unavailable(1)});await settle();assert.ok(view.q('[data-jam-nomatch]').textContent.includes('No encontramos una versión confiable'));
  view.jam.set({current:fx.track(1,{matched:{...fx.track(1).matched,durationSecs:211}})});await settle();assert.ok(view.q('[data-jam-duration-warning]').textContent.includes('10 s más'));
  view.jam.set({phase:'reconnecting'});await settle();assert.ok(view.q('[data-jam-reconnecting]'));assert.ok(view.q('[data-jam-pairing]'),'a reconnecting Jam keeps its panel');
  await view.done();
 });
 test('error and ended phases return to the join form with their message',async()=>{
  const view=await render('panel',{...fx.emptyState(),phase:'error',messageKey:'jam.error.linkInvalid'});
  assert.ok(view.q('[data-jam-message]').textContent.includes('no es una invitación válida'));assert.ok(view.q('[data-jam-link]'),'the form stays so the link can be fixed');
  view.jam.set({phase:'error',messageKey:'jam.error.connection'});await settle();assert.ok(view.q('[data-jam-message]').textContent.includes('No hay conexión con Spotify'));
  view.jam.set({phase:'error',messageKey:'jam.error.madeUp'});await settle();assert.ok(view.q('[data-jam-message]').textContent.includes('Algo salió mal'),'unknown error keys degrade gracefully');
  view.jam.set({phase:'ended',messageKey:'jam.ended.host'});await settle();assert.ok(view.q('[data-jam-message]').textContent.includes('El anfitrión cerró el Jam.'));assert.ok(view.q('[data-jam-message]').textContent.includes('Tu cola anterior se restauró.'));
  view.jam.set({phase:'ended',messageKey:'jam.ended.left'});await settle();assert.ok(view.q('[data-jam-message]').textContent.includes('Saliste del Jam.'));
  await view.done();
 });
 test('choosing another version searches YouTube Music and corrects the match',async()=>{
  const view=await render('panel',fx.activeState());
  view.q('[data-jam-choose]').click();await settle();await sleep(10);await settle();
  assert.deepEqual(view.jam.searches,['Song 1 Artist 1']);
  const rows=view.qa('.picker .row');assert.equal(rows.length,2);assert.ok(rows[1].textContent.includes('VIDEO'));
  rows[0].click();await settle();
  const call=view.jam.last('correctMatch');assert.equal(call[1],'spotify:track:1#0');assert.deepEqual(call[2],{videoId:'alt1',title:'Song 1 (Live)',artists:'Artist 1',thumbnail:null,durationSecs:205});
  assert.equal(view.q('.picker'),null,'the picker closes after a pick');
  await view.done();
 });
 test('the "..." menu opens sync settings and the debug panel, and signs out of Spotify',async()=>{
  const view=await render('panel',fx.activeState({sync:{status:'locked',offsetMs:-8,manualOffsetMs:30},log:['join ok','state 12']}));
  assert.equal(view.q('[data-jam-debug]'),null);assert.equal(view.q('[data-jam-sync]'),null);
  view.q('[data-jam-more]').click();await settle();assert.equal(view.q('[data-jam-more]').getAttribute('aria-expanded'),'true');
  assert.equal(document.activeElement,view.q('[data-jam-menu="sync"]'));
  view.q('[data-jam-menu="sync"]').click();await settle();assert.ok(view.q('[data-jam-sync]'));assert.equal(view.q('[role="menu"]'),null,'choosing closes the menu');
  view.q('[data-jam-sync] [data-step="10"]').click();await settle();assert.deepEqual(view.jam.last('setManualOffset'),['setManualOffset',40]);
  view.q('[data-jam-more]').click();await settle();view.q('[data-jam-menu="debug"]').click();await settle();
  assert.ok(view.q('.debug'));assert.ok(view.q('.debug').textContent.includes('state 12'));
  view.q('[data-jam-more]').click();await settle();key(document.activeElement,'Escape');await settle();assert.equal(view.q('[role="menu"]'),null);
  view.q('[data-jam-more]').click();await settle();view.q('[data-jam-menu="signout"]').click();await settle();assert.ok(view.jam.last('signOut'));
  await view.done();
 });

 // MARK: Connections button
 test('Connections button: host badge only while a Jam is live, labels follow the Jam',async()=>{
  const view=await render('connections',fx.emptyState());
  const button=()=>view.q('[data-connections]');
  assert.equal(button().getAttribute('aria-label'),'Conexiones');assert.equal(view.q('[data-host-badge]'),null);assert.equal(button().classList.contains('live'),false);
  view.jam.set(fx.activeState());await settle();
  assert.ok(view.q('[data-host-badge]'));assert.equal(view.q('[data-host-badge] .initial').textContent,'V');assert.equal(button().classList.contains('live'),true);
  assert.equal(button().getAttribute('aria-label'),'Conexiones. En el Jam de Valentina Rodríguez');assert.equal(button().title,'Conexiones. En el Jam de Valentina Rodríguez');
  view.jam.set({host:null,members:[fx.member('Tomás',{isMe:true})]});await settle();assert.equal(button().getAttribute('aria-label'),'Conexiones. En un Jam de Spotify');assert.equal(view.q('[data-host-badge] .initial').textContent,'?');
  view.jam.set({phase:'ended'});await settle();assert.equal(view.q('[data-host-badge]'),null);
  await view.done();
 });
 test('Connections flyout opens the panel, closes on Escape and outside clicks and restores focus',async()=>{
  const view=await render('connections',fx.emptyState());
  const button=view.q('[data-connections]');button.focus();button.click();await settle();await settle();
  const flyout=document.body.querySelector('.flyout');assert.ok(flyout,'the flyout lives under <body>, outside any clipping bar');assert.equal(flyout.getAttribute('role'),'dialog');assert.equal(button.getAttribute('aria-expanded'),'true');
  assert.ok(flyout.querySelector('[data-jam-panel]'));assert.equal(flyout.querySelector('[data-jam-title]').textContent,'Spotify Jam');
  key(document.activeElement??flyout,'Escape');await settle();assert.equal(document.body.querySelector('.flyout'),null);assert.equal(button.getAttribute('aria-expanded'),'false');assert.equal(document.activeElement,button);
  button.click();await settle();assert.ok(document.body.querySelector('.flyout'));
  document.body.dispatchEvent(new MouseEvent('pointerdown',{bubbles:true}));await settle();assert.equal(document.body.querySelector('.flyout'),null);
  button.click();await settle();document.body.querySelector('.flyout').dispatchEvent(new MouseEvent('pointerdown',{bubbles:true}));await settle();assert.ok(document.body.querySelector('.flyout'),'clicks inside keep it open');
  button.click();await settle();assert.equal(document.body.querySelector('.flyout'),null,'the button toggles it');
  await view.done();
 });

 // MARK: Badge
 test('badge marker names the host and is a button only when it has an action',async()=>{
  const view=await render('badge',fx.activeState());
  const badge=view.q('.badge');assert.equal(badge.tagName,'BUTTON');assert.equal(badge.getAttribute('aria-label'),'En el Jam de Valentina Rodríguez');assert.equal(view.qa('.avatar').length,4,'the stack shows four avatars');assert.ok(view.q('.stack .more').textContent.includes('+2'),'and a +N disc for the rest');
  badge.click();assert.deepEqual(view.calls.at(-1),['badge']);
  view.jam.set({host:null,members:[]});await settle();assert.equal(view.q('.badge').getAttribute('aria-label'),'En un Jam');
  await view.done();
 });

 // MARK: Queue rows
 test('queue rows: matched is a normal row, searching is dimmed with a spinner, unavailable says why',async()=>{
  const view=await render('queue',fx.activeState(),{playback:fx.jamPlayback()});
  const rows=view.qa('[data-jam-row]');assert.equal(rows.length,5,'the playing track plus four Jam rows');
  assert.equal(view.q('[data-jam-queue-title]').textContent,'Jam de Valentina Rodríguez');assert.ok(view.q('.count').textContent.includes('5'));
  const byStatus=status=>view.qa(`[data-jam-row][data-status="${status}"]`);
  const matched=byStatus('matched').filter(row=>row.dataset.jamRow!=='current'),searchingRow=byStatus('searching')[0],unavailableRow=byStatus('unavailable')[0];
  assert.equal(matched.length,2);assert.ok(!matched[0].classList.contains('dim'));assert.equal(matched[0].querySelector('[data-jam-row-status]'),null);assert.ok(matched[0].textContent.includes('Artist 2'));
  assert.ok(searchingRow.classList.contains('dim'));assert.ok(searchingRow.querySelector('.spinner'));assert.equal(searchingRow.querySelector('[data-jam-row-status]').textContent,'Buscando en YouTube Music…');
  assert.ok(unavailableRow.classList.contains('dim'));assert.equal(unavailableRow.querySelector('.spinner'),null);assert.equal(unavailableRow.querySelector('[data-jam-row-status]').textContent,'Sin equivalente en YouTube Music');assert.ok(unavailableRow.querySelector('.alert'));
  assert.deepEqual(rows.map(row=>row.dataset.jamRow),['current','0','1','2','3']);
  assert.equal(view.q('[data-jam-row="0"] .num').textContent,'2');assert.equal(view.q('[data-jam-row="3"] .num').textContent,'5');
  await view.done();
 });
 test('queue rows activate only what mirrors a native occurrence and open the shared context menu',async()=>{
  const view=await render('queue',fx.activeState(),{playback:fx.jamPlayback()});
  view.q('[data-jam-row="0"] .select').click();view.q('[data-jam-row="3"] .select').click();assert.deepEqual(view.calls,[['select',1],['select',2]]);
  assert.equal(view.q('[data-jam-row="1"] .select').disabled,true);assert.equal(view.q('[data-jam-row="2"] .select').disabled,true);
  view.q('[data-jam-row="current"] .select').click();assert.deepEqual(view.calls.at(-1),['toggle']);
  view.q('[data-jam-row="0"]').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true}));assert.deepEqual(view.calls.at(-1),['menu','e2']);
  const before=view.calls.length;view.q('[data-jam-row="1"]').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true}));assert.equal(view.calls.length,before,'rows with no native twin have no native menu');
  await view.done();
 });
 test('queue edits go to the Jam: remove by index, keyboard and drag reorder by Jam-queue index',async()=>{
  const view=await render('queue',fx.activeState(),{playback:fx.jamPlayback()});
  view.q('[data-jam-remove="2"]').click();await settle();assert.deepEqual(view.jam.last('removeQueue'),['removeQueue',2],'a row that only exists in the Jam can be removed');
  key(view.q('[data-jam-handle="1"]'),'ArrowDown');await settle();assert.deepEqual(view.jam.last('moveQueue'),['moveQueue',1,2]);
  key(view.q('[data-jam-handle="2"]'),'ArrowUp');await settle();assert.deepEqual(view.jam.last('moveQueue'),['moveQueue',2,1]);
  const before=view.jam.calls.length;key(view.q('[data-jam-handle="0"]'),'ArrowUp');key(view.q('[data-jam-handle="3"]'),'ArrowDown');await settle();assert.equal(view.jam.calls.length,before,'moves past either end are ignored');
  const rect=(top)=>({top,bottom:top+46,height:46,left:0,right:300,width:300,x:0,y:top});
  const dragover=(row,y)=>{const event=new Event('dragover',{bubbles:true,cancelable:true});event.clientY=y;event.dataTransfer={dropEffect:'',effectAllowed:'',setData(){},setDragImage(){}};row.getBoundingClientRect=()=>rect(0);row.dispatchEvent(event);flushSync();};
  const start=handle=>{const event=new Event('dragstart',{bubbles:true,cancelable:true});event.dataTransfer={dropEffect:'',effectAllowed:'',setData(){},setDragImage(){}};handle.dispatchEvent(event);flushSync();};
  start(view.q('[data-jam-handle="0"]'));dragover(view.q('[data-jam-row="2"]'),40);await settle();// lower half of row 2 -> after it
  view.q('[data-jam-row="2"]').dispatchEvent(Object.assign(new Event('drop',{bubbles:true,cancelable:true}),{clientY:40}));await settle();
  assert.deepEqual(view.jam.last('moveQueue'),['moveQueue',0,2],'drop after row 2 puts the track at index 2');
  start(view.q('[data-jam-handle="3"]'));dragover(view.q('[data-jam-row="1"]'),5);await settle();
  view.q('[data-jam-row="1"]').dispatchEvent(Object.assign(new Event('drop',{bubbles:true,cancelable:true}),{clientY:5}));await settle();
  assert.deepEqual(view.jam.last('moveQueue'),['moveQueue',3,1],'drop before row 1 puts the track at index 1');
  await view.done();
 });
 test('queue rows pick another version (also for tracks with no equivalent)',async()=>{
  const view=await render('queue',fx.activeState(),{playback:fx.jamPlayback()});
  view.q('[data-jam-row="2"] [data-jam-pick]').click();await settle();await sleep(10);await settle();
  assert.deepEqual(view.jam.searches,['Song 4 Artist 4']);
  view.qa('.picker .row')[1].click();await settle();
  const call=view.jam.last('correctMatch');assert.equal(call[1],'spotify:track:4#0');assert.equal(call[2].videoId,'alt2');assert.equal(view.q('.picker'),null);
  await view.done();
 });
 test('an empty Jam queue says so and the sidebar preview follows the Jam order without buttons',async()=>{
  const view=await render('queue',fx.activeState({current:null,queue:[]}),{playback:fx.jamPlayback()});
  assert.ok(view.text().includes('La cola del Jam está vacía.'));await view.done();
  const up=await render('upcoming',fx.activeState(),{playback:fx.jamPlayback()});
  assert.equal(up.q('h3').textContent,'Jam de Valentina Rodríguez');const rows=up.qa('.jam-row');assert.equal(rows.length,2);assert.equal(up.qa('button.row').length,0);
  assert.ok(rows[0].textContent.includes('Song 2'));assert.ok(rows[1].classList.contains('dim'));assert.ok(rows[1].textContent.includes('Buscando en YouTube Music…'));
  up.jam.set({phase:'idle'});await settle();assert.equal(up.q('h3').textContent,'A continuación','outside a Jam the native preview returns');
  await up.done();
 });

 // MARK: Exit dialog + toasts + debug
 test('exit dialog: stay is focused, confirm and cancel call the actions, Escape cancels, focus stays inside',async()=>{
  const view=await render('toasts',fx.activeState());
  assert.equal(view.q('[data-jam-exit]'),null);
  view.jam.set({pendingExit:{reasonKey:'jam.exit.playOther'}});await settle();await settle();
  const dialog=view.q('[data-jam-exit]');assert.ok(dialog);assert.equal(dialog.getAttribute('role'),'alertdialog');assert.equal(view.q('#jam-exit-title').textContent,'¿Salir del Jam?');
  assert.equal(view.q('[data-jam-exit-message]').textContent,'Para reproducir esto, Side B sale del Jam y restaura tu cola anterior.');
  const stay=view.q('[data-jam-exit-cancel]'),leave=view.q('[data-jam-exit-confirm]');assert.equal(document.activeElement,stay);assert.equal(stay.textContent,'Quedarme en el Jam');assert.equal(leave.textContent,'Salir del Jam y reproducir');
  leave.focus();assert.equal(key(leave,'Tab').defaultPrevented,true);assert.equal(document.activeElement,stay,'Tab wraps');
  assert.equal(key(stay,'Tab',{shiftKey:true}).defaultPrevented,true);assert.equal(document.activeElement,leave,'Shift+Tab wraps');
  leave.click();await settle();assert.ok(view.jam.last('confirmExit'));
  stay.click();await settle();assert.ok(view.jam.last('cancelExit'));
  key(document.body,'Escape');await settle();assert.equal(view.jam.calls.filter(call=>call[0]==='cancelExit').length,2);
  view.q('.scrim').click();await settle();assert.equal(view.jam.calls.filter(call=>call[0]==='cancelExit').length,3,'the scrim cancels as well');
  view.jam.set({pendingExit:{reasonKey:'jam.exit.somethingNew'}});await settle();assert.ok(view.q('[data-jam-exit-message]').textContent.includes('Side B sale del Jam'),'unknown reason keys use the generic body');
  view.jam.set({pendingExit:null});await settle();assert.equal(view.q('[data-jam-exit]'),null);
  await view.done();
 });
 test('toasts render each notice, dismiss on request and expire on their own',async()=>{
  const view=await render('toasts',fx.activeState(),{toastDuration:40});
  view.jam.set({toasts:[{id:2,key:'jam.notice.localOnly'},{id:1,key:'jam.error.connection'},{id:3,key:'jam.notice.neverHeardOf'}]});await settle();
  const toasts=view.qa('[data-toast-id]');assert.deepEqual(toasts.map(toast=>toast.dataset.toastId),['2','1','3']);
  assert.equal(toasts[0].querySelector('.text').textContent,'Esto sólo cambió para vos: el Jam sigue.');assert.equal(toasts[1].querySelector('.text').textContent,'No hay conexión con Spotify. Revisá tu red e intentá de nuevo.');assert.equal(toasts[2].querySelector('.text').textContent,'Hay una novedad en el Jam.');
  assert.equal(toasts[1].getAttribute('role'),'alert');assert.equal(toasts[0].getAttribute('role'),'status');
  toasts[0].querySelector('.dismiss').click();assert.deepEqual(view.jam.last('dismissToast'),['dismissToast',2]);
  await sleep(120);await settle();
  assert.deepEqual(view.jam.calls.filter(call=>call[0]==='dismissToast').map(call=>call[1]).sort(),[1,2,3],'the rest expire on their own timer');
  await view.done();
 });
 test('debug panel: sync offset, manual trim steps, resync and the log',async()=>{
  const view=await render('debug',fx.activeState({sync:{status:'adjusting',offsetMs:-42,manualOffsetMs:-20},log:Array.from({length:60},(_,i)=>`line ${i}`),runtime:{pluginAvailable:true,running:true,signedIn:null}}));
  assert.ok(view.q('[data-debug="offset"]').textContent.includes('-42 ms'));assert.ok(view.q('[data-debug="sync"]').textContent.includes('adjusting'));assert.ok(view.q('[data-debug="runtime"]').textContent.includes('sin comprobar'));
  assert.equal(view.qa('.log li').length,40,'the log shows its last 40 lines');assert.equal(view.qa('.log li').at(-1).textContent,'line 59');
  for(const [step,expected] of [[-50,-70],[-10,-30],[10,-10],[50,30]]){view.q(`[data-step="${step}"]`).click();assert.deepEqual(view.jam.last('setManualOffset'),['setManualOffset',expected]);}
  view.q('.reset').click();assert.deepEqual(view.jam.last('setManualOffset'),['setManualOffset',0]);
  view.q('[data-debug="resync"]').click();assert.ok(view.jam.last('resync'));
  view.jam.set({sync:{status:'idle',offsetMs:null,manualOffsetMs:0},log:[]});await settle();assert.ok(view.q('[data-debug="offset"]').textContent.includes('—'));assert.ok(view.q('.log .empty'));assert.equal(view.q('.reset').disabled,true);assert.equal(view.q('[data-debug="copy"]').disabled,true);
  await view.done();
 });

 // MARK: Live Jam invites UI
 test('JamInviteBanner renders known and unknown senders and triggers join and dismiss',async()=>{
  const host=document.createElement('div');document.body.append(host);
  const events=[];
  const inv1=fx.invite(1,{senderName:'Valentina'});
  let app=mount(JamInviteBanner,{target:host,props:{invite:null,onJoin:inv=>events.push(['join',inv.id]),onDismiss:id=>events.push(['dismiss',id])}});await settle();
  assert.equal(host.querySelector('[data-jam-invite-banner]'),null,'nothing renders when invite is null');
  await unmount(app);

  app=mount(JamInviteBanner,{target:host,props:{invite:inv1,onJoin:inv=>events.push(['join',inv.id]),onDismiss:id=>events.push(['dismiss',id])}});await settle();
  const banner=host.querySelector('[data-jam-invite-banner]');assert.ok(banner);
  assert.equal(banner.querySelector('[data-invite-title]').textContent,'Valentina te invitó a un Jam');
  assert.equal(banner.querySelector('[data-invite-subtitle]').textContent,'Spotify Jam · Escuchar juntos en Side B');
  banner.querySelector('[data-invite-join]').click();await settle();
  banner.querySelector('[data-invite-dismiss]').click();await settle();
  assert.deepEqual(events,[['join','inv-1'],['dismiss','inv-1']]);
  await unmount(app);

  const invUnknown=fx.invite(2,{senderName:null});
  app=mount(JamInviteBanner,{target:host,props:{invite:invUnknown,onJoin:()=>{},onDismiss:()=>{}}});await settle();
  assert.equal(host.querySelector('[data-invite-title]').textContent,'Tenés una invitación a un Jam');
  await unmount(app);host.remove();
 });

 test('JamPanel lists active invitations above the link input only when signed in and plugin ready',async()=>{
  const inv1=fx.invite(1,{senderName:'Valentina',participantCount:3});
  const inv2=fx.invite(2,{senderName:null,participantCount:1});
  const view=await render('panel',{...fx.emptyState(),invites:[inv1,inv2]});
  const section=view.q('[data-jam-invites]');assert.ok(section);
  assert.ok(section.textContent.includes('Invitaciones activas'));
  const cards=view.qa('[data-jam-invite-id]');assert.equal(cards.length,2);
  assert.ok(cards[0].textContent.includes('Jam de Valentina'));assert.ok(cards[0].textContent.includes('3 personas escuchando'));
  assert.ok(cards[1].textContent.includes('Invitación de Spotify Jam'));assert.ok(cards[1].textContent.includes('1 persona escuchando'));
  const field=view.q('.field');
  assert.ok(Boolean(section.compareDocumentPosition(field)&Node.DOCUMENT_POSITION_FOLLOWING),'active invitations appear above link field');
  view.q('[data-jam-invite-join="inv-1"]').click();await settle();assert.deepEqual(view.jam.last('joinInvite'),['joinInvite',inv1]);
  view.q('[data-jam-invite-dismiss="inv-2"]').click();await settle();assert.deepEqual(view.jam.last('dismissInvite'),['dismissInvite','inv-2']);

  view.jam.set({runtime:{pluginAvailable:true,running:false,signedIn:false}});await settle();
  assert.equal(view.q('[data-jam-invites]'),null,'hidden when signed out');
  view.jam.set({runtime:{pluginAvailable:false,running:false,signedIn:true}});await settle();
  assert.equal(view.q('[data-jam-invites]'),null,'hidden when plugin missing');
  await view.done();
 });

 test('ConnectionsButton shows an invite dot and tooltip when idle with invites, while live Jam badge takes precedence',async()=>{
  const inv=fx.invite(1,{senderName:'Valentina'});
  const view=await render('connections',{...fx.emptyState(),invites:[inv]});
  const button=()=>view.q('[data-connections]');
  assert.ok(view.q('[data-invite-badge]'));assert.equal(view.q('[data-host-badge]'),null);
  assert.equal(button().getAttribute('aria-label'),'Conexiones · Tenés una invitación a un Jam de Valentina');
  assert.equal(button().title,'Conexiones · Tenés una invitación a un Jam de Valentina');

  view.jam.set({invites:[fx.invite(2,{senderName:null})]});await settle();
  assert.equal(button().title,'Conexiones · Tenés una invitación a un Jam');

  view.jam.set(fx.activeState({invites:[inv]}));await settle();
  assert.ok(view.q('[data-host-badge]'));assert.equal(view.q('[data-invite-badge]'),null,'live host badge takes precedence');
  await view.done();
 });
}
