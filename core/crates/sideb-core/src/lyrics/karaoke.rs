//! Opt-in detailed lyrics. This module deliberately does not alter the classic lookup,
//! records or cache keys: users can switch back to exactly the existing lyrics panel.

use super::{LyricLine, LyricWord, Lyrics, LyricsContext, LyricsRequest};
use crate::SideBError;
use md5::{Digest, Md5};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::time::Duration;
use unicode_normalization::UnicodeNormalization;

const SCHEMA_VERSION: u32 = 4;
const MAX_BODY_BYTES: usize = 2 * 1024 * 1024;
const MAX_LINES: usize = 5000;
const MAX_WORDS_PER_LINE: usize = 2048;
const MAX_WORDS_TOTAL: usize = 50_000;
const HIT_TTL: i64 = 7 * 24 * 3600;
const LINE_TTL: i64 = 24 * 3600;
const MISS_TTL: i64 = 3600;
// A request made before the player learns the cut's duration is provisional.
const PROVISIONAL_TTL: i64 = 60;
const USER_AGENT: &str = concat!(
    "SideB/",
    env!("CARGO_PKG_VERSION"),
    " (karaoke experimental)"
);

/// The experimental document owns voice metadata without changing the classic
/// Lyrics/LyricLine records or the JSON that existing clients cache and consume.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Document {
    pub source: String,
    pub synced: bool,
    pub instrumental: bool,
    pub lines: Vec<Line>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Line {
    pub time_ms: Option<u64>,
    pub end_time_ms: Option<u64>,
    pub text: String,
    pub words: Option<Vec<LyricWord>>,
    pub translation: Option<String>,
    pub role: Option<String>,
    pub agent: Option<String>,
    pub group_id: Option<String>,
    pub section: Option<String>,
}

impl From<LyricLine> for Line {
    fn from(line: LyricLine) -> Self {
        Self {
            time_ms: line.time_ms,
            end_time_ms: line.end_time_ms,
            text: line.text,
            words: line.words,
            translation: line.translation,
            role: None,
            agent: None,
            group_id: None,
            section: None,
        }
    }
}

