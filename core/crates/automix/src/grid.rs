//! Beat grid estimation: an onset envelope (spectral flux), a global tempo
//! guess from its autocorrelation, and a constant-tempo grid fitted *locally*
//! to the region a transition will actually use.
//!
//! Fitting locally matters: a transition only reads the tail of one track and
//! the head of the next, and a grid that is right on average over four
//! minutes can still be tens of milliseconds off at either end.

use crate::audio::{Stereo, SRF};
use realfft::RealFftPlanner;

const FRAME: usize = 2048;
const HOP: usize = 441;
/// Envelope frames per second.
pub const FPS: f64 = SRF / HOP as f64;

/// Onset envelopes on a 100 Hz clock. Frame `i` describes the audio centred
/// at `i / FPS` seconds.
pub struct Envelope {
    /// Full-band spectral flux, lightly smoothed.
    pub full: Vec<f32>,
    /// Flux below ~200 Hz: kicks and bass note changes.
    pub low: Vec<f32>,
    /// Short-time RMS, for finding where a track is audible.
    pub rms: Vec<f32>,
    /// Pitch-class energy per frame (C..B), from 55 Hz to 2 kHz. Coarse at
    /// the bottom, but enough to see the harmony change.
    pub chroma: Vec<[f32; 12]>,
}

impl Envelope {
    pub fn compute(audio: &Stereo) -> Self {
        let mono = audio.mono();
        let frames = mono.len() / HOP + 1;
        let mut planner = RealFftPlanner::<f32>::new();
        let fft = planner.plan_fft_forward(FRAME);
        let window: Vec<f32> = (0..FRAME)
            .map(|i| 0.5 - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / FRAME as f32).cos())
            .collect();
        let mut buf = fft.make_input_vec();
        let mut spec = fft.make_output_vec();
        let bins = spec.len();
        let low_bins = (200.0 * FRAME as f64 / SRF).ceil() as usize;
        let mut prev = vec![0.0f32; bins];
        let mut full = vec![0.0f32; frames];
        let mut low = vec![0.0f32; frames];
        let mut rms = vec![0.0f32; frames];
        let mut chroma = vec![[0.0f32; 12]; frames];
        let pitch_class: Vec<Option<usize>> = (0..bins)
            .map(|b| {
                let hz = b as f64 * SRF / FRAME as f64;
                (55.0..=2000.0).contains(&hz).then(|| {
                    ((12.0 * (hz / 261.63).log2()).round() as i64).rem_euclid(12) as usize
                })
            })
            .collect();

        for f in 0..frames {
            let centre = (f * HOP) as i64;
            let start = centre - (FRAME / 2) as i64;
            let mut energy = 0.0f32;
            for i in 0..FRAME {
                let idx = start + i as i64;
                let s = if idx >= 0 && (idx as usize) < mono.len() { mono[idx as usize] } else { 0.0 };
                energy += s * s;
                buf[i] = s * window[i];
            }
            rms[f] = (energy / FRAME as f32).sqrt();
            fft.process(&mut buf, &mut spec).expect("fft size is fixed");
            let (mut flux_full, mut flux_low) = (0.0f32, 0.0f32);
            for b in 1..bins {
                let linear = spec[b].norm() / FRAME as f32 * 2.0;
                if let Some(pc) = pitch_class[b] {
                    chroma[f][pc] += linear;
                }
                let mag = (1.0 + 100.0 * linear).ln();
                let rise = (mag - prev[b]).max(0.0);
                flux_full += rise;
                if b <= low_bins {
                    flux_low += rise;
                }
                prev[b] = mag;
            }
            full[f] = flux_full;
            low[f] = flux_low;
        }
        Envelope { full: smooth(&full), low: smooth(&low), rms, chroma }
    }

}

/// 5-tap binomial smoothing: widens onset peaks enough that a grid a frame
/// off still scores, without merging neighbouring 16th notes.
fn smooth(x: &[f32]) -> Vec<f32> {
    let k = [1.0f32, 4.0, 6.0, 4.0, 1.0];
    let n = x.len() as i64;
    (0..n)
        .map(|i| {
            let mut acc = 0.0;
            for (j, w) in k.iter().enumerate() {
                let idx = (i + j as i64 - 2).clamp(0, n - 1) as usize;
                acc += w * x[idx];
            }
            acc / 16.0
        })
        .collect()
}

fn sample(env: &[f32], frame: f64) -> f32 {
    if frame < 0.0 || frame >= (env.len() - 1) as f64 {
        return 0.0;
    }
    let i = frame.floor() as usize;
    let frac = (frame - i as f64) as f32;
    env[i] + (env[i + 1] - env[i]) * frac
}

