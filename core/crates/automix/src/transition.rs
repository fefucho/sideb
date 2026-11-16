//! The fallback ladder: one entry point, [`prepare`], that turns any two
//! analysable songs into a rendered transition.
//!
//! * [`Kind::Mix`]: the full beat-matched, stem-aware bass swap ([`crate::mix`]).
//! * [`Kind::Cut`]: both songs have a trustworthy beat grid but cannot be
//!   beat-matched (tempos too far apart, or the mix planner refused for
//!   another reason). A leaves on a bar line through a low-pass sweep and a
//!   beat-synced echo, one bar of echo, then B enters clean on its first
//!   downbeat at its own tempo.
//! * [`Kind::Fade`]: no reliable grid on one of them. A fades out near its
//!   audible end, B starts at its audible start.
//!
//! Whatever the kind, the audio is: `pre` seconds of untouched A, the
//! transition, then all the rest of B untouched. A player switches from the
//! playing A to this file once, and B plays out of the file.

use crate::audio::{Stereo, SRF};
use crate::grid::{self, Grid};
use crate::mix::{self, Options, Plan, Refusal, StemMode, Track, MIN_GRID_CONFIDENCE};
use crate::stems;
pub use crate::mix::Cancelled;
use anyhow::{bail, Result};
use std::path::Path;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Kind {
    Mix,
    Cut,
    Fade,
}

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::Mix => "mix",
            Kind::Cut => "cut",
            Kind::Fade => "fade",
        }
    }
}

/// A rendered transition and where everything sits in it. Times named
/// "file" are seconds into [`Transition::audio`]; the others are seconds into
/// the original song.
pub struct Transition {
    pub kind: Kind,
    /// The whole file: A, the transition, the rest of B. Stereo, 44.1 kHz,
    /// with the requested gains baked in.
    pub audio: Stereo,
    /// The same excerpt as a plain crossfade, for comparison. Empty unless
    /// [`Options::baseline`] asked for it and the kind is [`Kind::Mix`].
    pub baseline: Stereo,
    /// Second of A heard at file second 0. A plays untouched from there until
    /// `overlap_start`.
    pub a_cut: f64,
    /// File seconds between which the file is neither plain A nor plain B.
    pub overlap_start: f64,
    pub overlap_end: f64,
    /// File second minus B second. Exact for file times from `overlap_end`
    /// on, where B is the untouched original.
    pub b_offset: f64,
    /// Second of B at which B enters the file; earlier seconds of B are not in it.
    pub b_entry: f64,
    /// File second at which a UI should switch its "now playing" to B: the
    /// bass swap of a mix, B's entry otherwise.
    pub handover: f64,
    /// Tempo of each song as measured; 0 when there was no usable estimate.
    pub bpm_a: f64,
    pub bpm_b: f64,
    /// Bars between the start of the change and B being fully in.
    pub bars: u32,
    /// Whether the stems came from the model (a mix) rather than a frequency
    /// split or none at all.
    pub stems_model: bool,
    /// Seconds of audio the model separated for this transition (0 for the
    /// fast render, for `Cut` and `Fade`, and when the cache had the stems).
    pub separated_seconds: f64,
    /// Whether this render has the same cut as the fast one would. Always
    /// true today: the plan (grid, overlap, cut point, B's entry) is made on
    /// the frequency split and the model only re-renders it, so an upgrade
    /// never moves `a_cut`. Kept in the contract so a future plan that does
    /// use the model can say it differs.
    pub same_cut_as_fast: bool,
    /// One line, in Spanish, about what was done and why.
    pub detail: String,
}

impl Transition {
    pub fn file_seconds(&self) -> f64 {
        self.audio.seconds()
    }
}

/// Mix-grid confidence below which a pair is not even tried through the
/// stem pipeline (1 means no evidence of a beat at all).
const HOPELESS_CONFIDENCE: f64 = 1.05;

/// One song's end of the transition as seen without stems.
struct Side {
    first: f64,
    last: f64,
    bpm: f64,
    grid: Grid,
}

