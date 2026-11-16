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
    // Reading refreshes the entry for the cache's least-recently-used pruning.
    let touched = [dir.join(format!("{tag}.meta")), dir.join(format!("{tag}.sig"))];
    for path in paths.iter().chain(&touched) {
        if let Ok(file) = std::fs::OpenOptions::new().write(true).open(path) {
            let _ = file.set_modified(std::time::SystemTime::now());
        }
    }
    Some(Span { stems: Stems { stem }, start, model_seconds: 0.0, model_run_seconds: 0.0 })
}

/// Whether the cache holds a finished separation under `tag` of at least
/// `min_seconds` of audio, without looking at any audio: the cheap question a
/// shell asks before deciding to request "stems". The content is verified when
/// the stems are actually used.
pub fn has_entry(dir: &Path, tag: &str, min_seconds: f64) -> bool {
    let Ok(meta) = std::fs::read_to_string(dir.join(format!("{tag}.meta"))) else { return false };
    let len = meta.split_whitespace().nth(1).and_then(|v| v.parse::<f64>().ok()).unwrap_or(0.0);
    // Half a second of slack: a window clamped at the start of a song is a
    // sample or two short of its nominal length.
    len >= (min_seconds - 0.5) * audio::SRF && dir.join(format!("{tag}.sig")).exists() && stem_paths(dir, tag).iter().all(|p| p.exists())
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
    // Single flight: one separation of a stretch at a time, process-wide.
    // Whoever needs a stretch somebody else is already separating waits for
    // it and reads it from the cache (a foreground caller waiting for a
    // background one speeds it up: see `model::separate_boostable`).
    let flight = loop {
        if let Some(hit) = cached(audio, (from, to), cache_dir, tag) {
            return Ok(hit);
        }
        match claim(cache_dir, tag, (from, to), priority) {
            Claim::Owner(flight) => break flight,
            Claim::Wait(done) => {
                while !done.finished() {
                    if cancel.is_some_and(|c| c.load(std::sync::atomic::Ordering::Relaxed)) {
                        anyhow::bail!("separación cancelada");
                    }
                    std::thread::sleep(std::time::Duration::from_millis(50));
                }
            }
        }
    };
    let _ = std::fs::remove_file(cache_dir.join(format!("{tag}.meta")));
    let window = audio.slice(from, (to - from) as usize);
    let started = std::time::Instant::now();
    let loads_before = crate::model::loads();
    let mut stem = crate::model::separate_boostable(&window, cancel, priority, Some(&flight.boost))?;
    let mut elapsed = started.elapsed().as_secs_f64();
    if crate::model::loads() != loads_before {
        elapsed = (elapsed - crate::model::info().map_or(0.0, |i| i.load_seconds)).max(0.01);
    }
    fold_residual(&window, &mut stem);
    store(audio, (from, to), &stem, cache_dir, tag)?;
    drop(flight);
    Ok(Span {
        stems: Stems { stem },
        start: from,
        model_seconds: window.seconds(),
        model_run_seconds: elapsed,
    })
}

/// A stretch being separated now.
struct Running {
    key: (std::path::PathBuf, String),
    span: (i64, i64),
    boost: std::sync::Arc<std::sync::atomic::AtomicBool>,
    done: std::sync::Arc<std::sync::atomic::AtomicBool>,
}

fn running() -> &'static std::sync::Mutex<Vec<Running>> {
    static R: std::sync::OnceLock<std::sync::Mutex<Vec<Running>>> = std::sync::OnceLock::new();
    R.get_or_init(Default::default)
}

/// Held by the separation in progress; releases the stretch (and wakes the
/// ones waiting for it) when dropped, finished or not.
struct Flight {
    key: (std::path::PathBuf, String),
    boost: std::sync::Arc<std::sync::atomic::AtomicBool>,
    done: std::sync::Arc<std::sync::atomic::AtomicBool>,
}

impl Drop for Flight {
    fn drop(&mut self) {
        self.done.store(true, std::sync::atomic::Ordering::SeqCst);
        let mut running = running().lock().unwrap_or_else(|e| e.into_inner());
        running.retain(|r| r.key != self.key || !std::sync::Arc::ptr_eq(&r.done, &self.done));
    }
}

struct Finished(std::sync::Arc<std::sync::atomic::AtomicBool>);

impl Finished {
    fn finished(&self) -> bool {
        self.0.load(std::sync::atomic::Ordering::SeqCst)
    }
}

