use crate::HomeArtistRunDto;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

static NEXT_ENTRY_ID: AtomicU64 = AtomicU64::new(1);
static SHUFFLE_COUNTER: AtomicU64 = AtomicU64::new(1);
const PLAYLIST_BATCH_SIZE: usize = 100;
const PLAYLIST_REFILL_THRESHOLD: usize = 10;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueueEntryDto {
    pub entry_id: String,
    pub video_id: String,
    pub title: String,
    pub artists: String,
    pub thumbnail: Option<String>,
    pub duration: Option<f64>,
    #[serde(default)]
    pub artist_id: Option<String>,
    #[serde(default)]
    pub album_id: Option<String>,
    #[serde(default)]
    pub album: Option<String>,
    #[serde(default)]
    pub artist_runs: Vec<HomeArtistRunDto>,
}

impl QueueEntryDto {
    pub fn new(
        video_id: String,
        title: String,
        artists: String,
        thumbnail: Option<String>,
        duration: Option<f64>,
    ) -> Self {
        Self::with_metadata(
            video_id, title, artists, thumbnail, duration, None, None, None,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub fn with_metadata(
        video_id: String,
        title: String,
        artists: String,
        thumbnail: Option<String>,
        duration: Option<f64>,
        artist_id: Option<String>,
        album_id: Option<String>,
        album: Option<String>,
    ) -> Self {
        Self::with_metadata_and_runs(
            video_id,
            title,
            artists,
            thumbnail,
            duration,
            artist_id,
            album_id,
            album,
            Vec::new(),
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub fn with_metadata_and_runs(
        video_id: String,
        title: String,
        artists: String,
        thumbnail: Option<String>,
        duration: Option<f64>,
        artist_id: Option<String>,
        album_id: Option<String>,
        album: Option<String>,
        artist_runs: Vec<HomeArtistRunDto>,
    ) -> Self {
        Self {
            entry_id: format!("queue-{}", NEXT_ENTRY_ID.fetch_add(1, Ordering::Relaxed)),
            video_id,
            title,
            artists,
            thumbnail,
            duration,
            artist_id,
            album_id,
            album,
            artist_runs,
        }
    }

    fn enrich_missing_metadata(&mut self, source: &Self) -> bool {
        let mut changed = false;
        if self.artists.trim().is_empty() && !source.artists.trim().is_empty() {
            self.artists = source.artists.clone();
            changed = true;
        }
        if self.artist_id.is_none() && source.artist_id.is_some() {
            self.artist_id = source.artist_id.clone();
            changed = true;
        }
        if self.album_id.is_none() && source.album_id.is_some() {
            self.album_id = source.album_id.clone();
            changed = true;
        }
        if self.album.is_none() && source.album.is_some() {
            self.album = source.album.clone();
            changed = true;
        }
        if self.artist_runs.is_empty() && !source.artist_runs.is_empty() {
            self.artist_runs = source.artist_runs.clone();
            changed = true;
        }
        changed
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueueSourceDto {
    pub kind: String,
    pub id: Option<String>,
    pub title: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueueRadioDto {
    pub loading: bool,
    pub error: Option<String>,
    pub can_retry: bool,
}

impl Default for QueueRadioDto {
    fn default() -> Self {
        Self {
            loading: false,
            error: None,
            can_retry: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueueStateDto {
    pub items: Vec<QueueEntryDto>,
    pub current_index: Option<usize>,
    pub source: Option<QueueSourceDto>,
    pub revision: u64,
    #[serde(default)]
    pub radio: Option<QueueRadioDto>,
    // The runtime retains the complete order; snapshots expose it in batches.
    #[serde(skip)]
    visible_len: usize,
    // Canonical rank belongs to each source occurrence, never its video ID. Explicit
    // insertions and drag edits have no rank and retain their queue slots on toggles.
    #[serde(skip)]
    source_ranks: HashMap<String, usize>,
    #[serde(skip)]
    next_source_rank: usize,
}

impl Default for QueueStateDto {
    fn default() -> Self {
        Self {
            items: vec![],
            current_index: None,
            source: None,
            revision: 0,
            radio: None,
            visible_len: 0,
            source_ranks: HashMap::new(),
            next_source_rank: 0,
        }
    }
}

impl QueueStateDto {
    pub fn snapshot(&self) -> Self {
        let len = if self
            .source
            .as_ref()
            .is_some_and(|source| source.kind == "playlist")
        {
            self.visible_len.min(self.items.len())
        } else {
            self.items.len()
        };
        Self {
            items: self.items[..len].to_vec(),
            current_index: self.current_index,
            source: self.source.clone(),
            revision: self.revision,
            radio: self.radio.clone(),
            visible_len: len,
            // Playback policy stays native; public snapshots need only visible items.
            source_ranks: HashMap::new(),
            next_source_rank: 0,
        }
    }

    fn extend_visible_batch(&mut self) {
        if let Some(index) = self.current_index {
            if index.saturating_add(PLAYLIST_REFILL_THRESHOLD + 1) >= self.visible_len {
                self.visible_len = self
                    .visible_len
                    .saturating_add(PLAYLIST_BATCH_SIZE)
                    .max(index.saturating_add(1))
                    .min(self.items.len());
            }
        }
    }

    pub fn replace(
        &mut self,
        items: Vec<QueueEntryDto>,
        current_index: usize,
        source: QueueSourceDto,
    ) -> Option<QueueEntryDto> {
        if items.is_empty() || current_index >= items.len() {
            return None;
        }
        // A replacement starts a new queue owner. Never trust occurrence IDs supplied
        // by the previous owner/client; stale asynchronous work must not match this queue.
        self.items = items
            .into_iter()
            .map(|mut item| {
                item.entry_id = new_entry_id();
                item
            })
            .collect();
        self.source_ranks = self
            .items
            .iter()
            .enumerate()
            .map(|(rank, entry)| (entry.entry_id.clone(), rank))
            .collect();
        self.next_source_rank = self.items.len();
        self.current_index = Some(current_index);
        self.visible_len = current_index
            .saturating_add(PLAYLIST_BATCH_SIZE)
            .min(self.items.len());
        self.source = Some(source);
        self.radio = None;
        self.revision += 1;
        self.current()
    }

    pub fn current(&self) -> Option<QueueEntryDto> {
        self.current_index
            .and_then(|index| self.items.get(index))
            .cloned()
    }

    pub fn select(&mut self, index: usize) -> Option<QueueEntryDto> {
        if index >= self.items.len() {
            return None;
        }
        self.current_index = Some(index);
        self.extend_visible_batch();
        self.revision += 1;
        self.current()
    }

    pub fn select_entry(&mut self, entry_id: &str) -> Option<QueueEntryDto> {
        let index = self
            .items
            .iter()
            .position(|entry| entry.entry_id == entry_id)?;
        self.select(index)
    }

    pub fn next(&mut self) -> Option<QueueEntryDto> {
        let next = self.current_index?.checked_add(1)?;
        self.select(next)
    }

    pub fn next_or_first(&self, wrap_at_end: bool) -> Option<QueueEntryDto> {
        let next_index = self.current_index?.checked_add(1)?;
        self.items
            .get(next_index)
            .cloned()
            .or_else(|| wrap_at_end.then(|| self.items.first().cloned()).flatten())
    }

    /// Starts shuffle without treating entries before a randomly selected canonical
    /// index as played history. The selected occurrence starts the new queue at zero.
    pub fn shuffle_on_start(&mut self) -> bool {
        let Some(index) = self.current_index else {
            return false;
        };
        if index > 0 {
            let active = self.items.remove(index);
            self.items.insert(0, active);
            self.current_index = Some(0);
            self.visible_len = PLAYLIST_BATCH_SIZE.min(self.items.len());
            self.revision += 1;
        }
        self.shuffle_after_current() || index > 0
    }

    /// Reorders only pending source occurrences, including those not yet published
    /// in a snapshot. History, active audio and explicit edits retain their slots.
    pub fn shuffle_after_current(&mut self) -> bool {
        let seed = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos() as u64)
            .unwrap_or(0)
            ^ SHUFFLE_COUNTER.fetch_add(1, Ordering::Relaxed);
        self.shuffle_after_current_with_seed(seed)
    }

    fn shuffle_after_current_with_seed(&mut self, seed: u64) -> bool {
        self.reorder_pending_source(Some(seed))
    }

    pub fn restore_order_after_current(&mut self) -> bool {
        self.reorder_pending_source(None)
    }

    fn reorder_pending_source(&mut self, seed: Option<u64>) -> bool {
        let Some(current_index) = self.current_index else {
            return false;
        };
        let Some(suffix) = self.items.get_mut(current_index.saturating_add(1)..) else {
            return false;
        };
        let slots = suffix
            .iter()
            .enumerate()
            .filter_map(|(index, entry)| {
                self.source_ranks
                    .contains_key(&entry.entry_id)
                    .then_some(index)
            })
            .collect::<Vec<_>>();
        if slots.len() < 2 {
            return false;
        }
        let mut entries = slots
            .iter()
            .map(|&index| suffix[index].clone())
            .collect::<Vec<_>>();
        if let Some(seed) = seed {
            // Small xorshift PRNG permits deterministic policy tests without dependencies.
            let mut state = if seed == 0 {
                0x9e37_79b9_7f4a_7c15
            } else {
                seed
            };
            for index in (1..entries.len()).rev() {
                state ^= state << 13;
                state ^= state >> 7;
                state ^= state << 17;
                entries.swap(index, (state as usize) % (index + 1));
            }
        } else {
            entries.sort_by_key(|entry| self.source_ranks[&entry.entry_id]);
        }
        for (index, entry) in slots.into_iter().zip(entries) {
            suffix[index] = entry;
        }
        self.revision += 1;
        true
    }

    pub fn previous(&mut self, position: f64) -> Option<QueueEntryDto> {
        if position > 3.0 {
            return self.current();
        }
        let index = self.current_index?;
        match index.checked_sub(1) {
            Some(previous) => self.select(previous),
            None => self.current(),
        }
    }

    pub fn enqueue(&mut self, items: Vec<QueueEntryDto>, at_next: bool) {
        if items.is_empty() {
            return;
        }
        let mut entries = items;
        let mut known_ids = self
            .items
            .iter()
            .map(|entry| entry.entry_id.clone())
            .collect::<HashSet<_>>();
        for entry in &mut entries {
            entry.entry_id = new_unique_entry_id(&mut known_ids);
        }
        let insert_at = if at_next {
            self.current_index
                .map_or(self.items.len(), |index| index + 1)
        } else {
            self.items.len()
        };
        let added_len = entries.len();
        self.items.splice(insert_at..insert_at, entries);
        // Explicit edits retain their existing visibility, including "add to end".
        self.visible_len = if at_next {
            self.visible_len
                .saturating_add(added_len)
                .min(self.items.len())
        } else {
            self.items.len()
        };
        if self.source.is_none() {
            self.source = Some(QueueSourceDto {
                kind: "manual".into(),
                id: None,
                title: None,
            });
        }
        self.revision += 1;
    }

    /// Removes a queue occurrence. The current item is protected so it cannot desync audio.
    pub fn remove_entry(&mut self, entry_id: &str) -> Result<bool, QueueRemoveError> {
        let Some(index) = self
            .items
            .iter()
            .position(|entry| entry.entry_id == entry_id)
        else {
            return Ok(false);
        };
        if self.current_index == Some(index) {
            return Err(QueueRemoveError::CurrentEntry);
        }
        self.items.remove(index);
        self.source_ranks.remove(entry_id);
        if index < self.visible_len {
            self.visible_len = self.visible_len.saturating_sub(1);
        }
        if let Some(current) = self.current_index {
            if index < current {
                self.current_index = Some(current - 1);
            }
        }
        self.revision += 1;
        self.extend_visible_batch();
        Ok(true)
    }

    /// Removes one exact occurrence and, when it was active, selects its successor or wraps
    /// to the first remaining occurrence. Playback orchestration performs the actual load.
    pub fn dismiss_entry(&mut self, entry_id: &str) -> Option<(bool, Option<QueueEntryDto>)> {
        let index = self
            .items
            .iter()
            .position(|entry| entry.entry_id == entry_id)?;
        let was_current = self.current_index == Some(index);
        self.items.remove(index);
        self.source_ranks.remove(entry_id);
        if index < self.visible_len {
            self.visible_len = self.visible_len.saturating_sub(1);
        }
        if was_current {
            self.current_index = if self.items.is_empty() {
                None
            } else if index < self.items.len() {
                Some(index)
            } else {
                Some(0)
            };
        } else if let Some(current) = self.current_index {
            if index < current {
                self.current_index = Some(current - 1);
            }
        }
        self.revision += 1;
        self.extend_visible_batch();
        Some((was_current, self.current()))
    }

    /// Moves one occurrence before another (or to the end), preserving the playing occurrence.
    pub fn move_entry(
        &mut self,
        entry_id: &str,
        before_entry_id: Option<&str>,
    ) -> Result<bool, QueueMoveError> {
        let from = self
            .items
            .iter()
            .position(|entry| entry.entry_id == entry_id)
            .ok_or(QueueMoveError::EntryNotFound)?;
        let before = match before_entry_id {
            Some(id) => self
                .items
                .iter()
                .position(|entry| entry.entry_id == id)
                .ok_or(QueueMoveError::TargetNotFound)?,
            None => self.items.len(),
        };
        if before == from || before == from + 1 {
            return Ok(false);
        }
        let active_id = self.current().map(|entry| entry.entry_id);
        let entry = self.items.remove(from);
        let target = if from < before { before - 1 } else { before };
        self.items.insert(target, entry);
        // A drag is an explicit placement, just like an enqueued occurrence. Future
        // shuffle toggles must not undo it or confuse it with the source's own order.
        self.source_ranks.remove(entry_id);
        if before_entry_id.is_none() {
            self.visible_len = self.items.len();
        }
        self.current_index =
            active_id.and_then(|id| self.items.iter().position(|entry| entry.entry_id == id));
        self.revision += 1;
        Ok(true)
    }

    pub fn begin_radio(&mut self) {
        self.radio = Some(QueueRadioDto {
            loading: true,
            error: None,
            can_retry: false,
        });
        self.revision += 1;
    }

    pub fn end_radio(&mut self, error: Option<String>, can_retry: bool) {
        self.radio = Some(QueueRadioDto {
            loading: false,
            error,
            can_retry,
        });
        self.revision += 1;
    }

    /// Appends unique radio recommendations, leaving explicit queue duplicates intact.
    pub fn merge_radio(&mut self, recommendations: Vec<QueueEntryDto>) -> Option<String> {
        let mut known = self
            .items
            .iter()
            .map(|entry| entry.video_id.clone())
            .collect::<HashSet<_>>();
        let mut metadata_changed = false;
        for recommendation in &recommendations {
            for existing in self
                .items
                .iter_mut()
                .filter(|entry| entry.video_id == recommendation.video_id)
            {
                metadata_changed |= existing.enrich_missing_metadata(recommendation);
            }
        }
        let mut added = Vec::new();
        for entry in recommendations {
            if entry.video_id.trim().is_empty() || !known.insert(entry.video_id.clone()) {
                continue;
            }
            added.push(entry);
        }
        let cursor = added.last().map(|entry| entry.video_id.clone());
        if !added.is_empty() {
            let mut entry_ids = self
                .items
                .iter()
                .map(|entry| entry.entry_id.clone())
                .collect::<HashSet<_>>();
            for entry in &mut added {
                if entry.entry_id.trim().is_empty() || !entry_ids.insert(entry.entry_id.clone()) {
                    entry.entry_id = new_unique_entry_id(&mut entry_ids);
                }
                self.source_ranks
                    .insert(entry.entry_id.clone(), self.next_source_rank);
                self.next_source_rank += 1;
            }
            self.items.extend(added);
            metadata_changed = true;
        }
        if metadata_changed {
            self.revision += 1;
        }
        cursor
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QueueRemoveError {
    CurrentEntry,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QueueMoveError {
    EntryNotFound,
    TargetNotFound,
}

fn new_entry_id() -> String {
    format!("queue-{}", NEXT_ENTRY_ID.fetch_add(1, Ordering::Relaxed))
}

fn new_unique_entry_id(seen: &mut HashSet<String>) -> String {
    loop {
        let id = new_entry_id();
        if seen.insert(id.clone()) {
            return id;
        }
    }
}

pub(crate) fn next_owner_epoch(epoch: u64) -> u64 {
    epoch.wrapping_add(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(id: &str) -> QueueEntryDto {
        QueueEntryDto::new(id.into(), id.into(), String::new(), None, None)
    }

    fn source() -> QueueSourceDto {
        QueueSourceDto {
            kind: "playlist".into(),
            id: Some("PL1".into()),
            title: Some("Playlist".into()),
        }
    }

    fn queue() -> QueueStateDto {
        let mut queue = QueueStateDto::default();
        queue.replace(vec![item("same"), item("same"), item("last")], 1, source());
        queue
    }

    fn entry_ids(items: &[QueueEntryDto]) -> Vec<String> {
        items.iter().map(|entry| entry.entry_id.clone()).collect()
    }

    #[test]
    fn initial_shuffle_at_a_hidden_canonical_index_keeps_the_entire_catalog() {
        let mut queue = QueueStateDto::default();
        queue.replace(
            (0..2000).map(|index| item(&index.to_string())).collect(),
            1234,
            source(),
        );
        let selected = queue.current().unwrap();
        let original_ids = entry_ids(&queue.items).into_iter().collect::<HashSet<_>>();

        queue.shuffle_on_start();

        assert_eq!(queue.current_index, Some(0));
        assert_eq!(queue.current(), Some(selected));
        assert_eq!(queue.snapshot().items.len(), 100);
        assert_eq!(
            entry_ids(&queue.items).into_iter().collect::<HashSet<_>>(),
            original_ids
        );
        assert_eq!(queue.items.len(), 2000);
        queue.restore_order_after_current();
        assert_eq!(
            queue.items[1..]
                .iter()
                .map(|entry| entry.video_id.clone())
                .collect::<Vec<_>>(),
            (0..2000)
                .filter(|&index| index != 1234)
                .map(|index| index.to_string())
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn toggles_reorder_only_pending_occurrences_across_the_complete_hidden_catalog() {
        let mut queue = QueueStateDto::default();
        queue.replace(
            (0..2000).map(|index| item(&index.to_string())).collect(),
            0,
            source(),
        );
        queue.shuffle_after_current_with_seed(42);
        queue.select(7);
        let fixed = queue.items[..8].to_vec();
        let pending_ids = entry_ids(&queue.items[8..])
            .into_iter()
            .collect::<HashSet<_>>();
        let mut canonical_pending = queue.items[8..].to_vec();
        canonical_pending.sort_by_key(|entry| queue.source_ranks[&entry.entry_id]);

        assert!(queue.restore_order_after_current());
        assert_eq!(queue.items[..8], fixed);
        assert_eq!(queue.items[8..], canonical_pending);
        assert_eq!(queue.snapshot().items.len(), 100);
        assert!(queue.shuffle_after_current_with_seed(314));
        assert_eq!(queue.items[..8], fixed);
        assert_ne!(queue.items[8..], canonical_pending);
        assert_eq!(
            entry_ids(&queue.items[8..])
                .into_iter()
                .collect::<HashSet<_>>(),
            pending_ids
        );
        assert!(queue.snapshot().items[8..].iter().any(|entry| entry
            .video_id
            .parse::<usize>()
            .unwrap()
            >= 100));
        queue.restore_order_after_current();
        assert_eq!(queue.items[8..], canonical_pending);
        assert_eq!(queue.previous(0.0), Some(fixed[6].clone()));
    }

    #[test]
    fn manual_insertions_keep_their_slots_and_duplicates_keep_their_canonical_ranks() {
        let mut queue = QueueStateDto::default();
        queue.replace((0..12).map(|_| item("same")).collect(), 0, source());
        let canonical = queue.items.clone();
        queue.shuffle_after_current_with_seed(42);
        queue.enqueue(vec![item("next-a"), item("next-b")], true);
        queue.enqueue(vec![item("end-a"), item("end-b")], false);
        let manual_slots = [1, 2, 14, 15].map(|index| (index, queue.items[index].clone()));
        let active = queue.current().unwrap();

        queue.restore_order_after_current();
        assert_eq!(queue.current(), Some(active));
        for (index, entry) in &manual_slots {
            assert_eq!(&queue.items[*index], entry);
        }
        assert_eq!(queue.items[3..14], canonical[1..]);
        queue.shuffle_after_current_with_seed(67);
        for (index, entry) in &manual_slots {
            assert_eq!(&queue.items[*index], entry);
        }
        queue.select(1); // A manually enqueued current track has no source rank.
        let history_and_current = queue.items[..2].to_vec();
        queue.restore_order_after_current();
        assert_eq!(queue.items[..2], history_and_current);
        assert_eq!(queue.items[3..14], canonical[1..]);
        assert_eq!(
            entry_ids(&queue.items)
                .into_iter()
                .collect::<HashSet<_>>()
                .len(),
            16
        );
    }

    #[test]
    fn removals_are_not_resurrected_and_drag_placements_survive_toggles() {
        let mut queue = QueueStateDto::default();
        queue.replace(
            (0..20).map(|index| item(&index.to_string())).collect(),
            0,
            source(),
        );
        let removed = queue.items[8].entry_id.clone();
        let moved = queue.items[6].entry_id.clone();
        let active = queue.current().unwrap();
        queue.shuffle_after_current_with_seed(42);
        queue.remove_entry(&removed).unwrap();
        queue.move_entry(&moved, None).unwrap();
        let fixed_index = queue.items.len() - 1;
        queue.restore_order_after_current();
        assert_eq!(queue.items[fixed_index].entry_id, moved);
        assert_eq!(queue.current(), Some(active));
        queue.shuffle_after_current_with_seed(314);
        assert_eq!(queue.items[fixed_index].entry_id, moved);
        assert!(queue.items.iter().all(|entry| entry.entry_id != removed));
        assert!(!queue.source_ranks.contains_key(&removed));
        assert!(!queue.source_ranks.contains_key(&moved));
    }

    #[test]
    fn reversible_source_order_is_shared_by_albums_artists_mixes_and_radio_pages() {
        for kind in ["playlist", "album", "artist", "mix", "radio"] {
            let mut queue = QueueStateDto::default();
            let mut context = source();
            context.kind = kind.into();
            queue.replace(
                (0..10).map(|index| item(&index.to_string())).collect(),
                2,
                context,
            );
            queue.merge_radio(vec![item("radio-a"), item("radio-b")]);
            queue.enqueue(vec![item("manual")], true);
            let canonical = queue.items.clone();
            queue.shuffle_after_current_with_seed(42);
            queue.restore_order_after_current();
            assert_eq!(queue.items, canonical, "source kind: {kind}");
            assert_eq!(queue.items[3].video_id, "manual");
            assert_eq!(queue.items.last().unwrap().video_id, "radio-b");
        }
    }

    #[test]
    fn playlist_snapshots_expand_by_100_and_play_every_occurrence_without_gaps() {
        let mut queue = QueueStateDto::default();
        let items = (0..2000)
            .map(|index| item(&format!("song-{index}")))
            .collect();
        queue.replace(items, 0, source());
        assert_eq!(queue.items.len(), 2000);
        let mut visible = queue.snapshot().items.len();
        assert_eq!(visible, 100);
        let ids = queue
            .items
            .iter()
            .map(|entry| entry.entry_id.clone())
            .collect::<HashSet<_>>();
        assert_eq!(ids.len(), 2000);
        for index in 1..2000 {
            assert_eq!(
                queue.next_or_first(false).unwrap().video_id,
                format!("song-{index}")
            );
            assert_eq!(queue.next().unwrap().video_id, format!("song-{index}"));
            assert!(queue.current_index.unwrap() < queue.visible_len);
            if queue.visible_len != visible {
                assert_eq!(queue.visible_len, visible + 100);
                visible = queue.visible_len;
            }
        }
        assert_eq!(visible, 2000);
        assert!(queue.next().is_none());
        assert!(queue.next_or_first(false).is_none());
        assert_eq!(queue.next_or_first(true).unwrap().video_id, "song-0");
        assert_eq!(queue.previous(0.0).unwrap().video_id, "song-1998");
    }

    #[test]
    fn shuffle_spans_the_complete_playlist_and_batches_preserve_that_order() {
        let mut queue = QueueStateDto::default();
        queue.replace(
            (0..2000).map(|index| item(&format!("{index}"))).collect(),
            0,
            source(),
        );
        let current = queue.current().unwrap();
        let mut expected = queue.clone();
        expected.source.as_mut().unwrap().kind = "album".into();
        assert!(expected.shuffle_after_current_with_seed(42));
        assert!(queue.shuffle_after_current_with_seed(42));
        assert_eq!(queue.current(), Some(current));
        assert_eq!(queue.snapshot().items.len(), 100);
        assert!(queue.snapshot().items.iter().any(|entry| entry
            .video_id
            .parse::<usize>()
            .unwrap()
            >= 100));
        for entry in expected.items.iter().skip(1) {
            assert_eq!(queue.next().unwrap(), *entry);
        }
        assert_eq!(queue.snapshot().items, expected.items);
        assert!(queue.next().is_none());
    }

    #[test]
    fn batches_preserve_history_duplicates_and_discard_the_old_playlist_on_replacement() {
        let mut queue = QueueStateDto::default();
        queue.replace((0..350).map(|_| item("same")).collect(), 150, source());
        let snapshot = queue.snapshot();
        assert_eq!(snapshot.items.len(), 250);
        assert_eq!(snapshot.current_index, Some(150));
        assert_eq!(
            snapshot
                .items
                .iter()
                .map(|entry| &entry.entry_id)
                .collect::<HashSet<_>>()
                .len(),
            250
        );
        assert_eq!(
            queue.previous(0.0).unwrap().entry_id,
            snapshot.items[149].entry_id
        );
        queue.replace(vec![item("new")], 0, source());
        assert_eq!(queue.snapshot().items.len(), 1);
        assert_eq!(queue.current().unwrap().video_id, "new");
        assert!(queue.next().is_none());
    }

    #[test]
    fn explicit_queue_edits_keep_their_visibility_and_occurrence_identity() {
        let mut queue = QueueStateDto::default();
        queue.replace(
            (0..250).map(|index| item(&format!("{index}"))).collect(),
            0,
            source(),
        );
        let active = queue.current().unwrap();
        queue.enqueue(vec![item("manual-next")], true);
        assert_eq!(queue.snapshot().items.len(), 101);
        assert_eq!(queue.next().unwrap().video_id, "manual-next");
        let manual_id = queue.current().unwrap().entry_id;
        queue.remove_entry(&active.entry_id).unwrap();
        assert_eq!(queue.current().unwrap().entry_id, manual_id);
        queue.enqueue(vec![item("manual-end")], false);
        assert_eq!(
            queue.snapshot().items.last().unwrap().video_id,
            "manual-end"
        );
        assert_eq!(queue.current().unwrap().entry_id, manual_id);
        let moved = queue.items[2].entry_id.clone();
        queue.move_entry(&moved, None).unwrap();
        assert_eq!(queue.snapshot().items.last().unwrap().entry_id, moved);
        assert_eq!(queue.current().unwrap().entry_id, manual_id);
    }

    #[test]
    fn duplicates_keep_occurrence_identity_and_playlist_order() {
        let mut queue = queue();
        assert_eq!(queue.items[0].video_id, queue.items[1].video_id);
        assert_ne!(queue.items[0].entry_id, queue.items[1].entry_id);
        assert_eq!(queue.current_index, Some(1));
        assert_eq!(queue.next().unwrap().video_id, "last");
    }

    #[test]
    fn previous_restarts_after_three_seconds_and_steps_at_or_below() {
        let mut queue = queue();
        let current = queue.current().unwrap().entry_id;
        assert_eq!(queue.previous(3.01).unwrap().entry_id, current);
        assert_eq!(queue.current_index, Some(1));
        assert_eq!(queue.previous(3.0).unwrap().video_id, "same");
        assert_eq!(queue.current_index, Some(0));
        let first = queue.current().unwrap().entry_id;
        let revision = queue.revision;
        assert_eq!(queue.previous(0.0).unwrap().entry_id, first);
        assert_eq!(queue.current_index, Some(0));
        assert_eq!(queue.revision, revision);
    }

    #[test]
    fn eof_and_invalid_selection_do_not_wrap_or_mutate() {
        let mut queue = queue();
        queue.select(2);
        let revision = queue.revision;
        assert!(queue.next().is_none());
        assert_eq!(queue.current_index, Some(2));
        assert_eq!(queue.revision, revision);
        assert!(queue.select(99).is_none());
    }

    #[test]
    fn shuffle_keeps_passed_entries_and_current_occurrence_in_place() {
        let mut queue = QueueStateDto::default();
        queue.replace(
            vec![
                item("passed"),
                item("current"),
                item("duplicate"),
                item("duplicate"),
                item("last"),
            ],
            1,
            source(),
        );
        let prefix = queue.items[..1].to_vec();
        let current = queue.current().unwrap();
        let suffix_before = queue.items[2..]
            .iter()
            .map(|entry| entry.entry_id.clone())
            .collect::<Vec<_>>();
        let mut suffix_ids = queue.items[2..]
            .iter()
            .map(|entry| entry.entry_id.clone())
            .collect::<Vec<_>>();
        suffix_ids.sort();
        let old_revision = queue.revision;

        assert!(queue.shuffle_after_current_with_seed(42));

        assert_eq!(queue.items[..1], prefix);
        assert_eq!(queue.current_index, Some(1));
        assert_eq!(queue.current().unwrap().entry_id, current.entry_id);
        let mut new_suffix_ids = queue.items[2..]
            .iter()
            .map(|entry| entry.entry_id.clone())
            .collect::<Vec<_>>();
        new_suffix_ids.sort();
        assert_eq!(new_suffix_ids, suffix_ids);
        assert_eq!(
            queue.items[2..]
                .iter()
                .map(|entry| entry.entry_id.clone())
                .collect::<Vec<_>>(),
            vec![
                suffix_before[0].clone(),
                suffix_before[2].clone(),
                suffix_before[1].clone()
            ],
        );
        assert_eq!(queue.revision, old_revision + 1);
    }

    #[test]
    fn repeat_wrap_target_is_first_occurrence_only_when_enabled() {
        let mut queue = queue();
        queue.select(2);
        let first = queue.items[0].entry_id.clone();
        assert!(queue.next_or_first(false).is_none());
        assert_eq!(queue.next_or_first(true).unwrap().entry_id, first);
        assert_eq!(queue.current_index, Some(2));
    }

    #[test]
    fn enqueue_next_and_end_preserve_current_and_reassign_client_ids() {
        let mut queue = queue();
        let current = queue.current().unwrap().entry_id;
        let mut client_item = item("same");
        client_item.entry_id = queue.items[0].entry_id.clone();
        queue.enqueue(vec![client_item.clone()], true);
        assert_eq!(queue.current().unwrap().entry_id, current);
        assert_eq!(queue.items[2].video_id, "same");
        assert_ne!(queue.items[2].entry_id, queue.items[0].entry_id);
        queue.enqueue(vec![client_item], false);
        assert_eq!(queue.items.last().unwrap().video_id, "same");
        assert_eq!(queue.items[0].video_id, "same");
        assert_eq!(queue.current_index, Some(1));
    }

    #[test]
    fn removing_by_occurrence_preserves_current_and_rejects_itself() {
        let mut queue = queue();
        let current = queue.current().unwrap().entry_id;
        assert_eq!(
            queue.remove_entry(&current),
            Err(QueueRemoveError::CurrentEntry)
        );
        let before_current = queue.items[0].entry_id.clone();
        assert_eq!(queue.remove_entry(&before_current), Ok(true));
        assert_eq!(queue.current_index, Some(0));
        assert_eq!(queue.current().unwrap().entry_id, current);
        assert_eq!(queue.remove_entry("missing"), Ok(false));
    }

    #[test]
    fn dismissing_active_duplicate_selects_successor_without_touching_other_occurrences() {
        let mut queue = QueueStateDto::default();
        queue.replace(vec![item("same"), item("same"), item("same")], 1, source());
        let active_id = queue.current().unwrap().entry_id;
        let first_id = queue.items[0].entry_id.clone();
        let (was_current, next) = queue.dismiss_entry(&active_id).unwrap();
        assert!(was_current);
        assert_eq!(next.unwrap().entry_id, queue.items[1].entry_id);
        assert_eq!(queue.items.len(), 2);
        assert_eq!(queue.items[0].entry_id, first_id);
        assert_eq!(queue.items[0].video_id, queue.items[1].video_id);
        assert_eq!(queue.current_index, Some(1));
    }

    #[test]
    fn dismissing_last_active_entry_wraps_to_first_remaining_or_leaves_empty_queue() {
        let mut queue = queue();
        queue.select(2);
        let last = queue.current().unwrap().entry_id;
        let (was_current, next) = queue.dismiss_entry(&last).unwrap();
        assert!(was_current);
        assert_eq!(next.unwrap().entry_id, queue.items[0].entry_id);
        assert_eq!(queue.current_index, Some(0));

        let first = queue.current().unwrap().entry_id;
        let (_, only) = queue.dismiss_entry(&first).unwrap();
        assert_eq!(only.unwrap().entry_id, queue.items[0].entry_id);
        let only = queue.current().unwrap().entry_id;
        let (was_current, next) = queue.dismiss_entry(&only).unwrap();
        assert!(was_current);
        assert!(next.is_none());
        assert!(queue.items.is_empty());
        assert_eq!(queue.current_index, None);
    }

    #[test]
    fn dismissing_a_nonactive_occurrence_preserves_the_playing_entry() {
        let mut queue = queue();
        let active = queue.current().unwrap().entry_id;
        let before = queue.items[0].entry_id.clone();
        let (was_current, selected) = queue.dismiss_entry(&before).unwrap();
        assert!(!was_current);
        assert_eq!(selected.unwrap().entry_id, active);
        assert_eq!(queue.current_index, Some(0));
        let unchanged = queue.clone();
        assert!(queue.dismiss_entry("stale").is_none());
        assert_eq!(queue, unchanged);
    }

    #[test]
    fn selecting_by_entry_id_survives_removing_an_earlier_occurrence() {
        let mut queue = queue();
        let intended = queue.items[2].entry_id.clone();
        let before_current = queue.items[0].entry_id.clone();
        queue.remove_entry(&before_current).unwrap();
        let selected = queue.select_entry(&intended).unwrap();
        assert_eq!(selected.entry_id, intended);
        assert_eq!(queue.current_index, Some(1));
    }

    #[test]
    fn move_duplicate_occurrences_preserves_active_identity_and_source() {
        let mut queue = queue();
        let first = queue.items[0].entry_id.clone();
        let active = queue.current().unwrap().entry_id;
        let last = queue.items[2].entry_id.clone();
        let source = queue.source.clone();
        let revision = queue.revision;
        assert_eq!(queue.move_entry(&first, None), Ok(true));
        assert_eq!(queue.current_index, Some(0));
        assert_eq!(queue.current().unwrap().entry_id, active);
        assert_eq!(queue.items[2].entry_id, first);
        assert_eq!(queue.source, source);
        assert_eq!(queue.revision, revision + 1);
        assert_eq!(queue.move_entry(&active, None), Ok(true));
        assert_eq!(queue.current_index, Some(2));
        assert_eq!(queue.current().unwrap().entry_id, active);
        assert_eq!(queue.move_entry(&active, Some(&last)), Ok(true));
        assert_eq!(queue.current_index, Some(0));
        assert_eq!(queue.current().unwrap().entry_id, active);
        assert_eq!(queue.items[1].entry_id, last);
    }

    #[test]
    fn move_no_ops_and_stale_ids_never_mutate_queue() {
        let mut queue = queue();
        let first = queue.items[0].entry_id.clone();
        let second = queue.items[1].entry_id.clone();
        let last = queue.items[2].entry_id.clone();
        let original = queue.clone();
        assert_eq!(queue.move_entry(&first, Some(&first)), Ok(false));
        assert_eq!(queue.move_entry(&first, Some(&second)), Ok(false));
        assert_eq!(queue.move_entry(&last, None), Ok(false));
        assert_eq!(
            queue.move_entry("stale", Some(&first)),
            Err(QueueMoveError::EntryNotFound)
        );
        assert_eq!(
            queue.move_entry(&first, Some("stale")),
            Err(QueueMoveError::TargetNotFound)
        );
        assert_eq!(queue, original);
        queue.replace(vec![item("same"), item("new")], 0, source());
        let replaced = queue.clone();
        assert_eq!(
            queue.move_entry(&first, None),
            Err(QueueMoveError::EntryNotFound)
        );
        assert_eq!(queue, replaced);
    }

    #[test]
    fn queue_replacement_invalidates_old_occurrence_ids_even_if_the_client_reuses_them() {
        let mut queue = queue();
        let stale_id = queue.items[0].entry_id.clone();
        queue.replace(vec![item("replacement")], 0, source());
        assert_ne!(queue.items[0].entry_id, stale_id);
        assert!(queue.select_entry(&stale_id).is_none());
    }

    #[test]
    fn radio_merge_deduplicates_recommendations_but_not_manual_occurrences() {
        let mut queue = queue();
        queue.enqueue(vec![item("same"), item("manual")], false);
        let cursor = queue.merge_radio(vec![item("last"), item("radio"), item("radio")]);
        assert_eq!(cursor.as_deref(), Some("radio"));
        assert_eq!(
            queue
                .items
                .iter()
                .filter(|entry| entry.video_id == "same")
                .count(),
            3
        );
        assert_eq!(
            queue
                .items
                .iter()
                .filter(|entry| entry.video_id == "radio")
                .count(),
            1
        );
    }

    #[test]
    fn seed_duplicate_enriches_all_existing_occurrences_without_replacing_them() {
        let mut queue = queue();
        let original_ids = queue
            .items
            .iter()
            .map(|entry| entry.entry_id.clone())
            .collect::<Vec<_>>();
        let original_revision = queue.revision;
        let mut radio_seed = item("same");
        radio_seed.artists = "Artist A & Artist B".into();
        radio_seed.artist_id = Some("UCartistA".into());
        radio_seed.album = Some("Album".into());
        radio_seed.album_id = Some("MPREalbum".into());
        radio_seed.artist_runs = vec![
            HomeArtistRunDto {
                text: "Artist A".into(),
                id: Some("UCartistA".into()),
            },
            HomeArtistRunDto {
                text: "Artist B".into(),
                id: Some("UCartistB".into()),
            },
        ];

        assert_eq!(queue.merge_radio(vec![radio_seed]), None);
        assert_eq!(queue.revision, original_revision + 1);
        assert_eq!(
            queue
                .items
                .iter()
                .map(|entry| entry.entry_id.clone())
                .collect::<Vec<_>>(),
            original_ids
        );
        assert_eq!(queue.current_index, Some(1));
        for occurrence in queue.items.iter().filter(|entry| entry.video_id == "same") {
            assert_eq!(occurrence.album.as_deref(), Some("Album"));
            assert_eq!(occurrence.artist_runs.len(), 2);
        }
    }

    #[test]
    fn replaced_queue_resets_optional_radio_state() {
        let mut queue = queue();
        queue.begin_radio();
        assert!(queue.radio.as_ref().unwrap().loading);
        queue.replace(vec![item("new")], 0, source());
        assert!(queue.radio.is_none());
    }

    #[test]
    fn queue_owner_epoch_invalidates_stale_radio_results() {
        let old_epoch = 41;
        let new_epoch = next_owner_epoch(old_epoch);
        assert_ne!(old_epoch, new_epoch);
        assert_eq!(next_owner_epoch(u64::MAX), 0);
    }

    #[test]
    fn older_queue_snapshots_deserialize_without_radio_or_metadata() {
        let queue: QueueStateDto = serde_json::from_str(
            r#"{"items":[{"entryId":"entry-1","videoId":"v1","title":"Track","artists":"Artist","thumbnail":null,"duration":null}],"currentIndex":0,"source":null,"revision":4}"#,
        ).unwrap();
        assert!(queue.radio.is_none());
        assert!(queue.items[0].artist_id.is_none());
        assert!(queue.items[0].album_id.is_none());
        assert!(queue.items[0].album.is_none());
    }
}
