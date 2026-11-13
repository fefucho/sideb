//! Spotify catalogue lookup for the `resolve` request: YouTube Music metadata in, a confident
//! `spotify:track:` URI out. Ported from the sibling `spotify-canvas` plugin (no crate
//! dependency between them). Uses the Web Player's Pathfinder GraphQL `searchDesktop` persisted
//! query, re-discovering its hash from the public bundle when the stored one goes stale.
//! Matching is deliberately conservative: a miss is better than the wrong recording.
//!
//! Never format reqwest errors: they can carry URLs and credentials.

use reqwest::{Client, Response};
use serde_json::{json, Value};
use std::sync::Mutex;
use std::time::Duration;
use tokio::sync::Semaphore;
use unicode_normalization::UnicodeNormalization;

const SEARCH_HASH: &str = "eef7cc54888d91bdd6802623477873caa3948ae173a0c34fd86827b267e94c03";
const JSON_LIMIT: usize = 2 * 1024 * 1024;
const BROWSER_UA: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
/// Concurrent lookups allowed at once (a host may resolve a whole playlist).
const MAX_CONCURRENT: usize = 4;

#[derive(Debug, PartialEq)]
pub enum Error {
    Auth,
    RateLimited,
    Unsupported,
    Network,
    Invalid,
    Unresolved,
    StaleQuery,
}
impl From<reqwest::Error> for Error {
    fn from(_: reqwest::Error) -> Self {
        Self::Network
    }
}

pub struct Query {
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub duration_ms: Option<u64>,
}
#[derive(Debug, PartialEq)]
pub struct Match {
    pub uri: String,
    pub title: String,
    pub artists: Vec<String>,
    pub duration_ms: u64,
}

fn normalized(value: &str) -> String {
    // Preserve version qualifiers, punctuation and digits; prefer a miss to the wrong recording.
    value
        .nfkc()
        .collect::<String>()
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}
fn base_clean_title(value: &str) -> String {
    let mut s = normalized(value);
    let prefixes = [
        " (feat.",
        " (feat ",
        " (featuring ",
        " [feat.",
        " [feat ",
        " [featuring ",
        " (with ",
        " [with ",
        " (official video",
        " (official music video",
        " (official audio",
        " [official video",
        " [official music video",
        " [official audio",
        " (video)",
        " [video]",
    ];
    for p in prefixes {
        if let Some((base, _)) = s.split_once(p) {
            s = base.trim().to_string();
        }
    }
    s
}
/// Drops notes that name the same recording in another mastering or edition ("(Remasterizado
/// 2007)", "- 2011 Remaster", "[Deluxe]"). Live, edit, remix and version notes are kept: those
/// are different recordings, and the duration check alone would not always tell them apart.
fn without_edition_note(title: &str) -> String {
    const EDITION: [&str; 9] = [
        "remaster",
        "remasterizad",
        "mono",
        "stereo",
        "deluxe",
        "bonus track",
        "anniversary",
        "aniversario",
        "explicit",
    ];
    let is_edition = |note: &str| EDITION.iter().any(|word| note.contains(word));
    let mut s = title.to_owned();
    for (open, close) in [('(', ')'), ('[', ']')] {
        while let Some(start) = s.rfind(open) {
            let Some(len) = s[start..].find(close) else {
                break;
            };
            if !is_edition(&s[start..start + len]) {
                break;
            }
            s.replace_range(start..start + len + close.len_utf8(), "");
            s = s.trim().to_owned();
        }
    }
    if let Some((base, note)) = s.rsplit_once(" - ") {
        if is_edition(note) {
            s = base.trim().to_owned();
        }
    }
    s
}
fn title_matches(candidate: &str, requested: &str) -> bool {
    let c = normalized(candidate);
    let r = normalized(requested);
    if c == r {
        return true;
    }
    let cb = base_clean_title(&c);
    let rb = base_clean_title(&r);
    if cb == rb || cb == r || c == rb {
        return true;
    }
    let (ce, re) = (without_edition_note(&cb), without_edition_note(&rb));
    !ce.is_empty() && ce == re
}
fn artist_matches(candidate_artists: &[&str], requested_artist: &str) -> bool {
    let r = normalized(requested_artist);
    for a in candidate_artists {
        let na = normalized(a);
        if na == r || r.contains(&na) || na.contains(&r) {
            return true;
        }
        for sep in [",", " & ", " feat. ", " feat ", " featuring ", " with "] {
            if let Some(lead) = r.split(sep).next() {
                if na == lead.trim() {
                    return true;
                }
            }
        }
    }
    false
}
fn base_clean_album(value: &str) -> String {
    let mut s = normalized(value);
    let prefixes = [
        " (10th anniversary",
        " (anniversary",
        " (deluxe",
        " [deluxe",
        " (special",
        " [special",
        " (bonus",
        " [bonus",
        " (remaster",
        " [remaster",
    ];
    for p in prefixes {
        if let Some((base, _)) = s.split_once(p) {
            s = base.trim().to_string();
        }
    }
    s
}
fn album_matches(candidate: &str, requested: &str) -> bool {
    let c = normalized(candidate);
    let r = normalized(requested);
    if c == r {
        return true;
    }
    let cb = base_clean_album(&c);
    let rb = base_clean_album(&r);
    cb == rb || cb == r || c == rb
}
fn valid_track_uri(uri: &str) -> bool {
    uri.strip_prefix("spotify:track:")
        .is_some_and(|id| id.len() == 22 && id.bytes().all(|b| b.is_ascii_alphanumeric()))
}

