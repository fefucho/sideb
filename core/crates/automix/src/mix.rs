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
use anyhow::Result;
use std::path::Path;

/// Why a full beat-matched mix was not planned. Everything but
/// [`Refusal::Other`] is a judgement about the two songs, not a failure.
#[derive(Debug, thiserror::Error)]
pub enum Refusal {
    #[error("tempos demasiado lejanos para sincronizar: {a:.1} y {b:.1} BPM")]
    TempoGap { a: f64, b: f64 },
    #[error("grilla de beats poco confiable (A {a:.2}, B {b:.2}; mínimo {MIN_GRID_CONFIDENCE})")]
    WeakGrid { a: f64, b: f64 },
    #[error("«{0}» es demasiado corta para mezclar")]
    TooShort(String),
    #[error(transparent)]
    Cancelled(#[from] Cancelled),
    #[error(transparent)]
    Other(#[from] anyhow::Error),
}

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
    /// HT-Demucs. Downloads the model if it is not on disk yet (blocking).
    Model,
    /// Frequency split only; no model, no download, no structure evidence.
    Frequency,
    /// [`StemMode::Model`] when the model is already on disk, else
    /// [`StemMode::Frequency`] for this transition and the model downloads in
    /// the background for the next ones.
    Auto,
}

#[derive(Clone, Debug)]
pub struct Options {
    /// Longest overlap allowed, in bars.
    pub max_bars: u32,
    /// Seconds of A kept, untouched, before anything changes.
    pub pre_seconds: f64,
    /// Seconds of B kept after the transition; infinite keeps all the rest.
    pub post_seconds: f64,
    pub stem_mode: StemMode,
    /// Shift the detected downbeat by this many beats, per deck.
    pub a_downbeat_shift: i64,
    pub b_downbeat_shift: i64,
    /// Linear gain baked into each song, for players that level tracks.
    pub a_gain: f32,
    pub b_gain: f32,
    /// Also render the plain-crossfade comparison.
    pub baseline: bool,
    /// Set from another thread to abandon the work at its next checkpoint
    /// (between stages; a stem separation in progress runs to its end).
    pub cancel: Option<std::sync::Arc<std::sync::atomic::AtomicBool>>,
}

/// What [`crate::prepare`] fails with when [`Options::cancel`] was set.
#[derive(Debug, thiserror::Error)]
#[error("preparación cancelada")]
pub struct Cancelled;

impl Options {
    pub(crate) fn check_cancel(&self) -> std::result::Result<(), Cancelled> {
        match &self.cancel {
            Some(flag) if flag.load(std::sync::atomic::Ordering::Relaxed) => Err(Cancelled),
            _ => Ok(()),
        }
    }
}

impl Default for Options {
    fn default() -> Self {
        Options {
            max_bars: 16,
            pre_seconds: 8.0,
            post_seconds: f64::INFINITY,
            stem_mode: StemMode::Auto,
            a_downbeat_shift: 0,
            b_downbeat_shift: 0,
            a_gain: 1.0,
            b_gain: 1.0,
            baseline: true,
            cancel: None,
        }
    }
}

/// One song's side of the transition: the stretch of it that was separated,
/// and the beat grid fitted there.
pub struct Deck {
    /// Track sample of the window's first sample.
    pub(crate) win_start: i64,
    pub(crate) stems: Stems,
    pub grid: Grid,
    /// Whether the grid's beat phase came from the drum stem.
    pub grid_from_drums: bool,
    /// Level of the "vocal band" (400 Hz to 3 kHz) per 10 ms frame from
    /// `win_start`, on the frequency split only. Read as a per-beat median it
    /// is the sustained level of voices, leads and pads: a bass line sits
    /// below the band, hats above it, and snares and claps are too short to
    /// move a median. Empty on a deck made from the model's stems, which has
    /// the vocal stem instead.
    tonal: Vec<f32>,
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
    /// What the decks hold: the model's stems ([`StemMode::Model`], a plan
    /// that knows where each song sings) or the frequency split
    /// ([`StemMode::Frequency`], one that guesses from band energies).
    pub stem_mode: StemMode,
    /// Seconds of audio the model separated for this plan (0 when the cache
    /// had them, and for a plan on the frequency split).
    pub separated_seconds: f64,
}

/// Lowest on-grid/off-grid onset ratio at which a grid is trusted enough to
/// stretch against. Provisional: calibrated on very little material.
pub const MIN_GRID_CONFIDENCE: f64 = 1.1;
/// How far the two tempos may differ and still be beat-matched.
pub const MAX_TEMPO_RATIO: f64 = 1.25;
/// Longest overlap, in seconds, whatever the tempo.
const MAX_OVERLAP_SECONDS: f64 = 42.0;
/// Below this pitch-content similarity the two songs are kept from playing
/// their harmony at once. Provisional.
const HARMONY_CLASH: f64 = 0.8;
/// Longest overlap, in bars, planned when nothing says where B starts singing.
const MAX_BLIND_BARS: i64 = 8;
/// Bars of overlap a plan with the vocal stem takes at least, harmony allowing
/// (double when the tempos are close), even when B starts singing at once.
const VOCAL_SWAP_BARS: i64 = 8;
/// Bars of an instrumental intro (B) or outro (A), read from band energies,
/// that are trusted enough to plan a long overlap around.
const CLEAR_INSTRUMENTAL_BARS: i64 = 6;
/// On the frequency split, B is taken to start singing (or leading) at the
/// first bar whose sustained vocal-band level (see [`Deck::tonal`]) is this many
/// times what its first bars have, and keeps it the bar after (a lower step).
/// Provisional.
const STEP_UP: f32 = 1.4;
/// ...and A's outro is the bars at its end whose vocal-band level is below this
/// fraction of its body's (the median of the bars before). Provisional.
const OUTRO_RATIO: f32 = 0.6;

fn n(seconds: f64) -> i64 {
    (seconds * SRF).round() as i64
}

/// A deck on the frequency split of its window: no model, no vocal or drum
/// stem. Cheap enough that the fast plan costs nothing.
fn build_deck_fast(track: &Track, from: f64, to: f64, fit: (f64, f64), bpm_guess: f64) -> Deck {
    let win_start = n(from);
    let window = track.audio.slice(win_start, (n(to) - win_start).max(0) as usize);
    let stems = stems::split_by_frequency(&window);
    let grid = grid::fit_grid(&track.env, fit.0, fit.1, bpm_guess);
    // The "vocal band": 400 Hz to 3 kHz, above where a bass line and a kick
    // leak into the mids and below the hats.
    let band = audio::lowpass4(&audio::highpass4(&window, 400.0), 3000.0);
    let mono = band.mono();
    let tonal: Vec<f32> = (0..mono.len() / 441)
        .map(|f| {
            let slice = &mono[f * 441..(f * 441 + 882).min(mono.len())];
            audio::rms(slice)
        })
        .collect();
    Deck { win_start, stems, grid, grid_from_drums: false, tonal }
}

/// A deck on the model's stems of `win_start..`.
fn build_deck_stems(track: &Track, win_start: i64, stems: Stems, fit: (f64, f64), bpm_guess: f64) -> Deck {
    let from = win_start as f64 / SRF;
    let window = track.audio.slice(win_start, stems.stem[0].len());
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
    Deck { win_start, stems, grid, grid_from_drums, tonal: Vec::new() }
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

    /// Median [`Deck::tonal`] level between two track times: the sustained
    /// level, which a snare or a clap in the band does not move.
    fn tonal_level(&self, from: f64, to: f64) -> f32 {
        let start = self.win_start as f64 / SRF;
        let a = (((from - start) * crate::grid::FPS).round().max(0.0) as usize).min(self.tonal.len());
        let b = (((to - start) * crate::grid::FPS).round().max(0.0) as usize).min(self.tonal.len());
        if b <= a {
            return 0.0;
        }
        let mut frames = self.tonal[a..b].to_vec();
        frames.sort_by(|x, y| x.partial_cmp(y).unwrap());
        frames[frames.len() / 2]
    }

    /// 90th percentile of the per-beat tonal level over the window.
    fn tonal_reference(&self) -> f32 {
        let first = self.grid.beat_at_or_before(self.win_start as f64 / SRF) + 1;
        let end = (self.win_start + self.stems.stem[0].len() as i64) as f64 / SRF;
        let mut levels = Vec::new();
        let mut k = first;
        while self.grid.beat(k + 1) < end {
            levels.push(self.tonal_level(self.grid.beat(k), self.grid.beat(k + 1)));
            k += 1;
        }
        if levels.is_empty() {
            return 0.0;
        }
        levels.sort_by(|a, b| a.partial_cmp(b).unwrap());
        levels[levels.len() * 9 / 10]
    }

    /// Mean tonal energy of bar `bar`.
    fn bar_tonal(&self, bar: i64) -> f32 {
        self.tonal_level(self.grid.beat(bar * 4), self.grid.beat(bar * 4 + 4))
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

/// Tempo of each song in the octave a DJ would count them in, before any
/// stems: A from its end, B from its start, B moved by powers of two to sit
/// within 1.42x of A. `None` when a song is too short to say.
pub fn rough_tempos(a: &Track, b: &Track) -> Option<(f64, f64)> {
    let (a_first, a_last) = grid::audible_range(&a.env);
    let (b_first, b_last) = grid::audible_range(&b.env);
    let a_bpm = grid::estimate_bpm(&a.env, (a_last - 90.0).max(a_first), a_last);
    let mut b_bpm = grid::estimate_bpm(&b.env, b_first, (b_first + 90.0).min(b_last));
    if a_bpm <= 0.0 || b_bpm <= 0.0 {
        return None;
    }
    while b_bpm < a_bpm / 1.42 {
        b_bpm *= 2.0;
    }
    while b_bpm > a_bpm * 1.42 {
        b_bpm /= 2.0;
    }
    Some((a_bpm, b_bpm))
}

/// Whether two rough tempos can be beat-matched at all.
pub fn tempos_compatible(a_bpm: f64, b_bpm: f64) -> bool {
    (1.0 / (MAX_TEMPO_RATIO * 1.03)..=MAX_TEMPO_RATIO * 1.03).contains(&(a_bpm / b_bpm))
}

/// Which separation a plan is made from.
#[derive(Clone, Copy)]
pub enum PlanKind<'a> {
    /// The frequency split: no model, a plan that guesses where the songs
    /// sing from band energies (the "fast" version).
    Fast,
    /// The model's stems of the spans [`crate::prefetch`] separates, from
    /// `cache` (separated now if a prefetch has not): a plan that knows where
    /// each song sings (the "stems" version).
    Stems { cache: &'a Path, priority: crate::model::Priority },
}

/// The fast plan: see [`PlanKind::Fast`].
pub fn plan(a: &Track, b: &Track, opts: &Options) -> std::result::Result<Plan, Refusal> {
    plan_with(a, b, opts, PlanKind::Fast)
}

/// The vocal-aware plan on the model's stems: see [`PlanKind::Stems`].
pub fn plan_stems(a: &Track, b: &Track, opts: &Options, cache: &Path, priority: crate::model::Priority) -> std::result::Result<Plan, Refusal> {
    plan_with(a, b, opts, PlanKind::Stems { cache, priority })
}

fn plan_with(a: &Track, b: &Track, opts: &Options, kind: PlanKind) -> std::result::Result<Plan, Refusal> {
    let (a_first, a_last) = grid::audible_range(&a.env);
    let (b_first, b_last) = grid::audible_range(&b.env);

    let Some((a_bpm, b_bpm)) = rough_tempos(a, b) else {
        let short = if grid::estimate_bpm(&a.env, (a_last - 90.0).max(a_first), a_last) <= 0.0 { a } else { b };
        return Err(Refusal::TooShort(short.name.clone()));
    };
    // Hopeless pairs are turned away before paying for stems.
    if !tempos_compatible(a_bpm, b_bpm) {
        return Err(Refusal::TempoGap { a: a_bpm, b: b_bpm });
    }
    opts.check_cancel()?;

    // The stretch of each song the plan reads: the last of A and the first of
    // B, the same ones a prefetch separates.
    let (a_span, b_span) = (crate::prefetch::tail_span(a), crate::prefetch::head_span(b));
    let a_fit = ((a_last - 60.0).max(a_first), a_last);
    let b_fit = (b_first, (b_first + 60.0).min(b_last));
    let stems_mode = matches!(kind, PlanKind::Stems { .. });
    let (mut deck_a, mut deck_b, separated_seconds) = match kind {
        PlanKind::Fast => (
            build_deck_fast(a, a_span.0 as f64 / SRF, a_span.1 as f64 / SRF, a_fit, a_bpm),
            build_deck_fast(b, b_span.0 as f64 / SRF, b_span.1 as f64 / SRF, b_fit, b_bpm),
            0.0,
        ),
        PlanKind::Stems { cache, priority } => {
            let cancel = opts.cancel.as_deref();
            let sa = stems::separate_span(&a.audio, a_span, cache, &format!("{}-tail", a.key), cancel, priority)?;
            opts.check_cancel()?;
            let sb = stems::separate_span(&b.audio, b_span, cache, &format!("{}-head", b.key), cancel, priority)?;
            let seconds = sa.model_seconds + sb.model_seconds;
            (
                build_deck_stems(a, sa.start, sa.stems, a_fit, a_bpm),
                build_deck_stems(b, sb.start, sb.stems, b_fit, b_bpm),
                seconds,
            )
        }
    };
    opts.check_cancel()?;
    let shift = |g: &mut Grid, by: i64| {
        g.anchor_bar_position = (g.anchor_bar_position as i64 - by).rem_euclid(4) as u32;
    };
    shift(&mut deck_a.grid, opts.a_downbeat_shift);
    shift(&mut deck_b.grid, opts.b_downbeat_shift);

    let ratio = deck_a.grid.bpm / deck_b.grid.bpm;
    if !(1.0 / MAX_TEMPO_RATIO..=MAX_TEMPO_RATIO).contains(&ratio) {
        return Err(Refusal::TempoGap { a: deck_a.grid.bpm, b: deck_b.grid.bpm });
    }
    if deck_a.grid.confidence < MIN_GRID_CONFIDENCE || deck_b.grid.confidence < MIN_GRID_CONFIDENCE {
        return Err(Refusal::WeakGrid { a: deck_a.grid.confidence, b: deck_b.grid.confidence });
    }
    let a_win_start = deck_a.win_start as f64 / SRF;
    let b_win_end = (deck_b.win_start + deck_b.stems.stem[0].len() as i64) as f64 / SRF;

    // --- B: how long before it sings or drops? The overlap must fit there.
    // With the vocal stem "sings" is read from it; without, from the mid band
    // (a bar is "busy" once it reaches half the song's loud level there).
    let b_first_bar = {
        let raw = ((b_first - 0.05 - deck_b.grid.beat(0)) / deck_b.grid.interval()).ceil() as i64;
        raw.div_euclid(4) + if raw.rem_euclid(4) == 0 { 0 } else { 1 }
    };
    let b_bars_available = ((b_win_end - 3.0 - deck_b.grid.beat(b_first_bar * 4)) / (4.0 * deck_b.grid.interval())).floor() as i64;
    let b_loud = deck_b.loud_reference(&[VOCALS, DRUMS, BASS, OTHER]);
    let b_mid = deck_b.tonal_reference();
    let b_base = {
        let mut first: Vec<f32> = (0..3).map(|i| deck_b.bar_tonal(b_first_bar + i)).collect();
        first.sort_by(|x, y| x.partial_cmp(y).unwrap());
        first[1]
    };
    let b_rhythm_loud = deck_b.loud_reference(&[DRUMS, BASS]);
    let rhythm = |bar: i64| -> f32 {
        let l = deck_b.bar_levels(&[DRUMS, BASS], b_first_bar + bar);
        l.iter().sum::<f32>() / 4.0
    };
    let b_sings = |bar: i64| -> bool {
        if stems_mode {
            deck_b.bar_sung(b_first_bar + bar, b_loud)
                && (deck_b.bar_sung(b_first_bar + bar + 1, b_loud)
                    || deck_b.bar_levels(&[VOCALS], b_first_bar + bar).iter().filter(|v| **v > 0.12 * b_loud).count() >= 3)
        } else {
            // A step up from where B starts, that holds: the cheap stand-in
            // for a voice or a lead coming in over an instrumental intro.
            bar >= 2
                && deck_b.bar_tonal(b_first_bar + bar) >= (STEP_UP * b_base).max(0.3 * b_mid)
                && deck_b.bar_tonal(b_first_bar + bar + 1) >= ((1.0 + 0.5 * (STEP_UP - 1.0)) * b_base).max(0.3 * b_mid)
        }
    };
    let mut b_intro_bars: Option<i64> = None;
    let mut b_vocal_bar: Option<i64> = None;
    for bar in 0..b_bars_available.min(24) {
        let sung = b_sings(bar);
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

    // --- A: where does it stop singing? Everything after that is outro.
    let a_end_bar = deck_a.grid.beat_at_or_before(a_last).div_euclid(4);
    let a_bars_available = ((deck_a.grid.beat(a_end_bar * 4) - a_win_start - 3.0) / (4.0 * deck_a.grid.interval())).floor() as i64;
    if a_bars_available < 4 {
        return Err(Refusal::TooShort(a.name.clone()));
    }
    if b_bars_available < 4 {
        return Err(Refusal::TooShort(b.name.clone()));
    }
    let a_loud = deck_a.loud_reference(&[VOCALS, DRUMS, BASS, OTHER]);
    let a_body = {
        let mut bars: Vec<f32> = (1..=a_bars_available.min(24)).map(|j| deck_a.bar_tonal(a_end_bar - j)).collect();
        bars.sort_by(|x, y| x.partial_cmp(y).unwrap());
        bars[bars.len() / 2]
    };
    let a_outro_bars = (1..=a_bars_available)
        .find(|j| if stems_mode { deck_a.bar_sung(a_end_bar - j, a_loud) } else { deck_a.bar_tonal(a_end_bar - j) >= OUTRO_RATIO * a_body })
        .map(|j| j - 1);

    // --- How long. B's intro bounds the overlap: it has to be over before B
    // sings or drops. Unless A leaves an instrumental outro at least as long:
    // then B may sing over it, the way a DJ brings a verse in over a beat.
    // That second reading is dropped when the two songs clash harmonically.
    //
    // With the vocal stem the limits are what it says. Without it, only an
    // intro (or outro) of CLEAR_INSTRUMENTAL_BARS or more is taken at its
    // word; anything shorter keeps the overlap short, and a song with no
    // visible structure is capped at MAX_BLIND_BARS.
    let (b_limit, a_outro_bars) = if stems_mode {
        (b_intro_bars.unwrap_or(16).max(4), a_outro_bars)
    } else {
        let limit = match b_intro_bars {
            Some(bars) if bars >= CLEAR_INSTRUMENTAL_BARS => bars.min(16),
            Some(bars) => bars.max(4),
            None => MAX_BLIND_BARS,
        };
        (limit, a_outro_bars.filter(|o| *o >= CLEAR_INSTRUMENTAL_BARS))
    };
    let a_limit = if stems_mode { a_outro_bars.unwrap_or(16) } else { a_outro_bars.unwrap_or(0) };
    let bar_seconds = 4.0 * 60.0 / ((deck_a.grid.bpm + deck_b.grid.bpm) / 2.0);
    let choose = |limit: i64| -> i64 {
        [16i64, 8, 4]
            .into_iter()
            .find(|c| {
                *c <= opts.max_bars as i64
                    && *c <= limit
                    && *c as f64 * bar_seconds <= MAX_OVERLAP_SECONDS
                    && *c + 2 <= b_bars_available
                    && *c <= a_bars_available
            })
            .unwrap_or(4)
    };
    let b_first_beat = b_first_bar * 4;
    let refine = |deck: &Deck, first: i64, count: usize| -> (Vec<f64>, bool) {
        let source = if deck.grid_from_drums { vec![DRUMS] } else { vec![VOCALS, DRUMS, BASS, OTHER] };
        let len = deck.stems.stem[0].len();
        let mono: Vec<f32> = (0..len)
            .map(|i| source.iter().map(|s| deck.stems.stem[*s].ch[0][i] + deck.stems.stem[*s].ch[1][i]).sum::<f32>() * 0.5)
            .collect();
        grid::refine_beats(&mono, deck.win_start as f64 / SRF, &deck.grid, first, count)
    };

    // With the vocal stem a long overlap does not need B to stay silent: A's
    // voice is faded out before B's comes in (see `bass_swap_gains`) and A's
    // instrumental plays under B's, so the overlap is at least
    // `VOCAL_SWAP_BARS` (16 when the tempos are within 10% of each other, so
    // the glide between them is gentle) unless the harmonies clash: the loop
    // below then tries the next shorter overlap, down to what B's intro allows.
    let swap_floor = match (stems_mode, ratio) {
        (false, _) => 0,
        (true, r) if (1.0 / 1.10..=1.10).contains(&r) => 2 * VOCAL_SWAP_BARS,
        (true, _) => VOCAL_SWAP_BARS,
    };
    let mut bars = choose(b_limit.max(a_limit).max(swap_floor));
    let (beats, a_skipped_bars, a_beats, a_refined, b_beats, b_refined, harmony) = loop {
        let a_skipped_bars = match a_outro_bars {
            Some(outro) if outro > bars => (outro - bars).min(16).min(a_bars_available - bars),
            _ => 0,
        };
        let beats = (bars * 4) as usize;
        let a_first_beat = (a_end_bar - a_skipped_bars) * 4 - beats as i64;

        // Beats that follow the hits, from the drum stem when there is one.
        let (a_beats, a_refined) = refine(&deck_a, a_first_beat, beats);
        let (b_beats, b_refined) = refine(&deck_b, b_first_beat, beats);

        let pa = deck_a.chroma(a_beats[0], a_beats[beats]);
        let pb = deck_b.chroma(b_beats[0], b_beats[beats]);
        let dot: f32 = pa.iter().zip(&pb).map(|(x, y)| x * y).sum();
        let norm = pa.iter().map(|x| x * x).sum::<f32>().sqrt() * pb.iter().map(|x| x * x).sum::<f32>().sqrt();
        let harmony = if norm > 0.0 { (dot / norm) as f64 } else { 1.0 };

        let shorter = choose(bars - 1).max(choose(b_limit));
        if harmony < HARMONY_CLASH && shorter < bars {
            bars = shorter;
            continue;
        }
        break (beats, a_skipped_bars, a_beats, a_refined, b_beats, b_refined, harmony);
    };

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
        Some(bar) if stems_mode && bar * 4 < beats as i64 => (bar * 4) as f64,
        _ => beats as f64,
    };

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
        stem_mode: if stems_mode { StemMode::Model } else { StemMode::Frequency },
        separated_seconds,
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
    // A's voice leaves before B's arrives: over the bar up to B's entry, or the
    // first bar of the overlap if B sings from the start.
    let leave_from = (b_vocal - 4.0).max(0.0);
    a[VOCALS] = down(x, leave_from, b_vocal.max(leave_from + 4.0)).min(down(x, swap + k / 4.0, k - k / 8.0));
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

/// Gains for a mix on the frequency split, where [`BASS`] is everything under
/// 180 Hz, [`OTHER`] 180 Hz to 2.5 kHz (voices, leads, snares) and [`DRUMS`]
/// everything above (hats, air): a bass swap on the middle bar line, the highs
/// of B coming in gradually from the first eighth and A's going out after the
/// swap, and the mids crossing over in the middle 40% of the overlap (a bar or
/// two, not all of it) so the two voices are never up together for long; 20%
/// if the harmonies clash.
fn eq_swap_gains(x: f64, k: f64, clash: bool) -> ([f32; GROUPS], [f32; GROUPS]) {
    let swap = k / 2.0;
    let mut a = [1.0f32; GROUPS];
    let mut b = [0.0f32; GROUPS];
    a[BASS] = down(x, swap - 1.0, swap);
    a[KICK] = a[BASS];
    b[BASS] = up(x, swap - 1.0, swap);
    b[KICK] = b[BASS];
    b[DRUMS] = up(x, k / 8.0, swap);
    a[DRUMS] = down(x, swap, k - k / 8.0);
    let (from, to) = if clash { (0.4 * k, 0.6 * k) } else { (0.3 * k, 0.7 * k) };
    a[OTHER] = down(x, from, to);
    b[OTHER] = up(x, from, to);
    b[VOCALS] = 1.0;
    (a, b)
}

pub struct Rendered {
    pub mix: Stereo,
    /// Same excerpt with a plain equal-power crossfade, for comparison.
    /// Empty unless [`Options::baseline`] asked for it.
    pub baseline: Stereo,
    /// Output second at which the overlap starts and ends: where beat 0 and
    /// beat `k` of the plan fall.
    pub overlap: (f64, f64),
    /// Output seconds between which the file differs from the originals:
    /// the overlap and the seams around it. Before it the output is A, after
    /// it B, sample for sample.
    pub changed: (f64, f64),
    /// Second of A heard at output second 0.
    pub a_start: f64,
    /// Second of B heard at `overlap.1`; B runs untouched from there.
    pub b_resume: f64,
}

const SEAM_LEAD: f64 = 0.5;
const SEAM_FADE: f64 = 0.05;
const WINDOW_MARGIN: f64 = 2.0;

pub fn render(a: &Track, b: &Track, plan: &Plan, opts: &Options) -> Result<Rendered> {
    let k = plan.beats;
    let (a_start, a_end) = (plan.a_beats[0], plan.a_beats[k]);
    let (b_start, b_end) = (plan.b_beats[0], plan.b_beats[k]);
    let overlap_len = n(plan.beat_times[k]);
    // `pre_seconds` of plain A before anything changes, seam included.
    let pre = n((opts.pre_seconds + SEAM_LEAD).min(a_start));
    let post = n(opts.post_seconds.min(b.audio.seconds() - b_end).max(1.0));
    let lead = n(SEAM_LEAD);
    let fade = n(SEAM_FADE);
    let (a_gain, b_gain) = (opts.a_gain, opts.b_gain);

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
    let mut baseline = Stereo::zeros(if opts.baseline { total } else { 0 });
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

        // Outside the processed stretch the output is one song, untouched.
        if o < -lead {
            for c in 0..2 {
                mix.ch[c][i] = a_gain * read(&a.audio, c, a_start_n + o);
            }
        } else if o >= overlap_len + lead {
            for c in 0..2 {
                mix.ch[c][i] = b_gain * read(&b.audio, c, b_end_n + (o - overlap_len));
            }
        } else {
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
            let (ga, gb) = if plan.stem_mode == StemMode::Model {
                bass_swap_gains(x, k as f64, plan.b_vocal_beat, clash)
            } else {
                eq_swap_gains(x, k as f64, clash)
            };

            for c in 0..2 {
                // Deck A: original, then (after a short seam) its processed stems.
                let a_val = if o < overlap_len {
                    let j = (o + lead) as usize;
                    let processed: f32 = (0..GROUPS).map(|s| ga[s] * a_proc[2 * s + c][j]).sum();
                    let w = ((o + lead) as f32 / fade as f32).clamp(0.0, 1.0);
                    read(&a.audio, c, a_start_n + o) * (1.0 - w) + processed * w
                } else {
                    0.0
                };

                // Deck B: processed stems, then (after a short seam) the original.
                let b_val = if o < 0 {
                    0.0
                } else {
                    let j = o as usize;
                    let processed: f32 = (0..GROUPS).map(|s| gb[s] * b_proc[2 * s + c][j]).sum();
                    let w = ((o - (overlap_len + lead - fade)) as f32 / fade as f32).clamp(0.0, 1.0);
                    processed * (1.0 - w) + read(&b.audio, c, b_end_n + (o - overlap_len)) * w
                };
                mix.ch[c][i] = a_gain * a_val + b_gain * b_val;
            }
        }

        if opts.baseline {
            // Both at their own tempo, equal-power crossfade.
            let p = (o as f64 / overlap_len as f64).clamp(0.0, 1.0);
            let fa = a_gain * (p * std::f64::consts::FRAC_PI_2).cos() as f32;
            let fb = b_gain * (p * std::f64::consts::FRAC_PI_2).sin() as f32;
            for c in 0..2 {
                baseline.ch[c][i] = fa * read(&a.audio, c, a_start_n + o) + fb * read(&b.audio, c, b_start_n + o);
            }
        }
    }

    // Only the overlap is ever gain-ridden: outside it the output has to stay
    // the untouched original, or the splice back onto the song would show.
    // The ceiling is whatever the louder original already reaches.
    let ceiling = (a_gain * peak(&a.audio)).max(b_gain * peak(&b.audio)).max(0.5);
    let changed_n = ((pre - lead).max(0) as usize, ((pre + overlap_len + lead) as usize).min(total));
    limit_changed(&mut mix, changed_n, ceiling);
    if opts.baseline {
        limit_changed(&mut baseline, changed_n, ceiling);
    }
    let overlap = (pre as f64 / SRF, (pre + overlap_len) as f64 / SRF);
    let changed = (changed_n.0 as f64 / SRF, changed_n.1 as f64 / SRF);
    Ok(Rendered {
        mix,
        baseline,
        overlap,
        changed,
        a_start: (a_start_n - pre) as f64 / SRF,
        b_resume: b_end_n as f64 / SRF,
    })
}

pub fn peak(audio: &Stereo) -> f32 {
    audio.ch.iter().flatten().fold(0.0f32, |m, v| m.max(v.abs()))
}

pub fn harmony_clashes(plan: &Plan) -> bool {
    plan.harmony < HARMONY_CLASH
}

/// [`limit`] for a stretch the caller will splice between untouched audio:
/// the gain it rides reaches 250 ms either side of the loud block that asked
/// for it, so only blocks 300 ms inside the stretch are allowed to ask.
pub fn limit_changed(audio: &mut Stereo, changed: (usize, usize), ceiling: f32) {
    let inset = n(0.3) as usize;
    if changed.1 > changed.0 + 2 * inset {
        limit(audio, (changed.0 + inset, changed.1 - inset), ceiling);
    }
}

/// Slow gain riding that keeps the sum of two songs under full scale without
/// audible pumping: per-block peaks, widened, then interpolated.
pub fn limit(audio: &mut Stereo, region: (usize, usize), ceiling: f32) {
    let block = 441usize;
    let pad = 30 * block;
    let from = region.0.saturating_sub(pad);
    let to = (region.1 + pad).min(audio.len());
    if to <= from {
        return;
    }
    let blocks = (to - from) / block + 1;
    let mut gain = vec![1.0f32; blocks];
    for (bi, g) in gain.iter_mut().enumerate() {
        let a = from + bi * block;
        let b = (a + block).min(to);
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
    for i in from..to {
        let pos = (i - from) as f32 / block as f32;
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
        let (a, _) = generate(&Spec { bpm: 120.0, root: 36, bars: 40, lead_in: 0.37, seed: 7, intro_bars: 8, outro_bars: 8 });
        let (b, _) = generate(&Spec { bpm: 126.0, root: 38, bars: 40, lead_in: 0.21, seed: 9, intro_bars: 8, outro_bars: 8 });
        let a = Track::new("a".into(), "a".into(), a);
        let b = Track::new("b".into(), "b".into(), b);
        let opts = Options { pre_seconds: 8.0, post_seconds: 8.0, stem_mode: StemMode::Frequency, ..Options::default() };
        let plan = plan(&a, &b, &opts).unwrap();
        assert_eq!(plan.beats, 32, "eight bars: the most planned without a vocal stem");
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
        let original = a.audio.ch[0][(rendered.a_start * SRF).round() as usize + 1000];
        assert!((first - original).abs() < 1e-4);
        let peak_of = |t: &Stereo| t.ch[0].iter().fold(0.0f32, |m, v| m.max(v.abs()));
        let ceiling = peak_of(&a.audio).max(peak_of(&b.audio));
        let peak = peak_of(&rendered.mix);
        assert!(peak <= ceiling * 1.001, "peak {peak} over the originals' {ceiling}");
    }

    #[test]
    fn the_frequency_swap_is_a_bass_swap_with_a_gradual_crossover() {
        let k = 64.0;
        let (a0, b0) = eq_swap_gains(0.0, k, false);
        assert!(a0[BASS] > 0.99 && a0[OTHER] > 0.99 && a0[DRUMS] > 0.99);
        assert!(b0[BASS] < 0.01 && b0[OTHER] < 0.01 && b0[DRUMS] < 0.01, "B is silent at the start");
        let (a1, b1) = eq_swap_gains(k, k, false);
        assert!(a1[BASS] < 0.01 && a1[OTHER] < 0.01 && a1[DRUMS] < 0.01);
        assert!(b1[BASS] > 0.99 && b1[OTHER] > 0.99 && b1[DRUMS] > 0.99, "B alone at the end");
        for step in 0..=128 {
            let x = k * step as f64 / 128.0;
            let (a, b) = eq_swap_gains(x, k, false);
            // Equal power in the bass swap and in the mid crossover.
            assert!((a[BASS].powi(2) + b[BASS].powi(2) - 1.0).abs() < 1e-5);
            assert!((a[OTHER].powi(2) + b[OTHER].powi(2) - 1.0).abs() < 1e-5);
        }
        // The two basses trade places in a beat, at the middle bar line.
        let (a, b) = eq_swap_gains(k / 2.0 - 1.0, k, false);
        assert!(a[BASS] > 0.99 && b[BASS] < 0.01);
        let (a, b) = eq_swap_gains(k / 2.0, k, false);
        assert!(a[BASS] < 0.01 && b[BASS] > 0.99);
        // The mids of both are up together only in the middle of the overlap.
        let both = |clash: bool| -> f64 {
            (0..=640).filter(|i| { let (a, b) = eq_swap_gains(k * *i as f64 / 640.0, k, clash); a[OTHER] > 0.2 && b[OTHER] > 0.2 }).count() as f64 / 640.0
        };
        assert!(both(false) < 0.35 && both(true) < both(false), "{} {}", both(false), both(true));
        // B's highs arrive before the swap, A's leave after it.
        let (a, b) = eq_swap_gains(k / 4.0, k, false);
        assert!(b[DRUMS] > 0.3 && b[DRUMS] < 0.99 && a[DRUMS] > 0.99);
    }

    fn pair(intro_a: u32, outro_a: u32, intro_b: u32, outro_b: u32) -> (Track, Track) {
        let (a, _) = generate(&Spec { bpm: 120.0, root: 36, bars: 60, lead_in: 0.3, seed: 5, intro_bars: intro_a, outro_bars: outro_a });
        let (b, _) = generate(&Spec { bpm: 124.0, root: 38, bars: 60, lead_in: 0.2, seed: 6, intro_bars: intro_b, outro_bars: outro_b });
        (Track::new("a".into(), "a".into(), a), Track::new("b".into(), "b".into(), b))
    }

    #[test]
    fn the_fast_plan_never_touches_the_model() {
        let (a, b) = pair(8, 8, 8, 8);
        // Whatever the stem mode asked for: `plan` is the frequency-split plan.
        let opts = Options { stem_mode: StemMode::Model, ..Options::default() };
        let plan = plan(&a, &b, &opts).unwrap();
        assert_eq!(plan.stem_mode, StemMode::Frequency);
        assert_eq!(plan.separated_seconds, 0.0);
    }

    #[test]
    fn a_clearly_instrumental_intro_allows_a_long_fast_mix() {
        // B opens with 16 bars of drums and pad before its lead comes in; A
        // ends with 8 of drums and bass. The band cue sees both.
        let (a, b) = pair(8, 8, 16, 8);
        let p = plan(&a, &b, &Options::default()).unwrap();
        assert!(p.b_intro_bars.is_some_and(|bars| bars >= 14), "B's intro read as {:?}", p.b_intro_bars);
        assert!(p.a_outro_bars.is_some_and(|bars| bars >= 6), "A's outro read as {:?}", p.a_outro_bars);
        assert_eq!(p.beats, 64, "sixteen bars");
        let overlap = p.beat_times[p.beats];
        assert!(overlap > 28.0 && overlap <= 36.0, "{overlap} s");
    }

    #[test]
    fn a_short_intro_keeps_the_fast_mix_short() {
        // The lead is in by the fourth bar: no room for a long overlap.
        let (a, b) = pair(8, 8, 4, 8);
        let p = plan(&a, &b, &Options::default()).unwrap();
        assert!(p.beats <= 16, "{} beats", p.beats);
    }

    #[test]
    fn a_song_with_no_visible_structure_is_planned_at_eight_bars_at_most() {
        // No intro at all: the lead is in from the first bar.
        let (a, b) = pair(0, 0, 0, 0);
        let p = plan(&a, &b, &Options::default()).unwrap();
        assert!(p.beats <= 32, "{} beats", p.beats);
    }
}
