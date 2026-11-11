//! Best-effort Genius enrichment. None of these requests participates in audio resolution.
//! The provider endpoints are deliberately isolated here because their shapes are not versioned.

use std::collections::HashSet;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

use md5::{Digest, Md5};
use scraper::{ElementRef, Html, Selector};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::Mutex;
use unicode_normalization::{char::is_combining_mark, UnicodeNormalization};

use crate::{db::Db, SideBError};

const MATCH_TTL: i64 = 30 * 24 * 3600;
// Match rules change independently of cached song documents and manual choices.
const MATCH_RULE_VERSION: &str = "v3";
const CONTENT_TTL: i64 = 30 * 24 * 3600;
const LYRICS_TTL: i64 = 7 * 24 * 3600;
const MISS_TTL: i64 = 24 * 3600;
const API_LIMIT: usize = 4 * 1024 * 1024;
const HTML_LIMIT: usize = 2 * 1024 * 1024;

#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Record)]
pub struct GeniusTrackRecord {
    pub video_id: String,
    pub title: String,
    pub artists: String,
    pub album: Option<String>,
    pub duration_seconds: Option<u64>,
    pub is_upload: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Enum, PartialEq, Eq)]
pub enum GeniusMatchStatusRecord {
    Matched,
    Ambiguous,
    NotFound,
}

#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Record)]
pub struct GeniusCandidateRecord {
    pub id: i64,
    pub title: String,
    pub artist: String,
    pub url: Option<String>,
    pub confidence: f64,
}

#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Record)]
pub struct GeniusPerformanceRecord {
    pub label: String,
    pub artists: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Record)]
pub struct GeniusSongRecord {
    pub id: i64,
    pub title: String,
    pub artist: String,
    pub url: Option<String>,
    pub description: Option<String>,
    pub release_date: Option<String>,
    pub annotation_count: u64,
    pub producers: Vec<String>,
    pub writers: Vec<String>,
    pub performances: Vec<GeniusPerformanceRecord>,
}

#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Record)]
pub struct GeniusResolutionRecord {
    pub status: GeniusMatchStatusRecord,
    pub song: Option<GeniusSongRecord>,
    pub candidates: Vec<GeniusCandidateRecord>,
    pub chosen_by_user: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Record)]
pub struct GeniusAnnotationRecord {
    pub id: i64,
    pub referent_id: i64,
    pub fragment: String,
    pub body: String,
    pub author: Option<String>,
    pub verified: bool,
    pub votes: i64,
    pub share_url: Option<String>,
    #[serde(default)]
    pub body_spans: Vec<GeniusAnnotationSpanRecord>,
    #[serde(default)]
    pub image_urls: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Record)]
pub struct GeniusAnnotationSpanRecord {
    pub text: String,
    pub url: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Record)]
pub struct GeniusAnnotationsRecord {
    pub items: Vec<GeniusAnnotationRecord>,
    pub next_page: Option<u32>,
}

#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Record)]
pub struct GeniusLyricLineRecord {
    pub text: String,
    pub referent_id: Option<i64>,
    pub is_header: bool,
    #[serde(default)]
    pub spans: Vec<GeniusLyricSpanRecord>,
}

#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Record)]
pub struct GeniusLyricSpanRecord {
    pub text: String,
    pub referent_id: Option<i64>,
}

#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Record)]
pub struct GeniusLyricsRecord {
    pub lines: Vec<GeniusLyricLineRecord>,
}

const LYRICS_CACHE_VERSION: u8 = 2;

#[derive(Serialize, Deserialize)]
struct CachedLyrics {
    version: u8,
    lyrics: GeniusLyricsRecord,
}

fn read_cached_lyrics(json: &str) -> Option<GeniusLyricsRecord> {
    let cached: CachedLyrics = serde_json::from_str(json).ok()?;
    (cached.version == LYRICS_CACHE_VERSION).then_some(cached.lyrics)
}

/// Session-local aggregate diagnostics. Never contains titles, IDs or lyric text.
#[derive(Clone, Debug, uniffi::Record)]
pub struct GeniusMetricsRecord {
    pub requests: u64,
    pub response_header_ms: u64,
    pub cache_hits: u64,
    pub http_429: u64,
    pub http_403: u64,
    pub http_5xx: u64,
    pub transport_errors: u64,
    pub parse_errors: u64,
}

#[derive(Default)]
struct Metrics {
    requests: AtomicU64,
    response_header_ms: AtomicU64,
    cache_hits: AtomicU64,
    http_429: AtomicU64,
    http_403: AtomicU64,
    http_5xx: AtomicU64,
    transport_errors: AtomicU64,
    parse_errors: AtomicU64,
}

#[derive(Default)]
struct RateGate {
    last_start: Option<Instant>,
    retry_at: Option<Instant>,
    forbidden_until: Option<Instant>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct MatchCache {
    status: GeniusMatchStatusRecord,
    song_id: Option<i64>,
    candidates: Vec<GeniusCandidateRecord>,
}

pub struct GeniusEngine {
    db: Arc<Db>,
    // A single HTTP gate bounds load from skips, preloads and manual searches together.
    request_gate: Mutex<RateGate>,
    // Re-checking the cache after this lock makes concurrent lookups single-flight.
    resolve_gate: Mutex<()>,
    // Re-check content cache after locking so two tracks sharing a Genius ID do not refetch it.
    document_gate: Mutex<()>,
    metrics: Metrics,
}

impl GeniusEngine {
    pub fn new(db: Arc<Db>) -> Self {
        Self {
            db,
            request_gate: Mutex::new(RateGate::default()),
            resolve_gate: Mutex::new(()),
            document_gate: Mutex::new(()),
            metrics: Metrics::default(),
        }
    }

    pub fn metrics(&self) -> GeniusMetricsRecord {
        let read = |counter: &AtomicU64| counter.load(Ordering::Relaxed);
        GeniusMetricsRecord {
            requests: read(&self.metrics.requests),
            response_header_ms: read(&self.metrics.response_header_ms),
            cache_hits: read(&self.metrics.cache_hits),
            http_429: read(&self.metrics.http_429),
            http_403: read(&self.metrics.http_403),
            http_5xx: read(&self.metrics.http_5xx),
            transport_errors: read(&self.metrics.transport_errors),
            parse_errors: read(&self.metrics.parse_errors),
        }
    }

    pub fn cached(&self, track: &GeniusTrackRecord) -> Option<GeniusResolutionRecord> {
        let (track_key, fingerprint) = track_keys(track);
        if let Some(id) = self.db.get_genius_choice(&track_key, &fingerprint) {
            return self.cached_detail(id).map(|song| GeniusResolutionRecord {
                status: GeniusMatchStatusRecord::Matched,
                song: Some(song),
                candidates: Vec::new(),
                chosen_by_user: true,
            });
        }
        let cache_key = match_cache_key(&track_key, &fingerprint);
        let json = self.db.get_genius_cache("match", &cache_key, MATCH_TTL)?;
        let match_cache: MatchCache = serde_json::from_str(&json).ok()?;
        let ttl = if match_cache.status == GeniusMatchStatusRecord::NotFound {
            MISS_TTL
        } else {
            MATCH_TTL
        };
        if self.db.get_genius_cache("match", &cache_key, ttl).is_none() {
            return None;
        }
        let song = match_cache.song_id.and_then(|id| self.cached_detail(id));
        if match_cache.status == GeniusMatchStatusRecord::Matched && song.is_none() {
            return None;
        }
        self.metrics.cache_hits.fetch_add(1, Ordering::Relaxed);
        Some(GeniusResolutionRecord {
            status: match_cache.status,
            song,
            candidates: match_cache.candidates,
            chosen_by_user: false,
        })
    }

