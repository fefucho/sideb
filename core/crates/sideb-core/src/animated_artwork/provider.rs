use std::fmt;

use reqwest::{Response, Url};
use scraper::{Html, Selector};
use serde_json::Value;
use unicode_normalization::UnicodeNormalization;

#[derive(Clone, Debug, PartialEq)]
pub(super) struct MotionVariant {
    pub(super) url: String,
    pub(super) width: u32,
    pub(super) height: u32,
    pub(super) frame_rate: f64,
    pub(super) codec: String,
    pub(super) bandwidth: u64,
}

#[derive(Clone, Debug, PartialEq)]
pub(super) struct ResolvedMotion {
    pub(super) collection_id: String,
    pub(super) variants: Vec<MotionVariant>,
}

#[derive(Clone, Debug, PartialEq)]
pub(super) enum Lookup {
    Found(ResolvedMotion),
    Absent,
    Unresolved,
}

#[derive(Debug)]
pub(super) enum ProviderError {
    Http(reqwest::Error),
    RateLimited { retry_after_secs: u64 },
    Invalid(String),
    Unsupported(String),
}

impl fmt::Display for ProviderError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Http(_) => write!(f, "Apple motion request failed"),
            Self::RateLimited { retry_after_secs } => write!(
                f,
                "Apple motion rate limited; retry after {retry_after_secs}s"
            ),
            Self::Invalid(e) => write!(f, "invalid Apple motion response: {e}"),
            Self::Unsupported(e) => write!(f, "unsupported Apple motion format: {e}"),
        }
    }
}

impl std::error::Error for ProviderError {}

impl From<reqwest::Error> for ProviderError {
    fn from(value: reqwest::Error) -> Self {
        Self::Http(value)
    }
}

const HTML_LIMIT: usize = 6 * 1024 * 1024;
const SEARCH_LIMIT: usize = 1024 * 1024;
const PLAYLIST_LIMIT: usize = 128 * 1024;

/// Resolves only a confidently matched Apple album. Network settings (timeout, TLS, UA,
/// redirect policy and rate limiting) belong to the caller's shared client/engine.
pub(super) async fn resolve(
    client: &reqwest::Client,
    request: &super::AnimatedArtworkRequest,
) -> Result<Lookup, ProviderError> {
    if request.title.trim().is_empty() || request.artists.trim().is_empty() {
        return Ok(Lookup::Unresolved);
    }

    let album = request.album.as_deref().filter(|s| !s.trim().is_empty());
    let selected = if let Some(album) = album {
        unique_collection(
            search(client, request, album, "album")
                .await?
                .into_iter()
                .filter(|c| album_match(c, request, album)),
        )
    } else {
        None
    };
    let selected = if let Some(c) = selected {
        c
    } else if let Some(duration) = request.duration_secs {
        let candidates = search(client, request, &request.title, "song").await?;
        match unique_collection(
            candidates
                .into_iter()
                .filter(|c| song_match(c, request, duration)),
        ) {
            Some(c) => c,
            None => return Ok(Lookup::Unresolved),
        }
    } else {
        return Ok(Lookup::Unresolved);
    };

    let id = selected.collection_id.to_string();
    let document = fetch_album(client, &request.storefront, &id).await?;
    let (id, master) = if let AlbumPayload::Master(master) = &document.payload {
        (id, master.clone())
    } else {
        match resolve_related_document(&document, |id| async move {
            fetch_album(client, &request.storefront, &id).await
        })
        .await?
        {
            Some(found) => found,
            None => return Ok(Lookup::Absent),
        }
    };
    resolve_master(client, request, id, master).await
}
async fn resolve_related_document<F, Fut>(
    document: &AlbumDocument,
    mut fetch: F,
) -> Result<Option<(String, String)>, ProviderError>
where
    F: FnMut(String) -> Fut,
    Fut: std::future::Future<Output = Result<AlbumDocument, ProviderError>>,
{
    let (related, mut uncertain) = related_candidates(document);
    let mut visited = std::collections::HashSet::from([document.id.clone()]);
    for candidate in related {
        if !visited.insert(candidate.id.clone()) {
            continue;
        }
        let alternate = match fetch(candidate.id.clone()).await {
            Ok(alternate) => alternate,
            Err(error @ ProviderError::RateLimited { .. }) => return Err(error),
            Err(_) => {
                uncertain = true;
                continue;
            }
        };
        if validate_related(document, &candidate, &alternate).is_err() {
            uncertain = true;
            continue;
        }
        if let AlbumPayload::Master(master) = alternate.payload {
            return Ok(Some((candidate.id, master)));
        }
        // Never traverse a second level. Keep uncertainty if an unchecked version was discovered.
        uncertain |= alternate.related.iter().any(|item| {
            item.pointer("/contentDescriptor/identifiers/storeAdamID")
                .and_then(Value::as_str)
                .is_none_or(|id| {
                    !visited.contains(id)
                        && !document.related.iter().any(|source| {
                            source
                                .pointer("/contentDescriptor/identifiers/storeAdamID")
                                .and_then(Value::as_str)
                                == Some(id)
                        })
                })
        });
    }
    if uncertain {
        Err(unsupported(
            "official album versions could not all be verified",
        ))
    } else {
        Ok(None)
    }
}

