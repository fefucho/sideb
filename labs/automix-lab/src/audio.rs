//! Loading, saving and small DSP helpers. Everything downstream works on
//! stereo, planar, 44.1 kHz f32.

use anyhow::{bail, Context, Result};
use std::path::Path;

pub const SR: u32 = 44_100;
pub const SRF: f64 = SR as f64;

/// A stereo signal: `ch[0]` left, `ch[1]` right, same length.
#[derive(Clone, Default)]
pub struct Stereo {
    pub ch: [Vec<f32>; 2],
}

impl Stereo {
    pub fn zeros(len: usize) -> Self {
        Self { ch: [vec![0.0; len], vec![0.0; len]] }
    }

    pub fn len(&self) -> usize {
        self.ch[0].len()
    }

    pub fn seconds(&self) -> f64 {
        self.len() as f64 / SRF
    }

    pub fn mono(&self) -> Vec<f32> {
        self.ch[0].iter().zip(&self.ch[1]).map(|(l, r)| 0.5 * (l + r)).collect()
    }

    /// Copy of `[start, start + len)`, zero-padded where it leaves the signal.
    pub fn slice(&self, start: i64, len: usize) -> Stereo {
        let mut out = Stereo::zeros(len);
        let n = self.len() as i64;
        for c in 0..2 {
            for i in 0..len {
                let src = start + i as i64;
                if src >= 0 && src < n {
                    out.ch[c][i] = self.ch[c][src as usize];
                }
            }
        }
        out
    }
}

pub fn load(path: &Path) -> Result<Stereo> {
    let data = stem_splitter_core::core::audio::read_audio(path)
        .with_context(|| format!("no se pudo leer {}", path.display()))?;
    let channels = data.channels.max(1) as usize;
    let frames = data.samples.len() / channels;
    if frames == 0 {
        bail!("{} no tiene audio", path.display());
    }
    let mut out = Stereo::zeros(frames);
    for i in 0..frames {
        let l = data.samples[i * channels];
        let r = if channels > 1 { data.samples[i * channels + 1] } else { l };
        out.ch[0][i] = l;
        out.ch[1][i] = r;
    }
    if data.sample_rate != SR {
        out = resample_linear(&out, data.sample_rate as f64, SRF);
    }
    Ok(out)
}

/// Linear-interpolation resampler. Good enough to audition a transition; a
/// shipping version wants a proper band-limited one.
fn resample_linear(input: &Stereo, from: f64, to: f64) -> Stereo {
    let out_len = (input.len() as f64 * to / from).floor() as usize;
    let mut out = Stereo::zeros(out_len);
    let step = from / to;
    for c in 0..2 {
        let src = &input.ch[c];
        for i in 0..out_len {
            let pos = i as f64 * step;
            let i0 = pos.floor() as usize;
            let frac = (pos - i0 as f64) as f32;
            let a = src[i0.min(src.len() - 1)];
            let b = src[(i0 + 1).min(src.len() - 1)];
            out.ch[c][i] = a + (b - a) * frac;
        }
    }
    out
}

pub fn save(path: &Path, audio: &Stereo) -> Result<()> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
    }
    let spec = hound::WavSpec {
        channels: 2,
        sample_rate: SR,
        bits_per_sample: 24,
        sample_format: hound::SampleFormat::Int,
    };
    let mut writer = hound::WavWriter::create(path, spec)?;
    let scale = (1i32 << 23) as f32 - 1.0;
    for i in 0..audio.len() {
        for c in 0..2 {
            let v = (audio.ch[c][i].clamp(-1.0, 1.0) * scale) as i32;
            writer.write_sample(v)?;
        }
    }
    writer.finalize()?;
    Ok(())
}

/// Reads a WAV written by the stem splitter (16-bit stereo at 44.1 kHz).
pub fn load_wav(path: &Path) -> Result<Stereo> {
    let mut reader = hound::WavReader::open(path)
        .with_context(|| format!("no se pudo abrir {}", path.display()))?;
    let spec = reader.spec();
    if spec.channels != 2 || spec.sample_rate != SR {
        bail!("stem con formato inesperado: {:?}", spec);
    }
    let scale = 1.0 / (1i64 << (spec.bits_per_sample - 1)) as f32;
    let samples: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Int => reader
            .samples::<i32>()
            .map(|s| s.map(|v| v as f32 * scale))
            .collect::<std::result::Result<_, _>>()?,
        hound::SampleFormat::Float => {
            reader.samples::<f32>().collect::<std::result::Result<_, _>>()?
        }
    };
    let frames = samples.len() / 2;
    let mut out = Stereo::zeros(frames);
    for i in 0..frames {
        out.ch[0][i] = samples[2 * i];
        out.ch[1][i] = samples[2 * i + 1];
    }
    Ok(out)
}

/// Two cascaded 2nd-order Butterworth low-passes (24 dB/oct), per channel.
pub fn lowpass4(input: &Stereo, cutoff_hz: f64) -> Stereo {
    let w0 = 2.0 * std::f64::consts::PI * cutoff_hz / SRF;
    let cos = w0.cos();
    let alpha = w0.sin() / (2.0 * std::f64::consts::FRAC_1_SQRT_2);
    let a0 = 1.0 + alpha;
    let b0 = ((1.0 - cos) / 2.0 / a0) as f32;
    let b1 = ((1.0 - cos) / a0) as f32;
    let b2 = b0;
    let a1 = (-2.0 * cos / a0) as f32;
    let a2 = ((1.0 - alpha) / a0) as f32;

    let mut out = input.clone();
    for c in 0..2 {
        for _ in 0..2 {
            let (mut z1, mut z2) = (0.0f32, 0.0f32);
            for x in out.ch[c].iter_mut() {
                let y = b0 * *x + z1;
                z1 = b1 * *x - a1 * y + z2;
                z2 = b2 * *x - a2 * y;
                *x = y;
            }
        }
    }
    out
}

pub fn rms(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    (samples.iter().map(|v| v * v).sum::<f32>() / samples.len() as f32).sqrt()
}