    pub async fn resolve(
        &self,
        track: GeniusTrackRecord,
        force: bool,
    ) -> Result<GeniusResolutionRecord, SideBError> {
        let _guard = self.resolve_gate.lock().await;
        if !force {
            if let Some(cached) = self.cached(&track) {
                return Ok(cached);
            }
        }
        let (track_key, fingerprint) = track_keys(&track);
        if let Some(id) = self.db.get_genius_choice(&track_key, &fingerprint) {
            let song = self.song_detail(id, force).await?;
            return Ok(GeniusResolutionRecord {
                status: GeniusMatchStatusRecord::Matched,
                song: Some(song),
                candidates: Vec::new(),
                chosen_by_user: true,
            });
        }

        // A fresh match survives an expired detail: refresh that document without searching again.
        if !force {
            let key = match_cache_key(&track_key, &fingerprint);
            if let Some(cache) = self
                .db
                .get_genius_cache("match", &key, MATCH_TTL)
                .and_then(|raw| serde_json::from_str::<MatchCache>(&raw).ok())
            {
                if cache.status == GeniusMatchStatusRecord::Matched {
                    if let Some(id) = cache.song_id {
                        let song = self.song_detail(id, false).await?;
                        return Ok(GeniusResolutionRecord {
                            status: GeniusMatchStatusRecord::Matched,
                            song: Some(song),
                            candidates: cache.candidates,
                            chosen_by_user: false,
                        });
                    }
                }
            }
        }

        let clean_title = clean_query_title(&track.title);
        let base_artist = base_artist_credit(&track.artists);
        let initial_query = format!("{clean_title} {base_artist}");

        let mut candidates = self.search_candidates(&initial_query).await?;
        rank_candidates(&track, &mut candidates);
        if !is_auto_match(&track, &candidates) {
            let fallback_artist = lead_artist(&track.artists);
            let fallback_query = format!("{clean_title} {fallback_artist}");
            if normalize(&fallback_query) != normalize(&initial_query) {
                let extra = self.search_candidates(&fallback_query).await?;
                let mut seen: HashSet<i64> = candidates.iter().map(|c| c.id).collect();
                candidates.extend(extra.into_iter().filter(|c| seen.insert(c.id)));
                rank_candidates(&track, &mut candidates);
            }
            if !is_auto_match(&track, &candidates)
                && normalize(&track.title) != normalize(&clean_title)
            {
                let raw_query = format!("{} {}", track.title, track.artists);
                if normalize(&raw_query) != normalize(&initial_query)
                    && normalize(&raw_query) != normalize(&fallback_query)
                {
                    let extra = self.search_candidates(&raw_query).await?;
                    let mut seen: HashSet<i64> = candidates.iter().map(|c| c.id).collect();
                    candidates.extend(extra.into_iter().filter(|c| seen.insert(c.id)));
                    rank_candidates(&track, &mut candidates);
                }
            }
        }
        // Very short names such as "OFF" otherwise surface unrelated titles containing the word.
        if normalize(&clean_title)
            .chars()
            .filter(|c| !c.is_whitespace())
            .count()
            <= 3
        {
            candidates.retain(|candidate| title_equivalent(&clean_title, &candidate.title));
        }
        candidates.truncate(10);
        let automatic = is_auto_match(&track, &candidates);
        let status = if automatic {
            GeniusMatchStatusRecord::Matched
        } else if candidates.is_empty() {
            GeniusMatchStatusRecord::NotFound
        } else {
            GeniusMatchStatusRecord::Ambiguous
        };
        let song_id = automatic.then(|| candidates[0].id);
        let song = if let Some(id) = song_id {
            Some(self.song_detail(id, force).await?)
        } else {
            None
        };
        let result = GeniusResolutionRecord {
            status: status.clone(),
            song,
            candidates: candidates.clone(),
            chosen_by_user: false,
        };
        let cache = MatchCache {
            status,
            song_id,
            candidates,
        };
        if let Ok(json) = serde_json::to_string(&cache) {
            self.db
                .put_genius_cache("match", &match_cache_key(&track_key, &fingerprint), &json);
        }
        Ok(result)
    }

    pub async fn search_manual(
        &self,
        query: String,
    ) -> Result<Vec<GeniusCandidateRecord>, SideBError> {
        let query = query.trim();
        if query.len() < 2 || query.len() > 200 {
            return Ok(Vec::new());
        }
        self.search_candidates(query).await
    }

    pub async fn choose(
        &self,
        track: GeniusTrackRecord,
        id: i64,
    ) -> Result<GeniusResolutionRecord, SideBError> {
        if id <= 0 {
            return Err(SideBError::NotFound {
                message: "Invalid Genius song".into(),
            });
        }
        let song = self.song_detail(id, false).await?;
        let (track_key, fingerprint) = track_keys(&track);
        self.db.put_genius_choice(&track_key, &fingerprint, id);
        Ok(GeniusResolutionRecord {
            status: GeniusMatchStatusRecord::Matched,
            song: Some(song),
            candidates: Vec::new(),
            chosen_by_user: true,
        })
    }

    pub fn clear_choice(&self, track: &GeniusTrackRecord) {
        let (track_key, fingerprint) = track_keys(track);
        self.db.remove_genius_choice(&track_key);
        self.db
            .remove_genius_cache("match", &match_cache_key(&track_key, &fingerprint));
    }

    pub fn report_miss(
        &self,
        track: &GeniusTrackRecord,
        status: GeniusMatchStatusRecord,
        candidate_ids: Vec<i64>,
    ) -> Result<(), SideBError> {
        let status = match status {
            GeniusMatchStatusRecord::Ambiguous => "ambiguous",
            GeniusMatchStatusRecord::NotFound => "not_found",
            GeniusMatchStatusRecord::Matched => {
                return Err(SideBError::Other {
                    message: "Only unresolved Genius tracks can be reported".into(),
                });
            }
        };
        let (track_key, fingerprint) = track_keys(track);
        let candidate_ids: Vec<i64> = candidate_ids
            .into_iter()
            .filter(|id| *id > 0)
            .take(10)
            .collect();
        let candidate_ids =
            serde_json::to_string(&candidate_ids).map_err(|error| SideBError::ParseError {
                message: error.to_string(),
            })?;
        self.db
            .record_genius_miss(
                &track_key,
                &fingerprint,
                &track.title,
                &track.artists,
                track.album.as_deref(),
                track.duration_seconds,
                track.is_upload,
                status,
                &candidate_ids,
            )
            .map_err(|error| SideBError::DbError {
                message: error.to_string(),
            })
    }

    fn cached_detail(&self, id: i64) -> Option<GeniusSongRecord> {
        let result = self
            .db
            .get_genius_cache("detail", &id.to_string(), CONTENT_TTL)
            .and_then(|json| serde_json::from_str(&json).ok());
        if result.is_some() {
            self.metrics.cache_hits.fetch_add(1, Ordering::Relaxed);
        }
        result
    }

    async fn song_detail(&self, id: i64, force: bool) -> Result<GeniusSongRecord, SideBError> {
        let _guard = self.document_gate.lock().await;
        if !force {
            if let Some(song) = self.cached_detail(id) {
                return Ok(song);
            }
        }
        let url = format!("https://genius.com/api/songs/{id}");
        let json = self.get_json(&url).await?;
        let raw = json
            .pointer("/response/song")
            .ok_or_else(|| SideBError::ParseError {
                message: "Genius song response missing".into(),
            })?;
        let song = parse_song(raw)?;
        if let Ok(data) = serde_json::to_string(&song) {
            self.db.put_genius_cache("detail", &id.to_string(), &data);
        }
        Ok(song)
    }

    async fn search_candidates(
        &self,
        query: &str,
    ) -> Result<Vec<GeniusCandidateRecord>, SideBError> {
        let url = format!(
            "https://genius.com/api/search/song?q={}",
            urlencoding::encode(query)
        );
        let json = self.get_json(&url).await?;
        let sections = json
            .pointer("/response/sections")
            .and_then(Value::as_array)
            .ok_or_else(|| SideBError::ParseError {
                message: "Genius search sections missing".into(),
            })?;
        let mut found = Vec::new();
        for section in sections {
            if let Some(hits) = section.get("hits").and_then(Value::as_array) {
                for hit in hits {
                    if let Some(raw) = hit.get("result") {
                        if let (Some(id), Some(title)) = (
                            raw.get("id").and_then(Value::as_i64),
                            raw.get("title").and_then(Value::as_str),
                        ) {
                            found.push(GeniusCandidateRecord {
                                id,
                                title: title.into(),
                                artist: raw
                                    .get("artist_names")
                                    .and_then(Value::as_str)
                                    .or_else(|| {
                                        raw.pointer("/primary_artist/name").and_then(Value::as_str)
                                    })
                                    .unwrap_or("")
                                    .into(),
                                url: raw.get("url").and_then(Value::as_str).map(str::to_owned),
                                confidence: 0.0,
                            });
                        }
                    }
                }
            }
        }
        let mut seen = HashSet::new();
        found.retain(|candidate| seen.insert(candidate.id));
        // Rank across all search sections before taking the ten best results in resolve().
        found.truncate(30);
        Ok(found)
    }

