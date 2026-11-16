//! HT-Demucs stem separation on a long-lived ONNX Runtime session.
//!
//! The model is loaded once into a session this module owns, and stays loaded
//! for as long as it keeps being used (and, if asked, a while after: see
//! [`set_idle_release`]). Nothing here touches the network once the model
//! file is on disk.
//!
//! The pre- and post-processing (a 4096-point complex-as-channels STFT in, an
//! inverse STFT of the model's spectral branch added to its waveform branch
//! out) is adapted from `stem-splitter-core` 1.2.0 by Gentrit Jashari,
//! <https://github.com/gentij/stem-splitter-core>, licensed `MIT OR Apache-2.0`
//! (the MIT terms apply here):
//!
//! > Copyright (c) Gentrit Jashari. Permission is hereby granted, free of
//! > charge, to any person obtaining a copy of this software and associated
//! > documentation files (the "Software"), to deal in the Software without
//! > restriction, including without limitation the rights to use, copy,
//! > modify, merge, publish, distribute, sublicense, and/or sell copies of the
//! > Software, and to permit persons to whom the Software is furnished to do
//! > so, subject to the following conditions: The above copyright notice and
//! > this permission notice shall be included in all copies or substantial
//! > portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT
//! > WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.
//!
//! The model itself is HT-Demucs (Meta, MIT) converted to ONNX/ORT format and
//! published at <https://huggingface.co/gentij/htdemucs-ort>.

use crate::audio::{Stereo, SR};
use anyhow::{anyhow, bail, Context, Result};
use ort::session::{builder::GraphOptimizationLevel, builder::SessionBuilder, Session};
use ort::value::TensorRef;
use rustfft::num_complex::Complex32;
use rustfft::{num_traits::Zero, Fft, FftPlanner};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

// ---- The model's fixed geometry (see the manifest it is published with).
const WINDOW: usize = 343_980;
const BINS: usize = 2048;
const FRAMES: usize = 336;
const NFFT: usize = 4096;
const STFT_HOP: usize = 1024;
/// Source order of the model's outputs.
const SOURCES: [&str; 4] = ["drums", "bass", "other", "vocals"];

const MODEL_URL: &str = "https://huggingface.co/gentij/htdemucs-ort/resolve/main/htdemucs.ort";
const MODEL_SHA256: &str = "09dc165512d8ef7480bcb2cacea9dda82d571f8dbf421d8c44a2ca5568bec729";
const MODEL_BYTES: u64 = 209_884_896;
const MODEL_FILE: &str = "htdemucs-09dc1655.ort";

/// Seconds of audio one model window holds.
pub const WINDOW_SECONDS: f64 = WINDOW as f64 / SR as f64;
/// How far consecutive windows advance, as a fraction of a window. A quarter
/// of each window overlaps its neighbours and is blended, so the model always
/// has context on both sides (it had none before the start of its window
/// when only the first half of each window was kept).
const STRIDE: f64 = 0.75;

// ------------------------------------------------------------------ settings

/// Which silicon the model may use.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Compute {
    /// The fastest the platform measured to be: CoreML on the CPU units on
    /// macOS (faster than its GPU), DirectML on Windows, the plain CPU
    /// provider anywhere else or when those fail.
    Auto,
    /// The GPU, whatever it costs (CoreML `CPUAndGPU`; DirectML).
    Gpu,
    /// ONNX Runtime's own CPU provider: the slowest, the most predictable.
    Cpu,
}

/// CoreML compute units (macOS).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Units {
    All,
    CpuAndGpu,
    CpuAndNeuralEngine,
    CpuOnly,
}

/// Everything about how the session is built that is worth measuring.
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Tuning {
    pub units: Units,
    /// `true`: ML Program; `false`: the older Neural Network format.
    pub ml_program: bool,
    /// Let the GPU accumulate in half precision.
    pub fp16_gpu: bool,
    pub static_shapes: bool,
    pub fast_prediction: bool,
    /// CPU threads for what the provider does not take.
    pub threads: usize,
    /// ONNX Runtime's CPU provider: keep an arena allocator / a memory
    /// pattern. Off: they only make it hold on to memory.
    pub cpu_arena: bool,
    pub cpu_memory_pattern: bool,
}

impl Default for Tuning {
    fn default() -> Self {
        // Measured on an M1 Pro (PLAN-024): the CPU units run the model at
        // ~5.5x realtime; the Neural Engine at the same speed with a slower
        // start and more memory; every GPU option at 0.2-1.8x.
        Tuning {
            units: Units::CpuOnly,
            ml_program: true,
            fp16_gpu: false,
            static_shapes: true,
            fast_prediction: false,
            threads: 4,
            cpu_arena: false,
            cpu_memory_pattern: false,
        }
    }
}

struct Settings {
    dir: Option<PathBuf>,
    compute: Compute,
    tuning: Tuning,
    idle: Option<Duration>,
}

