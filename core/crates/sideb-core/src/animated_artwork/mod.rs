//! Optional album motion: shared single flight, cancellation, leases and a private bounded cache.
//! Shells retain the request ID until their native player releases the local asset.
mod cache;
mod provider;
use cache::{Cache, MAX_FILE};
use md5::{Digest, Md5};
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    sync::{watch, Semaphore},
};
use unicode_normalization::UnicodeNormalization;

#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Record)]
pub struct AnimatedArtworkRequest {
    pub video_id: String,
    pub title: String,
    pub artists: String,
    pub album: Option<String>,
    pub album_id: Option<String>,
    pub duration_secs: Option<u64>,
    pub storefront: String,
    pub prefer_hevc: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize, uniffi::Record)]
pub struct AnimatedArtworkAsset {
    pub asset_id: String,
    pub local_path: String,
    pub codec: String,
    pub width: u32,
    pub height: u32,
    pub frame_rate: f64,
    pub size_bytes: u64,
}
#[derive(Clone, Debug, thiserror::Error)]
pub enum AnimatedArtworkError {
    #[error("Animated artwork request cancelled")]
    Cancelled,
    #[error("Animated artwork cache capacity exceeded")]
    Capacity,
    #[error("Animated artwork media is unsupported or invalid")]
    InvalidMedia,
    #[error("Animated artwork temporarily unavailable")]
    Unavailable,
    #[error("Animated artwork cache I/O failed: {0}")]
    Io(String),
}
impl From<std::io::Error> for AnimatedArtworkError {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e.to_string())
    }
}
type Outcome = Result<Option<AnimatedArtworkAsset>, AnimatedArtworkError>;
type SharedCache = Arc<tokio::sync::Mutex<Cache>>;
#[derive(Clone, Serialize, Deserialize)]
struct StoredVariant {
    url: String,
    width: u32,
    height: u32,
    frame_rate: f64,
    codec: String,
    bandwidth: u64,
}
#[derive(Clone, Serialize, Deserialize)]
struct StoredMotion {
    collection_id: String,
    variants: Vec<StoredVariant>,
}
impl From<provider::ResolvedMotion> for StoredMotion {
    fn from(m: provider::ResolvedMotion) -> Self {
        Self {
            collection_id: m.collection_id,
            variants: m
                .variants
                .into_iter()
                .map(|v| StoredVariant {
                    url: v.url,
                    width: v.width,
                    height: v.height,
                    frame_rate: v.frame_rate,
                    codec: v.codec,
                    bandwidth: v.bandwidth,
                })
                .collect(),
        }
    }
}
struct Flight {
    serial: u64,
    consumers: HashSet<String>,
    cancel: watch::Sender<bool>,
    result: watch::Sender<Option<Outcome>>,
    root: String,
}
struct Request {
    cancelled: watch::Sender<bool>,
    key: String,
    lease: Option<cache::Leases>,
}
#[derive(Default)]
struct State {
    serial: u64,
    flights: HashMap<String, Flight>,
    requests: HashMap<String, Request>,
    epochs: HashMap<String, u64>,
    backoff: HashMap<String, Instant>,
    provider_until: Option<Instant>,
    cancelled_ids: HashMap<String, Instant>,
}
struct Inner {
    state: Mutex<State>,
    caches: tokio::sync::Mutex<HashMap<String, SharedCache>>,
    gate: Semaphore,
}
/// Cheap and disk-free until the first explicitly eligible prepare/cache command.
#[derive(Clone)]
pub struct Engine {
    inner: Arc<Inner>,
}
impl Default for Engine {
    fn default() -> Self {
        Self::new()
    }
}
impl Engine {
    pub fn new() -> Self {
        fn make_inner() -> Arc<Inner> {
            Arc::new(Inner {
                state: Mutex::new(State::default()),
                caches: tokio::sync::Mutex::new(HashMap::new()),
                gate: Semaphore::new(1),
            })
        }
        // Multiple foreign-language handles still share one process-wide preparation and lease registry.
        #[cfg(not(test))]
        let inner = {
            static SHARED: std::sync::OnceLock<Arc<Inner>> = std::sync::OnceLock::new();
            SHARED.get_or_init(make_inner).clone()
        };
        #[cfg(test)]
        let inner = make_inner();
        Self { inner }
    }
    async fn cache(&self, root: &str) -> Result<SharedCache, AnimatedArtworkError> {
        let mut caches = self.inner.caches.lock().await;
        if let Some(cache) = caches.get(root) {
            return Ok(cache.clone());
        }
        let cache = Arc::new(tokio::sync::Mutex::new(Cache::open(root).await?));
        caches.insert(root.to_owned(), cache.clone());
        Ok(cache)
    }
    pub async fn prepare(
        &self,
        request: AnimatedArtworkRequest,
        request_id: String,
        cache_dir: String,
    ) -> Outcome {
        if request_id.is_empty() || cache_dir.is_empty() {
            return Err(AnimatedArtworkError::Unavailable);
        }
        // Request IDs identify one lifetime. Reusing one deliberately releases its previous lifetime.
        self.release_request(&request_id);
        let key = format!("{}:{}", hash(&cache_dir), request_key(&request));
        let (request_cancel, mut request_cancelled) = watch::channel(false);
        let (mut receiver, launch) = {
            let mut state = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
            state.backoff.retain(|_, until| *until > Instant::now());
            state
                .cancelled_ids
                .retain(|_, until| *until > Instant::now());
            if state.cancelled_ids.contains_key(&request_id) {
                return Err(AnimatedArtworkError::Cancelled);
            }
            if state.requests.len() >= 1024 {
                return Err(AnimatedArtworkError::Capacity);
            }
            state.requests.insert(
                request_id.clone(),
                Request {
                    cancelled: request_cancel,
                    key: key.clone(),
                    lease: None,
                },
            );
            if let Some(flight) = state.flights.get_mut(&key) {
                flight.consumers.insert(request_id.clone());
                (flight.result.subscribe(), None)
            } else {
                let (cancel, cancelled) = watch::channel(false);
                let (result, receiver) = watch::channel(None);
                let epoch = *state.epochs.get(&cache_dir).unwrap_or(&0);
                state.serial += 1;
                let serial = state.serial;
                state.flights.insert(
                    key.clone(),
                    Flight {
                        serial,
                        consumers: HashSet::from([request_id.clone()]),
                        cancel,
                        result,
                        root: cache_dir.clone(),
                    },
                );
                (receiver, Some((cancelled, epoch, serial)))
            }
        };
        if let Some((cancelled, epoch, serial)) = launch {
            let engine = self.clone();
            let flight_key = key.clone();
            tokio::spawn(async move {
                engine
                    .run(request, flight_key, cache_dir, epoch, serial, cancelled)
                    .await;
            });
        }
        loop {
            if *request_cancelled.borrow() {
                return Err(AnimatedArtworkError::Cancelled);
            }
            let value = receiver.borrow().clone();
            if let Some(outcome) = value {
                let mut state = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
                return if state.requests.contains_key(&request_id) {
                    if !matches!(&outcome, Ok(Some(_))) {
                        state.requests.remove(&request_id);
                    }
                    outcome
                } else {
                    Err(AnimatedArtworkError::Cancelled)
                };
            }
            tokio::select! {
                _ = request_cancelled.changed() => return Err(AnimatedArtworkError::Cancelled),
                changed = receiver.changed() => if changed.is_err() {return Err(AnimatedArtworkError::Cancelled);}
            }
        }
    }
    /// Cancels network work when the last consumer leaves; also releases a completed native player's lease.
    pub fn cancel(&self, request_id: &str) {
        {
            let mut state = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
            state
                .cancelled_ids
                .retain(|_, until| *until > Instant::now());
            if state.cancelled_ids.len() >= 1024 {
                if let Some(oldest) = state
                    .cancelled_ids
                    .iter()
                    .min_by_key(|(_, until)| **until)
                    .map(|(key, _)| key.clone())
                {
                    state.cancelled_ids.remove(&oldest);
                }
            }
            state.cancelled_ids.insert(
                request_id.to_owned(),
                Instant::now() + Duration::from_secs(300),
            );
        }
        self.release_request(request_id);
    }
    fn release_request(&self, request_id: &str) {
        let cache = {
            let mut state = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
            let Some(request) = state.requests.remove(request_id) else {
                return;
            };
            let _ = request.cancelled.send(true);
            let mut empty = false;
            if let Some(flight) = state.flights.get_mut(&request.key) {
                flight.consumers.remove(request_id);
                if flight.consumers.is_empty() {
                    let _ = flight.cancel.send(true);
                    empty = true;
                }
            }
            if empty {
                state.flights.remove(&request.key);
            }
            request.lease
        };
        if let Some(leases) = cache {
            cache::release(&leases, request_id);
        }
    }
    pub async fn cache_size(&self, cache_dir: String) -> Result<u64, AnimatedArtworkError> {
        self.cache(&cache_dir)
            .await?
            .lock()
            .await
            .disk_bytes()
            .await
    }
    pub async fn clear(&self, cache_dir: String) -> Result<u64, AnimatedArtworkError> {
        {
            let mut state = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
            *state.epochs.entry(cache_dir.clone()).or_default() += 1;
            let keys: Vec<_> = state
                .flights
                .iter()
                .filter(|(_, f)| f.root == cache_dir)
                .map(|(k, _)| k.clone())
                .collect();
            for key in keys {
                if let Some(flight) = state.flights.remove(&key) {
                    let _ = flight.cancel.send(true);
                    let _ = flight
                        .result
                        .send(Some(Err(AnimatedArtworkError::Cancelled)));
                    for id in flight.consumers {
                        if let Some(request) = state.requests.remove(&id) {
                            let _ = request.cancelled.send(true);
                        }
                    }
                }
            }
        }
        let _permit = self
            .inner
            .gate
            .acquire()
            .await
            .map_err(|_| AnimatedArtworkError::Cancelled)?;
        self.cache(&cache_dir).await?.lock().await.clear().await
    }
    async fn run(
        &self,
        request: AnimatedArtworkRequest,
        key: String,
        root: String,
        epoch: u64,
        serial: u64,
        mut cancelled: watch::Receiver<bool>,
    ) {
        let permit = tokio::select! { biased;
            _ = cancelled.changed() => return,
            permit = self.inner.gate.acquire() => permit,
        };
        let Ok(_permit) = permit else {
            return;
        };
        if *cancelled.borrow() {
            return;
        }
        let mut pending_asset = None;
        let work = async {
            let cache = self.cache(&root).await?;
            check_cancelled(&cancelled)?;
            let client = media_client()?;
            // Valid files outlive a provider locator/verdict TTL. Refresh only when the file is missing.
            let stored = { cache.lock().await.stored_metadata(&key) };
            if let Some(motion) = stored.as_ref().and_then(|m| m.motion.as_ref()) {
                if let Some(variant) = select_variant(&motion.variants, request.prefer_hevc) {
                    if let Some(asset) = cache
                        .lock()
                        .await
                        .lookup(&asset_key(&motion.collection_id, variant))
                        .await?
                    {
                        return Ok(Some(asset));
                    }
                }
            }
            let metadata = { cache.lock().await.metadata(&key) };
            let motion = if let Some(metadata) = metadata {
                metadata.motion
            } else {
                self.network_ready(&key)?;
                let lookup = network_wait(
                    &mut cancelled,
                    tokio::time::Instant::now() + Duration::from_secs(10),
                    provider::resolve(&client, &request),
                )
                .await?;
                match lookup {
                    Ok(provider::Lookup::Found(found)) => {
                        let found = StoredMotion::from(found);
                        cache
                            .lock()
                            .await
                            .set_metadata(key.clone(), Some(found.clone()))
                            .await?;
                        Some(found)
                    }
                    Ok(provider::Lookup::Absent) => {
                        cache.lock().await.set_metadata(key.clone(), None).await?;
                        None
                    }
                    Ok(provider::Lookup::Unresolved) => {
                        return Err(AnimatedArtworkError::Unavailable)
                    }
                    Err(error) => {
                        self.provider_backoff(&key, &error);
                        return Err(AnimatedArtworkError::Unavailable);
                    }
                }
            };
            let Some(mut motion) = motion else {
                return Ok(None);
            };
            for renewal in 0..=1 {
                let variant = select_variant(&motion.variants, request.prefer_hevc)
                    .ok_or(AnimatedArtworkError::InvalidMedia)?;
                let id = asset_key(&motion.collection_id, variant);
                if let Some(asset) = cache.lock().await.lookup(&id).await? {
                    return Ok(Some(asset));
                }
                check_cancelled(&cancelled)?;
                self.network_ready(&key)?;
                pending_asset = Some((cache.clone(), id.clone()));
                match download(&client, &cache, variant, &id, &mut cancelled).await {
                    Ok(asset) => return Ok(Some(asset)),
                    Err(DownloadError::Expired) if renewal == 0 => {
                        cache.lock().await.abort(&id).await;
                        check_cancelled(&cancelled)?;
                        self.network_ready(&key)?;
                        let lookup = network_wait(
                            &mut cancelled,
                            tokio::time::Instant::now() + Duration::from_secs(10),
                            provider::resolve(&client, &request),
                        )
                        .await?;
                        match lookup {
                            Ok(provider::Lookup::Found(found)) => {
                                motion = found.into();
                                cache
                                    .lock()
                                    .await
                                    .set_metadata(key.clone(), Some(motion.clone()))
                                    .await?;
                            }
                            Err(error) => {
                                self.provider_backoff(&key, &error);
                                return Err(AnimatedArtworkError::Unavailable);
                            }
                            _ => return Err(AnimatedArtworkError::Unavailable),
                        }
                    }
                    Err(DownloadError::RateLimited(seconds)) => {
                        self.provider_backoff(
                            &key,
                            &provider::ProviderError::RateLimited {
                                retry_after_secs: seconds,
                            },
                        );
                        return Err(AnimatedArtworkError::Unavailable);
                    }
                    Err(DownloadError::Other(error)) => return Err(error),
                    Err(DownloadError::Expired) => return Err(AnimatedArtworkError::Unavailable),
                }
            }
            Err(AnimatedArtworkError::Unavailable)
        };
        // Cancel only HTTP futures. Tokio filesystem operations can outlive a dropped future:
        // finish each operation and cleanup under the gate before clear may inspect the cache.
        let outcome = work.await;
        let outcome = if *cancelled.borrow() {
            Err(AnimatedArtworkError::Cancelled)
        } else {
            outcome
        };
        if let Some((cache, id)) = pending_asset {
            cache.lock().await.abort(&id).await;
        }
        let cache = self.cache(&root).await.ok();
        let mut cache_guard = match cache.as_ref() {
            Some(cache) => Some(cache.lock().await),
            None => None,
        };
        let mut state = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
        let current = state.flights.get(&key).is_some_and(|f| f.serial == serial);
        if current {
            if let Some(flight) = state.flights.remove(&key) {
                let outcome = if *state.epochs.get(&root).unwrap_or(&0) != epoch {
                    Err(AnimatedArtworkError::Cancelled)
                } else {
                    outcome
                };
                if outcome.is_err() && !matches!(outcome, Err(AnimatedArtworkError::Cancelled)) {
                    state.backoff.retain(|_, until| *until > Instant::now());
                    if state.backoff.len() >= 1024 {
                        if let Some(oldest) = state
                            .backoff
                            .iter()
                            .min_by_key(|(_, until)| **until)
                            .map(|(key, _)| key.clone())
                        {
                            state.backoff.remove(&oldest);
                        }
                    }
                    state
                        .backoff
                        .entry(key)
                        .or_insert(Instant::now() + Duration::from_secs(60));
                }
                if let Ok(Some(asset)) = &outcome {
                    for id in &flight.consumers {
                        if let Some(request) = state.requests.get_mut(id) {
                            request.lease = cache_guard.as_ref().map(|cache| cache.leases.clone());
                            if let Some(cache_guard) = cache_guard.as_mut() {
                                cache_guard.lease(&asset.asset_id, id.clone());
                            }
                        }
                    }
                }
                let _ = flight.result.send(Some(outcome));
            }
        }
    }
    fn backoff(&self, key: &str, seconds: u64) {
        let mut state = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
        state.backoff.retain(|_, until| *until > Instant::now());
        if state.backoff.len() >= 1024 {
            if let Some(oldest) = state
                .backoff
                .iter()
                .min_by_key(|(_, until)| **until)
                .map(|(key, _)| key.clone())
            {
                state.backoff.remove(&oldest);
            }
        }
        state.backoff.insert(
            key.to_owned(),
            Instant::now() + Duration::from_secs(seconds.clamp(1, 3600)),
        );
    }
    fn network_ready(&self, key: &str) -> Result<(), AnimatedArtworkError> {
        let state = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
        if state
            .provider_until
            .is_some_and(|until| until > Instant::now())
            || state
                .backoff
                .get(key)
                .is_some_and(|until| *until > Instant::now())
        {
            Err(AnimatedArtworkError::Unavailable)
        } else {
            Ok(())
        }
    }
    fn provider_backoff(&self, key: &str, error: &provider::ProviderError) {
        if let provider::ProviderError::RateLimited { retry_after_secs } = error {
            self.backoff(key, *retry_after_secs);
            let mut state = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
            let until = Instant::now() + Duration::from_secs((*retry_after_secs).clamp(1, 3600));
            state.provider_until = Some(state.provider_until.map_or(until, |old| old.max(until)));
        } else {
            self.backoff(key, 60);
        }
    }
}
fn normalize(value: &str) -> String {
    value
        .nfkc()
        .collect::<String>()
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}
fn hash(value: &str) -> String {
    format!("{:x}", Md5::digest(value.as_bytes()))
}
fn request_key(r: &AnimatedArtworkRequest) -> String {
    let identity = if !r.album.as_deref().unwrap_or("").trim().is_empty() {
        format!(
            "{}|{}|{}",
            normalize(r.album.as_deref().unwrap_or("")),
            normalize(&r.artists),
            r.album_id.as_deref().unwrap_or("")
        )
    } else {
        format!(
            "track:{}|{}|{}|{:?}",
            r.video_id,
            normalize(&r.title),
            normalize(&r.artists),
            r.duration_secs
        )
    };
    hash(&format!(
        "v1|{}|{}|{}",
        normalize(&r.storefront),
        r.prefer_hevc,
        identity
    ))
}
fn asset_key(collection: &str, v: &StoredVariant) -> String {
    hash(&format!(
        "v1|{collection}|{}|{}|{}|{}|{}",
        v.codec, v.width, v.height, v.frame_rate, v.bandwidth
    ))
}
fn select_variant(variants: &[StoredVariant], prefer_hevc: bool) -> Option<&StoredVariant> {
    variants
        .iter()
        .filter(|v| {
            v.width == v.height
                && v.width > 0
                && v.width <= 1080
                && v.frame_rate.is_finite()
                && v.frame_rate > 0.
                && v.frame_rate <= 60.1
                && if prefer_hevc {
                    v.codec.starts_with("hvc")
                        || v.codec.starts_with("hev")
                        || v.codec.starts_with("avc")
                        || v.codec == "h264"
                        || v.codec == "hevc"
                } else {
                    v.codec.starts_with("avc") || v.codec == "h264"
                }
        })
        .max_by(|a, b| {
            let codec = |v: &StoredVariant| {
                prefer_hevc && (v.codec.starts_with("hvc") || v.codec.starts_with("hev"))
            };
            a.width
                .cmp(&b.width)
                .then(a.frame_rate.total_cmp(&b.frame_rate))
                .then(codec(a).cmp(&codec(b)))
                .then(a.bandwidth.cmp(&b.bandwidth))
        })
}
fn checked_media_url(value: &str) -> Result<reqwest::Url, provider::ProviderError> {
    #[cfg(test)]
    if let Ok(url) = reqwest::Url::parse(value) {
        if url.scheme() == "http" && url.host_str() == Some("127.0.0.1") {
            return Ok(url);
        }
    }
    provider::checked_url(value)
}
fn media_client() -> Result<reqwest::Client, AnimatedArtworkError> {
    reqwest::Client::builder().redirect(reqwest::redirect::Policy::custom(|attempt| {
        if attempt.previous().len()>=5 || checked_media_url(attempt.url().as_str()).is_err() {attempt.stop()} else {attempt.follow()}
    })).connect_timeout(Duration::from_secs(10)).user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15").build().map_err(|_|AnimatedArtworkError::Unavailable)
}
enum DownloadError {
    Expired,
    RateLimited(u64),
    Other(AnimatedArtworkError),
}
impl From<std::io::Error> for DownloadError {
    fn from(e: std::io::Error) -> Self {
        Self::Other(e.into())
    }
}
fn check_cancelled(cancelled: &watch::Receiver<bool>) -> Result<(), AnimatedArtworkError> {
    if *cancelled.borrow() {
        Err(AnimatedArtworkError::Cancelled)
    } else {
        Ok(())
    }
}
async fn network_wait<T>(
    cancelled: &mut watch::Receiver<bool>,
    deadline: tokio::time::Instant,
    future: impl std::future::Future<Output = T>,
) -> Result<T, AnimatedArtworkError> {
    check_cancelled(cancelled)?;
    tokio::select! {biased;
        _=cancelled.changed()=>Err(AnimatedArtworkError::Cancelled),
        result=tokio::time::timeout_at(deadline,future)=>result.map_err(|_|AnimatedArtworkError::Unavailable),
    }
}
fn check_download(
    cancelled: &watch::Receiver<bool>,
    deadline: tokio::time::Instant,
) -> Result<(), AnimatedArtworkError> {
    check_cancelled(cancelled)?;
    if tokio::time::Instant::now() >= deadline {
        Err(AnimatedArtworkError::Unavailable)
    } else {
        Ok(())
    }
}
async fn download(
    client: &reqwest::Client,
    cache: &SharedCache,
    v: &StoredVariant,
    id: &str,
    cancelled: &mut watch::Receiver<bool>,
) -> Result<AnimatedArtworkAsset, DownloadError> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(90);
    checked_media_url(&v.url)
        .map_err(|_| DownloadError::Other(AnimatedArtworkError::InvalidMedia))?;
    let idle_deadline = || deadline.min(tokio::time::Instant::now() + Duration::from_secs(15));
    let mut response = network_wait(cancelled, idle_deadline(), client.get(&v.url).send())
        .await
        .map_err(DownloadError::Other)?
        .map_err(|_| DownloadError::Other(AnimatedArtworkError::Unavailable))?;
    if matches!(response.status().as_u16(), 403 | 404) {
        return Err(DownloadError::Expired);
    }
    if response.status().as_u16() == 429 {
        return Err(DownloadError::RateLimited(retry_after(response.headers())));
    }
    if !response.status().is_success() || checked_media_url(response.url().as_str()).is_err() {
        return Err(DownloadError::Other(AnimatedArtworkError::Unavailable));
    }
    let length = response.content_length();
    let reserve = length.unwrap_or(MAX_FILE);
    let path = cache
        .lock()
        .await
        .reserve(id, reserve)
        .await
        .map_err(DownloadError::Other)?;
    check_download(cancelled, deadline).map_err(DownloadError::Other)?;
    let mut file = tokio::fs::OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&path)
        .await?;
    #[cfg(test)]
    cache.lock().await.pause_io("opened").await;
    check_download(cancelled, deadline).map_err(DownloadError::Other)?;
    let mut bytes = 0u64;
    let streamed: Result<(), DownloadError> = async {
        loop {
            let chunk = network_wait(cancelled, idle_deadline(), response.chunk())
                .await
                .map_err(DownloadError::Other)?
                .map_err(|_| DownloadError::Other(AnimatedArtworkError::Unavailable))?;
            let Some(chunk) = chunk else {
                break;
            };
            bytes = bytes
                .checked_add(chunk.len() as u64)
                .ok_or(DownloadError::Other(AnimatedArtworkError::Capacity))?;
            if bytes > reserve || bytes > MAX_FILE {
                return Err(DownloadError::Other(AnimatedArtworkError::Capacity));
            }
            // Do not cancel a filesystem future: its blocking task may still write after cleanup.
            file.write_all(&chunk).await?;
            check_download(cancelled, deadline).map_err(DownloadError::Other)?;
        }
        if bytes == 0 || length.is_some_and(|n| n != bytes) {
            return Err(DownloadError::Other(AnimatedArtworkError::InvalidMedia));
        }
        Ok(())
    }
    .await;
    // Tokio File may buffer a pending blocking write after write_all returns. Drain it even
    // when HTTP/cancellation failed, then close before abort can delete the partial file.
    drop(response);
    let flushed = file.flush().await;
    drop(file);
    streamed?;
    flushed?;
    check_download(cancelled, deadline).map_err(DownloadError::Other)?;
    validate_mp4(&path, bytes, cancelled, deadline)
        .await
        .map_err(DownloadError::Other)?;
    check_download(cancelled, deadline).map_err(DownloadError::Other)?;
    // Once promotion starts, finish rename/index atomically with respect to the engine gate.
    let asset = AnimatedArtworkAsset {
        asset_id: id.into(),
        local_path: String::new(),
        codec: v.codec.clone(),
        width: v.width,
        height: v.height,
        frame_rate: v.frame_rate,
        size_bytes: bytes,
    };
    cache
        .lock()
        .await
        .commit(asset)
        .await
        .map_err(DownloadError::Other)
}