async fn fetch_album(
    client: &reqwest::Client,
    store: &str,
    id: &str,
) -> Result<AlbumDocument, ProviderError> {
    let page = format!("https://music.apple.com/{}/album/{id}", storefront(store));
    let response = client.get(checked_url(&page)?).send().await?;
    let html = bounded_body(response, HTML_LIMIT, "album HTML").await?;
    parse_album_document(&html, id)
}
async fn resolve_master(
    client: &reqwest::Client,
    request: &super::AnimatedArtworkRequest,
    id: String,
    master: String,
) -> Result<Lookup, ProviderError> {
    let response = client.get(checked_url(&master)?).send().await?;
    let master_base = checked_url(response.url().as_str())?;
    let text = String::from_utf8(bounded_body(response, PLAYLIST_LIMIT, "master playlist").await?)
        .map_err(|_| ProviderError::Invalid("playlist is not UTF-8".into()))?;
    let variants = parse_master(&text, master_base, request.prefer_hevc)?;
    if variants.is_empty() {
        return Err(ProviderError::Unsupported(
            "no compatible square SDR variants".into(),
        ));
    }
    let mut resolved = Vec::new();
    for mut variant in variants.into_iter().take(2) {
        let response = client.get(checked_url(&variant.url)?).send().await?;
        let media_base = checked_url(response.url().as_str())?;
        let text =
            String::from_utf8(bounded_body(response, PLAYLIST_LIMIT, "media playlist").await?)
                .map_err(|_| ProviderError::Invalid("media playlist is not UTF-8".into()))?;
        variant.url = parse_media_playlist(&text, &media_base)?;
        resolved.push(variant);
    }
    Ok(Lookup::Found(ResolvedMotion {
        collection_id: id,
        variants: resolved,
    }))
}

#[derive(Debug, Clone)]
struct Candidate {
    collection_id: u64,
    artist: String,
    album: String,
    title: String,
    duration: Option<u64>,
    kind: String,
}

// Shared across Engine instances. Ten searches/minute leaves headroom below the public API limit.
async fn wait_search_slot() {
    static NEXT: std::sync::OnceLock<tokio::sync::Mutex<tokio::time::Instant>> =
        std::sync::OnceLock::new();
    let mut next = NEXT
        .get_or_init(|| tokio::sync::Mutex::new(tokio::time::Instant::now()))
        .lock()
        .await;
    tokio::time::sleep_until(*next).await;
    *next = tokio::time::Instant::now() + std::time::Duration::from_secs(6);
}
async fn search(
    client: &reqwest::Client,
    req: &super::AnimatedArtworkRequest,
    term: &str,
    entity: &str,
) -> Result<Vec<Candidate>, ProviderError> {
    let url = Url::parse_with_params(
        "https://itunes.apple.com/search",
        &[
            ("term", format!("{} {term}", req.artists)),
            ("entity", entity.into()),
            ("media", "music".into()),
            ("country", storefront(&req.storefront)),
            ("limit", "25".into()),
        ],
    )
    .map_err(|e| ProviderError::Invalid(e.to_string()))?;
    wait_search_slot().await;
    let response = client.get(url).send().await?;
    let bytes = bounded_body(response, SEARCH_LIMIT, "search response").await?;
    parse_search_response(&bytes)
}

