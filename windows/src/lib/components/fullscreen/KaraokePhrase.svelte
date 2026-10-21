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
  type Fragment = { rect: SVGRectElement; gradient: SVGLinearGradientElement; x: number; y: number; width: number; height: number; before: number; total: number; rtl: boolean };
  type Word = { start: number; end: number; fragments: Fragment[]; effect?: HTMLSpanElement; clipId: string; maskId: string; origin: string; progress: number };
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
      if (word.progress !== progress) for (const f of word.fragments) {
        const feather = Math.min(30, f.total / 2);
        const edge = progress * (f.total + feather) - f.before;
        // Advance coordinates are shared across wrapped fragments. Gradients use
        // physical glyph rectangles from the native DOM Range, preserving shaping.
        f.gradient.setAttribute('x1', String(f.rtl ? f.x + f.width - edge : f.x + edge - feather));
        f.gradient.setAttribute('x2', String(f.rtl ? f.x + f.width - edge + feather : f.x + edge));
        f.rect.setAttribute('opacity', progress <= 0 ? '0' : progress >= 1 ? '1' : '1');
        f.rect.setAttribute('fill', progress >= 1 ? 'white' : `url(#${f.gradient.id})`);
      }
      word.progress = progress;
      const active = progress > 0 && progress < 1;
      const animated = active && motion && !reduced;
      if (animated) {
        if (!word.effect) {
          const layer = document.createElement('span'); layer.className = 'word-highlight'; layer.textContent = line.text;
          layer.style.mask = `url(#${word.maskId})`; layer.style.clipPath = `url(#${word.clipId})`;
          layer.style.transformOrigin = word.origin; effects.append(layer); word.effect = layer;
        }
        const duration = word.end - word.start;
        const envelope = smooth((ms - word.start) / Math.min(240, duration * .24)) * smooth((word.end - ms) / Math.min(280, duration * .28));
        const sustain = smooth((duration - 700) / 1000) * envelope;
        word.effect.style.transform = `translateY(${-2 * sustain}px) scale(${1 + .13 * sustain})`;
        word.effect.style.filter = `drop-shadow(0 0 5px rgb(255 255 255 / ${.28 * envelope}))`;
      }
      if (!animated && word.effect) { word.effect.remove(); word.effect = undefined; }
      changing ||= active;
    }
    return changing;
  }
  function measure() {
    measurement = undefined;
    if (!mounted || disposed || !visible || !host || !base || !definitions || !effects) return;
    definitions.replaceChildren(); effects.replaceChildren(); words = [];
    if (!enabled || !line.segments?.length) return;
    const node = base.firstChild;
    if (!node || node.nodeType !== Node.TEXT_NODE) return;
    // offsetWidth excludes the ancestor's context scale. Divide screen-space
    // ranges by that scale before storing local drawing geometry.
    const bounds = host.getBoundingClientRect();
    const scale = host.offsetWidth > 0 ? bounds.width / host.offsetWidth : 1;
    const unit = Number.isFinite(scale) && scale > 0 ? scale : 1;
    const combined = document.createElementNS(svg, 'mask'); combined.id = `${id}-sweep`; combined.setAttribute('maskUnits','userSpaceOnUse'); combined.setAttribute('x','-30'); combined.setAttribute('y','-24'); combined.setAttribute('width',String(host.offsetWidth+60)); combined.setAttribute('height',String(host.offsetHeight+48)); definitions.append(combined);
    const highlight = document.createElement('span'); highlight.className = 'word-highlight'; highlight.textContent = line.text; highlight.style.mask = `url(#${combined.id})`; effects.append(highlight);
    for (const [index, segment] of line.segments.entries()) {
      const range = document.createRange(); range.setStart(node, segment.start); range.setEnd(node, segment.end);
      const boxes = Array.from(range.getClientRects()).filter(r => r.width > 0 && r.height > 0);
      const total = boxes.reduce((n, r) => n + r.width / unit, 0);
      const mask = document.createElementNS(svg, 'mask'); mask.id = `${id}-word-${index}`;
      mask.setAttribute('maskUnits', 'userSpaceOnUse'); mask.setAttribute('maskContentUnits', 'userSpaceOnUse');
      mask.setAttribute('x', '-30'); mask.setAttribute('y', '-24'); mask.setAttribute('width', String(host.offsetWidth + 60)); mask.setAttribute('height', String(host.offsetHeight + 48));
      const clip = document.createElementNS(svg, 'clipPath'); clip.id = `${id}-clip-${index}`;
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
        const fixed = rect.cloneNode(true); clip.append(fixed); rect.id = `${id}-rect-${index}-${part}`; combined.append(rect);
        const reference = document.createElementNS(svg,'use'); reference.setAttribute('href',`#${rect.id}`); mask.append(reference); definitions.append(gradient);
        fragments.push({ rect, gradient, x, y, width, height, before, total, rtl }); before += width;
      }
      definitions.append(mask, clip);
      const origin = fragments.length ? `${(Math.min(...fragments.map(f=>f.x))+Math.max(...fragments.map(f=>f.x+f.width)))/2}px ${(Math.min(...fragments.map(f=>f.y))+Math.max(...fragments.map(f=>f.y+f.height)))/2}px` : 'center';
      words.push({ start: segment.word.startMs, end: segment.word.endMs, fragments, clipId:clip.id, maskId:mask.id, origin, progress:-1 });
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
    else { definitions?.replaceChildren(); effects?.replaceChildren(); words=[]; }
  }
  $effect(() => { line; geometry; enabled; offset; motion; reduced; untrack(()=>{if(effects)effects.style.visibility='hidden';scheduleMeasure();}); });
  onMount(() => {
    mounted = true;
    const resize = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(scheduleMeasure); resize?.observe(host);
    const intersection = typeof IntersectionObserver === 'undefined' ? null : new IntersectionObserver(entries => setVisible(entries[0]?.isIntersecting ?? false));
    intersection?.observe(host); if (!intersection) setVisible(true);
    void document.fonts?.ready.then(() => { if (!disposed) scheduleMeasure(); });
    return () => { disposed = true; resize?.disconnect(); intersection?.disconnect(); unsubscribe?.(); if (measurement !== undefined) cancelAnimationFrame(measurement); };
  });
</script>
<span class="phrase" bind:this={host} dir="auto"><span bind:this={base} class:dim={enabled && !!line.segments}>{line.text || '♪'}</span><svg width="0" height="0" aria-hidden="true"><defs bind:this={definitions}></defs></svg><span class="effects" bind:this={effects} aria-hidden="true"></span></span>
<style>
  .phrase { display:block; position:relative; white-space:pre-wrap; overflow-wrap:anywhere; user-select:text; }
  .dim { opacity:.70; }.effects { position:absolute; inset:0; pointer-events:none; }
  .effects :global(.word-highlight) { position:absolute; inset:0; color:white; white-space:inherit; overflow-wrap:inherit; pointer-events:none; }
  @media(forced-colors:active) { .effects { display:none; }.dim {opacity:1;} }
  svg { position:absolute; pointer-events:none; } @media(prefers-contrast:more) { .dim { opacity:.86; } }
</style>