    async fn get_json(&self, url: &str) -> Result<Value, SideBError> {
        let data = self.get_bytes(url, "application/json", API_LIMIT).await?;
        serde_json::from_slice(&data).map_err(|error| {
            self.metrics.parse_errors.fetch_add(1, Ordering::Relaxed);
            SideBError::ParseError {
                message: error.to_string(),
            }
        })
    }

    async fn get_bytes(
        &self,
        url: &str,
        accept: &str,
        limit: usize,
    ) -> Result<Vec<u8>, SideBError> {
        let mut last_error = None;
        for attempt in 0..2 {
            let mut gate = self.request_gate.lock().await;
            if gate
                .forbidden_until
                .is_some_and(|until| until > Instant::now())
            {
                return Err(SideBError::NetworkError {
                    message: "Genius HTTP 403; retry later".into(),
                });
            }
            if let Some(until) = gate.retry_at.filter(|until| *until > Instant::now()) {
                let wait = until.saturating_duration_since(Instant::now());
                if wait > Duration::from_secs(30) {
                    return Err(SideBError::NetworkError {
                        message: "Genius rate limited; retry later".into(),
                    });
                }
                tokio::time::sleep(wait).await;
            }
            if let Some(last) = gate.last_start {
                let elapsed = last.elapsed();
                if elapsed < Duration::from_millis(250) {
                    tokio::time::sleep(Duration::from_millis(250) - elapsed).await;
                }
            }
            gate.last_start = Some(Instant::now());
            let request_started = Instant::now();
            self.metrics.requests.fetch_add(1, Ordering::Relaxed);
            let response = crate::http::genius_client()
                .get(url)
                .header(reqwest::header::ACCEPT, accept)
                .header(
                    reqwest::header::USER_AGENT,
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 Safari/605.1.15",
                )
                .timeout(Duration::from_secs(8))
                .send()
                .await;
            self.metrics.response_header_ms.fetch_add(
                request_started.elapsed().as_millis() as u64,
                Ordering::Relaxed,
            );
            let mut response = match response {
                Ok(r) => r,
                Err(error) => {
                    self.metrics
                        .transport_errors
                        .fetch_add(1, Ordering::Relaxed);
                    last_error = Some(SideBError::NetworkError {
                        message: error.to_string(),
                    });
                    drop(gate);
                    if attempt == 0 {
                        tokio::time::sleep(Duration::from_millis(500)).await;
                        continue;
                    }
                    break;
                }
            };
            if response.url().host_str() != Some("genius.com") {
                return Err(SideBError::NetworkError {
                    message: "Genius redirected outside its domain".into(),
                });
            }
            let status = response.status();
            if !status.is_success() {
                let retry_after = response
                    .headers()
                    .get(reqwest::header::RETRY_AFTER)
                    .and_then(|h| h.to_str().ok())
                    .and_then(|s| {
                        s.parse::<u64>().ok().or_else(|| {
                            httpdate::parse_http_date(s).ok().map(|date| {
                                date.duration_since(std::time::SystemTime::now())
                                    .unwrap_or_default()
                                    .as_secs()
                            })
                        })
                    })
                    .unwrap_or(1)
                    .min(86_400);
                match status.as_u16() {
                    429 => {
                        self.metrics.http_429.fetch_add(1, Ordering::Relaxed);
                    }
                    403 => {
                        self.metrics.http_403.fetch_add(1, Ordering::Relaxed);
                        gate.forbidden_until = Some(Instant::now() + Duration::from_secs(5 * 60));
                    }
                    500..=599 => {
                        self.metrics.http_5xx.fetch_add(1, Ordering::Relaxed);
                    }
                    _ => {}
                }
                if status.as_u16() == 429 {
                    gate.retry_at = Some(Instant::now() + Duration::from_secs(retry_after));
                }
                last_error = Some(SideBError::NetworkError {
                    message: format!("Genius HTTP {status}"),
                });
                drop(gate);
                if attempt == 0
                    && (status.as_u16() == 429 || status.is_server_error())
                    && retry_after <= 30
                {
                    tokio::time::sleep(Duration::from_secs(retry_after)).await;
                    continue;
                }
                break;
            }
            if response
                .content_length()
                .is_some_and(|size| size > limit as u64)
            {
                return Err(SideBError::ParseError {
                    message: "Genius response too large".into(),
                });
            }
            let mut data = Vec::new();
            while let Some(chunk) =
                response
                    .chunk()
                    .await
                    .map_err(|e| SideBError::NetworkError {
                        message: e.to_string(),
                    })?
            {
                if data.len() + chunk.len() > limit {
                    return Err(SideBError::ParseError {
                        message: "Genius response too large".into(),
                    });
                }
                data.extend_from_slice(&chunk);
            }
            return Ok(data);
        }
        Err(last_error.unwrap_or_else(|| SideBError::NetworkError {
            message: "Genius unavailable".into(),
        }))
    }
}

fn track_keys(track: &GeniusTrackRecord) -> (String, String) {
    let mut id_hash = Md5::new();
    id_hash.update(track.video_id.as_bytes());
    let mut meta_hash = Md5::new();
    meta_hash.update(
        format!(
            "{}\t{}\t{}\t{}",
            track.title,
            track.artists,
            track.album.as_deref().unwrap_or(""),
            track.duration_seconds.unwrap_or(0)
        )
        .as_bytes(),
    );
    (
        format!("{:x}", id_hash.finalize()),
        format!("{:x}", meta_hash.finalize()),
    )
}

fn match_cache_key(track_key: &str, fingerprint: &str) -> String {
    format!("{MATCH_RULE_VERSION}:{track_key}:{fingerprint}")
}

fn normalize(text: &str) -> String {
    let decomposed: String = text.nfd().filter(|c| !is_combining_mark(*c)).collect();
    decomposed
        .to_lowercase()
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { ' ' })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn base_artist_credit(artists: &str) -> String {
    static FEATURE_RE: OnceLock<regex::Regex> = OnceLock::new();
    let re = FEATURE_RE.get_or_init(|| {
        regex::Regex::new(r"(?i)(?:\s*[\(\[\{]\s*(?:feat\.?|ft\.?|featuring|with|w/)\s+[^\]\)\}]+[\)\]\}]|\s+(?:feat\.?|ft\.?|featuring|with|w/)\s+.*$)").expect("constant regex")
    });
    re.replace_all(artists.trim(), "").trim().to_owned()
}

fn lead_artist(artists: &str) -> String {
    let base = base_artist_credit(artists);
    let first = base.split(',').next().unwrap_or(&base).trim();
    first.split(" & ").next().unwrap_or(first).trim().to_owned()
}

fn title_equivalent(left: &str, right: &str) -> bool {
    let left = normalize(left);
    let right = normalize(right);
    if left == right {
        return true;
    }
    // Genius punctuates some acronyms as separate letters (L.E.S.); players may not.
    let acronym = |spaced: &str, compact: &str| {
        let words: Vec<_> = spaced.split_whitespace().collect();
        (2..=5).contains(&words.len())
            && words.iter().all(|word| word.chars().count() == 1)
            && words.concat() == compact
    };
    acronym(&left, &right) || acronym(&right, &left)
}

fn artist_credit_matches(source: &str, candidate: &str) -> bool {
    let source_full = normalize(source);
    let candidate_full = normalize(candidate);
    if source_full == candidate_full {
        return true;
    }
    // The YouTube catalog sometimes credits the same person twice under both names.
    if (source_full == "kanye west ye" || source_full == "ye kanye west")
        && (candidate_full == "kanye west" || candidate_full == "ye")
    {
        return true;
    }
    let source_base = normalize(&base_artist_credit(source));
    let candidate_base = normalize(&base_artist_credit(candidate));
    if !source_base.is_empty() && source_base == candidate_base {
        return true;
    }
    let source_lead = normalize(&lead_artist(source));
    let candidate_lead = normalize(&lead_artist(candidate));
    if source_lead == source_base && source_lead == candidate_lead {
        return true;
    }
    false
}

fn artist_score(source: &str, candidate: &str) -> f64 {
    let source_full = normalize(source);
    let candidate_full = normalize(candidate);
    let source_base = normalize(&base_artist_credit(source));
    let candidate_base = normalize(&base_artist_credit(candidate));
    let source_lead = normalize(&lead_artist(source));
    let candidate_lead = normalize(&lead_artist(candidate));

    if !source_base.is_empty() && source_base == candidate_base {
        return 1.0;
    }
    let full_sim = strsim::jaro_winkler(&source_full, &candidate_full);
    let base_sim = strsim::jaro_winkler(&source_base, &candidate_base);
    let lead_sim = strsim::jaro_winkler(&source_lead, &candidate_lead);

    full_sim.max(base_sim).max(lead_sim * 0.85)
}

fn clean_query_title(title: &str) -> String {
    static PATTERN: OnceLock<regex::Regex> = OnceLock::new();
    let re = PATTERN.get_or_init(|| {
        regex::Regex::new(r"(?i)\s*[\[(](?:(?:official\s+)?(?:music\s+)?(?:video|audio|visualizer|lyric\s+video)|explicit|(?:feat\.?|ft\.?|featuring|with)\s+[^\])]+|bonus\s+track|deluxe(?:\s+edition|\s+version)?|remaster(?:ed)?(?:\s+\d{4})?|\d{4}\s+remaster(?:ed)?|album\s+version|single\s+version)[\])]").expect("constant regex")
    });
    static PIPE_PATTERN: OnceLock<regex::Regex> = OnceLock::new();
    let pipe_re = PIPE_PATTERN.get_or_init(|| {
        regex::Regex::new(r"\s*\|.*$").expect("constant regex")
    });
    let without_pipe = pipe_re.replace_all(title, "");
    let mut cleaned = without_pipe.into_owned();
    loop {
        let next = re.replace_all(&cleaned, "").trim().to_owned();
        if next == cleaned {
            break;
        }
        cleaned = next;
    }
    cleaned
}

fn version_flags(title: &str) -> HashSet<&'static str> {
    let words: HashSet<String> = normalize(title)
        .split_whitespace()
        .map(str::to_owned)
        .collect();
    [
        "live",
        "remix",
        "acoustic",
        "instrumental",
        "demo",
        "edit",
        "translation",
    ]
    .into_iter()
    .filter(|flag| words.iter().any(|word| word.starts_with(flag)))
    .collect()
}

