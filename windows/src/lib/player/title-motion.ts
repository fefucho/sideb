/** One interactive title, moved by the compositor. No playback or per-frame state. */
export interface TitleMotionOptions { enabled: boolean; key: string; paused?: boolean }
export function titleMotion(viewport: HTMLElement, initial: TitleMotionOptions) {
  const content = viewport.querySelector<HTMLElement>('.title-parts')!;
  // Older embedded engines and non-layout renderers retain the static accessible title.
  if (typeof ResizeObserver === 'undefined' || typeof IntersectionObserver === 'undefined' || !content.animate) {
    return { update(_options: TitleMotionOptions) {}, destroy() {} };
  }
  let options = initial, animation: Animation | undefined, geometry = '', destroyed = false;
  let hovered = false, focused = false, visible = true, foreground = document.hasFocus();
  let distance = 0, travel = 0;
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
  function sync() {
    if (!animation) return;
    if (hovered || focused || options.paused || !visible || !foreground || document.hidden || reduced.matches) animation.pause();
    else animation.play();
  }
  function measure(reset = false) {
    if (destroyed) return;
    const width = viewport.clientWidth, full = content.scrollWidth;
    const next = `${options.enabled}:${options.key}:${width}:${full}:${reduced.matches}`;
    if (!reset && next === geometry) return;
    geometry = next;
    animation?.cancel(); animation = undefined;
    viewport.scrollLeft = 0;
    distance = Math.max(0, full - width);
    if (!options.enabled || reduced.matches || !width || distance <= 1) return;
    travel = Math.max(3500, distance / 24 * 1000);
    const duration = 1000 + travel + 1300;
    animation = content.animate([
      { transform: 'translateX(0)', offset: 0 },
      { transform: 'translateX(0)', offset: 1000 / duration },
      { transform: `translateX(-${distance}px)`, offset: (1000 + travel) / duration },
      { transform: `translateX(-${distance}px)`, offset: 1 }
    ], { duration, iterations: Infinity, easing: 'linear' });
    sync();
  }
  function enter() { hovered = true; sync(); }
  function leave() { hovered = false; sync(); }
  function focus(event: FocusEvent) {
    focused = true; sync();
    const target = event.target;
    if (!(target instanceof HTMLElement) || !content.contains(target)) return;
    // Reveal a clipped keyboard target locally; never scroll the app shell.
    viewport.scrollLeft = 0;
    const box = target.getBoundingClientRect(), clip = viewport.getBoundingClientRect();
    if (box.left >= clip.left && box.right <= clip.right) return;
    const start = box.left - content.getBoundingClientRect().left;
    const offset = Math.min(distance, Math.max(0, start - Math.max(0, (clip.width - box.width) / 2)));
    if (animation) animation.currentTime = 1000 + offset / distance * travel;
    else viewport.scrollLeft = Math.max(0, start);
  }
  function blur(event: FocusEvent) { focused = event.relatedTarget instanceof Node && viewport.contains(event.relatedTarget); sync(); }
  function background() { foreground = false; sync(); }
  function foregrounded() { foreground = true; sync(); }
  function preference() { measure(true); }
  const resize = new ResizeObserver(() => measure());
  resize.observe(viewport); resize.observe(content);
  const intersection = new IntersectionObserver(entries => { visible = entries[0]?.isIntersecting ?? false; sync(); });
  intersection.observe(viewport);
  viewport.addEventListener('mouseenter', enter); viewport.addEventListener('mouseleave', leave);
  viewport.addEventListener('focusin', focus); viewport.addEventListener('focusout', blur);
  window.addEventListener('blur', background); window.addEventListener('focus', foregrounded);
  document.addEventListener('visibilitychange', sync); reduced.addEventListener('change', preference);
  void document.fonts?.ready.then(() => measure());
  measure();
  return {
    update(next: TitleMotionOptions) { options = next; measure(); sync(); },
    destroy() {
      destroyed = true; animation?.cancel(); resize.disconnect(); intersection.disconnect();
      viewport.removeEventListener('mouseenter', enter); viewport.removeEventListener('mouseleave', leave);
      viewport.removeEventListener('focusin', focus); viewport.removeEventListener('focusout', blur);
      window.removeEventListener('blur', background); window.removeEventListener('focus', foregrounded);
      document.removeEventListener('visibilitychange', sync); reduced.removeEventListener('change', preference);
    }
  };
}
