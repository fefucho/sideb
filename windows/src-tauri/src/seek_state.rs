//! Windows seek intent, separate from the position observed by libmpv.
//! No engine calls or playback clock: the deadline also expires while paused.
use std::time::{Duration, Instant};

pub(crate) const SEEK_DEADLINE: Duration = Duration::from_secs(15);
const POSITION_TOLERANCE: f64 = 0.25;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct SeekOwner {
    pub auth: u64,
    pub generation: u64,
    pub entry_id: String,
}
#[derive(Clone, Debug)]
pub(crate) struct PendingSeek {
    pub owner: SeekOwner,
    pub target: f64,
    pub deadline: Instant,
    pub dispatched: bool,
    pub resuming: bool,
}
#[derive(Default)]
pub(crate) struct SeekState {
    pub revision: u64,
    pub pending: Option<PendingSeek>,
    pub error: Option<String>,
    pub deferred_eof: bool,
}
impl SeekState {
    pub fn begin(
        &mut self,
        owner: SeekOwner,
        seconds: f64,
        duration: f64,
        now: Instant,
        resuming: bool,
    ) -> u64 {
        self.revision = self.revision.wrapping_add(1);
        self.error = None;
        let target = if duration.is_finite() && duration > 0.0 {
            seconds.min(duration)
        } else {
            seconds
        };
        self.pending = Some(PendingSeek {
            owner,
            target,
            deadline: now + SEEK_DEADLINE,
            dispatched: false,
            resuming,
        });
        self.revision
    }
    pub fn adopt(&mut self, previous: u64, owner: &SeekOwner) {
        if let Some(pending) = self.pending.as_mut() {
            if pending.resuming
                && pending.owner.generation == previous
                && pending.owner.auth == owner.auth
                && pending.owner.entry_id == owner.entry_id
            {
                pending.owner.generation = owner.generation;
                pending.resuming = false;
                return;
            }
        }
        self.cancel();
    }
    pub fn cancel(&mut self) {
        self.revision = self.revision.wrapping_add(1);
        self.pending = None;
        self.error = None;
        self.deferred_eof = false;
    }
    pub fn fail(&mut self, revision: u64, message: &str) -> bool {
        if self.revision != revision || self.pending.is_none() {
            return false;
        }
        self.revision = self.revision.wrapping_add(1);
        self.pending = None;
        self.error = Some(message.into());
        true
    }
    pub fn observe(&mut self, owner: &SeekOwner, position: f64, now: Instant) -> bool {
        let Some(pending) = self.pending.as_ref() else {
            return false;
        };
        if pending.owner != *owner || !pending.dispatched {
            return false;
        }
        if now >= pending.deadline {
            return self.fail(
                self.revision,
                "No se pudo confirmar la posición solicitada a tiempo.",
            );
        }
        if position.is_finite() && (position - pending.target).abs() <= POSITION_TOLERANCE {
            self.revision = self.revision.wrapping_add(1);
            self.pending = None;
            self.error = None;
            return true;
        }
        false
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn owner(generation: u64, entry: &str) -> SeekOwner {
        SeekOwner {
            auth: 3,
            generation,
            entry_id: entry.into(),
        }
    }
    #[test]
    fn observed_position_is_required_and_undispatched_samples_cannot_confirm() {
        let mut seek = SeekState::default();
        let now = Instant::now();
        seek.begin(owner(4, "a"), 41.0, 0.0, now, false);
        assert!(!seek.observe(&owner(4, "a"), 41.0, now));
        seek.pending.as_mut().unwrap().dispatched = true;
        assert!(!seek.observe(&owner(4, "a"), 0.0, now));
        assert!(seek.observe(&owner(4, "a"), 41.07, now));
        assert!(seek.pending.is_none());
    }
    #[test]
    fn last_cue_wins_and_stale_deadline_cannot_fail_it() {
        let mut seek = SeekState::default();
        let now = Instant::now();
        let old = seek.begin(owner(4, "a"), 30.0, 200.0, now, false);
        seek.begin(owner(4, "a"), 80.0, 200.0, now, false);
        assert!(!seek.fail(old, "old timeout"));
        seek.pending.as_mut().unwrap().dispatched = true;
        assert!(!seek.observe(&owner(4, "a"), 30.0, now));
        assert!(seek.observe(&owner(4, "a"), 80.0, now));
    }
    #[test]
    fn restored_adoption_is_scoped_to_account_and_occurrence() {
        let mut seek = SeekState::default();
        let now = Instant::now();
        seek.begin(owner(4, "a"), 90.0, 0.0, now, true);
        let mut wrong = SeekState::default();
        wrong.begin(owner(4, "a"), 90.0, 0.0, now, true);
        wrong.adopt(4, &owner(5, "duplicate"));
        assert!(wrong.pending.is_none());
        wrong.begin(owner(4, "a"), 90.0, 0.0, now, true);
        let mut other_account = owner(5, "a");
        other_account.auth = 9;
        wrong.adopt(4, &other_account);
        assert!(wrong.pending.is_none());
        seek.adopt(4, &owner(5, "a"));
        assert_eq!(seek.pending.as_ref().unwrap().owner.generation, 5);
        seek.pending.as_mut().unwrap().dispatched = true;
        assert!(!seek.observe(&owner(4, "a"), 90.0, now));
        assert!(seek.observe(&owner(5, "a"), 90.0, now));
    }
    #[test]
    fn duration_clamp_and_paused_deadline_do_not_require_clock_ticks() {
        let mut seek = SeekState::default();
        let now = Instant::now();
        seek.begin(owner(4, "a"), 90.0, 0.0, now, false);
        assert_eq!(seek.pending.as_ref().unwrap().target, 90.0);
        seek.begin(owner(4, "a"), 90.0, 45.0, now, false);
        assert_eq!(seek.pending.as_ref().unwrap().target, 45.0);
        assert!(seek.fail(seek.revision, "timeout"));
        assert!(seek.pending.is_none());
        assert_eq!(seek.error.as_deref(), Some("timeout"));
    }
    #[test]
    fn deferred_eof_waits_for_observed_result_and_is_cancelled_on_item_replacement() {
        let mut seek = SeekState::default();
        let now = Instant::now();
        seek.begin(owner(4, "a"), 80.0, 200.0, now, false);
        seek.deferred_eof = true;
        seek.begin(owner(4, "a"), 30.0, 200.0, now, false);
        assert!(seek.deferred_eof);
        seek.pending.as_mut().unwrap().dispatched = true;
        assert!(!seek.observe(&owner(4, "a"), 80.0, now));
        assert!(seek.observe(&owner(4, "a"), 30.0, now));
        assert!(seek.pending.is_none());
        assert!(seek.deferred_eof);
        // The native waiter checks is_idle before replaying EOF. A replacement
        // cancels that waiter even if its callback was already queued.
        seek.cancel();
        assert!(!seek.deferred_eof);
    }
}
