export type RGB = [number, number, number];
/** Window-wide collection color follows its document and fades 140px below the header. */
export function collectionAmbientFrame(headerTop:number, headerHeight:number, scrollTop:number, windowHeight:number, canvasTop=0) {
  const top=canvasTop-Math.max(0,scrollTop);
  const clearance=Math.max(0,headerTop+scrollTop-canvasTop);
  const height=Math.max(1,headerHeight)+clearance+140+Math.max(0,-scrollTop);
  return {top,height,visible:top+height>canvasTop&&top<windowHeight};
}
export const neutral: [RGB, RGB] = [[.18*255, .22*255, .28*255], [.15*255, .18*255, .23*255]];
export function hue([r, g, b]: RGB) { const max = Math.max(r,g,b), min = Math.min(r,g,b), d = max-min; return d === 0 ? 0 : (((max === r ? (g-b)/d : max === g ? (b-r)/d+2 : (r-g)/d+4) / 6) + 1) % 1; }
export function chroma(rgb: RGB) { return (Math.max(...rgb) - Math.min(...rgb)) / 255; }
export function hueDistance(a: RGB, b: RGB) { const d = Math.abs(hue(a)-hue(b)); return Math.min(d, 1-d); }
export function hslColor(h: number, s: number, l: number): RGB {
  const a = s*Math.min(l,1-l); const component = (n: number) => { const k=(n+h*12)%12; return Math.round(255*(l-a*Math.max(-1, Math.min(k-3,9-k,1)))); }; return [component(0),component(8),component(4)];
}
/** HomeAmbientPaletteSampler: hue families, supported accents, weighted alpha/saturation. */
export function samplePalette(pixels: ArrayLike<number>): RGB[] {
  if(pixels.length<4 || pixels.length%4)return [];
  const bins=Array.from({length:12},()=>({rgb:[0,0,0] as RGB,count:0,weight:0}));
  for (let i=0;i<pixels.length;i+=4) {
    const alpha=pixels[i+3]/255;if(alpha<=.5)continue;
    const rgb:RGB=[pixels[i]/255,pixels[i+1]/255,pixels[i+2]/255];
    const luminance=.2126*rgb[0]+.7152*rgb[1]+.0722*rgb[2];if(luminance<=.055||luminance>=.92)continue;
    const saturation=(Math.max(...rgb)-Math.min(...rgb))/Math.max(Math.max(...rgb),.001);if(saturation<.16)continue;
    const bin=bins[Math.min(11,Math.floor(hue(rgb)*12))],weight=alpha*(.08+saturation*saturation);
    bin.count++;bin.weight+=weight;bin.rgb=bin.rgb.map((c,j)=>c+rgb[j]*weight) as RGB;
  }
  return bins.filter(bin=>bin.count>=Math.max(3,Math.floor(pixels.length/4/128))&&bin.weight>0)
    .sort((a,b)=>b.weight/Math.sqrt(b.count)-a.weight/Math.sqrt(a.count)).slice(0,3).map(bin=>{
      const rgb=bin.rgb.map(c=>c/bin.weight) as RGB,luminance=.2126*rgb[0]+.7152*rgb[1]+.0722*rgb[2];
      return rgb.map(c=>(luminance+(c-luminance)*.84)*255) as RGB;
    });
}
export function ambientColor(rgb:RGB):RGB {
  const maximum=Math.max(...rgb)/255,minimum=Math.min(...rgb)/255,chroma=maximum-minimum;
  if(chroma<=.08)return rgb;
  const saturation=Math.min(.78,Math.max(.48,chroma/Math.max(maximum,.001))),low=.8*(1-saturation);
  return rgb.map(c=>(low+(c/255-minimum)/chroma*(.8-low))*255) as RGB;
}
function counterLight(rgb:RGB):RGB {
  const h=(hue(rgb)+.44)%1,s=.42,v=.68;
  const component=(n:number)=>{const k=(n+h*6)%6;return 255*v*(1-s*Math.max(0,Math.min(k,4-k,1)));};
  return [component(5),component(3),component(1)];
}
export function choosePalette(colors: RGB[]): [RGB,RGB] {
  const ranked=[...colors].sort((a,b)=>chroma(b)-chroma(a));
  const left=ranked[0]??neutral[0];
  const right=ranked.slice(1).sort((a,b)=>hueDistance(left,b)*chroma(b)-hueDistance(left,a)*chroma(a))[0]??ranked[0]??neutral[1];
  return [ambientColor(left),chroma(left)>.12&&chroma(right)>.12&&hueDistance(left,right)<.1?counterLight(left):ambientColor(right)];
}
