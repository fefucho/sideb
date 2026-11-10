//! One provider process per request. A trusted, explicitly installed executable, not a sandbox.
//! The job owns one private directory: closing the process comes before removing it, and the
//! directory outlives `run` (a lease) until the consumer releases the job.
//!
//! No secret ever reaches argv, the environment or stderr: the credential travels on stdin only,
//! the environment is empty (plus the three OS variables Windows needs to load system libraries),
//! stderr is discarded and the console window is suppressed.

use super::lease;
use super::protocol::{Failure, Outcome, MAX_INPUT_BYTES, MAX_OUTPUT_BYTES};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const POLL: Duration = Duration::from_millis(20);

pub struct Job {
    directory: PathBuf,
    cancelled: AtomicBool,
    finished: AtomicBool,
    kill: Mutex<Option<Arc<AtomicBool>>>,
}

impl Job {
    pub fn new(directory: PathBuf) -> Arc<Self> {
        Arc::new(Self {
            directory,
            cancelled: AtomicBool::new(false),
            finished: AtomicBool::new(false),
            kill: Mutex::new(None),
        })
    }

    pub fn directory(&self) -> &Path {
        &self.directory
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }

    /// Terminates the process, then removes the directory (immediately if the process is already
    /// done, otherwise as soon as `run` observes the cancellation).
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
        if let Some(flag) = self.kill.lock().ok().and_then(|slot| slot.clone()) {
            flag.store(true, Ordering::SeqCst);
        }
        if self.finished.load(Ordering::SeqCst) {
            lease::remove_dir_with_retries(self.directory.clone());
        }
    }

    fn finish(&self) {
        self.finished.store(true, Ordering::SeqCst);
        if self.is_cancelled() {
            lease::remove_dir_with_retries(self.directory.clone());
        }
    }

    /// Blocking. Returns stdout (<= 16 KiB) of a process that exited with status 0.
    pub fn run(&self, executable: &Path, input: &[u8], deadline: Duration) -> Outcome<Vec<u8>> {
        let result = self.run_inner(executable, input, deadline);
        self.finish();
        result
    }

    fn run_inner(&self, executable: &Path, input: &[u8], deadline: Duration) -> Outcome<Vec<u8>> {
        if input.len() > MAX_INPUT_BYTES {
            return Err(Failure::Invalid);
        }
        if self.is_cancelled() {
            return Err(Failure::Cancelled);
        }
        let mut command = Command::new(executable);
        command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .env_clear();
        for name in ["SystemRoot", "SystemDrive", "windir"] {
            if cfg!(windows) {
                if let Some(value) = std::env::var_os(name) {
                    command.env(name, value);
                }
            }
        }
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            const CREATE_NO_WINDOW: u32 = 0x0800_0000;
            command.creation_flags(CREATE_NO_WINDOW);
        }
        let kill = Arc::new(AtomicBool::new(false));
        if let Ok(mut slot) = self.kill.lock() {
            *slot = Some(kill.clone());
        }
        let mut child = command.spawn().map_err(|_| Failure::Unavailable)?;
        // `cancel` may have run between the check above and the spawn.
        if self.is_cancelled() {
            let _ = child.kill();
            let _ = child.wait();
            return Err(Failure::Cancelled);
        }

        let mut stdin = child.stdin.take();
        let payload = input.to_vec();
        let writer = std::thread::spawn(move || {
            if let Some(pipe) = stdin.as_mut() {
                let _ = pipe.write_all(&payload);
            }
            drop(stdin); // closing stdin ends the request
        });

        let output = Arc::new(Mutex::new(Vec::<u8>::new()));
        let overflow = Arc::new(AtomicBool::new(false));
        let mut stdout = child.stdout.take().ok_or(Failure::Unavailable)?;
        let (sink, flag) = (output.clone(), overflow.clone());
        let reader = std::thread::spawn(move || {
            let mut chunk = [0u8; 4096];
            while let Ok(read) = stdout.read(&mut chunk) {
                if read == 0 {
                    break;
                }
                let mut buffer = sink.lock().unwrap_or_else(|e| e.into_inner());
                if buffer.len() + read > MAX_OUTPUT_BYTES {
                    flag.store(true, Ordering::SeqCst);
                    break;
                }
                buffer.extend_from_slice(&chunk[..read]);
            }
        });

        let started = Instant::now();
        let outcome = loop {
            if kill.load(Ordering::SeqCst) || self.is_cancelled() {
                break Err(Failure::Cancelled);
            }
            if overflow.load(Ordering::SeqCst) {
                break Err(Failure::Invalid);
            }
            match child.try_wait() {
                Ok(Some(status)) => {
                    break if status.success() {
                        Ok(())
                    } else {
                        Err(Failure::Unavailable)
                    }
                }
                Ok(None) => {}
                Err(_) => break Err(Failure::Unavailable),
            }
            if started.elapsed() >= deadline {
                break Err(Failure::Unavailable);
            }
            std::thread::sleep(POLL);
        };
        if outcome.is_err() {
            let _ = child.kill();
        }
        let _ = child.wait();
        let _ = writer.join();
        if outcome.is_ok() {
            // The process is gone: its pipe is at EOF and the reader drains what is left.
            let _ = reader.join();
        }
        outcome?;
        if overflow.load(Ordering::SeqCst) {
            return Err(Failure::Invalid);
        }
        if self.is_cancelled() {
            return Err(Failure::Cancelled);
        }
        let bytes = output.lock().map(|b| b.clone()).unwrap_or_default();
        Ok(bytes)
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn script(name: &str, body: &str) -> (PathBuf, PathBuf) {
        let dir = std::env::temp_dir().join(format!("sideb-job-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let exe = dir.join("provider.sh");
        std::fs::write(&exe, format!("#!/bin/sh\n{body}\n")).unwrap();
        std::fs::set_permissions(&exe, std::fs::Permissions::from_mode(0o700)).unwrap();
        (dir.join("out"), exe)
    }

    fn job(dir: &Path) -> Arc<Job> {
        std::fs::create_dir_all(dir).unwrap();
        Job::new(dir.to_path_buf())
    }

    #[test]
    fn echoes_stdin_and_requires_exit_zero() {
        let (out, exe) = script("echo", "cat");
        let job = job(&out);
        let data = job
            .run(&exe, br#"{"x":1}"#, Duration::from_secs(5))
            .unwrap();
        assert_eq!(data, br#"{"x":1}"#);
        assert!(
            out.exists(),
            "the lease keeps the directory after a normal finish"
        );
        job.cancel();
        assert!(wait_gone(&out), "release removes it");

        let (out, exe) = script("fail", "cat >/dev/null; echo {}; exit 3");
        assert_eq!(job_run(&out, &exe), Err(Failure::Unavailable));
    }

    fn job_run(out: &Path, exe: &Path) -> Outcome<Vec<u8>> {
        job(out).run(exe, b"{}", Duration::from_secs(5))
    }

    fn wait_gone(path: &Path) -> bool {
        for _ in 0..100 {
            if !path.exists() {
                return true;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        false
    }

    #[test]
    fn parent_environment_is_not_inherited() {
        std::env::set_var("SIDEB_TEST_SECRET_W6", "hunter2");
        let (out, exe) = script(
            "env",
            "cat >/dev/null; if env | grep -q SIDEB_TEST_SECRET_W6; then echo '{\"leak\":true}'; else echo '{\"leak\":false}'; fi",
        );
        let data = job_run(&out, &exe).unwrap();
        assert_eq!(String::from_utf8(data).unwrap().trim(), r#"{"leak":false}"#);
    }

    #[test]
    fn output_over_16_kib_is_rejected() {
        let (out, exe) = script(
            "flood",
            "cat >/dev/null; head -c 40000 /dev/zero | tr '\\0' 'a'",
        );
        assert_eq!(job_run(&out, &exe), Err(Failure::Invalid));
    }

    #[test]
    fn exactly_16_kib_is_accepted() {
        let (out, exe) = script(
            "limit",
            "cat >/dev/null; head -c 16384 /dev/zero | tr '\\0' 'a'",
        );
        assert_eq!(job_run(&out, &exe).unwrap().len(), 16384);
    }

    #[test]
    fn deadline_kills_a_stuck_process() {
        let (out, exe) = script("stuck", "sleep 30");
        let started = Instant::now();
        let result = job(&out).run(&exe, b"{}", Duration::from_millis(300));
        assert_eq!(result, Err(Failure::Unavailable));
        assert!(started.elapsed() < Duration::from_secs(5));
    }

    #[test]
    fn cancel_terminates_and_removes_the_directory() {
        let (out, exe) = script("cancel", "sleep 30");
        let job = job(&out);
        let runner = job.clone();
        let handle = std::thread::spawn(move || runner.run(&exe, b"{}", Duration::from_secs(30)));
        std::thread::sleep(Duration::from_millis(300));
        let started = Instant::now();
        job.cancel();
        assert_eq!(handle.join().unwrap(), Err(Failure::Cancelled));
        assert!(started.elapsed() < Duration::from_secs(5));
        assert!(wait_gone(&out));
    }

    #[test]
    fn cancel_before_run_never_spawns() {
        let (out, exe) = script("early", "touch spawned; cat");
        let job = job(&out);
        job.cancel();
        assert_eq!(
            job.run(&exe, b"{}", Duration::from_secs(5)),
            Err(Failure::Cancelled)
        );
    }

    #[test]
    fn oversized_input_is_refused() {
        let (out, exe) = script("big", "cat");
        let big = vec![b'a'; MAX_INPUT_BYTES + 1];
        assert_eq!(
            job(&out).run(&exe, &big, Duration::from_secs(5)),
            Err(Failure::Invalid)
        );
    }
}