fn settings() -> &'static Mutex<Settings> {
    static S: OnceLock<Mutex<Settings>> = OnceLock::new();
    S.get_or_init(|| {
        Mutex::new(Settings { dir: None, compute: Compute::Auto, tuning: Tuning::default(), idle: Some(DEFAULT_IDLE) })
    })
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// How long the session stays loaded after its last use unless told
/// otherwise. Short on purpose: it holds ~2-3 GB, and loading it again on ONNX
/// Runtime's CPU provider takes well under a second.
pub const DEFAULT_IDLE: Duration = Duration::from_secs(15);

/// Where the model file lives (and is downloaded to). Call once at startup.
pub fn configure(dir: &Path) {
    lock(settings()).dir = Some(dir.to_path_buf());
}

pub fn set_compute(compute: Compute) {
    let mut s = lock(settings());
    if s.compute != compute {
        s.compute = compute;
        drop(s);
        unload();
    }
}

/// Overrides how the session is built (for measurements). Reloads the model.
pub fn set_tuning(tuning: Tuning) {
    let mut s = lock(settings());
    if s.tuning != tuning {
        s.tuning = tuning;
        drop(s);
        unload();
    }
}

/// How long the session stays loaded after its last use; `None` keeps it
/// for the life of the process. Default [`DEFAULT_IDLE`].
pub fn set_idle_release(after: Option<Duration>) {
    let mut s = lock(settings());
    let changed = s.idle.is_some() != after.is_some();
    s.idle = after;
    drop(s);
    // Whether the session is kept decides its provider under "auto".
    if changed {
        unload();
    }
}

// ------------------------------------------------------------------ the file

/// The model file, if it is on disk: ours, or the one `stem-splitter-core`
/// downloaded before this module existed (reused so nobody downloads 210 MB
/// twice).
pub fn model_path() -> Option<PathBuf> {
    let ours = lock(settings()).dir.as_ref().map(|d| d.join(MODEL_FILE));
    if let Some(path) = ours.filter(|p| std::fs::metadata(p).is_ok_and(|m| m.len() == MODEL_BYTES)) {
        return Some(path);
    }
    let legacy = directories::ProjectDirs::from("dev", "StemSplitter", "stem-splitter-core")?.cache_dir().join("models");
    std::fs::read_dir(legacy)
        .ok()?
        .flatten()
        .map(|e| e.path())
        .find(|p| p.extension().is_some_and(|x| x == "ort") && std::fs::metadata(p).is_ok_and(|m| m.len() == MODEL_BYTES))
}

pub fn ready() -> bool {
    model_path().is_some()
}

/// Bytes the model occupies on disk (0 if absent).
pub fn model_bytes() -> u64 {
    model_path().and_then(|p| std::fs::metadata(p).ok()).map_or(0, |m| m.len())
}

/// Unloads the session and deletes the model file(s), including the compiled
/// CoreML cache.
pub fn delete() -> Result<()> {
    unload();
    if let Some(path) = model_path() {
        std::fs::remove_file(path)?;
    }
    if let Some(dir) = lock(settings()).dir.clone() {
        let _ = std::fs::remove_dir_all(dir.join("coreml-cache"));
        let _ = std::fs::remove_file(dir.join(MODEL_FILE));
    }
    Ok(())
}

static DOWNLOADING: AtomicBool = AtomicBool::new(false);

pub fn downloading() -> bool {
    DOWNLOADING.load(Ordering::SeqCst)
}

/// Downloads the model (blocking) unless it is on disk. Verified against its
/// SHA-256 and moved into place only when whole.
pub fn download() -> Result<()> {
    use sha2::{Digest, Sha256};
    use std::io::{Read, Write};
    if ready() {
        return Ok(());
    }
    let dir = lock(settings()).dir.clone().context("no se configuró la carpeta del modelo")?;
    std::fs::create_dir_all(&dir)?;
    let part = dir.join(format!("{MODEL_FILE}.part"));
    let client = reqwest::blocking::Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(30 * 60))
        .build()?;
    let mut response = client.get(MODEL_URL).send()?.error_for_status()?;
    let mut file = std::fs::File::create(&part)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 256 * 1024];
    loop {
        let n = response.read(&mut buffer)?;
        if n == 0 {
            break;
        }
        hasher.update(&buffer[..n]);
        file.write_all(&buffer[..n])?;
    }
    file.flush()?;
    drop(file);
    let digest: String = hasher.finalize().iter().map(|b| format!("{b:02x}")).collect();
    if digest != MODEL_SHA256 {
        let _ = std::fs::remove_file(&part);
        bail!("el modelo descargado no coincide con su huella");
    }
    std::fs::rename(&part, dir.join(MODEL_FILE))?;
    Ok(())
}

/// Starts [`download`] on a background thread, once at a time.
pub fn start_download() {
    if ready() || DOWNLOADING.swap(true, Ordering::SeqCst) {
        return;
    }
    let spawned = std::thread::Builder::new().name("automix-model-download".into()).spawn(|| {
        let _ = std::panic::catch_unwind(download);
        DOWNLOADING.store(false, Ordering::SeqCst);
    });
    if spawned.is_err() {
        DOWNLOADING.store(false, Ordering::SeqCst);
    }
}

