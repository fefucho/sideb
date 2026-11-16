//! Stem separation of a short window, through HT-Demucs (ONNX Runtime).
//!
//! Only the part of a song a transition reads is ever separated, which is
//! what makes real stems affordable: tens of seconds, not the whole track.

use crate::audio::{self, Stereo};
use anyhow::{Context, Result};
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

/// The model [`stem_splitter_core`] runs by default.
const MODEL_NAME: &str = "htdemucs_ort_v1";

/// Whether the HT-Demucs model is already on disk (a finished download: the
/// splitter writes to a `.part` file and renames it when done).
pub fn model_ready() -> bool {
    let Ok(dir) = stem_splitter_core::io::paths::models_cache_dir() else { return false };
    std::fs::read_dir(dir)
        .map(|entries| {
            entries.flatten().any(|e| {
                e.path().extension().is_some_and(|x| x == "ort") && e.metadata().map(|m| m.len() > 1 << 20).unwrap_or(false)
            })
        })
        .unwrap_or(false)
}

static DOWNLOADING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Starts downloading the model on a background thread, if it is not already
/// on disk or downloading. Returns at once.
pub fn start_model_download() {
    use std::sync::atomic::Ordering;
    if model_ready() || DOWNLOADING.swap(true, Ordering::SeqCst) {
        return;
    }
    let spawned = std::thread::Builder::new().name("automix-model-download".into()).spawn(|| {
        // The splitter panics on a bad registry and reports the rest as errors;
        // either way the next transition simply tries again.
        let _ = std::panic::catch_unwind(|| stem_splitter_core::ensure_model(MODEL_NAME, None));
        DOWNLOADING.store(false, Ordering::SeqCst);
    });
    if spawned.is_err() {
        DOWNLOADING.store(false, Ordering::SeqCst);
    }
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
/// the stems cache, which would otherwise grow by ~100 MB per transition.
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

/// Separates `window` with the model, or reuses an earlier separation of the
/// same window. `tag` names the window (track key plus head/tail); the stems
/// live next to it in `cache_dir` as `<tag>_<stem>.wav`, with `<tag>.wav` the
/// window they were made from and `<tag>.done` marking a finished run.
pub fn separate(window: &Stereo, cache_dir: &Path, tag: &str) -> Result<Stems> {
    std::fs::create_dir_all(cache_dir)?;
    let input = cache_dir.join(format!("{tag}.wav"));
    let done = cache_dir.join(format!("{tag}.done"));
    let cached: Vec<std::path::PathBuf> =
        ["vocals", "drums", "bass", "other"].iter().map(|n| cache_dir.join(format!("{tag}_{n}.wav"))).collect();
    // Keyed by content: same length is not enough, a window cut a few
    // milliseconds elsewhere would get stems that no longer line up with it.
    let same_window = done.exists()
        && audio::load_wav(&input)
            .map(|w| {
                w.len() == window.len()
                    && (0..w.len()).step_by(997).all(|i| (w.ch[0][i] - window.ch[0][i]).abs() < 1e-3)
            })
            .unwrap_or(false);
    if same_window && cached.iter().all(|p| p.exists()) {
        let mut stem: [Stereo; 4] = Default::default();
        for (i, path) in cached.iter().enumerate() {
            stem[i] = audio::load_wav(path)?.slice(0, window.len());
        }
        fold_residual(window, &mut stem);
        // Reading refreshes the entry for the cache's oldest-first pruning.
        let _ = std::fs::File::create(&done);
        return Ok(Stems { stem });
    }
    let _ = std::fs::remove_file(&done);
    audio::save_for_playback(&input, window)?;
    let result = stem_splitter_core::split_file(
        input.to_str().context("ruta no UTF-8")?,
        stem_splitter_core::SplitOptions {
            output_dir: cache_dir.to_string_lossy().into_owned(),
            ..Default::default()
        },
    )
    .map_err(|e| anyhow::anyhow!("falló la separación de stems: {e}"))?;

    let paths = [&result.vocals_path, &result.drums_path, &result.bass_path, &result.other_path];
    let mut stem: [Stereo; 4] = Default::default();
    for (i, path) in paths.iter().enumerate() {
        let loaded = audio::load_wav(Path::new(path))?;
        stem[i] = loaded.slice(0, window.len());
    }
    fold_residual(window, &mut stem);
    std::fs::File::create(&done)?;
    Ok(Stems { stem })
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
}
