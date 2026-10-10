use crate::HomeArtistRunDto;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

static NEXT_ENTRY_ID: AtomicU64 = AtomicU64::new(1);
static SHUFFLE_COUNTER: AtomicU64 = AtomicU64::new(1);
const PLAYLIST_BATCH_SIZE: usize = 100;
const PLAYLIST_REFILL_THRESHOLD: usize = 10;

/// Responsive provider subtitles may contain counters in an album/credit slot.
/// Require a numeric count, so genuine names such as Views, Plays or The 1975 survive.
pub(crate) fn provider_statistic(value: &str) -> bool {
    let value = value.trim().to_lowercase();
    [
        "plays",
        "play",
        "views",
        "view",
        "streams",
        "stream",
        "listeners",
        "listener",
        "subscribers",
        "subscriber",
        "reproducciones",
        "visualizaciones",
        "vistas",
        "oyentes",
        "suscriptores",
    ]
    .iter()
    .any(|unit| {
        let Some(index) = value.find(unit) else {
            return false;
        };
        if value[index + unit.len()..]
            .chars()
            .next()
            .is_some_and(|ch| !ch.is_whitespace())
        {
            return false;
        }
        let count = value[..index]
            .chars()
            .filter(|ch| !ch.is_whitespace())
            .collect::<String>();
        let number = count.trim_end_matches(|ch: char| ch.is_alphabetic());
        let scale = &count[number.len()..];
        number.chars().any(|ch| ch.is_ascii_digit())
            && number
                .chars()
                .all(|ch| ch.is_ascii_digit() || matches!(ch, '.' | ','))
            && matches!(
                scale,
                "" | "k"
                    | "m"
                    | "b"
                    | "mil"
                    | "millon"
                    | "millón"
                    | "millones"
                    | "million"
                    | "millions"
                    | "billion"
                    | "billions"
            )
    })
}

fn provider_duration(value: &str) -> bool {
    let parts = value.split(':').collect::<Vec<_>>();
    (2..=3).contains(&parts.len())
        && parts.iter().enumerate().all(|(index, part)| {
            !part.is_empty()
                && part.chars().all(|ch| ch.is_ascii_digit())
                && (index == 0 || part.len() == 2)
        })
}

pub(crate) fn metadata_album(value: &Option<String>, album_id: &Option<String>) -> Option<String> {
    value
        .as_ref()
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .filter(|value| {
            album_id.as_ref().is_some_and(|id| !id.trim().is_empty())
                || !(provider_statistic(value) || provider_duration(value))
        })
        .map(str::to_owned)
}

pub(crate) fn metadata_credit(value: &str) -> String {
    value
        .split(['•', '·'])
        .map(str::trim)
        .filter(|part| {
            !part.is_empty()
                && !provider_statistic(part)
                && !provider_duration(part)
                && !matches!(
                    part.to_lowercase().as_str(),
                    "song"
                        | "canción"
                        | "cancion"
                        | "video"
                        | "vídeo"
                        | "album"
                        | "álbum"
                        | "single"
                        | "sencillo"
                        | "ep"
                        | "playlist"
                        | "lista"
                        | "mix"
                )
        })
        .collect::<Vec<_>>()
        .join(" • ")
}

pub(crate) fn metadata_artist_runs(runs: &[HomeArtistRunDto]) -> Vec<HomeArtistRunDto> {
    let descriptor = |value: &str| !value.trim().is_empty() && metadata_credit(value).is_empty();
    let linked = |run: &HomeArtistRunDto| run.id.as_ref().is_some_and(|id| !id.trim().is_empty());
    let mut groups = vec![Vec::new()];
    for (index, run) in runs.iter().enumerate() {
        if matches!(run.text.trim(), "•" | "·") {
            groups.push(Vec::new());
        } else {
            groups.last_mut().unwrap().push(index);
        }
    }
    let mut rejected = HashSet::new();
    for group in groups {
        if !group.iter().any(|&index| linked(&runs[index]))
            && descriptor(
                &group
                    .iter()
                    .map(|&index| runs[index].text.as_str())
                    .collect::<String>(),
            )
        {
            rejected.extend(group.iter().copied());
        }
        for index in group {
            if !linked(&runs[index]) && descriptor(&runs[index].text) {
                rejected.insert(index);
            }
        }
    }
    let mut retained = runs
        .iter()
        .enumerate()
        .filter(|(index, _)| !rejected.contains(index))
        .map(|(_, run)| run.clone())
        .collect::<Vec<_>>();
    let punctuation = |run: &HomeArtistRunDto| {
        !linked(run)
            && run
                .text
                .chars()
                .all(|ch| ch.is_whitespace() || matches!(ch, '•' | '·' | ',' | ';' | '&'))
    };
    while retained.first().is_some_and(&punctuation) {
        retained.remove(0);
    }
    while retained.last().is_some_and(&punctuation) {
        retained.pop();
    }
    retained
}

pub(crate) fn metadata_label_matches(left: &str, right: &str) -> bool {
    left.trim().to_lowercase() == right.trim().to_lowercase()
}

pub(crate) fn metadata_credit_with_runs(value: &str, runs: &[HomeArtistRunDto]) -> String {
    let cleaned = metadata_credit(value);
    if cleaned == value.trim() && !cleaned.is_empty()
        || !runs
            .iter()
            .any(|run| run.id.as_ref().is_some_and(|id| !id.trim().is_empty()))
    {
        return cleaned;
    }
    // Linked names are semantic credits even when an artist is named Song/Views.
    // Unlinked fragments can split a counter across runs, so inspect whole groups.
    let mut groups = vec![(String::new(), false)];
    let mut previous_linked = false;
    for run in runs {
        let linked = run.id.as_ref().is_some_and(|id| !id.trim().is_empty());
        for (index, part) in run.text.split(['•', '·']).enumerate() {
            if index > 0 {
                groups.push((String::new(), false));
                previous_linked = false;
            }
            let group = groups.last_mut().unwrap();
            if linked
                && previous_linked
                && group.0.ends_with(char::is_alphanumeric)
                && part.starts_with(char::is_alphanumeric)
            {
                group.0.push_str(", ");
            }
            group.0.push_str(part);
            group.1 |= linked && !part.trim().is_empty();
            previous_linked = linked;
        }
    }
    groups
        .into_iter()
        .map(|(text, linked)| {
            if linked {
                text.trim().to_owned()
            } else {
                metadata_credit(&text)
            }
        })
        .filter(|text| !text.is_empty())
        .collect::<Vec<_>>()
        .join(" • ")
}