// ------------------------------------------------------------------- session

/// What is actually running.
#[derive(Clone, Debug)]
pub struct Info {
    /// "CoreML", "DirectML" or "CPU".
    pub provider: String,
    /// Human description of the units / options, e.g. "CPUAndGPU MLProgram".
    pub detail: String,
    pub load_seconds: f64,
}

struct Loaded {
    session: Session,
    info: Info,
}

struct Slot {
    loaded: Option<Loaded>,
    last_use: Instant,
    watcher: bool,
}

fn slot() -> &'static Mutex<Slot> {
    static S: OnceLock<Mutex<Slot>> = OnceLock::new();
    S.get_or_init(|| Mutex::new(Slot { loaded: None, last_use: Instant::now(), watcher: false }))
}

static LOAD_COUNT: AtomicU64 = AtomicU64::new(0);

/// Times the session has been built in this process.
pub fn loads() -> u64 {
    LOAD_COUNT.load(Ordering::SeqCst)
}

pub fn loaded() -> bool {
    lock(slot()).loaded.is_some()
}

/// The session in use, if one is loaded.
pub fn info() -> Option<Info> {
    lock(slot()).loaded.as_ref().map(|l| l.info.clone())
}

/// Drops the session (and with it the model's memory).
pub fn unload() {
    lock(slot()).loaded = None;
    give_memory_back();
}

/// Asks the allocator to return the pages the model's buffers left free.
fn give_memory_back() {
    #[cfg(target_os = "macos")]
    {
        extern "C" {
            fn malloc_zone_pressure_relief(zone: *mut std::ffi::c_void, goal: usize) -> usize;
        }
        // SAFETY: a null zone means "all zones"; the call only frees memory.
        unsafe {
            malloc_zone_pressure_relief(std::ptr::null_mut(), 0);
        }
    }
}

fn build_session(path: &Path, compute: Compute, tuning: Tuning, cache_dir: Option<&Path>) -> Result<Loaded> {
    let started = Instant::now();
    let threads = tuning.threads.max(1);
    let builder = || -> Result<SessionBuilder> {
        Ok(SessionBuilder::new()?
            .with_optimization_level(GraphOptimizationLevel::Level3)?
            .with_intra_threads(threads)?
            .with_inter_threads(1)?
            .with_parallel_execution(false)?)
    };
    let _ = cache_dir;
    // Why the accelerated provider could not be used, for the CPU's detail.
    let mut why: Option<String> = None;

    #[cfg(target_os = "macos")]
    if compute != Compute::Cpu {
        use ort::ep::coreml::{ComputeUnits, ModelFormat, SpecializationStrategy};
        // An explicit "gpu" is honoured, whatever it costs.
        let units = if compute == Compute::Gpu { Units::CpuAndGpu } else { tuning.units };
        let mut ep = ort::ep::CoreML::default()
            .with_compute_units(match units {
                Units::All => ComputeUnits::All,
                Units::CpuAndGpu => ComputeUnits::CPUAndGPU,
                Units::CpuAndNeuralEngine => ComputeUnits::CPUAndNeuralEngine,
                Units::CpuOnly => ComputeUnits::CPUOnly,
            })
            .with_model_format(if tuning.ml_program { ModelFormat::MLProgram } else { ModelFormat::NeuralNetwork })
            .with_static_input_shapes(tuning.static_shapes)
            .with_low_precision_accumulation_on_gpu(tuning.fp16_gpu)
            .with_specialization_strategy(if tuning.fast_prediction {
                SpecializationStrategy::FastPrediction
            } else {
                SpecializationStrategy::Default
            });
        if let Some(dir) = cache_dir {
            std::fs::create_dir_all(dir).ok();
            ep = ep.with_model_cache_dir(dir.to_string_lossy());
        }
        match builder()?.with_execution_providers([ep.build()]).and_then(|b| b.commit_from_file(path)) {
            Err(e) => why = Some(format!("CoreML: {e}")),
            Ok(session) => return Ok(Loaded {
                session,
                info: Info {
                    provider: "CoreML".into(),
                    detail: format!(
                        "{:?} {}{}{}{}",
                        units,
                        if tuning.ml_program { "MLProgram" } else { "NeuralNetwork" },
                        if tuning.fp16_gpu { " fp16" } else { "" },
                        if tuning.static_shapes { " static" } else { "" },
                        if tuning.fast_prediction { " fast" } else { "" },
                    ),
                    load_seconds: started.elapsed().as_secs_f64(),
                },
            }),
        }
    }

    #[cfg(target_os = "windows")]
    if compute != Compute::Cpu {
        let ep = ort::ep::DirectML::default().build();
        match builder()?.with_execution_providers([ep]).and_then(|b| b.commit_from_file(path)) {
            Err(e) => why = Some(format!("DirectML: {e}")),
            Ok(session) => {
                return Ok(Loaded {
                    session,
                    info: Info { provider: "DirectML".into(), detail: "GPU".into(), load_seconds: started.elapsed().as_secs_f64() },
                })
            }
        }
    }

    let _ = compute;
    let cores = std::thread::available_parallelism().map_or(4, |n| n.get());
    // Measured (PLAN-024): the arena and the memory pattern that ONNX Runtime
    // turns on by default hold on to every buffer a window needed, 5.2 GB
    // after a prefetch against 2.9 GB without; neither costs any speed. The
    // rest of what is left is the model's own working set.
    let session = SessionBuilder::new()?
        .with_optimization_level(GraphOptimizationLevel::Level3)?
        .with_intra_threads(cores)?
        .with_inter_threads(1)?
        .with_parallel_execution(false)?
        .with_memory_pattern(tuning.cpu_memory_pattern)?
        .with_execution_providers([ort::ep::CPU::default().with_arena_allocator(tuning.cpu_arena).build()])?
        .commit_from_file(path)?;
    Ok(Loaded {
        session,
        info: Info {
            provider: "CPU".into(),
            detail: match why.or_else(fallback_reason) {
                Some(why) => format!("{cores} hilos; el acelerador no se pudo usar: {why}"),
                None => format!("{cores} hilos"),
            },
            load_seconds: started.elapsed().as_secs_f64(),
        },
    })
}

