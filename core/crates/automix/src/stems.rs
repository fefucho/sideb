//! Stem separation of a short window, through HT-Demucs (ONNX Runtime).
//!
//! Only the part of a song a transition reads is ever separated, which is
//! what makes real stems affordable: tens of seconds, not the whole track.

use crate::audio::{self, Stereo};
use anyhow::Result;
use std::path::Path;

pub const VOCALS: usize = 0;
pub const DRUMS: usize = 1;
pub const BASS: usize = 2;
pub const OTHER: usize = 3;
/// Not a model stem: the drums below 150 Hz (the kick's weight), split off so
/// the low end of the two kits can be swapped like the basses are.
pub const KICK: usize = 4;
pub const GROUPS: usize = 5;

/// The four stems of one window. They sum exactly to the window they came
/// from: whatever the model left out is folded into `other`.
pub struct Stems {
    pub stem: [Stereo; 4],
}

impl Stems {
    /// Planar channels of `[start, start + len)` in stretcher order: group 0
    /// L, group 0 R, group 1 L, ... with the drums split into [`DRUMS`] (above
    /// 150 Hz) and [`KICK`] (below).
    pub fn planar(&self, start: i64, len: usize) -> Vec<Vec<f32>> {
        let mut out = Vec::with_capacity(2 * GROUPS);
        let drums = self.stem[DRUMS].slice(start, len);
        let kick = audio::lowpass4(&drums, 150.0);
        for (i, s) in self.stem.iter().enumerate() {
            let mut part = if i == DRUMS { drums.clone() } else { s.slice(start, len) };
            if i == DRUMS {
                for c in 0..2 {
                    for (v, k) in part.ch[c].iter_mut().zip(&kick.ch[c]) {
                        *v -= k;
                    }
                }
            }
            let [l, r] = part.ch;
            out.push(l);
            out.push(r);
        }
        let [l, r] = kick.ch;
        out.push(l);
        out.push(r);
        out
    }
}

/// Whether the HT-Demucs model is already on disk.
pub fn model_ready() -> bool {
    crate::model::ready()
}

/// Starts downloading the model on a background thread, if it is not already
/// on disk or downloading. Returns at once.
pub fn start_model_download() {
    crate::model::start_download();
}

/// Turns [`crate::mix::StemMode::Auto`] into what to do right now: the model
/// when it is on disk, else the frequency split (and the model starts
/// downloading for next time).
pub fn resolve(mode: crate::mix::StemMode) -> crate::mix::StemMode {
    use crate::mix::StemMode;
    match mode {
        StemMode::Auto if model_ready() => StemMode::Model,
        StemMode::Auto => {
            start_model_download();
            StemMode::Frequency
        }
        other => other,
    }
}

/// Deletes the oldest files of `dir` until it is under `max_bytes`. Meant for
/// the stems cache, which would otherwise grow by ~50 MB per transition.
pub fn prune_cache(dir: &Path, max_bytes: u64) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    let mut files: Vec<(std::time::SystemTime, u64, std::path::PathBuf)> = entries
        .flatten()
        .filter_map(|e| {
            let meta = e.metadata().ok()?;
            meta.is_file().then(|| (meta.modified().unwrap_or(std::time::UNIX_EPOCH), meta.len(), e.path()))
        })
        .collect();
    let mut total: u64 = files.iter().map(|f| f.1).sum();
    files.sort();
    for (_, len, path) in files {
        if total <= max_bytes {
            break;
        }
        if std::fs::remove_file(path).is_ok() {
            total -= len;
        }
    }
}

/// Stems of a stretch of a track, and where it starts.
pub struct Span {
    pub stems: Stems,
    /// Track sample of the first sample of every stem.
    pub start: i64,
    /// Seconds of audio the model actually separated for this call (0 when the
    /// cache had it).
    pub model_seconds: f64,
    /// Wall-clock seconds the model took, session load excluded.
    pub model_run_seconds: f64,
}

/// Fingerprint of a stretch of a track: its samples at every multiple of
/// `SIG_STEP`, quantised to 16 bits. Enough to tell two different songs (or
/// two cuts of one) apart without keeping the audio.
const SIG_STEP: usize = 1009;

fn signature(audio: &Stereo, from: usize, to: usize) -> Vec<i16> {
    let first = from.div_ceil(SIG_STEP);
    (first..).map(|k| k * SIG_STEP).take_while(|p| *p < to.min(audio.len())).map(|p| (audio.ch[0][p].clamp(-1.0, 1.0) * 16_383.0) as i16).collect()
}

fn stem_paths(dir: &Path, tag: &str) -> Vec<std::path::PathBuf> {
    ["vocals", "drums", "bass", "other"].iter().map(|n| dir.join(format!("{tag}_{n}.wav"))).collect()
}

