// Measurement harness: load time and throughput of the model under one tuning.
//   model_bench <song> <model-dir> <seconds> <units> <fp16:0|1> <mlprogram:0|1> [cpu]
use automix::audio;
use automix::model::{self, Compute, Priority, Tuning, Units};
use std::time::Instant;

fn rss_mb() -> f64 {
    let pid = std::process::id().to_string();
    let out = std::process::Command::new("ps").args(["-o", "rss=", "-p", &pid]).output().unwrap();
    String::from_utf8_lossy(&out.stdout).trim().parse::<f64>().unwrap_or(0.0) / 1024.0
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let song = audio::load(std::path::Path::new(&a[1])).unwrap();
    model::configure(std::path::Path::new(&a[2]));
    let secs: f64 = a[3].parse().unwrap();
    let units = match a[4].as_str() {
        "all" => Units::All,
        "gpu" => Units::CpuAndGpu,
        "ane" => Units::CpuAndNeuralEngine,
        _ => Units::CpuOnly,
    };
    model::set_tuning(Tuning { units, fp16_gpu: a[5] == "1", ml_program: a[6] == "1", ..Tuning::default() });
    if a.get(7).map(String::as_str) == Some("cpu") {
        model::set_compute(Compute::Cpu);
    }
    let w = song.slice(44_100 * 60, (secs * 44_100.0) as usize);
    let rss0 = rss_mb();
    let t = Instant::now();
    model::separate(&w, None, Priority::Normal).unwrap();
    let first = t.elapsed().as_secs_f64();
    let info = model::info().unwrap();
    let rss1 = rss_mb();
    let t = Instant::now();
    model::separate(&w, None, Priority::Normal).unwrap();
    let second = t.elapsed().as_secs_f64();
    model::unload();
    std::thread::sleep(std::time::Duration::from_millis(500));
    let rss2 = rss_mb();
    println!("rss after unload: {rss2:.0} MB");
    std::thread::sleep(std::time::Duration::from_secs(5));
    let pid = std::process::id().to_string();
    let out = std::process::Command::new("footprint").args(["-p", &pid]).output().unwrap();
    for line in String::from_utf8_lossy(&out.stdout).lines().filter(|l| l.contains("Footprint") || l.contains("Dirty") || l.contains("TOTAL")) {
        println!("footprint after unload+5s: {line}");
    }
    println!("rss after 5 s: {:.0} MB", rss_mb());
    println!(
        "{} [{}] load {:.1}s | first call {:.1}s | warm call {:.2}s = {:.1}x realtime ({:.1} x by window) | rss {:.0} -> {:.0} MB",
        info.provider, info.detail, info.load_seconds, first, second, secs / second, model::realtime_factor().unwrap_or(0.0), rss0, rss1
    );
}
