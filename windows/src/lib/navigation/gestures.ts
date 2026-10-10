/**
 * WebView2 WheelEvent has no contact/momentum phases. Ordinary wheel scrolling
 * therefore NEVER navigates. Alt + horizontal wheel is an explicit alternative,
 * grouped by 180 ms of silence and latched until Alt is released. This grouping
 * is not a claim about Precision Touchpad contact boundaries.
 * Touch/pen pull uses real PointerEvent capture/end/cancel, from an explicitly
 * marked non-scroll surface. Hardware gesture parity remains unverified.
 */
export type GestureAction='back'|'forward'|'dismiss-fullscreen';
export type GestureOwner='history'|'local'|'excluded';
export interface GestureContext {
  revision:string|number; enabled:boolean; blocked:boolean; fullscreen:boolean;
  reduceMotion:boolean; height:number; backTitle:string|null; forwardTitle:string|null;
}
export interface GestureProgress {
  action:GestureAction|null; title:string|null; phase:'idle'|'tracking'|'armed'|'committed'|'cancelled';
  distance:number; progress:number; available:boolean;
}
export interface GestureOutput {consume:boolean;progress:GestureProgress;commit?:GestureAction}
export const idleGesture=():GestureProgress=>({action:null,title:null,phase:'idle',distance:0,progress:0,available:false});
type WheelSample={x:number;y:number;at:number;alt:boolean;ctrl:boolean;pixels:boolean;owner:GestureOwner};
const finite=(value:number)=>Number.isFinite(value)?value:0;
const blocked=(context:GestureContext)=>!context.enabled||context.blocked;
const changed=(before:GestureContext,after:GestureContext)=>before.revision!==after.revision||before.fullscreen!==after.fullscreen||before.height!==after.height||blocked(after);