impl From<Lyrics> for Document {
    fn from(lyrics: Lyrics) -> Self {
        Self {
            source: lyrics.source,
            synced: lyrics.synced,
            instrumental: lyrics.instrumental,
            lines: lyrics.lines.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(Serialize, Deserialize)]
struct CacheEntry {
    version: u32,
    fetched_at: i64,
    lyrics: Option<Document>,
}

/// Unlike legacy successes, experimental cache entries expire and include the request
/// signature. A different cut/album/duration cannot inherit an unrelated rich lyric.
fn cache_key(req: &LyricsRequest, boidu_enabled: bool) -> String {
    let signature = serde_json::to_vec(&(
        &req.video_id,
        &req.title,
        &req.artists,
        &req.album,
        req.duration.filter(|v| v.is_finite() && *v > 0.0),
        boidu_enabled,
    ))
    .unwrap_or_default();
    let mut digest = Md5::new();
    digest.update(signature);
    format!("karaoke:v{SCHEMA_VERSION}:{:x}", digest.finalize())
}

fn has_words(lyrics: &Document) -> bool {
    lyrics
        .lines
        .iter()
        .any(|line| line.words.as_ref().is_some_and(|words| !words.is_empty()))
}

fn cached(entry: CacheEntry, now: i64) -> Option<Option<Document>> {
    let ttl = match &entry.lyrics {
        Some(lyrics) if has_words(lyrics) || lyrics.instrumental => HIT_TTL,
        Some(_) => LINE_TTL,
        None => MISS_TTL,
    };
    (entry.version == SCHEMA_VERSION && now >= entry.fetched_at && now - entry.fetched_at < ttl)
        .then_some(entry.lyrics)
}

fn request_duration(req: &LyricsRequest) -> Option<f64> {
    req.duration
        .filter(|value| value.is_finite() && *value > 0.0)
}

fn cached_for_request(
    entry: CacheEntry,
    now: i64,
    req: &LyricsRequest,
) -> Option<Option<Document>> {
    if request_duration(req).is_none() && now.saturating_sub(entry.fetched_at) >= PROVISIONAL_TTL {
        return None;
    }
    cached(entry, now)
}

fn cache_fallback(hit: &Document, provider_failed: bool) -> bool {
    !provider_failed || has_words(hit) || hit.instrumental
}

pub(crate) async fn get(
    context: &LyricsContext<'_>,
    req: LyricsRequest,
    force_refresh: bool,
) -> Result<Option<Document>, SideBError> {
    let now = super::now_secs();
    let boidu_enabled = context.db.get_setting("lyrics_boidu").as_deref() != Some("false");
    let key = cache_key(&req, boidu_enabled);
    if !force_refresh {
        if let Some(Some(json)) = context.db.get_lyrics(&key, now, MISS_TTL) {
            if let Ok(entry) = serde_json::from_str(&json) {
                if let Some(hit) = cached_for_request(entry, now, &req) {
                    return Ok(hit);
                }
            }
        }
    }

    // A read-only classic cache probe provides a safe line fallback. Its old parser's
    // word timestamps are deliberately not promoted to the experimental contract.
    let legacy_fallback = if force_refresh {
        None
    } else {
        context
            .db
            .get_lyrics(&req.video_id, now, super::MISS_TTL_SECS)
            .flatten()
            .and_then(|json| serde_json::from_str::<Lyrics>(&json).ok())
            .map(line_only)
    };

    // Resolve fresh providers first. On an equal-quality result their existing
    // order wins, and the read-only classic fallback is considered last.
    let mut fallback = None;
    let mut failed = false;
    if boidu_enabled {
        match boidu(&req).await {
            Ok(Some(hit)) if has_words(&hit) || hit.instrumental => {
                save(context, &key, now, Some(&hit));
                return Ok(Some(hit));
            }
            Ok(Some(hit)) => fallback = prefer(fallback, hit),
            Ok(None) => {}
            Err(()) => failed = true,
        }
    }
    match lrclib(&req).await {
        Ok(Some(hit)) => fallback = prefer(fallback, hit),
        Ok(None) => {}
        Err(()) => failed = true,
    }

    let fallback = prefer_classic_fallback(fallback, legacy_fallback);
    if let Some(hit) = fallback {
        // A refresh is fresh provider data only, never a stale experimental or legacy
        // cache result disguised as a successful network refresh.
        if cache_fallback(&hit, failed) {
            save(context, &key, now, Some(&hit));
        }
        return Ok(Some(hit));
    }
    if failed {
        return Err(SideBError::NetworkError {
            message: "Detailed lyrics are temporarily unavailable".into(),
        });
    }
    save(context, &key, now, None);
    Ok(None)
}

fn save(context: &LyricsContext<'_>, key: &str, now: i64, hit: Option<&Document>) {
    let entry = CacheEntry {
        version: SCHEMA_VERSION,
        fetched_at: now,
        lyrics: hit.cloned(),
    };
    if let Ok(json) = serde_json::to_string(&entry) {
        context.db.put_lyrics(key, Some(&json), now);
    }
}

fn line_only(lyrics: Lyrics) -> Document {
    let mut lyrics = Document::from(lyrics);
    for line in &mut lyrics.lines {
        line.words = None;
    }
    lyrics
}

fn prefer(current: Option<Document>, next: Document) -> Option<Document> {
    fn quality(document: &Document) -> (bool, bool, bool, bool) {
        let metadata = document.lines.iter().any(|line| {
            [
                &line.role,
                &line.agent,
                &line.group_id,
                &line.section,
                &line.translation,
            ]
            .iter()
            .any(|value| {
                value
                    .as_deref()
                    .is_some_and(|value| !value.trim().is_empty())
            })
        });
        (
            document.instrumental,
            document.synced,
            has_words(document),
            metadata,
        )
    }
    if current
        .as_ref()
        .is_none_or(|old| quality(&next) > quality(old))
    {
        Some(next)
    } else {
        current
    }
}

fn prefer_classic_fallback(fresh: Option<Document>, classic: Option<Document>) -> Option<Document> {
    match (fresh, classic) {
        (Some(fresh), Some(classic)) => {
            // A cached translation must not make stale/flattened text outrank
            // a freshly fetched document. Keep the classic result only when
            // it supplies a stronger timing/instrumental state.
            if (classic.instrumental, classic.synced) > (fresh.instrumental, fresh.synced) {
                Some(classic)
            } else {
                Some(fresh)
            }
        }
        (fresh, classic) => fresh.or(classic),
    }
}

/// Status and JSON failures stay errors. This keeps 401/429/503/HTML responses out
/// of the negative cache and leaves the previous document available to the UI.
async fn json_response(mut response: reqwest::Response) -> Result<Option<Value>, ()> {
    if response.status() == reqwest::StatusCode::NOT_FOUND {
        return Ok(None);
    }
    if !response.status().is_success()
        || response
            .content_length()
            .is_some_and(|size| size > MAX_BODY_BYTES as u64)
    {
        return Err(());
    }
    let mut body = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| ())? {
        if body.len().saturating_add(chunk.len()) > MAX_BODY_BYTES {
            return Err(());
        }
        body.extend_from_slice(&chunk);
    }
    serde_json::from_slice(&body).map(Some).map_err(|_| ())
}

async fn boidu(req: &LyricsRequest) -> Result<Option<Document>, ()> {
    let mut query = vec![("s", req.title.clone()), ("a", req.artists.clone())];
    if let Some(album) = req.album.as_ref().filter(|value| !value.is_empty()) {
        query.push(("al", album.clone()));
    }
    if let Some(duration) = req
        .duration
        .filter(|value| value.is_finite() && *value > 0.0)
    {
        query.push(("d", duration.round().to_string()));
    }
    let response = crate::http::client()
        .get("https://lyrics-api.boidu.dev/getLyrics")
        .query(&query)
        .header("User-Agent", USER_AGENT)
        .timeout(Duration::from_secs(8))
        .send()
        .await
        .map_err(|_| ())?;
    let Some(value) = json_response(response).await? else {
        return Ok(None);
    };
    let lines = boidu_lines(&value).ok_or(())?;
    Ok(Some(Document {
        source: "Better Lyrics / Boidu".into(),
        synced: lines.iter().any(|line| line.time_ms.is_some()),
        instrumental: false,
        lines,
    }))
}

/// Providers sometimes keep a null/empty TTML key beside a valid LRC/JSON
/// fallback. Choose the first parsable payload, not merely the first present key.
fn boidu_lines(value: &Value) -> Option<Vec<Line>> {
    ["ttml", "syncedLyrics", "lyrics", "lrc", "richSync"]
        .iter()
        .find_map(|key| {
            let raw = value.get(*key)?;
            let text = match raw {
                Value::String(text) if !text.trim().is_empty() => text.clone(),
                Value::Array(array) if !array.is_empty() => raw.to_string(),
                Value::Object(_) => raw.to_string(),
                _ => return None,
            };
            let lines = parse(&text);
            (!lines.is_empty()).then_some(lines)
        })
}

/// /get accepts title + artist without duration. Album/duration improve its
/// precision; an omitted duration is not a reason to switch to fuzzy /search.
fn lrclib_query(req: &LyricsRequest) -> Vec<(&'static str, String)> {
    let mut query = vec![
        ("track_name", req.title.clone()),
        ("artist_name", req.artists.clone()),
    ];
    if let Some(album) = req.album.as_ref().filter(|value| !value.is_empty()) {
        query.push(("album_name", album.clone()));
    }
    if let Some(duration) = request_duration(req).filter(|value| (1.0..=3600.0).contains(value)) {
        query.push(("duration", duration.to_string()));
    }
    query
}

fn identity_key(text: &str) -> String {
    let normalized = text
        .nfkc()
        .flat_map(char::to_lowercase)
        .map(|character| {
            if character.is_alphanumeric() {
                character
            } else {
                ' '
            }
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    if normalized.is_empty() {
        text.nfkc()
            .flat_map(char::to_lowercase)
            .collect::<String>()
            .trim()
            .to_owned()
    } else {
        normalized
    }
}

/// Keep version/feature words: removing Live, remix or featured performers can
/// attach correctly timed lyrics for the wrong recording. Missing metadata is
/// tolerated for compatible responses; present identity fields must agree.
fn lrclib_matches(req: &LyricsRequest, value: &Value) -> bool {
    for (expected, keys) in [
        (Some(req.title.as_str()), &["trackName", "name"][..]),
        (Some(req.artists.as_str()), &["artistName"][..]),
        (
            req.album
                .as_deref()
                .filter(|album| !album.trim().is_empty()),
            &["albumName"][..],
        ),
    ] {
        let Some(expected) = expected else { continue };
        let mut remote = None;
        for key in keys {
            match value.get(*key) {
                None | Some(Value::Null) => {}
                Some(Value::String(text)) if text.trim().is_empty() => {}
                Some(Value::String(text)) => {
                    remote = Some(text);
                    break;
                }
                Some(_) => return false,
            }
        }
        if let Some(remote) = remote {
            if identity_key(remote) != identity_key(expected) {
                return false;
            }
        }
    }
    if let (Some(expected), Some(remote)) = (request_duration(req), value.get("duration")) {
        let Some(remote) = remote
            .as_f64()
            .filter(|value| value.is_finite() && *value > 0.0)
        else {
            return false;
        };
        // The documented /get matching window is ±2 seconds.
        if (expected - remote).abs() > 2.0 {
            return false;
        }
    }
    true
}

async fn lrclib(req: &LyricsRequest) -> Result<Option<Document>, ()> {
    let response = crate::http::client()
        .get(format!("{}/get", super::LRCLIB_ROOT))
        .query(&lrclib_query(req))
        .header("User-Agent", USER_AGENT)
        .timeout(Duration::from_secs(5))
        .send()
        .await
        .map_err(|_| ())?;
    let Some(value) = json_response(response).await? else {
        return Ok(None);
    };
    if !lrclib_matches(req, &value) {
        return Ok(None);
    }
    lrclib_document(&value)
}

fn lrclib_document(value: &Value) -> Result<Option<Document>, ()> {
    if value.get("instrumental").and_then(Value::as_bool) == Some(true) {
        return Ok(Some(Document {
            source: "LRCLIB".into(),
            synced: false,
            instrumental: true,
            lines: vec![],
        }));
    }
    let synced = value
        .get("syncedLyrics")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty());
    let plain = value
        .get("plainLyrics")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty());
    let Some(raw) = synced.or(plain) else {
        return Ok(None);
    };
    if raw.len() > MAX_BODY_BYTES {
        return Err(());
    }
    let lines = if synced.is_some() {
        let lines = parse(raw);
        if lines.is_empty() {
            return Err(());
        }
        lines
    } else {
        let lines = raw
            .lines()
            .take(MAX_LINES + 1)
            .map(|line| Line::from(LyricLine::simple(None, line.to_owned())))
            .collect::<Vec<_>>();
        if lines.len() > MAX_LINES {
            return Err(());
        }
        lines
    };
    Ok(Some(Document {
        source: "LRCLIB".into(),
        synced: lines.iter().any(|line| line.time_ms.is_some()),
        instrumental: false,
        lines,
    }))
}

fn parse(text: &str) -> Vec<Line> {
    if text.len() > MAX_BODY_BYTES {
        return vec![];
    }
    let trimmed = text.trim_start_matches('\u{feff}').trim();
    let mut lines = if trimmed.starts_with('<') {
        parse_ttml(trimmed)
    } else if trimmed.starts_with('{') || (trimmed.starts_with('[') && trimmed.contains("\"")) {
        serde_json::from_str(trimmed)
            .ok()
            .map(parse_json)
            .unwrap_or_default()
    } else {
        parse_elrc(trimmed)
    };
    if lines.len() > MAX_LINES {
        return vec![];
    }
    let total_words = lines
        .iter()
        .map(|line| line.words.as_ref().map_or(0, Vec::len))
        .sum::<usize>();
    for line in &mut lines {
        if total_words > MAX_WORDS_TOTAL
            || line
                .words
                .as_ref()
                .is_some_and(|words| words.len() > MAX_WORDS_PER_LINE)
        {
            line.words = None;
        }
        validate_words(line);
        if line.time_ms.is_none() {
            line.time_ms = line
                .words
                .as_ref()
                .and_then(|words| words.first())
                .map(|word| word.start_ms);
        }
        if line.end_time_ms.is_none() {
            line.end_time_ms = line
                .words
                .as_ref()
                .and_then(|words| words.iter().map(|word| word.end_ms).max());
        }
        if line
            .end_time_ms
            .zip(line.time_ms)
            .is_some_and(|(end, start)| end <= start)
        {
            line.end_time_ms = None;
        }
    }
    lines
}

fn millis(number: f64, scale: f64) -> Option<u64> {
    let value = number * scale;
    (value.is_finite() && value >= 0.0 && value < u64::MAX as f64).then(|| value.round() as u64)
}

fn time(text: &str) -> Option<u64> {
    let text = text.trim();
    if let Some(number) = text.strip_suffix("ms") {
        return millis(number.parse().ok()?, 1.0);
    }
    if let Some(number) = text.strip_suffix('s') {
        return millis(number.parse().ok()?, 1000.0);
    }
    if let Some(number) = text.strip_suffix('m') {
        return millis(number.parse().ok()?, 60_000.0);
    }
    if let Some(number) = text.strip_suffix('h') {
        return millis(number.parse().ok()?, 3_600_000.0);
    }
    let parts = text.split(':').collect::<Vec<_>>();
    match parts.as_slice() {
        [seconds] => millis(seconds.parse().ok()?, 1000.0),
        [minutes, seconds] => {
            let minutes = minutes.parse::<u64>().ok()?;
            let seconds = seconds.parse::<f64>().ok()?;
            if !(0.0..60.0).contains(&seconds) {
                return None;
            }
            millis(minutes as f64 * 60.0 + seconds, 1000.0)
        }
        [hours, minutes, seconds] => {
            let hours = hours.parse::<u64>().ok()?;
            let minutes = minutes.parse::<u64>().ok()?;
            let seconds = seconds.parse::<f64>().ok()?;
            if minutes >= 60 || !(0.0..60.0).contains(&seconds) {
                return None;
            }
            millis(
                hours as f64 * 3600.0 + minutes as f64 * 60.0 + seconds,
                1000.0,
            )
        }
        _ => None,
    }
}

/// eLRC markers name the start of the following fragment. A final marker closes
/// the previous fragment, not an empty last word; no duration is fabricated.
fn parse_elrc(text: &str) -> Vec<Line> {
    let mut lines = super::parse_lrc(text)
        .into_iter()
        .map(Line::from)
        .collect::<Vec<_>>();
    for line in &mut lines {
        let original = line.text.clone();
        let mut remainder = original.as_str();
        let mut result = String::new();
        let mut segments: Vec<(String, u64)> = Vec::new();
        let mut previous: Option<u64> = None;
        let mut words = Vec::new();
        while let Some(open) = remainder.find('<') {
            let Some(close) = remainder[open..].find('>') else {
                break;
            };
            let close = open + close;
            let Some(marker) = time(&remainder[open + 1..close]) else {
                // A malformed markup/timing response is not a literal lyric.
                // Let the next provider supply a readable fallback instead.
                return vec![];
            };
            let fragment = &remainder[..open];
            result.push_str(fragment);
            if let Some(start) = previous {
                if !fragment.is_empty() {
                    segments.push((fragment.to_owned(), start));
                    if marker > start {
                        words.push(LyricWord {
                            text: fragment.to_owned(),
                            start_ms: start,
                            end_ms: marker,
                        });
                    }
                }
            } else if !fragment.trim().is_empty() {
                // A leading unmarked fragment starts at the line's known cue.
                if let Some(start) = line.time_ms {
                    segments.push((fragment.to_owned(), start));
                    if marker > start {
                        words.push(LyricWord {
                            text: fragment.to_owned(),
                            start_ms: start,
                            end_ms: marker,
                        });
                    }
                }
            }
            previous = Some(marker);
            remainder = &remainder[close + 1..];
        }
        result.push_str(remainder);
        if previous.is_some() {
            // An unclosed final fragment stays readable but has no manufactured
            // word end. Partial coverage is rejected by validate_words below.
            line.text = result;
            if !words.is_empty() && segments.len() == words.len() {
                line.words = Some(words);
            }
        }
    }
    lines
}

fn xml_attr<'a>(node: roxmltree::Node<'a, 'a>, name: &str) -> Option<&'a str> {
    node.attributes()
        .find(|attr| attr.name() == name)
        .map(|attr| attr.value())
}

fn role_attribute(node: roxmltree::Node<'_, '_>) -> Option<String> {
    let role = xml_attr(node, "role")?.trim();
    if role.split_whitespace().any(|role| role == "x-bg") {
        Some("background".into())
    } else if role
        .split_whitespace()
        .any(|role| matches!(role, "lead" | "x-lead"))
    {
        Some("lead".into())
    } else if role.is_empty() || is_overlay(node) {
        None
    } else {
        Some(role.to_owned())
    }
}

fn is_overlay(node: roxmltree::Node<'_, '_>) -> bool {
    xml_attr(node, "role").is_some_and(|roles| {
        roles
            .split_whitespace()
            .any(|role| matches!(role, "x-translation" | "x-roman" | "x-romanization"))
    })
}

fn inherited_attribute(node: roxmltree::Node<'_, '_>, name: &str) -> Option<String> {
    node.ancestors().find_map(|ancestor| {
        xml_attr(ancestor, name)
            .filter(|value| !value.trim().is_empty())
            .map(str::to_owned)
    })
}

#[derive(Clone, PartialEq, Eq, Hash)]
struct VoiceKey {
    role: Option<String>,
    agent: Option<String>,
    section: Option<String>,
    // Separate independently declared background phrases; nested repeated x-bg
    // wrappers remain one voice. Sibling spans with the same agent stay together.
    background: Option<roxmltree::NodeId>,
}

fn voice_key(node: roxmltree::Node<'_, '_>, paragraph: roxmltree::Node<'_, '_>) -> VoiceKey {
    let role = node.ancestors().find_map(role_attribute);
    let background = (role.as_deref() == Some("background")).then(|| {
        node.ancestors()
            .take_while(|ancestor| *ancestor != paragraph)
            .find(|ancestor| {
                role_attribute(*ancestor).as_deref() == Some("background")
                    && ancestor
                        .parent()
                        .and_then(|parent| parent.ancestors().find_map(role_attribute))
                        .as_deref()
                        != Some("background")
            })
            .unwrap_or(paragraph)
            .id()
    });
    VoiceKey {
        role,
        agent: inherited_attribute(node, "agent"),
        section: inherited_attribute(node, "song-part"),
        background,
    }
}

struct Voice {
    line: Line,
    last_span: Option<roxmltree::NodeId>,
    paragraph_voice: bool,
    common_scope: Option<roxmltree::NodeId>,
}

fn voice_index(
    voices: &mut Vec<Voice>,
    indices: &mut std::collections::HashMap<VoiceKey, usize>,
    key: VoiceKey,
    main_key: &VoiceKey,
    group_id: &str,
) -> usize {
    let next = voices.len();
    *indices.entry(key.clone()).or_insert_with(|| {
        voices.push(Voice {
            line: Line {
                time_ms: None,
                end_time_ms: None,
                text: String::new(),
                words: Some(Vec::new()),
                translation: None,
                role: key.role.clone(),
                agent: key.agent.clone(),
                group_id: Some(group_id.to_owned()),
                section: key.section.clone(),
            },
            last_span: None,
            paragraph_voice: key == *main_key,
            common_scope: None,
        });
        next
    })
}

/// Keep the deepest element containing every non-whitespace fragment of a voice.
/// A timed child that contains only part of the text cannot bound the whole line.
fn include_voice_fragment(voice: &mut Voice, node: roxmltree::Node<'_, '_>, fragment: &str) {
    if fragment.trim().is_empty() {
        return;
    }
    let range = node.range();
    let scope = voice
        .common_scope
        .and_then(|id| node.document().get_node(id));
    voice.common_scope = scope
        .and_then(|scope| {
            scope.ancestors().find(|ancestor| {
                let ancestor_range = ancestor.range();
                ancestor_range.start <= range.start && ancestor_range.end >= range.end
            })
        })
        .or_else(|| node.ancestors().find(|ancestor| ancestor.is_element()))
        .map(|scope| scope.id());
}

fn complete_interval(node: roxmltree::Node<'_, '_>) -> Option<(u64, u64)> {
    let start = xml_attr(node, "begin").and_then(time)?;
    let end = xml_attr(node, "end").and_then(time)?;
    (end > start).then_some((start, end))
}

fn parse_ttml(text: &str) -> Vec<Line> {
    // DTD/entity declarations are disabled by roxmltree's default parser. Limit
    // both response bytes and nodes; XML is input data, never executable markup.
    let options = roxmltree::ParsingOptions {
        nodes_limit: 40_000,
        ..Default::default()
    };
    let Ok(document) = roxmltree::Document::parse_with_options(text, options) else {
        return vec![];
    };
    if document.root_element().tag_name().name() != "tt" {
        return vec![];
    }
    let mut lines = Vec::new();
    for (paragraph_index, paragraph) in document
        .descendants()
        .filter(|node| node.is_element() && node.tag_name().name() == "p")
        .enumerate()
    {
        if paragraph.ancestors().any(is_overlay) {
            continue;
        }
        let group_id = format!("ttml:p:{paragraph_index}");
        let main_key = voice_key(paragraph, paragraph);
        let mut voices: Vec<Voice> = Vec::new();
        let mut indices = std::collections::HashMap::new();
        for node in paragraph.descendants() {
            if node
                .ancestors()
                .take_while(|ancestor| *ancestor != paragraph)
                .any(is_overlay)
            {
                continue;
            }
            let fragment = if node.is_text() {
                node.text()
            } else if node.is_element() && node.tag_name().name() == "br" {
                Some("\n")
            } else {
                None
            };
            let Some(fragment) = fragment else { continue };
            let index = voice_index(
                &mut voices,
                &mut indices,
                voice_key(node, paragraph),
                &main_key,
                &group_id,
            );
            let voice = &mut voices[index];
            include_voice_fragment(voice, node, fragment);
            voice.line.text.push_str(fragment);
            // Only actual timed spans supply segment timing. Keep syllables from
            // distinct spans separate even if their start/end happen to match.
            let timed = node
                .ancestors()
                .take_while(|ancestor| *ancestor != paragraph)
                .filter(|ancestor| ancestor.is_element() && ancestor.tag_name().name() == "span")
                .find_map(|span| {
                    Some((
                        span.id(),
                        time(xml_attr(span, "begin")?)?,
                        time(xml_attr(span, "end")?)?,
                    ))
                });
            let words = voice.line.words.as_mut().unwrap();
            if fragment.chars().all(char::is_whitespace) {
                if let Some(last) = words.last_mut() {
                    last.text.push_str(fragment);
                }
            } else if let Some((span, start, end)) = timed.filter(|(_, start, end)| end > start) {
                if let Some(last) = words.last_mut().filter(|last| {
                    voice.last_span == Some(span) && last.start_ms == start && last.end_ms == end
                }) {
                    last.text.push_str(fragment);
                } else {
                    words.push(LyricWord {
                        text: fragment.to_owned(),
                        start_ms: start,
                        end_ms: end,
                    });
                }
                voice.last_span = Some(span);
            } else {
                voice.last_span = None;
            }
        }
        for overlay in paragraph.descendants().filter(|node| {
            node.is_element()
                && xml_attr(*node, "role").is_some_and(|roles| {
                    roles.split_whitespace().any(|role| role == "x-translation")
                })
        }) {
            if overlay
                .ancestors()
                .skip(1)
                .take_while(|node| *node != paragraph)
                .any(is_overlay)
            {
                continue;
            }
            let value = overlay
                .descendants()
                .filter_map(|node| {
                    if node.is_text() {
                        node.text()
                    } else if node.is_element() && node.tag_name().name() == "br" {
                        Some("\n")
                    } else {
                        None
                    }
                })
                .collect::<String>();
            if !value.trim().is_empty() {
                let index = voice_index(
                    &mut voices,
                    &mut indices,
                    voice_key(overlay.parent().unwrap_or(paragraph), paragraph),
                    &main_key,
                    &group_id,
                );
                let translation = &mut voices[index].line.translation;
                if let Some(previous) = translation {
                    previous.push('\n');
                    previous.push_str(&value);
                } else {
                    *translation = Some(value);
                }
            }
        }
        let paragraph_start = xml_attr(paragraph, "begin").and_then(time);
        let paragraph_end = xml_attr(paragraph, "end").and_then(time);
        let has_text = voices
            .iter()
            .any(|voice| !voice.line.text.trim().is_empty());
        if !has_text && paragraph_start.is_some() {
            voice_index(
                &mut voices,
                &mut indices,
                main_key.clone(),
                &main_key,
                &group_id,
            );
        }
        for mut voice in voices {
            if voice.line.text.trim().is_empty() && (has_text || !voice.paragraph_voice) {
                continue;
            }
            let explicit_voice_interval = (!voice.paragraph_voice)
                .then(|| voice.common_scope.and_then(|id| document.get_node(id)))
                .flatten()
                .and_then(|scope| {
                    let ancestors = scope
                        .ancestors()
                        .take_while(|ancestor| *ancestor != paragraph)
                        .collect::<Vec<_>>();
                    let reliable = |(start, end): &(u64, u64)| {
                        paragraph_start.is_none_or(|paragraph| *start >= paragraph)
                            && paragraph_end.is_none_or(|paragraph| *end <= paragraph)
                            && voice.line.words.as_ref().is_none_or(|words| {
                                words
                                    .iter()
                                    .all(|word| word.start_ms >= *start && word.end_ms <= *end)
                            })
                    };
                    // A declared voice container retains its interval even if
                    // a single timed child also contains all of the text.
                    ancestors
                        .iter()
                        .copied()
                        .filter(|ancestor| {
                            ["role", "agent", "song-part"]
                                .iter()
                                .any(|name| xml_attr(*ancestor, name).is_some())
                        })
                        .filter_map(complete_interval)
                        .find(reliable)
                        .or_else(|| {
                            ancestors
                                .into_iter()
                                .filter_map(complete_interval)
                                .find(reliable)
                        })
                });
            // Validate against complete explicit bounds before deriving limits
            // from segments. Partial/invalid coverage keeps its container or p
            // interval; a partial max(end) must never become a line's true end.
            voice.line.time_ms = explicit_voice_interval
                .map(|(start, _)| start)
                .or(paragraph_start);
            voice.line.end_time_ms = explicit_voice_interval
                .map(|(_, end)| end)
                .or(paragraph_end);
            validate_words(&mut voice.line);
            if let Some(words) = &voice.line.words {
                if voice.line.time_ms.is_none()
                    || (!voice.paragraph_voice && explicit_voice_interval.is_none())
                {
                    voice.line.time_ms = words.iter().map(|word| word.start_ms).min();
                }
                if voice.line.end_time_ms.is_none()
                    || (!voice.paragraph_voice && explicit_voice_interval.is_none())
                {
                    voice.line.end_time_ms = words.iter().map(|word| word.end_ms).max();
                }
            }
            lines.push(voice.line);
            if lines.len() > MAX_LINES {
                return vec![];
            }
        }
    }
    lines
}

/// Explicit schemas only: snake_case/startTimeMs fields are milliseconds,
/// generic start/end fields are seconds. Numeric magnitude never guesses units.
fn json_time(value: &Value, ms_keys: &[&str], second_keys: &[&str]) -> Option<u64> {
    for key in ms_keys {
        if let Some(number) = value
            .get(*key)
            .and_then(|value| value.as_f64().or_else(|| value.as_str()?.parse().ok()))
        {
            return millis(number, 1.0);
        }
    }
    for key in second_keys {
        if let Some(raw) = value.get(*key) {
            if let Some(number) = raw.as_f64() {
                return millis(number, 1000.0);
            }
            if let Some(string) = raw.as_str() {
                return time(string);
            }
        }
    }
    None
}

fn parse_json(value: Value) -> Vec<Line> {
    let Some(array) = value
        .as_array()
        .or_else(|| value.get("lines").and_then(Value::as_array))
        .or_else(|| value.get("richSync").and_then(Value::as_array))
    else {
        return vec![];
    };
    array
        .iter()
        .filter_map(|item| {
            let words = item
                .get("words")
                .or_else(|| item.get("parts"))
                .and_then(Value::as_array)
                .map(|words| {
                    words
                        .iter()
                        .filter_map(|word| {
                            Some(LyricWord {
                                text: word
                                    .get("text")
                                    .or_else(|| word.get("word"))?
                                    .as_str()?
                                    .to_owned(),
                                start_ms: json_time(
                                    word,
                                    &["start_ms", "startTimeMs", "startTime"],
                                    &["start", "time"],
                                )?,
                                end_ms: json_time(
                                    word,
                                    &["end_ms", "endTimeMs", "endTime"],
                                    &["end"],
                                )?,
                            })
                        })
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default();
            let text = item
                .get("text")
                .or_else(|| item.get("line"))
                .or_else(|| item.get("words"))
                .and_then(Value::as_str)
                .map(str::to_owned)
                .unwrap_or_else(|| {
                    // Preserve even tokens whose timing is missing/invalid.
                    item.get("words")
                        .or_else(|| item.get("parts"))
                        .and_then(Value::as_array)
                        .map(|parts| {
                            parts
                                .iter()
                                .filter_map(|part| {
                                    part.get("text")
                                        .or_else(|| part.get("word"))
                                        .and_then(Value::as_str)
                                })
                                .collect::<String>()
                        })
                        .unwrap_or_default()
                });
            let start = json_time(
                item,
                &["time_ms", "start_ms", "startTimeMs", "startTime"],
                &["start", "time"],
            );
            if text.is_empty() && start.is_none() {
                return None;
            }
            Some(Line {
                time_ms: start,
                end_time_ms: json_time(item, &["end_ms", "endTimeMs", "endTime"], &["end"]),
                text,
                words: (!words.is_empty()).then_some(words),
                translation: item
                    .get("translation")
                    .and_then(Value::as_str)
                    .map(str::to_owned),
                role: item
                    .get("role")
                    .and_then(Value::as_str)
                    .map(|role| if role == "x-bg" { "background" } else { role }.to_owned()),
                agent: item.get("agent").and_then(Value::as_str).map(str::to_owned),
                group_id: item
                    .get("group_id")
                    .or_else(|| item.get("groupId"))
                    .and_then(Value::as_str)
                    .map(str::to_owned),
                section: item
                    .get("section")
                    .and_then(Value::as_str)
                    .map(str::to_owned),
            })
        })
        .collect()
}

/// Untimed punctuation belongs to the adjacent real segment; it does not create
/// another segment or a duration. Untimed letters still make coverage incomplete.
fn is_text_affix(character: char) -> bool {
    character.is_whitespace()
        || character.is_ascii_punctuation()
        || "“”‘’«»…—–¡¿、。，！？：；（）「」『』【】".contains(character)
}

/// Align token content to the exact display string without inventing missing
/// words/timing. Invalid or partial timing falls back to a whole readable line.
fn validate_words(line: &mut Line) {
    let Some(words) = line.words.as_mut() else {
        return;
    };
    let mut cursor = 0;
    let mut previous_start = None;
    let mut valid = !words.is_empty();
    for word in words.iter_mut() {
        let token = word.text.trim();
        if token.is_empty()
            || word.end_ms <= word.start_ms
            || previous_start.is_some_and(|start| word.start_ms < start)
            || line.time_ms.is_some_and(|start| word.start_ms < start)
            || line.end_time_ms.is_some_and(|end| word.end_ms > end)
        {
            valid = false;
            break;
        }
        let Some(relative) = line.text[cursor..].find(token) else {
            valid = false;
            break;
        };
        let start = cursor + relative;
        if !line.text[cursor..start].chars().all(is_text_affix) {
            valid = false;
            break;
        }
        let end = start + token.len();
        word.text = line.text[cursor..end].to_owned();
        cursor = end;
        previous_start = Some(word.start_ms);
    }
    if !line.text[cursor..].chars().all(is_text_affix) {
        valid = false
    }
    if valid {
        if let Some(last) = words.last_mut() {
            last.text.push_str(&line.text[cursor..])
        }
    } else {
        line.words = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{KaraokeLyricsInfo, LyricLineInfo, LyricsInfo};

    fn request() -> LyricsRequest {
        LyricsRequest {
            video_id: "test-video".into(),
            title: "Song".into(),
            artists: "Artist".into(),
            album: Some("Album".into()),
            duration: Some(200.0),
        }
    }

    fn lyric() -> Lyrics {
        Lyrics {
            source: "test".into(),
            synced: true,
            instrumental: false,
            lines: vec![LyricLine {
                time_ms: Some(1000),
                end_time_ms: Some(3000),
                text: "Uno dos".into(),
                words: Some(vec![
                    LyricWord {
                        text: "Uno ".into(),
                        start_ms: 1000,
                        end_ms: 2000,
                    },
                    LyricWord {
                        text: "dos".into(),
                        start_ms: 2000,
                        end_ms: 3000,
                    },
                ]),
                translation: Some("One two".into()),
            }],
        }
    }

    #[test]
    fn elrc_start_markers_have_real_nonzero_ranges_and_no_empty_word() {
        let lines = parse("[00:01.00]<00:01.00>Uno <00:02.00>dos<00:03.00>");
        assert_eq!(lines[0].text, "Uno dos");
        let words = lines[0].words.as_ref().unwrap();
        assert_eq!(words.len(), 2);
        assert_eq!((words[0].start_ms, words[0].end_ms), (1000, 2000));
        assert_eq!((words[1].start_ms, words[1].end_ms), (2000, 3000));
        assert_eq!(
            words
                .iter()
                .map(|word| word.text.as_str())
                .collect::<String>(),
            lines[0].text
        );
        assert_eq!(lines[0].end_time_ms, Some(3000));
    }

    #[test]
    fn elrc_unicode_spaces_and_unclosed_fragment_remain_readable() {
        let lines = parse("[00:01.00]<00:01.00>¡Ésta!  <00:02.00>私👩🏽‍💻<00:03.00>");
        assert_eq!(lines[0].text, "¡Ésta!  私👩🏽‍💻");
        assert_eq!(
            lines[0]
                .words
                .as_ref()
                .unwrap()
                .iter()
                .map(|word| word.text.as_str())
                .collect::<String>(),
            lines[0].text
        );
        let lines = parse("[00:01.00]<00:01.00>Uno <00:02.00>dos");
        assert_eq!(lines[0].text, "Uno dos");
        assert!(
            lines[0].words.is_none(),
            "the last word has no known end; never invent one"
        );
    }

    #[test]
    fn invalid_word_ranges_fall_back_without_losing_text() {
        for raw in [
            "[00:01.00]<00:01.00>Uno<00:01.00>",
            "[00:01.00]<00:03.00>Uno<00:02.00>",
        ] {
            let lines = parse(raw);
            assert_eq!(lines[0].text, "Uno");
            assert!(lines[0].words.is_none());
        }
    }

    #[test]
    fn ttml_namespaces_nested_spans_entities_translation_and_breaks() {
        let raw = r#"<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div>
        <p begin="1s" end="4s"><span begin="1s" end="2s"><span>Uno &amp; </span></span><br/><span begin="2s" end="4s">私 &#x1F600;</span><span ttm:role="x-translation">One and me</span></p>
        </div></body></tt>"#;
        let lines = parse(raw);
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].text, "Uno & \n私 😀");
        assert_eq!(lines[0].translation.as_deref(), Some("One and me"));
        let words = lines[0].words.as_ref().unwrap();
        assert_eq!(words.len(), 2);
        assert_eq!((words[0].start_ms, words[1].end_ms), (1000, 4000));
        assert_eq!(
            words
                .iter()
                .map(|word| word.text.as_str())
                .collect::<String>(),
            lines[0].text
        );
    }

    #[test]
    fn ttml_nested_background_retains_independent_voice_spaces_and_syllables() {
        let raw = r#"<tt xmlns:ttm="urn:ttm" xmlns:itunes="urn:itunes"><body ttm:agent="v1"><div itunes:song-part="Chorus"><p begin="1s" end="4s">¡<span begin="1s" end="1.5s">Ho</span><span begin="1.5s" end="2s">la</span>,  <span ttm:role="x-bg" ttm:agent="v2">(<span begin="1.2s" end="1.8s">E</span><span ttm:role="x-bg"><span begin="1.8s" end="2.6s">-co</span></span>)<span ttm:role="x-translation">(Echo)</span></span><span begin="3s" end="3.5s">tú!</span><span ttm:role="x-translation">Hello, you!</span></p></div></body></tt>"#;
        let lines = parse(raw);
        assert_eq!(lines.len(), 2);
        let lead = &lines[0];
        let background = &lines[1];
        assert_eq!(lead.text, "¡Hola,  tú!");
        assert_eq!(background.text, "(E-co)");
        assert_eq!(lead.role, None);
        assert_eq!(background.role.as_deref(), Some("background"));
        assert_eq!(lead.agent.as_deref(), Some("v1"));
        assert_eq!(background.agent.as_deref(), Some("v2"));
        assert_eq!(lead.section.as_deref(), Some("Chorus"));
        assert_eq!(background.section, lead.section);
        assert_eq!(lead.group_id.as_deref(), Some("ttml:p:0"));
        assert_eq!(background.group_id, lead.group_id);
        assert_eq!(background.time_ms, Some(1200));
        assert_eq!(background.end_time_ms, Some(2600));
        assert_eq!(lead.translation.as_deref(), Some("Hello, you!"));
        assert_eq!(background.translation.as_deref(), Some("(Echo)"));
        for (line, count) in [(lead, 3), (background, 2)] {
            let words = line.words.as_ref().unwrap();
            assert_eq!(words.len(), count);
            assert_eq!(
                words
                    .iter()
                    .map(|word| word.text.as_str())
                    .collect::<String>(),
                line.text
            );
        }
        let words = background.words.as_ref().unwrap();
        assert_eq!((words[0].start_ms, words[0].end_ms), (1200, 1800));
        assert_eq!((words[1].start_ms, words[1].end_ms), (1800, 2600));
    }

    #[test]
    fn ttml_agent_overrides_group_sibling_segments_without_reordering_voices() {
        let raw = r#"<tt xmlns:m="urn:metadata" xmlns:i="urn:itunes"><body m:agent="v1" i:song-part="Verse"><p begin="1s" end="5s"><span begin="1s" end="3s">First</span><span m:agent="v2" begin="2s" end="3s">Second </span><span m:agent="v2" begin="3s" end="4s">voice</span><span begin="4s" end="5s"> voice</span></p><p m:agent="v3" i:song-part="Outro" begin="8s" end="9s">(parentheses)</p></body></tt>"#;
        let lines = parse(raw);
        assert_eq!(lines.len(), 3);
        assert_eq!(lines[0].text, "First voice");
        assert_eq!(lines[1].text, "Second voice");
        assert_eq!(lines[0].agent.as_deref(), Some("v1"));
        assert_eq!(lines[1].agent.as_deref(), Some("v2"));
        assert_eq!(lines[1].time_ms, Some(2000));
        assert_eq!(lines[1].end_time_ms, Some(4000));
        assert_eq!(lines[1].words.as_ref().unwrap().len(), 2);
        assert_eq!(lines[2].agent.as_deref(), Some("v3"));
        assert_eq!(lines[2].section.as_deref(), Some("Outro"));
        assert_eq!(lines[2].group_id.as_deref(), Some("ttml:p:1"));
        assert_ne!(lines[2].group_id, lines[0].group_id);
        assert!(lines.iter().all(|line| line.role.is_none()));
        assert_eq!(parse(raw)[1].group_id, lines[1].group_id);
    }

    #[test]
    fn ttml_keeps_distinct_syllables_even_when_timestamps_match() {
        let lines = parse(
            r#"<tt><body><p><span begin="1s" end="2s">ca<span>n</span></span><span begin="1s" end="2s">ta</span><span begin="2s" end="3s">r</span></p></body></tt>"#,
        );
        let words = lines[0].words.as_ref().unwrap();
        assert_eq!(
            words
                .iter()
                .map(|word| word.text.as_str())
                .collect::<Vec<_>>(),
            ["can", "ta", "r"]
        );
        assert_eq!(words[0].start_ms, words[1].start_ms);
        assert_eq!(words[0].end_ms, words[1].end_ms);
    }

    #[test]
    fn ttml_inherited_background_does_not_duplicate_an_empty_lead() {
        let lines = parse(
            r#"<tt xmlns:m="urn:metadata"><body m:role="x-bg" m:agent="ensemble"><p begin="1s" end="3s"><span m:role="x-bg"><span begin="1s" end="2s">Ah</span></span>  <span begin="2s" end="3s">oh</span></p></body></tt>"#,
        );
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].text, "Ah  oh");
        assert_eq!(lines[0].role.as_deref(), Some("background"));
        assert_eq!(lines[0].agent.as_deref(), Some("ensemble"));
        assert_eq!(lines[0].words.as_ref().unwrap().len(), 2);
        let only_nested = parse(
            r#"<tt xmlns:m="urn:m"><body><p begin="1s" end="3s"><span m:role="x-bg"><span begin="1.2s" end="2.5s">Oh</span></span></p></body></tt>"#,
        );
        assert_eq!(only_nested.len(), 1);
        assert_eq!(only_nested[0].role.as_deref(), Some("background"));
        assert_eq!(only_nested[0].time_ms, Some(1200));
    }

