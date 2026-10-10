import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import ts from 'typescript';
const source=await readFile(new URL('../src/lib/navigation/gestures.ts',import.meta.url),'utf8');
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {NavigationGesturePolicy,installNavigationGestures}=await import(`data:text/javascript;base64,${Buffer.from(compiled).toString('base64')}`);
const context=()=>({revision:'route:session',enabled:true,blocked:false,fullscreen:false,reduceMotion:false,height:600,backTitle:'Inicio',forwardTitle:'Buscar'});
const wheel=(x,y=0,extra={})=>({x,y,at:1,alt:true,ctrl:false,pixels:true,owner:'history',...extra});

test('ordinary wheel, zoom and non-pixel wheel never claim navigation',()=>{
  for(const extra of [{alt:false},{ctrl:true},{pixels:false}]){const policy=new NavigationGesturePolicy();assert.equal(policy.wheelEvent(wheel(200,0,extra),context()).consume,false);assert.equal(policy.settleWheel(context()).commit,undefined);}
});
test('Alt wheel reports candidate/progress, hysteresis and one commit until Alt released',()=>{
  const policy=new NavigationGesturePolicy(),ctx=context();
  let output=policy.wheelEvent(wheel(40),ctx);assert.equal(output.progress.action,'back');assert.equal(output.progress.title,'Inicio');assert.equal(output.progress.phase,'tracking');
  output=policy.wheelEvent(wheel(26),ctx);assert.equal(output.progress.phase,'armed');
  output=policy.wheelEvent(wheel(-18),ctx);assert.equal(output.progress.phase,'armed');
  assert.equal(policy.settleWheel(ctx).commit,'back');
  assert.equal(policy.wheelEvent(wheel(200),ctx).consume,true);assert.equal(policy.settleWheel(ctx).commit,undefined);
  policy.releaseAlt(ctx);policy.wheelEvent(wheel(-80),ctx);assert.equal(policy.settleWheel(ctx).commit,'forward');
});
test('local/excluded burst owns all events even when pointer leaves shelf or reaches its edge',()=>{
  for(const owner of ['local','excluded']){const policy=new NavigationGesturePolicy(),ctx=context();assert.equal(policy.wheelEvent(wheel(2,0,{owner}),ctx).consume,false);assert.equal(policy.wheelEvent(wheel(200),ctx).consume,false);assert.equal(policy.settleWheel(ctx).commit,undefined);}
  const policy=new NavigationGesturePolicy(),ctx=context();policy.wheelEvent(wheel(20),ctx);assert.equal(policy.wheelEvent(wheel(60,0,{owner:'local'}),ctx).consume,true);assert.equal(policy.settleWheel(ctx).commit,'back');
});
test('vertical, diagonal and unavailable destinations do not commit',()=>{
  const vertical=new NavigationGesturePolicy(),ctx=context();vertical.wheelEvent(wheel(3,40),ctx);vertical.wheelEvent(wheel(100,0),ctx);assert.equal(vertical.settleWheel(ctx).commit,undefined);
  const diagonal=new NavigationGesturePolicy();assert.equal(diagonal.wheelEvent(wheel(30,30),ctx).consume,false);assert.equal(diagonal.settleWheel(ctx).commit,undefined);
  for(const override of [{backTitle:null},{blocked:true},{enabled:false},{fullscreen:true}]){const policy=new NavigationGesturePolicy(),modified={...ctx,...override};policy.wheelEvent(wheel(150),modified);assert.equal(policy.settleWheel(modified).commit,undefined);}
});
test('route, account, resize, modal and explicit cancellation drain a claimed burst without commit',()=>{
  for(const modified of [{revision:'other-session'},{revision:'other-route'},{height:700},{blocked:true}]){const policy=new NavigationGesturePolicy(),ctx=context();policy.wheelEvent(wheel(100),ctx);assert.equal(policy.settleWheel({...ctx,...modified}).commit,undefined);}
  const policy=new NavigationGesturePolicy(),ctx=context();policy.wheelEvent(wheel(100),ctx);assert.equal(policy.cancel().consume,true);assert.equal(policy.wheelEvent(wheel(100),ctx).consume,true);assert.equal(policy.settleWheel(ctx).commit,undefined);
});
test('touch/pen pull follows displacement, snaps when cancelled and commits only its own pointer',()=>{
  const ctx={...context(),fullscreen:true};const policy=new NavigationGesturePolicy();
  assert.equal(policy.beginPointer(1,20,20,'touch',true,ctx).consume,true);
  assert.equal(policy.movePointer(2,20,200,ctx).consume,false);
  let output=policy.movePointer(1,20,80,ctx);assert.equal(output.progress.distance,60);assert.equal(output.progress.phase,'tracking');assert.equal(policy.endPointer(1,ctx).commit,undefined);
  policy.beginPointer(1,20,20,'pen',true,ctx);output=policy.movePointer(1,20,180,ctx);assert.equal(output.progress.phase,'armed');assert.equal(policy.endPointer(1,ctx).commit,'dismiss-fullscreen');
  policy.beginPointer(1,20,20,'touch',true,ctx);policy.movePointer(1,20,180,ctx);assert.equal(policy.endPointer(1,ctx,true).commit,undefined);
});
test('mouse, unmarked surfaces, horizontal/upward starts and changed contexts cannot close fullscreen',()=>{
  const ctx={...context(),fullscreen:true};
  for(const [type,eligible] of [['mouse',true],['touch',false]]){const policy=new NavigationGesturePolicy();assert.equal(policy.beginPointer(1,0,0,type,eligible,ctx).consume,false);assert.equal(policy.endPointer(1,ctx).commit,undefined);}
  for(const [x,y] of [[100,2],[2,-50]]){const policy=new NavigationGesturePolicy();policy.beginPointer(1,0,0,'touch',true,ctx);policy.movePointer(1,x,y,ctx);policy.movePointer(1,0,200,ctx);assert.equal(policy.endPointer(1,ctx).commit,undefined);}
  for(const override of [{revision:'new'},{blocked:true},{fullscreen:false},{height:700}]){const policy=new NavigationGesturePolicy();policy.beginPointer(1,0,0,'touch',true,ctx);policy.movePointer(1,0,200,ctx);assert.equal(policy.endPointer(1,{...ctx,...override}).commit,undefined);}
});