fn analyse(track: &Track, tail: bool) -> Option<Side> {
    let (first, last) = grid::audible_range(&track.env);
    if last - first < 12.0 {
        return None;
    }
    let (from, to) = if tail { ((last - 90.0).max(first), last) } else { (first, (first + 90.0).min(last)) };
    let bpm = grid::estimate_bpm(&track.env, from, to);
    if bpm <= 0.0 {
        return None;
    }
    let (from, to) = if tail { ((last - 60.0).max(first), last) } else { (first, (first + 60.0).min(last)) };
    Some(Side { first, last, bpm, grid: grid::fit_grid(&track.env, from, to, bpm) })
}

/// Renders the transition from `a` to `b`, falling down the ladder
/// ([`Kind::Mix`], [`Kind::Cut`], [`Kind::Fade`]) as far as it must. Fails only
/// when a song has no audible audio at all.
///
/// `cache` holds stem separations between runs (see [`crate::stems`]).
pub fn prepare(a: &Track, b: &Track, cache: &Path, opts: &Options) -> Result<Transition> {
    opts.check_cancel()?;
    let side_a = analyse(a, true);
    let side_b = analyse(b, false);
    let (a_first, a_last) = grid::audible_range(&a.env);
    let (b_first, b_last) = grid::audible_range(&b.env);
    if a_last <= a_first || b_last <= b_first {
        bail!("una de las canciones no tiene audio audible");
    }
    let confident = |s: &Option<Side>| s.as_ref().is_some_and(|s| s.grid.confidence >= MIN_GRID_CONFIDENCE);
    let hopeless = |s: &Option<Side>| s.as_ref().is_none_or(|s| s.grid.confidence < HOPELESS_CONFIDENCE);
    let grids_ok = confident(&side_a) && confident(&side_b);

    // Rung 1: the full mix, unless the pair is evidently out of its reach.
    let mut note;
    let mut weak = hopeless(&side_a) || hopeless(&side_b);
    // The grid read off the full mix can be hopeless where the drum stem's is
    // not: a "stems" request still tries the model for such a pair.
    let stems_wanted = stems::resolve(opts.stem_mode) == StemMode::Model;
    if weak && !(stems_wanted && side_a.is_some() && side_b.is_some()) {
        note = "sin grilla de beats confiable".to_owned();
    } else {
        match mix::rough_tempos(a, b) {
            Some((ra, rb)) if !mix::tempos_compatible(ra, rb) => {
                note = format!("tempos demasiado lejanos ({ra:.0} y {rb:.0} BPM)");
            }
            _ => {
                // The fast plan is always made: it is cheap, it is the
                // fallback, and it is what the cut of a stems plan is
                // compared with (`same_cut_as_fast`).
                let fast = if weak {
                    Err(Refusal::WeakGrid { a: side_a.as_ref().map_or(1.0, |s| s.grid.confidence), b: side_b.as_ref().map_or(1.0, |s| s.grid.confidence) })
                } else {
                    mix::plan(a, b, opts)
                };
                let fast_cut = fast.as_ref().ok().map(|p| (p.a_beats[0], p.beats, p.a_skipped_bars));
                let mut chosen: Option<Plan> = None;
                if stems_wanted {
                    match mix::plan_stems(a, b, opts, cache, crate::model::Priority::Normal) {
                        Ok(plan) => chosen = Some(plan),
                        Err(Refusal::Cancelled(c)) => return Err(c.into()),
                        // The model could not run, or the pair is not for it:
                        // the fast version stands (`stems_model` says so).
                        Err(_) => {}
                    }
                }
                match (chosen, fast) {
                    (Some(plan), _) | (None, Ok(plan)) => {
                        opts.check_cancel()?;
                        let same = fast_cut.is_some_and(|(start, beats, skipped)| {
                            (start - plan.a_beats[0]).abs() < 1e-3 && beats == plan.beats && skipped == plan.a_skipped_bars
                        });
                        match render_mix(a, b, &plan, opts, same) {
                            Ok(done) => return Ok(done),
                            Err(e) => note = format!("la mezcla falló al renderizar: {e}"),
                        }
                    }
                    (None, Err(Refusal::Cancelled(c))) => return Err(c.into()),
                    (None, Err(Refusal::WeakGrid { .. })) => {
                        weak = true;
                        note = "grilla de beats poco confiable".to_owned();
                    }
                    (None, Err(e)) => note = e.to_string(),
                }
            }
        }
    }

    // Rung 2: a cut, when both grids can be trusted.
    if !weak && grids_ok {
        if let (Some(sa), Some(sb)) = (&side_a, &side_b) {
            match render_cut(a, b, sa, sb, opts, &note) {
                Ok(done) => return Ok(done),
                Err(e) => note = format!("{note}; el corte no fue posible: {e}"),
            }
        }
    }

    // Rung 3: a fade, which needs nothing but the audible range.
    render_fade(
        a,
        b,
        (a_first, a_last),
        (b_first, b_last),
        (side_a.map_or(0.0, |s| s.bpm), side_b.map_or(0.0, |s| s.bpm)),
        opts,
        &note,
    )
}

