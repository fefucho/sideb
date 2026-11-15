//! Synthetic test tracks with a known tempo and a known first downbeat, so
//! the grid fit and the beat lock of a rendered mix can be checked against
//! ground truth instead of by ear.

use crate::audio::{Stereo, SRF};

pub struct Spec {
    pub bpm: f64,
    /// MIDI note of the root (36 = C2).
    pub root: i32,
    pub bars: u32,
    /// Seconds of silence before the first downbeat.
    pub lead_in: f64,
    pub seed: u64,
}

struct Rng(u64);

impl Rng {
    fn next(&mut self) -> f32 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        (self.0 >> 40) as f32 / (1u64 << 24) as f32 * 2.0 - 1.0
    }
}

fn hz(midi: i32) -> f64 {
    440.0 * 2f64.powf((midi - 69) as f64 / 12.0)
}

fn add(out: &mut [f32], start: f64, len: f64, mut f: impl FnMut(f64) -> f32) {
    let a = (start * SRF) as usize;
    let count = (len * SRF) as usize;
    for i in 0..count {
        if a + i < out.len() {
            out[a + i] += f(i as f64 / SRF);
        }
    }
}

/// Intro (8 bars, drums and pad), body with bass and a lead, outro (8 bars,
/// drums and bass). Returns the track and the time of its first downbeat.
pub fn generate(spec: &Spec) -> (Stereo, f64) {
    let beat = 60.0 / spec.bpm;
    let total = spec.lead_in + spec.bars as f64 * 4.0 * beat + 1.0;
    let len = (total * SRF) as usize;
    let mut m = vec![0.0f32; len];
    let mut rng = Rng(spec.seed.max(1));
    let tau = std::f64::consts::TAU;
    let progression = [0, 0, 5, 7];

    for bar in 0..spec.bars {
        let intro = bar < 8;
        let outro = bar + 8 >= spec.bars;
        let chord = progression[(bar % 4) as usize];
        for b in 0..4 {
            let t = spec.lead_in + (bar * 4 + b) as f64 * beat;

            // Kick on every beat: a pitch sweep with a fast decay.
            add(&mut m, t, 0.25, |x| {
                let phase = tau * (45.0 * x + (110.0 / 30.0) * (1.0 - (-30.0 * x).exp()));
                (0.8 * phase.sin() * (-9.0 * x).exp()) as f32
            });
            // Clap on 2 and 4.
            if b % 2 == 1 {
                add(&mut m, t, 0.12, |x| 0.25 * rng.next() * (-35.0 * x).exp() as f32);
            }
            // Hat on the off-beat.
            add(&mut m, t + beat / 2.0, 0.05, |x| 0.12 * rng.next() * (-90.0 * x).exp() as f32);

            // Bass: eighth notes on the chord root, silent through the intro.
            if !intro {
                for e in 0..2 {
                    let f = hz(spec.root + chord);
                    add(&mut m, t + e as f64 * beat / 2.0, beat * 0.45, |x| {
                        let s = (tau * f * x).sin() + 0.3 * (tau * 2.0 * f * x).sin();
                        (0.3 * s * (-4.0 * x).exp()) as f32
                    });
                }
            }
        }

        let bar_start = spec.lead_in + (bar * 4) as f64 * beat;
        // Pad: a triad held through the bar, absent in the outro.
        if !outro {
            for (i, interval) in [0, 7, 16].iter().enumerate() {
                let f = hz(spec.root + 24 + chord + interval);
                let bar_len = 4.0 * beat;
                add(&mut m, bar_start, bar_len, |x| {
                    let edge = (x / 0.05).min(1.0) * ((bar_len - x) / 0.05).min(1.0);
                    (0.05 * (tau * f * x + i as f64).sin() * edge) as f32
                });
            }
        }
        // Lead standing in for a vocal: body only, a note per beat.
        if !intro && !outro {
            let melody = [12, 14, 16, 14];
            for b in 0..4 {
                let f = hz(spec.root + 36 + chord + melody[(b + bar as usize) % 4]);
                add(&mut m, bar_start + b as f64 * beat, beat * 0.9, |x| {
                    let vibrato = 0.004 * (tau * 5.5 * x).sin();
                    (0.1 * (tau * f * x * (1.0 + vibrato)).sin() * (-2.5 * x).exp()) as f32
                });
            }
        }
        // Crash on every eighth bar line.
        if bar % 8 == 0 {
            add(&mut m, bar_start, 1.2, |x| 0.15 * rng.next() * (-3.5 * x).exp() as f32);
        }
    }

    (Stereo { ch: [m.clone(), m] }, spec.lead_in)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grid::{self, Envelope};

    #[test]
    fn grid_fit_recovers_tempo_and_downbeat() {
        for (bpm, lead_in) in [(120.0, 0.37), (126.0, 0.21), (98.0, 0.5)] {
            let (audio, first_downbeat) =
                generate(&Spec { bpm, root: 36, bars: 32, lead_in, seed: 7 });
            let env = Envelope::compute(&audio);
            let (first, last) = grid::audible_range(&env);
            let guess = grid::estimate_bpm(&env, first, last);
            let g = grid::fit_grid(&env, first, (first + 60.0).min(last), guess);
            assert!((g.bpm - bpm).abs() < 0.05, "tempo {bpm}: got {}", g.bpm);

            // Some downbeat of the fitted grid must sit on a true downbeat.
            let bar = 4.0 * 60.0 / bpm;
            let offset = (g.beat(0) - first_downbeat).rem_euclid(bar);
            let error = offset.min(bar - offset);
            assert!(error < 0.012, "tempo {bpm}: downbeat off by {:.1} ms", error * 1000.0);
        }
    }
}
