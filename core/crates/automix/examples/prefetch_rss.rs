// Peak memory and time of prefetching the two ends of one song.
//   prefetch_rss <song.m4a> <stems-dir> <model-dir> [auto|cpu|gpu] [threads]
use automix::model::{self, Compute, Tuning};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

fn rss_kb() -> u64 {
    let pid = std::process::id().to_string();
    let out = std::process::Command::new("ps").args(["-o", "rss=", "-p", &pid]).output().unwrap();
    String::from_utf8_lossy(&out.stdout).trim().parse::<u64>().unwrap_or(0)
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let stems = std::path::PathBuf::from(&a[2]);
    let _ = std::fs::remove_dir_all(&stems);
    model::configure(std::path::Path::new(&a[3]));
    match a.get(4).map(String::as_str) {
        Some("cpu") => model::set_compute(Compute::Cpu),
        Some("gpu") => model::set_compute(Compute::Gpu),
        Some("keep") => model::set_idle_release(None),
        _ => {}
    }
    if let Some(t) = a.get(5) {
        model::set_tuning(Tuning { threads: t.parse().unwrap(), ..Tuning::default() });
    }
    let peak = Arc::new(AtomicU64::new(0));
    let stop = Arc::new(AtomicBool::new(false));
    let sampler = {
        let (peak, stop) = (peak.clone(), stop.clone());
        std::thread::spawn(move || {
            while !stop.load(Ordering::Relaxed) {
                peak.fetch_max(rss_kb(), Ordering::Relaxed);
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
        })
    };
    let start = rss_kb();
    let t = std::time::Instant::now();
    let audio = automix::audio::load(std::path::Path::new(&a[1])).unwrap();
    let track = automix::Track::new("t".into(), "t".into(), audio);
    let decoded = t.elapsed().as_secs_f64();
    let seconds = automix::prefetch::prefetch(&track, &stems, true, true, None).unwrap();
    let total = t.elapsed().as_secs_f64();
    drop(track);
    let after = rss_kb();
    model::unload();
    std::thread::sleep(std::time::Duration::from_secs(3));
    println!("rss 3 s after unloading the model: {} MB", rss_kb() / 1024);
    stop.store(true, Ordering::Relaxed);
    sampler.join().unwrap();
    println!(
        "{} s of audio separated; decode+analysis {:.1}s, total {:.1}s; rss start {} MB, peak {} MB, after {} MB; {:?}",
        seconds as u64,
        decoded,
        total,
        start / 1024,
        peak.load(Ordering::Relaxed) / 1024,
        after / 1024,
        model::info().map(|i| format!("{} {}", i.provider, i.detail))
    );
}
