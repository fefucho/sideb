use std::{future::Future, time::Duration};
use tokio::sync::{Mutex, MutexGuard, RwLock, RwLockReadGuard, RwLockWriteGuard};

/// Requests share stable credentials. Only replacing/removing the session is
/// exclusive; background library reads must never serialize user mutations.
#[derive(Default)]
pub struct SessionOperations {
    session: RwLock<()>,
    mutations: Mutex<()>,
}

pub struct MutationGuard<'a> {
    _session: RwLockReadGuard<'a, ()>,
    _mutation: MutexGuard<'a, ()>,
}

impl SessionOperations {
    pub async fn read(&self) -> RwLockReadGuard<'_, ()> {
        self.session.read().await
    }

    pub async fn write(&self) -> RwLockWriteGuard<'_, ()> {
        self.session.write().await
    }

    pub async fn mutation(&self) -> MutationGuard<'_> {
        // Queued mutations do not pin the old session while waiting their turn.
        let mutation = self.mutations.lock().await;
        let session = self.session.read().await;
        MutationGuard {
            _session: session,
            _mutation: mutation,
        }
    }

    /// Includes queueing and transport. Dropping the future releases both guards;
    /// the caller reports an unconfirmed result and never retries automatically.
    pub async fn run_mutation<F: Future>(
        &self,
        action: F,
    ) -> Result<F::Output, tokio::time::error::Elapsed> {
        tokio::time::timeout(Duration::from_secs(15), async {
            let _guard = self.mutation().await;
            action.await
        })
        .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    };
    use tokio::{sync::oneshot, task::yield_now, time::timeout};

    #[tokio::test(start_paused = true)]
    async fn a_slow_library_request_does_not_delay_a_like_or_other_reads() {
        let operations = SessionOperations::default();
        let _library = operations.read().await;
        assert_eq!(
            operations.run_mutation(async { "liked" }).await.unwrap(),
            "liked"
        );
        let _other_library = timeout(Duration::from_millis(1), operations.read())
            .await
            .unwrap();
    }

    #[tokio::test(start_paused = true)]
    async fn session_replacement_waits_for_requests_and_blocks_new_mutations() {
        let operations = SessionOperations::default();
        let library = operations.read().await;
        assert!(timeout(Duration::from_millis(1), operations.write())
            .await
            .is_err());
        drop(library);
        let replacement = operations.write().await;
        let called = AtomicBool::new(false);
        assert!(operations
            .run_mutation(async { called.store(true, Ordering::SeqCst) })
            .await
            .is_err());
        assert!(!called.load(Ordering::SeqCst));
        drop(replacement);
        assert!(operations.run_mutation(async {}).await.is_ok());
    }

    #[tokio::test(start_paused = true)]
    async fn mutations_remain_serialized_but_reads_can_continue() {
        let operations = Arc::new(SessionOperations::default());
        let (started, ready) = oneshot::channel();
        let (finish, finished) = oneshot::channel();
        let first_operations = operations.clone();
        let first = tokio::spawn(async move {
            first_operations
                .run_mutation(async {
                    started.send(()).unwrap();
                    finished.await.unwrap();
                })
                .await
        });
        ready.await.unwrap();
        let called = Arc::new(AtomicBool::new(false));
        let second_called = called.clone();
        let second_operations = operations.clone();
        let second = tokio::spawn(async move {
            second_operations
                .run_mutation(async { second_called.store(true, Ordering::SeqCst) })
                .await
        });
        yield_now().await;
        assert!(!called.load(Ordering::SeqCst));
        let _library = operations.read().await;
        finish.send(()).unwrap();
        first.await.unwrap().unwrap();
        second.await.unwrap().unwrap();
        assert!(called.load(Ordering::SeqCst));
    }

    #[tokio::test(start_paused = true)]
    async fn an_unanswered_action_times_out_and_releases_the_session_and_mutation_queue() {
        let operations = SessionOperations::default();
        assert!(operations
            .run_mutation(std::future::pending::<()>())
            .await
            .is_err());
        let replacement = timeout(Duration::from_millis(1), operations.write())
            .await
            .unwrap();
        drop(replacement);
        assert_eq!(operations.run_mutation(async { 42 }).await.unwrap(), 42);
    }
}
