import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import vm from 'node:vm';
import {Session} from 'node:inspector';
import {Window} from 'happy-dom';

const source = await readFile(new URL('./diagnose-volume.ps1', import.meta.url), 'utf8');
const probe = source.match(/\$probe = @'\r?\n([\s\S]*?)\r?\n'@/)[1];
function fixture() {
  const window = new Window({url:'http://tauri.localhost'});
  const document = window.document;
  document.body.innerHTML = '<button data-volume-scroll="fullscreen" data-volume-scroll-control><span class="artwork-percentage">50 %</span></button><div data-volume-excluded>private title</div>';
  let hit = document.querySelector('button'), now = 0, nextTimer = 0;
  const timers = new Map(), calls = [];
  const original = function(...args) { calls.push({receiver:this,args}); return Promise.resolve({volume:49,privateUrl:'SECRET-URL',queue:['SECRET-TRACK']}); };
  const ipc = {invoke:original};
  window.__TAURI_INTERNALS__ = ipc;
  document.elementFromPoint = () => hit;
  const context = vm.createContext({window,document,navigator:{userAgent:'Fixture runtime'},Element:window.Element,
    performance:{now:()=>now},queueMicrotask,setTimeout:(fn,ms)=>{timers.set(++nextTimer,{fn,ms});return nextTimer;},clearTimeout:id=>timers.delete(id)});
  assert.equal(vm.runInContext(probe,context),'ready');
  return {window,document,ipc,original,calls,timers,stop:()=>window.__sidebVolumeProbe.stop(),
    afterEvents:()=>{for(const [id,timer] of [...timers])if(timer.ms===0){timers.delete(id);timer.fn();}},
    hit:node=>{hit=node;},advance:ms=>{now+=ms;},wheel:(extra={})=>{
      const event=new window.WheelEvent('wheel',{bubbles:true,cancelable:true,deltaY:60,clientX:20,clientY:20,...extra});
      for (const name of ['ctrlKey','altKey','metaKey','shiftKey']) Object.defineProperty(event,name,{value:extra[name]??false});
      hit.dispatchEvent(event);return event;
    }};
}

test('capture observes cancellation after app handling without consuming wheel or issuing audio commands',async()=>{
  const f=fixture();
  f.wheel(); await Promise.resolve();
  // A microtask checkpoint alone must not publish a premature prevented:false.
  assert.equal(f.timers.size,2);f.afterEvents();
  f.window.addEventListener('wheel',event=>event.preventDefault());
  f.advance(250);f.wheel();await Promise.resolve();f.afterEvents();
  const report=f.stop();
  assert.equal(f.calls.length,0);assert.equal(report.wheels,2);assert.equal(report.audioRequests,0);
  assert.equal(report.entries[0].y,60);assert.equal(report.entries[0].mode,0);
  assert.equal(report.entries[1].prevented,false);assert.equal(report.entries[3].prevented,true);
  assert.equal(f.ipc.invoke,f.original);assert.equal(f.timers.size,0);
});

test('real CDP conditions observe immutable IPC functions without replacing arguments, return values or callbacks',async()=>{
  const f=fixture(),callbacks=new Map(),requests=[];
  function postMessage(message) { requests.push(message);return message; }
  function runCallback(id,data) { return callbacks.get(id)?.(data); }
  Object.defineProperty(f.ipc,'postMessage',{value:postMessage});
  Object.defineProperty(f.ipc,'runCallback',{value:runCallback});
  globalThis.__sidebTestProbe=f.window.__sidebVolumeProbe;
  globalThis.__sidebTestIPC=f.ipc;
  const session=new Session();session.connect();
  const post=(name,args={})=>new Promise((resolve,reject)=>session.post(name,args,(error,result)=>error?reject(error):resolve(result)));
  let pauses=0;session.on('Debugger.paused',()=>{pauses++;session.post('Debugger.resume');});
  try {
    await post('Debugger.enable');
    for(const [name,args] of [['postMessage','arguments[0]'],['runCallback','arguments[0], arguments[1]']]){
      const functionObject=await post('Runtime.evaluate',{expression:`globalThis.__sidebTestIPC.${name}`});
      const condition=`try { globalThis.__sidebTestProbe?.${name==='postMessage'?'request':'confirmed'}?.(${args}); } catch (_) {} false`;
      await post('Debugger.setBreakpointOnFunctionCall',{objectId:functionObject.result.objectId,condition});
    }
    const message={cmd:'set_playback_volume',callback:1,error:2,payload:{volume:49,expectedGeneration:8,privateToken:'SECRET-TOKEN'}};
    const dto={volume:49,privateUrl:'SECRET-URL',queue:['SECRET-TRACK']};
    let delivered;callbacks.set(1,value=>{delivered=value;return value;});
    assert.equal(f.ipc.postMessage(message),message);assert.equal(requests[0],message);
    assert.equal(f.ipc.runCallback(1,dto),dto);assert.equal(delivered,dto);
    f.ipc.postMessage({cmd:'set_playback_volume',callback:3,error:4,payload:{volume:48}});
    f.ipc.runCallback(4,{message:'SECRET-ERROR'});
    f.ipc.postMessage({cmd:'unrelated-command',callback:5,error:6,payload:{secret:'SECRET-OTHER'}});
    const report=f.stop(),serialized=JSON.stringify(report);
    assert.equal(report.audioRequests,2);assert.equal(pauses,0);
    assert.equal(report.entries[1].volume,49);assert.equal(report.entries.at(-1).kind,'audio-rejected');
    assert.equal(serialized.includes('SECRET'),false);assert.equal(serialized.includes('expectedGeneration'),false);
    assert.equal(f.ipc.invoke,f.original);assert.equal(f.ipc.postMessage,postMessage);assert.equal(f.ipc.runCallback,runCallback);
    assert.equal(f.window.__sidebVolumeProbe,undefined);
    const count=report.entries.length;f.ipc.postMessage(message);f.wheel();await Promise.resolve();
    assert.equal(report.entries.length,count);
  } finally {
    await post('Debugger.disable');session.disconnect();
    delete globalThis.__sidebTestProbe;delete globalThis.__sidebTestIPC;
  }
});

test('capture is bounded, expires without terminal cleanup and preserves its report for collection',async()=>{
  const f=fixture();
  for(let i=0;i<500;i++){f.wheel();f.afterEvents();}await Promise.resolve();
  assert.equal(f.timers.size,1);
  const expiry=[...f.timers.values()][0];assert.equal(expiry.ms,120000);expiry.fn();
  assert.equal(f.ipc.invoke,f.original);
  const report=f.stop();assert.equal(report.entries.length,400);assert.equal(report.truncated,true);
  assert.equal(f.window.__sidebVolumeProbe,undefined);
});
