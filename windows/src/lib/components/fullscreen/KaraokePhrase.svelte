<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import type { PreparedLine } from '$lib/player/karaoke';
  import type { KaraokeClock } from '$lib/player/karaoke-clock';
  interface Props {
    line: PreparedLine; clock: KaraokeClock; enabled: boolean; offset: number; geometry: string;
    motion?: boolean; reduced?: boolean;
  }
  let { line, clock, enabled, offset, geometry, motion = true, reduced = false }: Props = $props();
  const instanceId = $props.id();
  const id = instanceId.replaceAll(':', '-');
  let host: HTMLSpanElement, base: HTMLSpanElement, definitions: SVGDefsElement, effects: HTMLSpanElement;
  let visible = false, mounted = false, disposed = false;
  let unsubscribe: (() => void) | undefined;
  const svg = 'http://www.w3.org/2000/svg';
  type Fragment = {
    rect: SVGRectElement; movingRect: SVGRectElement; hole: SVGRectElement;
    gradient: SVGLinearGradientElement; clipId: string; maskId: string;
    effect?: HTMLSpanElement; glow?: HTMLSpanElement;
    wordIndex: number; origin: string; anchorWidth: number; maximumScale: number;
    x: number; y: number; width: number; height: number; before: number; total: number; rtl: boolean;
  };
  type Word = { start: number; end: number; fragments: Fragment[]; progress: number };
  let words: Word[] = [];
  let measurement: number | undefined;
  const smooth = (n: number) => { const v = Math.min(1, Math.max(0, n)); return v * v * (3 - 2 * v); };

  function paint(ms: number): boolean {
    if (!visible || disposed) return false;
    ms += offset;
    host.classList.toggle('voice-active',line.start!==null&&line.end!==null&&ms>=line.start&&ms<line.end);
    if(!enabled)return false;
    let changing = false;
    for (const word of words) {
      const progress = Math.min(1, Math.max(0, (ms - word.start) / (word.end - word.start)));
      // An exact start boundary must wake the first sweep even at zero fill.
      const active = ms >= word.start && ms < word.end;
      if (word.progress === progress && !active) continue;
      const animated = active && motion && !reduced;
      const duration = word.end - word.start;
      const envelope = smooth((ms - word.start) / Math.min(240, duration * .24)) * smooth((word.end - ms) / Math.min(280, duration * .28));
      const sustain = smooth((duration - 700) / 1000) * envelope;
      for (const f of word.fragments) {
        if (word.progress !== progress) {
          const feather = Math.min(30, f.total / 2);
          const edge = progress * (f.total + feather) - f.before;
          // One continuous advance across native shaped/wrapped fragments.
          f.gradient.setAttribute('x1', String(f.rtl ? f.x + f.width - edge : f.x + edge - feather));
          f.gradient.setAttribute('x2', String(f.rtl ? f.x + f.width - edge + feather : f.x + edge));
          for (const rect of [f.rect, f.movingRect]) {
            rect.setAttribute('fill', progress >= 1 ? 'white' : `url(#${f.gradient.id})`);
            rect.setAttribute('opacity', progress <= 0 ? '0' : '1');
          }
        }
        // Transfer BOTH inks out of the stationary phrase before moving them.
        // Leaving either underneath produces a second, offset set of glyphs.
        f.hole.setAttribute('opacity', animated ? '1' : '0');
        f.rect.setAttribute('opacity', animated || progress <= 0 ? '0' : '1');
        if (animated) {
          if (!f.effect) {
            const layer = document.createElement('span'); layer.className = 'word-effect';
            const fragment = document.createElement('span'); fragment.className = 'word-fragment';
            fragment.style.clipPath = `url(#${f.clipId})`;
            const dim = document.createElement('span'); dim.className = 'word-highlight word-base'; dim.textContent = line.text;
            const lit = document.createElement('span'); lit.className = 'word-highlight'; lit.textContent = line.text;
            const fill = document.createElement('span'); fill.className = 'word-fragment'; fill.style.clipPath = fragment.style.clipPath;
            const glow = document.createElement('span'); glow.className = 'word-glow';
            lit.style.mask = `url(#${f.maskId})`;
            fragment.append(dim); fill.append(lit); glow.append(fill); layer.append(fragment, glow); effects.append(layer); f.effect = layer; f.glow = glow;
            // Mac anchors each visual line at its bottom, never at the union of
            // a word's rectangles on different lines.
            layer.style.transformOrigin = f.origin;
          }
          // 24px drawing room minus twice the 5px glow radius, as on Mac.
          const scale = Math.min(1 + .13 * sustain, f.maximumScale, 1 + 14 / Math.max(1, f.anchorWidth / 2));
          f.effect.style.transform = `translateY(${-2 * sustain}px) scale(${scale})`;
          f.glow!.style.filter = `drop-shadow(0 0 5px rgb(255 255 255 / ${.28 * envelope}))`;
        } else if (f.effect) { f.effect.remove(); f.effect = undefined; f.glow = undefined; }
      }
      word.progress = progress;
      changing ||= active;
    }
    return changing;
  }
  function measure() {
    measurement = undefined;
    if (!mounted || disposed || !visible || !host || !base || !definitions || !effects) return;
    base.style.mask = ''; definitions.replaceChildren(); effects.replaceChildren(); words = [];
    if (!enabled || !line.segments?.length) return;
    const node = base.firstChild;
    if (!node || node.nodeType !== Node.TEXT_NODE) return;
    // offsetWidth excludes the ancestor's context scale. Divide screen-space
    // ranges by that scale before storing local drawing geometry.
    const bounds = host.getBoundingClientRect();
    const scale = host.offsetWidth > 0 ? bounds.width / host.offsetWidth : 1;
    const unit = Number.isFinite(scale) && scale > 0 ? scale : 1;
    const makeMask = (suffix: string) => {
      const mask = document.createElementNS(svg, 'mask'); mask.id = `${id}-${suffix}`;
      mask.setAttribute('maskUnits', 'userSpaceOnUse'); mask.setAttribute('maskContentUnits', 'userSpaceOnUse');
      mask.setAttribute('x', '-30'); mask.setAttribute('y', '-24');
      mask.setAttribute('width', String(host.offsetWidth + 60)); mask.setAttribute('height', String(host.offsetHeight + 48));
      mask.style.maskType = 'luminance'; definitions.append(mask); return mask;
    };
    const combined = makeMask('sweep');
    const stationary = makeMask('stationary');
    const background = document.createElementNS(svg, 'rect');
    for (const [key, value] of Object.entries({x:-30,y:-24,width:host.offsetWidth+60,height:host.offsetHeight+48,fill:'white'})) background.setAttribute(key,String(value));
    stationary.append(background); base.style.mask = `url(#${stationary.id})`;
    const highlight = document.createElement('span'); highlight.className = 'word-highlight'; highlight.textContent = line.text; highlight.style.mask = `url(#${combined.id})`; effects.append(highlight);
    for (const [index, segment] of line.segments.entries()) {
      const range = document.createRange(); range.setStart(node, segment.start); range.setEnd(node, segment.end);
      const boxes = Array.from(range.getClientRects()).filter(r => r.width > 0 && r.height > 0);
      const total = boxes.reduce((n, r) => n + r.width / unit, 0);
      const strong = Array.from(segment.word.text).find(char=>/[\p{L}\p{N}]/u.test(char));
      const rtl = strong ? /[\p{Script=Hebrew}\p{Script=Arabic}\p{Script=Syriac}]/u.test(strong) : getComputedStyle(base).direction==='rtl';
      let before = 0;
      const fragments: Fragment[] = [];
      for (const [part, box] of boxes.entries()) {
        const x = (box.left - bounds.left) / unit, y = (box.top - bounds.top) / unit, width = box.width / unit, height = box.height / unit;
        const gradient = document.createElementNS(svg, 'linearGradient'); gradient.id = `${id}-gradient-${index}-${part}`;
        gradient.setAttribute('gradientUnits', 'userSpaceOnUse'); gradient.setAttribute('y1', '0'); gradient.setAttribute('y2', '0');
        for (const [offset, color] of [['0', 'white'], ['1', 'black']]) { const stop = document.createElementNS(svg, 'stop'); stop.setAttribute('offset', offset); stop.setAttribute('stop-color', color); gradient.append(stop); }
        const rect = document.createElementNS(svg, 'rect');
        for (const [name, value] of Object.entries({ x, y, width, height })) rect.setAttribute(name, String(value));
        const clip = document.createElementNS(svg, 'clipPath'); clip.id = `${id}-clip-${index}-${part}`;
        clip.setAttribute('clipPathUnits', 'userSpaceOnUse'); clip.append(rect.cloneNode(true));
        const hole = rect.cloneNode(true) as SVGRectElement; hole.setAttribute('fill', 'black'); hole.setAttribute('opacity', '0'); stationary.append(hole);
        const movingRect = rect.cloneNode(true) as SVGRectElement;
        const mask = makeMask(`word-${index}-${part}`); mask.append(movingRect);
        combined.append(rect); definitions.append(gradient, clip);
        fragments.push({ rect, movingRect, hole, gradient, clipId:clip.id, maskId:mask.id, wordIndex:index, origin:'center', anchorWidth:width, maximumScale:1, x, y, width, height, before, total, rtl }); before += width;
      }
      words.push({ start: segment.word.startMs, end: segment.word.endMs, fragments, progress:-1 });
    }
    // Physical neighbours, including overlapping earlier runs, constrain the
    // expansion independently of reading direction (Mac WordAnchors contract).
    const rows: Fragment[][] = [];
    for (const fragment of words.flatMap(word => word.fragments)) {
      let row = rows.find(row => Math.abs(row[0].y - fragment.y) < 1);
      if (!row) rows.push(row = []);
      row.push(fragment);
    }
    for (const row of rows) {
      const groups = new Map<number, Fragment[]>();
      for (const f of row) { const group = groups.get(f.wordIndex) ?? []; group.push(f); groups.set(f.wordIndex,group); }
      const anchors = Array.from(groups.values(), fragments => {
        const x = Math.min(...fragments.map(f => f.x)), right = Math.max(...fragments.map(f => f.x + f.width));
        return {fragments,x,right,width:right-x,bottom:Math.max(...fragments.map(f => f.y + f.height))};
      }).sort((a,b) => a.x - b.x);
      let leftMaximum = -Infinity;
      anchors.forEach((anchor,index) => {
        let room = 24;
        if (index > 0) room = Math.min(room, Math.max(0, anchor.x - leftMaximum) * .45);
        if (index + 1 < anchors.length) room = Math.min(room, Math.max(0, anchors[index+1].x - anchor.right) * .45);
        for (const f of anchor.fragments) {
          f.maximumScale = 1 + room / Math.max(1, anchor.width / 2);
          f.anchorWidth = anchor.width;
          f.origin = `${anchor.x + anchor.width / 2}px ${anchor.bottom}px`;
        }
        leftMaximum = Math.max(leftMaximum, anchor.right);
      });
    }
    effects.style.visibility = 'visible';
    paint(clock.sample());
  }
  function scheduleMeasure() {
    if (!visible || measurement !== undefined || disposed) return;
    measurement = requestAnimationFrame(measure);
  }
  function setVisible(next: boolean) {
    visible = next; unsubscribe?.(); unsubscribe = undefined;
    if (visible) { measure(); unsubscribe = clock.subscribe(paint); }
    else { if(base)base.style.mask=''; definitions?.replaceChildren(); effects?.replaceChildren(); words=[]; }
  }
  $effect(() => { line; geometry; enabled; offset; motion; reduced; untrack(()=>{if(base)base.style.mask='';if(effects)effects.style.visibility='hidden';scheduleMeasure();}); });
  onMount(() => {
    mounted = true;
    const resize = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(scheduleMeasure); resize?.observe(host);
    const intersection = typeof IntersectionObserver === 'undefined' ? null : new IntersectionObserver(entries => setVisible(entries[0]?.isIntersecting ?? false));
    intersection?.observe(host); if (!intersection) setVisible(true);
    void document.fonts?.ready.then(() => { if (!disposed) scheduleMeasure(); });
    return () => { disposed = true; resize?.disconnect(); intersection?.disconnect(); unsubscribe?.(); if (measurement !== undefined) cancelAnimationFrame(measurement); };
  });
</script>
<span class="phrase" bind:this={host} dir="auto"><span class="base" bind:this={base} class:dim={enabled && !!line.segments}>{line.text || '♪'}</span><svg width="0" height="0" aria-hidden="true"><defs bind:this={definitions}></defs></svg><span class="effects" bind:this={effects} aria-hidden="true"></span></span>
<style>
  .phrase { display:block; position:relative; white-space:pre-wrap; overflow-wrap:anywhere; user-select:text; }
  .base { display:block; }
  .dim { opacity:.70; }.effects { position:absolute; inset:0; pointer-events:none; user-select:none; }
  .effects :global(.word-glow), .effects :global(.word-effect), .effects :global(.word-fragment), .effects :global(.word-highlight) { position:absolute; inset:0; color:white; white-space:inherit; overflow-wrap:inherit; pointer-events:none; }
  .effects :global(.word-base) { opacity:.70; }
  @media(forced-colors:active) { .effects { display:none; }.dim {opacity:1;mask:none !important;} }
  svg { position:absolute; pointer-events:none; } @media(prefers-contrast:more) { .dim, .effects :global(.word-base) { opacity:.86; } }
</style>