fn ensure_loaded(slot: &mut Slot) -> Result<()> {
    if slot.loaded.is_some() {
        return Ok(());
    }
    let path = model_path().context("el modelo de stems no está en disco")?;
    let (compute, tuning, cache) = {
        let s = lock(settings());
        // On a Mac "auto" is ONNX Runtime's CPU provider, not CoreML: measured
        // on prefetching one song (126 s of audio) it is as fast (4.0x against
        // 3.6x realtime), peaks at 2.9 GB against 4.6 GB, and gives its memory
        // back when the session is dropped, where CoreML keeps ~1.7 GB. An
        // explicit "gpu" is still CoreML's CPU-and-GPU units.
        let compute = if cfg!(target_os = "macos") && s.compute == Compute::Auto { Compute::Cpu } else { s.compute };
        (compute, s.tuning, s.dir.as_ref().map(|d| d.join("coreml-cache")))
    };
    let loaded = build_session(&path, compute, tuning, cache.as_deref())?;
    LOAD_COUNT.fetch_add(1, Ordering::SeqCst);
    slot.loaded = Some(loaded);
    if !slot.watcher {
        slot.watcher = true;
        let spawned = std::thread::Builder::new().name("automix-model-idle".into()).spawn(idle_watcher);
        if spawned.is_err() {
            slot.watcher = false;
        }
    }
    Ok(())
}

/// Releases the session once it has sat unused for the configured time.
fn idle_watcher() {
    loop {
        std::thread::sleep(Duration::from_secs(1));
        let idle = lock(settings()).idle;
        let mut s = lock(slot());
        if s.loaded.is_none() {
            s.watcher = false;
            return;
        }
        if let Some(after) = idle {
            if s.last_use.elapsed() >= after {
                s.loaded = None;
                s.watcher = false;
                drop(s);
                give_memory_back();
                return;
            }
        }
    }
}

// ----------------------------------------------------------------------- DSP

struct Transforms {
    forward: Arc<dyn Fft<f32>>,
    inverse: Arc<dyn Fft<f32>>,
    hann: Vec<f32>,
}

fn transforms() -> &'static Transforms {
    static T: OnceLock<Transforms> = OnceLock::new();
    T.get_or_init(|| {
        let mut planner = FftPlanner::new();
        let hann = (0..NFFT).map(|i| 0.5 - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / (NFFT - 1) as f32).cos()).collect();
        Transforms { forward: planner.plan_fft_forward(NFFT), inverse: planner.plan_fft_inverse(NFFT), hann }
    })
}

/// Complex-as-channels spectrogram of a stereo window, centre-padded: planar
/// `[L.re, L.im, R.re, R.im]` each `BINS x FRAMES`.
fn stft(left: &[f32], right: &[f32], out: &mut Vec<f32>) {
    let t = transforms();
    let pad = NFFT / 2;
    let mut l = vec![0.0f32; pad + WINDOW + pad];
    let mut r = vec![0.0f32; pad + WINDOW + pad];
    l[pad..pad + WINDOW].copy_from_slice(left);
    r[pad..pad + WINDOW].copy_from_slice(right);
    out.clear();
    out.resize(4 * BINS * FRAMES, 0.0);
    let mut bl = vec![Complex32::zero(); NFFT];
    let mut br = vec![Complex32::zero(); NFFT];
    for fr in 0..FRAMES {
        let start = fr * STFT_HOP;
        for i in 0..NFFT {
            bl[i] = Complex32::new(l[start + i] * t.hann[i], 0.0);
            br[i] = Complex32::new(r[start + i] * t.hann[i], 0.0);
        }
        t.forward.process(&mut bl);
        t.forward.process(&mut br);
        for fi in 0..BINS {
            let at = fi * FRAMES + fr;
            out[at] = bl[fi].re;
            out[BINS * FRAMES + at] = bl[fi].im;
            out[2 * BINS * FRAMES + at] = br[fi].re;
            out[3 * BINS * FRAMES + at] = br[fi].im;
        }
    }
}

