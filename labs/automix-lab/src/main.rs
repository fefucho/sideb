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
    /// Separa con el modelo, a baja prioridad, el final y el principio de cada
    /// canción (lo que haría la precarga) y mide cuánto tarda.
    Prefetch {
        files: Vec<String>,
        #[arg(long, default_value = "out/stems-cache")]
        stems_cache: PathBuf,
    },
    /// Desarma un archivo de transición: dónde empieza A, dónde deja de ser A,
    /// dónde pasa a ser B y qué tanto de B contiene (busca coincidencias exactas).
    Inspect { wav: PathBuf, a: PathBuf, b: PathBuf },
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
        /// «fast»: sin modelo (separa sólo graves del resto); «stems»: con
        /// HT-Demucs, que se descarga si falta.
        #[arg(long, default_value = "stems")]
        quality: String,
        /// Igual que `--quality fast`.
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
    // The model is looked for here first, then where `stem-splitter-core`
    // used to put it, and downloaded here if it is nowhere.
    automix::model::configure(std::path::Path::new("out/model"));
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
        Command::Prefetch { files, stems_cache } => {
            let started = Instant::now();
            for file in files {
                let track = load_track(&file)?;
                let t = Instant::now();
                let seconds = automix::prefetch::prefetch(&track, &stems_cache, true, true, None)?;
                println!("{}: {seconds:.0} s de audio separados en {:.1} s", track.name, t.elapsed().as_secs_f64());
            }
            println!("total {:.1} s; modelo: {:?}", started.elapsed().as_secs_f64(), automix::model::info());
            Ok(())
        }
        Command::Inspect { wav, a, b } => inspect(&wav, &a, &b),
        Command::Synth { out, bpm, root, bars, lead_in } => {
            let (audio, downbeat) = synth::generate(&synth::Spec { bpm, root, bars, lead_in, seed: 7, intro_bars: 8, outro_bars: 8 });
            audio::save(&out, &audio)?;
            println!("{}: {bpm} BPM, primer tiempo en {downbeat:.3} s, {:.1} s", out.display(), audio.seconds());
            Ok(())
        }
        Command::Mix { a, b, out, max_bars, pre, post, stems_cache, quality, no_stems, a_downbeat, b_downbeat } => {
            let opts = automix::Options {
                max_bars,
                pre_seconds: pre,
                stem_mode: if no_stems || quality == "fast" { automix::StemMode::Frequency } else { automix::StemMode::Model },
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
    if opts.stem_mode == automix::StemMode::Model && !automix::model::ready() {
        println!("Bajando el modelo de stems (~210 MB)…");
        automix::model::download()?;
    }
    let started = Instant::now();
    let track_a = load_track(&a)?;
    let track_b = load_track(&b)?;
    let loaded = started.elapsed();

    let transition = automix::prepare(&track_a, &track_b, stems_cache, &opts)?;
    let prepared = started.elapsed();
    println!("A «{}» -> B «{}»", track_a.name, track_b.name);
    println!("Tipo: {}. {}", transition.kind.as_str(), transition.detail);
    println!(
        "Stems del modelo: {} ({:.0} s de audio separados ahora); mismo corte que la versión rápida: {}",
        if transition.stems_model { "sí" } else { "no" },
        transition.separated_seconds,
        if transition.same_cut_as_fast { "sí" } else { "no" }
    );
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

/// Takes a transition file apart by exact sample matches against the two songs.
fn inspect(wav: &std::path::Path, a: &std::path::Path, b: &std::path::Path) -> Result<()> {
    let file = audio::load_wav(wav)?;
    let a = audio::load(a)?;
    let b = audio::load(b)?;
    let sr = audio::SRF;
    println!("archivo {:.2} s, A {:.2} s, B {:.2} s", file.seconds(), a.seconds(), b.seconds());
    let same = |x: f32, y: f32| (x - y).abs() < 1e-5;

    // Where in A does the file begin? Match a short run taken 1 s in.
    let probe = 44_100.min(file.len() / 2);
    let run = 24;
    let found = (0..a.len().saturating_sub(run)).find(|&p| (0..run).all(|k| same(a.ch[0][p + k], file.ch[0][probe + k])));
    match found {
        Some(p) => {
            let cut = p as i64 - probe as i64;
            let mut end = 0usize;
            while end < file.len() && ((cut + end as i64) as usize) < a.len() && same(file.ch[0][end], a.ch[0][(cut + end as i64) as usize]) {
                end += 1;
            }
            println!("A: el archivo arranca en el segundo {:.3} de A y es A exacto hasta el segundo {:.3} del archivo (A hasta su segundo {:.3})", cut as f64 / sr, end as f64 / sr, (cut + end as i64) as f64 / sr);
        }
        None => println!("A: el principio del archivo no es A (¿ganancia aplicada o A distinta?)"),
    }

    // B: assume it plays to its end inside the file.
    let offset = file.len() as i64 - b.len() as i64;
    let mut start = file.len();
    while start > 0 && (start as i64 - offset) >= 0 && same(file.ch[0][start - 1], b.ch[0][(start as i64 - 1 - offset) as usize]) {
        start -= 1;
    }
    println!(
        "B: el archivo es B exacto desde el segundo {:.3} del archivo (B desde su segundo {:.3}) hasta el final; archivo = B + {:.3} s; B completa {:.1} s",
        start as f64 / sr,
        (start as i64 - offset) as f64 / sr,
        offset as f64 / sr,
        b.seconds()
    );
    if file.len() - start < 5 * 44_100 {
        // No exact B: it may be a different encode of the same song. Find where
        // a stretch of B sits in the file by correlating 1 kHz envelopes.
        let env = |x: &audio::Stereo| -> Vec<f32> {
            x.ch[0].chunks(44).map(|c| c.iter().map(|v| v.abs()).sum::<f32>() / c.len() as f32).collect()
        };
        let (fe, be) = (env(&file), env(&b));
        for at in [30_000usize, 60_000, 120_000] {
            if at + 4000 >= be.len() {
                continue;
            }
            let probe = &be[at..at + 2000];
            let (mut best, mut best_pos) = (f32::MIN, 0usize);
            let mean_p = probe.iter().sum::<f32>() / probe.len() as f32;
            for pos in 0..fe.len().saturating_sub(2000) {
                let w = &fe[pos..pos + 2000];
                let mean_w = w.iter().sum::<f32>() / 2000.0;
                let c: f32 = probe.iter().zip(w).map(|(p, q)| (p - mean_p) * (q - mean_w)).sum();
                let n = (w.iter().map(|q| (q - mean_w).powi(2)).sum::<f32>().sqrt() * probe.iter().map(|p| (p - mean_p).powi(2)).sum::<f32>().sqrt()).max(1e-9);
                if c / n > best {
                    best = c / n;
                    best_pos = pos;
                }
            }
            println!(
                "B (aproximado): el segundo {:.1} de B está en el segundo {:.1} del archivo (correlación {best:.3}) => archivo = B + {:.2} s",
                at as f64 / 1000.0,
                best_pos as f64 / 1000.0,
                (best_pos as f64 - at as f64) / 1000.0
            );
        }
    }
    let total = file.seconds();
    println!("el tramo que no es ni A ni B dura {:.1} s; B ocupa {:.0}% del archivo", (start as f64 / sr) - 0.0, 100.0 * (total - start as f64 / sr) / total);
    Ok(())
}