test('cancel drains inertia, a new Alt press recovers; focus reset admits the next sequence',()=>{
  const policy=new NavigationGesturePolicy(),ctx=context();policy.wheelEvent(wheel(100),ctx);policy.cancel();
  policy.wheelEvent(wheel(100),ctx);assert.equal(policy.settleWheel(ctx).commit,undefined);
  policy.startAlt();policy.wheelEvent(wheel(-100),ctx);assert.equal(policy.settleWheel(ctx).commit,'forward');
  policy.reset();policy.wheelEvent(wheel(100),ctx);assert.equal(policy.settleWheel(ctx).commit,'back');
  policy.beginPointer(1,0,0,'touch',true,{...ctx,fullscreen:true});policy.reset();assert.equal(policy.endPointer(1,{...ctx,fullscreen:true}).commit,undefined);
});
test('Reduce Motion retains actions; presentation chooses whether to animate',()=>{
  const policy=new NavigationGesturePolicy(),ctx={...context(),reduceMotion:true};policy.wheelEvent(wheel(100),ctx);assert.equal(policy.settleWheel(ctx).commit,'back');
  policy.beginPointer(1,0,0,'touch',true,{...ctx,fullscreen:true});policy.movePointer(1,0,200,{...ctx,fullscreen:true});assert.equal(policy.endPointer(1,{...ctx,fullscreen:true}).commit,'dismiss-fullscreen');
});

test('browser adapter ignores ordinary wheel/mouse movement and cleans up all listeners',()=>{
  const listeners=new Map(),documentListeners=new Map();
  const view={addEventListener:(name,handler)=>listeners.set(name,handler),removeEventListener:name=>listeners.delete(name),setTimeout,clearTimeout,document:{hidden:false,addEventListener:(name,handler)=>documentListeners.set(name,handler),removeEventListener:name=>documentListeners.delete(name)}};
  let contexts=0,publications=0,commits=0;
  const handle=installNavigationGestures(view,{context:()=>{contexts++;return context();},progress:()=>publications++,commit:()=>commits++});
  for(let i=0;i<100;i++){listeners.get('pointermove')({pointerId:12});listeners.get('pointerdown')({isPrimary:true,pointerType:'mouse'});listeners.get('wheel')({altKey:false});}
  assert.equal(contexts,0);assert.equal(publications,0);assert.equal(commits,0);
  handle.dispose();assert.equal(listeners.size,0);assert.equal(documentListeners.size,0);
});