fn n(seconds: f64) -> i64 {
    (seconds * SRF).round() as i64
}

fn read(track: &Stereo, c: usize, pos: i64) -> f32 {
    if pos >= 0 && (pos as usize) < track.len() { track.ch[c][pos as usize] } else { 0.0 }
}

/// Copies `track[from .. from + len)` times `gain` into `out` at `at`, with
/// a linear fade-in of `ramp` samples at the start so a mid-signal entry
/// does not click.
fn paste(out: &mut Stereo, at: i64, track: &Stereo, from: i64, len: usize, gain: f32, ramp: usize) {
    for i in 0..len {
        let dst = at + i as i64;
        if dst < 0 || dst as usize >= out.len() {
            continue;
        }
        let w = if ramp > 0 { (i as f32 / ramp as f32).min(1.0) } else { 1.0 };
        for c in 0..2 {
            out.ch[c][dst as usize] += gain * w * read(track, c, from + i as i64);
        }
    }
}

/// The loudest the two originals get, with gains: what a transition's own
/// peaks are held under.
fn ceiling(a: &Track, b: &Track, opts: &Options) -> f32 {
    (opts.a_gain * mix::peak(&a.audio)).max(opts.b_gain * mix::peak(&b.audio)).max(0.5)
}

// ---------------------------------------------------------------- Mix

fn render_mix(a: &Track, b: &Track, plan: &mix::Plan, opts: &Options, same_cut: bool) -> Result<Transition> {
    let rendered = mix::render(a, b, plan, opts)?;
    let k = plan.beats;
    let swap = rendered.overlap.0 + plan.beat_times[k / 2];
    let model = plan.stem_mode == StemMode::Model;
    let detail = format!(
        "Mezcla de {} compases ({:.0} s) con cambio de bajo; {:.0} y {:.0} BPM; {}; armonía {}.",
        k / 4,
        plan.beat_times[k],
        plan.a.grid.bpm,
        plan.b.grid.bpm,
        if model { "stems del modelo" } else { "versión rápida (separación por frecuencias)" },
        if !model { "sin evaluar" } else if mix::harmony_clashes(plan) { "en choque: no se superponen" } else { "compatible" },
    );
    Ok(Transition {
        kind: Kind::Mix,
        a_cut: rendered.a_start,
        overlap_start: rendered.changed.0,
        overlap_end: rendered.changed.1,
        b_offset: rendered.overlap.1 - rendered.b_resume,
        // The overlap's first beat can fall just before B's first sample.
        b_entry: plan.b_beats[0].max(0.0),
        handover: swap,
        bpm_a: plan.a.grid.bpm,
        bpm_b: plan.b.grid.bpm,
        bars: (k / 4) as u32,
        stems_model: model,
        separated_seconds: plan.separated_seconds,
        same_cut_as_fast: same_cut,
        detail,
        audio: rendered.mix,
        baseline: rendered.baseline,
    })
}

// ---------------------------------------------------------------- Cut

/// Two-pole state-variable low-pass (TPT form), stable under per-sample
/// cutoff changes.
struct Svf {
    ic1: f32,
    ic2: f32,
}