enum Claim {
    Owner(Flight),
    Wait(Finished),
}

fn claim(dir: &Path, tag: &str, span: (i64, i64), priority: crate::model::Priority) -> Claim {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    let key = (dir.to_path_buf(), tag.to_owned());
    let mut running = running().lock().unwrap_or_else(|e| e.into_inner());
    if let Some(other) = running.iter().find(|r| r.key == key && r.span.0 <= span.0 && r.span.1 >= span.1) {
        if priority == crate::model::Priority::Normal {
            other.boost.store(true, Ordering::SeqCst);
        }
        return Claim::Wait(Finished(other.done.clone()));
    }
    let (boost, done) = (Arc::new(AtomicBool::new(priority == crate::model::Priority::Normal)), Arc::new(AtomicBool::new(false)));
    running.push(Running { key: key.clone(), span, boost: boost.clone(), done: done.clone() });
    Claim::Owner(Flight { key, boost, done })
}

/// Deletes whole cache entries, least recently used first, until the cache is
/// under `max_bytes`, never an entry whose tag is in `protect` (the stretches
/// of the pair about to be prepared: if they alone are over the cap, the cap
/// is exceeded rather than make them useless). An entry is deleted `.meta`
/// first, so a half-deleted one is never mistaken for a finished one.
pub fn prune_entries(dir: &Path, max_bytes: u64, protect: &[String]) {
    let Ok(read) = std::fs::read_dir(dir) else { return };
    // tag -> (newest modification, bytes, files)
    let mut entries: std::collections::HashMap<String, (std::time::SystemTime, u64, Vec<std::path::PathBuf>)> = Default::default();
    for file in read.flatten() {
        let Ok(meta) = file.metadata() else { continue };
        if !meta.is_file() {
            continue;
        }
        let name = file.file_name().to_string_lossy().into_owned();
        let tag = ["_vocals.wav", "_drums.wav", "_bass.wav", "_other.wav", ".sig", ".meta"]
            .iter()
            .find_map(|suffix| name.strip_suffix(suffix))
            .unwrap_or(&name)
            .to_owned();
        let entry = entries.entry(tag).or_insert((std::time::UNIX_EPOCH, 0, Vec::new()));
        entry.0 = entry.0.max(meta.modified().unwrap_or(std::time::UNIX_EPOCH));
        entry.1 += meta.len();
        entry.2.push(file.path());
    }
    let mut total: u64 = entries.values().map(|e| e.1).sum();
    let mut order: Vec<_> = entries.into_iter().filter(|(tag, _)| !protect.contains(tag)).collect();
    order.sort_by_key(|(_, e)| e.0);
    for (_, (_, bytes, mut files)) in order {
        if total <= max_bytes {
            break;
        }
        files.sort_by_key(|f| f.extension().is_none_or(|x| x != "meta"));
        for file in files {
            let _ = std::fs::remove_file(file);
        }
        total = total.saturating_sub(bytes);
    }
}