/// Where the track starts and stops being audible, in seconds, judged
/// against its own loud passages.
pub fn audible_range(env: &Envelope) -> (f64, f64) {
    let mut sorted: Vec<f32> = env.rms.clone();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let loud = sorted[(sorted.len() as f64 * 0.9) as usize].max(1e-6);
    let threshold = loud * 0.05; // -26 dB under the loud reference
    let first = env.rms.iter().position(|v| *v > threshold).unwrap_or(0);
    let last = env.rms.iter().rposition(|v| *v > threshold).unwrap_or(env.rms.len() - 1);
    (first as f64 / FPS, last as f64 / FPS)
}

/// Global tempo guess from the autocorrelation of the onset envelope, with a
/// broad preference for tempos near 120 BPM to settle octave ambiguity.
pub fn estimate_bpm(env: &Envelope, from: f64, to: f64) -> f64 {
    let a = ((from * FPS) as usize).min(env.full.len());
    let b = ((to * FPS) as usize).min(env.full.len());
    let region = &env.full[a..b];
    if region.len() < (FPS * 8.0) as usize {
        return 0.0;
    }
    let mean = region.iter().sum::<f32>() / region.len() as f32;
    let x: Vec<f32> = region.iter().map(|v| v - mean).collect();
    let ac = |lag: usize| -> f32 {
        if lag >= x.len() {
            return 0.0;
        }
        let n = x.len() - lag;
        x[..n].iter().zip(&x[lag..]).map(|(p, q)| p * q).sum::<f32>() / n as f32
    };
    let (mut best_bpm, mut best_score) = (0.0, f32::MIN);
    let mut bpm = 55.0;
    while bpm <= 210.0 {
        let lag = 60.0 / bpm * FPS;
        // Linear interpolation between integer lags, plus support from the
        // two-beat and four-beat lags so a subdivision cannot win alone.
        let at = |l: f64| -> f32 {
            let i = l.floor() as usize;
            let f = (l - i as f64) as f32;
            ac(i) * (1.0 - f) + ac(i + 1) * f
        };
        let raw = at(lag) + 0.5 * at(2.0 * lag) + 0.25 * at(4.0 * lag);
        let octave = (bpm / 120.0f64).log2();
        let prior = (-0.5 * (octave / 0.7).powi(2)).exp() as f32;
        let score = raw * prior;
        if score > best_score {
            best_score = score;
            best_bpm = bpm;
        }
        bpm += 0.25;
    }
    best_bpm
}

/// A constant-tempo grid valid around the region it was fitted to.
#[derive(Clone, Debug)]
pub struct Grid {
    pub bpm: f64,
    /// Time of one beat, in seconds; other beats are `anchor + k * interval`.
    pub anchor: f64,
    /// How much stronger onsets are on the grid than between beats (1 = no
    /// evidence of a beat at all).
    pub confidence: f64,
    /// Which beat of the bar `anchor` is, 0 = downbeat.
    pub anchor_bar_position: u32,
}

impl Grid {
    pub fn interval(&self) -> f64 {
        60.0 / self.bpm
    }

    /// Time of beat `k`, where beat 0 is a downbeat.
    pub fn beat(&self, k: i64) -> f64 {
        self.anchor + (k - self.anchor_bar_position as i64) as f64 * self.interval()
    }

    /// Index of the last beat at or before `t`.
    pub fn beat_at_or_before(&self, t: f64) -> i64 {
        ((t - self.beat(0)) / self.interval() + 1e-6).floor() as i64
    }
}

fn grid_score(env: &[f32], from: f64, to: f64, interval: f64, phase: f64) -> f64 {
    let mut t = from + phase;
    let (mut sum, mut n) = (0.0f64, 0u32);
    while t < to {
        sum += sample(env, t * FPS) as f64;
        n += 1;
        t += interval;
    }
    if n == 0 { 0.0 } else { sum / n as f64 }
}

