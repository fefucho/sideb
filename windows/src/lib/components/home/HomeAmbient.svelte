<script lang="ts" module>
  let smoke: Promise<string> | null = null;
  function smokeTexture() {
    if (smoke) return smoke;
    smoke = new Promise<string>(resolve => {
      const worker = new Worker(new URL('../../home/smoke.worker.ts',import.meta.url),{type:'module'});
      worker.onmessage = ({data}) => {
        const source=document.createElement('canvas'); source.width=data.width; source.height=data.height;
        source.getContext('2d')!.putImageData(new ImageData(data.pixels,data.width,data.height),0,0);
        const canvas=document.createElement('canvas'); canvas.width=data.width; canvas.height=data.height;
        const ctx=canvas.getContext('2d')!;
        // Bake softness into this small, shared bitmap. No filter on animated layers.
        ctx.filter='blur(5px)'; ctx.drawImage(source,0,0);
        worker.terminate(); resolve(canvas.toDataURL());
      };
      worker.onerror = () => { worker.terminate(); smoke=null; resolve(''); };
      worker.postMessage({});
    });
    return smoke;
  }
</script>
<script lang="ts">
  import { onMount } from 'svelte';
  import { choosePalette, collectionAmbientFrame, type RGB } from '$lib/home/ambient';
  import { fallbackArtworkUrl } from '$lib/images/artwork';
  let { artwork, session, active = true, collection = false }: { artwork: string[]; session: string; active?: boolean; collection?: boolean } = $props();
  let palette = $state<[RGB,RGB]>(choosePalette([])); let mask=$state(''); let awake=$state(false); let reduced=$state(false); let phase=$state(0);
  let inViewport=$state(true);let measurePosition=()=>{};
  let ambientTop=$state<number|null>(null);let ambientHeight=$state<number|null>(null);let geometryReady=$state(false);
  let worker: Worker | null=null; let generation=0; let cache=new Map<string,Uint8ClampedArray>(); let cacheSession='';
  async function pixels(url: string) {
    if (cache.has(url)) { const value=cache.get(url)!;cache.delete(url);cache.set(url,value);return value; }
    const account = cacheSession;
    const image=new Image(); image.crossOrigin='anonymous'; image.src=fallbackArtworkUrl(url,32)??url; await image.decode();
    const canvas=document.createElement('canvas'); canvas.width=canvas.height=32; const ctx=canvas.getContext('2d')!;
    ctx.drawImage(image,0,0,32,32); const value=ctx.getImageData(0,0,32,32).data; if (account === cacheSession) cache.set(url,value);
    while(cache.size>64) cache.delete(cache.keys().next().value!); return value;
  }
  $effect(() => {
    const urls=[...artwork], account=session, visible=active; const current=++generation;
    if (cacheSession!==account) { cache.clear(); cacheSession=account; palette=choosePalette([]); }
    if (!worker || !visible) return;
    void Promise.allSettled(urls.map(pixels)).then(results => {
      if(current!==generation || account!==cacheSession) return;
      worker?.postMessage({ generation:current, pixels:results.flatMap(r => r.status==='fulfilled' ? [r.value] : []) });
    });
  });
  function position(node:HTMLDivElement) {
    let frame=0;let disposed=false;
    const root=document.querySelector<HTMLElement>('.content-column');
    let observedHeader:HTMLElement|null=null;
    const update=()=>{
      if(disposed)return;
      if(!collection){ambientTop=null;ambientHeight=null;geometryReady=true;if(observedHeader)resize.unobserve(observedHeader);observedHeader=null;inViewport=true;return;}
      if(!active){inViewport=false;return;}
      const header=root?.querySelector<HTMLElement>('.collection-header')??null;
      if(header!==observedHeader){if(observedHeader)resize.unobserve(observedHeader);observedHeader=header;if(header)resize.observe(header);}
      if(!header||!root){geometryReady=false;inViewport=false;return;}
      const box=header.getBoundingClientRect();
      const bounds=collectionAmbientFrame(box.top,box.height,root.scrollTop,window.innerHeight,node.parentElement?.getBoundingClientRect().top??0);
      ambientTop=bounds.top;ambientHeight=bounds.height;geometryReady=true;
      inViewport=bounds.visible;
    };
    const schedule=()=>{if(!frame&&!disposed)frame=requestAnimationFrame(()=>{frame=0;update();});};
    measurePosition=schedule;
    const resize=new ResizeObserver(schedule);if(root)resize.observe(root);
    const mutation=new MutationObserver(schedule);if(root)mutation.observe(root,{childList:true,subtree:true});
    root?.addEventListener('scroll',schedule,{passive:true});window.addEventListener('resize',schedule);schedule();
    return {destroy(){disposed=true;cancelAnimationFrame(frame);resize.disconnect();mutation.disconnect();root?.removeEventListener('scroll',schedule);window.removeEventListener('resize',schedule);measurePosition=()=>{};}};
  }
  $effect(()=>{active;collection;measurePosition();});
  function swing(cycle:number,amplitude:number,shift=0){return Math.sin(phase*2*Math.PI/cycle+shift)*amplitude;}
  function cosine(cycle:number,amplitude:number,shift=0){return Math.cos(phase*2*Math.PI/cycle+shift)*amplitude;}
  $effect(()=>{
    if(!awake||reduced||!active||!inViewport)return;
    let last=performance.now();let frame=0;
    const tick=(now:number)=>{if(now-last>=1000/30){phase+=(now-last)/1000;last=now;}frame=requestAnimationFrame(tick);};
    frame=requestAnimationFrame(tick);return()=>cancelAnimationFrame(frame);
  });
  onMount(() => {
    let mounted=true;
    void smokeTexture().then(value=>{if(mounted)mask=value;}); worker=new Worker(new URL('../../home/ambient.worker.ts',import.meta.url),{type:'module'});
    worker.onmessage=event => { if(event.data.generation===generation) palette=event.data.palette; };
    // Trigger initial sample after creating the worker.
    const current=++generation; const account=session;
    if(active)void Promise.allSettled(artwork.map(pixels)).then(results => { if(current===generation && account===cacheSession) worker?.postMessage({generation:current,pixels:results.flatMap(r => r.status==='fulfilled' ? [r.value] : [])}); });
    const media=window.matchMedia('(prefers-reduced-motion:reduce)');const reduce=()=>reduced=media.matches;reduce();media.addEventListener('change',reduce);
    const sync=() => awake=!document.hidden && document.hasFocus(); sync();
    document.addEventListener('visibilitychange',sync); window.addEventListener('blur',sync); window.addEventListener('focus',sync);
    return () => { mounted=false; generation++; worker?.terminate(); worker=null; cache.clear(); media.removeEventListener('change',reduce); document.removeEventListener('visibilitychange',sync); window.removeEventListener('blur',sync); window.removeEventListener('focus',sync); };
  });
