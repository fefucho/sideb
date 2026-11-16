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

/// Frames AVFoundation (AVPlayer, AVAssetReader) drops from an AAC-in-MP4
/// stream on top of what its edit list declares: CoreAudio's own AAC priming.
///
/// Measured, not documented: on YouTube Music streams (edit list
/// `media_time` 1600) AVAssetReader's first frame is the decoder's frame
/// 3712 = 1600 + 2112, while `afconvert` (ExtAudioFile) starts at 2112 and
/// ffmpeg, which honours the edit list alone, at 1600. The engine's clock has
/// to be the one the player shows, or the splice from the playing song into
/// the rendered file lands tens of milliseconds off the beat; so on macOS the
/// engine follows AVFoundation. Elsewhere (libmpv, i.e. ffmpeg) it follows the
/// edit list only. `automix-lab check-decode` repeats the measurement.
#[cfg(target_os = "macos")]
const PLAYER_EXTRA_PRIMING: usize = 2112;
#[cfg(not(target_os = "macos"))]
const PLAYER_EXTRA_PRIMING: usize = 0;

/// Decodes a whole file to stereo 44.1 kHz.
///
/// Sample 0 is the first sample the platform's player shows at time 0: for an
/// MP4 the encoder priming its edit list declares is dropped (plus, on macOS,
/// what AVFoundation drops on top; see [`PLAYER_EXTRA_PRIMING`]).
pub fn load(path: &Path) -> Result<Stereo> {
    use symphonia::core::audio::SampleBuffer;
    use symphonia::core::errors::Error as SymError;

    let file = std::fs::File::open(path).with_context(|| format!("no se pudo abrir {}", path.display()))?;
    let stream = symphonia::core::io::MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = symphonia::core::probe::Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let probed = symphonia::default::get_probe()
        .format(&hint, stream, &Default::default(), &Default::default())
        .with_context(|| format!("formato no reconocido: {}", path.display()))?;
    let mut format = probed.format;
    let track = format.default_track().context("sin pista de audio")?;
    let track_id = track.id;
    let is_aac = track.codec_params.codec == symphonia::core::codecs::CODEC_TYPE_AAC;
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &Default::default())
        .context("códec de audio no soportado")?;

    let mut interleaved: Vec<f32> = Vec::new();
    let (mut rate, mut channels) = (0u32, 0usize);
    // Packet-level damage is a dropout, not the end of the song; the end of
    // the stream is an error symphonia reports as `IoError`.
    while let Ok(packet) = format.next_packet() {
        if packet.track_id() != track_id {
            continue;
        }
        match decoder.decode(&packet) {
            Ok(decoded) => {
                rate = decoded.spec().rate;
                channels = decoded.spec().channels.count();
                let mut buffer = SampleBuffer::<f32>::new(decoded.capacity() as u64, *decoded.spec());
                buffer.copy_interleaved_ref(decoded);
                interleaved.extend_from_slice(buffer.samples());
            }
            Err(SymError::DecodeError(_)) => continue,
            Err(e) => return Err(e).with_context(|| format!("no se pudo decodificar {}", path.display())),
        }
    }
    let channels = channels.max(1);
    let frames = interleaved.len() / channels;
    let declared = mp4_edit_list_start(path).map(|s| (s * rate as f64).round() as usize);
    let priming = match declared {
        Some(declared) => declared + if is_aac { PLAYER_EXTRA_PRIMING } else { 0 },
        None => 0,
    };
    if frames <= priming {
        bail!("{} no tiene audio", path.display());
    }
    let mut out = Stereo::zeros(frames - priming);
    for i in priming..frames {
        let l = interleaved[i * channels];
        let r = if channels > 1 { interleaved[i * channels + 1] } else { l };
        out.ch[0][i - priming] = l;
        out.ch[1][i - priming] = r;
    }
    if rate != SR {
        out = resample_linear(&out, rate as f64, SRF);
    }
    Ok(out)
}