fn has_sequel_suffix(norm_title: &str) -> bool {
    let words: Vec<&str> = norm_title.split_whitespace().collect();
    if words.is_empty() {
        return false;
    }
    let last = words[words.len() - 1];
    if last.len() == 1 && last.chars().all(|c| c.is_ascii_digit()) && last != "1" && last != "0" {
        return true;
    }
    if words.len() >= 2 {
        let prev = words[words.len() - 2];
        if (prev == "pt" || prev == "part")
            && (last.chars().all(|c| c.is_ascii_digit())
                || matches!(last, "ii" | "iii" | "iv" | "v" | "vi"))
        {
            return true;
        }
        if last.starts_with('v')
            && last.len() > 1
            && last[1..].chars().all(|c| c.is_ascii_digit())
        {
            return true;
        }
    }
    false
}

fn rank_candidates(track: &GeniusTrackRecord, candidates: &mut Vec<GeniusCandidateRecord>) {
    let clean_title = clean_query_title(&track.title);
    let title = normalize(&clean_title);
    let track_has_sequel = has_sequel_suffix(&title);
    for candidate in candidates.iter_mut() {
        let candidate_title = normalize(&candidate.title);
        let title_score = if title_equivalent(&title, &candidate_title) {
            1.0
        } else {
            let sim = strsim::jaro_winkler(&title, &candidate_title);
            if !track_has_sequel && has_sequel_suffix(&candidate_title) {
                sim * 0.8
            } else {
                sim
            }
        };
        let artist_score = artist_score(&track.artists, &candidate.artist);
        let version_ok = version_flags(&track.title) == version_flags(&candidate.title);
        candidate.confidence = if version_ok {
            title_score * 0.7 + artist_score * 0.3
        } else {
            0.0
        };
    }
    candidates.sort_by(|a, b| {
        b.confidence
            .total_cmp(&a.confidence)
            .then_with(|| a.id.cmp(&b.id))
    });
}

fn is_auto_match(track: &GeniusTrackRecord, candidates: &[GeniusCandidateRecord]) -> bool {
    let Some(first) = candidates.first() else {
        return false;
    };
    if version_flags(&track.title) != version_flags(&first.title) {
        return false;
    }
    let title = normalize(&clean_query_title(&track.title));
    let candidate_title = normalize(&first.title);
    if title.chars().filter(|c| !c.is_whitespace()).count() <= 3
        && !title_equivalent(&title, &candidate_title)
    {
        return false;
    }
    // Identical titles by the same lead artist can be different album cuts.
    // Search results do not reliably provide album or duration for disambiguation.
    if candidates.iter().skip(1).any(|candidate| {
        title_equivalent(&candidate.title, &first.title)
            && (artist_credit_matches(&track.artists, &candidate.artist)
                || (normalize(&lead_artist(&candidate.artist))
                    == normalize(&lead_artist(&first.artist))
                    && candidate.confidence >= 0.95))
    }) {
        return false;
    }
    // "Live" cannot identify a venue or recording year. Let the user choose that cut.
    if !version_flags(&track.title).is_empty() && !title_equivalent(&title, &candidate_title) {
        return false;
    }
    if title_equivalent(&title, &candidate_title)
        && artist_credit_matches(&track.artists, &first.artist)
    {
        return true;
    }
    let margin = first.confidence - candidates.get(1).map_or(0.0, |c| c.confidence);
    (title_equivalent(&title, &candidate_title)
        || strsim::jaro_winkler(&title, &candidate_title) >= 0.92)
        && artist_credit_matches(&track.artists, &first.artist)
        && artist_score(&track.artists, &first.artist) >= 0.85
        && (candidates.len() == 1 || margin >= 0.12)
}

fn text_from_dom(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Array(items) => items.iter().map(text_from_dom).collect::<Vec<_>>().join(""),
        Value::Object(object) => {
            let tag = object.get("tag").and_then(Value::as_str).unwrap_or("");
            let inner = object
                .get("children")
                .map(text_from_dom)
                .unwrap_or_default();
            match tag {
                "br" => "\n".into(),
                "p" | "blockquote" => format!("{}\n\n", inner.trim()),
                "li" => format!("• {}\n", inner.trim()),
                _ => inner,
            }
        }
        _ => String::new(),
    }
}

fn clean_text(value: &str) -> String {
    value
        .split('\n')
        .map(str::trim)
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_owned()
}

fn parse_song(raw: &Value) -> Result<GeniusSongRecord, SideBError> {
    let id = raw
        .get("id")
        .and_then(Value::as_i64)
        .ok_or_else(|| SideBError::ParseError {
            message: "Genius song ID missing".into(),
        })?;
    let title = raw
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_owned();
    let artist = raw
        .pointer("/primary_artist/name")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_owned();
    let description = raw
        .pointer("/description/dom")
        .map(text_from_dom)
        .map(|s| clean_text(&s))
        .filter(|s| !s.is_empty() && s != "?")
        .or_else(|| {
            raw.pointer("/description/plain")
                .and_then(Value::as_str)
                .map(clean_text)
                .filter(|s| !s.is_empty() && s != "?")
        });
    let names = |key: &str| -> Vec<String> {
        raw.get(key)
            .and_then(Value::as_array)
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.get("name").and_then(Value::as_str).map(str::to_owned))
                    .collect()
            })
            .unwrap_or_default()
    };
    let performances = raw
        .get("custom_performances")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|p| {
                    let label = p.get("label")?.as_str()?.to_owned();
                    let artists: Vec<String> = p
                        .get("artists")?
                        .as_array()?
                        .iter()
                        .filter_map(|a| a.get("name").and_then(Value::as_str).map(str::to_owned))
                        .collect();
                    (!artists.is_empty()).then_some(GeniusPerformanceRecord { label, artists })
                })
                .collect()
        })
        .unwrap_or_default();
    Ok(GeniusSongRecord {
        id,
        title,
        artist,
        url: raw.get("url").and_then(Value::as_str).map(str::to_owned),
        description,
        release_date: raw
            .get("release_date_for_display")
            .and_then(Value::as_str)
            .map(str::to_owned),
        annotation_count: raw
            .get("annotation_count")
            .and_then(Value::as_u64)
            .unwrap_or(0),
        producers: names("producer_artists"),
        writers: names("writer_artists"),
        performances,
    })
}