/// Persist only public image locations. A signed image cannot be recovered by
/// removing its credential query, so discard it from disk while retaining RAM.
pub(crate) fn durable_thumbnail(value: &Option<String>) -> Option<String> {
    let value = value.as_ref()?;
    let mut url = reqwest::Url::parse(value).ok()?;
    if !matches!(url.scheme(), "https" | "http")
        || !url.username().is_empty()
        || url.password().is_some()
        || url
            .host_str()
            .is_some_and(|host| host == "googlevideo.com" || host.ends_with(".googlevideo.com"))
        || url.path().contains("videoplayback")
        || url.query_pairs().any(|(key, _)| {
            let key = key.to_ascii_lowercase();
            matches!(
                key.as_str(),
                "expire"
                    | "expires"
                    | "sig"
                    | "lsig"
                    | "s"
                    | "key"
                    | "policy"
                    | "credential"
                    | "rs"
                    | "sqp"
                    | "apikey"
                    | "api_key"
                    | "key-pair-id"
                    | "jwt"
                    | "session"
                    | "sid"
            ) || key.contains("token")
                || key.contains("sign")
                || key.contains("auth")
                || key.starts_with("x-amz-")
                || key.starts_with("x-goog-")
        })
    {
        return None;
    }
    url.set_fragment(None);
    Some(url.into())
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueueEntryDto {
    #[serde(default)]
    pub is_upload: bool,
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
        let mut entry = Self {
            is_upload: false,
            entry_id: new_entry_id(),
            video_id,
            title,
            artists,
            thumbnail,
            duration,
            artist_id,
            album_id,
            album,
            artist_runs,
        };
        entry.normalize_metadata();
        entry
    }

    pub(crate) fn normalize_metadata(&mut self) -> bool {
        let album = metadata_album(&self.album, &self.album_id);
        let runs = metadata_artist_runs(&self.artist_runs);
        let artists = metadata_credit_with_runs(&self.artists, &runs);
        let changed = album != self.album || artists != self.artists || runs != self.artist_runs;
        self.album = album;
        self.artists = artists;
        self.artist_runs = runs;
        changed
    }

    fn enrich_missing_metadata(&mut self, source: &Self) -> bool {
        let mut source = source.clone();
        source.normalize_metadata();
        let mut changed = self.normalize_metadata();
        if source.is_upload && !self.is_upload {
            self.is_upload = true;
            changed = true;
        }
        if self.artists.is_empty()
            && !source.artists.is_empty()
            && (self.artist_id.is_none() || self.artist_id == source.artist_id)
        {
            self.artists = source.artists.clone();
            changed = true;
        }
        if self.artist_id.is_none()
            && source.artist_id.is_some()
            && (self.artists.is_empty() || metadata_label_matches(&self.artists, &source.artists))
        {
            self.artist_id = source.artist_id.clone();
            changed = true;
        }
        if self.album_id.is_none()
            && source.album_id.is_some()
            && self.album.as_ref().is_none_or(|album| {
                source
                    .album
                    .as_ref()
                    .is_some_and(|label| metadata_label_matches(album, label))
            })
        {
            self.album_id = source.album_id.clone();
            changed = true;
        }
        if self.album.is_none()
            && source.album.is_some()
            && (self.album_id.is_none() || self.album_id == source.album_id)
        {
            self.album = source.album.clone();
            changed = true;
        }
        if self.artist_runs.is_empty()
            && !source.artist_runs.is_empty()
            && metadata_label_matches(&self.artists, &source.artists)
            && (self.artist_id.is_none() || self.artist_id == source.artist_id)
        {
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
    // insertions and drag edits have anchors instead of ranks. Shuffle keeps their
    // pending slots; restoring the original order projects them beside their anchors.
    #[serde(skip)]
    source_ranks: HashMap<String, usize>,
    #[serde(skip)]
    next_source_rank: usize,
    #[serde(skip)]
    explicit_placements: HashMap<String, QueuePlacement>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
enum QueuePlacement {
    After(String),
    Before(String),
    End,
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
            explicit_placements: HashMap::new(),
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
            explicit_placements: HashMap::new(),
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
                item.normalize_metadata();
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
        self.explicit_placements.clear();
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
        self.reorder_pending_source(seed)
    }

    /// Restores the complete source, above and below the playing occurrence. Explicit
    /// edits follow occurrence anchors, and the playing identity determines its new index.
    pub fn restore_original_order(&mut self) -> bool {
        if self.items.is_empty() {
            return false;
        }
        let active_id = self.current().map(|entry| entry.entry_id);
        let old_ids = self
            .items
            .iter()
            .map(|entry| entry.entry_id.clone())
            .collect::<Vec<_>>();
        let visible_explicit = self
            .items
            .iter()
            .take(self.visible_len)
            .filter(|entry| self.explicit_placements.contains_key(&entry.entry_id))
            .map(|entry| entry.entry_id.clone())
            .collect::<HashSet<_>>();
        let mut sources = self
            .items
            .iter()
            .filter(|entry| self.source_ranks.contains_key(&entry.entry_id))
            .map(|entry| entry.entry_id.clone())
            .collect::<Vec<_>>();
        sources.sort_by_key(|id| self.source_ranks[id]);
        let known_ids = old_ids.iter().cloned().collect::<HashSet<_>>();
        let mut before = HashMap::<String, Vec<String>>::new();
        let mut after = HashMap::<String, Vec<String>>::new();
        let mut end = Vec::new();
        for id in &old_ids {
            if self.source_ranks.contains_key(id) {
                continue;
            }
            match self.explicit_placements.get(id) {
                Some(QueuePlacement::Before(anchor)) if known_ids.contains(anchor) => {
                    before.entry(anchor.clone()).or_default().push(id.clone());
                }
                Some(QueuePlacement::After(anchor)) if known_ids.contains(anchor) => {
                    after.entry(anchor.clone()).or_default().push(id.clone());
                }
                _ => end.push(id.clone()),
            }
        }
        let mut ordered = Vec::with_capacity(self.items.len());
        let mut emitted = HashSet::new();
        for root in sources.iter().chain(end.iter()) {
            project_queue_entry(root, &before, &after, &mut emitted, &mut ordered);
        }
        // Unexpected orphan/cyclic metadata cannot loop or discard an occurrence:
        // preserve the existing relative order of any disconnected component.
        for id in &old_ids {
            if emitted.insert(id.clone()) {
                ordered.push(id.clone());
            }
        }
        if ordered == old_ids {
            return false;
        }
        let mut entries = std::mem::take(&mut self.items)
            .into_iter()
            .map(|entry| (entry.entry_id.clone(), entry))
            .collect::<HashMap<_, _>>();
        self.items = ordered
            .into_iter()
            .filter_map(|id| entries.remove(&id))
            .collect();
        self.current_index =
            active_id.and_then(|id| self.items.iter().position(|entry| entry.entry_id == id));
        if let Some(index) = self.current_index {
            self.visible_len = self
                .visible_len
                .max(index.saturating_add(PLAYLIST_BATCH_SIZE))
                .min(self.items.len());
        }
        if let Some(last) = self
            .items
            .iter()
            .rposition(|entry| visible_explicit.contains(&entry.entry_id))
        {
            self.visible_len = self.visible_len.max(last + 1);
        }
        self.revision += 1;
        true
    }

    fn reorder_pending_source(&mut self, seed: u64) -> bool {
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
            entry.normalize_metadata();
            entry.entry_id = new_unique_entry_id(&mut known_ids);
        }
        let insert_at = if at_next {
            self.current_index
                .map_or(self.items.len(), |index| index + 1)
        } else {
            self.items.len()
        };
        let added_len = entries.len();
        let mut anchor = if at_next {
            self.current().map(|entry| entry.entry_id)
        } else {
            None
        };
        for entry in &entries {
            let placement = anchor
                .as_ref()
                .map_or(QueuePlacement::End, |id| QueuePlacement::After(id.clone()));
            self.explicit_placements
                .insert(entry.entry_id.clone(), placement);
            // Each call to Play Next preserves its own internal order. Repeated calls
            // share the current anchor; projection preserves their latest queue order.
            anchor = Some(entry.entry_id.clone());
        }
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
        self.detach_dependents(entry_id);
        self.items.remove(index);
        self.source_ranks.remove(entry_id);
        self.explicit_placements.remove(entry_id);
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
        self.detach_dependents(entry_id);
        self.items.remove(index);
        self.source_ranks.remove(entry_id);
        self.explicit_placements.remove(entry_id);
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
        if before_entry_id.is_some_and(|target| self.anchor_chain_reaches(target, entry_id)) {
            // Moving an anchor before its own descendant would introduce a cycle.
            // Dependents retain the former placement before recording the drag.
            self.detach_dependents(entry_id);
        }
        let active_id = self.current().map(|entry| entry.entry_id);
        let entry = self.items.remove(from);
        let target = if from < before { before - 1 } else { before };
        self.items.insert(target, entry);
        // A drag is an explicit placement, just like an enqueued occurrence. Future
        // shuffle toggles must not undo it or confuse it with the source's own order.
        self.source_ranks.remove(entry_id);
        self.explicit_placements.insert(
            entry_id.to_owned(),
            before_entry_id.map_or(QueuePlacement::End, |id| {
                QueuePlacement::Before(id.to_owned())
            }),
        );
        if before_entry_id.is_none() {
            self.visible_len = self.items.len();
        }
        self.current_index =
            active_id.and_then(|id| self.items.iter().position(|entry| entry.entry_id == id));
        self.revision += 1;
        Ok(true)
    }

    fn anchor_chain_reaches(&self, entry_id: &str, target: &str) -> bool {
        let mut current = entry_id;
        let mut visited = HashSet::new();
        while visited.insert(current) {
            if current == target {
                return true;
            }
            current = match self.explicit_placements.get(current) {
                Some(QueuePlacement::After(anchor) | QueuePlacement::Before(anchor)) => anchor,
                _ => return false,
            };
        }
        false
    }

    fn detach_dependents(&mut self, entry_id: &str) {
        let inherited = self.explicit_placements.get(entry_id).cloned();
        let rank = self.source_ranks.get(entry_id).copied();
        let predecessor = rank.and_then(|rank| {
            self.source_ranks
                .iter()
                .filter(|(_, value)| **value < rank)
                .max_by_key(|(_, value)| **value)
                .map(|(id, _)| id.clone())
        });
        let successor = rank.and_then(|rank| {
            self.source_ranks
                .iter()
                .filter(|(_, value)| **value > rank)
                .min_by_key(|(_, value)| **value)
                .map(|(id, _)| id.clone())
        });
        for placement in self.explicit_placements.values_mut() {
            let was_after = match placement {
                QueuePlacement::After(anchor) if anchor == entry_id => true,
                QueuePlacement::Before(anchor) if anchor == entry_id => false,
                _ => continue,
            };
            *placement = inherited.clone().unwrap_or_else(|| {
                if was_after {
                    predecessor
                        .as_ref()
                        .map(|id| QueuePlacement::After(id.clone()))
                        .or_else(|| {
                            successor
                                .as_ref()
                                .map(|id| QueuePlacement::Before(id.clone()))
                        })
                } else {
                    successor
                        .as_ref()
                        .map(|id| QueuePlacement::Before(id.clone()))
                        .or_else(|| {
                            predecessor
                                .as_ref()
                                .map(|id| QueuePlacement::After(id.clone()))
                        })
                }
                .unwrap_or(QueuePlacement::End)
            });
        }
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
    pub fn merge_radio(&mut self, mut recommendations: Vec<QueueEntryDto>) -> Option<String> {
        for entry in &mut recommendations {
            entry.normalize_metadata();
        }
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

/// Private durable envelope. These ordering maps never cross the WebView boundary.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct DurableQueue {
    queue: QueueStateDto,
    visible_len: usize,
    source_ranks: HashMap<String, usize>,
    next_source_rank: usize,
    explicit_placements: HashMap<String, QueuePlacement>,
}
impl QueueStateDto {
    pub(crate) fn durable(&self) -> DurableQueue {
        let mut queue = self.clone();
        for entry in &mut queue.items {
            entry.thumbnail = durable_thumbnail(&entry.thumbnail);
        }
        DurableQueue {
            queue,
            visible_len: self.visible_len,
            source_ranks: self.source_ranks.clone(),
            next_source_rank: self.next_source_rank,
            explicit_placements: self.explicit_placements.clone(),
        }
    }
    /// Append provider occurrences without replacing edited prefix or deduplicating songs.
    pub(crate) fn source_prefix(&self) -> Vec<String> {
        let mut entries = self
            .items
            .iter()
            .filter_map(|entry| {
                self.source_ranks
                    .get(&entry.entry_id)
                    .map(|rank| (*rank, entry.video_id.clone()))
            })
            .collect::<Vec<_>>();
        entries.sort_by_key(|(rank, _)| *rank);
        entries.into_iter().map(|(_, id)| id).collect()
    }
    pub(crate) fn filter_radio_recommendations(&mut self, video_id: &str) {
        let current = self.current().map(|entry| entry.entry_id);
        let remove = self
            .items
            .iter()
            .filter(|entry| {
                entry.video_id == video_id
                    && Some(&entry.entry_id) != current.as_ref()
                    && self.source_ranks.contains_key(&entry.entry_id)
            })
            .map(|entry| entry.entry_id.clone())
            .collect::<Vec<_>>();
        for id in remove {
            let _ = self.remove_entry(&id);
        }
    }
    pub(crate) fn append_source(&mut self, items: Vec<QueueEntryDto>, shuffled: bool) {
        let current = self.current().map(|entry| entry.entry_id);
        let mut added = Vec::new();
        for mut entry in items {
            entry.normalize_metadata();
            entry.entry_id = new_entry_id();
            self.source_ranks
                .insert(entry.entry_id.clone(), self.next_source_rank);
            self.next_source_rank += 1;
            added.push(entry);
        }
        if shuffled {
            // Preserve the shuffled prefix and every manual slot. Only new suffix
            // occurrences are randomized; canonical ranks retain reversibility.
            let mut seed = SHUFFLE_COUNTER.fetch_add(1, Ordering::Relaxed)
                ^ SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_nanos() as u64;
            for index in (1..added.len()).rev() {
                seed ^= seed << 13;
                seed ^= seed >> 7;
                seed ^= seed << 17;
                added.swap(index, seed as usize % (index + 1));
            }
            let insertion = self
                .items
                .iter()
                .enumerate()
                .skip(self.current_index.map_or(0, |index| index + 1))
                .find(|(_, entry)| {
                    matches!(
                        self.explicit_placements.get(&entry.entry_id),
                        Some(QueuePlacement::End)
                    )
                })
                .map_or(self.items.len(), |(index, _)| index);
            self.items.splice(insertion..insertion, added);
        } else {
            self.items.extend(added);
            self.restore_original_order();
        }
        if let Some(current) = current {
            self.current_index = self
                .items
                .iter()
                .position(|entry| entry.entry_id == current);
        }
        self.extend_visible_batch();
        self.revision += 1;
    }
}
impl DurableQueue {
    pub(crate) fn restore(self) -> Option<QueueStateDto> {
        let mut queue = self.queue;
        let ids = queue
            .items
            .iter()
            .map(|entry| entry.entry_id.as_str())
            .collect::<HashSet<_>>();
        if ids.len() != queue.items.len()
            || queue
                .items
                .iter()
                .any(|entry| entry.entry_id.is_empty() || entry.video_id.trim().is_empty())
            || queue
                .current_index
                .is_some_and(|index| index >= queue.items.len())
        {
            return None;
        }
        queue.visible_len = self
            .visible_len
            .max(queue.current_index.map_or(0, |index| index + 1))
            .min(queue.items.len());
        queue.source_ranks = self.source_ranks;
        queue.next_source_rank = self.next_source_rank;
        queue.explicit_placements = self.explicit_placements;
        queue.radio = None;
        for entry in &mut queue.items {
            entry.normalize_metadata();
        }
        Some(queue)
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

fn project_queue_entry(
    root: &str,
    before: &HashMap<String, Vec<String>>,
    after: &HashMap<String, Vec<String>>,
    emitted: &mut HashSet<String>,
    ordered: &mut Vec<String>,
) {
    enum Visit {
        Enter(String),
        Emit(String),
        Leave(String),
    }
    // Iterative traversal also supports long Play Next chains without recursive
    // stack growth. Child lists already follow their relative queue order.
    let mut stack = vec![Visit::Enter(root.to_owned())];
    let mut visiting = HashSet::new();
    while let Some(visit) = stack.pop() {
        match visit {
            Visit::Enter(id) => {
                if emitted.contains(&id) || !visiting.insert(id.clone()) {
                    continue;
                }
                stack.push(Visit::Leave(id.clone()));
                if let Some(children) = after.get(&id) {
                    stack.extend(children.iter().rev().cloned().map(Visit::Enter));
                }
                stack.push(Visit::Emit(id.clone()));
                if let Some(children) = before.get(&id) {
                    stack.extend(children.iter().rev().cloned().map(Visit::Enter));
                }
            }
            Visit::Emit(id) => {
                if emitted.insert(id.clone()) {
                    ordered.push(id);
                }
            }
            Visit::Leave(id) => {
                visiting.remove(&id);
            }
        }
    }
}

fn new_entry_id() -> String {
    format!(
        "queue-{}-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos(),
        NEXT_ENTRY_ID.fetch_add(1, Ordering::Relaxed)
    )
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
    #[test]
    fn responsive_statistics_are_not_album_names_without_a_destination() {
        for value in [
            "337M plays",
            "1.3 B views",
            "1\u{202f}234 reproducciones",
            "42 millones visualizaciones",
            "12 streams today",
        ] {
            assert!(super::provider_statistic(value), "{value}");
            assert_eq!(super::metadata_album(&Some(value.into()), &None), None);
        }
        for value in ["Views", "Plays", "1989", "The 1975", "100 Playstations"] {
            assert!(!super::provider_statistic(value), "{value}");
            assert_eq!(
                super::metadata_album(&Some(value.into()), &None).as_deref(),
                Some(value)
            );
        }
        assert_eq!(
            super::metadata_album(&Some("100 Plays".into()), &Some("MPRE-real".into())).as_deref(),
            Some("100 Plays")
        );
        assert_eq!(
            super::metadata_credit("Song • Artist A • Artist B • 337M plays • 3:45"),
            "Artist A • Artist B"
        );
        let linked = |text: &str| HomeArtistRunDto {
            text: text.into(),
            id: Some(format!("UC-{text}")),
        };
        let plain = |text: &str| HomeArtistRunDto {
            text: text.into(),
            id: None,
        };
        assert_eq!(
            super::metadata_credit_with_runs(
                "Song • Views • 337M plays",
                &[
                    linked("Song"),
                    plain(" • "),
                    linked("Views"),
                    plain(" • "),
                    plain("337M"),
                    plain(" plays")
                ]
            ),
            "Song • Views"
        );
        assert_eq!(
            super::metadata_credit_with_runs("", &[linked("Artist A"), linked("Artist B")]),
            "Artist A, Artist B"
        );
    }

    #[test]
    fn radio_replaces_old_metric_album_and_rejects_incoming_counters() {
        let mut queue = queue();
        for entry in &mut queue.items {
            if entry.video_id == "same" {
                entry.album = Some("337M plays".into());
                entry.artists = "Song • Artist • 337M plays".into();
            }
        }
        let ids = queue
            .items
            .iter()
            .map(|entry| entry.entry_id.clone())
            .collect::<Vec<_>>();
        let mut real = item("same");
        real.album = Some("Actual Album".into());
        real.album_id = Some("MPRE-real".into());
        queue.merge_radio(vec![real]);
        for entry in queue.items.iter().filter(|entry| entry.video_id == "same") {
            assert_eq!(entry.album.as_deref(), Some("Actual Album"));
            assert_eq!(entry.album_id.as_deref(), Some("MPRE-real"));
            assert_eq!(entry.artists, "Artist");
        }
        assert_eq!(
            queue
                .items
                .iter()
                .map(|entry| entry.entry_id.clone())
                .collect::<Vec<_>>(),
            ids
        );
        let mut incoming = item("new-counter");
        incoming.album = Some("7M views".into());
        incoming.artists = "Video • 7M views".into();
        queue.merge_radio(vec![incoming]);
        let added = queue.items.last().unwrap();
        assert_eq!(added.album, None);
        assert!(added.artists.is_empty());
    }

    #[test]
    fn durable_restore_cleans_legacy_metric_metadata_without_changing_occurrences() {
        let mut queue = queue();
        queue.items[0].album = Some("337M plays".into());
        queue.items[0].artists = "Song • Artist • 337M plays".into();
        queue.items[0].artist_runs = vec![
            HomeArtistRunDto {
                text: "Artist".into(),
                id: Some("UC-artist".into()),
            },
            HomeArtistRunDto {
                text: " • ".into(),
                id: None,
            },
            HomeArtistRunDto {
                text: "337M".into(),
                id: None,
            },
            HomeArtistRunDto {
                text: " plays".into(),
                id: None,
            },
        ];
        let id = queue.items[0].entry_id.clone();
        let restored = queue.durable().restore().unwrap();
        assert_eq!(restored.items[0].entry_id, id);
        assert_eq!(restored.items[0].album, None);
        assert_eq!(restored.items[0].artists, "Artist");
        assert_eq!(restored.items[0].artist_runs.len(), 1);
        assert_eq!(
            restored.items[0].artist_runs[0].id.as_deref(),
            Some("UC-artist")
        );
        assert_eq!(restored.current_index, queue.current_index);
    }

    #[test]
    fn enrichment_does_not_link_a_different_album_or_artist_label() {
        let mut existing = QueueEntryDto::with_metadata(
            "seed".into(),
            "Title".into(),
            "Frank Ocean feat. Guest".into(),
            None,
            None,
            None,
            None,
            Some("Blonde Deluxe".into()),
        );
        let source = QueueEntryDto::with_metadata_and_runs(
            "seed".into(),
            "Title".into(),
            "Frank Ocean".into(),
            None,
            None,
            Some("UC-frank".into()),
            Some("MPRE-blonde".into()),
            Some("Blonde".into()),
            vec![HomeArtistRunDto {
                text: "Frank Ocean".into(),
                id: Some("UC-frank".into()),
            }],
        );
        existing.enrich_missing_metadata(&source);
        assert_eq!(existing.album.as_deref(), Some("Blonde Deluxe"));
        assert_eq!(existing.album_id, None);
        assert_eq!(existing.artists, "Frank Ocean feat. Guest");
        assert_eq!(existing.artist_id, None);
        assert!(existing.artist_runs.is_empty());
        existing.album = Some(" blonde ".into());
        existing.artists = " frank ocean ".into();
        existing.enrich_missing_metadata(&source);
        assert_eq!(existing.album_id.as_deref(), Some("MPRE-blonde"));
        assert_eq!(existing.artist_id.as_deref(), Some("UC-frank"));
        assert_eq!(existing.artist_runs, source.artist_runs);
        existing.artist_runs.clear();
        existing.artist_id = Some("UC-another-artist".into());
        existing.enrich_missing_metadata(&source);
        assert_eq!(existing.artist_id.as_deref(), Some("UC-another-artist"));
        assert!(existing.artist_runs.is_empty());
        existing.artist_id = Some("UC-frank".into());
        existing.enrich_missing_metadata(&source);
        assert_eq!(existing.artist_runs, source.artist_runs);
        existing.album = None;
        existing.album_id = Some("MPRE-other".into());
        existing.enrich_missing_metadata(&source);
        assert_eq!(existing.album, None);
        existing.album_id = Some("MPRE-blonde".into());
        existing.enrich_missing_metadata(&source);
        assert_eq!(existing.album.as_deref(), Some("Blonde"));
    }
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

    fn video_ids(queue: &QueueStateDto) -> Vec<&str> {
        queue
            .items
            .iter()
            .map(|entry| entry.video_id.as_str())
            .collect()
    }

    #[test]
    fn durable_artwork_drops_signed_credentials_without_mutating_occurrences_or_ram() {
        let signed = "https://image.test/cover?%74oken=private-image-token&size=512";
        let clean = "https://image.test/public?size=512";
        let mut queue = QueueStateDto::default();
        queue.replace(
            vec![
                QueueEntryDto::new(
                    "same".into(),
                    "A".into(),
                    "Artist".into(),
                    Some(signed.into()),
                    None,
                ),
                QueueEntryDto::new(
                    "same".into(),
                    "B".into(),
                    "Artist".into(),
                    Some(clean.into()),
                    None,
                ),
            ],
            1,
            QueueSourceDto {
                kind: "playlist".into(),
                id: Some("list".into()),
                title: None,
            },
        );
        let ids = queue
            .items
            .iter()
            .map(|entry| entry.entry_id.clone())
            .collect::<Vec<_>>();
        let encoded = serde_json::to_string(&queue.durable()).unwrap();
        assert!(!encoded.contains("private-image-token"));
        let restored: DurableQueue = serde_json::from_str(&encoded).unwrap();
        let restored = restored.restore().unwrap();
        assert!(restored.items[0].thumbnail.is_none());
        assert_eq!(restored.items[1].thumbnail.as_deref(), Some(clean));
        assert_eq!(queue.items[0].thumbnail.as_deref(), Some(signed));
        assert_eq!(restored.current_index, Some(1));
        assert_eq!(
            restored
                .items
                .iter()
                .map(|entry| entry.entry_id.clone())
                .collect::<Vec<_>>(),
            ids
        );
        for query in [
            "expire=5",
            "SIGNATURE=secret",
            "auth=secret",
            "key=secret",
            "x-amz-credential=secret",
            "rs=secret&sqp=encoded",
            "api_key=secret",
        ] {
            assert!(durable_thumbnail(&Some(format!("https://image.test/a?{query}"))).is_none());
        }
        assert!(durable_thumbnail(&Some("https://user:secret@image.test/a".into())).is_none());
    }

    #[test]
    fn durable_roundtrip_keeps_duplicates_shuffle_placements_and_uploads_private() {
        let mut queue = QueueStateDto::default();
        let mut upload = item("same");
        upload.is_upload = true;
        queue.replace(vec![upload, item("same"), item("last")], 0, source());
        queue.enqueue(vec![item("manual")], true);
        let canonical = queue
            .items
            .iter()
            .map(|entry| entry.entry_id.clone())
            .collect::<Vec<_>>();
        queue.shuffle_after_current_with_seed(77);
        let active = queue.current().unwrap().entry_id;
        let persisted = serde_json::to_string(&queue.durable()).unwrap();
        let restored: DurableQueue = serde_json::from_str(&persisted).unwrap();
        let mut restored = restored.restore().unwrap();
        assert_eq!(restored.current().unwrap().entry_id, active);
        assert!(restored.current().unwrap().is_upload);
        restored.restore_original_order();
        assert_eq!(
            restored
                .items
                .iter()
                .map(|entry| entry.entry_id.clone())
                .collect::<Vec<_>>(),
            canonical
        );
        let public = serde_json::to_value(restored.snapshot()).unwrap();
        assert!(public.get("source_ranks").is_none());
        assert!(public.get("explicit_placements").is_none());
        assert_eq!(public["items"][0]["isUpload"], true);
    }
    #[test]
    fn progressive_suffix_keeps_edits_duplicates_active_and_reversible_shuffle() {
        for shuffled in [false, true] {
            let mut queue = QueueStateDto::default();
            queue.replace(vec![item("same"), item("same"), item("third")], 0, source());
            queue.enqueue(vec![item("next")], true);
            queue.enqueue(vec![item("end")], false);
            let removed = queue.items[2].entry_id.clone();
            queue.remove_entry(&removed).unwrap();
            if shuffled {
                queue.shuffle_after_current_with_seed(5);
            }
            let active = queue.current().unwrap().entry_id;
            let before = queue
                .items
                .iter()
                .map(|entry| entry.entry_id.clone())
                .collect::<Vec<_>>();
            queue.append_source(vec![item("same"), item("fourth")], shuffled);
            assert_eq!(queue.current().unwrap().entry_id, active);
            assert!(!queue.items.iter().any(|entry| entry.entry_id == removed));
            assert_eq!(
                queue
                    .items
                    .iter()
                    .filter(|entry| entry.video_id == "same")
                    .count(),
                2
            );
            assert_eq!(
                queue
                    .items
                    .iter()
                    .filter(|entry| before.contains(&entry.entry_id))
                    .map(|entry| entry.entry_id.clone())
                    .collect::<Vec<_>>(),
                before
            );
            queue.restore_original_order();
            assert_eq!(
                queue
                    .items
                    .iter()
                    .map(|entry| entry.video_id.as_str())
                    .collect::<Vec<_>>(),
                vec!["same", "next", "third", "same", "fourth", "end"]
            );
        }
    }
    #[test]
    fn disliked_radio_filter_keeps_manual_occurrences_and_active_entry() {
        let mut queue = QueueStateDto::default();
        queue.replace(vec![item("same"), item("same"), item("other")], 0, source());
        let active = queue.current().unwrap().entry_id;
        queue.enqueue(vec![item("same")], true);
        let manual = queue.items[1].entry_id.clone();
        queue.filter_radio_recommendations("same");
        assert_eq!(queue.current().unwrap().entry_id, active);
        assert!(queue.items.iter().any(|entry| entry.entry_id == manual));
        assert_eq!(
            queue
                .items
                .iter()
                .filter(|entry| entry.video_id == "same")
                .count(),
            2
        );
    }

    #[test]
    fn restoring_an_album_relocates_its_first_track_and_an_intermediate_track() {
        let titles = [
            "Say You Will",
            "Welcome To Heartbreak",
            "Heartless",
            "Amazing",
            "Love Lockdown",
            "Paranoid",
            "RoboCop",
            "Street Lights",
            "Bad News",
        ];
        let mut queue = QueueStateDto::default();
        let mut album = source();
        album.kind = "album".into();
        queue.replace(titles.iter().map(|title| item(title)).collect(), 0, album);
        let canonical = queue.items.clone();
        // Reproduce the reported layout: the album's first track is playing fifth
        // in shuffle, while an intermediate track appears above it.
        queue.items.rotate_left(4);
        let first = canonical[0].clone();
        queue.select_entry(&first.entry_id);
        assert_eq!(queue.current_index, Some(5));
        queue.restore_original_order();
        assert_eq!(queue.items, canonical);
        assert_eq!(queue.current(), Some(first));
        assert_eq!(queue.current_index, Some(0));
        assert_eq!(queue.next_or_first(false), Some(canonical[1].clone()));

        queue.items.rotate_left(5);
        let middle = canonical[7].clone();
        queue.select_entry(&middle.entry_id);
        assert_eq!(queue.current_index, Some(2));
        queue.restore_original_order();
        assert_eq!(queue.items, canonical);
        assert_eq!(queue.current(), Some(middle));
        assert_eq!(queue.current_index, Some(7));
        assert_eq!(queue.next_or_first(false), Some(canonical[8].clone()));
        assert_eq!(queue.previous(0.0), Some(canonical[6].clone()));
    }

    #[test]
    fn repeated_play_next_and_an_active_manual_track_keep_their_anchor_order() {
        let mut queue = QueueStateDto::default();
        queue.replace(
            ["a", "b", "c", "d"].into_iter().map(item).collect(),
            2,
            source(),
        );
        queue.shuffle_on_start();
        queue.enqueue(vec![item("x"), item("y")], true);
        queue.enqueue(vec![item("newest")], true);
        queue.enqueue(vec![item("end-a"), item("end-b")], false);
        let current_source = queue.current().unwrap();
        queue.restore_original_order();
        assert_eq!(
            video_ids(&queue),
            ["a", "b", "c", "newest", "x", "y", "d", "end-a", "end-b"]
        );
        assert_eq!(queue.current(), Some(current_source));
        assert_eq!(queue.current_index, Some(2));

        let active_manual = queue.items[4].clone();
        queue.select_entry(&active_manual.entry_id);
        queue.enqueue(vec![item("manual-next-a"), item("manual-next-b")], true);
        queue.items.swap(0, 1); // Include source history above the manual current.
        queue.restore_original_order();
        assert_eq!(
            video_ids(&queue),
            [
                "a",
                "b",
                "c",
                "newest",
                "x",
                "manual-next-a",
                "manual-next-b",
                "y",
                "d",
                "end-a",
                "end-b"
            ]
        );
        assert_eq!(queue.current(), Some(active_manual));
        assert_eq!(queue.current_index, Some(4));
        assert_eq!(
            queue.next_or_first(false).unwrap().video_id,
            "manual-next-a"
        );
    }

    #[test]
    fn deleting_manual_and_source_anchors_retains_their_remaining_next_entries() {
        let mut queue = QueueStateDto::default();
        queue.replace(
            ["a", "b", "c", "d"].into_iter().map(item).collect(),
            2,
            source(),
        );
        let current_source = queue.current().unwrap();
        queue.enqueue(vec![item("x"), item("y")], true);
        let removed_manual = queue.items[3].entry_id.clone();
        queue.remove_entry(&removed_manual).unwrap();
        queue.items.swap(0, 1);
        queue.restore_original_order();
        assert_eq!(video_ids(&queue), ["a", "b", "c", "y", "d"]);
        assert_eq!(queue.next_or_first(false).unwrap().video_id, "y");

        let (_, next) = queue.dismiss_entry(&current_source.entry_id).unwrap();
        let current_manual = next.unwrap();
        queue.items.swap(0, 1);
        queue.restore_original_order();
        assert_eq!(video_ids(&queue), ["a", "b", "y", "d"]);
        assert_eq!(queue.current(), Some(current_manual));
        assert_eq!(queue.current_index, Some(2));
        assert!(queue
            .items
            .iter()
            .all(|entry| entry.entry_id != removed_manual
                && entry.entry_id != current_source.entry_id));
    }

    #[test]
    fn a_drag_anchor_follows_its_target_and_survives_that_targets_removal() {
        let mut queue = QueueStateDto::default();
        queue.replace(
            ["a", "b", "c", "d", "e"].into_iter().map(item).collect(),
            0,
            source(),
        );
        let moved = queue.items[1].entry_id.clone();
        let target = queue.items[3].entry_id.clone();
        queue.move_entry(&moved, Some(&target)).unwrap();
        queue.shuffle_after_current_with_seed(42);
        queue.restore_original_order();
        assert_eq!(video_ids(&queue), ["a", "c", "b", "d", "e"]);
        queue.remove_entry(&target).unwrap();
        queue.shuffle_after_current_with_seed(19);
        queue.restore_original_order();
        assert_eq!(video_ids(&queue), ["a", "c", "b", "e"]);
        assert!(!queue
            .explicit_placements
            .values()
            .any(|placement| matches!(placement,
            QueuePlacement::Before(anchor) | QueuePlacement::After(anchor) if anchor == &target)));
    }

    #[test]
    fn dragging_a_manual_anchor_before_its_descendant_breaks_the_cycle() {
        let mut queue = QueueStateDto::default();
        queue.replace(vec![item("a"), item("b")], 0, source());
        queue.enqueue(vec![item("x"), item("y"), item("z")], true);
        let moved = queue.items[1].entry_id.clone();
        let target = queue.items[3].entry_id.clone();
        queue.move_entry(&moved, Some(&target)).unwrap();
        queue.restore_original_order();
        assert_eq!(video_ids(&queue), ["a", "y", "x", "z", "b"]);
        assert_eq!(
            entry_ids(&queue.items)
                .into_iter()
                .collect::<HashSet<_>>()
                .len(),
            5
        );
        assert!(!queue.anchor_chain_reaches(&target, &moved));
    }

    #[test]
    fn a_dragged_playing_source_keeps_its_next_entries_and_current_identity() {
        let mut queue = QueueStateDto::default();
        queue.replace(
            ["a", "b", "c", "d"].into_iter().map(item).collect(),
            2,
            source(),
        );
        let active = queue.current().unwrap();
        let target = queue.items[0].entry_id.clone();
        queue.enqueue(vec![item("next")], true);
        queue.move_entry(&active.entry_id, Some(&target)).unwrap();
        queue.restore_original_order();
        assert_eq!(video_ids(&queue), ["c", "next", "a", "b", "d"]);
        assert_eq!(queue.current(), Some(active));
        assert_eq!(queue.current_index, Some(0));
    }

    #[test]
    fn unexpected_cyclic_placements_fall_back_to_stable_order_without_losing_entries() {
        let mut queue = QueueStateDto::default();
        queue.replace(vec![item("a")], 0, source());
        queue.enqueue(vec![item("x"), item("y")], true);
        let x = queue.items[1].entry_id.clone();
        let y = queue.items[2].entry_id.clone();
        queue
            .explicit_placements
            .insert(x.clone(), QueuePlacement::After(y.clone()));
        queue
            .explicit_placements
            .insert(y, QueuePlacement::After(x));
        let original = queue.items.clone();
        assert!(!queue.restore_original_order());
        assert_eq!(queue.items, original);
    }

    #[test]
    fn restoring_large_play_next_chains_keeps_all_entries_without_recursive_stack_growth() {
        let mut queue = QueueStateDto::default();
        queue.replace(
            (0..2000)
                .map(|index| item(&format!("source-{index}")))
                .collect(),
            1234,
            source(),
        );
        let canonical = queue.items.clone();
        let active = queue.current().unwrap();
        queue.shuffle_on_start();
        queue.enqueue(
            (0..2000)
                .map(|index| item(&format!("manual-{index}")))
                .collect(),
            true,
        );
        let manual_ids = entry_ids(&queue.items[1..2001]);
        queue.restore_original_order();
        assert_eq!(queue.items.len(), 4000);
        assert_eq!(queue.current(), Some(active));
        assert_eq!(queue.current_index, Some(1234));
        assert_eq!(queue.items[..1235], canonical[..1235]);
        assert_eq!(entry_ids(&queue.items[1235..3235]), manual_ids);
        assert_eq!(queue.items[3235..], canonical[1235..]);
        assert_eq!(queue.snapshot().items.len(), 3235);
        assert_eq!(
            entry_ids(&queue.items)
                .into_iter()
                .collect::<HashSet<_>>()
                .len(),
            4000
        );
        assert_eq!(queue.next_or_first(false).unwrap().video_id, "manual-0");
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
        queue.restore_original_order();
        assert_eq!(queue.current_index, Some(1234));
        assert_eq!(queue.current().unwrap().video_id, "1234");
        assert_eq!(queue.snapshot().items.len(), 1334);
        assert_eq!(
            queue
                .items
                .iter()
                .map(|entry| entry.video_id.clone())
                .collect::<Vec<_>>(),
            (0..2000).map(|index| index.to_string()).collect::<Vec<_>>()
        );
    }

    #[test]
    fn off_restores_all_source_entries_and_on_shuffles_the_complete_pending_catalog() {
        let mut queue = QueueStateDto::default();
        queue.replace(
            (0..2000).map(|index| item(&index.to_string())).collect(),
            0,
            source(),
        );
        let canonical = queue.items.clone();
        let active = canonical[47].clone();
        queue.shuffle_after_current_with_seed(42);
        queue.select_entry(&active.entry_id);
        assert_ne!(queue.current_index, Some(47));
        assert!(queue.restore_original_order());
        assert_eq!(queue.items, canonical);
        assert_eq!(queue.current_index, Some(47));
        assert_eq!(queue.current(), Some(active));
        let fixed = queue.items[..48].to_vec();
        let pending_ids = entry_ids(&queue.items[48..])
            .into_iter()
            .collect::<HashSet<_>>();
        assert!(queue.shuffle_after_current_with_seed(314));
        assert_eq!(queue.items[..48], fixed);
        assert_ne!(queue.items[48..], canonical[48..]);
        assert_eq!(
            entry_ids(&queue.items[48..])
                .into_iter()
                .collect::<HashSet<_>>(),
            pending_ids
        );
        assert!(queue.snapshot().items[48..].iter().any(|entry| entry
            .video_id
            .parse::<usize>()
            .unwrap()
            >= 100));
        queue.restore_original_order();
        assert_eq!(queue.items, canonical);
        assert_eq!(queue.previous(0.0), Some(canonical[46].clone()));
    }

    #[test]
    fn manual_insertions_follow_the_moving_active_occurrence_and_append_stays_last() {
        let mut queue = QueueStateDto::default();
        queue.replace((0..12).map(|_| item("same")).collect(), 6, source());
        let canonical = queue.items.clone();
        queue.shuffle_on_start();
        queue.enqueue(vec![item("next-a"), item("next-b")], true);
        queue.enqueue(vec![item("end-a"), item("end-b")], false);
        let manual_entries = [1, 2, 14, 15].map(|index| queue.items[index].clone());
        let active = queue.current().unwrap();

        queue.restore_original_order();
        assert_eq!(queue.current(), Some(active));
        assert_eq!(queue.current_index, Some(6));
        assert_eq!(queue.items[..7], canonical[..7]);
        assert_eq!(queue.items[7..9], manual_entries[..2]);
        assert_eq!(queue.items[9..14], canonical[7..]);
        assert_eq!(queue.items[14..], manual_entries[2..]);
        let canonical_with_manuals = queue.items.clone();
        queue.shuffle_after_current_with_seed(67);
        assert_eq!(queue.items[7..9], manual_entries[..2]);
        assert_eq!(queue.items[14..], manual_entries[2..]);
        queue.select_entry(&manual_entries[0].entry_id);
        let active_manual = queue.current().unwrap();
        queue.restore_original_order();
        assert_eq!(queue.items, canonical_with_manuals);
        assert_eq!(queue.current(), Some(active_manual));
        assert_eq!(queue.current_index, Some(7));
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
        queue.restore_original_order();
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
            queue.restore_original_order();
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
