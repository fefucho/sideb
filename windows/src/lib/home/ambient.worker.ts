import { choosePalette, samplePalette } from './ambient';
self.onmessage = (event: MessageEvent<{ generation: number; pixels: Uint8ClampedArray[] }>) => {
  self.postMessage({ generation: event.data.generation, palette: choosePalette(event.data.pixels.flatMap(samplePalette)) });
};
