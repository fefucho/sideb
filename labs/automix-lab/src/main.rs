//! automix-lab: a bench for auditioning automatic DJ-style transitions.
//!
//! Two songs in, one WAV out: the end of the first, a beat-matched,
//! stem-aware transition, and the start of the second. Not part of the app.

mod audio;
mod grid;
mod mix;
mod stems;
mod stretch;
mod synth;
mod yt;

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
        /// Segundos de A antes de la mezcla y de B después.
        #[arg(long, default_value_t = 20.0)]
        pre: f64,
        #[arg(long, default_value_t = 20.0)]
        post: f64,
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
        Command::Synth { out, bpm, root, bars, lead_in } => {
            let (audio, downbeat) = synth::generate(&synth::Spec { bpm, root, bars, lead_in, seed: 7 });
            audio::save(&out, &audio)?;
            println!("{}: {bpm} BPM, primer tiempo en {downbeat:.3} s, {:.1} s", out.display(), audio.seconds());
            Ok(())
        }
        Command::Mix { a, b, out, max_bars, pre, post, no_stems, a_downbeat, b_downbeat } => {
            let opts = mix::Options {
                max_bars,
                pre_seconds: pre,
                post_seconds: post,
                stem_mode: if no_stems { mix::StemMode::Frequency } else { mix::StemMode::Model },
                a_downbeat_shift: a_downbeat,
                b_downbeat_shift: b_downbeat,
            };
            run_mix(a, b, out, opts)
        }
    }
}

/// A local file, or `yt:<search, id or URL>` fetched into `out/cache/`.
fn load_track(source: &str) -> Result<mix::Track> {
    if let Some(what) = source.strip_prefix("yt:") {
        let fetched = yt::fetch(what, std::path::Path::new("out/cache"))?;
        let key = fetched.path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
        return Ok(mix::Track::new(fetched.title, key, audio::load(&fetched.path)?));
    }
    let path = PathBuf::from(source);
    let name = path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    let key: String = name.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect();
    Ok(mix::Track::new(name, key, audio::load(&path)?))
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

fn run_mix(a: String, b: String, out: PathBuf, opts: mix::Options) -> Result<()> {
    let started = Instant::now();
    let track_a = load_track(&a)?;
    let track_b = load_track(&b)?;
    let plan = mix::plan(&track_a, &track_b, &opts, std::path::Path::new("out/stems-cache"))?;
    let k = plan.beats;
    let source = |drums: bool, refined: bool| {
        format!(
            "{}{}",
            if drums { "grilla de batería" } else { "grilla de la mezcla" },
            if refined { ", golpes seguidos" } else { ", grilla rígida" }
        )
    };
    println!(
        "A «{}»: {:.2} BPM (confianza {:.2}; {}), sale de {:.2} a {:.2} s",
        track_a.name,
        plan.a.grid.bpm,
        plan.a.grid.confidence,
        source(plan.a.grid_from_drums, plan.a_refined),
        plan.a_beats[0],
        plan.a_beats[k]
    );
    println!(
        "B «{}»: {:.2} BPM (confianza {:.2}; {}), entra de {:.2} a {:.2} s",
        track_b.name,
        plan.b.grid.bpm,
        plan.b.grid.confidence,
        source(plan.b.grid_from_drums, plan.b_refined),
        plan.b_beats[0],
        plan.b_beats[k]
    );
    println!(
        "Estructura: A {}; B {}",
        match plan.a_outro_bars {
            Some(bars) => format!("deja de cantar {bars} compases antes del final, se saltean {}", plan.a_skipped_bars),
            None => "sin voz detectada en el final".to_owned(),
        },
        match plan.b_intro_bars {
            Some(bars) => format!("canta o arranca fuerte a los {bars} compases"),
            None => "sin entrada fuerte detectada en el principio".to_owned(),
        }
    );
    println!(
        "Mezcla: {} compases, {:.1} s, cambio de bajo a los {:.1} s; armonía {:.2} ({})",
        k / 4,
        plan.beat_times[k],
        plan.beat_times[k / 2],
        plan.harmony,
        if mix::harmony_clashes(&plan) { "choque: no se superponen" } else { "compatible" }
    );
    let analysed = started.elapsed();

    let rendered = mix::render(&track_a, &track_b, &plan, &opts)?;
    audio::save(&out, &rendered.mix)?;
    let baseline = out.with_file_name(format!(
        "{}-crossfade.wav",
        out.file_stem().map(|s| s.to_string_lossy()).unwrap_or_default()
    ));
    audio::save(&baseline, &rendered.baseline)?;
    println!(
        "La mezcla ocupa de {:.1} a {:.1} s del archivo.",
        rendered.overlap.0, rendered.overlap.1
    );
    println!("Análisis y stems {:.1} s, render {:.1} s", analysed.as_secs_f64(), (started.elapsed() - analysed).as_secs_f64());
    println!("Transición:      {}", out.display());
    println!("Crossfade común: {}", baseline.display());
    Ok(())
}