/** Pure observable policy; no browser, timers, provider calls or native phases. */
export class NavigationGesturePolicy {
  private wheel: {owner:GestureOwner;context:GestureContext;x:number;y:number;at:number;claimed:boolean;invalid:boolean}|null=null;
  private latched=false;
  private pointer:{id:number;x:number;y:number;context:GestureContext;invalid:boolean;claimed:boolean}|null=null;
  private progress=idleGesture();
  private output(consume=false,commit?:GestureAction):GestureOutput {return{consume,progress:{...this.progress},...(commit?{commit}:{})};}
  cancel():GestureOutput {
    const consume=Boolean(this.wheel?.claimed||this.pointer?.claimed);
    if(this.wheel?.claimed)this.latched=true;
    this.wheel=null;if(this.pointer)this.pointer.invalid=true;
    this.progress={...this.progress,phase:'cancelled',progress:0};return this.output(consume);
  }
  reset():GestureOutput {this.wheel=null;this.pointer=null;this.latched=false;this.progress=idleGesture();return this.output();}
  startAlt():void {this.wheel=null;this.latched=false;this.progress=idleGesture();}
  wheelEvent(event:WheelSample,context:GestureContext):GestureOutput {
    if(!event.alt||event.ctrl||!event.pixels) return this.output();
    if(!this.wheel)this.wheel={owner:event.owner,context:{...context},x:0,y:0,at:event.at,claimed:false,invalid:false};
    const contact=this.wheel;contact.at=event.at;
    if(changed(contact.context,context))contact.invalid=true;
    // Ownership is captured once, including local shelves at their edges.
    if(contact.owner!=='history'||context.fullscreen||contact.invalid||blocked(context))return this.output(contact.claimed);
    if(this.latched)return this.output(true);
    contact.x+=finite(event.x);contact.y+=finite(event.y);
    if(!contact.claimed&&Math.abs(contact.y)>10&&Math.abs(contact.y)>Math.abs(contact.x)*1.35){contact.owner='local';return this.output();}
    if(!contact.claimed&&(Math.abs(contact.x)<10||Math.abs(contact.x)<Math.abs(contact.y)*1.35))return this.output();
    contact.claimed=true;
    const action=contact.x>0?'back':'forward';const title=action==='back'?context.backTitle:context.forwardTitle;
    const distance=Math.abs(contact.x),available=title!==null;
    const wasArmed=this.progress.phase==='armed'&&this.progress.action===action;
    const armed=available&&distance>=(wasArmed?64*.72:64);
    this.progress={action,title,phase:armed?'armed':'tracking',distance,progress:Math.min(1,distance/64),available};
    return this.output(true);
  }
  /** Called after the quiet interval, not a fabricated physical contact end. */
  settleWheel(context:GestureContext):GestureOutput {
    const contact=this.wheel;this.wheel=null;
    if(!contact)return this.output();
    if(contact.invalid||changed(contact.context,context)||this.latched||this.progress.phase!=='armed'||!contact.claimed){this.progress=idleGesture();return this.output(contact.claimed);}
    this.latched=true;this.progress={...this.progress,phase:'committed'};return this.output(true,this.progress.action!);
  }
  releaseAlt(context:GestureContext):GestureOutput {const result=this.settleWheel(context);this.latched=false;return result;}
  beginPointer(id:number,x:number,y:number,type:string,eligible:boolean,context:GestureContext):GestureOutput {
    if(!eligible||!['touch','pen'].includes(type)||!context.fullscreen||blocked(context))return this.output();
    this.pointer={id,x,y,context:{...context},invalid:false,claimed:false};this.progress=idleGesture();return this.output(true);
  }
  movePointer(id:number,x:number,y:number,context:GestureContext):GestureOutput {
    const pointer=this.pointer;if(!pointer||pointer.id!==id)return this.output();
    if(changed(pointer.context,context))pointer.invalid=true;
    if(pointer.invalid)return this.output(true);
    const dx=finite(x-pointer.x),dy=finite(y-pointer.y);
    if(!pointer.claimed&&Math.abs(dx)>10&&Math.abs(dx)>Math.abs(dy)*1.35){pointer.invalid=true;return this.output(true);}
    if(!pointer.claimed&&dy < -10){pointer.invalid=true;return this.output(true);}
    if(!pointer.claimed&&(dy<10||dy<Math.abs(dx)*1.35))return this.output(true);
    pointer.claimed=true;
    const distance=Math.max(0,dy),threshold=Math.min(160,Math.max(100,context.height*.23));
    const armed=distance>=(this.progress.phase==='armed'?threshold*.72:threshold);
    this.progress={action:'dismiss-fullscreen',title:null,phase:armed?'armed':'tracking',distance,progress:Math.min(1,distance/threshold),available:true};
    return this.output(true);
  }
  endPointer(id:number,context:GestureContext,cancelled=false):GestureOutput {
    const pointer=this.pointer;if(!pointer||pointer.id!==id)return this.output();this.pointer=null;
    if(cancelled||pointer.invalid||changed(pointer.context,context)||this.progress.phase!=='armed'){this.progress={...this.progress,phase:'cancelled',progress:0};return this.output(true);}
    this.progress={...this.progress,phase:'committed'};return this.output(true,'dismiss-fullscreen');
  }
}

export interface GestureHooks {context:()=>GestureContext;progress:(state:GestureProgress)=>void;commit:(action:GestureAction)=>void}

function ownerFor(target:EventTarget|null):GestureOwner {
  if(!(target instanceof Element))return 'excluded';
  if(target.closest('[data-gesture-local],.card-shelf,.mode-tabs,.chips,.featured-pages,[role="slider"]'))return 'local';
  if(target.closest('[data-gesture-excluded],input,textarea,select,button,a,[contenteditable="true"],[role="menu"],[role="dialog"]'))return 'excluded';
  return 'history';
}
function pullSurface(target:EventTarget|null):HTMLElement|null {
  if(!(target instanceof Element)||ownerFor(target)!=='history')return null;
  const surface=target.closest<HTMLElement>('[data-gesture-pull]');if(!surface)return null;
  // A scrollable ancestor always owns vertical input, even at its edge.
  for(let node:Element|null=target;node;node=node.parentElement){
    const style=getComputedStyle(node);
    if(/auto|scroll/.test(style.overflowY)&&node.scrollHeight>node.clientHeight+1)return null;
    if(node===surface)break;
  }
  return surface;
}

