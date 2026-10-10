import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const source = await readFile(new URL('../src/lib/genius/popover.ts', import.meta.url), 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { annotationPlacement, annotationAnchorVisible, annotationVisibleRect } = await import(`data:text/javascript;base64,${Buffer.from(js).toString('base64')}`);
const rect = (left, top, width = 160, height = 28) => ({ left, top, right: left + width, bottom: top + height, width, height });

test('annotation prefers trailing arrow pointing to the selected line without sidebar offset', () => {
  const anchor = rect(810, 240), viewport = { width: 1280, height: 800 };
  const popup = annotationPlacement(anchor, 300, viewport);
  assert.equal(popup.arrowSide, 'right');
  assert.equal(popup.left + popup.width + 10, anchor.left);
  assert.equal(popup.top + popup.arrowOffset, (anchor.top + anchor.bottom) / 2);
  assert.ok(popup.left >= 16 && popup.top >= 16);
});
test('annotation follows an anchor moved by scroll or resize and clamps at viewport edges', () => {
  const viewport = { width: 1100, height: 650 };
  const first = annotationPlacement(rect(700, 200), 300, viewport);
  const moved = annotationPlacement(rect(650, 280), 300, viewport);
  assert.equal(moved.left, first.left - 50);
  assert.equal(moved.top, first.top + 80);
  const bottom = annotationPlacement(rect(650, 610), 300, viewport);
  assert.equal(bottom.top + 300, viewport.height - 16);
  const arrowTip = bottom.top + bottom.arrowOffset;
  assert.ok(arrowTip >= 610 && arrowTip <= 638, 'rounded corner clamp still points inside selected line');
});
test('annotation flips right or vertically on narrow windows, retaining a line-pointing arrow', () => {
  const right = annotationPlacement(rect(30, 200, 80), 300, { width: 1000, height: 700 });
  assert.equal(right.arrowSide, 'left'); assert.equal(right.left, 120);
  const belowAnchor = rect(40, 80, 150), below = annotationPlacement(belowAnchor, 300, { width: 360, height: 640 });
  assert.equal(below.arrowSide, 'top'); assert.equal(below.top, belowAnchor.bottom + 10);
  assert.equal(below.left + below.arrowOffset, 115); assert.equal(below.width, 328);
  const aboveAnchor = rect(60, 550, 180), above = annotationPlacement(aboveAnchor, 300, { width: 360, height: 640 });
  assert.equal(above.arrowSide, 'bottom'); assert.equal(above.top + 300 + 10, aboveAnchor.top);
  assert.equal(above.left + above.arrowOffset, 150);
});
test('annotation closes when the selected line leaves its scroll panel or viewport', () => {
  const viewport = { width: 1200, height: 800 }, panel = rect(700, 100, 400, 550);
  assert.equal(annotationAnchorVisible(rect(720, 120), viewport, panel), true);
  assert.equal(annotationAnchorVisible(rect(720, 70, 160, 20), viewport, panel), false);
  assert.equal(annotationAnchorVisible(rect(720, 680), viewport, panel), false);
  assert.equal(annotationAnchorVisible(rect(1250, 200), viewport), false);
  assert.equal(annotationAnchorVisible(rect(720, 200, 0, 0), viewport, panel), false);
  assert.equal(annotationAnchorVisible(rect(720, 90, 160, 28), viewport, panel), true);
  const visible = annotationVisibleRect(rect(720, 90, 160, 28), viewport, panel);
  const popup = annotationPlacement(visible, 300, viewport);
  assert.equal(popup.top + popup.arrowOffset, 109, 'arrow points into the visible portion of a clipped line');
});

// Run the actual component's async event functions with a delayed controller response.
const component = await readFile(new URL('../src/lib/components/fullscreen/GeniusPanel.svelte', import.meta.url), 'utf8');
const script = component.match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
const ast = ts.createSourceFile('GeniusPanel.ts', script, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
const functions = ast.statements.filter(node => ts.isFunctionDeclaration(node) && ['showAnnotation', 'cancelPendingAnnotation', 'closeAnnotation', 'annotationKey', 'cancelMovingRequest'].includes(node.name?.text)).map(node => node.getText(ast)).join('\n');
const harnessCode = ts.transpileModule(`export function createHarness(controller, window) {
  let annotationRequest=0, pendingAnchor=null, anchor=null, selected=null, anchorRectIndex=0, trackKey='track';
  const geniusState={annotations:[{id:7,referentId:7}]};
  ${functions}
  return {showAnnotation,cancelPendingAnnotation,closeAnnotation,annotationKey,cancelMovingRequest,state:()=>({selected,anchor,anchorRectIndex}),changeTrack:()=>trackKey='other'};
}`, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { createHarness } = await import(`data:text/javascript;base64,${Buffer.from(harnessCode).toString('base64')}`);
const deferred = () => { let resolve; const promise = new Promise(done => resolve = done); return { promise, resolve }; };
const trigger = () => ({ isConnected: true, focused: false, closest:()=>null, focus() { this.focused = true; }, getClientRects: () => [rect(700, 200), rect(700, 229)] });
const click = (button, y = 210) => ({ currentTarget: button, detail: 1, clientX: 740, clientY: y });

test('outside pointer cancels a pending annotation before the controller returns', async () => {
  const task = deferred(), button = trigger();
  const harness = createHarness({ ensureAnnotation: () => task.promise }, { getSelection: () => null });
  const opening = harness.showAnnotation(7, click(button));
  harness.cancelPendingAnnotation({ composedPath: () => [{}] }); task.resolve(); await opening;
  assert.equal(harness.state().selected, null);
});
test('trigger clicks are retained and multi-line annotation anchors the exact clicked line', async () => {
  const task = deferred(), button = trigger();
  const harness = createHarness({ ensureAnnotation: () => task.promise }, { getSelection: () => null });
  const opening = harness.showAnnotation(7, click(button, 240));
  harness.cancelPendingAnnotation({ composedPath: () => [button] }); task.resolve(); await opening;
  assert.equal(harness.state().selected.id, 7); assert.equal(harness.state().anchorRectIndex, 1);
  harness.closeAnnotation(false); assert.equal(button.focused, false, 'outside dismissal preserves focus of clicked control');
});
test('pending annotation retains the clicked fragment before async work and cancels when content moves', async()=>{
  const task=deferred(),button=trigger();
  const harness=createHarness({ensureAnnotation:()=>task.promise},{getSelection:()=>null});
  const opening=harness.showAnnotation(7,click(button,240));button.getClientRects=()=>[rect(700,100),rect(700,129)];task.resolve();await opening;
  assert.equal(harness.state().anchorRectIndex,1);
  const later=deferred(),cancelled=createHarness({ensureAnnotation:()=>later.promise},{getSelection:()=>null});
  const request=cancelled.showAnnotation(7,click(button,140));cancelled.cancelMovingRequest();later.resolve();await request;
  assert.equal(cancelled.state().selected,null);
});
test('inline annotation activates by Enter/Space once and keyboard anchors its visible fragment',async()=>{
  const button=trigger();let clicks=0;button.click=()=>clicks++;
  const harness=createHarness({ensureAnnotation:async()=>{}},{getSelection:()=>null,innerHeight:600});
  for(const key of ['Enter',' ']){let prevented=0,stopped=0;harness.annotationKey({key,currentTarget:button,preventDefault:()=>prevented++,stopPropagation:()=>stopped++});assert.equal(prevented,1);assert.equal(stopped,1);}
  harness.annotationKey({key:' ',repeat:true,currentTarget:button,preventDefault(){},stopPropagation(){}});assert.equal(clicks,2);
  button.getClientRects=()=>[rect(700,-40),rect(700,10)];
  await harness.showAnnotation(7,{currentTarget:button,detail:0});assert.equal(harness.state().anchorRectIndex,1);
});
test('annotation ignores text selection and stale track responses, explicit close restores trigger focus', async () => {
  const button = trigger(); let requests = 0;
  const selecting = createHarness({ ensureAnnotation: async () => requests++ }, { getSelection: () => ({ isCollapsed: false, containsNode: () => true }) });
  await selecting.showAnnotation(7, click(button)); assert.equal(requests, 0);
  const task = deferred();
  const changed = createHarness({ ensureAnnotation: () => task.promise }, { getSelection: () => null });
  const pending = changed.showAnnotation(7, click(button)); changed.changeTrack(); task.resolve(); await pending;
  assert.equal(changed.state().selected, null);
  const opened = createHarness({ ensureAnnotation: async () => {} }, { getSelection: () => null });
  await opened.showAnnotation(7, click(button)); opened.closeAnnotation(); assert.equal(button.focused, true);
});

test('artwork/info keyboard context menu remains available after removing the ellipsis button', async () => {
  const fullscreen = await readFile(new URL('../src/lib/components/fullscreen/FullscreenNowPlaying.svelte', import.meta.url), 'utf8');
  const ast = ts.createSourceFile('Fullscreen.ts', fullscreen.match(/<script lang="ts">([\s\S]*?)<\/script>/)[1], ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  const handler = ast.statements.find(node => ts.isFunctionDeclaration(node) && node.name?.text === 'trackMenuKey');
  const js = ts.transpileModule(`export function harness(currentTrack,onOpenMenu){${handler.getText(ast)};return trackMenuKey;}`, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
  const { harness } = await import(`data:text/javascript;base64,${Buffer.from(js).toString('base64')}`);
  const opened = [], event = (key, shiftKey = false) => ({ key, shiftKey, prevented: false, stopped: false, preventDefault() {this.prevented=true;}, stopPropagation() {this.stopped=true;} });
  const handle = harness({videoId:'track'}, e=>opened.push(e));
  const menuKey = event('ContextMenu'), shiftF10 = event('F10',true), plainF10 = event('F10');
  handle(menuKey);handle(shiftF10);handle(plainF10);
  assert.deepEqual(opened,[menuKey,shiftF10]);assert.equal(menuKey.prevented,true);assert.equal(shiftF10.stopped,true);assert.equal(plainF10.prevented,false);
  harness(null,e=>opened.push(e))(event('ContextMenu'));assert.equal(opened.length,2);
});