impl GeniusEngine {
    pub fn cached_annotations(&self, song_id: i64, page: u32) -> Option<GeniusAnnotationsRecord> {
        let result = self
            .db
            .get_genius_cache("annotations", &format!("{song_id}:{page}"), CONTENT_TTL)
            .and_then(|json| serde_json::from_str(&json).ok());
        if result.is_some() {
            self.metrics.cache_hits.fetch_add(1, Ordering::Relaxed);
        }
        result
    }

    pub fn cached_lyrics(&self, song_id: i64) -> Option<GeniusLyricsRecord> {
        let result = self
            .db
            .get_genius_cache("lyrics", &song_id.to_string(), LYRICS_TTL)
            .and_then(|json| read_cached_lyrics(&json));
        if result.is_some() {
            self.metrics.cache_hits.fetch_add(1, Ordering::Relaxed);
        }
        result
    }

    pub async fn annotations(
        &self,
        song_id: i64,
        page: u32,
        force: bool,
    ) -> Result<GeniusAnnotationsRecord, SideBError> {
        let _guard = self.document_gate.lock().await;
        if song_id <= 0 || page == 0 || page > 100 {
            return Err(SideBError::NotFound {
                message: "Invalid Genius annotation page".into(),
            });
        }
        let key = format!("{song_id}:{page}");
        if !force {
            if let Some(json) = self.db.get_genius_cache("annotations", &key, CONTENT_TTL) {
                if let Ok(cached) = serde_json::from_str(&json) {
                    return Ok(cached);
                }
            }
        }
        let url = format!("https://genius.com/api/referents?song_id={song_id}&text_format=dom,plain&per_page=50&page={page}");
        let json = self.get_json(&url).await?;
        let raw = json
            .pointer("/response/referents")
            .and_then(Value::as_array)
            .ok_or_else(|| SideBError::ParseError {
                message: "Genius referents missing".into(),
            })?;
        let result = parse_annotation_page(raw, page);
        if let Ok(data) = serde_json::to_string(&result) {
            self.db.put_genius_cache("annotations", &key, &data);
        }
        Ok(result)
    }

    pub async fn lyrics(
        &self,
        song_id: i64,
        song_url: String,
        force: bool,
    ) -> Result<GeniusLyricsRecord, SideBError> {
        let _guard = self.document_gate.lock().await;
        if song_id <= 0 {
            return Err(SideBError::NotFound {
                message: "Invalid Genius song".into(),
            });
        }
        let key = song_id.to_string();
        if !force {
            if let Some(json) = self.db.get_genius_cache("lyrics", &key, LYRICS_TTL) {
                if let Some(cached) = read_cached_lyrics(&json) {
                    return Ok(cached);
                }
            }
        }
        let parsed = reqwest::Url::parse(&song_url).map_err(|_| SideBError::ParseError {
            message: "Invalid Genius URL".into(),
        })?;
        if parsed.scheme() != "https" || parsed.host_str() != Some("genius.com") {
            return Err(SideBError::ParseError {
                message: "Non-Genius lyrics URL".into(),
            });
        }
        let data = self
            .get_bytes(parsed.as_str(), "text/html", HTML_LIMIT)
            .await?;
        let html = String::from_utf8(data).map_err(|_| SideBError::ParseError {
            message: "Invalid Genius HTML encoding".into(),
        })?;
        let result = parse_lyrics(&html);
        if result.lines.is_empty() {
            return Err(SideBError::ParseError {
                message: "No Genius lyric containers found".into(),
            });
        }
        if let Ok(data) = serde_json::to_string(&CachedLyrics {
            version: LYRICS_CACHE_VERSION,
            lyrics: result.clone(),
        }) {
            self.db.put_genius_cache("lyrics", &key, &data);
        }
        Ok(result)
    }
}

fn parse_annotation(raw: &Value) -> Option<GeniusAnnotationRecord> {
    let referent_id = raw.get("id")?.as_i64()?;
    let fragment = raw.get("fragment")?.as_str()?.trim().to_owned();
    let annotation = raw.get("annotations")?.as_array()?.first()?;
    let id = annotation.get("id")?.as_i64()?;
    let body = annotation
        .pointer("/body/plain")
        .and_then(Value::as_str)
        .filter(|body| !body.trim().is_empty())
        .map(str::to_owned)
        .or_else(|| annotation.pointer("/body/dom").map(text_from_dom))
        .map(|s| clean_text(&s))?;
    if fragment.is_empty() || body.is_empty() {
        return None;
    }
    let mut body_spans = Vec::new();
    let mut image_urls = Vec::new();
    if let Some(dom) = annotation.pointer("/body/dom") {
        collect_annotation_dom(dom, None, &mut body_spans, &mut image_urls);
    }
    if body_spans.is_empty() {
        body_spans.push(GeniusAnnotationSpanRecord {
            text: body.clone(),
            url: None,
        });
    }
    Some(GeniusAnnotationRecord {
        id,
        referent_id,
        fragment,
        body,
        author: annotation
            .pointer("/authors/0/user/name")
            .and_then(Value::as_str)
            .or_else(|| {
                annotation
                    .pointer("/authors/0/user/login")
                    .and_then(Value::as_str)
            })
            .map(str::to_owned),
        verified: annotation
            .get("verified")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        votes: annotation
            .get("votes_total")
            .and_then(Value::as_i64)
            .unwrap_or(0),
        share_url: annotation
            .get("share_url")
            .and_then(Value::as_str)
            .map(str::to_owned),
        body_spans,
        image_urls,
    })
}

fn genius_content_url(raw: &str) -> Option<String> {
    let url = raw.trim();
    if url.starts_with("https://") || url.starts_with("http://") {
        Some(url.to_owned())
    } else if url.starts_with('/') && !url.starts_with("//") {
        Some(format!("https://genius.com{url}"))
    } else {
        None
    }
}

fn collect_annotation_dom(
    value: &Value,
    active_link: Option<&str>,
    spans: &mut Vec<GeniusAnnotationSpanRecord>,
    images: &mut Vec<String>,
) {
    if spans.len() >= 512 {
        return;
    }
    match value {
        Value::String(text) => {
            if !text.is_empty() {
                let url = active_link.map(str::to_owned);
                if let Some(last) = spans.last_mut() {
                    if last.url == url {
                        last.text.push_str(text);
                        return;
                    }
                }
                spans.push(GeniusAnnotationSpanRecord {
                    text: text.clone(),
                    url,
                });
            }
        }
        Value::Array(children) => {
            for child in children {
                collect_annotation_dom(child, active_link, spans, images);
            }
        }
        Value::Object(node) => {
            let tag = node.get("tag").and_then(Value::as_str).unwrap_or("");
            let attrs = node.get("attributes");
            if tag == "img" {
                if images.len() < 8 {
                    if let Some(url) = attrs
                        .and_then(|a| a.get("src").or_else(|| a.get("data-src")))
                        .and_then(Value::as_str)
                        .and_then(genius_content_url)
                    {
                        if !images.contains(&url) {
                            images.push(url);
                        }
                    }
                }
                return;
            }
            if tag == "br" {
                collect_annotation_dom(&Value::String("\n".into()), active_link, spans, images);
                return;
            }
            let link = if tag == "a" {
                attrs
                    .and_then(|a| a.get("href"))
                    .and_then(Value::as_str)
                    .and_then(genius_content_url)
            } else {
                None
            };
            let active = link.as_deref().or(active_link);
            if let Some(children) = node.get("children") {
                collect_annotation_dom(children, active, spans, images);
            }
            if matches!(tag, "p" | "div" | "blockquote" | "li") {
                collect_annotation_dom(&Value::String("\n\n".into()), active_link, spans, images);
            }
        }
        _ => {}
    }
}

fn parse_annotation_page(raw: &[Value], page: u32) -> GeniusAnnotationsRecord {
    GeniusAnnotationsRecord {
        items: raw.iter().filter_map(parse_annotation).collect(),
        // Paging follows server row count, not the number of parseable annotations.
        next_page: (raw.len() == 50).then_some(page + 1),
    }
}

#[derive(Default)]
struct LyricBuilder {
    lines: Vec<GeniusLyricLineRecord>,
    current: String,
    referent_id: Option<i64>,
    spans: Vec<GeniusLyricSpanRecord>,
}