/// Inverse of [`stft`] for one source, added into `dst_l` / `dst_r`.
fn istft_add(spec: &[f32], dst_l: &mut [f32], dst_r: &mut [f32]) {
    let t = transforms();
    let pad = NFFT / 2;
    let padded = WINDOW + 2 * pad;
    let mut out_l = vec![0.0f32; padded];
    let mut out_r = vec![0.0f32; padded];
    let mut weight = vec![0.0f32; padded];
    let mut bl = vec![Complex32::zero(); NFFT];
    let mut br = vec![Complex32::zero(); NFFT];
    let scale = 1.0 / NFFT as f32;
    for fr in 0..FRAMES {
        bl.fill(Complex32::zero());
        br.fill(Complex32::zero());
        for fi in 0..BINS {
            let at = fi * FRAMES + fr;
            bl[fi] = Complex32::new(spec[at], spec[BINS * FRAMES + at]);
            br[fi] = Complex32::new(spec[2 * BINS * FRAMES + at], spec[3 * BINS * FRAMES + at]);
        }
        for fi in 1..BINS {
            bl[NFFT - fi] = bl[fi].conj();
            br[NFFT - fi] = br[fi].conj();
        }
        bl[0].im = 0.0;
        br[0].im = 0.0;
        bl[NFFT / 2].im = 0.0;
        br[NFFT / 2].im = 0.0;
        t.inverse.process(&mut bl);
        t.inverse.process(&mut br);
        let start = fr * STFT_HOP;
        for i in 0..NFFT {
            let pos = start + i;
            if pos < padded {
                let w = t.hann[i];
                out_l[pos] += bl[i].re * w * scale;
                out_r[pos] += br[i].re * w * scale;
                weight[pos] += w * w;
            }
        }
    }
    for i in 0..WINDOW {
        let w = weight[pad + i];
        let norm = if w > 1e-10 { 1.0 / w } else { 1.0 };
        dst_l[i] += out_l[pad + i] * norm;
        dst_r[i] += out_r[pad + i] * norm;
    }
}

/// One model window: `[source][channel][WINDOW]`, sources in [`SOURCES`] order.
fn run_window(session: &mut Session, left: &[f32], right: &[f32]) -> Result<Vec<f32>> {
    let mut time_branch = Vec::with_capacity(2 * WINDOW);
    time_branch.extend_from_slice(left);
    time_branch.extend_from_slice(right);
    let mut spec_branch = Vec::new();
    stft(left, right, &mut spec_branch);

    let time_in = TensorRef::from_array_view(([1usize, 2, WINDOW], time_branch.as_slice()))?;
    let spec_in = TensorRef::from_array_view(([1usize, 4, BINS, FRAMES], spec_branch.as_slice()))?;
    let positional = {
        let names: Vec<&str> = session.inputs().iter().map(|i| i.name()).collect();
        matches!(names.as_slice(), ["input", "x"])
    };
    let mut outputs = if positional {
        session.run(ort::inputs![time_in, spec_in])?
    } else {
        session.run(ort::inputs!["input" => time_in, "x" => spec_in])?
    };
    let freq = outputs.remove("output").ok_or_else(|| anyhow!("el modelo no devolvió la rama espectral"))?;
    let time = outputs.remove("add_67").ok_or_else(|| anyhow!("el modelo no devolvió la rama temporal"))?;
    let (time_shape, time_data) = time.try_extract_tensor::<f32>()?;
    let (freq_shape, freq_data) = freq.try_extract_tensor::<f32>()?;
    let sources = SOURCES.len();
    if time_shape.len() != 4 || time_shape[1] as usize != sources || time_shape[3] as usize != WINDOW {
        bail!("forma inesperada de la salida temporal: {time_shape:?}");
    }
    if freq_shape.len() != 5 || freq_shape[1] as usize != sources {
        bail!("forma inesperada de la salida espectral: {freq_shape:?}");
    }
    let mut out = time_data.to_vec();
    let per_source = 4 * BINS * FRAMES;
    std::thread::scope(|scope| {
        for (source, chunk) in out.chunks_mut(2 * WINDOW).enumerate() {
            let spec = &freq_data[source * per_source..(source + 1) * per_source];
            scope.spawn(move || {
                let (l, r) = chunk.split_at_mut(WINDOW);
                istft_add(spec, l, r);
            });
        }
    });

    // A provider that "runs" but returns silence for a loud input is broken
    // (seen with CoreML on some models): say so, the caller falls back.
    let peak_in = left.iter().chain(right).fold(0.0f32, |m, v| m.max(v.abs()));
    let peak_out = out.iter().fold(0.0f32, |m, v| m.max(v.abs()));
    if peak_in > 1e-4 && peak_out < 1e-6 {
        bail!("el proveedor de ejecución devolvió silencio");
    }
    Ok(out)
}