/// The cached stems of `tag` if they cover `[from, to)` of `audio` and were
/// made from the same audio there.
fn cached(audio: &Stereo, (from, to): (i64, i64), dir: &Path, tag: &str) -> Option<Span> {
    let meta = std::fs::read_to_string(dir.join(format!("{tag}.meta"))).ok()?;
    let mut parts = meta.split_whitespace().map(|v| v.parse::<i64>().ok());
    let (start, len) = (parts.next()??, parts.next()??);
    if start > from || start + len < to {
        return None;
    }
    let raw = std::fs::read(dir.join(format!("{tag}.sig"))).ok()?;
    let stored: Vec<i16> = raw.chunks_exact(2).map(|c| i16::from_le_bytes([c[0], c[1]])).collect();
    // Compare the samples both fingerprints hold for the requested stretch.
    let first = (from as usize).div_ceil(SIG_STEP);
    let base = (start as usize).div_ceil(SIG_STEP);
    let ours = signature(audio, from as usize, to as usize);
    for (i, value) in ours.iter().enumerate() {
        let theirs = stored.get(first + i - base)?;
        if (i32::from(*value) - i32::from(*theirs)).abs() > 3 {
            return None;
        }
    }
    let paths = stem_paths(dir, tag);
    if !paths.iter().all(|p| p.exists()) {
        return None;
    }
    let mut stem: [Stereo; 4] = Default::default();
    for (i, path) in paths.iter().enumerate() {
        stem[i] = audio::load_wav(path).ok()?.slice(0, len as usize);
    }
    // Reading refreshes the entry for the cache's oldest-first pruning.
    for path in &paths {
        if let Ok(file) = std::fs::OpenOptions::new().write(true).open(path) {
            let _ = file.set_modified(std::time::SystemTime::now());
        }
    }
    Some(Span { stems: Stems { stem }, start, model_seconds: 0.0, model_run_seconds: 0.0 })
}

/// Writes `stem` (the stems of `audio[from..to)`) into the cache under `tag`;
/// the `.meta` file goes last, so a half-written entry is never read.
fn store(audio: &Stereo, (from, to): (i64, i64), stem: &[Stereo; 4], dir: &Path, tag: &str) -> Result<()> {
    for (path, stem) in stem_paths(dir, tag).iter().zip(stem) {
        audio::save_for_playback(path, stem)?;
    }
    let sig: Vec<u8> = signature(audio, from as usize, to as usize).iter().flat_map(|v| v.to_le_bytes()).collect();
    std::fs::write(dir.join(format!("{tag}.sig")), sig)?;
    std::fs::write(dir.join(format!("{tag}.meta")), format!("{from} {}", to - from))?;
    Ok(())
}

/// Stems of `audio[from..to)` by the model, or from an earlier separation of
/// a stretch that covers it (a prefetch separates the widest stretch any
/// transition could read; a transition only asks for what it reads). The
/// returned span may be wider than asked. `tag` names the stretch
/// (`<track key>-tail` or `-head`); its files are `<tag>_<stem>.wav`, `.sig`
/// and `.meta` (written last, so a half-finished separation is never read).
pub fn separate_span(
    audio: &Stereo,
    (from, to): (i64, i64),
    cache_dir: &Path,
    tag: &str,
    cancel: Option<&std::sync::atomic::AtomicBool>,
    priority: crate::model::Priority,
) -> Result<Span> {
    let from = from.clamp(0, audio.len() as i64);
    let to = to.clamp(from, audio.len() as i64);
    if to - from < 1000 {
        anyhow::bail!("tramo demasiado corto para separar");
    }
    std::fs::create_dir_all(cache_dir)?;
    if let Some(hit) = cached(audio, (from, to), cache_dir, tag) {
        return Ok(hit);
    }
    let _ = std::fs::remove_file(cache_dir.join(format!("{tag}.meta")));
    let window = audio.slice(from, (to - from) as usize);
    let started = std::time::Instant::now();
    let loads_before = crate::model::loads();
    let mut stem = crate::model::separate(&window, cancel, priority)?;
    let mut elapsed = started.elapsed().as_secs_f64();
    if crate::model::loads() != loads_before {
        elapsed = (elapsed - crate::model::info().map_or(0.0, |i| i.load_seconds)).max(0.01);
    }
    fold_residual(&window, &mut stem);
    store(audio, (from, to), &stem, cache_dir, tag)?;
    Ok(Span {
        stems: Stems { stem },
        start: from,
        model_seconds: window.seconds(),
        model_run_seconds: elapsed,
    })
}

/// A stand-in that needs no model: "bass" is everything under 180 Hz and
/// "other" is the rest. Enough to hear beat alignment and a bass swap.
pub fn split_by_frequency(window: &Stereo) -> Stems {
    let bass = audio::lowpass4(window, 180.0);
    let mut stem: [Stereo; 4] = [
        Stereo::zeros(window.len()),
        Stereo::zeros(window.len()),
        bass,
        Stereo::zeros(window.len()),
    ];
    fold_residual(window, &mut stem);
    Stems { stem }
}