impl Svf {
    fn process(&mut self, x: f32, cutoff_hz: f64, q: f64) -> f32 {
        let g = (std::f64::consts::PI * cutoff_hz / SRF).tan() as f32;
        let k = (1.0 / q) as f32;
        let a1 = 1.0 / (1.0 + g * (g + k));
        let a2 = g * a1;
        let a3 = g * a2;
        let v3 = x - self.ic2;
        let v1 = a1 * self.ic1 + a2 * v3;
        let v2 = self.ic2 + a2 * self.ic1 + a3 * v3;
        self.ic1 = 2.0 * v1 - self.ic1;
        self.ic2 = 2.0 * v2 - self.ic2;
        v2
    }
}

/// Bars of B's start that come through an opening low-pass in a cut.
const SWEEP_BARS: u32 = 2;

/// A leaves on its last bar line through a closing low-pass and a ping-pong
/// echo that rings out for the rest of the bar; B comes in on its first
/// downbeat, clean.
fn render_cut(a: &Track, b: &Track, sa: &Side, sb: &Side, opts: &Options, why: &str) -> Result<Transition> {
    let (ga, gb) = (&sa.grid, &sb.grid);
    let bar_a = 4.0 * ga.interval();
    let bar_b = 4.0 * gb.interval();

    // A's last bar line that still has music on it.
    let exit_bar = ga.beat_at_or_before(sa.last - 0.1).div_euclid(4);
    let leave = ga.beat(exit_bar * 4);
    // As long an exit as the tempo allows: up to four bars, 12 seconds.
    let exit_bars = if 4.0 * bar_a <= 12.0 { 4 } else if 2.0 * bar_a <= 6.0 { 2 } else { 1 };
    let exit_start = leave - exit_bars as f64 * bar_a;
    if exit_start < sa.first + 2.0 {
        bail!("{} es demasiado corta para salir en compás", a.name);
    }

    // B's first downbeat, and the little of B that may precede it (a
    // pickup), kept shorter than the echo that has to be gone by then.
    let raw = ((sb.first - 0.05 - gb.beat(0)) / gb.interval()).ceil() as i64;
    let first_bar = raw.div_euclid(4) + if raw.rem_euclid(4) == 0 { 0 } else { 1 };
    let downbeat = gb.beat(first_bar * 4);
    if downbeat >= b.audio.seconds() - 4.0 {
        bail!("{} es demasiado corta para entrar en compás", b.name);
    }
    let pickup_max = 0.5 * bar_a.min(bar_b);
    let entry = (sb.first - 0.02).max(downbeat - pickup_max).max(0.0).min(downbeat);

    let pre = opts.pre_seconds.min(exit_start);
    let a_cut = exit_start - pre;
    let file_leave = leave - a_cut;
    let file_downbeat = file_leave + bar_a;
    let file_entry = file_downbeat - (downbeat - entry);
    let b_offset = file_downbeat - downbeat;
    let b_end = (downbeat + opts.post_seconds).min(b.audio.seconds());

    let total = n(file_downbeat + (b_end - downbeat)) as usize;
    let mut audio = Stereo::zeros(total);

    // Untouched A up to the start of the change.
    let exit_n = n(exit_start - a_cut);
    paste(&mut audio, 0, &a.audio, n(a_cut), exit_n as usize, opts.a_gain, 0);

    // The change: A through the closing filter, plus the echo of it.
    let lead_in = n(0.25);
    let from = exit_n - lead_in;
    let leave_n = n(file_leave);
    let end_n = n(file_entry);
    let delay = (0.75 * ga.interval() * SRF).round() as usize;
    let feedback = 0.55f32;
    let damping = 0.45f32; // one-pole low-pass in the echo loop: dark repeats
    let blend = n(0.05) as f32;
    let tail_len = (end_n - leave_n).max(1) as f32;
    let sweep_len = (leave_n - exit_n).max(1) as f64;
    let mut filter = [Svf { ic1: 0.0, ic2: 0.0 }, Svf { ic1: 0.0, ic2: 0.0 }];
    // Ping-pong: what left feeds the right delay and back.
    let mut line = [vec![0.0f32; delay.max(1)], vec![0.0f32; delay.max(1)]];
    let mut lp = [0.0f32; 2];
    let mut pos = 0usize;
    for i in from..end_n.min(total as i64) {
        let t = i - exit_n; // samples since the change started
        let progress = (t as f64 / sweep_len).clamp(0.0, 1.0);
        let cutoff = 20_000.0 * (250.0f64 / 20_000.0).powf(progress.powf(0.8));
        let q = 0.8 + 1.4 * progress;
        let live = i < leave_n;
        let dry_gain = if i < leave_n - n(0.02) {
            1.0
        } else if live {
            (leave_n - i) as f32 / n(0.02) as f32
        } else {
            0.0
        };
        let send = (progress / 0.5).min(1.0) as f32 * 0.8;
        // Past the bar line nothing of A is left but the echo, which is
        // brought to zero by the time B comes in.
        let tail = if live {
            1.0
        } else {
            let p = ((i - leave_n) as f32 / tail_len).clamp(0.0, 1.0);
            let s = 1.0 - p;
            s * s * (3.0 - 2.0 * s)
        };
        // Both lines are read before either is written: each channel's echo
        // comes from the other's line.
        let echoed = [line[1][pos], line[0][pos]];
        for c in 0..2 {
            let source = if live { read(&a.audio, c, n(a_cut) + i) } else { 0.0 };
            let filtered = filter[c].process(source, cutoff, q);
            lp[c] += damping * (echoed[c] - lp[c]);
            line[c][pos] = send * filtered + feedback * lp[c];
            if i >= exit_n {
                let w = ((i - exit_n) as f32 / blend).min(1.0);
                let heard = read(&a.audio, c, n(a_cut) + i) * (1.0 - w) + filtered * w;
                audio.ch[c][i as usize] += opts.a_gain * (dry_gain * heard + 0.7 * tail * echoed[c]);
            }
        }
        pos = (pos + 1) % line[0].len();
    }

    // B, from its entry to the end...
    let ramp = n(0.003) as usize;
    paste(&mut audio, n(file_entry), &b.audio, n(entry), (n(b_end) - n(entry)).max(0) as usize, opts.b_gain, ramp);
    // ...with its first two bars coming through a low-pass that opens: B enters
    // on the downbeat, clean in time, and its highs arrive over the bars that
    // follow instead of all at once. The last stretch of the sweep is
    // crossfaded to the untouched original, so after `overlap_end` B is exact.
    let sweep_end = (n(file_downbeat + SWEEP_BARS as f64 * bar_b) as usize).min(total);
    let sweep_from = n(file_entry).max(0) as usize;
    if sweep_end > sweep_from + n(0.5) as usize {
        let len = (sweep_end - sweep_from) as f64;
        let blend = n(0.15) as usize;
        let mut filter = [Svf { ic1: 0.0, ic2: 0.0 }, Svf { ic1: 0.0, ic2: 0.0 }];
        for i in sweep_from..sweep_end {
            let progress = (i - sweep_from) as f64 / len;
            let cutoff = 350.0 * (20_000.0f64 / 350.0).powf(progress.powf(0.7));
            let keep = ((sweep_end - i) as f32 / blend as f32).min(1.0);
            for c in 0..2 {
                let heard = audio.ch[c][i];
                let filtered = filter[c].process(heard, cutoff, 0.8);
                audio.ch[c][i] = heard + (filtered - heard) * keep;
            }
        }
    }

    let region = ((exit_n - lead_in).max(0) as usize, sweep_end);
    mix::limit_changed(&mut audio, region, ceiling(a, b, opts));

    Ok(Transition {
        kind: Kind::Cut,
        audio,
        baseline: Stereo::default(),
        a_cut,
        overlap_start: file_leave - exit_bars as f64 * bar_a,
        overlap_end: sweep_end as f64 / SRF,
        b_offset,
        b_entry: entry,
        handover: file_downbeat,
        bpm_a: ga.bpm,
        bpm_b: gb.bpm,
        bars: exit_bars + 1 + SWEEP_BARS,
        stems_model: false,
        separated_seconds: 0.0,
        same_cut_as_fast: true,
        detail: format!(
            "Corte en compás: A sale con filtro y eco ({exit_bars} {}) y B entra en su primer tiempo abriendo el filtro durante {SWEEP_BARS} compases; {why}.",
            if exit_bars == 1 { "compás" } else { "compases" }
        ),
    })
}