fn check_status(status: u16) -> Result<(), Error> {
    match status {
        200..=299 => Ok(()),
        401 | 403 => Err(Error::Auth),
        429 => Err(Error::RateLimited),
        _ => Err(Error::Network),
    }
}
async fn bounded_body(mut response: Response, limit: usize) -> Result<Vec<u8>, Error> {
    if response.content_length().is_some_and(|n| n > limit as u64) {
        return Err(Error::Invalid);
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await? {
        if bytes.len().saturating_add(chunk.len()) > limit {
            return Err(Error::Invalid);
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}
async fn bounded(response: Response, limit: usize) -> Result<Vec<u8>, Error> {
    check_status(response.status().as_u16())?;
    bounded_body(response, limit).await
}
fn parse_graph(value: Value) -> Result<Value, Error> {
    if value
        .get("errors")
        .is_some_and(|e| !e.as_array().is_some_and(Vec::is_empty))
    {
        let stale = value
            .get("errors")
            .and_then(Value::as_array)
            .is_some_and(|errors| {
                errors.iter().any(|error| {
                    error
                        .get("message")
                        .and_then(Value::as_str)
                        .is_some_and(|message| {
                            let message = message.to_ascii_lowercase();
                            message.contains("persisted")
                                || message.contains("query hash")
                                || message.contains("sha256")
                        })
                })
            });
        return Err(if stale {
            Error::StaleQuery
        } else {
            Error::Unsupported
        });
    }
    value
        .get("data")
        .filter(|v| v.is_object())
        .cloned()
        .ok_or(Error::Unsupported)
}
fn web_player_script(html: &str) -> Option<&str> {
    let needle = "https://open.spotifycdn.com/cdn/build/web-player/web-player.";
    let mut offset = 0;
    while let Some(relative) = html[offset..].find(needle) {
        let start = offset + relative;
        let rest = &html[start..];
        let end = rest
            .find(|c: char| c == '"' || c == '\'' || c.is_whitespace() || c == '<' || c == '>')
            .unwrap_or(rest.len());
        let candidate = &rest[..end];
        if candidate.ends_with(".js") {
            return Some(candidate);
        }
        offset = start + needle.len();
    }
    None
}
fn persisted_hash<'a>(document: &'a str, operation: &str) -> Option<&'a str> {
    let needle = format!("\"{operation}\",\"query\",\"");
    let start = document.find(&needle)? + needle.len();
    let candidate = document.get(start..start + 64)?;
    candidate
        .bytes()
        .all(|byte| byte.is_ascii_hexdigit())
        .then_some(candidate)
}
fn chunk_id<'a>(script: &'a str, chunk: &str) -> Option<&'a str> {
    let needle = format!(":\"{chunk}\"");
    let end = script.find(&needle)?;
    let prefix = script.get(..end)?;
    let start = prefix
        .rfind(|c: char| !c.is_ascii_digit())
        .map_or(0, |index| index + 1);
    script.get(start..end).filter(|id| !id.is_empty())
}
fn chunk_hashes<'a>(script: &'a str, id: &str) -> Vec<&'a str> {
    let needle = format!("{id}:\"");
    let mut hashes = Vec::new();
    let mut offset = 0;
    while let Some(relative) = script[offset..].find(&needle) {
        let start = offset + relative;
        let preceded_by_digit = script
            .get(..start)
            .and_then(|prefix| prefix.chars().last())
            .is_some_and(|c| c.is_ascii_digit());
        let value_start = start + needle.len();
        if !preceded_by_digit {
            if let Some(candidate) = script.get(value_start..value_start + 8) {
                if candidate.bytes().all(|byte| byte.is_ascii_hexdigit()) {
                    hashes.push(candidate);
                }
            }
        }
        offset = value_start;
    }
    hashes
}
fn search_chunk_urls(script_url: &str, script: &str) -> Vec<String> {
    let Some(id) = chunk_id(script, "xpui-routes-search") else {
        return Vec::new();
    };
    let base = script_url
        .rsplit_once('/')
        .map_or(script_url, |(base, _)| base);
    let mut urls = Vec::new();
    for hash in chunk_hashes(script, id) {
        let url = format!("{base}/xpui-routes-search.{hash}.js");
        if !urls.contains(&url) {
            urls.push(url);
        }
    }
    urls
}
async fn discover_search_hash(http: &Client) -> Result<String, Error> {
    let response = http
        .get("https://open.spotify.com/")
        .header("user-agent", BROWSER_UA)
        .send()
        .await?;
    let html = bounded(response, 512 * 1024).await?;
    let html = std::str::from_utf8(&html).map_err(|_| Error::Unsupported)?;
    let script_url = web_player_script(html)
        .ok_or(Error::Unsupported)?
        .to_owned();
    let response = http
        .get(&script_url)
        .header("user-agent", BROWSER_UA)
        .send()
        .await?;
    let script = bounded(response, 8 * 1024 * 1024).await?;
    let script = std::str::from_utf8(&script).map_err(|_| Error::Unsupported)?;
    if let Some(hash) = persisted_hash(script, "searchDesktop") {
        return Ok(hash.to_owned());
    }
    for url in search_chunk_urls(&script_url, script) {
        let Ok(response) = http.get(&url).header("user-agent", BROWSER_UA).send().await else {
            continue;
        };
        let Ok(chunk) = bounded(response, 512 * 1024).await else {
            continue;
        };
        let Ok(chunk) = std::str::from_utf8(&chunk) else {
            continue;
        };
        if let Some(hash) = persisted_hash(chunk, "searchDesktop") {
            return Ok(hash.to_owned());
        }
    }
    Err(Error::Unsupported)
}
async fn graph(
    http: &Client,
    token: &str,
    client_token: &str,
    hash: &str,
    variables: Value,
) -> Result<Value, Error> {
    let response = http.post("https://api-partner.spotify.com/pathfinder/v2/query")
        .bearer_auth(token).header("client-token", client_token)
        .json(&json!({"operationName":"searchDesktop","variables":variables,"extensions":{"persistedQuery":{"version":1,"sha256Hash":hash}}}))
        .send().await?;
    let status = response.status().as_u16();
    let data = bounded_body(response, JSON_LIMIT).await?;
    if !(200..=299).contains(&status) {
        if let Ok(value) = serde_json::from_slice::<Value>(&data) {
            if let Err(error @ Error::StaleQuery) = parse_graph(value) {
                return Err(error);
            }
        }
        return Err(match status {
            401 | 403 => Error::Auth,
            429 => Error::RateLimited,
            _ => Error::Network,
        });
    }
    parse_graph(serde_json::from_slice(&data).map_err(|_| Error::Unsupported)?)
}
fn search_variables(query: &Query) -> Value {
    json!({
        "searchTerm": format!("{} {}", query.title, query.artist),
        "offset": 0,
        "limit": 10,
        "numberOfTopResults": 5,
        "includeArtistHasConcertsField": false,
        "includeAudiobooks": false,
        "includeAuthors": false,
        "includePreReleases": false,
        "includeAlbumPreReleases": false,
        "includeEpisodeContentRatingsV2": false,
        "isPrefix": null,
        "sectionFilters": ["GENERIC"],
    })
}
/// Picks the best confident candidate: title and artist must match, duration within 45 s (4 s
/// counts as the same recording), album agreement ranks higher. When the caller does not know the
/// duration (many YouTube Music rows carry none) title and artist decide alone, in search order.
fn select_track(data: &Value, query: &Query) -> Result<Match, Error> {
    let expected_ms = query.duration_ms.filter(|ms| *ms > 0);
    let items = data
        .pointer("/searchV2/tracksV2/items")
        .and_then(Value::as_array)
        .ok_or(Error::Unsupported)?;
    // Buckets in priority order: exact+album, exact, near+album, near.
    let mut buckets: [Option<Match>; 4] = [None, None, None, None];
    for item in items {
        let Some(candidate) = item.pointer("/item/data") else {
            continue;
        };
        let Some(name) = candidate.get("name").and_then(Value::as_str) else {
            continue;
        };
        if !title_matches(name, &query.title) {
            continue;
        }
        let Some(ms) = candidate
            .pointer("/duration/totalMilliseconds")
            .and_then(Value::as_u64)
        else {
            continue;
        };
        let delta = expected_ms.map_or(0, |expected| ms.abs_diff(expected));
        let artists: Vec<&str> = candidate
            .pointer("/artists/items")
            .and_then(Value::as_array)
            .map(|arr| {
                arr.iter()
                    .filter_map(|a| a.pointer("/profile/name").and_then(Value::as_str))
                    .collect()
            })
            .unwrap_or_default();
        if !artist_matches(&artists, &query.artist) {
            continue;
        }
        let album_match = query
            .album
            .as_deref()
            .filter(|a| !a.trim().is_empty())
            .is_some_and(|album| {
                candidate
                    .pointer("/albumOfTrack/name")
                    .and_then(Value::as_str)
                    .is_some_and(|a| album_matches(a, album))
            });
        let Some(uri) = candidate
            .get("uri")
            .and_then(Value::as_str)
            .filter(|s| valid_track_uri(s))
        else {
            continue;
        };
        let slot = match (delta <= 4000, delta <= 45_000, album_match) {
            (true, _, true) => 0,
            (true, _, false) => 1,
            (false, true, true) => 2,
            (false, true, false) => 3,
            _ => continue,
        };
        if buckets[slot].is_none() {
            buckets[slot] = Some(Match {
                uri: uri.to_owned(),
                title: name.to_owned(),
                artists: artists.iter().map(|a| a.to_string()).collect(),
                duration_ms: ms,
            });
        }
    }
    buckets
        .into_iter()
        .flatten()
        .next()
        .ok_or(Error::Unresolved)
}