/** Root calls invalidate() on route/session/modal changes, and dispose() on teardown. */
export function installNavigationGestures(view:Window,hooks:GestureHooks) {
  const policy=new NavigationGesturePolicy();let timer:number|null=null;let captured:HTMLElement|null=null;let pointerId:number|null=null;
  let published=idleGesture();
  const apply=(output:GestureOutput)=>{
    const next=output.progress;
    if(next.action!==published.action||next.title!==published.title||next.phase!==published.phase||next.distance!==published.distance||next.progress!==published.progress||next.available!==published.available){published={...next};hooks.progress(next);}
    if(output.commit)hooks.commit(output.commit);
  };
  const clear=()=>{if(timer!==null)view.clearTimeout(timer);timer=null;};
  const invalidate=()=>{clear();apply(policy.cancel());};
  const resetForFocus=()=>{clear();apply(policy.reset());const previous=captured,id=pointerId;captured=null;pointerId=null;if(previous&&id!==null&&previous.hasPointerCapture(id))previous.releasePointerCapture(id);};
  const wheel=(event:WheelEvent)=>{
    if(!event.altKey||event.ctrlKey||event.deltaMode!==0)return;
    const result=policy.wheelEvent({x:event.deltaX,y:event.deltaY,at:event.timeStamp,alt:event.altKey,ctrl:event.ctrlKey,pixels:event.deltaMode===0,owner:ownerFor(event.target)},hooks.context());
    if(result.consume&&event.cancelable)event.preventDefault();apply(result);
    if(event.altKey){clear();timer=view.setTimeout(()=>{timer=null;apply(policy.settleWheel(hooks.context()));},180);}
  };
  const keyup=(event:KeyboardEvent)=>{if(event.key==='Alt'){clear();apply(policy.releaseAlt(hooks.context()));}};
  const keydown=(event:KeyboardEvent)=>{if(event.key==='Alt'&&!event.repeat){clear();policy.startAlt();}};
  const down=(event:PointerEvent)=>{
    if(!event.isPrimary||!['touch','pen'].includes(event.pointerType))return;const surface=pullSurface(event.target);if(!surface)return;const result=policy.beginPointer(event.pointerId,event.clientX,event.clientY,event.pointerType,true,hooks.context());
    if(result.consume&&surface){captured=surface;pointerId=event.pointerId;surface.setPointerCapture(event.pointerId);if(event.cancelable)event.preventDefault();apply(result);}
  };
  const move=(event:PointerEvent)=>{if(event.pointerId!==pointerId)return;const result=policy.movePointer(event.pointerId,event.clientX,event.clientY,hooks.context());if(result.consume&&event.cancelable)event.preventDefault();apply(result);};
  const end=(event:PointerEvent)=>{if(event.pointerId!==pointerId)return;const result=policy.endPointer(event.pointerId,hooks.context(),event.type!=='pointerup');const previous=captured;captured=null;pointerId=null;apply(result);if(previous?.hasPointerCapture(event.pointerId))previous.releasePointerCapture(event.pointerId);};
  const visibility=()=>{if(view.document.hidden)resetForFocus();};
  view.addEventListener('wheel',wheel,{passive:false});view.addEventListener('keyup',keyup);view.addEventListener('keydown',keydown);view.addEventListener('blur',resetForFocus);view.addEventListener('resize',invalidate);view.document.addEventListener('visibilitychange',visibility);
  view.addEventListener('pointerdown',down);view.addEventListener('pointermove',move);view.addEventListener('pointerup',end);view.addEventListener('pointercancel',end);view.addEventListener('lostpointercapture',end);
  return {invalidate,dispose(){resetForFocus();view.removeEventListener('wheel',wheel);view.removeEventListener('keyup',keyup);view.removeEventListener('keydown',keydown);view.removeEventListener('blur',resetForFocus);view.removeEventListener('resize',invalidate);view.document.removeEventListener('visibilitychange',visibility);view.removeEventListener('pointerdown',down);view.removeEventListener('pointermove',move);view.removeEventListener('pointerup',end);view.removeEventListener('pointercancel',end);view.removeEventListener('lostpointercapture',end);}};
}