// ---------------------------------------------------------------- separation

/// Who is asking. Background work (a prefetch) waits, between windows, for
/// every normal request to finish: it never delays one by more than the window
/// it has in flight.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Priority {
    Normal,
    Low,
}

static ACTIVE: AtomicUsize = AtomicUsize::new(0);
static RUNNING: AtomicUsize = AtomicUsize::new(0);
static MOST_RUNNING: AtomicUsize = AtomicUsize::new(0);

/// The most model windows that ever ran at the same time in this process
/// (one: the session is behind a lock; this is how the tests know).
pub fn most_windows_at_once() -> usize {
    MOST_RUNNING.load(Ordering::SeqCst)
}

/// Held while a foreground job (a transition being prepared) runs, so that
/// background separations make way for it even when it does not use the
/// model itself.
pub fn busy() -> impl Drop {
    Active::new(Priority::Normal)
}

fn realtime() -> &'static Mutex<Option<f64>> {
    static R: OnceLock<Mutex<Option<f64>>> = OnceLock::new();
    R.get_or_init(|| Mutex::new(None))
}

/// How many seconds of audio the model separates per second of wall clock
/// once loaded (a moving average over the windows run in this process), or
/// `None` before it has run.
pub fn realtime_factor() -> Option<f64> {
    *lock(realtime())
}

/// Seeds [`realtime_factor`] with a value measured in an earlier run, until
/// this process measures its own.
pub fn seed_realtime_factor(factor: f64) {
    let mut r = lock(realtime());
    if r.is_none() && factor.is_finite() && factor > 0.0 {
        *r = Some(factor);
    }
}

fn note_window(new_audio_seconds: f64, run_seconds: f64) {
    if run_seconds <= 0.0 {
        return;
    }
    let sample = new_audio_seconds / run_seconds;
    let mut r = lock(realtime());
    *r = Some(r.map_or(sample, |old| 0.7 * old + 0.3 * sample));
}

struct Active(bool);

impl Active {
    fn new(priority: Priority) -> Active {
        if priority == Priority::Normal {
            ACTIVE.fetch_add(1, Ordering::SeqCst);
        }
        Active(priority == Priority::Normal)
    }
}

impl Drop for Active {
    fn drop(&mut self) {
        if self.0 {
            ACTIVE.fetch_sub(1, Ordering::SeqCst);
        }
    }
}

/// Separates `audio` into the four stems `[vocals, drums, bass, other]`
/// (this crate's order) with windows that overlap by a quarter, blended with
/// triangular weights. The model loads on first use and stays loaded; `cancel`
/// is checked between windows, and [`Priority::Low`] callers also yield to
/// normal ones between windows.
pub fn separate(audio: &Stereo, cancel: Option<&AtomicBool>, priority: Priority) -> Result<[Stereo; 4]> {
    separate_boostable(audio, cancel, priority, None)
}