fn parse_search_response(bytes: &[u8]) -> Result<Vec<Candidate>, ProviderError> {
    let data: Value =
        serde_json::from_slice(&bytes).map_err(|e| ProviderError::Invalid(e.to_string()))?;
    let Some(results) = data.get("results").and_then(Value::as_array) else {
        return Err(ProviderError::Invalid("search results missing".into()));
    };
    Ok(results
        .iter()
        .filter_map(|v| {
            Some(Candidate {
                collection_id: v.get("collectionId")?.as_u64()?,
                artist: nonempty(v.get("artistName")?.as_str()?)?,
                album: nonempty(v.get("collectionName")?.as_str()?).unwrap_or_default(),
                title: nonempty(v.get("trackName").and_then(Value::as_str).unwrap_or(""))
                    .unwrap_or_default(),
                duration: v
                    .get("trackTimeMillis")
                    .and_then(Value::as_u64)
                    .map(|ms| ms.saturating_add(500) / 1000),
                kind: v
                    .get("wrapperType")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string(),
            })
        })
        .collect())
}

fn unique_collection(mut candidates: impl Iterator<Item = Candidate>) -> Option<Candidate> {
    let first = candidates.next()?;
    if candidates.any(|candidate| candidate.collection_id != first.collection_id) {
        None
    } else {
        Some(first)
    }
}
fn album_match(c: &Candidate, req: &super::AnimatedArtworkRequest, expected: &str) -> bool {
    c.collection_id > 0
        && c.kind == "collection"
        && normalize(&c.album) == normalize(expected)
        && artist_match(&c.artist, &req.artists)
}
fn song_match(c: &Candidate, req: &super::AnimatedArtworkRequest, duration: u64) -> bool {
    c.collection_id > 0
        && c.kind == "track"
        && normalize(&c.title) == normalize(&req.title)
        && artist_match(&c.artist, &req.artists)
        && c.duration.is_some_and(|d| d.abs_diff(duration) <= 4)
        && req
            .album
            .as_deref()
            .filter(|a| !a.trim().is_empty())
            .map_or(true, |a| normalize(&c.album) == normalize(a))
}
fn artist_match(candidate: &str, requested: &str) -> bool {
    let c = normalize(candidate);
    let r = normalize(requested);
    c == r || r.split(" feat ").next().is_some_and(|lead| c == lead)
}
fn normalize(s: &str) -> String {
    s.nfkd()
        .filter(|c| !unicode_normalization::char::is_combining_mark(*c))
        .flat_map(char::to_lowercase)
        .map(|c| if c.is_alphanumeric() { c } else { ' ' })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}
fn nonempty(s: &str) -> Option<String> {
    (!s.trim().is_empty()).then(|| s.trim().to_owned())
}
fn storefront(s: &str) -> String {
    let s = s.trim().to_ascii_lowercase();
    if s.len() == 2 && s.bytes().all(|b| b.is_ascii_lowercase()) {
        s
    } else {
        "us".into()
    }
}

