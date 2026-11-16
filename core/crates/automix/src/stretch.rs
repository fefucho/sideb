//! Offline time-stretching along a time map.
//!
//! A [`TimeMap`] says which input sample should be heard at each output
//! sample. Rendering follows it through Signalsmith Stretch's streaming API,
//! feeding input ahead by the stretcher's latency so the result lands on the
//! map to the sample — which is what lets two decks stay beat-locked and lets
//! the processed audio be spliced back onto the untouched original.

use crate::audio::SR;
use signalsmith_stretch::Stretch;

/// Piecewise-linear map from output samples to input samples.
#[derive(Clone, Debug)]
pub struct TimeMap {
    /// Output sample positions, strictly increasing.
    pub out: Vec<f64>,
    /// Input sample position heard at each of `out`.
    pub input: Vec<f64>,
    /// Playback rate (input samples per output sample) before the first knot
    /// and after the last.
    pub rate_before: f64,
    pub rate_after: f64,
}

impl TimeMap {
    pub fn at(&self, o: f64) -> f64 {
        let n = self.out.len();
        if o <= self.out[0] {
            return self.input[0] + (o - self.out[0]) * self.rate_before;
        }
        if o >= self.out[n - 1] {
            return self.input[n - 1] + (o - self.out[n - 1]) * self.rate_after;
        }
        let i = match self.out.binary_search_by(|v| v.partial_cmp(&o).unwrap()) {
            Ok(i) => return self.input[i],
            Err(i) => i - 1,
        };
        let f = (o - self.out[i]) / (self.out[i + 1] - self.out[i]);
        self.input[i] + f * (self.input[i + 1] - self.input[i])
    }
}

const BLOCK: usize = 256;

/// Renders `out_len` output samples starting at output position `out_start`.
///
/// `src` is planar, any number of channels, all the same length; positions
/// outside it read as silence. All channels go through one stretcher so they
/// keep their phase relationship (the stems of one song must still sum to
/// that song).
pub fn render(src: &[Vec<f32>], map: &TimeMap, out_start: i64, out_len: usize) -> Vec<Vec<f32>> {
    let channels = src.len();
    let src_len = src[0].len() as i64;
    let mut stretch = Stretch::preset_default(channels as u32, SR);
    let in_latency = stretch.input_latency() as f64;
    let out_latency = stretch.output_latency() as f64;

    // The stretcher shows, at output `o`, the input it was fed at the time
    // it produced `o - out_latency`, minus `in_latency`. So to hear `map(o)`
    // at `o`, the input fed by output time `x` must reach:
    let feed = |x: f64| map.at(x + out_latency) + in_latency;

    // Start early and throw the warm-up away, so the first kept sample is
    // already settled.
    let warmup = (((in_latency + out_latency) * 4.0) as usize).max(16_384) / BLOCK * BLOCK;
    let mut o = out_start - warmup as i64;
    let mut fed = feed(o as f64).round() as i64;

    let mut out: Vec<Vec<f32>> = (0..channels).map(|_| Vec::with_capacity(out_len)).collect();
    let mut in_buf: Vec<f32> = Vec::new();
    let mut out_buf = vec![0.0f32; BLOCK * channels];
    let end = out_start + out_len as i64;

    while o < end {
        let target = feed((o + BLOCK as i64) as f64).round() as i64;
        let count = (target - fed).max(0) as usize;
        in_buf.clear();
        in_buf.resize(count * channels, 0.0);
        for i in 0..count {
            let pos = fed + i as i64;
            if pos >= 0 && pos < src_len {
                for c in 0..channels {
                    in_buf[i * channels + c] = src[c][pos as usize];
                }
            }
        }
        stretch.process(&in_buf, &mut out_buf);
        fed += count as i64;

        for i in 0..BLOCK {
            let pos = o + i as i64;
            if pos >= out_start && pos < end {
                for c in 0..channels {
                    out[c].push(out_buf[i * channels + c]);
                }
            }
        }
        o += BLOCK as i64;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn click_track(len: usize, positions: &[usize]) -> Vec<f32> {
        let mut x = vec![0.0f32; len];
        for &p in positions {
            for i in 0..200 {
                if p + i < len {
                    // A short decaying burst: broadband, with a clear peak.
                    let env = (-(i as f32) / 30.0).exp();
                    x[p + i] = env * (i as f32 * 0.9).sin();
                }
            }
        }
        x
    }

    fn peak_near(x: &[f32], centre: usize, radius: usize) -> usize {
        let a = centre.saturating_sub(radius);
        let b = (centre + radius).min(x.len());
        let mut energy_best = (0.0f32, a);
        // Energy over a short window, so the answer is the burst, not one sample.
        for i in a..b.saturating_sub(64) {
            let e: f32 = x[i..i + 64].iter().map(|v| v * v).sum();
            if e > energy_best.0 {
                energy_best = (e, i);
            }
        }
        energy_best.1
    }

    #[test]
    fn identity_map_keeps_events_in_place() {
        let positions = [30_000usize, 60_000, 90_000];
        let src = vec![click_track(120_000, &positions)];
        let map = TimeMap { out: vec![0.0, 1.0], input: vec![0.0, 1.0], rate_before: 1.0, rate_after: 1.0 };
        let out = render(&src, &map, 0, 120_000);
        for &p in &positions {
            let found = peak_near(&out[0], p, 2_000) as i64;
            assert!((found - p as i64).abs() <= 64, "click at {p} landed at {found}");
        }
    }

    #[test]
    fn stretched_map_lands_events_on_their_knots() {
        // Input clicks every 20_000 samples; play at 0.8x speed, so they must
        // come out every 25_000.
        let positions = [20_000usize, 40_000, 60_000, 80_000];
        let src = vec![click_track(100_000, &positions)];
        let map = TimeMap {
            out: vec![0.0, 125_000.0],
            input: vec![0.0, 100_000.0],
            rate_before: 1.0,
            rate_after: 1.0,
        };
        let out = render(&src, &map, 0, 125_000);
        for &p in &positions {
            let expected = p * 5 / 4;
            let found = peak_near(&out[0], expected, 3_000) as i64;
            assert!((found - expected as i64).abs() <= 128, "click at {p} expected {expected}, landed at {found}");
        }
    }
}