/// Fits tempo and phase to `[from, to]`, searching ±3% around `bpm_guess`.
pub fn fit_grid(env: &Envelope, from: f64, to: f64, bpm_guess: f64) -> Grid {
    let search = |centre: f64, span: f64, bpm_step: f64, phase_step: f64| -> (f64, f64, f64) {
        let (mut best, mut best_bpm, mut best_phase) = (-1.0, centre, 0.0);
        let mut bpm = centre - span;
        while bpm <= centre + span {
            let interval = 60.0 / bpm;
            let mut phase = 0.0;
            while phase < interval {
                let s = grid_score(&env.full, from, to, interval, phase);
                if s > best {
                    best = s;
                    best_bpm = bpm;
                    best_phase = phase;
                }
                phase += phase_step;
            }
            bpm += bpm_step;
        }
        (best_bpm, best_phase, best)
    };

    let (bpm1, _, _) = search(bpm_guess, bpm_guess * 0.03, 0.05, 0.004);
    let (bpm, phase, on) = search(bpm1, 0.06, 0.004, 0.001);
    let interval = 60.0 / bpm;
    let off = grid_score(&env.full, from, to, interval, (phase + interval / 2.0) % interval);
    let quarter = grid_score(&env.full, from, to, interval, (phase + interval / 4.0) % interval);
    let confidence = on / ((off + quarter) / 2.0).max(1e-9);

    // Downbeat: harmony mostly changes on bar lines, so of the four beats of
    // a bar it is the one where the pitch content differs most from the beat
    // before it, with low-frequency novelty (bass note changes, kick accents)
    // as a second opinion. Still a heuristic; the CLI can override it.
    let anchor = from + phase;
    let beat_chroma = |t: f64| -> [f32; 12] {
        let a = ((t * FPS).round().max(0.0) as usize).min(env.chroma.len());
        let b = (((t + interval) * FPS).round().max(0.0) as usize).min(env.chroma.len());
        let mut acc = [0.0f32; 12];
        for frame in &env.chroma[a..b] {
            for (x, v) in acc.iter_mut().zip(frame) {
                *x += v;
            }
        }
        acc
    };
    let distance = |p: &[f32; 12], q: &[f32; 12]| -> f64 {
        let dot: f32 = p.iter().zip(q).map(|(x, y)| x * y).sum();
        let np: f32 = p.iter().map(|x| x * x).sum::<f32>().sqrt();
        let nq: f32 = q.iter().map(|x| x * x).sum::<f32>().sqrt();
        if np <= 0.0 || nq <= 0.0 { 0.0 } else { 1.0 - (dot / (np * nq)) as f64 }
    };
    let mut harmonic = [0.0f64; 4];
    let mut low = [0.0f64; 4];
    let mut counts = [0u32; 4];
    let mut k = 0usize;
    let mut t = anchor;
    let mut previous = beat_chroma(anchor - interval);
    while t + interval < to {
        let current = beat_chroma(t);
        harmonic[k % 4] += distance(&current, &previous);
        low[k % 4] += sample(&env.low, t * FPS) as f64;
        counts[k % 4] += 1;
        previous = current;
        k += 1;
        t += interval;
    }
    let normalised = |v: &mut [f64; 4]| {
        for p in 0..4 {
            if counts[p] > 0 {
                v[p] /= counts[p] as f64;
            }
        }
        let total: f64 = v.iter().sum();
        if total > 0.0 {
            v.iter_mut().for_each(|x| *x /= total);
        }
    };
    normalised(&mut harmonic);
    normalised(&mut low);
    let mut downbeat = 0usize;
    let score = |p: usize| harmonic[p] + 0.5 * low[p];
    for p in 0..4 {
        if score(p) > score(downbeat) {
            downbeat = p;
        }
    }
    // `anchor` is beat index 0 of the scan; the downbeat sits `downbeat`
    // beats later, so the anchor is `(4 - downbeat) % 4` beats into its bar.
    let anchor_bar_position = ((4 - downbeat) % 4) as u32;
    Grid { bpm, anchor, confidence, anchor_bar_position }
}

impl Grid {
    /// The same beats, re-labelled so that a downbeat falls as close as
    /// possible to `t`. Used to give a grid fitted on drums the bar phase
    /// found on the full mix, where the harmony is.
    pub fn with_downbeat_near(mut self, t: f64) -> Self {
        let k = ((t - self.anchor) / self.interval()).round() as i64;
        self.anchor_bar_position = (-k).rem_euclid(4) as u32;
        self
    }
}

