import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {readFileSync} from 'node:fs';
if(!process.execArgv.includes('--conditions=browser')){
 test('Jam presentation rules, string mapping and queue pairing',()=>{
  const {NODE_TEST_CONTEXT,...env}=process.env;
  const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});assert.equal(result.status,0,result.stdout+result.stderr);
 });
}else{
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,moduleFor}=await mountedSvelteEnvironment('jam-ui-presentation');
 const presentation=await import(await moduleFor(path.join(root,'src/lib/components/jam/view.ts')));
 const i18n=await import(await moduleFor(path.join(root,'src/lib/i18n/index.ts')));
 const fixtures=await import('./jam-ui-fixtures.mjs');
 const {jamText,noticeTone,syncLabel,mergeJamQueue,durationDelta,parseDuration,avatarTint,orderedMembers,isJamLive,jamTitle,badgeLabel,formatMs,inviteSenderName,inviteBannerTitle,inviteCardTitle,inviteParticipantsLabel,connectionsInviteTooltip}=presentation;

 test('every contract key the session logic may emit resolves to real copy in both languages',()=>{
  const keys=['jam.notice.localOnly','jam.notice.noHostDevice','jam.notice.noEquivalent','jam.notice.unavailableInJam','jam.error.notSignedIn','jam.error.pluginMissing','jam.error.linkInvalid','jam.error.connection','jam.error.generic','jam.ended.host','jam.ended.left','jam.exit.playOther'];
  for(const language of ['es','en'])for(const key of keys){
   const text=jamText(key,undefined,language);
   assert.ok(text&&text!=='No disponible',`${key}/${language}`);
   assert.ok(!text.includes('jam.')&&!text.includes('%@'),`${key}/${language}: ${text}`);
  }
  assert.equal(jamText('jam.error.linkInvalid',undefined,'en'),"The link isn't a valid Spotify Jam invitation.");
  assert.equal(jamText('jam.notice.noHostDevice',undefined,'es'),'El anfitrión no tiene un dispositivo activo');
  assert.equal(jamText('jam.ended.host',undefined,'en'),'The host closed the Jam.');
  assert.equal(jamText('jam.exit.playOther',undefined,'es'),'Para reproducir esto, Side B sale del Jam y restaura tu cola anterior.');
 });
 test('unknown keys degrade to a generic string of their family and values fill positional placeholders',()=>{
  assert.equal(jamText('jam.notice.somethingNew',undefined,'en'),'Something changed in the Jam.');
  assert.equal(jamText('jam.error.somethingNew',undefined,'en'),'Something went wrong while joining the Jam.');
  assert.equal(jamText('jam.exit.somethingNew',undefined,'en'),'To play this, Side B leaves the Jam and restores your previous queue.');
  assert.equal(jamText('totally.unknown',undefined,'en'),'Something changed in the Jam.');
  assert.equal(jamText('jam.action.added',{title:'Blinding Lights'},'en'),'“Blinding Lights” was added to the Jam.');
  assert.equal(noticeTone('jam.action.added'),'success');assert.equal(noticeTone('jam.error.generic'),'warning');assert.equal(noticeTone('jam.notice.localOnly'),'info');
  assert.ok(i18n.hasText('windows.jam.notice.localOnly')&&!i18n.hasText('jam.notice.localOnly'));
 });
 test('sync status ladder follows the Mac panel',()=>{
  const state=fixtures.activeState();
  assert.equal(syncLabel(state),'synced');
  assert.equal(syncLabel({...state,hostActive:false}),'hostInactive');
  assert.equal(syncLabel({...state,current:null}),'waiting');
  assert.equal(syncLabel({...state,current:fixtures.searching(1)}),'searching');
  assert.equal(syncLabel({...state,current:fixtures.unavailable(1)}),'noMatch');
  assert.equal(syncLabel({...state,paused:true}),'paused');
  assert.equal(syncLabel({...state,sync:{...state.sync,status:'adjusting'}}),'adjusting');
  assert.equal(isJamLive({phase:'active'}),true);assert.equal(isJamLive({phase:'reconnecting'}),true);assert.equal(isJamLive({phase:'joining'}),false);assert.equal(isJamLive({phase:'ended'}),false);
 });
 test('titles, badge labels, durations and avatars',()=>{
  const state=fixtures.activeState();
  assert.equal(jamTitle(state,'es'),'Jam de Valentina Rodríguez');assert.equal(badgeLabel(state,'en'),"In Valentina Rodríguez's Jam");
  assert.equal(jamTitle({host:null,members:[]},'es'),'Jam de Spotify');assert.equal(badgeLabel({host:null,members:[]},'es'),'En un Jam');
  assert.equal(formatMs(200000),'3:20');assert.equal(formatMs(null),'');assert.equal(parseDuration('3:20'),200);assert.equal(parseDuration('1:02:03'),3723);assert.equal(parseDuration(null),null);
  assert.equal(durationDelta(fixtures.track(1,{durationMs:200000,matched:{...fixtures.track(1).matched,durationSecs:203}})),3);assert.equal(durationDelta(fixtures.track(1,{durationMs:200000,matched:{...fixtures.track(1).matched,durationSecs:201}})),null);
  assert.equal(avatarTint('Mei'),avatarTint('Mei'));assert.notEqual(avatarTint('Mei'),avatarTint('Ana'));
  assert.deepEqual(orderedMembers(state.members).slice(0,2).map(m=>m.name),['Valentina Rodríguez','Tomás']);
 });
 test('Jam queue pairing mirrors native occurrences only when the matched videos agree',()=>{
  const state=fixtures.activeState(),playback=fixtures.jamPlayback();
  const rows=mergeJamQueue(state.queue,playback);
  assert.deepEqual(rows.map(row=>row.number),[2,3,4,5]);
  assert.deepEqual(rows.map(row=>row.entry?.entryId??null),['e2',null,null,'e5']);assert.deepEqual(rows.map(row=>row.nativeIndex),[1,null,null,2]);
  const stale=mergeJamQueue(state.queue,{queue:{...playback.queue,items:playback.queue.items.slice(0,2)}});
  assert.ok(stale.every(row=>row.entry===null&&row.nativeIndex===null),'without a reliable pairing nothing is invented');
 });
 test('Windows catalog carries the shared Jam wording and every windows.jam key is bilingual',()=>{
  const catalog=JSON.parse(readFileSync(path.join(root,'src/lib/i18n/catalog.json'),'utf8')),own=JSON.parse(readFileSync(path.join(root,'src/lib/i18n/windows.json'),'utf8'));
  for(const key of ['jam.panel.title','jam.join','jam.exit.confirm','jam.exit.cancel','connections.title','jam.surface.tab','jam.queue.unavailable','jam.queue.resolving'])assert.ok(catalog[key]?.es&&catalog[key]?.en,key);
  const jamKeys=Object.keys(own).filter(key=>key.startsWith('windows.jam.'));assert.ok(jamKeys.length>20);
  for(const key of jamKeys)assert.ok(own[key].es&&own[key].en,key);
 });
 test('invite presentation formats sender, participant counts and connections tooltip in es and en',()=>{
  const known=fixtures.invite(1,{senderName:'  Valentina  ',participantCount:3});
  const single=fixtures.invite(2,{senderName:'',participantCount:1});
  const unknown=fixtures.invite(3,{senderName:null,participantCount:null});
  assert.equal(inviteSenderName(known),'Valentina');
  assert.equal(inviteSenderName(single),null);
  assert.equal(inviteBannerTitle(known,'es'),'Valentina te invitó a un Jam');
  assert.equal(inviteBannerTitle(known,'en'),'Valentina invited you to a Jam');
  assert.equal(inviteBannerTitle(unknown,'es'),'Tenés una invitación a un Jam');
  assert.equal(inviteBannerTitle(unknown,'en'),'You have a Jam invitation');
  assert.equal(inviteCardTitle(known,'es'),'Jam de Valentina');
  assert.equal(inviteCardTitle(known,'en'),"Valentina's Jam");
  assert.equal(inviteCardTitle(unknown,'es'),'Invitación de Spotify Jam');
  assert.equal(inviteCardTitle(unknown,'en'),'Spotify Jam invitation');
  assert.equal(inviteParticipantsLabel(single,'es'),'1 persona escuchando');
  assert.equal(inviteParticipantsLabel(single,'en'),'1 person listening');
  assert.equal(inviteParticipantsLabel(known,'es'),'3 personas escuchando');
  assert.equal(inviteParticipantsLabel(known,'en'),'3 people listening');
  assert.equal(inviteParticipantsLabel(unknown,'es'),'Spotify Jam · Escuchar juntos en Side B');
  assert.equal(inviteParticipantsLabel(unknown,'en'),'Spotify Jam · Listen together in Side B');
  assert.equal(connectionsInviteTooltip([known],'es'),'Conexiones · Tenés una invitación a un Jam de Valentina');
  assert.equal(connectionsInviteTooltip([known],'en'),'Connections · You have a Jam invite from Valentina');
  assert.equal(connectionsInviteTooltip([unknown],'es'),'Conexiones · Tenés una invitación a un Jam');
  assert.equal(connectionsInviteTooltip([unknown],'en'),'Connections · You have a Jam invitation');
 });
}