/// Start of the first non-empty edit of an MP4's first track, in seconds of
/// media time: the encoder delay players skip. `None` for anything that is
/// not an MP4 with an edit list starting after 0.
fn mp4_edit_list_start(path: &Path) -> Option<f64> {
    use std::io::{Read, Seek, SeekFrom};
    let mut file = std::fs::File::open(path).ok()?;
    let len = file.metadata().ok()?.len();

    // Walk the top-level boxes without reading `mdat`: `moov` comes first in
    // a streamed (fragmented) file and last in many files from other sources.
    let mut at = 0u64;
    let mut moov = None;
    while at + 8 <= len {
        let mut head = [0u8; 16];
        file.seek(SeekFrom::Start(at)).ok()?;
        let got = file.read(&mut head).ok()?;
        if got < 8 {
            break;
        }
        let size32 = u32::from_be_bytes([head[0], head[1], head[2], head[3]]) as u64;
        let (size, header) = match size32 {
            0 => (len - at, 8),
            1 if got >= 16 => (u64::from_be_bytes(head[8..16].try_into().ok()?), 16),
            1 => break,
            n => (n, 8),
        };
        if size < header || at + size > len {
            break;
        }
        if &head[4..8] == b"moov" {
            if size > 32 << 20 {
                return None;
            }
            let mut body = vec![0u8; (size - header) as usize];
            file.seek(SeekFrom::Start(at + header)).ok()?;
            file.read_exact(&mut body).ok()?;
            moov = Some(body);
            break;
        }
        at += size;
    }
    parse_edit_list(&moov?)
}

/// Child boxes of a container's body: `(type, body)`.
fn boxes(body: &[u8]) -> Vec<([u8; 4], &[u8])> {
    let mut out = Vec::new();
    let mut at = 0usize;
    while at + 8 <= body.len() {
        let size = u32::from_be_bytes([body[at], body[at + 1], body[at + 2], body[at + 3]]) as usize;
        let kind = [body[at + 4], body[at + 5], body[at + 6], body[at + 7]];
        if size < 8 || at + size > body.len() {
            break;
        }
        out.push((kind, &body[at + 8..at + size]));
        at += size;
    }
    out
}

fn child<'a>(body: &'a [u8], kind: &[u8; 4]) -> Option<&'a [u8]> {
    boxes(body).into_iter().find(|(k, _)| k == kind).map(|(_, b)| b)
}