/// Beat times that follow the actual hits rather than a rigid grid.
///
/// `signal` is mono (ideally the drum stem), with sample 0 at `signal_start`
/// seconds of the track. For beats `first..=first + count` of `grid`, finds
/// the transient nearest each expected beat at ~1.5 ms resolution, fits out
/// any tempo error, and keeps the slow part of what is left (a drummer
/// pushing or dragging), not note-to-note swing.
///
/// Returns the beat times in track seconds and whether hits were found
/// often enough to trust; when they were not, the times are the grid's.
pub fn refine_beats(signal: &[f32], signal_start: f64, grid: &Grid, first: i64, count: usize) -> (Vec<f64>, bool) {
    const HOP: usize = 64;
    const WIN: usize = 256;
    let frames = signal.len() / HOP;
    let mut level = vec![0.0f32; frames];
    for (i, l) in level.iter_mut().enumerate() {
        let a = i * HOP;
        let b = (a + WIN).min(signal.len());
        *l = (signal[a..b].iter().map(|v| v * v).sum::<f32>() / WIN as f32).sqrt();
    }
    // Rise in level over ~4.5 ms; the frame's window starts at its index, so
    // the rise is credited to the window's centre.
    let novelty = |i: i64| -> f32 {
        if i < 3 || i as usize >= frames { 0.0 } else { (level[i as usize] - level[i as usize - 3]).max(0.0) }
    };
    let to_frame = |t: f64| ((t - signal_start) * SRF / HOP as f64).round() as i64;
    let frame_seconds = HOP as f64 / SRF;
    let reach = (0.045 / frame_seconds) as i64;

    let pad = 8i64;
    let total = count as i64 + 1 + 2 * pad;
    let mut offset = vec![0.0f64; total as usize];
    let mut strength = vec![0.0f32; total as usize];
    for j in 0..total {
        let centre = to_frame(grid.beat(first - pad + j));
        let (mut best, mut best_i) = (0.0f32, centre);
        for i in centre - reach..=centre + reach {
            let v = novelty(i);
            if v > best {
                best = v;
                best_i = i;
            }
        }
        offset[j as usize] = (best_i - centre) as f64 * frame_seconds;
        strength[j as usize] = best;
    }
    let grid_beats: Vec<f64> = (0..=count as i64).map(|j| grid.beat(first + j)).collect();
    let mut sorted = strength.clone();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let reference = sorted[sorted.len() * 3 / 4];
    if reference <= 1e-5 {
        return (grid_beats, false);
    }
    let mut strong: Vec<bool> = strength.iter().map(|s| *s >= 0.35 * reference).collect();
    if strong.iter().filter(|s| **s).count() < total as usize * 2 / 5 {
        return (grid_beats, false);
    }

    // Line through the offsets (a constant phase error plus a tempo error),
    // refitted twice without the hits that sit far from it.
    let (mut alpha, mut beta) = (0.0f64, 0.0f64);
    for pass in 0..3 {
        let pts: Vec<(f64, f64)> =
            (0..total as usize).filter(|j| strong[*j]).map(|j| (j as f64, offset[j])).collect();
        if pts.len() < 8 {
            return (grid_beats, false);
        }
        let n = pts.len() as f64;
        let mx = pts.iter().map(|p| p.0).sum::<f64>() / n;
        let my = pts.iter().map(|p| p.1).sum::<f64>() / n;
        let sxx: f64 = pts.iter().map(|p| (p.0 - mx).powi(2)).sum();
        let sxy: f64 = pts.iter().map(|p| (p.0 - mx) * (p.1 - my)).sum();
        beta = if sxx > 0.0 { sxy / sxx } else { 0.0 };
        alpha = my - beta * mx;
        if pass < 2 {
            for j in 0..total as usize {
                if strong[j] && (offset[j] - (alpha + beta * j as f64)).abs() > 0.020 {
                    strong[j] = false;
                }
            }
        }
    }

    // What is left once the line is removed, held through weak beats, then
    // median-of-5 and mean-of-3 so only slow drift survives.
    let mut residual = vec![0.0f64; total as usize];
    let mut last = 0.0;
    for j in 0..total as usize {
        if strong[j] {
            last = (offset[j] - (alpha + beta * j as f64)).clamp(-0.025, 0.025);
        }
        residual[j] = last;
    }
    let at = |v: &[f64], j: i64| v[j.clamp(0, total - 1) as usize];
    let median: Vec<f64> = (0..total)
        .map(|j| {
            let mut w = [at(&residual, j - 2), at(&residual, j - 1), at(&residual, j), at(&residual, j + 1), at(&residual, j + 2)];
            w.sort_by(|a, b| a.partial_cmp(b).unwrap());
            w[2]
        })
        .collect();
    let smooth: Vec<f64> = (0..total).map(|j| (at(&median, j - 1) + at(&median, j) + at(&median, j + 1)) / 3.0).collect();

    let beats = (0..=count as i64)
        .map(|j| {
            let i = (j + pad) as usize;
            grid.beat(first + j) + alpha + beta * i as f64 + smooth[i]
        })
        .collect();
    (beats, true)
}
