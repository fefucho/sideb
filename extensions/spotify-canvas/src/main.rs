//! One request per process. Credentials arrive only on stdin; stdout is protocol JSON.
use rand::RngCore;
use reqwest::{Client, Response, Url};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{path::PathBuf, time::Duration};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use unicode_normalization::UnicodeNormalization;

const CANVAS_HASH: &str = "575138ab27cd5c1b3e54da54d0a7cc8d85485402de26340c2145f0f6bb5e7a9f";
const SEARCH_HASH: &str = "eef7cc54888d91bdd6802623477873caa3948ae173a0c34fd86827b267e94c03";
const JSON_LIMIT: usize = 2 * 1024 * 1024;
const MEDIA_LIMIT: usize = 24 * 1024 * 1024;
const BROWSER_UA: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Request {
    protocol_version: u32,
    request_id: String,
    credential: String,
    output_directory: PathBuf,
    track: Track,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Track {
    video_id: String,
    title: String,
    artist: String,
    album: Option<String>,
    duration_seconds: Option<u64>,
    explicit: Option<bool>,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Reply {
    protocol_version: u32,
    request_id: String,
    status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    file_name: Option<&'static str>,
}
#[derive(Debug, PartialEq)]
enum Error {
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
fn title_matches(candidate: &str, requested: &str) -> bool {
    let c = normalized(candidate);
    let r = normalized(requested);
    if c == r {
        return true;
    }
    let cb = base_clean_title(&c);
    let rb = base_clean_title(&r);
    cb == rb || cb == r || c == rb
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
fn bearer(raw: &str) -> Result<&str, Error> {
    let value = raw.trim();
    let value = if value
        .get(..7)
        .is_some_and(|prefix| prefix.eq_ignore_ascii_case("bearer "))
    {
        &value[7..]
    } else {
        value
    };
    if value.is_empty() || value.len() > 8192 || !value.bytes().all(|b| b.is_ascii_graphic()) {
        return Err(Error::Auth);
    }
    Ok(value)
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
struct DiscoveredHashes {
    search: Option<String>,
    canvas: Option<String>,
}
async fn discover_hashes(http: &Client) -> Result<DiscoveredHashes, Error> {
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
    let canvas = persisted_hash(script, "canvas").map(str::to_owned);
    let mut search = persisted_hash(script, "searchDesktop").map(str::to_owned);
    if search.is_none() {
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
                search = Some(hash.to_owned());
                break;
            }
        }
    }
    Ok(DiscoveredHashes { search, canvas })
}
async fn discover_once<'a>(
    http: &Client,
    cache: &'a mut Option<DiscoveredHashes>,
) -> Result<&'a DiscoveredHashes, Error> {
    if cache.is_none() {
        let result = tokio::time::timeout(Duration::from_secs(6), discover_hashes(http)).await;
        *cache = Some(match result {
            Ok(Ok(hashes)) => hashes,
            _ => return Err(Error::Unsupported),
        });
    }
    cache.as_ref().ok_or(Error::Unsupported)
}
async fn graph(
    http: &Client,
    token: &str,
    client_token: &str,
    operation: &str,
    hash: &str,
    variables: Value,
) -> Result<Value, Error> {
    let response = http.post("https://api-partner.spotify.com/pathfinder/v2/query")
        .bearer_auth(token).header("client-token", client_token)
        .json(&json!({"operationName":operation,"variables":variables,"extensions":{"persistedQuery":{"version":1,"sha256Hash":hash}}}))
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
async fn client_token(http: &Client) -> Result<String, Error> {
    let mut random = [0u8; 16];
    rand::thread_rng().fill_bytes(&mut random);
    let device_id: String = random.iter().map(|b| format!("{b:02x}")).collect();
    let response = http.post("https://clienttoken.spotify.com/v1/clienttoken").json(&json!({"client_data":{
        "client_version":"1.2.42.432.g3121", "client_id":"d8a5ed958d274c2e8ee717e6a4b0971d",
        "js_sdk_data":{"device_brand":"Apple","device_model":"MacBookPro","os":"Mac OS","os_version":"10.15.7","device_id":device_id,"device_type":"computer"}
    }})).header("accept", "application/json").send().await?;
    let bytes = bounded(response, 65536).await?;
    let data: Value = serde_json::from_slice(&bytes).map_err(|_| Error::Unsupported)?;
    data.pointer("/granted_token/token")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .map(String::from)
        .ok_or(Error::Unsupported)
}
fn select_track(data: &Value, track: &Track) -> Result<String, Error> {
    let duration = track.duration_seconds.ok_or(Error::Unresolved)?;
    let items = data
        .pointer("/searchV2/tracksV2/items")
        .and_then(Value::as_array)
        .ok_or(Error::Unsupported)?;
    let expected_ms = duration.saturating_mul(1000);

    let mut exact_with_album = Vec::new();
    let mut exact = Vec::new();
    let mut metadata_with_album = Vec::new();
    let mut metadata = Vec::new();

    for item in items {
        let Some(candidate) = item.pointer("/item/data") else {
            continue;
        };
        let Some(name) = candidate.get("name").and_then(Value::as_str) else {
            continue;
        };
        if !title_matches(name, &track.title) {
            continue;
        }
        let Some(ms) = candidate
            .pointer("/duration/totalMilliseconds")
            .and_then(Value::as_u64)
        else {
            continue;
        };
        let duration_delta = ms.abs_diff(expected_ms);
        let candidate_artists: Vec<&str> = candidate
            .pointer("/artists/items")
            .and_then(Value::as_array)
            .map(|arr| {
                arr.iter()
                    .filter_map(|a| a.pointer("/profile/name").and_then(Value::as_str))
                    .collect()
            })
            .unwrap_or_default();

        if !artist_matches(&candidate_artists, &track.artist) {
            continue;
        }

        let album_match =
            if let Some(album) = track.album.as_deref().filter(|a| !a.trim().is_empty()) {
                candidate
                    .pointer("/albumOfTrack/name")
                    .and_then(Value::as_str)
                    .is_some_and(|a| album_matches(a, album))
            } else {
                false
            };

        if let Some(explicit) = track.explicit {
            let rating = candidate
                .pointer("/contentRating/label")
                .and_then(Value::as_str);
            if rating != Some(if explicit { "EXPLICIT" } else { "NONE" }) {
                continue;
            }
        }
        if let Some(uri) = candidate
            .get("uri")
            .and_then(Value::as_str)
            .filter(|s| valid_track_uri(s))
        {
            let uri_str = uri.to_owned();
            if duration_delta <= 4000 {
                if album_match {
                    exact_with_album.push(uri_str);
                } else {
                    exact.push(uri_str);
                }
            } else if duration_delta <= 45_000 {
                // Some YouTube Music results are the full music video while the
                // Spotify recording is shorter.
                if album_match {
                    metadata_with_album.push(uri_str);
                } else {
                    metadata.push(uri_str);
                }
            }
        }
    }

    if let Some(first) = exact_with_album.into_iter().next() {
        return Ok(first);
    }
    if let Some(first) = exact.into_iter().next() {
        return Ok(first);
    }
    if let Some(first) = metadata_with_album.into_iter().next() {
        return Ok(first);
    }
    if let Some(first) = metadata.into_iter().next() {
        return Ok(first);
    }

    Err(Error::Unresolved)
}
fn search_variables(track: &Track) -> Value {
    json!({
        "searchTerm": format!("{} {}", track.title, track.artist),
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
fn valid_track_uri(uri: &str) -> bool {
    uri.strip_prefix("spotify:track:")
        .is_some_and(|id| id.len() == 22 && id.bytes().all(|b| b.is_ascii_alphanumeric()))
}
fn media_url(value: &str) -> Result<Url, Error> {
    let url = Url::parse(value).map_err(|_| Error::Invalid)?;
    // Exact hosts only: do not send session credentials to a media URL or follow redirects.
    if url.scheme() != "https"
        || !url.username().is_empty()
        || url.password().is_some()
        || url.port().is_some()
        || !matches!(url.host_str(), Some("canvaz.scdn.co" | "canvas.scdn.co"))
    {
        return Err(Error::Invalid);
    }
    Ok(url)
}
fn canvas_url(data: &Value) -> Result<Option<Url>, Error> {
    let track = data
        .get("trackUnion")
        .filter(|v| v.is_object())
        .ok_or(Error::Unsupported)?;
    let canvas = track.get("canvas").ok_or(Error::Unsupported)?;
    if canvas.is_null() {
        return Ok(None);
    }
    let value = canvas
        .get("url")
        .and_then(Value::as_str)
        .ok_or(Error::Unsupported)?;
    // Static/JPEG Canvas remains a normal fallback to the existing cover in this first version.
    if canvas
        .get("type")
        .and_then(Value::as_str)
        .is_some_and(|s| s.contains("IMAGE"))
    {
        return Ok(None);
    }
    media_url(value).map(Some)
}
async fn resolve(request: &Request) -> Result<bool, Error> {
    if request.protocol_version != 1
        || request.request_id.len() > 128
        || request.track.video_id.len() > 128
        || request.track.title.len() > 1000
        || request.track.artist.len() > 1000
        || !request.output_directory.is_absolute()
    {
        return Err(Error::Invalid);
    }
    let token = bearer(&request.credential)?;
    let http = Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(8))
        .connect_timeout(Duration::from_secs(4))
        .build()?;
    let client_token = client_token(&http).await?;
    let mut discovered = None;
    let variables = search_variables(&request.track);
    let search = match graph(
        &http,
        token,
        &client_token,
        "searchDesktop",
        SEARCH_HASH,
        variables.clone(),
    )
    .await
    {
        Ok(data) => data,
        Err(Error::StaleQuery) => {
            let hashes = discover_once(&http, &mut discovered).await?;
            let hash = hashes.search.as_deref().ok_or(Error::Unsupported)?;
            graph(
                &http,
                token,
                &client_token,
                "searchDesktop",
                hash,
                variables,
            )
            .await?
        }
        Err(error) => return Err(error),
    };
    let uri = select_track(&search, &request.track)?;
    let canvas_variables = json!({"trackUri":uri});
    let data = match graph(
        &http,
        token,
        &client_token,
        "canvas",
        CANVAS_HASH,
        canvas_variables.clone(),
    )
    .await
    {
        Ok(data) => data,
        Err(Error::StaleQuery) => {
            let hashes = discover_once(&http, &mut discovered).await?;
            let hash = hashes.canvas.as_deref().ok_or(Error::Unsupported)?;
            graph(
                &http,
                token,
                &client_token,
                "canvas",
                hash,
                canvas_variables,
            )
            .await?
        }
        Err(error) => return Err(error),
    };
    let Some(url) = canvas_url(&data)? else {
        return Ok(false);
    };
    // A separate client has no authorization, cookies or redirect forwarding.
    let response = http.get(url).send().await?;
    // Expired/blocked CDN media is not an invalid user session.
    if !response.status().is_success() {
        return Err(if response.status().as_u16() == 429 {
            Error::RateLimited
        } else {
            Error::Network
        });
    }
    let bytes = bounded(response, MEDIA_LIMIT).await?;
    if bytes.len() < 16 || &bytes[4..8] != b"ftyp" {
        return Err(Error::Invalid);
    }
    let path = request.output_directory.join("visual.mp4");
    let mut file = tokio::fs::OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(path)
        .await
        .map_err(|_| Error::Invalid)?;
    file.write_all(&bytes).await.map_err(|_| Error::Invalid)?;
    file.flush().await.map_err(|_| Error::Invalid)?;
    Ok(true)
}
#[tokio::main]
async fn main() {
    // Do not format errors: reqwest errors/requests can contain URLs or credentials.
    let mut input = Vec::new();
    if tokio::io::stdin()
        .take(32769)
        .read_to_end(&mut input)
        .await
        .is_err()
        || input.len() > 32768
    {
        return;
    }
    let Ok(request) = serde_json::from_slice::<Request>(&input) else {
        return;
    };
    let result = tokio::time::timeout(Duration::from_secs(18), resolve(&request)).await;
    let status = match result {
        Ok(Ok(true)) => "ready",
        Ok(Ok(false)) => "absent",
        Ok(Err(Error::Auth)) => "authRequired",
        Ok(Err(Error::RateLimited)) => "rateLimited",
        Ok(Err(Error::Unresolved)) => "unresolved",
        Ok(Err(Error::Unsupported | Error::StaleQuery)) => "unsupported",
        _ => "unavailable",
    };
    let reply = Reply {
        protocol_version: 1,
        request_id: request.request_id,
        status,
        file_name: (status == "ready").then_some("visual.mp4"),
    };
    if let Ok(bytes) = serde_json::to_vec(&reply) {
        let _ = tokio::io::stdout().write_all(&bytes).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn track() -> Track {
        Track {
            video_id: "yt".into(),
            title: "Song (Live)".into(),
            artist: "Artist".into(),
            album: Some("Album".into()),
            duration_seconds: Some(200),
            explicit: Some(true),
        }
    }
    #[test]
    fn protocol_request_accepts_native_paths_of_both_platforms() {
        // The host sends its own native path: POSIX on macOS, drive/UNC with escaped backslashes on Windows.
        for directory in [
            "/Users/someone/Library/Application Support/Side B/Sessions/request-uuid",
            r"C:\Users\someone\AppData\Local\Side B\Sessions\request-uuid",
            r"\\?\C:\Users\someone\Sessions\request-uuid",
        ] {
            let json = json!({"protocolVersion":1,"requestId":"r","credential":"secret",
                "outputDirectory":directory,"track":{"videoId":"yt","title":"T","artist":"A"}});
            let request: Request = serde_json::from_value(json).unwrap();
            assert_eq!(request.output_directory, PathBuf::from(directory));
            assert!(request
                .output_directory
                .join("visual.mp4")
                .ends_with("visual.mp4"));
        }
    }
    fn candidate(id: &str) -> Value {
        json!({"item":{"data":{"name":"Song (Live)","duration":{"totalMilliseconds":200000},"artists":{"items":[{"profile":{"name":"Artist"}}]},"albumOfTrack":{"name":"Album"},"contentRating":{"label":"EXPLICIT"},"uri":format!("spotify:track:{id}")}}})
    }
    fn page(items: Vec<Value>) -> Value {
        json!({"searchV2":{"tracksV2":{"items":items}}})
    }
    #[tokio::test]
    async fn oversized_chunked_body_is_rejected_without_content_length() {
        let server = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = server.local_addr().unwrap();
        let peer = tokio::spawn(async move {
            let (mut socket, _) = server.accept().await.unwrap();
            let mut request = [0; 2048];
            let _ = socket.read(&mut request).await;
            let _ = socket.write_all(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n8\r\n12345678\r\n8\r\nabcdefgh\r\n0\r\n\r\n").await;
        });
        let response = Client::new()
            .get(format!("http://{address}/fixture"))
            .send()
            .await
            .unwrap();
        assert_eq!(bounded(response, 10).await, Err(Error::Invalid));
        peer.await.unwrap();
    }

    #[test]
    fn matching_rejects_ambiguous_versions_and_unknown_duration() {
        let id = "1234567890123456789012";
        assert!(select_track(&page(vec![candidate(id)]), &track()).is_ok());
        // Duplicate catalog entries for the same recording take the top ranked search result
        assert_eq!(
            select_track(
                &page(vec![candidate(id), candidate("2234567890123456789012")]),
                &track()
            ),
            Ok("spotify:track:1234567890123456789012".into())
        );
        let mut t = track();
        t.title = "Song".into();
        assert_eq!(
            select_track(&page(vec![candidate(id)]), &t),
            Err(Error::Unresolved)
        );
        t = track();
        t.explicit = Some(false);
        assert_eq!(
            select_track(&page(vec![candidate(id)]), &t),
            Err(Error::Unresolved)
        );
        t = track();
        t.duration_seconds = None;
        assert_eq!(
            select_track(&page(vec![candidate(id)]), &t),
            Err(Error::Unresolved)
        );

        // Featured artist and album edition resilience (e.g. Instant Crush)
        let instant_crush_candidate = json!({
            "item": {
                "data": {
                    "name": "Instant Crush (feat. Julian Casablancas)",
                    "duration": { "totalMilliseconds": 337560 },
                    "artists": { "items": [{ "profile": { "name": "Daft Punk" } }, { "profile": { "name": "Julian Casablancas" } }] },
                    "albumOfTrack": { "name": "Random Access Memories (10th Anniversary Edition)" },
                    "contentRating": { "label": "NONE" },
                    "uri": "spotify:track:2cGxRwrMyEAp8dEbuZaVv6"
                }
            }
        });
        let ytm_track = Track {
            video_id: "khnokW3Mw24".into(),
            title: "Instant Crush".into(),
            artist: "Daft Punk".into(),
            album: Some("Random Access Memories".into()),
            duration_seconds: Some(338),
            explicit: None,
        };
        assert_eq!(
            select_track(&page(vec![instant_crush_candidate]), &ytm_track),
            Ok("spotify:track:2cGxRwrMyEAp8dEbuZaVv6".into())
        );
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
        assert_eq!(
            canvas_url(&json!({"trackUnion":{}})),
            Err(Error::Unsupported)
        );
        assert_eq!(canvas_url(&json!({"trackUnion":{"canvas":null}})), Ok(None));
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
        let script = r#"var a={4406:"xpui-routes-search"};var b={4406:"04981b42",4406:"a0a5ee13"};var c=new X("canvas","query","575138ab27cd5c1b3e54da54d0a7cc8d85485402de26340c2145f0f6bb5e7a9f",null);"#;
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
        assert_eq!(
            persisted_hash(script, "canvas"),
            Some("575138ab27cd5c1b3e54da54d0a7cc8d85485402de26340c2145f0f6bb5e7a9f")
        );
        let chunk = r#"new X("searchDesktop","query","eef7cc54888d91bdd6802623477873caa3948ae173a0c34fd86827b267e94c03",null);"#;
        assert_eq!(
            persisted_hash(chunk, "searchDesktop"),
            Some("eef7cc54888d91bdd6802623477873caa3948ae173a0c34fd86827b267e94c03")
        );
        assert_eq!(persisted_hash(chunk, "missing"), None);
        assert_eq!(
            persisted_hash("\"searchDesktop\",\"query\",\"abc\"", "searchDesktop"),
            None
        );
    }
    #[test]
    fn search_variables_match_current_web_player() {
        let variables = search_variables(&track());
        assert_eq!(variables["searchTerm"], "Song (Live) Artist");
        assert_eq!(variables["sectionFilters"], json!(["GENERIC"]));
        assert_eq!(variables["isPrefix"], Value::Null);
        assert!(variables.get("query").is_none());
    }
    #[tokio::test]
    #[ignore = "network: reads the public Spotify web player"]
    async fn current_web_player_hashes_are_discoverable() {
        let http = Client::builder()
            .timeout(Duration::from_secs(8))
            .build()
            .unwrap();
        let hashes = discover_hashes(&http).await.unwrap();
        assert_eq!(hashes.canvas.as_deref(), Some(CANVAS_HASH));
        assert_eq!(hashes.search.as_deref(), Some(SEARCH_HASH));
    }
    #[test]
    fn media_hosts_and_bearer_are_strict() {
        for u in [
            "http://canvaz.scdn.co/v.mp4",
            "https://canvaz.scdn.co.evil.test/v.mp4",
            "https://user@canvaz.scdn.co/v.mp4",
            "file:///tmp/v.mp4",
        ] {
            assert!(media_url(u).is_err());
        }
        assert!(media_url("https://canvaz.scdn.co/v.mp4").is_ok());
        assert_eq!(bearer("Bearer abc"), Ok("abc"));
        assert!(bearer("abc\r\nsecret").is_err());
        assert!(bearer("😀😀😀").is_err());
    }
}