/// `moov` body -> start of the first real edit, in seconds.
fn parse_edit_list(moov: &[u8]) -> Option<f64> {
    let trak = boxes(moov).into_iter().find(|(k, _)| k == b"trak").map(|(_, b)| b)?;
    let elst = child(child(trak, b"edts")?, b"elst")?;
    let mdhd = child(child(trak, b"mdia")?, b"mdhd")?;
    let be32 = |b: &[u8], at: usize| b.get(at..at + 4).map(|v| u32::from_be_bytes([v[0], v[1], v[2], v[3]]));
    let be64 = |b: &[u8], at: usize| b.get(at..at + 8).map(|v| u64::from_be_bytes(v.try_into().unwrap()));

    // FullBox: version(1) flags(3), then entry_count; each entry is
    // segment_duration, media_time, rate (32 or 64 bit fields by version).
    let version = *elst.first()?;
    let count = be32(elst, 4)? as usize;
    let (entry_len, media_at) = if version == 0 { (12, 4) } else { (20, 8) };
    let media_time = (0..count).find_map(|i| {
        let base = 8 + i * entry_len;
        let t = if version == 0 { be32(elst, base + media_at)? as i32 as i64 } else { be64(elst, base + media_at)? as i64 };
        (t >= 0).then_some(t)
    })?;
    let timescale = if *mdhd.first()? == 0 { be32(mdhd, 12)? } else { be32(mdhd, 20)? };
    (media_time > 0 && timescale > 0).then(|| media_time as f64 / timescale as f64)
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

/// 24-bit WAV, for listening tests.
pub fn save(path: &Path, audio: &Stereo) -> Result<()> {
    write_wav(path, audio, 24)
}

/// The file a player is handed: 16-bit, or 32-bit float when a baked-in gain
/// pushes samples over full scale (the player's own gain brings them back).
pub fn save_for_playback(path: &Path, audio: &Stereo) -> Result<()> {
    let peak = audio.ch.iter().flatten().fold(0.0f32, |m, v| m.max(v.abs()));
    write_wav(path, audio, if peak > 1.0 { 32 } else { 16 })
}

fn write_wav(path: &Path, audio: &Stereo, bits: u16) -> Result<()> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
    }
    let float = bits == 32;
    let spec = hound::WavSpec {
        channels: 2,
        sample_rate: SR,
        bits_per_sample: bits,
        sample_format: if float { hound::SampleFormat::Float } else { hound::SampleFormat::Int },
    };
    let mut writer = hound::WavWriter::create(path, spec)?;
    let scale = (1i64 << (bits - 1)) as f32 - 1.0;
    for i in 0..audio.len() {
        for c in 0..2 {
            let v = audio.ch[c][i];
            if float {
                writer.write_sample(v)?;
            } else {
                writer.write_sample((v.clamp(-1.0, 1.0) * scale) as i32)?;
            }
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
    biquad2(input, cutoff_hz, false)
}

/// Two cascaded 2nd-order Butterworth high-passes (24 dB/oct), per channel.
pub fn highpass4(input: &Stereo, cutoff_hz: f64) -> Stereo {
    biquad2(input, cutoff_hz, true)
}

fn biquad2(input: &Stereo, cutoff_hz: f64, high: bool) -> Stereo {
    let w0 = 2.0 * std::f64::consts::PI * cutoff_hz / SRF;
    let cos = w0.cos();
    let alpha = w0.sin() / (2.0 * std::f64::consts::FRAC_1_SQRT_2);
    let a0 = 1.0 + alpha;
    let (b0, b1) = if high {
        (((1.0 + cos) / 2.0 / a0) as f32, (-(1.0 + cos) / a0) as f32)
    } else {
        (((1.0 - cos) / 2.0 / a0) as f32, ((1.0 - cos) / a0) as f32)
    };
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

#[cfg(test)]
mod tests {
    use super::*;

    fn mp4_box(kind: &[u8; 4], body: &[u8]) -> Vec<u8> {
        let mut out = ((body.len() + 8) as u32).to_be_bytes().to_vec();
        out.extend_from_slice(kind);
        out.extend_from_slice(body);
        out
    }

    fn moov_with(version: u8, media_time: i64, timescale: u32) -> Vec<u8> {
        let mut elst = vec![version, 0, 0, 0, 0, 0, 0, 2];
        // An empty edit first (media_time -1), then the real one.
        let entry = |t: i64| -> Vec<u8> {
            if version == 0 {
                [0u32.to_be_bytes().to_vec(), (t as i32).to_be_bytes().to_vec(), 0x0001_0000u32.to_be_bytes().to_vec()].concat()
            } else {
                [0u64.to_be_bytes().to_vec(), t.to_be_bytes().to_vec(), 0x0001_0000u32.to_be_bytes().to_vec()].concat()
            }
        };
        elst.extend(entry(-1));
        elst.extend(entry(media_time));
        let mut mdhd = vec![0u8; 4];
        mdhd.extend_from_slice(&[0u8; 8]);
        mdhd.extend_from_slice(&timescale.to_be_bytes());
        let trak = [mp4_box(b"edts", &mp4_box(b"elst", &elst)), mp4_box(b"mdia", &mp4_box(b"mdhd", &mdhd))].concat();
        mp4_box(b"trak", &trak)
    }

    #[test]
    fn edit_list_start_is_read_in_seconds() {
        // The value found on YouTube Music streams: 1600 frames at 44.1 kHz.
        let moov = moov_with(0, 1600, 44_100);
        let start = parse_edit_list(&moov).expect("edit list");
        assert!((start - 1600.0 / 44_100.0).abs() < 1e-9);
        // 64-bit entries.
        let start = parse_edit_list(&moov_with(1, 2112, 44_100)).expect("edit list v1");
        assert!((start - 2112.0 / 44_100.0).abs() < 1e-9);
        // No priming declared.
        assert!(parse_edit_list(&moov_with(0, 0, 44_100)).is_none());
        // Not enough of a box to say anything.
        assert!(parse_edit_list(&[0, 0, 0, 4]).is_none());
    }

    #[test]
    fn wav_roundtrip_for_playback_keeps_samples() {
        let dir = std::env::temp_dir().join(format!("automix-audio-{}", std::process::id()));
        let mut x = Stereo::zeros(1000);
        for i in 0..1000 {
            x.ch[0][i] = (i as f32 * 0.01).sin() * 0.5;
            x.ch[1][i] = (i as f32 * 0.02).cos() * 0.25;
        }
        let path = dir.join("x.wav");
        save_for_playback(&path, &x).unwrap();
        assert_eq!(hound::WavReader::open(&path).unwrap().spec().bits_per_sample, 16);
        let back = load_wav(&path).unwrap();
        assert_eq!(back.len(), 1000);
        assert!((back.ch[0][500] - x.ch[0][500]).abs() < 1e-3);

        // Over full scale (a baked-in gain): float, nothing clipped.
        x.ch[0][10] = 1.7;
        save_for_playback(&path, &x).unwrap();
        assert_eq!(hound::WavReader::open(&path).unwrap().spec().sample_format, hound::SampleFormat::Float);
        assert!((load_wav(&path).unwrap().ch[0][10] - 1.7).abs() < 1e-6);
        std::fs::remove_dir_all(dir).ok();
    }
}