    #[test]
    fn ttml_preserves_edge_spaces_and_falls_back_if_words_are_incomplete() {
        let lines = parse(
            r#"<tt xmlns:m="urn:metadata"><body><p begin="1s" end="4s">  <span begin="1s" end="2s">One</span> missing <span m:role="x-bg">(background)</span>  </p></body></tt>"#,
        );
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[0].text, "  One missing   ");
        assert!(lines[0].words.is_none());
        assert_eq!(lines[1].text, "(background)");
        assert!(lines[1].words.is_none());
        assert_eq!(lines[1].time_ms, Some(1000));
        assert_eq!(lines[1].end_time_ms, Some(4000));
    }

    #[test]
    fn partial_background_coverage_uses_paragraph_bounds_without_a_partial_end() {
        for container in ["", "begin='1.5s'", "begin='5s' end='2s'"] {
            let raw = format!("<tt xmlns:m='urn:m'><body><p begin='1s' end='6s'><span m:role='x-bg' {container}><span begin='2s' end='3s'>One</span> missing</span></p></body></tt>");
            let lines = parse(&raw);
            assert_eq!(lines.len(), 1);
            let line = &lines[0];
            assert_eq!(line.text, "One missing");
            assert!(line.words.is_none());
            assert_eq!(
                (line.time_ms, line.end_time_ms),
                (Some(1000), Some(6000)),
                "{container}"
            );
        }
    }

    #[test]
    fn partial_voice_without_a_complete_container_has_no_invented_end() {
        for paragraph in ["begin='1s'", ""] {
            let raw = format!("<tt xmlns:m='urn:m'><body><p {paragraph}><span m:role='x-bg'><span begin='2s' end='3s'>One</span> missing</span></p></body></tt>");
            let line = parse(&raw).remove(0);
            assert_eq!(line.text, "One missing");
            assert!(line.words.is_none());
            assert_eq!(
                line.time_ms,
                if paragraph.is_empty() {
                    None
                } else {
                    Some(1000)
                }
            );
            assert_eq!(line.end_time_ms, None);
        }
    }

    #[test]
    fn complete_voice_container_bounds_survive_word_validation_fallback() {
        for voice in ["m:role='x-bg'", "m:agent='v2'"] {
            let raw = format!("<tt xmlns:m='urn:m'><body><p begin='1s' end='8s'><span {voice} begin='1.5s' end='5s'><span begin='2s' end='3s'>One</span> missing</span></p></body></tt>");
            let line = parse(&raw).remove(0);
            assert_eq!(line.text, "One missing");
            // The following fragment inherits the container's start, after a
            // later child. This timing order cannot drive word highlighting.
            assert!(line.words.is_none());
            assert_eq!(
                (line.time_ms, line.end_time_ms),
                (Some(1500), Some(5000)),
                "{voice}"
            );
        }
    }

    #[test]
    fn complete_voice_container_keeps_explicit_bounds_beyond_complete_words() {
        let lines = parse("<tt xmlns:m='urn:m'><body><p begin='1s' end='8s'><span m:role='x-bg' begin='1.5s' end='5s'><span begin='2s' end='3s'>One </span><span begin='3s' end='4s'>two</span></span></p></body></tt>");
        let line = &lines[0];
        assert_eq!(line.text, "One two");
        assert_eq!(line.words.as_ref().unwrap().len(), 2);
        assert_eq!((line.time_ms, line.end_time_ms), (Some(1500), Some(5000)));
        for voice in ["m:role='x-bg'", "m:agent='v2'"] {
            let raw = format!("<tt xmlns:m='urn:m'><body><p begin='1s' end='8s'><span {voice} begin='1.5s' end='5s'><span begin='2s' end='3s'>One</span></span></p></body></tt>");
            let line = parse(&raw).remove(0);
            assert_eq!(
                (line.time_ms, line.end_time_ms),
                (Some(1500), Some(5000)),
                "{voice}"
            );
            let words = line.words.unwrap();
            assert_eq!(words.len(), 1);
            assert_eq!((words[0].start_ms, words[0].end_ms), (2000, 3000));
        }
    }

    fn provider_document(source: &str, raw: &str) -> Document {
        let lines = parse(raw);
        Document {
            source: source.into(),
            synced: lines.iter().any(|line| line.time_ms.is_some()),
            instrumental: false,
            lines,
        }
    }

    #[test]
    fn fresh_ttml_metadata_wins_over_classic_synced_cache_and_plain_provider_lines() {
        let fresh = provider_document("Boidu", "<tt xmlns:m='urn:m' xmlns:i='urn:i'><body m:agent='v1'><div i:song-part='Chorus'><p begin='1s' end='4s'>Main<span m:role='x-bg'>Background</span></p></div></body></tt>");
        assert!(!has_words(&fresh));
        let lrclib = provider_document("LRCLIB", "[00:01.00]Main Background");
        let mut classic = line_only(lyric());
        classic.source = "classic cache".into();
        let fresh_providers = prefer(Some(fresh), lrclib);
        let chosen = prefer_classic_fallback(fresh_providers, Some(classic)).unwrap();
        assert_eq!(chosen.source, "Boidu");
        assert_eq!(chosen.lines.len(), 2);
        assert_eq!(chosen.lines[1].role.as_deref(), Some("background"));
        assert_eq!(chosen.lines[0].agent.as_deref(), Some("v1"));
        assert_eq!(chosen.lines[0].section.as_deref(), Some("Chorus"));
        assert_eq!(chosen.lines[0].group_id.as_deref(), Some("ttml:p:0"));
    }

    #[test]
    fn fallback_quality_preserves_synced_over_plain_and_provider_order_in_ties() {
        let plain = provider_document("plain", "Plain text");
        let boidu = provider_document("Boidu", "[00:01.00]Timed line");
        let lrclib = provider_document("LRCLIB", "[00:01.00]Another timed line");
        let chosen = prefer(prefer(Some(plain.clone()), boidu.clone()), lrclib.clone()).unwrap();
        assert_eq!(chosen.source, "Boidu");
        assert_eq!(
            prefer(Some(boidu.clone()), plain.clone()).unwrap().source,
            "Boidu"
        );
        assert_eq!(prefer(Some(plain), lrclib).unwrap().source, "LRCLIB");
        let metadata_plain = provider_document(
            "metadata plain",
            "<tt xmlns:m='urn:m'><body><p m:agent='v1'>Plain text</p></body></tt>",
        );
        assert_eq!(
            prefer_classic_fallback(Some(metadata_plain), Some(line_only(lyric())))
                .unwrap()
                .source,
            "test"
        );
        let mut classic = line_only(lyric());
        classic.source = "classic cache".into();
        assert_eq!(
            prefer_classic_fallback(Some(boidu), Some(classic))
                .unwrap()
                .source,
            "Boidu"
        );
    }

    #[test]
    fn rich_voice_metadata_survives_record_conversion_and_v4_cache_roundtrip() {
        let mut document = Document::from(lyric());
        let line = &mut document.lines[0];
        line.role = Some("background".into());
        line.agent = Some("v2".into());
        line.group_id = Some("ttml:p:7".into());
        line.section = Some("Chorus".into());
        let json = serde_json::to_string(&CacheEntry {
            version: SCHEMA_VERSION,
            fetched_at: 10,
            lyrics: Some(document),
        })
        .unwrap();
        let decoded = cached(serde_json::from_str(&json).unwrap(), 11)
            .unwrap()
            .unwrap();
        let info = KaraokeLyricsInfo::from(decoded);
        assert_eq!(info.lines[0].role.as_deref(), Some("background"));
        assert_eq!(info.lines[0].agent.as_deref(), Some("v2"));
        assert_eq!(info.lines[0].group_id.as_deref(), Some("ttml:p:7"));
        assert_eq!(info.lines[0].section.as_deref(), Some("Chorus"));
        assert_eq!(info.lines[0].words.len(), 2);
        let old_key = cache_key(&request(), true).replacen("karaoke:v4:", "karaoke:v3:", 1);
        assert_ne!(old_key, cache_key(&request(), true));
        for version in [1, 2, 3] {
            assert!(cached(
                CacheEntry {
                    version,
                    fetched_at: 10,
                    lyrics: Some(lyric().into())
                },
                11
            )
            .is_none());
        }
        let old_json = serde_json::json!({
            "version": 1,
            "fetched_at": 10,
            "lyrics": lyric(),
        });
        assert!(cached(serde_json::from_value(old_json).unwrap(), 11).is_none());
        let classic = KaraokeLyricsInfo::from(lyric());
        assert!(classic.lines.iter().all(|line| line.role.is_none()
            && line.agent.is_none()
            && line.group_id.is_none()
            && line.section.is_none()));
    }

    #[test]
    fn malformed_inline_markup_is_not_displayed_as_lyric_text() {
        assert!(parse("[00:01.00]<00:bad>Uno<00:02.00>").is_empty());
        assert!(parse("[00:01.00]<html>Service unavailable</html>").is_empty());
    }

    #[test]
    fn ttml_line_timing_does_not_fabricate_word_timing() {
        let lines = parse(
            r#"<tt><body><p begin="1s" end="4s">A plain timed line</p><p>Plain text</p></body></tt>"#,
        );
        assert_eq!(lines[0].time_ms, Some(1000));
        assert_eq!(lines[0].end_time_ms, Some(4000));
        assert!(lines.iter().all(|line| line.words.is_none()));
        assert_eq!(lines[1].time_ms, None);
    }

    #[test]
    fn ttml_rejects_dtd_html_and_malformed_xml() {
        for raw in [
            "<!DOCTYPE tt [<!ENTITY x 'expanded'>]><tt><p>&x;</p></tt>",
            "<html><body><p>Service unavailable</p></body></html>",
            "<tt><p begin='1s'>broken",
        ] {
            assert!(parse(raw).is_empty());
        }
    }

    #[test]
    fn json_units_are_schema_based_even_for_long_tracks() {
        let lines = parse(
            r#"[{"start":500.25,"end":503,"text":"Hold on","words":[{"start":500.25,"end":501,"word":"Hold"},{"start":501,"end":503,"word":"on"}]}]"#,
        );
        let words = lines[0].words.as_ref().unwrap();
        assert_eq!(lines[0].time_ms, Some(500250));
        assert_eq!(words[1].end_ms, 503000);
        assert_eq!(
            words
                .iter()
                .map(|word| word.text.as_str())
                .collect::<String>(),
            "Hold on"
        );
        let lines = parse(
            r#"{"lines":[{"startTimeMs":100,"endTimeMs":400,"text":"Hi","words":[{"start_ms":100,"end_ms":400,"text":"Hi"}]}]}"#,
        );
        assert_eq!(lines[0].words.as_ref().unwrap()[0].start_ms, 100);
        assert_eq!(lines[0].words.as_ref().unwrap()[0].end_ms, 400);
    }

    #[test]
    fn partial_json_or_mismatched_words_use_readable_line_fallback() {
        let lines = parse(
            r#"[{"start":1,"end":3,"text":"One two","words":[{"start":1,"end":2,"word":"One"}]}]"#,
        );
        assert_eq!(lines[0].text, "One two");
        assert!(lines[0].words.is_none());
        let lines =
            parse(r#"[{"start":1,"text":"One","words":[{"start":-1,"end":2,"word":"One"}]}]"#);
        assert!(lines[0].words.is_none());
    }

    #[test]
    fn oversized_documents_and_word_arrays_are_bounded() {
        assert!(parse(&"a".repeat(MAX_BODY_BYTES + 1)).is_empty());
        let lines = (0..MAX_LINES + 1)
            .map(|_| "[00:01.00]One")
            .collect::<Vec<_>>()
            .join("\n");
        assert!(parse(&lines).is_empty());
        let words = (0..MAX_WORDS_PER_LINE + 1)
            .map(|index| serde_json::json!({"word":"x", "start_ms":index, "end_ms":index+1}))
            .collect::<Vec<_>>();
        let value = serde_json::json!([{"text":"x".repeat(words.len()),"words":words}]);
        let lines = parse(&value.to_string());
        assert!(lines[0].words.is_none());
        assert_eq!(lines[0].text.len(), MAX_WORDS_PER_LINE + 1);
    }

    #[test]
    fn time_parser_rejects_nonfinite_negative_and_invalid_clock_values() {
        for raw in ["NaN", "-1s", "inf", "1:60", "1:99:00", "1:2:3:4"] {
            assert_eq!(time(raw), None, "{raw}");
        }
        assert_eq!(time("12:30.125"), Some(750125));
        assert_eq!(time("10.25ms"), Some(10));
    }

    #[test]
    fn rich_contract_preserves_words_translation_and_instrumental() {
        let info = KaraokeLyricsInfo::from(lyric());
        assert_eq!(info.provider, "test");
        assert_eq!(info.lines[0].words[0].text, "Uno ");
        assert_eq!(info.lines[0].words[1].end_ms, 3000);
        assert_eq!(info.lines[0].translation.as_deref(), Some("One two"));
        let instrumental = KaraokeLyricsInfo::from(Lyrics {
            source: "test".into(),
            synced: false,
            instrumental: true,
            lines: vec![],
        });
        assert!(instrumental.instrumental);
        // Compile-time assertion that classic constructors and signatures remain unchanged.
        let classic = LyricsInfo {
            provider: "test".into(),
            is_synced: true,
            lines: vec![LyricLineInfo {
                time_ms: Some(1),
                end_time_ms: None,
                text: "Old panel".into(),
            }],
        };
        assert_eq!(classic.lines[0].text, "Old panel");
    }

    #[test]
    fn cache_expiry_schema_and_request_signature_are_independent_of_classic() {
        let req = request();
        let key = cache_key(&req, true);
        assert!(key.starts_with("karaoke:v4:"));
        assert_ne!(key, req.video_id);
        assert_ne!(key, cache_key(&req, false));
        let mut other = request();
        other.duration = Some(220.0);
        assert_ne!(key, cache_key(&other, true));
        assert!(cached(
            CacheEntry {
                version: SCHEMA_VERSION,
                fetched_at: 10,
                lyrics: Some(lyric().into())
            },
            11
        )
        .is_some());
        assert!(cached(
            CacheEntry {
                version: SCHEMA_VERSION,
                fetched_at: 10,
                lyrics: Some(lyric().into())
            },
            10 + HIT_TTL
        )
        .is_none());
        assert!(cached(
            CacheEntry {
                version: 0,
                fetched_at: 10,
                lyrics: Some(lyric().into())
            },
            11
        )
        .is_none());
        assert!(cached(
            CacheEntry {
                version: SCHEMA_VERSION,
                fetched_at: 10,
                lyrics: None
            },
            11
        )
        .unwrap()
        .is_none());
        assert!(cached(
            CacheEntry {
                version: SCHEMA_VERSION,
                fetched_at: 10,
                lyrics: None
            },
            10 + MISS_TTL
        )
        .is_none());
        assert!(cached(
            CacheEntry {
                version: SCHEMA_VERSION,
                fetched_at: 10,
                lyrics: Some(lyric().into())
            },
            9
        )
        .is_none());
    }

    #[test]
    fn unknown_duration_cache_is_provisional_for_hits_lines_and_misses() {
        let mut unknown = request();
        unknown.duration = None;
        for lyrics in [Some(lyric().into()), Some(line_only(lyric())), None] {
            let entry = || CacheEntry {
                version: SCHEMA_VERSION,
                fetched_at: 10,
                lyrics: lyrics.clone(),
            };
            assert!(cached_for_request(entry(), 10 + PROVISIONAL_TTL - 1, &unknown).is_some());
            assert!(cached_for_request(entry(), 10 + PROVISIONAL_TTL, &unknown).is_none());
            assert!(cached_for_request(entry(), 10 + PROVISIONAL_TTL, &request()).is_some());
        }
        assert_ne!(cache_key(&unknown, true), cache_key(&request(), true));
        for duration in [0.0, -1.0, f64::NAN, f64::INFINITY] {
            unknown.duration = Some(duration);
            let entry = CacheEntry {
                version: SCHEMA_VERSION,
                fetched_at: 10,
                lyrics: None,
            };
            assert!(cached_for_request(entry, 10 + PROVISIONAL_TTL, &unknown).is_none());
        }
    }

    #[test]
    fn failed_provider_does_not_cement_a_low_quality_fallback() {
        let plain = provider_document("Boidu", "Readable plain text");
        let synced_lines = provider_document("LRCLIB", "[00:01.00]Readable synced line");
        let classic = line_only(lyric());
        for fallback in [&plain, &synced_lines, &classic] {
            assert!(!cache_fallback(fallback, true));
            assert!(cache_fallback(fallback, false));
        }
        assert!(cache_fallback(&lyric().into(), true));
        let instrumental = Document {
            source: "LRCLIB".into(),
            synced: false,
            instrumental: true,
            lines: vec![],
        };
        assert!(cache_fallback(&instrumental, true));
    }

    #[test]
    fn lrclib_get_query_omits_unknown_or_unsupported_duration_without_changing_endpoint() {
        let mut req = request();
        for duration in [None, Some(0.0), Some(f64::NAN), Some(0.5), Some(3601.0)] {
            req.duration = duration;
            let query = lrclib_query(&req);
            assert!(query
                .iter()
                .any(|(key, value)| *key == "track_name" && value == "Song"));
            assert!(query
                .iter()
                .any(|(key, value)| *key == "artist_name" && value == "Artist"));
            assert!(query.iter().all(|(key, _)| *key != "duration"));
        }
        for duration in [1.0, 200.25, 3600.0] {
            req.duration = Some(duration);
            assert_eq!(
                lrclib_query(&req)
                    .iter()
                    .find(|(key, _)| *key == "duration")
                    .unwrap()
                    .1
                    .parse::<f64>()
                    .unwrap(),
                duration
            );
        }
    }

    #[test]
    fn lrclib_identity_matching_preserves_versions_features_and_recording_length() {
        let req = request();
        let exact = serde_json::json!({"trackName":"Song","artistName":"Artist","albumName":"Album","duration":200.0});
        assert!(lrclib_matches(&req, &exact));
        for (field, wrong) in [
            ("trackName", "Song (Live)"),
            ("trackName", "Song - Remix"),
            ("trackName", "Song feat. Guest"),
            ("artistName", "Other Artist"),
            ("artistName", "Artist feat. Guest"),
            ("albumName", "Album (Deluxe)"),
        ] {
            let mut candidate = exact.clone();
            candidate[field] = Value::String(wrong.into());
            assert!(!lrclib_matches(&req, &candidate), "{field}: {wrong}");
        }
        for duration in [197.99, 202.01, 0.0, -1.0] {
            let mut candidate = exact.clone();
            candidate["duration"] = serde_json::json!(duration);
            assert!(!lrclib_matches(&req, &candidate));
        }
        for duration in [198.0, 202.0] {
            let mut candidate = exact.clone();
            candidate["duration"] = serde_json::json!(duration);
            assert!(lrclib_matches(&req, &candidate));
        }
        let mut featured = request();
        featured.title = "Song (feat. Guest)".into();
        assert!(!lrclib_matches(&featured, &exact));
        let mut unknown = request();
        unknown.duration = None;
        assert!(lrclib_matches(&unknown, &exact));
        assert!(lrclib_matches(
            &req,
            &serde_json::json!({"syncedLyrics":"[00:01.00]Compatible payload"})
        ));
    }

    #[test]
    fn lrclib_identity_normalizes_unicode_case_and_spacing_without_losing_words() {
        let mut req = request();
        req.title = "Cafe\u{301} — Live (feat. Guest)".into();
        req.artists = "ARTIST  & Guest".into();
        req.album = None;
        let candidate = serde_json::json!({"trackName":"CAFÉ Live feat Guest","artistName":"Artist, Guest","duration":200});
        assert!(lrclib_matches(&req, &candidate));
        let mut wrong = candidate.clone();
        wrong["trackName"] = serde_json::json!("CAFÉ");
        assert!(!lrclib_matches(&req, &wrong));
        assert!(lrclib_matches(
            &request(),
            &serde_json::json!({"name":"Song","artistName":"Artist"})
        ));
        assert!(lrclib_matches(
            &request(),
            &serde_json::json!({"trackName":null,"name":"Song","artistName":"Artist","albumName":""})
        ));
        let mut punctuation = request();
        punctuation.title = "?".into();
        assert!(!lrclib_matches(
            &punctuation,
            &serde_json::json!({"trackName":"!"})
        ));
    }

    #[test]
    fn experimental_writes_and_legacy_read_fallback_leave_classic_rows_intact() {
        let db = crate::db::Db::open(std::path::Path::new(":memory:")).unwrap();
        let req = request();
        let classic = serde_json::to_string(&lyric()).unwrap();
        db.put_lyrics(&req.video_id, Some(&classic), 10);
        let entry = CacheEntry {
            version: SCHEMA_VERSION,
            fetched_at: 11,
            lyrics: Some(lyric().into()),
        };
        db.put_lyrics(
            &cache_key(&req, true),
            Some(&serde_json::to_string(&entry).unwrap()),
            11,
        );
        assert_eq!(
            db.get_lyrics(&req.video_id, 12, 3600).flatten().as_deref(),
            Some(classic.as_str())
        );
        let safe = line_only(lyric());
        assert!(safe.lines[0].words.is_none());
        assert_eq!(safe.lines[0].translation.as_deref(), Some("One two"));
    }
    async fn local_response(status: &str, body: &str) -> reqwest::Response {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let wire = format!("HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\nContent-Type: application/json\r\n\r\n{body}", body.len());
        tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut request = vec![0; 4096];
            let _ = stream.read(&mut request).await;
            let _ = stream.write_all(wire.as_bytes()).await;
        });
        reqwest::Client::builder()
            .no_proxy()
            .build()
            .unwrap()
            .get(format!("http://{address}/"))
            .timeout(Duration::from_secs(2))
            .send()
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn transient_http_and_json_errors_cannot_be_negative_cache_results() {
        for status in [
            "400 Bad Request",
            "401 Unauthorized",
            "429 Too Many Requests",
            "503 Service Unavailable",
        ] {
            assert!(
                json_response(local_response(status, r#"{"error":"temporary"}"#).await)
                    .await
                    .is_err()
            );
        }
        assert!(
            json_response(local_response("200 OK", "<html>unavailable</html>").await)
                .await
                .is_err()
        );
        assert!(json_response(local_response("404 Not Found", "{}").await)
            .await
            .unwrap()
            .is_none());
        assert!(
            json_response(local_response("200 OK", r#"{"ttml":"ok"}"#).await)
                .await
                .unwrap()
                .is_some()
        );
    }

    #[tokio::test]
    async fn response_byte_limit_applies_before_parsing_external_json() {
        let body = "x".repeat(MAX_BODY_BYTES + 1);
        assert!(json_response(local_response("200 OK", &body).await)
            .await
            .is_err());
    }
    #[test]
    fn json_preserves_tokens_without_timing_when_no_line_text_was_supplied() {
        let lines =
            parse(r#"[{"words":[{"text":"One ","start":1,"end":2},{"text":"two","start":2}]}]"#);
        assert_eq!(lines[0].text, "One two");
        assert!(lines[0].words.is_none());
    }

    #[test]
    #[ignore = "optional local provider sample; set SIDEB_KARAOKE_SAMPLE; never embeds song text"]
    fn inspect_retained_provider_sample_without_printing_lyrics() {
        let path = std::env::var("SIDEB_KARAOKE_SAMPLE")
            .expect("set SIDEB_KARAOKE_SAMPLE to a JSON response");
        let raw = std::fs::read_to_string(path).unwrap();
        let value: Value = serde_json::from_str(&raw).unwrap();
        let lines = parse(value.get("ttml").and_then(Value::as_str).unwrap());
        let rich_lines = lines
            .iter()
            .filter(|line| line.words.as_ref().is_some_and(|words| !words.is_empty()))
            .count();
        let word_count = lines
            .iter()
            .map(|line| line.words.as_ref().map_or(0, Vec::len))
            .sum::<usize>();
        assert!(!lines.is_empty());
        assert!(rich_lines > 0);
        for line in &lines {
            if let Some(words) = &line.words {
                assert_eq!(
                    words
                        .iter()
                        .map(|word| word.text.as_str())
                        .collect::<String>(),
                    line.text
                );
                assert!(words.iter().all(|word| word.end_ms > word.start_ms));
            }
        }
        println!(
            "retained provider sample: lines={}, rich_lines={}, timed_segments={}, background_lines={} (text omitted)",
            lines.len(),
            rich_lines,
            word_count,
            lines.iter().filter(|line| line.role.as_deref() == Some("background")).count()
        );
    }
    #[test]
    fn boidu_chooses_usable_payload_after_null_empty_or_invalid_ttml() {
        for ttml in [
            Value::Null,
            Value::String(String::new()),
            serde_json::json!({"unexpected":true}),
            Value::String("<broken>".into()),
        ] {
            let value = serde_json::json!({"ttml":ttml,"syncedLyrics":"[00:01.00]A complete line"});
            let lines = boidu_lines(&value).unwrap();
            assert_eq!(lines[0].text, "A complete line");
        }
        let value = serde_json::json!({"ttml":"", "richSync":[{"start":1,"end":2,"text":"Word","words":[{"start":1,"end":2,"word":"Word"}]}]});
        assert!(boidu_lines(&value).unwrap()[0].words.is_some());
    }

    #[test]
    fn lrclib_plain_and_synced_payload_limits_are_errors_not_negative_hits() {
        let plain = (0..MAX_LINES + 1)
            .map(|_| "A plain line")
            .collect::<Vec<_>>()
            .join("\n");
        assert!(lrclib_document(&serde_json::json!({"plainLyrics":plain})).is_err());
        let synced = (0..MAX_LINES + 1)
            .map(|_| "[00:01.00]A timed line")
            .collect::<Vec<_>>()
            .join("\n");
        assert!(lrclib_document(&serde_json::json!({"syncedLyrics":synced})).is_err());
        let hit = lrclib_document(&serde_json::json!({"plainLyrics":"One\nTwo"}))
            .unwrap()
            .unwrap();
        assert_eq!(hit.lines.len(), 2);
        assert!(!hit.synced);
    }
}
