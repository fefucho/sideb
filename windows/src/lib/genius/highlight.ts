import { samplePalette, hue, hslColor, type RGB } from '../home/ambient';

export type AnnotationColorMode = 'artwork' | 'contrast' | 'neutral';
/** Whitespace stays in the lyric flow but is not painted as an annotation. */
export function annotationText(value: string) {
  const [,before,text,after]=value.match(/^(\s*)([\s\S]*?)(\s*)$/u)!;
  return {before,text,after};
}
const luminance = ([r,g,b]: RGB) => {
  const linear = [r,g,b].map(value => { const s=value/255; return s<=.04045?s/12.92:((s+.055)/1.055)**2.4; });
  return .2126*linear[0]+.7152*linear[1]+.0722*linear[2];
};
/** Bound the active (.48) tint so white lyrics remain legible over the dark scene. */
function readableTint(rgb: RGB): RGB {
  let tint=rgb;
  while(luminance(tint)>.28) tint=tint.map(value=>value*.95) as RGB;
  return tint.map(Math.round) as RGB;
}
export function annotationPalette(pixels: ArrayLike<number> = []): {artwork: RGB; contrast: RGB} {
  const dominant=samplePalette(pixels)[0];
  if(!dominant) { const fallback=readableTint([190,190,200]); return {artwork:fallback,contrast:fallback}; }
  return {artwork:readableTint(hslColor(hue(dominant),.58,.62)),contrast:readableTint(hslColor((hue(dominant)+.5)%1,.52,.62))};
}
export function annotationTint(palette: ReturnType<typeof annotationPalette>, mode: AnnotationColorMode, active = false): string {
  // Like Apple, neutral normal/hover stays white while selection retains an accent.
  return (mode==='neutral'&&!active?[255,255,255]:palette[mode==='neutral'?'artwork':mode]).join(' ');
}