fn retry_after(headers: &reqwest::header::HeaderMap) -> u64 {
    headers
        .get(reqwest::header::RETRY_AFTER)
        .and_then(|h| h.to_str().ok())
        .and_then(|s| {
            s.parse::<u64>().ok().or_else(|| {
                httpdate::parse_http_date(s)
                    .ok()
                    .and_then(|d| d.duration_since(std::time::SystemTime::now()).ok())
                    .map(|d| d.as_secs())
            })
        })
        .unwrap_or(60)
        .clamp(1, 3600)
}
/// Walk top-level boxes without loading the movie; reject truncation, missing initialization and empty media.
async fn validate_mp4(
    path: &std::path::Path,
    size: u64,
    cancelled: &watch::Receiver<bool>,
    deadline: tokio::time::Instant,
) -> Result<(), AnimatedArtworkError> {
    let mut file = tokio::fs::File::open(path).await?;
    let mut offset = 0u64;
    let (mut ftyp, mut moov, mut mdat) = (false, false, false);
    while offset < size {
        check_download(cancelled, deadline)?;
        if size - offset < 8 {
            return Err(AnimatedArtworkError::InvalidMedia);
        }
        let mut header = [0u8; 8];
        file.read_exact(&mut header).await?;
        let n = u32::from_be_bytes(header[..4].try_into().unwrap());
        let (box_size, header_size) = if n == 1 {
            let mut wide = [0u8; 8];
            file.read_exact(&mut wide).await?;
            (u64::from_be_bytes(wide), 16)
        } else if n == 0 {
            (size - offset, 8)
        } else {
            (n as u64, 8)
        };
        if box_size < header_size || box_size > size - offset {
            return Err(AnimatedArtworkError::InvalidMedia);
        }
        match &header[4..] {
            b"ftyp" => ftyp = box_size >= 16,
            b"moov" => moov = box_size > 8,
            b"mdat" => mdat = box_size > 8,
            _ => {}
        }
        offset += box_size;
        tokio::io::AsyncSeekExt::seek(&mut file, std::io::SeekFrom::Start(offset)).await?;
    }
    if ftyp && moov && mdat {
        Ok(())
    } else {
        Err(AnimatedArtworkError::InvalidMedia)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn request() -> AnimatedArtworkRequest {
        AnimatedArtworkRequest {
            video_id: "track1".into(),
            title: "Title".into(),
            artists: "Artist".into(),
            album: Some("Album".into()),
            album_id: Some("ytm1".into()),
            duration_secs: None,
            storefront: "us".into(),
            prefer_hevc: false,
        }
    }
    #[test]
    fn same_album_shares_but_editions_country_codec_do_not() {
        let a = request();
        let mut b = a.clone();
        b.video_id = "track2".into();
        b.title = "Different".into();
        assert_eq!(request_key(&a), request_key(&b));
        for change in 0..3 {
            let mut b = a.clone();
            match change {
                0 => b.album = Some("Album Deluxe".into()),
                1 => b.storefront = "uy".into(),
                _ => b.prefer_hevc = true,
            };
            assert_ne!(request_key(&a), request_key(&b));
        }
    }
    #[test]
    fn absent_album_uses_track_identity() {
        let mut a = request();
        a.album = None;
        let mut b = a.clone();
        b.video_id = "other".into();
        assert_ne!(request_key(&a), request_key(&b));
    }
    #[test]
    fn preserves_native_1080_60() {
        let variant = |w, f| StoredVariant {
            url: String::new(),
            width: w,
            height: w,
            frame_rate: f,
            codec: "avc1.4d".into(),
            bandwidth: 100,
        };
        let v = vec![variant(768, 30.), variant(1080, 60.), variant(2160, 60.)];
        assert_eq!(select_variant(&v, false).unwrap().width, 1080);
        assert_eq!(select_variant(&v, false).unwrap().frame_rate, 60.);
    }
    #[test]
    fn cancellation_keeps_other_consumer() {
        let e = Engine::new();
        let (tx, _cancelled) = watch::channel(false);
        let (result, _) = watch::channel(None);
        {
            let mut s = e.inner.state.lock().unwrap();
            s.flights.insert(
                "k".into(),
                Flight {
                    serial: 1,
                    consumers: HashSet::from(["a".into(), "b".into()]),
                    cancel: tx.clone(),
                    result,
                    root: "r".into(),
                },
            );
            for id in ["a", "b"] {
                s.requests.insert(
                    id.into(),
                    Request {
                        cancelled: watch::channel(false).0,
                        key: "k".into(),
                        lease: None,
                    },
                );
            }
        }
        e.cancel("a");
        assert!(!*tx.borrow());
        e.cancel("b");
        assert!(*tx.borrow());
    }
    fn temp_root() -> String {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        std::env::temp_dir()
            .join(format!(
                "sideb-motion-engine-{}-{}",
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos(),
                NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
            ))
            .to_string_lossy()
            .into_owned()
    }
    fn tiny_mp4() -> Vec<u8> {
        let mut bytes = Vec::new();
        for (kind, payload) in [
            (b"ftyp", vec![0; 8]),
            (b"moov", vec![0]),
            (b"mdat", vec![42]),
        ] {
            bytes.extend_from_slice(&((8 + payload.len()) as u32).to_be_bytes());
            bytes.extend_from_slice(kind);
            bytes.extend(payload);
        }
        bytes
    }
    async fn fixture_server() -> (
        String,
        tokio::sync::oneshot::Receiver<()>,
        tokio::sync::oneshot::Sender<()>,
        tokio::task::JoinHandle<()>,
    ) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}/movie.mp4", listener.local_addr().unwrap());
        let (started_tx, started) = tokio::sync::oneshot::channel();
        let (release, release_rx) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut request = [0; 4096];
            let _ = stream.read(&mut request).await;
            let bytes = tiny_mp4();
            let header = format!(
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                bytes.len()
            );
            stream.write_all(header.as_bytes()).await.unwrap();
            let _ = started_tx.send(());
            let _ = release_rx.await;
            let _ = stream.write_all(&bytes).await;
        });
        (url, started, release, server)
    }
    async fn seed(engine: &Engine, root: &str, url: String) {
        let key = format!("{}:{}", hash(root), request_key(&request()));
        engine
            .cache(root)
            .await
            .unwrap()
            .lock()
            .await
            .set_metadata(
                key,
                Some(StoredMotion {
                    collection_id: "fixture".into(),
                    variants: vec![StoredVariant {
                        url,
                        width: 1080,
                        height: 1080,
                        frame_rate: 60.,
                        codec: "avc1.4d".into(),
                        bandwidth: 100,
                    }],
                }),
            )
            .await
            .unwrap();
    }
    #[tokio::test]
    async fn singleflight_cancel_one_consumer_retains_other_and_lease() {
        let engine = Engine::new();
        let root = temp_root();
        let (url, started, release, server) = fixture_server().await;
        seed(&engine, &root, url).await;
        let a = {
            let e = engine.clone();
            let r = root.clone();
            tokio::spawn(async move { e.prepare(request(), "a".into(), r).await })
        };
        started.await.unwrap();
        let b = {
            let e = engine.clone();
            let r = root.clone();
            tokio::spawn(async move { e.prepare(request(), "b".into(), r).await })
        };
        tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                if engine.inner.state.lock().unwrap().requests.len() == 2 {
                    break;
                }
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        engine.cancel("a");
        assert!(matches!(
            tokio::time::timeout(Duration::from_secs(1), a)
                .await
                .unwrap()
                .unwrap(),
            Err(AnimatedArtworkError::Cancelled)
        ));
        release.send(()).unwrap();
        let asset = tokio::time::timeout(Duration::from_secs(2), b)
            .await
            .unwrap()
            .unwrap()
            .unwrap()
            .unwrap();
        assert_eq!(asset.frame_rate, 60.);
        assert_eq!(engine.clear(root.clone()).await.unwrap(), asset.size_bytes);
        assert!(std::path::Path::new(&asset.local_path).exists());
        // This sync release also works on a caller without a Tokio runtime.
        let copy = engine.clone();
        std::thread::spawn(move || copy.cancel("b")).join().unwrap();
        assert_eq!(engine.clear(root.clone()).await.unwrap(), 0);
        server.await.unwrap();
        let _ = tokio::fs::remove_dir_all(root).await;
    }
    #[tokio::test]
    async fn clear_cancels_http_and_late_result_cannot_repopulate() {
        let engine = Engine::new();
        let root = temp_root();
        let (url, started, release, server) = fixture_server().await;
        seed(&engine, &root, url).await;
        let task = {
            let e = engine.clone();
            let r = root.clone();
            tokio::spawn(async move { e.prepare(request(), "clear-me".into(), r).await })
        };
        started.await.unwrap();
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(2), engine.clear(root.clone()))
                .await
                .unwrap()
                .unwrap(),
            0
        );
        assert!(matches!(
            task.await.unwrap(),
            Err(AnimatedArtworkError::Cancelled)
        ));
        let _ = release.send(());
        server.await.unwrap();
        assert_eq!(engine.cache_size(root.clone()).await.unwrap(), 0);
        let mut entries = tokio::fs::read_dir(&root).await.unwrap();
        while let Some(entry) = entries.next_entry().await.unwrap() {
            assert!(!entry.file_name().to_string_lossy().ends_with(".mp4"));
            assert!(!entry.file_name().to_string_lossy().ends_with(".part"));
        }
        let _ = tokio::fs::remove_dir_all(root).await;
    }
    #[tokio::test]
    async fn transient_resolution_does_not_persist_absence() {
        let e = Engine::new();
        let root = temp_root();
        let mut invalid = request();
        invalid.artists.clear();
        assert!(e
            .prepare(invalid, "unresolved".into(), root.clone())
            .await
            .is_err());
        let key = format!("{}:{}", hash(&root), request_key(&request()));
        assert!(e
            .cache(&root)
            .await
            .unwrap()
            .lock()
            .await
            .metadata(&key)
            .is_none());
        let _ = tokio::fs::remove_dir_all(root).await;
    }
    #[tokio::test]
    async fn last_consumer_cancel_closes_http_socket() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}/movie.mp4", listener.local_addr().unwrap());
        let (started_tx, started) = tokio::sync::oneshot::channel();
        let (disconnected_tx, disconnected) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut bytes = [0; 4096];
            let _ = stream.read(&mut bytes).await.unwrap();
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 50000\r\n\r\n")
                .await
                .unwrap();
            let _ = started_tx.send(());
            match stream.read(&mut bytes).await {
                Ok(0) => {}
                Err(e)
                    if matches!(
                        e.kind(),
                        std::io::ErrorKind::ConnectionReset | std::io::ErrorKind::ConnectionAborted
                    ) => {}
                result => panic!("request socket remained open: {result:?}"),
            }
            let _ = disconnected_tx.send(());
        });
        let engine = Engine::new();
        let root = temp_root();
        seed(&engine, &root, url).await;
        let task = {
            let e = engine.clone();
            let r = root.clone();
            tokio::spawn(async move { e.prepare(request(), "disconnect".into(), r).await })
        };
        started.await.unwrap();
        engine.cancel("disconnect");
        assert!(matches!(
            task.await.unwrap(),
            Err(AnimatedArtworkError::Cancelled)
        ));
        tokio::time::timeout(Duration::from_secs(2), disconnected)
            .await
            .unwrap()
            .unwrap();
        server.await.unwrap();
        assert_eq!(engine.clear(root.clone()).await.unwrap(), 0);
        let _ = tokio::fs::remove_dir_all(root).await;
    }
    #[tokio::test]
    async fn cancellation_before_ffi_prepare_registration_stays_cancelled() {
        let engine = Engine::new();
        let root = temp_root();
        engine.cancel("not-started-yet");
        assert!(matches!(
            engine
                .prepare(request(), "not-started-yet".into(), root.clone())
                .await,
            Err(AnimatedArtworkError::Cancelled)
        ));
        assert!(!std::path::Path::new(&root).exists());
    }
    #[test]
    fn track_metadata_enrichment_changes_lookup_fingerprint() {
        let mut a = request();
        a.album = None;
        let mut b = a.clone();
        b.duration_secs = Some(180);
        assert_ne!(request_key(&a), request_key(&b));
    }
    async fn clear_during_filesystem_operation(phase: &'static str) {
        let engine = Engine::new();
        let root = temp_root();
        let (url, started, release, server) = fixture_server().await;
        seed(&engine, &root, url).await;
        let (reached_tx, reached) = tokio::sync::oneshot::channel();
        let (resume, resume_rx) = tokio::sync::oneshot::channel();
        engine.cache(&root).await.unwrap().lock().await.io_pause = Some(cache::IoPause {
            phase,
            reached: reached_tx,
            resume: resume_rx,
        });
        let task = {
            let e = engine.clone();
            let r = root.clone();
            tokio::spawn(async move { e.prepare(request(), "io-race".into(), r).await })
        };
        started.await.unwrap();
        release.send(()).unwrap();
        tokio::time::timeout(Duration::from_secs(2), reached)
            .await
            .unwrap()
            .unwrap();
        let clear = {
            let e = engine.clone();
            let r = root.clone();
            tokio::spawn(async move { e.clear(r).await })
        };
        tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                if engine.inner.state.lock().unwrap().epochs.get(&root) == Some(&1) {
                    break;
                }
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        // clear has invalidated the request but cannot pass an unfinished filesystem transaction.
        assert!(!clear.is_finished());
        resume.send(()).unwrap();
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(2), clear)
                .await
                .unwrap()
                .unwrap()
                .unwrap(),
            0
        );
        assert!(matches!(
            task.await.unwrap(),
            Err(AnimatedArtworkError::Cancelled)
        ));
        server.await.unwrap();
        let mut entries = tokio::fs::read_dir(&root).await.unwrap();
        while let Some(entry) = entries.next_entry().await.unwrap() {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            assert!(
                !name.ends_with(".mp4") && !name.ends_with(".part"),
                "orphan after clear: {name}"
            );
        }
        let _ = tokio::fs::remove_dir_all(root).await;
    }
    #[tokio::test]
    async fn clear_waits_for_opened_partial_before_cleanup() {
        clear_during_filesystem_operation("opened").await;
    }
    #[tokio::test]
    async fn clear_waits_for_renamed_asset_to_enter_index() {
        clear_during_filesystem_operation("renamed").await;
    }
    #[tokio::test]
    async fn provider_retry_after_blocks_other_albums_but_allows_local_assets() {
        let engine = Engine::new();
        let root = temp_root();
        seed(
            &engine,
            &root,
            "https://mvod.itunes.apple.com/fixture.mp4".into(),
        )
        .await;
        let key = format!("{}:{}", hash(&root), request_key(&request()));
        let cache = engine.cache(&root).await.unwrap();
        let motion = cache
            .lock()
            .await
            .stored_metadata(&key)
            .unwrap()
            .motion
            .unwrap();
        let variant = &motion.variants[0];
        let id = asset_key(&motion.collection_id, variant);
        let bytes = tiny_mp4();
        let path = cache
            .lock()
            .await
            .reserve(&id, bytes.len() as u64)
            .await
            .unwrap();
        tokio::fs::write(path, &bytes).await.unwrap();
        cache
            .lock()
            .await
            .commit(AnimatedArtworkAsset {
                asset_id: id,
                local_path: String::new(),
                codec: variant.codec.clone(),
                width: 1080,
                height: 1080,
                frame_rate: 60.,
                size_bytes: bytes.len() as u64,
            })
            .await
            .unwrap();
        engine.provider_backoff(
            "album-a",
            &provider::ProviderError::RateLimited {
                retry_after_secs: 120,
            },
        );
        assert!(engine.network_ready("album-b").is_err());
        let asset = engine
            .prepare(request(), "cache-hit".into(), root.clone())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(asset.size_bytes, bytes.len() as u64);
        engine.inner.state.lock().unwrap().provider_until =
            Some(Instant::now() - Duration::from_secs(1));
        assert!(engine.network_ready("album-b").is_ok());
        engine.cancel("cache-hit");
        assert_eq!(engine.clear(root.clone()).await.unwrap(), 0);
        let _ = tokio::fs::remove_dir_all(root).await;
    }
}
