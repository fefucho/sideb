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

/// Separates `window` with the model, or reuses an earlier separation of the
/// same window. `tag` names the window (track key plus head/tail); the stems
/// live next to it in `cache_dir` as `<tag>_<stem>.wav`.
pub fn separate(window: &Stereo, cache_dir: &Path, tag: &str) -> Result<Stems> {
    std::fs::create_dir_all(cache_dir)?;
    let work_dir = cache_dir;
    let input = work_dir.join(format!("{tag}.wav"));
    let cached: Vec<std::path::PathBuf> =
        ["vocals", "drums", "bass", "other"].iter().map(|n| work_dir.join(format!("{tag}_{n}.wav"))).collect();
    let same_window = audio::load_wav(&input).map(|w| w.len() == window.len()).unwrap_or(false);
    if same_window && cached.iter().all(|p| p.exists()) {
        let mut stem: [Stereo; 4] = Default::default();
        for (i, path) in cached.iter().enumerate() {
            stem[i] = audio::load_wav(path)?.slice(0, window.len());
        }
        fold_residual(window, &mut stem);
        return Ok(Stems { stem });
    }
    audio::save(&input, window)?;
    let result = stem_splitter_core::split_file(
        input.to_str().context("ruta no UTF-8")?,
        stem_splitter_core::SplitOptions {
            output_dir: work_dir.to_string_lossy().into_owned(),
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