impl LyricBuilder {
    fn flush(&mut self) {
        let text = self.current.trim().to_owned();
        if !text.is_empty() && self.lines.len() < 1_000 {
            let start = self.current.len() - self.current.trim_start().len();
            let end = start + text.len();
            let mut offset = 0;
            let mut spans: Vec<GeniusLyricSpanRecord> = Vec::new();
            for span in std::mem::take(&mut self.spans) {
                let span_end = offset + span.text.len();
                let kept_start = start.max(offset);
                let kept_end = end.min(span_end);
                if kept_start < kept_end {
                    let kept_text =
                        span.text[(kept_start - offset)..(kept_end - offset)].to_owned();
                    if let Some(last) = spans.last_mut() {
                        if last.referent_id == span.referent_id {
                            last.text.push_str(&kept_text);
                            offset = span_end;
                            continue;
                        }
                    }
                    spans.push(GeniusLyricSpanRecord {
                        text: kept_text,
                        referent_id: span.referent_id,
                    });
                }
                offset = span_end;
            }
            debug_assert_eq!(
                spans
                    .iter()
                    .map(|span| span.text.as_str())
                    .collect::<String>(),
                text
            );
            let is_header = text.starts_with('[') && text.ends_with(']');
            self.lines.push(GeniusLyricLineRecord {
                text,
                referent_id: self.referent_id,
                is_header,
                spans,
            });
        }
        self.current.clear();
        self.referent_id = None;
        self.spans.clear();
    }

    fn push_text(&mut self, text: &str, referent_id: Option<i64>) {
        for (index, part) in text.split('\n').enumerate() {
            if index > 0 {
                self.flush();
            }
            if !part.is_empty() {
                self.current.push_str(part);
                if self.referent_id.is_none() && referent_id.is_some() {
                    self.referent_id = referent_id;
                }
                if let Some(last) = self.spans.last_mut() {
                    if last.referent_id == referent_id {
                        last.text.push_str(part);
                        continue;
                    }
                }
                self.spans.push(GeniusLyricSpanRecord {
                    text: part.to_owned(),
                    referent_id,
                });
            }
        }
    }
}

fn referent_from_href(href: &str) -> Option<i64> {
    href.strip_prefix('/')
        .and_then(|path| path.split('/').next()?.parse().ok())
        .or_else(|| href.split("#note-").nth(1)?.split('-').next()?.parse().ok())
}

fn walk_lyrics(node: ElementRef<'_>, active_ref: Option<i64>, builder: &mut LyricBuilder) {
    let name = node.value().name();
    if name == "script"
        || name == "style"
        || node.value().attr("data-exclude-from-selection") == Some("true")
    {
        return;
    }
    if name == "br" {
        builder.flush();
        return;
    }
    let referent = if name == "a" {
        node.value()
            .attr("data-id")
            .or_else(|| node.value().attr("data-annotation-id"))
            .and_then(|id| id.parse().ok())
            .or_else(|| node.value().attr("href").and_then(referent_from_href))
            .or(active_ref)
    } else {
        active_ref
    };
    for child in node.children() {
        if let Some(text) = child.value().as_text() {
            builder.push_text(text, referent);
        } else if let Some(element) = ElementRef::wrap(child) {
            walk_lyrics(element, referent, builder);
        }
    }
}