// ---------------------------------------------------------------- Fade

const FADE_SECONDS: f64 = 6.0;
const FADE_OVERLAP: f64 = 1.0;

/// A fades out over its last seconds; B starts at its audible start while the
/// tail of the fade is still going.
fn render_fade(
    a: &Track,
    b: &Track,
    (a_first, a_last): (f64, f64),
    (b_first, _b_last): (f64, f64),
    (bpm_a, bpm_b): (f64, f64),
    opts: &Options,
    why: &str,
) -> Result<Transition> {
    let fade = FADE_SECONDS.min(0.6 * (a_last - a_first));
    let overlap = FADE_OVERLAP.min(fade / 2.0);
    let fade_start = a_last - fade;
    let pre = opts.pre_seconds.min(fade_start);
    let a_cut = fade_start - pre;
    let file_fade_start = fade_start - a_cut;
    let file_a_end = a_last - a_cut;
    let entry = (b_first - 0.02).max(0.0);
    let file_entry = file_a_end - overlap;
    let b_end = (entry + (b.audio.seconds() - entry).min(opts.post_seconds + overlap)).min(b.audio.seconds());

    let total = n(file_entry + (b_end - entry)).max(n(file_a_end)) as usize;
    let mut audio = Stereo::zeros(total);
    let fade_n = n(fade);
    for i in 0..n(file_a_end) {
        let into = i - n(file_fade_start);
        let g = if into <= 0 {
            1.0
        } else if into >= fade_n {
            0.0
        } else {
            let p = into as f32 / fade_n as f32;
            0.5 * (1.0 + (std::f32::consts::PI * p).cos())
        };
        for c in 0..2 {
            audio.ch[c][i as usize] += opts.a_gain * g * read(&a.audio, c, n(a_cut) + i);
        }
    }
    paste(&mut audio, n(file_entry), &b.audio, n(entry), (n(b_end) - n(entry)).max(0) as usize, opts.b_gain, n(0.005) as usize);
    let region = (n(file_fade_start).max(0) as usize, (n(file_a_end) as usize).min(total));
    mix::limit_changed(&mut audio, region, ceiling(a, b, opts));

    Ok(Transition {
        kind: Kind::Fade,
        audio,
        baseline: Stereo::default(),
        a_cut,
        overlap_start: file_fade_start,
        overlap_end: file_a_end,
        b_offset: file_entry - entry,
        b_entry: entry,
        handover: file_entry,
        bpm_a,
        bpm_b,
        bars: 0,
        stems_model: false,
        separated_seconds: 0.0,
        same_cut_as_fast: true,
        detail: format!("Fundido de {fade:.0} s: A se apaga y B arranca desde su inicio audible; {why}."),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::synth::{generate, Spec};

    fn track(bpm: f64, root: i32, bars: u32, lead_in: f64, seed: u64) -> (Track, f64) {
        let (audio, downbeat) = generate(&Spec { bpm, root, bars, lead_in, seed, intro_bars: 8, outro_bars: 8 });
        (Track::new(format!("{bpm}"), format!("t{bpm}-{seed}"), audio), downbeat)
    }

    fn options() -> Options {
        Options { stem_mode: StemMode::Frequency, baseline: false, ..Options::default() }
    }

    /// Largest difference between the file and `song` (times `gain`) over
    /// file seconds `[from, to)`, with `offset` = file second minus song second.
    fn worst_difference(file: &Stereo, song: &Stereo, gain: f32, offset: f64, from: f64, to: f64) -> f32 {
        let shift = (-offset * SRF).round() as i64;
        let mut worst = 0.0f32;
        for i in (from * SRF) as i64..(to * SRF) as i64 {
            worst = worst.max((file.ch[0][i as usize] - gain * read(song, 0, i + shift)).abs());
        }
        worst
    }

    /// What every kind promises about the file.
    fn check_contract(t: &Transition, a: &Track, b: &Track, a_gain: f32, b_gain: f32) {
        assert!(t.a_cut >= 0.0 && t.overlap_start > 0.0, "A has to play untouched first");
        assert!(t.overlap_start <= t.handover && t.handover < t.file_seconds(), "handover outside the file's change");
        assert!(t.overlap_end < t.file_seconds());
        // The start of the file is A, untouched, up to the change.
        let to_change = t.overlap_start - 0.05;
        assert!(worst_difference(&t.audio, &a.audio, a_gain, -t.a_cut, 0.0, to_change) < 1e-4, "start is not plain A");
        // From the end of the change the file is B untouched, to its very end.
        let from = t.overlap_end + 0.05;
        assert!(worst_difference(&t.audio, &b.audio, b_gain, t.b_offset, from, t.file_seconds() - 0.01) < 1e-4, "rest is not plain B");
        let b_end_in_file = b.audio.seconds() + t.b_offset;
        assert!((b_end_in_file - t.file_seconds()).abs() < 0.01, "the file stops before the end of B");
        assert!(t.b_entry >= 0.0 && t.b_entry < b.audio.seconds());
    }

    #[test]
    fn close_tempos_mix() {
        let (a, _) = track(120.0, 36, 40, 0.37, 7);
        let (b, _) = track(126.0, 38, 40, 0.21, 9);
        let t = prepare(&a, &b, Path::new("unused"), &options()).unwrap();
        assert_eq!(t.kind, Kind::Mix, "{}", t.detail);
        assert!((t.overlap_start - 8.0).abs() < 1e-3, "pre is 8 s by default");
        assert_eq!(t.bars, 8);
        assert!(!t.stems_model && t.same_cut_as_fast && t.separated_seconds == 0.0);
        check_contract(&t, &a, &b, 1.0, 1.0);
        // The bass swap is in the middle of the change.
        let middle = 0.5 * (t.overlap_start + t.overlap_end);
        assert!((t.handover - middle).abs() < 2.0, "swap at {} of {}..{}", t.handover, t.overlap_start, t.overlap_end);
    }

    #[test]
    fn gains_are_baked_in_and_may_need_float() {
        let (a, _) = track(120.0, 36, 40, 0.37, 7);
        let (b, _) = track(126.0, 38, 40, 0.21, 9);
        let opts = Options { a_gain: 0.5, b_gain: 2.5, ..options() };
        let t = prepare(&a, &b, Path::new("unused"), &opts).unwrap();
        check_contract(&t, &a, &b, 0.5, 2.5);
        assert!(mix::peak(&t.audio) > 1.0, "a +8 dB gain on a loud synth song goes over full scale");
    }

    #[test]
    fn far_tempos_cut_on_the_bar() {
        let (a, a_down) = track(100.0, 36, 40, 0.37, 7);
        let (b, b_down) = track(75.0, 38, 40, 0.21, 9);
        let t = prepare(&a, &b, Path::new("unused"), &options()).unwrap();
        assert_eq!(t.kind, Kind::Cut, "{}", t.detail);
        check_contract(&t, &a, &b, 1.0, 1.0);

        // B's first downbeat lands exactly one bar of A after a bar line of A.
        let bar_a = 4.0 * 60.0 / 100.0;
        let a_bar_in_file = |k: f64| a_down + k * bar_a - t.a_cut;
        let b_down_in_file = b_down + t.b_offset;
        let bars_since_a_downbeat = (b_down_in_file - a_bar_in_file(0.0)) / bar_a;
        assert!(
            (bars_since_a_downbeat - bars_since_a_downbeat.round()).abs() < 0.02,
            "B's downbeat is {bars_since_a_downbeat} bars after A's, not a whole number"
        );
        let last_a_bar = b_down_in_file - bar_a;
        assert!(last_a_bar > t.overlap_start && last_a_bar < t.overlap_end, "A does not leave on the bar before B");
        // B's filter sweep is part of the change: B is exact only after it.
        assert!(t.overlap_end > t.handover + 2.0, "the sweep runs for two bars of B after its downbeat");
        // B enters clean at its own tempo: no stretching of what follows.
        assert!((t.bpm_a - 100.0).abs() < 2.0);
        assert!([75.0, 150.0].iter().any(|b| (t.bpm_b - b).abs() < 2.0), "B counted at {}", t.bpm_b);
    }

    /// Noise has no beat: no grid can be trusted, so the ladder bottoms out.
    #[test]
    fn beatless_audio_fades() {
        let noise = |seed: u64| {
            let mut state = seed;
            let mut x = Stereo::zeros(60 * 44_100);
            for i in 0..x.len() {
                state ^= state << 13;
                state ^= state >> 7;
                state ^= state << 17;
                let v = ((state >> 40) as f32 / (1u64 << 24) as f32 * 2.0 - 1.0) * 0.2;
                x.ch[0][i] = v;
                x.ch[1][i] = v;
            }
            x
        };
        let a = Track::new("a".into(), "na".into(), noise(3));
        let b = Track::new("b".into(), "nb".into(), noise(5));
        let t = prepare(&a, &b, Path::new("unused"), &options()).unwrap();
        assert_eq!(t.kind, Kind::Fade, "{}", t.detail);
        check_contract(&t, &a, &b, 1.0, 1.0);
        assert!(t.overlap_end - t.overlap_start >= 5.0, "a fade of about six seconds");
        // A is silent by the end of the fade, B's first second is already in.
        assert!(t.handover < t.overlap_end && t.overlap_end - t.handover <= 1.01);
    }

    #[test]
    fn silence_is_an_error_not_a_panic() {
        let silent = |s: &str| Track::new(s.into(), s.into(), Stereo::zeros(30 * 44_100));
        let (b, _) = track(120.0, 36, 40, 0.2, 9);
        // Whatever comes out, nothing may panic.
        let _ = prepare(&silent("a"), &b, Path::new("unused"), &options());
    }

    /// Needs the model on disk. `cargo test -p automix -- --ignored stems_plan`.
    #[test]
    #[ignore = "needs the HT-Demucs model on disk"]
    fn stems_plan_is_vocal_aware_and_honest_about_its_cut() {
        assert!(crate::model::ready());
        let (a, _) = generate(&Spec { bpm: 120.0, root: 36, bars: 60, lead_in: 0.37, seed: 7, intro_bars: 8, outro_bars: 8 });
        let (b, _) = generate(&Spec { bpm: 126.0, root: 38, bars: 60, lead_in: 0.21, seed: 9, intro_bars: 8, outro_bars: 8 });
        let (a, b) = (Track::new("a".into(), "sa".into(), a), Track::new("b".into(), "sb".into(), b));
        let dir = std::env::temp_dir().join(format!("automix-stemsplan-{}", std::process::id()));
        let fast = prepare(&a, &b, &dir, &options()).unwrap();
        let full = prepare(&a, &b, &dir, &Options { stem_mode: StemMode::Model, ..options() }).unwrap();
        assert_eq!(fast.kind, Kind::Mix);
        assert_eq!(full.kind, Kind::Mix);
        assert!(full.stems_model && !fast.stems_model);
        check_contract(&full, &a, &b, 1.0, 1.0);
        // `same_cut_as_fast` says exactly whether the cut moved.
        assert_eq!(full.same_cut_as_fast, fast.a_cut == full.a_cut && fast.bars == full.bars);
        // Both sides' stems were separated (the two spans, not the songs).
        assert!(full.separated_seconds > 100.0 && full.separated_seconds < 140.0, "{}", full.separated_seconds);
        // A second request is served from the cache: no separation at all.
        let again = prepare(&a, &b, &dir, &Options { stem_mode: StemMode::Model, ..options() }).unwrap();
        assert_eq!(again.separated_seconds, 0.0);
        assert_eq!(again.a_cut, full.a_cut);
        std::fs::remove_dir_all(dir).ok();
    }
}