</script>
<div use:position class="ambient" class:awake={awake&&active} class:collection class:inactive={collection&&!active} class:ready={Boolean(mask)} style:top={ambientTop===null?undefined:`${ambientTop}px`} style:height={ambientHeight===null?undefined:`${ambientHeight}px`} style:visibility={collection&&!geometryReady?'hidden':undefined} style={`--left:rgb(${palette[0].join(' ')});--right:rgb(${palette[1].join(' ')});--mask:url('${mask}');--a:translate(${swing(42,11)}cqw,${cosine(52.5,11)}cqh);--b:translate(${swing(50,11,2)}cqw,${cosine(62.5,11,1.6)}cqh);--c:translate(${swing(36,15,4)}cqw,${cosine(45,15,3.2)}cqh);--cloud-a:translate(${swing(45,11)}cqw,${cosine(56,6)}cqh) rotate(${swing(70,3.5)}deg);--cloud-b:translate(${cosine(65,14,1)}cqw,${swing(78,8,2)}cqh) rotate(${cosine(88,4.5)}deg) scaleX(-1)`} aria-hidden="true">
  <div class="light a"></div><div class="light b"></div><div class="light c"></div><div class="smoke first"></div><div class="smoke second"></div><div class="shade"></div>
</div>
<style>
  @property --left { syntax:'<color>'; inherits:true; initial-value:rgb(60 84 122); }
  @property --right { syntax:'<color>'; inherits:true; initial-value:rgb(102 77 132); }
  .ambient { position:fixed; inset:0 0 0 var(--sidebar-width); container-type:size; --extent:max(100cqw,100cqh); pointer-events:none; z-index:0; overflow:hidden; background:#111318; transition:--left 1s,--right 1s; }
  .collection { inset:0; height:540px; background:transparent; mask-image:linear-gradient(#000 60%,transparent); }
  .collection.inactive { visibility:hidden; }
  .collection .a {opacity:.58;} .collection .b {opacity:.50;} .collection .first {opacity:.86;} .collection .second {opacity:.8;}
  .light { position:absolute; aspect-ratio:1; mix-blend-mode:screen; border-radius:50%; background:radial-gradient(circle closest-side,color-mix(in srgb,var(--tint) 100%,transparent),color-mix(in srgb,var(--tint) 74%,transparent) 32%,color-mix(in srgb,var(--tint) 23%,transparent) 70%,transparent); }
  .a { --tint:var(--left); width:calc(var(--extent)*1.24); left:calc(6cqw - var(--extent)*.62); top:calc(2cqh - var(--extent)*.62); opacity:.46; transform:var(--a); }
  .b { --tint:var(--right); width:calc(var(--extent)*1.16); left:calc(94cqw - var(--extent)*.58); top:calc(18cqh - var(--extent)*.58); opacity:.42; transform:var(--b); }
  .c { --tint:var(--left); width:calc(var(--extent)*.84); left:calc(43cqw - var(--extent)*.42); top:calc(73cqh - var(--extent)*.42); opacity:.16; transform:var(--c); }
  .smoke { position:absolute; inset:-25%; mask-image:var(--mask); mask-size:100% 100%; background:linear-gradient(to bottom right,color-mix(in srgb,var(--left) 40.6%,transparent),color-mix(in srgb,var(--right) 35%,transparent)); opacity:0; transition:opacity .5s; mix-blend-mode:screen; transform:var(--cloud-a); }
  .ready .smoke { opacity:1; } .second { inset:-37.5%; background:linear-gradient(to bottom right,color-mix(in srgb,var(--left) 26.1%,transparent),color-mix(in srgb,var(--right) 22.5%,transparent)); transform:var(--cloud-b); }
  .awake .light,.awake .smoke { will-change:transform; }
  .shade { position:absolute; inset:0; background:linear-gradient(transparent,#00000014 42%,#00000075); }
  @media (prefers-reduced-motion:reduce) { .ambient,.smoke { transition:none; } .awake .light,.awake .smoke { will-change:auto; } }
</style>