/// Shared by every lookup: an unauthenticated-redirect-free HTTP client, the discovered hash and
/// a concurrency gate.
pub struct Searcher {
    http: Client,
    discovered: Mutex<Option<String>>,
    gate: Semaphore,
}
impl Searcher {
    pub fn new() -> Option<Self> {
        let http = Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .timeout(Duration::from_secs(8))
            .connect_timeout(Duration::from_secs(4))
            .user_agent(BROWSER_UA)
            .build()
            .ok()?;
        Some(Self {
            http,
            discovered: Mutex::new(None),
            gate: Semaphore::new(MAX_CONCURRENT),
        })
    }
    fn stored_hash(&self) -> Option<String> {
        self.discovered.lock().ok().and_then(|hash| hash.clone())
    }
    pub async fn resolve(
        &self,
        bearer: &str,
        client_token: &str,
        query: &Query,
    ) -> Result<Match, Error> {
        let _permit = self.gate.acquire().await.map_err(|_| Error::Unsupported)?;
        let variables = search_variables(query);
        let hash = self.stored_hash().unwrap_or_else(|| SEARCH_HASH.to_owned());
        let data = match graph(&self.http, bearer, client_token, &hash, variables.clone()).await {
            Ok(data) => data,
            Err(Error::StaleQuery) => {
                let fresh =
                    tokio::time::timeout(Duration::from_secs(6), discover_search_hash(&self.http))
                        .await
                        .map_err(|_| Error::Unsupported)??;
                if let Ok(mut slot) = self.discovered.lock() {
                    *slot = Some(fresh.clone());
                }
                graph(&self.http, bearer, client_token, &fresh, variables).await?
            }
            Err(error) => return Err(error),
        };
        select_track(&data, query)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn query() -> Query {
        Query {
            title: "Song (Live)".into(),
            artist: "Artist".into(),
            album: Some("Album".into()),
            duration_ms: Some(200_000),
        }
    }
    fn candidate(id: &str) -> Value {
        json!({"item":{"data":{"name":"Song (Live)","duration":{"totalMilliseconds":200000},"artists":{"items":[{"profile":{"name":"Artist"}}]},"albumOfTrack":{"name":"Album"},"uri":format!("spotify:track:{id}")}}})
    }
    fn page(items: Vec<Value>) -> Value {
        json!({"searchV2":{"tracksV2":{"items":items}}})
    }

    #[test]
    fn matching_is_conservative() {
        let id = "1234567890123456789012";
        let found = select_track(&page(vec![candidate(id)]), &query()).unwrap();
        assert_eq!(found.uri, format!("spotify:track:{id}"));
        assert_eq!(found.title, "Song (Live)");
        assert_eq!(found.artists, vec!["Artist".to_string()]);
        assert_eq!(found.duration_ms, 200_000);
        // Duplicate catalogue entries: the top ranked result wins.
        let two = page(vec![candidate(id), candidate("2234567890123456789012")]);
        assert_eq!(
            select_track(&two, &query()).unwrap().uri,
            format!("spotify:track:{id}")
        );
        let mut q = query();
        q.title = "Song".into();
        assert_eq!(
            select_track(&page(vec![candidate(id)]), &q),
            Err(Error::Unresolved)
        );
        q = query();
        // Unknown duration (many YouTube Music rows have none): title and artist decide.
        q.duration_ms = None;
        assert_eq!(
            select_track(&page(vec![candidate(id)]), &q).map(|m| m.uri),
            Ok(format!("spotify:track:{id}"))
        );
        q.duration_ms = Some(0);
        assert!(select_track(&page(vec![candidate(id)]), &q).is_ok());
        q = query();
        q.duration_ms = Some(300_000);
        assert_eq!(
            select_track(&page(vec![candidate(id)]), &q),
            Err(Error::Unresolved)
        );
        q = query();
        q.artist = "Somebody Else".into();
        assert_eq!(
            select_track(&page(vec![candidate(id)]), &q),
            Err(Error::Unresolved)
        );
        assert_eq!(select_track(&json!({}), &query()), Err(Error::Unsupported));
    }

    #[test]
    fn edition_notes_do_not_block_a_match() {
        assert!(title_matches(
            "De Música Ligera - Remasterizado 2007",
            "De Música Ligera (Remasterizado 2007)"
        ));
        assert!(title_matches(
            "De Música Ligera",
            "De Música Ligera (Remasterizado 2007)"
        ));
        assert!(title_matches("Heroes - 2017 Remaster", "Heroes"));
        assert!(title_matches("Song [Deluxe]", "Song"));
        // Different recordings stay different.
        assert!(!title_matches("Song - Live", "Song"));
        assert!(!title_matches("Song (Radio Edit)", "Song"));
        assert!(!title_matches(
            "Midnight City",
            "Midnight City (slowed to perfection)"
        ));
    }

    #[test]
    fn album_and_exact_duration_rank_higher() {
        let mut near = candidate("1234567890123456789012");
        near["item"]["data"]["duration"]["totalMilliseconds"] = json!(230_000);
        let mut other_album = candidate("2234567890123456789012");
        other_album["item"]["data"]["albumOfTrack"]["name"] = json!("Compilation");
        let best = candidate("3234567890123456789012");
        let picked = select_track(&page(vec![near, other_album, best]), &query()).unwrap();
        assert_eq!(picked.uri, "spotify:track:3234567890123456789012");
        let mut near = candidate("1234567890123456789012");
        near["item"]["data"]["duration"]["totalMilliseconds"] = json!(230_000);
        let mut other_album = candidate("2234567890123456789012");
        other_album["item"]["data"]["albumOfTrack"]["name"] = json!("Compilation");
        // Exact duration without album beats near duration with album.
        assert_eq!(
            select_track(&page(vec![near, other_album]), &query())
                .unwrap()
                .uri,
            "spotify:track:2234567890123456789012"
        );
    }

    #[test]
    fn featured_artist_and_album_edition_resilience() {
        let candidate = json!({"item":{"data":{
            "name":"Instant Crush (feat. Julian Casablancas)",
            "duration":{"totalMilliseconds":337560},
            "artists":{"items":[{"profile":{"name":"Daft Punk"}},{"profile":{"name":"Julian Casablancas"}}]},
            "albumOfTrack":{"name":"Random Access Memories (10th Anniversary Edition)"},
            "uri":"spotify:track:2cGxRwrMyEAp8dEbuZaVv6"}}});
        let q = Query {
            title: "Instant Crush".into(),
            artist: "Daft Punk".into(),
            album: Some("Random Access Memories".into()),
            duration_ms: Some(338_000),
        };
        let found = select_track(&page(vec![candidate]), &q).unwrap();
        assert_eq!(found.uri, "spotify:track:2cGxRwrMyEAp8dEbuZaVv6");
        assert_eq!(found.artists.len(), 2);
    }

    #[test]
    fn errors_never_become_absence() {
        assert_eq!(
            parse_graph(json!({"errors":[{"message":"PersistedQueryNotFound"}]})),
            Err(Error::StaleQuery)
        );
        assert_eq!(
            parse_graph(json!({"errors":[{"message":"Bad request"}]})),
            Err(Error::Unsupported)
        );
        assert_eq!(
            parse_graph(json!({"errors":[{"message":"The query hash is invalid"}]})),
            Err(Error::StaleQuery)
        );
        assert_eq!(check_status(401), Err(Error::Auth));
        assert_eq!(check_status(429), Err(Error::RateLimited));
    }

    #[test]
    fn discovery_parsers_read_current_web_player_layout() {
        let html = r#"<link href="https://open.spotifycdn.com/cdn/build/web-player/web-player.430d3681.css"><script src="https://open.spotifycdn.com/cdn/build/web-player/web-player.c263f3db.js"></script>"#;
        assert_eq!(
            web_player_script(html),
            Some("https://open.spotifycdn.com/cdn/build/web-player/web-player.c263f3db.js")
        );
        let script =
            r#"var a={4406:"xpui-routes-search"};var b={4406:"04981b42",4406:"a0a5ee13"};"#;
        assert_eq!(
            search_chunk_urls(
                "https://open.spotifycdn.com/cdn/build/web-player/web-player.c263f3db.js",
                script
            ),
            vec![
                "https://open.spotifycdn.com/cdn/build/web-player/xpui-routes-search.04981b42.js"
                    .to_owned(),
                "https://open.spotifycdn.com/cdn/build/web-player/xpui-routes-search.a0a5ee13.js"
                    .to_owned(),
            ]
        );
        let chunk = r#"new X("searchDesktop","query","eef7cc54888d91bdd6802623477873caa3948ae173a0c34fd86827b267e94c03",null);"#;
        assert_eq!(persisted_hash(chunk, "searchDesktop"), Some(SEARCH_HASH));
        assert_eq!(persisted_hash(chunk, "missing"), None);
        assert_eq!(
            persisted_hash("\"searchDesktop\",\"query\",\"abc\"", "searchDesktop"),
            None
        );
    }

    #[test]
    fn search_variables_match_current_web_player() {
        let variables = search_variables(&query());
        assert_eq!(variables["searchTerm"], "Song (Live) Artist");
        assert_eq!(variables["sectionFilters"], json!(["GENERIC"]));
        assert_eq!(variables["isPrefix"], Value::Null);
    }

    /// Live check against Spotify. Needs a Web Player bearer in the file named by
    /// `SIDEB_JAM_LIVE_TOKEN_FILE`; run with `cargo test live_resolve -- --ignored --nocapture`.
    #[tokio::test]
    #[ignore]
    async fn live_resolve() {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let path = std::env::var("SIDEB_JAM_LIVE_TOKEN_FILE").expect("token file");
        let raw = std::fs::read_to_string(path).unwrap();
        let bearer = raw.trim().trim_start_matches("Bearer ").trim();
        let http = Client::builder().user_agent(BROWSER_UA).build().unwrap();
        let body = json!({"client_data":{"client_version":"1.2.42.432.g3121","client_id":"d8a5ed958d274c2e8ee717e6a4b0971d",
            "js_sdk_data":{"device_brand":"Apple","device_model":"MacBookPro","os":"Mac OS","os_version":"10.15.7","device_id":"0123456789abcdef0123456789abcdef","device_type":"computer"}}});
        let token: Value = http
            .post("https://clienttoken.spotify.com/v1/clienttoken")
            .header("accept", "application/json")
            .json(&body)
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        let client_token = token
            .pointer("/granted_token/token")
            .and_then(Value::as_str)
            .unwrap()
            .to_owned();
        let searcher = Searcher::new().unwrap();
        // Rows shaped exactly like YouTube Music search results (title, artists, album, "m:ss").
        let rows: Vec<Value> = match std::env::var("SIDEB_JAM_LIVE_QUERIES") {
            Ok(file) => serde_json::from_str(&std::fs::read_to_string(file).unwrap()).unwrap(),
            Err(_) => vec![
                json!({"title":"Blinding Lights","artists":"The Weeknd","album":"After Hours","duration":"3:20"}),
            ],
        };
        for row in rows {
            let title = row["title"].as_str().unwrap_or("");
            let artist = row["artists"].as_str().unwrap_or("");
            let album = row["album"].as_str();
            let ms = row["duration"]
                .as_str()
                .unwrap_or("0")
                .split(':')
                .fold(0u64, |acc, part| {
                    acc * 60 + part.parse::<u64>().unwrap_or(0)
                })
                * 1000;
            let query = Query {
                title: title.into(),
                artist: artist.into(),
                album: album.map(String::from),
                duration_ms: Some(ms),
            };
            let outcome = searcher.resolve(bearer, &client_token, &query).await;
            println!(
                "{title} / {artist}: {:?}",
                outcome
                    .map(|m| (m.uri, m.title, m.duration_ms))
                    .map_err(|e| format!("{e:?}"))
            );
        }
    }
}