fn fold_residual(window: &Stereo, stem: &mut [Stereo; 4]) {
    for c in 0..2 {
        for i in 0..window.len() {
            let sum = stem[VOCALS].ch[c][i] + stem[DRUMS].ch[c][i] + stem[BASS].ch[c][i] + stem[OTHER].ch[c][i];
            stem[OTHER].ch[c][i] += window.ch[c][i] - sum;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mix::StemMode;

    #[test]
    fn explicit_modes_are_not_second_guessed() {
        assert_eq!(resolve(StemMode::Frequency), StemMode::Frequency);
        assert_eq!(resolve(StemMode::Model), StemMode::Model);
    }

    #[test]
    fn frequency_split_adds_back_to_the_window() {
        let mut window = Stereo::zeros(10_000);
        for i in 0..10_000 {
            window.ch[0][i] = (i as f32 * 0.05).sin() * 0.4 + (i as f32 * 0.9).sin() * 0.2;
            window.ch[1][i] = (i as f32 * 0.07).cos() * 0.3;
        }
        let stems = split_by_frequency(&window);
        for i in (0..10_000).step_by(131) {
            for c in 0..2 {
                let sum: f32 = stems.stem.iter().map(|s| s.ch[c][i]).sum();
                assert!((sum - window.ch[c][i]).abs() < 1e-5);
            }
        }
    }

    #[test]
    fn pruning_removes_the_oldest_until_under_budget() {
        let dir = std::env::temp_dir().join(format!("automix-stems-prune-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        for (i, name) in ["old", "mid", "new"].iter().enumerate() {
            let path = dir.join(name);
            std::fs::write(&path, vec![0u8; 1000]).unwrap();
            let file = std::fs::OpenOptions::new().write(true).open(&path).unwrap();
            file.set_modified(std::time::UNIX_EPOCH + std::time::Duration::from_secs(1000 + i as u64)).unwrap();
        }
        prune_cache(&dir, 1500);
        let mut left: Vec<String> =
            std::fs::read_dir(&dir).unwrap().flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
        left.sort();
        assert_eq!(left, ["new"]);
        std::fs::remove_dir_all(dir).ok();
    }

    fn song(len: usize, seed: f32) -> Stereo {
        let mut x = Stereo::zeros(len);
        for i in 0..len {
            x.ch[0][i] = (i as f32 * 0.021 * seed).sin() * 0.3 + (i as f32 * 0.0007).sin() * 0.2;
            x.ch[1][i] = (i as f32 * 0.013 * seed).cos() * 0.25;
        }
        x
    }

    #[test]
    fn a_cached_stretch_serves_any_span_inside_it() {
        let dir = std::env::temp_dir().join(format!("automix-span-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let audio = song(44_100 * 30, 1.0);
        // The stems of [4 s, 24 s), as a prefetch would have left them.
        let (from, to) = (44_100 * 4, 44_100 * 24);
        let window = audio.slice(from, (to - from) as usize);
        let mut stem = split_by_frequency(&window).stem;
        fold_residual(&window, &mut stem);
        store(&audio, (from, to), &stem, &dir, "a-tail").unwrap();

        // A span inside it is a hit and comes back as the whole stretch.
        let hit = cached(&audio, (44_100 * 8, 44_100 * 20), &dir, "a-tail").expect("inside");
        assert_eq!(hit.start, from);
        assert_eq!(hit.stems.stem[0].len(), window.len());
        assert_eq!(hit.model_seconds, 0.0);
        // The stems still add up to the audio they came from.
        let sum = hit.stems.stem.iter().map(|s| s.ch[0][50_000]).sum::<f32>();
        assert!((sum - window.ch[0][50_000]).abs() < 1e-3);
        // A span that sticks out, another tag, and another song are misses.
        assert!(cached(&audio, (44_100 * 2, 44_100 * 20), &dir, "a-tail").is_none());
        assert!(cached(&audio, (44_100 * 8, 44_100 * 26), &dir, "a-tail").is_none());
        assert!(cached(&audio, (44_100 * 8, 44_100 * 20), &dir, "b-tail").is_none());
        assert!(cached(&song(44_100 * 30, 1.7), (44_100 * 8, 44_100 * 20), &dir, "a-tail").is_none());
        // Without its .meta (a separation that never finished) nothing is read.
        std::fs::remove_file(dir.join("a-tail.meta")).unwrap();
        assert!(cached(&audio, (44_100 * 8, 44_100 * 20), &dir, "a-tail").is_none());
        std::fs::remove_dir_all(dir).ok();
    }
}