async fn bounded_body(
    response: Response,
    limit: usize,
    label: &str,
) -> Result<Vec<u8>, ProviderError> {
    if response.status() == reqwest::StatusCode::TOO_MANY_REQUESTS {
        return Err(ProviderError::RateLimited {
            retry_after_secs: retry_after(&response),
        });
    }
    if !response.status().is_success() {
        return Err(ProviderError::Invalid(format!(
            "{label} returned HTTP {}",
            response.status()
        )));
    }
    let mut body = Vec::new();
    let mut response = response;
    while let Some(chunk) = response.chunk().await? {
        if body.len().saturating_add(chunk.len()) > limit {
            return Err(ProviderError::Invalid(format!(
                "{label} exceeds {limit} bytes"
            )));
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

fn retry_after(response: &Response) -> u64 {
    let Some(raw) = response
        .headers()
        .get(reqwest::header::RETRY_AFTER)
        .and_then(|v| v.to_str().ok())
    else {
        return 60;
    };
    if let Ok(seconds) = raw.parse::<u64>() {
        return seconds.clamp(1, 3600);
    }
    httpdate::parse_http_date(raw)
        .ok()
        .map(|when| {
            when.duration_since(std::time::SystemTime::now())
                .unwrap_or_default()
                .as_secs()
                .clamp(1, 3600)
        })
        .unwrap_or(60)
}

pub(super) fn checked_url(raw: &str) -> Result<Url, ProviderError> {
    let url = Url::parse(raw).map_err(|e| ProviderError::Invalid(format!("bad URL: {e}")))?;
    let host = url.host_str().unwrap_or("").to_ascii_lowercase();
    let allowed = host == "music.apple.com"
        || host == "itunes.apple.com"
        || host == "mvod.itunes.apple.com"
        || host.ends_with(".phobos.apple.com")
        || host.ends_with(".mzstatic.com");
    if url.scheme() != "https"
        || url.port_or_known_default() != Some(443)
        || !allowed
        || url.username() != ""
        || url.password().is_some()
    {
        return Err(ProviderError::Invalid(
            "URL is outside approved HTTPS Apple hosts".into(),
        ));
    }
    Ok(url)
}

#[derive(Debug)]
enum AlbumPayload {
    Absent,
    Master(String),
}
#[derive(Debug)]
struct AlbumDocument {
    id: String,
    header: Value,
    related: Vec<Value>,
    payload: AlbumPayload,
}
#[derive(Debug)]
struct RelatedAlbum {
    id: String,
}
const RELATED_LIMIT: usize = 3;
fn unsupported(reason: &str) -> ProviderError {
    ProviderError::Unsupported(reason.into())
}
#[cfg(test)]
fn parse_album_html(html: &[u8], expected_id: &str) -> Result<AlbumPayload, ProviderError> {
    Ok(parse_album_document(html, expected_id)?.payload)
}
fn parse_album_document(html: &[u8], expected_id: &str) -> Result<AlbumDocument, ProviderError> {
    let html = std::str::from_utf8(html)
        .map_err(|_| ProviderError::Invalid("album HTML is not UTF-8".into()))?;
    let document = Html::parse_document(html);
    let selector = Selector::parse("script#serialized-server-data").unwrap();
    let script = document
        .select(&selector)
        .next()
        .ok_or_else(|| unsupported("serialized-server-data missing"))?;
    let root: Value = serde_json::from_str(&script.text().collect::<String>())
        .map_err(|e| ProviderError::Invalid(e.to_string()))?;
    let sections = root
        .pointer("/data/0/data/sections")
        .and_then(Value::as_array)
        .ok_or_else(|| unsupported("album sections missing"))?;
    let mut header = None;
    let mut related = Vec::new();
    let mut unknown_related = false;
    for section in sections {
        if section.get("id").and_then(Value::as_str).is_some_and(|id| {
            id.starts_with("other-versions") && id != "other-versions - other-versions"
        }) {
            unknown_related = true;
        }
        let is_related =
            section.get("id").and_then(Value::as_str) == Some("other-versions - other-versions");
        let items = match section.get("items").and_then(Value::as_array) {
            Some(items) => items,
            None if is_related => {
                unknown_related = true;
                continue;
            }
            None => continue,
        };
        if is_related {
            related.extend(items.iter().cloned());
        }
        for item in items {
            let item_id = item
                .get("id")
                .or_else(|| item.get("collectionId"))
                .and_then(|id| {
                    id.as_str()
                        .map(str::to_owned)
                        .or_else(|| id.as_u64().map(|id| id.to_string()))
                });
            if item_id.as_deref() == Some(expected_id)
                || item_id.as_deref() == Some(&format!("album-detail-header - {expected_id}"))
            {
                if header.is_some() {
                    return Err(unsupported("duplicate album header"));
                }
                header = Some(item.clone());
            }
        }
    }
    let header = header.ok_or_else(|| unsupported("target album has no usable motion field"))?;
    let motion = header
        .get("videoArtwork")
        .ok_or_else(|| unsupported("album videoArtwork field missing"))?;
    let payload = if motion.is_null() {
        AlbumPayload::Absent
    } else {
        AlbumPayload::Master(
            motion
                .pointer("/dictionary/motionDetailSquare/video")
                .and_then(Value::as_str)
                .ok_or_else(|| unsupported("motion schema unknown"))?
                .to_owned(),
        )
    };
    if matches!(payload, AlbumPayload::Absent) && unknown_related {
        return Err(unsupported("other versions schema unknown"));
    }
    Ok(AlbumDocument {
        id: expected_id.into(),
        header,
        related,
        payload,
    })
}
fn album_title(item: &Value) -> Option<&str> {
    item.get("title")
        .and_then(Value::as_str)
        .or_else(|| item.pointer("/titleLinks/0/title").and_then(Value::as_str))
}
fn artwork(item: &Value) -> Option<&Value> {
    item.pointer("/artwork/dictionary")
}
fn artwork_url(item: &Value) -> Option<&str> {
    artwork(item)?.get("url")?.as_str()
}
fn artist_identity(header: &Value) -> Option<(String, String)> {
    let links = header.get("subtitleLinks")?.as_array()?;
    let artists: Vec<_> = links
        .iter()
        .filter_map(|link| {
            let descriptor = link.pointer("/segue/destination/contentDescriptor")?;
            if descriptor.get("kind")?.as_str() != Some("artist") {
                return None;
            }
            Some((
                descriptor
                    .pointer("/identifiers/storeAdamID")?
                    .as_str()?
                    .to_owned(),
                normalize(link.get("title")?.as_str()?),
            ))
        })
        .collect();
    if artists.is_empty() {
        None
    } else {
        Some((
            artists
                .iter()
                .map(|a| a.0.as_str())
                .collect::<Vec<_>>()
                .join("|"),
            artists
                .iter()
                .map(|a| a.1.as_str())
                .collect::<Vec<_>>()
                .join("|"),
        ))
    }
}
fn related_candidates(document: &AlbumDocument) -> (Vec<RelatedAlbum>, bool) {
    let mut result = Vec::new();
    let mut uncertain = false;
    let mut seen = std::collections::HashSet::from([document.id.clone()]);
    for item in &document.related {
        let Some(id) = item
            .pointer("/contentDescriptor/identifiers/storeAdamID")
            .and_then(Value::as_str)
        else {
            uncertain = true;
            continue;
        };
        if id.is_empty() || !id.bytes().all(|b| b.is_ascii_digit()) {
            uncertain = true;
            continue;
        }
        if !seen.insert(id.to_owned()) {
            continue;
        }
        let linked_id = format!("other-versions - {id}");
        if item.get("id").and_then(Value::as_str) != Some(linked_id.as_str())
            || item
                .pointer("/contentDescriptor/kind")
                .and_then(Value::as_str)
                != Some("album")
        {
            uncertain = true;
            continue;
        }
        let (Some(title), Some(original_title)) =
            (album_title(item), album_title(&document.header))
        else {
            uncertain = true;
            continue;
        };
        // Recognized Deluxe/live/remaster or track-count changes belong to another edition.
        if normalize(title) != normalize(original_title) {
            continue;
        }
        let (Some(count), Some(original_count)) = (
            item.get("trackCount")
                .and_then(Value::as_u64)
                .filter(|n| *n > 0),
            document
                .header
                .get("trackCount")
                .and_then(Value::as_u64)
                .filter(|n| *n > 0),
        ) else {
            uncertain = true;
            continue;
        };
        if count != original_count {
            continue;
        }
        if result.len() >= RELATED_LIMIT {
            uncertain = true;
            continue;
        }
        result.push(RelatedAlbum { id: id.to_owned() });
    }
    (result, uncertain)
}

fn validate_related(
    original: &AlbumDocument,
    candidate: &RelatedAlbum,
    alternate: &AlbumDocument,
) -> Result<(), ProviderError> {
    if alternate.id != candidate.id
        || album_title(&original.header).map(normalize)
            != album_title(&alternate.header).map(normalize)
    {
        return Err(unsupported("alternate album edition differs"));
    }
    if artist_identity(&original.header).is_none()
        || artist_identity(&original.header) != artist_identity(&alternate.header)
    {
        return Err(unsupported("alternate album artist differs"));
    }
    if original.header.get("trackCount").and_then(Value::as_u64)
        != alternate.header.get("trackCount").and_then(Value::as_u64)
    {
        return Err(unsupported("alternate album track count differs"));
    }
    let backlink = alternate
        .related
        .iter()
        .find(|item| {
            item.pointer("/contentDescriptor/identifiers/storeAdamID")
                .and_then(Value::as_str)
                == Some(original.id.as_str())
        })
        .ok_or_else(|| unsupported("alternate album has no reciprocal official version link"))?;
    if backlink.get("id").and_then(Value::as_str)
        != Some(format!("other-versions - {}", original.id).as_str())
        || backlink
            .pointer("/contentDescriptor/kind")
            .and_then(Value::as_str)
            != Some("album")
    {
        return Err(unsupported("alternate backlink descriptor differs"));
    }
    if album_title(backlink).map(normalize) != album_title(&original.header).map(normalize)
        || artwork_url(backlink)
            .zip(artwork_url(&original.header))
            .is_some_and(|(a, b)| a != b)
    {
        return Err(unsupported("alternate album backlink artwork differs"));
    }
    Ok(())
}

fn parse_master(
    text: &str,
    base: Url,
    prefer_hevc: bool,
) -> Result<Vec<MotionVariant>, ProviderError> {
    if !text.lines().any(|l| l.trim() == "#EXTM3U") {
        return Err(ProviderError::Invalid("not an HLS playlist".into()));
    }
    if text
        .lines()
        .any(|l| l.trim().starts_with("#EXT-X-SESSION-KEY:"))
    {
        return Err(ProviderError::Unsupported(
            "encrypted master playlist".into(),
        ));
    }
    let lines: Vec<_> = text.lines().collect();
    let mut variants = Vec::new();
    for i in 0..lines.len() {
        let line = lines[i].trim();
        let Some(attrs) = line.strip_prefix("#EXT-X-STREAM-INF:") else {
            continue;
        };
        let uri = lines
            .iter()
            .skip(i + 1)
            .map(|l| l.trim())
            .find(|l| !l.is_empty() && !l.starts_with('#'));
        let Some(uri) = uri else { continue };
        let attrs = attributes(attrs);
        let Some((w, h)) = attrs
            .get("RESOLUTION")
            .and_then(|s| s.split_once('x'))
            .and_then(|(w, h)| Some((w.parse::<u32>().ok()?, h.parse::<u32>().ok()?)))
        else {
            continue;
        };
        if w == 0
            || w != h
            || w > 1080
            || h > 1080
            || attrs.get("VIDEO-RANGE").is_some_and(|v| v != "SDR")
        {
            continue;
        }
        let fps: f64 = attrs
            .get("FRAME-RATE")
            .and_then(|v| v.parse().ok())
            .unwrap_or(0.0);
        if !fps.is_finite() || fps <= 0.0 || fps > 60.0 {
            continue;
        }
        let codec_list = attrs.get("CODECS").cloned().unwrap_or_default();
        let codec = codec_list
            .split(',')
            .map(str::trim)
            .find(|c| c.starts_with("avc1") || c.starts_with("hvc1") || c.starts_with("hev1"));
        let Some(codec) = codec else { continue };
        // false is the portable H.264 path, including the Mac's compatibility retry.
        if !prefer_hevc && !codec.starts_with("avc1") {
            continue;
        }
        let url = base
            .join(uri)
            .map_err(|e| ProviderError::Invalid(e.to_string()))?;
        checked_url(url.as_str())?;
        variants.push(MotionVariant {
            url: url.to_string(),
            width: w,
            height: h,
            frame_rate: fps,
            codec: codec.to_owned(),
            bandwidth: attrs
                .get("BANDWIDTH")
                .and_then(|v| v.parse().ok())
                .unwrap_or(0),
        });
    }
    variants.sort_by(|a, b| {
        b.width
            .cmp(&a.width)
            .then_with(|| b.frame_rate.total_cmp(&a.frame_rate))
            .then_with(|| {
                let rank = |c: &str| {
                    if (prefer_hevc && !c.starts_with("avc1"))
                        || (!prefer_hevc && c.starts_with("avc1"))
                    {
                        1
                    } else {
                        0
                    }
                };
                rank(&b.codec).cmp(&rank(&a.codec))
            })
            .then_with(|| b.bandwidth.cmp(&a.bandwidth))
    });
    let Some(primary) = variants.first().cloned() else {
        return Ok(Vec::new());
    };
    let mut selected = vec![primary.clone()];
    if let Some(alternate) = variants.iter().find(|v| {
        v.width == primary.width
            && v.frame_rate == primary.frame_rate
            && v.codec.starts_with("avc1") != primary.codec.starts_with("avc1")
    }) {
        selected.push(alternate.clone());
    }
    Ok(selected)
}

fn attributes(input: &str) -> std::collections::HashMap<String, String> {
    let mut out = std::collections::HashMap::new();
    let mut key = String::new();
    let mut value = String::new();
    let mut in_value = false;
    let mut quoted = false;
    for c in input.chars().chain(std::iter::once(',')) {
        if c == '"' {
            quoted = !quoted;
            continue;
        }
        if c == '=' && !in_value {
            in_value = true;
            continue;
        }
        if c == ',' && !quoted {
            if !key.is_empty() {
                out.insert(key.trim().into(), value.trim().into());
            }
            key.clear();
            value.clear();
            in_value = false;
            continue;
        }
        if in_value {
            value.push(c);
        } else {
            key.push(c);
        }
    }
    out
}

fn parse_media_playlist(text: &str, base: &Url) -> Result<String, ProviderError> {
    if !text.lines().any(|l| l.trim() == "#EXTM3U") {
        return Err(ProviderError::Invalid("not an HLS media playlist".into()));
    }
    let mut endlist = false;
    let mut encrypted = false;
    let mut init = std::collections::HashSet::new();
    let mut resources = Vec::new();
    for line in text.lines().map(str::trim).filter(|l| !l.is_empty()) {
        if line == "#EXT-X-ENDLIST" {
            endlist = true;
        }
        if let Some(attrs) = line.strip_prefix("#EXT-X-KEY:") {
            if attributes(attrs)
                .get("METHOD")
                .map_or(true, |m| m != "NONE")
            {
                encrypted = true;
            }
        }
        if line.starts_with("#EXT-X-SESSION-KEY:") {
            encrypted = true;
        }
        if let Some(attrs) = line.strip_prefix("#EXT-X-MAP:") {
            if let Some(uri) = attributes(attrs).get("URI") {
                init.insert(resolve_uri(base, uri)?);
            }
        }
        if !line.starts_with('#') {
            resources.push(resolve_uri(base, line)?);
        }
    }
    if !endlist {
        return Err(ProviderError::Unsupported(
            "playlist is not complete VOD".into(),
        ));
    }
    if encrypted {
        return Err(ProviderError::Unsupported(
            "encrypted media playlist".into(),
        ));
    }
    if init.is_empty() {
        return Err(ProviderError::Unsupported(
            "media playlist has no initialization map".into(),
        ));
    }
    let unique: std::collections::HashSet<_> = resources.into_iter().collect();
    if unique.len() != 1 || init.len() != 1 || init != unique {
        return Err(ProviderError::Unsupported(
            "media segments and init map are not a single MP4 resource".into(),
        ));
    }
    Ok(init.into_iter().next().unwrap())
}
fn resolve_uri(base: &Url, uri: &str) -> Result<String, ProviderError> {
    let resolved = base
        .join(uri)
        .map_err(|e| ProviderError::Invalid(e.to_string()))?;
    Ok(checked_url(resolved.as_str())?.to_string())
}

#[cfg(test)]
#[path = "tests.rs"]
mod tests;
