//! automix-lab: a bench for auditioning automatic DJ-style transitions.
//!
//! Two songs in, one WAV out: the end of the first, a beat-matched,
//! stem-aware transition, and the start of the second. Not part of the app.

mod yt;

use automix::{audio, grid, synth};

use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::time::Instant;

#[derive(Parser)]
#[command(about = "Banco de pruebas de transiciones automáticas (experimento, no forma parte de la app)")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Muestra tempo, grilla y rango audible de una canción.
    Analyze { file: String },
    /// Decodifica una canción a WAV tal como la ve el motor.
    Decode { file: String, out: PathBuf },
    /// Compara cómo decodifica el motor una canción con un WAV de referencia
    /// (p. ej. `afconvert -f WAVE -d LEI16@44100 cancion.m4a ref.wav`) y
    /// muestra el desfase en muestras: 0 = el motor y CoreAudio coinciden.
    CheckDecode { file: String, reference: PathBuf },
    /// Nivel (dBFS, RMS) de un WAV cada 0,5 s entre dos segundos, para ver
    /// de un vistazo cómo se mueve una transición.
    Levels {
        file: PathBuf,
        #[arg(long, default_value_t = 0.0)]
        from: f64,
        #[arg(long, default_value_t = 60.0)]
        to: f64,
    },
    /// Genera una pista sintética de tempo conocido.
    Synth {
        out: PathBuf,
        #[arg(long, default_value_t = 120.0)]
        bpm: f64,
        /// Nota MIDI de la tónica (36 = Do2).
        #[arg(long, default_value_t = 36)]
        root: i32,
        #[arg(long, default_value_t = 48)]
        bars: u32,
        #[arg(long, default_value_t = 0.37)]
        lead_in: f64,
    },
    /// Renderiza la transición de A hacia B. Cada una es un archivo de audio
    /// o `yt:<búsqueda, id o URL>` para bajarla de YouTube Music.
    Mix {
        a: String,
        b: String,
        #[arg(short, long, default_value = "out/mix.wav")]
        out: PathBuf,
        /// Largo máximo de la mezcla en compases (4, 8 o 16).
        #[arg(long, default_value_t = 16)]
        max_bars: u32,
        /// Segundos de A antes de la transición y de B después (B entero: `inf`).
        #[arg(long, default_value_t = 20.0)]
        pre: f64,
        #[arg(long, default_value_t = 20.0)]
        post: f64,
        /// Carpeta donde se guardan los stems ya separados.
        #[arg(long, default_value = "out/stems-cache")]
        stems_cache: PathBuf,
        /// Sin modelo de stems: separa sólo graves del resto.
        #[arg(long)]
        no_stems: bool,
        /// Corre el primer tiempo detectado de A o B esta cantidad de beats.
        #[arg(long, default_value_t = 0, allow_hyphen_values = true)]
        a_downbeat: i64,
        #[arg(long, default_value_t = 0, allow_hyphen_values = true)]
        b_downbeat: i64,
    },
}

fn main() -> Result<()> {
    match Cli::parse().command {
        Command::Analyze { file } => analyze(file),
        Command::Decode { file, out } => audio::save(&out, &load_track(&file)?.audio),
        Command::CheckDecode { file, reference } => check_decode(&file, &reference),
        Command::Levels { file, from, to } => {
            let x = audio::load_wav(&file)?;
            let mut t = from;
            while t < to.min(x.seconds()) {
                let a = (t * audio::SRF) as usize;
                let b = (((t + 0.5) * audio::SRF) as usize).min(x.len());
                let db = 20.0 * audio::rms(&x.ch[0][a..b]).max(1e-9).log10();
                println!("{t:6.1} s {db:6.1} dB {}", "#".repeat(((db + 60.0).max(0.0) / 1.5) as usize));
                t += 0.5;
            }
            Ok(())
        }
        Command::Synth { out, bpm, root, bars, lead_in } => {
            let (audio, downbeat) = synth::generate(&synth::Spec { bpm, root, bars, lead_in, seed: 7 });
            audio::save(&out, &audio)?;
            println!("{}: {bpm} BPM, primer tiempo en {downbeat:.3} s, {:.1} s", out.display(), audio.seconds());
            Ok(())
        }
        Command::Mix { a, b, out, max_bars, pre, post, stems_cache, no_stems, a_downbeat, b_downbeat } => {
            let opts = automix::Options {
                max_bars,
                pre_seconds: pre,
                stem_mode: if no_stems { automix::StemMode::Frequency } else { automix::StemMode::Model },
                a_downbeat_shift: a_downbeat,
                b_downbeat_shift: b_downbeat,
                post_seconds: post,
                baseline: true,
                ..automix::Options::default()
            };
            run_mix(a, b, out, &stems_cache, opts)
        }
    }
}

