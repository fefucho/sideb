//! Separating ahead of time: the stretch of a song a transition could read,
//! whichever song it is paired with.
//!
//! The vocal-aware plan reads the last stretch of A far enough back to find
//! where A stops singing (up to 16 bars of outro) and still fit the overlap
//! (up to 36 s), and the first stretch of B far enough on to find where B
//! starts singing (up to 24 bars) and fit the overlap. Separating those two
//! stretches of every song in the queue, at low priority while nothing else
//! is going on, leaves the transition itself only to plan and render.

use crate::grid;
use crate::mix::Track;
use crate::stems;
use anyhow::Result;
use std::path::Path;
use std::sync::atomic::AtomicBool;

/// Seconds before a song's audible end that are separated as A.
pub const TAIL_SECONDS: f64 = 62.0;
/// Seconds after a song's audible start that are separated as B.
pub const HEAD_SECONDS: f64 = 64.0;
pub const MARGIN: f64 = 4.5;

fn n(seconds: f64) -> i64 {
    (seconds * crate::audio::SRF).round() as i64
}

/// The stretch of `track` separated when it is the outgoing song, in samples.
pub fn tail_span(track: &Track) -> (i64, i64) {
    let (_, last) = grid::audible_range(&track.env);
    (n((last - TAIL_SECONDS).max(0.0)), n(last + MARGIN).min(track.audio.len() as i64))
}

/// The stretch separated when it is the incoming song.
pub fn head_span(track: &Track) -> (i64, i64) {
    let (first, _) = grid::audible_range(&track.env);
    (n((first - MARGIN).max(0.0)), n(first + HEAD_SECONDS).min(track.audio.len() as i64))
}

/// Separates the tail and/or the head of `track` into `cache` at low
/// priority. Returns the seconds of audio the model ran on (0 if the cache
/// already had them).
pub fn prefetch(track: &Track, cache: &Path, tail: bool, head: bool, cancel: Option<&AtomicBool>) -> Result<f64> {
    let mut seconds = 0.0;
    if tail {
        let span = stems::separate_span(&track.audio, tail_span(track), cache, &format!("{}-tail", track.key), cancel, crate::model::Priority::Low)?;
        seconds += span.model_seconds;
    }
    if head {
        let span = stems::separate_span(&track.audio, head_span(track), cache, &format!("{}-head", track.key), cancel, crate::model::Priority::Low)?;
        seconds += span.model_seconds;
    }
    Ok(seconds)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::synth::{generate, Spec};

    #[test]
    fn spans_cover_what_a_transition_reads() {
        let (audio, _) = generate(&Spec { bpm: 120.0, root: 36, bars: 60, lead_in: 0.3, seed: 3, intro_bars: 8, outro_bars: 8 });
        let track = Track::new("t".into(), "t".into(), audio);
        let (from, to) = tail_span(&track);
        assert!(to - from > n(55.0) && to - from <= n(TAIL_SECONDS + MARGIN + 0.1));
        let (hfrom, hto) = head_span(&track);
        assert!(hfrom >= 0 && hto - hfrom > n(40.0));
        // Room for 16 bars of outro to skip, then the longest overlap, then the margins.
        assert!(TAIL_SECONDS >= 36.0 + 20.0 + 4.0);
    }
}