fn parse_lyrics(html: &str) -> GeniusLyricsRecord {
    let document = Html::parse_document(html);
    let selector = Selector::parse("[data-lyrics-container='true']").expect("constant selector");
    let mut builder = LyricBuilder::default();
    for container in document.select(&selector) {
        walk_lyrics(container, None, &mut builder);
        builder.flush();
    }
    GeniusLyricsRecord {
        lines: builder.lines,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn track(title: &str, artist: &str) -> GeniusTrackRecord {
        GeniusTrackRecord {
            video_id: "test-video".into(),
            title: title.into(),
            artists: artist.into(),
            album: None,
            duration_seconds: Some(210),
            is_upload: false,
        }
    }

    #[test]
    fn version_and_artist_matching_refuses_wrong_cuts() {
        let t = track("Bohemian Rhapsody (Live)", "Queen");
        let mut candidates = vec![
            GeniusCandidateRecord {
                id: 1,
                title: "Bohemian Rhapsody".into(),
                artist: "Queen".into(),
                url: None,
                confidence: 0.0,
            },
            GeniusCandidateRecord {
                id: 2,
                title: "Bohemian Rhapsody (Live Aid)".into(),
                artist: "Queen".into(),
                url: None,
                confidence: 0.0,
            },
        ];
        rank_candidates(&t, &mut candidates);
        assert_eq!(candidates[0].id, 2);
        assert!(
            !is_auto_match(&t, &candidates),
            "the live venue is ambiguous"
        );
        let t = track("DESPECHÁ", "ROSALÍA");
        let mut candidates = vec![
            GeniusCandidateRecord {
                id: 3,
                title: "DESPECHÁ".into(),
                artist: "ROSALÍA".into(),
                url: None,
                confidence: 0.0,
            },
            GeniusCandidateRecord {
                id: 4,
                title: "DESPECHÁ RMX".into(),
                artist: "ROSALÍA".into(),
                url: None,
                confidence: 0.0,
            },
        ];
        rank_candidates(&t, &mut candidates);
        assert!(is_auto_match(&t, &candidates));
    }

    #[test]
    fn html_lines_keep_referent_ids_without_running_script() {
        let html = r#"<div data-lyrics-container="true"><div data-exclude-from-selection="true"><button>271 Contributors</button><div>Page introduction</div></div><a href="/123/annotation">First line<br>Second line</a><br><span>[Chorus]</span><br>Plain line</div>"#;
        let lines = parse_lyrics(html).lines;
        assert_eq!(lines.len(), 4);
        assert_eq!(lines[0].referent_id, Some(123));
        assert_eq!(lines[0].spans[0].referent_id, Some(123));
        assert_eq!(lines[1].referent_id, Some(123));
        assert!(lines[2].is_header);
        assert_eq!(lines[3].referent_id, None);
    }

    #[test]
    fn compton_html_keeps_distinct_annotations_and_spaces() {
        // Reduced from the two adjacent referent fragments in Genius's Compton HTML.
        let html = r#"<div data-lyrics-container="true">
          <a href="/123/Kendrick-lamar-compton/Produced-by-just-blaze"><span>[Produced by Just Blaze]</span></a><br>
          <span>[Verse 1: Kendrick Lamar]</span><br>
          <a href="/1104354/Kendrick-lamar-compton/And-the-chapter"><span>And the chapter that read at 25 I would live</span></a><span tabindex="0" style="position:absolute"></span> <a href="/1104195/Kendrick-lamar-compton/Dormant"><span>dormant like five in the morning</span></a><br>
          Plain <a href="/55/annotation">marked</a> text
        </div>"#;
        let lines = parse_lyrics(html).lines;
        assert_eq!(lines.len(), 4);
        assert!(lines[0].is_header);
        assert_eq!(lines[0].referent_id, Some(123));
        assert_eq!(lines[0].spans[0].referent_id, Some(123));
        assert_eq!(lines[1].referent_id, None);
        assert_eq!(
            lines[2].text,
            "And the chapter that read at 25 I would live dormant like five in the morning"
        );
        assert_eq!(lines[2].spans[0].referent_id, Some(1104354));
        assert_eq!(lines[2].spans[1].referent_id, None);
        assert_eq!(lines[2].spans[2].referent_id, Some(1104195));
        assert_eq!(lines[3].text, "Plain marked text");
        for line in &lines {
            assert_eq!(
                line.spans
                    .iter()
                    .map(|span| span.text.as_str())
                    .collect::<String>(),
                line.text
            );
        }
    }

    #[test]
    fn old_lyrics_cache_is_refetched() {
        let lyrics = parse_lyrics("<div data-lyrics-container='true'>One line</div>");
        assert!(read_cached_lyrics(&serde_json::to_string(&lyrics).unwrap()).is_none());
        let current = serde_json::to_string(&CachedLyrics {
            version: LYRICS_CACHE_VERSION,
            lyrics: lyrics.clone(),
        })
        .unwrap();
        assert_eq!(
            read_cached_lyrics(&current).unwrap().lines[0].text,
            "One line"
        );
    }

    #[test]
    fn annotation_dom_keeps_links_and_images_and_lyric_spans_keep_partial_marks() {
        let raw = serde_json::json!({
            "id": 9, "fragment": "Marked words", "annotations": [{
                "id": 10,
                "body": {"plain": "Read source and see photo", "dom": {"tag": "root", "children": [
                    {"tag":"p", "children":["Read ", {"tag":"a", "attributes":{"href":"/artists/sample"}, "children":["source"]}, " and see photo"]},
                    {"tag":"img", "attributes":{"src":"https://images.genius.com/example.jpg"}}
                ]}}
            }]
        });
        let annotation = parse_annotation(&raw).unwrap();
        assert!(annotation
            .body_spans
            .iter()
            .any(|span| span.text == "source"
                && span.url.as_deref() == Some("https://genius.com/artists/sample")));
        assert_eq!(
            annotation.image_urls,
            ["https://images.genius.com/example.jpg"]
        );
        let lyrics = parse_lyrics("<div data-lyrics-container='true'>Plain <a href='/9/annotation'>marked words</a> after<br>Next</div>");
        assert_eq!(lyrics.lines[0].spans.len(), 3);
        assert_eq!(lyrics.lines[0].spans[0].referent_id, None);
        assert_eq!(lyrics.lines[0].spans[1].referent_id, Some(9));
        assert_eq!(lyrics.lines[0].spans[2].referent_id, None);
    }

    #[test]
    fn metadata_fingerprint_changes_with_version() {
        assert_ne!(
            track_keys(&track("Song", "Artist")).1,
            track_keys(&track("Song (Live)", "Artist")).1
        );
    }

    #[test]
    fn miss_report_rejects_confirmed_matches() {
        let db = Arc::new(Db::open(std::path::Path::new(":memory:")).unwrap());
        let engine = GeniusEngine::new(db);
        let track = track("Real", "Kendrick Lamar");
        assert!(engine
            .report_miss(&track, GeniusMatchStatusRecord::Matched, vec![1])
            .is_err());
        assert!(engine
            .report_miss(&track, GeniusMatchStatusRecord::Ambiguous, vec![1, -2])
            .is_ok());
    }

    #[test]
    fn detail_and_annotation_fixtures_preserve_partial_content() {
        let raw = serde_json::json!({
            "id": 123, "title": "Canción", "primary_artist": {"name": "Artista"},
            "description": {"dom": {"tag": "root", "children": [
                {"tag": "p", "children": ["Una historia."]},
                {"tag": "p", "children": ["Otra parte."]}
            ]}},
            "producer_artists": [{"name": "Productor"}],
            "writer_artists": [{"name": "Compositor"}],
            "custom_performances": [{"label": "Guitarra", "artists": [{"name": "Músico"}]}]
        });
        let song = parse_song(&raw).unwrap();
        assert!(song.description.unwrap().contains("Una historia."));
        assert_eq!(song.producers, ["Productor"]);
        assert_eq!(song.performances[0].artists, ["Músico"]);
        assert!(parse_song(&serde_json::json!({"title":"No ID"})).is_err());

        let valid = serde_json::json!({
            "id": 45, "fragment": "Una línea", "annotations": [{
                "id": 98, "body": {"dom": {"tag": "p", "children": ["Explicación"]}}
            }]
        });
        let mut rows = vec![serde_json::json!({"broken":true}); 50];
        rows[0] = valid;
        let page = parse_annotation_page(&rows, 1);
        assert_eq!(page.items.len(), 1);
        assert_eq!(page.next_page, Some(2));
        assert_eq!(page.items[0].referent_id, 45);
    }

    #[tokio::test]
    async fn repeated_resolve_with_valid_cache_uses_no_network() {
        let db = Arc::new(Db::open(std::path::Path::new(":memory:")).unwrap());
        let engine = GeniusEngine::new(db.clone());
        let track = track("DESPECHÁ", "ROSALÍA");
        let (key, fingerprint) = track_keys(&track);
        let song = parse_song(&serde_json::json!({
            "id": 321, "title": "DESPECHÁ", "primary_artist": {"name": "ROSALÍA"}
        }))
        .unwrap();
        db.put_genius_cache("detail", "321", &serde_json::to_string(&song).unwrap());
        let match_cache = MatchCache {
            status: GeniusMatchStatusRecord::Matched,
            song_id: Some(321),
            candidates: Vec::new(),
        };
        db.put_genius_cache(
            "match",
            &format!("{key}:{fingerprint}"),
            &serde_json::to_string(&match_cache).unwrap(),
        );
        assert!(
            engine.cached(&track).is_none(),
            "old matching rules must expire"
        );
        db.put_genius_cache(
            "match",
            &match_cache_key(&key, &fingerprint),
            &serde_json::to_string(&match_cache).unwrap(),
        );
        assert!(engine
            .resolve(track.clone(), false)
            .await
            .unwrap()
            .song
            .is_some());
        assert!(engine.resolve(track, false).await.unwrap().song.is_some());
        assert_eq!(engine.metrics().requests, 0);
    }

    #[test]
    fn duplicate_exact_candidates_require_user_choice() {
        let track = track("Song", "Artist feat. Guest");
        let mut candidates = vec![1, 2]
            .into_iter()
            .map(|id| GeniusCandidateRecord {
                id,
                title: "Song".into(),
                artist: "Artist".into(),
                url: None,
                confidence: 0.0,
            })
            .collect();
        rank_candidates(&track, &mut candidates);
        assert!(!is_auto_match(&track, &candidates));
    }

    #[test]
    fn reported_misses_match_only_when_title_and_credits_are_safe() {
        let cases = [
            ("Les", "Childish Gambino", "L.E.S.", "Childish Gambino"),
            (
                "luther",
                "Kendrick Lamar & SZA",
                "luther",
                "Kendrick Lamar & SZA",
            ),
            (
                "SISTERS AND BROTHERS",
                "Kanye West & Ye",
                "SISTERS AND BROTHERS",
                "Kanye West",
            ),
            (
                "HIGHS AND LOWS",
                "Kanye West & Ye",
                "HIGHS AND LOWS",
                "Kanye West",
            ),
            ("CIRCLES", "Kanye West & Ye", "CIRCLES", "Kanye West"),
            (
                "BEAUTY AND THE BEAST",
                "Kanye West & Ye",
                "BEAUTY AND THE BEAST",
                "Kanye West",
            ),
            (
                "Pain 1993 (feat. Playboi Carti)",
                "Drake",
                "Pain 1993",
                "Drake (Ft. Playboi Carti)",
            ),
            (
                "Rich Nigga Shit (feat. Young Thug)",
                "21 Savage & Metro Boomin",
                "Rich Nigga Shit",
                "21 Savage & Metro Boomin (Ft. Young Thug)",
            ),
            (
                "Wants and Needs (feat. Lil Baby)",
                "Drake",
                "Wants and Needs",
                "Drake (Ft. Lil Baby)",
            ),
            (
                "Feel The Fiyaaaah (feat. Takeoff)",
                "Metro Boomin & A$AP Rocky",
                "Feel The Fiyaaaah",
                "Metro Boomin & A$AP Rocky (Ft. Takeoff)",
            ),
            (
                "Take It Easy Freestyle",
                "A$AP Rocky",
                "Take It Easy Freestyle",
                "A$AP Rocky (Ft. A$AP Ferg)",
            ),
            (
                "Bohemian Rhapsody (Remastered 2011)",
                "Queen",
                "Bohemian Rhapsody",
                "Queen",
            ),
            (
                "Now Or Never (Bonus Track) (feat. Mary J. Blige)",
                "Kendrick Lamar",
                "Now or Never",
                "Kendrick Lamar (Ft. Mary J. Blige)",
            ),
        ];
        for (title, artists, genius_title, genius_artist) in cases {
            let track = track(title, artists);
            let mut candidates = vec![GeniusCandidateRecord {
                id: 1,
                title: genius_title.into(),
                artist: genius_artist.into(),
                url: None,
                confidence: 0.0,
            }];
            rank_candidates(&track, &mut candidates);
            assert!(is_auto_match(&track, &candidates), "{title} / {artists}");
        }
        assert!(!artist_credit_matches(
            "Kendrick Lamar & SZA",
            "Kendrick Lamar"
        ));
        assert!(!title_equivalent("OFF", "Off The Grid"));
        let off = track("OFF", "Kanye West & Ye");
        let mut unrelated = vec![GeniusCandidateRecord {
            id: 2,
            title: "Off The Grid".into(),
            artist: "Kanye West".into(),
            url: None,
            confidence: 0.0,
        }];
        rank_candidates(&off, &mut unrelated);
        assert!(!is_auto_match(&off, &unrelated));
    }

    #[test]
    fn original_track_beats_sequel_or_part_two() {
        let track = track("Flashing Lights (feat. Dwele)", "Kanye West");
        let mut candidates = vec![
            GeniusCandidateRecord {
                id: 9_246_747,
                title: "Flashing Lights 2".into(),
                artist: "Kanye West".into(),
                url: None,
                confidence: 0.0,
            },
            GeniusCandidateRecord {
                id: 523,
                title: "Flashing Lights".into(),
                artist: "Kanye West (Ft. Dwele)".into(),
                url: None,
                confidence: 0.0,
            },
        ];
        rank_candidates(&track, &mut candidates);
        assert_eq!(candidates[0].id, 523);
        assert!(is_auto_match(&track, &candidates));
    }

    #[test]
    fn deluxe_and_original_cuts_with_same_title_stay_ambiguous() {
        let mut track = track("I CAN'T WAIT", "Kanye West & Ye");
        track.album = Some("BULLY - DELUXE".into());
        let mut candidates = vec![
            GeniusCandidateRecord {
                id: 12_883_010,
                title: "I CAN’T WAIT".into(),
                artist: "Kanye West".into(),
                url: None,
                confidence: 0.0,
            },
            GeniusCandidateRecord {
                id: 13_356_920,
                title: "I CAN’T WAIT".into(),
                artist: "Kanye West & Lauryn Hill".into(),
                url: None,
                confidence: 0.0,
            },
        ];
        rank_candidates(&track, &mut candidates);
        assert!(!is_auto_match(&track, &candidates));
    }

    #[test]
    fn query_cleanup_removes_metadata_but_keeps_recording_versions() {
        assert_eq!(clean_query_title("Levitating [Explicit]"), "Levitating");
        assert_eq!(clean_query_title("Runaway (feat. Pusha T)"), "Runaway");
        assert_eq!(
            clean_query_title("Song (Live) [Official Video]"),
            "Song (Live)"
        );
        assert_eq!(
            clean_query_title("Now Or Never (Bonus Track) (feat. Mary J. Blige)"),
            "Now Or Never"
        );
        assert_eq!(
            clean_query_title("Bohemian Rhapsody (Remastered 2011)"),
            "Bohemian Rhapsody"
        );
        assert!(version_flags("Song (Live)").contains("live"));
    }

    #[test]
    fn cache_evicts_old_song_and_its_documents_after_500_songs() {
        let db = Db::open(std::path::Path::new(":memory:")).unwrap();
        db.put_genius_cache("detail", "1", "{}");
        db.put_genius_cache("lyrics", "1", "{}");
        for id in 2..=501 {
            db.put_genius_cache("detail", &id.to_string(), "{}");
        }
        assert!(db.get_genius_cache("detail", "1", CONTENT_TTL).is_none());
        assert!(db.get_genius_cache("lyrics", "1", LYRICS_TTL).is_none());
        assert!(db.get_genius_cache("detail", "501", CONTENT_TTL).is_some());
    }

    #[tokio::test]
    #[ignore = "requires live Genius endpoints; run explicitly during provider debugging"]
    async fn live_pipeline_fetches_context_annotations_and_lyrics() {
        let db = Arc::new(Db::open(std::path::Path::new(":memory:")).unwrap());
        let engine = GeniusEngine::new(db);
        let resolution = engine
            .resolve(track("DESPECHÁ", "ROSALÍA"), false)
            .await
            .unwrap();
        assert_eq!(resolution.status, GeniusMatchStatusRecord::Matched);
        let song = resolution.song.unwrap();
        assert_eq!(song.id, 8_173_139);
        println!(
            "Genius context probe: story={}, producers={}, writers={}, performances={}",
            song.description.is_some(),
            song.producers.len(),
            song.writers.len(),
            song.performances.len()
        );
        let annotations = engine.annotations(song.id, 1, false).await.unwrap();
        let song_url = song.url.unwrap();
        let lyrics = engine
            .lyrics(song.id, song_url.clone(), false)
            .await
            .unwrap();
        assert!(!lyrics.lines.is_empty());
        let linked_lines = lyrics
            .lines
            .iter()
            .filter(|line| line.referent_id.is_some())
            .count();
        let linked_annotations = lyrics
            .lines
            .iter()
            .filter(|line| {
                line.referent_id.is_some_and(|id| {
                    annotations
                        .items
                        .iter()
                        .any(|annotation| annotation.referent_id == id || annotation.id == id)
                })
            })
            .count();
        println!(
            "Genius live probe: annotations={}, lyric_lines={}, linked_lines={}, linked_annotations={}, requests={}, cache_hits={}",
            annotations.items.len(),
            lyrics.lines.len(),
            linked_lines,
            linked_annotations,
            engine.metrics().requests,
            engine.metrics().cache_hits
        );
        let request_count = engine.metrics().requests;
        let _ = engine
            .resolve(track("DESPECHÁ", "ROSALÍA"), false)
            .await
            .unwrap();
        let _ = engine.annotations(song.id, 1, false).await.unwrap();
        let _ = engine.lyrics(song.id, song_url, false).await.unwrap();
        assert_eq!(
            engine.metrics().requests,
            request_count,
            "fresh cache must make no requests"
        );
    }

    #[tokio::test]
    #[ignore = "requires live Genius search; run explicitly while calibrating matching"]
    async fn live_resolution_matrix() {
        let db = Arc::new(Db::open(std::path::Path::new(":memory:")).unwrap());
        let engine = GeniusEngine::new(db);
        let cases = [
            ("Thinkin Bout You (Official Video)", "Frank Ocean"),
            ("Blinding Lights [Official Audio]", "The Weeknd"),
            ("HUMBLE. (Lyric Video)", "Kendrick Lamar"),
            ("Starboy | Official Music Video", "The Weeknd"),
            ("Runaway (feat. Pusha T)", "Kanye West"),
            ("Levitating [Explicit]", "Dua Lipa"),
            ("Bohemian Rhapsody (Remastered 2011)", "Queen"),
            ("Hotel California - Live at The Forum", "Eagles"),
        ];
        for (index, (title, artist)) in cases.into_iter().enumerate() {
            let result = engine.resolve(track(title, artist), false).await.unwrap();
            println!(
                "Genius matrix case={index} status={:?} id={:?} top={:?} confidence={:.3}",
                result.status,
                result.song.as_ref().map(|song| song.id),
                result.candidates.first().map(|item| item.id),
                result
                    .candidates
                    .first()
                    .map_or(0.0, |item| item.confidence)
            );
        }
        println!("Genius matrix requests={}", engine.metrics().requests);
    }

    #[tokio::test]
    #[ignore = "requires live Genius search; run explicitly while calibrating matching"]
    async fn live_metadata_cleanup_recovers_common_tracks() {
        let db = Arc::new(Db::open(std::path::Path::new(":memory:")).unwrap());
        let engine = GeniusEngine::new(db);
        for (title, artist) in [
            ("Runaway (feat. Pusha T)", "Kanye West"),
            ("Levitating [Explicit]", "Dua Lipa"),
        ] {
            let resolution = engine.resolve(track(title, artist), false).await.unwrap();
            println!(
                "Genius metadata probe: status={:?} id={:?} requests={}",
                resolution.status,
                resolution.song.as_ref().map(|song| song.id),
                engine.metrics().requests
            );
            assert_eq!(resolution.status, GeniusMatchStatusRecord::Matched);
        }
    }

    #[tokio::test]
    #[ignore = "requires a live Genius HTML page; run explicitly when validating the extractor"]
    async fn live_lyrics_exclude_page_header() {
        let db = Arc::new(Db::open(std::path::Path::new(":memory:")).unwrap());
        let engine = GeniusEngine::new(db);
        let lyrics = engine
            .lyrics(
                53_152,
                "https://genius.com/Frank-ocean-thinkin-bout-you-lyrics".into(),
                false,
            )
            .await
            .unwrap();
        assert!(!lyrics.lines.is_empty());
        assert!(
            lyrics.lines[0].is_header,
            "the first line should be the verse header, not page furniture"
        );
        assert!(!lyrics
            .lines
            .iter()
            .any(|line| line.text.contains("Contributors")));
    }
}