/// [`separate`] for a caller that may be waited for: while `boost` is set, a
/// [`Priority::Low`] separation stops yielding to foreground work (someone
/// foreground needs exactly what it is making, and waiting for it).
pub fn separate_boostable(audio: &Stereo, cancel: Option<&AtomicBool>, priority: Priority, boost: Option<&AtomicBool>) -> Result<[Stereo; 4]> {
    let _active = Active::new(priority);
    let n = audio.len();
    let stride = (WINDOW as f64 * STRIDE) as usize;
    let mut sum: Vec<Vec<f32>> = (0..SOURCES.len() * 2).map(|_| vec![0.0; n]).collect();
    let mut weights = vec![0.0f32; n];
    let triangle: Vec<f32> = (0..WINDOW)
        .map(|i| {
            let half = WINDOW / 2;
            (if i < half { i + 1 } else { WINDOW - i }) as f32
        })
        .collect();

    let mut left = vec![0.0f32; WINDOW];
    let mut right = vec![0.0f32; WINDOW];
    let mut start = 0usize;
    let mut retried_on_cpu = false;
    loop {
        while priority == Priority::Low && ACTIVE.load(Ordering::SeqCst) > 0 && !boost.is_some_and(|b| b.load(Ordering::SeqCst)) {
            if cancel.is_some_and(|c| c.load(Ordering::Relaxed)) {
                bail!("separación cancelada");
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        if cancel.is_some_and(|c| c.load(Ordering::Relaxed)) {
            bail!("separación cancelada");
        }
        for i in 0..WINDOW {
            left[i] = audio.ch[0].get(start + i).copied().unwrap_or(0.0);
            right[i] = audio.ch[1].get(start + i).copied().unwrap_or(0.0);
        }
        let out = loop {
            let mut guard = lock(slot());
            ensure_loaded(&mut guard)?;
            guard.last_use = Instant::now();
            let session = &mut guard.loaded.as_mut().expect("just loaded").session;
            let run_started = Instant::now();
            let now = RUNNING.fetch_add(1, Ordering::SeqCst) + 1;
            MOST_RUNNING.fetch_max(now, Ordering::SeqCst);
            let window = run_window(session, &left, &right);
            RUNNING.fetch_sub(1, Ordering::SeqCst);
            match window {
                Ok(out) => {
                    let fresh = if start == 0 { WINDOW.min(n) } else { stride.min(n - start) };
                    note_window(fresh as f64 / SR as f64, run_started.elapsed().as_secs_f64());
                    break out;
                }
                Err(e) if !retried_on_cpu && guard.loaded.as_ref().is_some_and(|l| l.info.provider != "CPU") => {
                    // The accelerated provider failed: carry on without it.
                    tracing_note(&e);
                    retried_on_cpu = true;
                    guard.loaded = None;
                    drop(guard);
                    set_compute(Compute::Cpu);
                }
                Err(e) => return Err(e),
            }
        };
        let end = (start + WINDOW).min(n);
        for i in 0..end - start {
            let w = triangle[i];
            weights[start + i] += w;
            for s in 0..SOURCES.len() {
                sum[2 * s][start + i] += w * out[s * 2 * WINDOW + i];
                sum[2 * s + 1][start + i] += w * out[s * 2 * WINDOW + WINDOW + i];
            }
        }
        if start + WINDOW >= n {
            break;
        }
        start += stride;
    }
    for (i, w) in weights.iter().enumerate() {
        if *w > 0.0 {
            for channel in sum.iter_mut() {
                channel[i] /= *w;
            }
        }
    }
    // [vocals, drums, bass, other] from [drums, bass, other, vocals].
    let take = |source: usize, sum: &mut Vec<Vec<f32>>| Stereo {
        ch: [std::mem::take(&mut sum[2 * source]), std::mem::take(&mut sum[2 * source + 1])],
    };
    let (drums, bass, other, vocals) = (take(0, &mut sum), take(1, &mut sum), take(2, &mut sum), take(3, &mut sum));
    Ok([vocals, drums, bass, other])
}

/// Why the accelerated provider was given up on in this process, if it was.
fn fallback() -> &'static Mutex<Option<String>> {
    static F: OnceLock<Mutex<Option<String>>> = OnceLock::new();
    F.get_or_init(|| Mutex::new(None))
}

pub fn fallback_reason() -> Option<String> {
    lock(fallback()).clone()
}

fn tracing_note(e: &anyhow::Error) {
    *lock(fallback()) = Some(format!("falló al correr: {e:#}"));
}

/// Window count (and so model runs) [`separate`] needs for `seconds` of audio.
pub fn windows_for(seconds: f64) -> usize {
    let n = (seconds * SR as f64) as usize;
    let stride = (WINDOW as f64 * STRIDE) as usize;
    if n <= WINDOW { 1 } else { 1 + (n - WINDOW).div_ceil(stride) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn window_counts() {
        assert_eq!(windows_for(5.0), 1);
        assert_eq!(windows_for(WINDOW_SECONDS), 1);
        assert_eq!(windows_for(WINDOW_SECONDS + 0.1), 2);
        // 60 s: 1 + ceil((60 - 7.8) / 5.85) = 10 windows, against 16 when
        // half of each window was thrown away.
        assert_eq!(windows_for(60.0), 10);
    }

    #[test]
    fn stft_then_istft_returns_the_window() {
        // The spectral branch of one "source" that is the whole signal must
        // come back as the signal: the pair is the model's pre/post-processing.
        let left: Vec<f32> = (0..WINDOW).map(|i| (i as f32 * 0.013).sin() * 0.3 + (i as f32 * 0.31).sin() * 0.1).collect();
        let right: Vec<f32> = (0..WINDOW).map(|i| (i as f32 * 0.017).cos() * 0.2).collect();
        let mut spec = Vec::new();
        stft(&left, &right, &mut spec);
        let (mut l, mut r) = (vec![0.0f32; WINDOW], vec![0.0f32; WINDOW]);
        istft_add(&spec, &mut l, &mut r);
        // Away from the edges the round trip is exact.
        for i in (NFFT..WINDOW - NFFT).step_by(997) {
            assert!((l[i] - left[i]).abs() < 1e-3, "left {i}: {} vs {}", l[i], left[i]);
            assert!((r[i] - right[i]).abs() < 1e-3);
        }
    }

    #[test]
    fn model_file_is_found_where_configured() {
        let dir = std::env::temp_dir().join(format!("automix-model-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        configure(&dir);
        // A file of the wrong size is not the model.
        std::fs::write(dir.join(MODEL_FILE), b"nope").unwrap();
        assert!(model_path().is_none_or(|p| !p.starts_with(&dir)));
        std::fs::remove_dir_all(dir).ok();
    }

    fn tone(seconds: f64) -> Stereo {
        let n = (seconds * SR as f64) as usize;
        let mut x = Stereo::zeros(n);
        for i in 0..n {
            let t = i as f32 / SR as f32;
            // A bass line, a chord and a click track: something for every stem.
            let kick = if (t * 2.0).fract() < 0.05 { (1.0 - (t * 2.0).fract() / 0.05) * (t * 400.0).sin() } else { 0.0 };
            x.ch[0][i] = 0.25 * (t * 55.0 * std::f32::consts::TAU).sin() + 0.15 * (t * 440.0 * std::f32::consts::TAU).sin() + 0.3 * kick;
            x.ch[1][i] = 0.25 * (t * 55.0 * std::f32::consts::TAU).sin() + 0.12 * (t * 554.0 * std::f32::consts::TAU).sin() + 0.3 * kick;
        }
        x
    }

    /// Needs the model on disk (here or where `stem-splitter-core` left it):
    /// `cargo test --release -p automix -- --ignored --test-threads=1` (the
    /// session is process-wide, so these tests must not run concurrently).
    #[test]
    #[ignore = "needs the HT-Demucs model on disk"]
    fn model_separates_and_stays_loaded() {
        assert!(ready(), "the model is not on disk");
        set_idle_release(None);
        let input = tone(14.0);
        let before = loads();
        let stems = separate(&input, None, Priority::Normal).expect("separation");
        let again = separate(&tone(9.0), None, Priority::Normal).expect("second separation");
        assert_eq!(loads() - before.min(loads()), loads() - before, "sanity");
        assert!(loads() - before <= 1, "the session is built once and reused, not per call");
        assert!(loaded() && info().is_some());
        assert_eq!(stems[0].len(), input.len());
        assert_eq!(again[3].len(), 9 * SR as usize);
        // The four stems of a signal add up to about the signal.
        let (mut err, mut energy) = (0.0f64, 0.0f64);
        for i in (SR as usize..input.len() - SR as usize).step_by(7) {
            let sum: f32 = stems.iter().map(|s| s.ch[0][i]).sum();
            err += ((sum - input.ch[0][i]) as f64).powi(2);
            energy += (input.ch[0][i] as f64).powi(2);
        }
        let snr = 10.0 * (energy / err.max(1e-12)).log10();
        assert!(snr > 15.0, "stems sum {snr:.1} dB over their error");
        assert!(realtime_factor().is_some_and(|f| f > 0.5));
    }

    #[test]
    #[ignore = "needs the HT-Demucs model on disk; takes ~5 s"]
    fn model_is_released_after_idling() {
        assert!(ready());
        set_idle_release(Some(Duration::from_secs(2)));
        separate(&tone(4.0), None, Priority::Normal).expect("separation");
        assert!(loaded());
        std::thread::sleep(Duration::from_secs(4));
        assert!(!loaded(), "the session is dropped once idle");
        // And comes back by itself when it is needed again.
        separate(&tone(4.0), None, Priority::Normal).expect("separation after release");
        assert!(loaded());
        set_idle_release(Some(Duration::from_secs(60)));
    }

    #[test]
    fn low_priority_yields_to_a_foreground_job() {
        let guard = busy();
        let started = Instant::now();
        let cancel = AtomicBool::new(false);
        let waited = std::thread::scope(|scope| {
            let low = scope.spawn(|| separate(&tone(2.0), Some(&cancel), Priority::Low));
            std::thread::sleep(Duration::from_millis(400));
            // Still waiting for the foreground job: cancel it out of the queue.
            cancel.store(true, Ordering::SeqCst);
            low.join().unwrap()
        });
        assert!(waited.is_err(), "a background separation does not start while a job is busy");
        assert!(started.elapsed() < Duration::from_secs(3));
        drop(guard);
    }

    /// Needs the model on disk: `cargo test -p automix --release -- --ignored model_never`.
    #[test]
    #[ignore = "needs the HT-Demucs model on disk"]
    fn model_never_runs_two_windows_at_once() {
        assert!(ready());
        set_idle_release(None);
        std::thread::scope(|scope| {
            for (i, priority) in [Priority::Normal, Priority::Low, Priority::Normal, Priority::Low].into_iter().enumerate() {
                scope.spawn(move || {
                    separate(&tone(9.0 + i as f64), None, priority).expect("separation");
                });
            }
        });
        assert_eq!(most_windows_at_once(), 1, "the session is used by one window at a time, process-wide");
        set_idle_release(Some(DEFAULT_IDLE));
    }

    #[test]
    fn the_default_tuning_keeps_no_memory_it_does_not_need() {
        let t = Tuning::default();
        assert!(!t.cpu_arena && !t.cpu_memory_pattern);
        assert_eq!(DEFAULT_IDLE, Duration::from_secs(15));
    }
}