/// A stand-in that needs no model: three bands in the stems' slots. [`BASS`]
/// is everything under 180 Hz, [`DRUMS`] everything above 2.5 kHz (hats, air:
/// the rhythm that can be told apart) and [`OTHER`] what is between (voices,
/// leads, snares). They add up to the window exactly.
pub fn split_by_frequency(window: &Stereo) -> Stems {
    let bass = audio::lowpass4(window, 180.0);
    let low = audio::lowpass4(window, 2500.0);
    let mut highs = window.clone();
    for c in 0..2 {
        for (h, l) in highs.ch[c].iter_mut().zip(&low.ch[c]) {
            *h -= l;
        }
    }
    let mut stem: [Stereo; 4] = [Stereo::zeros(window.len()), highs, bass, Stereo::zeros(window.len())];
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

    #[test]
    fn an_entry_is_ready_only_when_whole_and_long_enough() {
        let dir = std::env::temp_dir().join(format!("automix-entry-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let audio = song(44_100 * 70, 1.0);
        let window = audio.slice(0, 44_100 * 66);
        let stem = split_by_frequency(&window).stem;
        assert!(!has_entry(&dir, "x-tail", 60.0));
        store(&audio, (0, 44_100 * 66), &stem, &dir, "x-tail").unwrap();
        assert!(has_entry(&dir, "x-tail", 60.0));
        assert!(!has_entry(&dir, "x-tail", 70.0), "a shorter stretch than the plan reads is not ready");
        std::fs::remove_file(dir.join("x-tail_bass.wav")).unwrap();
        assert!(!has_entry(&dir, "x-tail", 60.0), "a missing stem is not ready");
        std::fs::remove_dir_all(dir).ok();
    }

    fn fake_entry(dir: &Path, tag: &str, bytes: usize, age_seconds: u64) {
        let now = std::time::SystemTime::now();
        let files: Vec<String> = ["vocals", "drums", "bass", "other"].iter().map(|n| format!("{tag}_{n}.wav")).chain([format!("{tag}.sig"), format!("{tag}.meta")]).collect();
        for name in files {
            let path = dir.join(&name);
            std::fs::write(&path, vec![0u8; bytes]).unwrap();
            std::fs::OpenOptions::new().write(true).open(&path).unwrap().set_modified(now - std::time::Duration::from_secs(age_seconds)).unwrap();
        }
    }

    #[test]
    fn pruning_deletes_whole_entries_and_spares_the_protected_ones() {
        let dir = std::env::temp_dir().join(format!("automix-entries-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        // Six bytes-per-file entries of 6 * 1000 bytes; the oldest is the one
        // the upcoming pair needs.
        fake_entry(&dir, "old-tail", 1000, 5000);
        fake_entry(&dir, "mid-tail", 1000, 3000);
        fake_entry(&dir, "new-head", 1000, 1000);
        fake_entry(&dir, "newest-tail", 1000, 10);
        let count = |tag: &str| std::fs::read_dir(&dir).unwrap().flatten().filter(|e| e.file_name().to_string_lossy().starts_with(tag)).count();
        // Room for two entries: the two oldest go, whole, and not one file of
        // anything else.
        prune_entries(&dir, 12_000, &[]);
        assert_eq!((count("old-tail"), count("mid-tail"), count("new-head"), count("newest-tail")), (0, 0, 6, 6));
        // Protected entries stay even when they alone are over the cap.
        fake_entry(&dir, "old-tail", 1000, 9000);
        prune_entries(&dir, 1, &["old-tail".to_owned(), "new-head".to_owned()]);
        assert_eq!((count("old-tail"), count("new-head"), count("newest-tail")), (6, 6, 0));
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn a_hit_makes_the_entry_the_most_recently_used() {
        let dir = std::env::temp_dir().join(format!("automix-lru-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let audio = song(44_100 * 30, 1.0);
        let window = audio.slice(0, 44_100 * 20);
        let stem = split_by_frequency(&window).stem;
        store(&audio, (0, 44_100 * 20), &stem, &dir, "x-tail").unwrap();
        for entry in std::fs::read_dir(&dir).unwrap().flatten() {
            entry.path().metadata().unwrap();
            std::fs::OpenOptions::new().write(true).open(entry.path()).unwrap().set_modified(std::time::SystemTime::now() - std::time::Duration::from_secs(10_000)).unwrap();
        }
        assert!(cached(&audio, (44_100, 44_100 * 10), &dir, "x-tail").is_some());
        let age = std::fs::metadata(dir.join("x-tail.meta")).unwrap().modified().unwrap().elapsed().unwrap();
        assert!(age < std::time::Duration::from_secs(60), "the meta was touched by the hit: {age:?}");
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn a_stretch_being_separated_is_waited_for_not_separated_twice() {
        let dir = std::path::PathBuf::from("/nonexistent-automix-single-flight");
        let low = crate::model::Priority::Low;
        // The first claim owns the stretch; a second for a stretch inside it
        // waits, and a foreground waiter speeds a background owner up.
        let Claim::Owner(owner) = claim(&dir, "t-tail", (0, 1000), low) else { panic!("first claim owns") };
        assert!(!owner.boost.load(std::sync::atomic::Ordering::SeqCst));
        let Claim::Wait(done) = claim(&dir, "t-tail", (100, 900), crate::model::Priority::Normal) else { panic!("second waits") };
        assert!(owner.boost.load(std::sync::atomic::Ordering::SeqCst), "the foreground waiter boosts the background owner");
        assert!(!done.finished());
        // A stretch that is not inside it is its own work, and so is another tag.
        assert!(matches!(claim(&dir, "t-tail", (0, 5000), low), Claim::Owner(_)));
        assert!(matches!(claim(&dir, "other-tail", (0, 1000), low), Claim::Owner(_)));
        drop(owner);
        assert!(done.finished(), "the waiter is released when the owner is done");
        assert!(matches!(claim(&dir, "t-tail", (100, 900), low), Claim::Owner(_)));
    }
}
