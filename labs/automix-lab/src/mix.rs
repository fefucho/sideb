//! Planning and rendering one transition.
//!
//! The outgoing track (A) and the incoming one (B) overlap for a whole
//! number of bars. Over that overlap the mix tempo glides from A's to B's,
//! both decks follow it beat by beat, and each stem has its own gain curve.
//! Outside the overlap the output is the untouched original audio, so the
//! rendered transition can be spliced between the two songs.
//!
//! Where the overlap sits is decided from the stems: it must be over before
//! B starts singing or drops, and it may skip a long instrumental outro of A
//! but never music A is still singing over.

use crate::audio::{self, Stereo, SRF};
use crate::grid::{self, Envelope, Grid};
use crate::stems::{self, Stems, BASS, DRUMS, GROUPS, KICK, OTHER, VOCALS};
use crate::stretch::{self, TimeMap};
use anyhow::{bail, Result};
use std::path::Path;

pub struct Track {
    pub name: String,
    /// Stable identity for caches (a video id, or the file name).
    pub key: String,
    pub audio: Stereo,
    pub env: Envelope,
}

impl Track {
    pub fn new(name: String, key: String, audio: Stereo) -> Self {
        let env = Envelope::compute(&audio);
        Track { name, key, audio, env }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum StemMode {
    /// HT-Demucs.
    Model,
    /// Frequency split only; no model, no download, no structure evidence.
    Frequency,
}

pub struct Options {
    /// Longest overlap allowed, in bars.
    pub max_bars: u32,
    pub pre_seconds: f64,
    pub post_seconds: f64,
    pub stem_mode: StemMode,
    /// Shift the detected downbeat by this many beats, per deck.
    pub a_downbeat_shift: i64,
    pub b_downbeat_shift: i64,
}

/// One song's side of the transition: the stretch of it that was separated,
/// and the beat grid fitted there.
pub struct Deck {
    /// Track sample of the window's first sample.
    win_start: i64,
    stems: Stems,
    pub grid: Grid,
    /// Whether the grid's beat phase came from the drum stem.
    pub grid_from_drums: bool,
}

/// Everything decided before any audio is rendered.
pub struct Plan {
    pub a: Deck,
    pub b: Deck,
    pub beats: usize,
    /// Track seconds of every beat of the overlap on each deck.
    pub a_beats: Vec<f64>,
    pub b_beats: Vec<f64>,
    /// Whether those follow the actual hits (true) or the rigid grid.
    pub a_refined: bool,
    pub b_refined: bool,
    /// Output seconds of every beat of the overlap, from 0.
    pub beat_times: Vec<f64>,
    /// Beat of the overlap at which B starts singing (`beats` if it does not).
    pub b_vocal_beat: f64,
    /// Bars of B before it sings or drops, if either was found.
    pub b_intro_bars: Option<i64>,
    /// Bars of instrumental outro on A, if A sings in its tail at all.
    pub a_outro_bars: Option<i64>,
    /// Bars of A's outro left unplayed.
    pub a_skipped_bars: i64,
    /// Pitch-content similarity of the two decks over the overlap, 0..1.
    pub harmony: f64,
}

/// Lowest on-grid/off-grid onset ratio at which a grid is trusted enough to
/// stretch against. Provisional: calibrated on very little material.
pub const MIN_GRID_CONFIDENCE: f64 = 1.1;
/// How far the two tempos may differ and still be beat-matched.
pub const MAX_TEMPO_RATIO: f64 = 1.25;
/// Longest overlap, in seconds, whatever the tempo.
const MAX_OVERLAP_SECONDS: f64 = 36.0;
/// Below this pitch-content similarity the two songs are kept from playing
/// their harmony at once. Provisional.
const HARMONY_CLASH: f64 = 0.8;
const WINDOW_SECONDS: f64 = 90.0;

fn n(seconds: f64) -> i64 {
    (seconds * SRF).round() as i64
}

fn build_deck(
    track: &Track,
    from: f64,
    to: f64,
    fit: (f64, f64),
    bpm_guess: f64,
    tag: &str,
    opts: &Options,
    cache: &Path,
) -> Result<Deck> {
    let win_start = n(from);
    let window = track.audio.slice(win_start, (n(to) - win_start) as usize);
    let stems = match opts.stem_mode {
        StemMode::Model => stems::separate(&window, cache, &format!("{}-{tag}", track.key))?,
        StemMode::Frequency => stems::split_by_frequency(&window),
    };

    // Bar phase from the full mix (that is where the harmony is); beat phase
    // and tempo from the drum stem when it is the clearer of the two.
    let mix_grid = grid::fit_grid(&track.env, fit.0, fit.1, bpm_guess);
    let drum_env = Envelope::compute(&stems.stem[DRUMS]);
    let has_drums = audio::rms(&stems.stem[DRUMS].ch[0]) > 0.05 * audio::rms(&window.ch[0]);
    let mut grid = mix_grid.clone();
    let mut grid_from_drums = false;
    if has_drums {
        let mut drum_grid = grid::fit_grid(&drum_env, fit.0 - from, fit.1 - from, mix_grid.bpm);
        drum_grid.anchor += from;
        if drum_grid.confidence >= mix_grid.confidence {
            grid = drum_grid.with_downbeat_near(mix_grid.beat(0));
            grid_from_drums = true;
        }
    }
    Ok(Deck { win_start, stems, grid, grid_from_drums })
}

impl Deck {
    fn span(&self, from: f64, to: f64) -> (usize, usize) {
        let len = self.stems.stem[0].len();
        let a = ((n(from) - self.win_start).max(0) as usize).min(len);
        let b = ((n(to) - self.win_start).max(0) as usize).min(len);
        (a, b.max(a))
    }

    /// RMS of the sum of `which` stems between two track times.
    fn level(&self, which: &[usize], from: f64, to: f64) -> f32 {
        let (a, b) = self.span(from, to);
        if b <= a {
            return 0.0;
        }
        let mut acc = 0.0f32;
        for i in a..b {
            let v: f32 = which.iter().map(|s| self.stems.stem[*s].ch[0][i]).sum();
            acc += v * v;
        }
        (acc / (b - a) as f32).sqrt()
    }

    /// Level of `which` on each of the four beats of bar `bar`.
    fn bar_levels(&self, which: &[usize], bar: i64) -> [f32; 4] {
        let mut out = [0.0; 4];
        for (i, o) in out.iter_mut().enumerate() {
            let k = bar * 4 + i as i64;
            *o = self.level(which, self.grid.beat(k), self.grid.beat(k + 1));
        }
        out
    }

    /// 90th percentile of the per-beat level of `which` over the window.
    fn loud_reference(&self, which: &[usize]) -> f32 {
        let first = self.grid.beat_at_or_before(self.win_start as f64 / SRF) + 1;
        let end = (self.win_start + self.stems.stem[0].len() as i64) as f64 / SRF;
        let mut levels = Vec::new();
        let mut k = first;
        while self.grid.beat(k + 1) < end {
            levels.push(self.level(which, self.grid.beat(k), self.grid.beat(k + 1)));
            k += 1;
        }
        if levels.is_empty() {
            return 0.0;
        }
        levels.sort_by(|a, b| a.partial_cmp(b).unwrap());
        levels[levels.len() * 9 / 10]
    }

    /// Whether bar `bar` is sung: at least two of its beats carry a vocal
    /// that is not just bleed.
    fn bar_sung(&self, bar: i64, reference: f32) -> bool {
        self.bar_levels(&[VOCALS], bar).iter().filter(|v| **v > 0.12 * reference).count() >= 2
    }

    /// Summed pitch-class profile of everything but the drums.
    fn chroma(&self, from: f64, to: f64) -> [f32; 12] {
        let (a, b) = self.span(from, to);
        let mut tonal = Stereo::zeros(b - a);
        for s in [VOCALS, BASS, OTHER] {
            for c in 0..2 {
                for i in a..b {
                    tonal.ch[c][i - a] += self.stems.stem[s].ch[c][i];
                }
            }
        }
        let env = Envelope::compute(&tonal);
        let mut acc = [0.0f32; 12];
        for frame in &env.chroma {
            for (x, v) in acc.iter_mut().zip(frame) {
                *x += v;
            }
        }
        acc
    }
}

pub fn plan(a: &Track, b: &Track, opts: &Options, cache: &Path) -> Result<Plan> {
    let (a_first, a_last) = grid::audible_range(&a.env);
    let (b_first, b_last) = grid::audible_range(&b.env);

    let a_bpm = grid::estimate_bpm(&a.env, (a_last - 90.0).max(a_first), a_last);
    if a_bpm <= 0.0 {
        bail!("{}: demasiado corta para estimar el tempo", a.name);
    }
    let mut b_bpm = grid::estimate_bpm(&b.env, b_first, (b_first + 90.0).min(b_last));
    if b_bpm <= 0.0 {
        bail!("{}: demasiado corta para estimar el tempo", b.name);
    }
    // Count B in A's octave, the way a DJ counts 70 BPM against 140.
    while b_bpm < a_bpm / 1.42 {
        b_bpm *= 2.0;
    }
    while b_bpm > a_bpm * 1.42 {
        b_bpm /= 2.0;
    }

    // Hopeless pairs are turned away before paying for stems.
    let rough = a_bpm / b_bpm;
    if !(1.0 / (MAX_TEMPO_RATIO * 1.03)..=MAX_TEMPO_RATIO * 1.03).contains(&rough) {
        bail!("tempos demasiado lejanos para sincronizar: {a_bpm:.1} y {b_bpm:.1} BPM");
    }

    let a_from = (a_last - WINDOW_SECONDS).max(0.0);
    let mut deck_a = build_deck(
        a,
        a_from,
        (a_last + 2.0).min(a.audio.seconds()),
        ((a_last - 60.0).max(a_first), a_last),
        a_bpm,
        "tail",
        opts,
        cache,
    )?;
    let b_from = (b_first - 2.0).max(0.0);
    let mut deck_b = build_deck(
        b,
        b_from,
        (b_first + WINDOW_SECONDS).min(b.audio.seconds()),
        (b_first, (b_first + 60.0).min(b_last)),
        b_bpm,
        "head",
        opts,
        cache,
    )?;
    let shift = |g: &mut Grid, by: i64| {
        g.anchor_bar_position = (g.anchor_bar_position as i64 - by).rem_euclid(4) as u32;
    };
    shift(&mut deck_a.grid, opts.a_downbeat_shift);
    shift(&mut deck_b.grid, opts.b_downbeat_shift);

    let ratio = deck_a.grid.bpm / deck_b.grid.bpm;
    if !(1.0 / MAX_TEMPO_RATIO..=MAX_TEMPO_RATIO).contains(&ratio) {
        bail!(
            "tempos demasiado lejanos para sincronizar: {:.1} y {:.1} BPM",
            deck_a.grid.bpm,
            deck_b.grid.bpm
        );
    }
    if deck_a.grid.confidence < MIN_GRID_CONFIDENCE || deck_b.grid.confidence < MIN_GRID_CONFIDENCE {
        bail!(
            "grilla de beats poco confiable (A {:.2}, B {:.2}; mínimo {MIN_GRID_CONFIDENCE})",
            deck_a.grid.confidence,
            deck_b.grid.confidence
        );
    }

    // --- B: how long before it sings or drops? The overlap must fit there.
    let b_first_bar = {
        let raw = ((b_first - 0.05 - deck_b.grid.beat(0)) / deck_b.grid.interval()).ceil() as i64;
        raw.div_euclid(4) + if raw.rem_euclid(4) == 0 { 0 } else { 1 }
    };
    let b_bars_available =
        ((b_from + WINDOW_SECONDS - 3.0 - deck_b.grid.beat(b_first_bar * 4)) / (4.0 * deck_b.grid.interval())).floor() as i64;
    let b_loud = deck_b.loud_reference(&[VOCALS, DRUMS, BASS, OTHER]);
    let b_rhythm_loud = deck_b.loud_reference(&[DRUMS, BASS]);
    let rhythm = |bar: i64| -> f32 {
        let l = deck_b.bar_levels(&[DRUMS, BASS], b_first_bar + bar);
        l.iter().sum::<f32>() / 4.0
    };
    let mut b_intro_bars: Option<i64> = None;
    let mut b_vocal_bar: Option<i64> = None;
    for bar in 0..b_bars_available.min(24) {
        let sung = deck_b.bar_sung(b_first_bar + bar, b_loud)
            && (deck_b.bar_sung(b_first_bar + bar + 1, b_loud)
                || deck_b.bar_levels(&[VOCALS], b_first_bar + bar).iter().filter(|v| **v > 0.12 * b_loud).count() >= 3);
        if sung && b_vocal_bar.is_none() {
            b_vocal_bar = Some(bar);
        }
        let drops = bar >= 2
            && b_rhythm_loud > 0.0
            && rhythm(bar) >= 0.6 * b_rhythm_loud
            && (rhythm(bar - 1) + rhythm(bar - 2)) / 2.0 < 0.3 * b_rhythm_loud;
        if (sung || drops) && b_intro_bars.is_none() {
            b_intro_bars = Some(bar);
        }
        if b_intro_bars.is_some() && b_vocal_bar.is_some() {
            break;
        }
    }

    let bar_seconds = 4.0 * 60.0 / ((deck_a.grid.bpm + deck_b.grid.bpm) / 2.0);
    let mut bars = 4i64;
    for candidate in [16i64, 8, 4] {
        if candidate <= opts.max_bars as i64
            && candidate <= b_intro_bars.unwrap_or(16).max(4)
            && candidate as f64 * bar_seconds <= MAX_OVERLAP_SECONDS
            && candidate + 2 <= b_bars_available
        {
            bars = candidate;
            break;
        }
    }

    // --- A: where does it stop singing? A long outro after that is skipped.
    let a_end_bar = deck_a.grid.beat_at_or_before(a_last).div_euclid(4);
    let a_bars_available =
        ((deck_a.grid.beat(a_end_bar * 4) - a_from - 3.0) / (4.0 * deck_a.grid.interval())).floor() as i64;
    if a_bars_available < bars {
        bars = if a_bars_available >= 8 { 8 } else { 4 };
        if a_bars_available < bars {
            bail!("{}: demasiado corta para mezclar", a.name);
        }
    }
    let a_loud = deck_a.loud_reference(&[VOCALS, DRUMS, BASS, OTHER]);
    let a_outro_bars = (1..=a_bars_available).find(|j| deck_a.bar_sung(a_end_bar - j, a_loud)).map(|j| j - 1);
    let a_skipped_bars = match a_outro_bars {
        Some(outro) if outro > bars => (outro - bars).min(16).min(a_bars_available - bars),
        _ => 0,
    };
    let a_last_beat = (a_end_bar - a_skipped_bars) * 4;
    let beats = (bars * 4) as usize;
    let a_first_beat = a_last_beat - beats as i64;
    let b_first_beat = b_first_bar * 4;

    // --- Beats that follow the hits, from the drum stem when there is one.
    let refine = |deck: &Deck, first: i64, from_drums: bool| -> (Vec<f64>, bool) {
        let source = if from_drums { vec![DRUMS] } else { vec![VOCALS, DRUMS, BASS, OTHER] };
        let len = deck.stems.stem[0].len();
        let mono: Vec<f32> = (0..len)
            .map(|i| source.iter().map(|s| deck.stems.stem[*s].ch[0][i] + deck.stems.stem[*s].ch[1][i]).sum::<f32>() * 0.5)
            .collect();
        grid::refine_beats(&mono, deck.win_start as f64 / SRF, &deck.grid, first, beats)
    };
    let (a_beats, a_refined) = refine(&deck_a, a_first_beat, deck_a.grid_from_drums);
    let (b_beats, b_refined) = refine(&deck_b, b_first_beat, deck_b.grid_from_drums);

    // The mix tempo glides between the tempos actually measured on each side.
    let a_local = 60.0 * beats as f64 / (a_beats[beats] - a_beats[0]);
    let b_local = 60.0 * beats as f64 / (b_beats[beats] - b_beats[0]);
    let mut beat_times = Vec::with_capacity(beats + 1);
    let mut t = 0.0;
    for k in 0..=beats {
        beat_times.push(t);
        let progress = (k as f64 + 0.5) / beats as f64;
        t += 60.0 / (a_local + (b_local - a_local) * progress);
    }

    let b_vocal_beat = match b_vocal_bar {
        Some(bar) if bar * 4 < beats as i64 => (bar * 4) as f64,
        _ => beats as f64,
    };

    let pa = deck_a.chroma(a_beats[0], a_beats[beats]);
    let pb = deck_b.chroma(b_beats[0], b_beats[beats]);
    let dot: f32 = pa.iter().zip(&pb).map(|(x, y)| x * y).sum();
    let norm = pa.iter().map(|x| x * x).sum::<f32>().sqrt() * pb.iter().map(|x| x * x).sum::<f32>().sqrt();
    let harmony = if norm > 0.0 { (dot / norm) as f64 } else { 1.0 };

    Ok(Plan {
        a: deck_a,
        b: deck_b,
        beats,
        a_beats,
        b_beats,
        a_refined,
        b_refined,
        beat_times,
        b_vocal_beat,
        b_intro_bars,
        a_outro_bars,
        a_skipped_bars,
        harmony,
    })
}

fn up(x: f64, from: f64, to: f64) -> f32 {
    let p = ((x - from) / (to - from)).clamp(0.0, 1.0);
    (p * std::f64::consts::FRAC_PI_2).sin() as f32
}

fn down(x: f64, from: f64, to: f64) -> f32 {
    let p = ((x - from) / (to - from)).clamp(0.0, 1.0);
    (p * std::f64::consts::FRAC_PI_2).cos() as f32
}

/// Group gains for both decks at beat position `x` of a `k`-beat overlap.
///
/// The "bass swap": B's drums come in early and at full weight but without
/// their low end; on the middle bar line the basses and kick lows trade
/// places and A's drums are gone within a bar; A's harmony drains away
/// through the second half. A stops singing before B starts (`b_vocal`), and
/// when the two songs clash harmonically (`clash`) their harmonies do not
/// overlap at all.
fn bass_swap_gains(x: f64, k: f64, b_vocal: f64, clash: bool) -> ([f32; GROUPS], [f32; GROUPS]) {
    let swap = k / 2.0;
    let mut a = [1.0f32; GROUPS];
    let mut b = [0.0f32; GROUPS];

    a[BASS] = down(x, swap - 0.5, swap);
    a[KICK] = a[BASS];
    a[DRUMS] = down(x, swap, swap + 4.0);
    a[OTHER] = if clash { down(x, swap - 4.0, swap) } else { down(x, swap, k - k / 8.0) };
    a[VOCALS] = down(x, b_vocal - 2.0, b_vocal).min(down(x, swap + k / 4.0, k - k / 8.0));
    if clash {
        a[VOCALS] = a[VOCALS].min(down(x, swap, swap + 4.0));
    }

    b[BASS] = up(x, swap - 0.5, swap);
    b[KICK] = b[BASS];
    b[DRUMS] = 0.85 * up(x, 0.0, (k / 8.0).max(2.0)) + 0.15 * up(x, swap - 0.5, swap);
    b[OTHER] = if clash { up(x, swap - 0.5, swap) } else { 0.7 * up(x, k / 8.0, swap) + 0.3 * up(x, swap, swap + 2.0) };
    b[VOCALS] = 1.0;
    (a, b)
}

pub struct Rendered {
    pub mix: Stereo,
    /// Same excerpt with a plain equal-power crossfade, for comparison.
    pub baseline: Stereo,
    /// Output second at which the overlap starts and ends.
    pub overlap: (f64, f64),
}

const SEAM_LEAD: f64 = 0.5;
const SEAM_FADE: f64 = 0.05;
const WINDOW_MARGIN: f64 = 2.0;

pub fn render(a: &Track, b: &Track, plan: &Plan, opts: &Options) -> Result<Rendered> {
    let k = plan.beats;
    let (a_start, a_end) = (plan.a_beats[0], plan.a_beats[k]);
    let (b_start, b_end) = (plan.b_beats[0], plan.b_beats[k]);
    let overlap_len = n(plan.beat_times[k]);
    let pre = n(opts.pre_seconds.min(a_start));
    let post = n(opts.post_seconds.min(b.audio.seconds() - b_end).max(1.0));
    let lead = n(SEAM_LEAD);
    let fade = n(SEAM_FADE);

    // The stretch each deck is rendered from, cut out of its separated window.
    let a_src_start = n(a_start - WINDOW_MARGIN - SEAM_LEAD);
    let a_src_len = (n(a_end + WINDOW_MARGIN) - a_src_start) as usize;
    let b_src_start = n(b_start - WINDOW_MARGIN);
    let b_src_len = (n(b_end + WINDOW_MARGIN + SEAM_LEAD) - b_src_start) as usize;
    let a_src = plan.a.stems.planar(a_src_start - plan.a.win_start, a_src_len);
    let b_src = plan.b.stems.planar(b_src_start - plan.b.win_start, b_src_len);

    // Time maps: output sample (0 = first beat of the overlap) -> source sample.
    let out_knots: Vec<f64> = plan.beat_times.iter().map(|t| t * SRF).collect();
    let a_knots: Vec<f64> = plan.a_beats.iter().map(|t| t * SRF - a_src_start as f64).collect();
    let b_knots: Vec<f64> = plan.b_beats.iter().map(|t| t * SRF - b_src_start as f64).collect();
    let slope = |knots: &[f64], i: usize| (knots[i + 1] - knots[i]) / (out_knots[i + 1] - out_knots[i]);
    let a_map = TimeMap {
        rate_before: 1.0,
        rate_after: slope(&a_knots, k - 1),
        out: out_knots.clone(),
        input: a_knots.clone(),
    };
    let b_map = TimeMap {
        rate_before: slope(&b_knots, 0),
        rate_after: 1.0,
        out: out_knots.clone(),
        input: b_knots.clone(),
    };

    // A is processed from just before the overlap to its end; B from the
    // start of the overlap to just after it.
    let a_proc = stretch::render(&a_src, &a_map, -lead, (overlap_len + lead) as usize);
    let b_proc = stretch::render(&b_src, &b_map, 0, (overlap_len + lead) as usize);

    let total = (pre + overlap_len + post) as usize;
    let mut mix = Stereo::zeros(total);
    let mut baseline = Stereo::zeros(total);
    let a_start_n = n(a_start);
    let b_start_n = n(b_start);
    let b_end_n = n(b_end);
    let clash = plan.harmony < HARMONY_CLASH;
    let read = |track: &Stereo, c: usize, pos: i64| -> f32 {
        if pos >= 0 && (pos as usize) < track.len() { track.ch[c][pos as usize] } else { 0.0 }
    };

    let mut beat = 0usize;
    for i in 0..total {
        let o = i as i64 - pre;

        // Beat position inside the overlap, for the gain curves.
        let x = if o <= 0 {
            0.0
        } else if o >= overlap_len {
            k as f64
        } else {
            while beat + 1 < k && (o as f64) >= out_knots[beat + 1] {
                beat += 1;
            }
            beat as f64 + (o as f64 - out_knots[beat]) / (out_knots[beat + 1] - out_knots[beat])
        };
        let (ga, gb) = bass_swap_gains(x, k as f64, plan.b_vocal_beat, clash);

        for c in 0..2 {
            // Deck A: original, then (after a short seam) its processed stems.
            let a_orig = read(&a.audio, c, a_start_n + o);
            let a_val = if o < -lead {
                a_orig
            } else if o < overlap_len {
                let j = (o + lead) as usize;
                let processed: f32 = (0..GROUPS).map(|s| ga[s] * a_proc[2 * s + c][j]).sum();
                let w = ((o + lead) as f32 / fade as f32).clamp(0.0, 1.0);
                a_orig * (1.0 - w) + processed * w
            } else {
                0.0
            };

            // Deck B: processed stems, then (after a short seam) the original.
            let b_orig = read(&b.audio, c, b_end_n + (o - overlap_len));
            let b_val = if o < 0 {
                0.0
            } else if o < overlap_len + lead {
                let j = o as usize;
                let processed: f32 = (0..GROUPS).map(|s| gb[s] * b_proc[2 * s + c][j]).sum();
                let w = ((o - (overlap_len + lead - fade)) as f32 / fade as f32).clamp(0.0, 1.0);
                processed * (1.0 - w) + b_orig * w
            } else {
                b_orig
            };
            mix.ch[c][i] = a_val + b_val;

            // Baseline: both at their own tempo, equal-power crossfade.
            let p = (o as f64 / overlap_len as f64).clamp(0.0, 1.0);
            let fa = (p * std::f64::consts::FRAC_PI_2).cos() as f32;
            let fb = (p * std::f64::consts::FRAC_PI_2).sin() as f32;
            baseline.ch[c][i] = fa * read(&a.audio, c, a_start_n + o) + fb * read(&b.audio, c, b_start_n + o);
        }
    }

    // Only the overlap is ever gain-ridden: outside it the output has to stay
    // the untouched original, or the splice back onto the song would show.
    // The ceiling is whatever the louder original already reaches.
    let peak_of = |t: &Stereo| t.ch.iter().flatten().fold(0.0f32, |m, v| m.max(v.abs()));
    let ceiling = peak_of(&a.audio).max(peak_of(&b.audio)).max(0.5);
    let region = ((pre - lead).max(0) as usize, ((pre + overlap_len + lead) as usize).min(total));
    limit(&mut mix, region, ceiling);
    limit(&mut baseline, region, ceiling);
    let overlap = (pre as f64 / SRF, (pre + overlap_len) as f64 / SRF);
    Ok(Rendered { mix, baseline, overlap })
}

pub fn harmony_clashes(plan: &Plan) -> bool {
    plan.harmony < HARMONY_CLASH
}

/// Slow gain riding that keeps the sum of two songs under full scale without
/// audible pumping: per-block peaks, widened, then interpolated.
fn limit(audio: &mut Stereo, region: (usize, usize), ceiling: f32) {
    let block = 441usize;
    let blocks = audio.len() / block + 1;
    let mut gain = vec![1.0f32; blocks];
    for (bi, g) in gain.iter_mut().enumerate() {
        let a = bi * block;
        let b = ((bi + 1) * block).min(audio.len());
        let mut peak = 0.0f32;
        for c in 0..2 {
            for v in &audio.ch[c][a..b] {
                peak = peak.max(v.abs());
            }
        }
        if peak > ceiling && a >= region.0 && b <= region.1 {
            *g = ceiling / peak;
        }
    }
    // Hold each reduction for 150 ms either side, then smooth over 100 ms.
    let hold = 15i64;
    let widened: Vec<f32> = (0..blocks as i64)
        .map(|i| {
            let a = (i - hold).max(0) as usize;
            let b = ((i + hold + 1) as usize).min(blocks);
            gain[a..b].iter().cloned().fold(1.0, f32::min)
        })
        .collect();
    let smooth = 10i64;
    let smoothed: Vec<f32> = (0..blocks as i64)
        .map(|i| {
            let a = (i - smooth).max(0) as usize;
            let b = ((i + smooth + 1) as usize).min(blocks);
            // Taking the minimum with the widened value keeps the guarantee.
            (widened[a..b].iter().sum::<f32>() / (b - a) as f32).min(widened[i as usize])
        })
        .collect();
    for i in 0..audio.len() {
        let pos = i as f32 / block as f32;
        let b0 = (pos.floor() as usize).min(blocks - 1);
        let b1 = (b0 + 1).min(blocks - 1);
        let g = smoothed[b0] + (smoothed[b1] - smoothed[b0]) * (pos - b0 as f32);
        let g = g.min(smoothed[b0]).min(smoothed[b1]).max(0.0);
        for c in 0..2 {
            audio.ch[c][i] *= g;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grid::FPS;
    use crate::synth::{generate, Spec};

    /// Worst distance, in milliseconds, between where a beat should fall in
    /// the rendered overlap and the nearest strong onset actually there.
    fn worst_beat_error(audio: &Stereo, overlap_start: f64, beat_times: &[f64]) -> f64 {
        let env = Envelope::compute(audio);
        let mut worst = 0.0f64;
        for t in beat_times {
            let centre = ((overlap_start + t) * FPS).round() as i64;
            let (mut best, mut best_frame) = (0.0f32, centre);
            for frame in centre - 12..=centre + 12 {
                if frame >= 0 && (frame as usize) < env.low.len() && env.low[frame as usize] > best {
                    best = env.low[frame as usize];
                    best_frame = frame;
                }
            }
            worst = worst.max((best_frame - centre).abs() as f64 / FPS * 1000.0);
        }
        worst
    }

    #[test]
    fn both_decks_stay_on_the_mix_grid() {
        let (a, _) = generate(&Spec { bpm: 120.0, root: 36, bars: 40, lead_in: 0.37, seed: 7 });
        let (b, _) = generate(&Spec { bpm: 126.0, root: 38, bars: 40, lead_in: 0.21, seed: 9 });
        let a = Track::new("a".into(), "a".into(), a);
        let b = Track::new("b".into(), "b".into(), b);
        let opts = Options {
            max_bars: 16,
            pre_seconds: 8.0,
            post_seconds: 8.0,
            stem_mode: StemMode::Frequency,
            a_downbeat_shift: 0,
            b_downbeat_shift: 0,
        };
        let plan = plan(&a, &b, &opts, Path::new("unused")).unwrap();
        assert_eq!(plan.beats, 64);
        let rendered = render(&a, &b, &plan, &opts).unwrap();

        // Kicks of whichever deck is audible must sit on the planned beats
        // through the whole overlap: A at the start, both in the middle, B at
        // the end. A plain crossfade of 120 against 126 BPM cannot do that.
        let mixed = worst_beat_error(&rendered.mix, rendered.overlap.0, &plan.beat_times);
        let plain = worst_beat_error(&rendered.baseline, rendered.overlap.0, &plan.beat_times);
        assert!(mixed <= 20.0, "beats drift {mixed:.0} ms in the mix");
        assert!(plain > 60.0, "the baseline was expected to drift, got {plain:.0} ms");

        // The seams hand over to the untouched originals.
        let first = rendered.mix.ch[0][1000];
        let original = a.audio.ch[0][(plan.a_beats[0] * SRF).round() as usize - (8.0 * SRF) as usize + 1000];
        assert!((first - original).abs() < 1e-4);
        let peak_of = |t: &Stereo| t.ch[0].iter().fold(0.0f32, |m, v| m.max(v.abs()));
        let ceiling = peak_of(&a.audio).max(peak_of(&b.audio));
        let peak = peak_of(&rendered.mix);
        assert!(peak <= ceiling * 1.001, "peak {peak} over the originals' {ceiling}");
    }
}
