/** HomeAmbientSmoke: account-independent mask prepared once, away from the UI thread. */
const hashes = new Map<string, number>();
const u64 = (value: bigint) => BigInt.asUintN(64, value);
function hash(x: number, y: number) {
  const key = `${x}|${y}`, cached = hashes.get(key);
  if (cached !== undefined) return cached;
  let value = u64(BigInt(x) * 0x9E3779B185EBCA87n) ^ u64(BigInt(y) * 0xC2B2AE3D27D4EB4Fn);
  value = u64((value ^ (value >> 30n)) * 0xBF58476D1CE4E5B9n);
  value = u64((value ^ (value >> 27n)) * 0x94D049BB133111EBn);
  value ^= value >> 31n;
  const result = Number(value & 0xFFFFFFn) / 0xFFFFFF;
  hashes.set(key, result);
  return result;
}
const mix = (a: number, b: number, amount: number) => a + (b - a) * amount;
function noise(x: number, y: number) {
  const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
  const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
  return mix(mix(hash(ix, iy), hash(ix + 1, iy), sx), mix(hash(ix, iy + 1), hash(ix + 1, iy + 1), sx), sy);
}
function fractal(x: number, y: number) {
  let sum = 0, amplitude = .57, frequency = 1;
  for (let i = 0; i < 4; i++) { sum += noise(x * frequency, y * frequency) * amplitude; frequency *= 2.03; amplitude *= .47; }
  return sum;
}
function smoothstep(low: number, high: number, value: number) {
  const t = Math.min(1, Math.max(0, (value - low) / (high - low)));
  return t * t * (3 - 2 * t);
}
self.onmessage = () => {
  const width = 384, height = 256, pixels = new Uint8ClampedArray(width * height * 4);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const u = x / (width - 1), v = y / (height - 1);
    const flowX = u * 4.8 + fractal(u * 2.4 + 11, v * 2.4 - 7) * 2.8;
    const flowY = v * 3.2 + fractal(u * 2.4 - 19, v * 2.4 + 13) * 2.8;
    const haze = fractal(flowX, flowY), ridge = 1 - Math.abs(2 * noise(flowX + haze * .7, flowY * .72) - 1);
    const ribbon = Math.max(0, (ridge - .30) / .70) ** 2.8;
    const border = smoothstep(0, .09, u) * (1 - smoothstep(.91, 1, u)), depth = (1 - v) ** .65;
    const density = (haze * .40 + ribbon * .60) * (.35 + haze * .65) * border * depth;
    const i = (y * width + x) * 4;
    pixels[i] = pixels[i + 1] = pixels[i + 2] = 255;
    pixels[i + 3] = Math.floor(Math.min(255, Math.max(0, density * 210)));
  }
  self.postMessage({ width, height, pixels }, { transfer: [pixels.buffer] });
  hashes.clear();
};
