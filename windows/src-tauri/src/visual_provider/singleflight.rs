//! One recovery at a time: concurrent callers share the same attempt (and its result).

use std::future::Future;
use std::sync::{Arc, Mutex};
use tokio::sync::watch;

pub struct SingleFlight<T> {
    slot: Mutex<Option<watch::Receiver<Option<T>>>>,
}

impl<T> Default for SingleFlight<T> {
    fn default() -> Self {
        Self {
            slot: Mutex::new(None),
        }
    }
}

struct ClearOnDrop<T>(Arc<SingleFlight<T>>);

impl<T> Drop for ClearOnDrop<T> {
    fn drop(&mut self) {
        if let Ok(mut slot) = self.0.slot.lock() {
            *slot = None;
        }
    }
}

impl<T: Clone + Default + Send + Sync + 'static> SingleFlight<T> {
    pub fn is_running(&self) -> bool {
        self.slot.lock().map(|slot| slot.is_some()).unwrap_or(false)
    }

    /// The first caller starts `make()` on the async runtime (it survives that caller being
    /// dropped); everyone else waits for the same value. A crashed flight yields `T::default()`.
    pub async fn run<F, M>(self: &Arc<Self>, make: M) -> T
    where
        F: Future<Output = T> + Send + 'static,
        M: FnOnce() -> F,
    {
        let (mut rx, leader) = {
            let mut slot = self.slot.lock().unwrap_or_else(|e| e.into_inner());
            match slot.as_ref().filter(|rx| rx.has_changed().is_ok()) {
                Some(rx) => (rx.clone(), None),
                None => {
                    let (tx, rx) = watch::channel(None);
                    *slot = Some(rx.clone());
                    (rx, Some(tx))
                }
            }
        };
        if let Some(tx) = leader {
            let future = make();
            let guard = ClearOnDrop(self.clone());
            tauri::async_runtime::spawn(async move {
                let value = future.await;
                drop(guard); // the slot is free before anyone observes the result
                let _ = tx.send(Some(value));
            });
        }
        loop {
            if let Some(value) = rx.borrow_and_update().clone() {
                return value;
            }
            if rx.changed().await.is_err() {
                return rx.borrow().clone().unwrap_or_default();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Duration;

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn concurrent_callers_share_one_flight() {
        let flights = Arc::new(AtomicUsize::new(0));
        let gate = Arc::new(SingleFlight::<Option<String>>::default());
        let make = |flights: Arc<AtomicUsize>| {
            move || async move {
                flights.fetch_add(1, Ordering::SeqCst);
                tokio::time::sleep(Duration::from_millis(150)).await;
                Some("token".to_owned())
            }
        };
        let (a, b, c) = tokio::join!(
            gate.run(make(flights.clone())),
            gate.run(make(flights.clone())),
            gate.run(make(flights.clone())),
        );
        assert_eq!(
            (a.as_deref(), b.as_deref(), c.as_deref()),
            (Some("token"), Some("token"), Some("token"))
        );
        assert_eq!(flights.load(Ordering::SeqCst), 1);
        assert!(!gate.is_running());
        // A later call starts a new flight.
        assert_eq!(
            gate.run(make(flights.clone())).await.as_deref(),
            Some("token")
        );
        assert_eq!(flights.load(Ordering::SeqCst), 2);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_panicking_flight_yields_default_and_frees_the_slot() {
        let gate = Arc::new(SingleFlight::<Option<String>>::default());
        let value = gate.run(|| async { panic!("boom") }).await;
        assert_eq!(value, None);
        assert_eq!(
            gate.run(|| async { Some("again".to_owned()) })
                .await
                .as_deref(),
            Some("again")
        );
    }
}