/// A local file, or `yt:<search, id or URL>` fetched into `out/cache/`.
fn load_track(source: &str) -> Result<automix::Track> {
    if let Some(what) = source.strip_prefix("yt:") {
        let fetched = yt::fetch(what, std::path::Path::new("out/cache"))?;
        let key = fetched.path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
        return Ok(automix::Track::new(fetched.title, key, audio::load(&fetched.path)?));
    }
    let path = PathBuf::from(source);
    let name = path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    let key: String = name.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect();
    Ok(automix::Track::new(name, key, audio::load(&path)?))
}

fn analyze(file: String) -> Result<()> {
    let track = load_track(&file)?;
    let (first, last) = grid::audible_range(&track.env);
    println!("{}: {:.1} s, audible de {first:.2} a {last:.2} s", track.name, track.audio.seconds());
    for (label, from, to) in [
        ("inicio", first, (first + 60.0).min(last)),
        ("final", (last - 60.0).max(first), last),
    ] {
        let guess = grid::estimate_bpm(&track.env, from, to);
        let g = grid::fit_grid(&track.env, from, to, guess);
        println!(
            "  {label}: {:.2} BPM (estimación global {guess:.1}), confianza {:.2}, primer tiempo de compás en {:.3} s",
            g.bpm,
            g.confidence,
            g.beat(g.beat_at_or_before(from).div_euclid(4) * 4 + 4)
        );
    }
    Ok(())
}

fn run_mix(a: String, b: String, out: PathBuf, stems_cache: &std::path::Path, opts: automix::Options) -> Result<()> {
    let started = Instant::now();
    let track_a = load_track(&a)?;
    let track_b = load_track(&b)?;
    let loaded = started.elapsed();

    let transition = automix::prepare(&track_a, &track_b, stems_cache, &opts)?;
    let prepared = started.elapsed();
    println!("A «{}» -> B «{}»", track_a.name, track_b.name);
    println!("Tipo: {}. {}", transition.kind.as_str(), transition.detail);
    println!(
        "Tempos medidos: A {:.2} BPM, B {:.2} BPM; {} compases",
        transition.bpm_a, transition.bpm_b, transition.bars
    );
    println!(
        "Archivo de {:.1} s: arranca en el segundo {:.2} de A; cambio de {:.1} a {:.1} s; B entra desde su segundo {:.2} (archivo = B + {:.3} s); pasar a B a los {:.1} s",
        transition.file_seconds(),
        transition.a_cut,
        transition.overlap_start,
        transition.overlap_end,
        transition.b_entry,
        transition.b_offset,
        transition.handover
    );

    audio::save(&out, &transition.audio)?;
    println!("Transición:      {}", out.display());
    if transition.baseline.len() > 0 {
        let baseline = out.with_file_name(format!(
            "{}-crossfade.wav",
            out.file_stem().map(|s| s.to_string_lossy()).unwrap_or_default()
        ));
        audio::save(&baseline, &transition.baseline)?;
        println!("Crossfade común: {}", baseline.display());
    }
    println!(
        "Carga {:.1} s, análisis, stems y render {:.1} s",
        loaded.as_secs_f64(),
        (prepared - loaded).as_secs_f64()
    );
    Ok(())
}

/// Lag, in samples, at which the engine's decode best matches the reference
/// (positive: the engine is late), searched over +-4096 samples.
fn check_decode(file: &str, reference: &std::path::Path) -> Result<()> {
    let ours = audio::load(std::path::Path::new(file))?;
    let theirs = audio::load_wav(reference)?;
    // A stretch from the middle of the song, where there is plenty of signal.
    let len = 20_000usize;
    let at = (ours.len().min(theirs.len()) / 2).saturating_sub(len / 2);
    let (mut best, mut best_lag) = (f64::MIN, 0i64);
    for lag in -4096i64..=4096 {
        let mut acc = 0.0f64;
        for i in at..at + len {
            let j = i as i64 + lag;
            if j >= 0 && (j as usize) < ours.len() {
                acc += (ours.ch[0][j as usize] * theirs.ch[0][i]) as f64;
            }
        }
        if acc > best {
            best = acc;
            best_lag = lag;
        }
    }
    println!("{file}: motor {} muestras, referencia {}; desfase {best_lag} muestras", ours.len(), theirs.len());
    Ok(())
}
