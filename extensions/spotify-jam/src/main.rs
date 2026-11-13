//! Side B ⇄ Spotify Jam, guest side. Long-lived process: JSON lines in on stdin, JSON lines out on
//! stdout (session protocol v2). It never plays audio and knows nothing about YouTube Music: it
//! joins a Jam with the user's Web Player session, mirrors the shared player state and queue, and
//! relays playback commands. Interfaces are unofficial (see extensions/README.md).
//!
//! stdin:  {"type":"join","credential":"<bearer>","link":"<url|token>"}
//!         {"type":"credential","credential":"<bearer>"}            (renewed token)
//!         {"type":"command","action":"pause|resume|next|previous|seek|add","positionMs":0,"uri":"","requestId":""}
//!         {"type":"command","action":"move|insert|remove","revision":"…", …}   (queue editing, see README)
//!         {"type":"resolve","requestId":"…","title":"…","artist":"…","album":null,"durationMs":197000}
//!         {"type":"leave"}                                           (stdin EOF also leaves)
//! stdout: joined · state · members · session · notice · commandResult · resolved · ended · error
//!
//! Never format reqwest/tungstenite errors into output: they can contain the bearer.

mod invites;
mod search;

use base64::Engine;
use futures_util::{SinkExt, StreamExt};
use rand::RngCore;
use reqwest::Client;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::io::Read;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio_tungstenite::tungstenite::Message;

pub(crate) const SP: &str = "https://spclient.wg.spotify.com";
pub(crate) const UA: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
const QUEUE_LIMIT: usize = 200;
/// More uncached tracks than this: emit the state with what is cached first, then again.
const META_EAGER_LIMIT: usize = 60;
const META_PARALLEL: usize = 6;

pub(crate) fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}
pub(crate) fn emit(value: Value) {
    println!("{value}");
}
pub(crate) fn fail(code: &str, retryable: bool) {
    emit(json!({"type":"error","code":code,"retryable":retryable}));
}
fn random_hex(bytes: usize) -> String {
    let mut raw = vec![0u8; bytes];
    rand::thread_rng().fill_bytes(&mut raw);
    raw.iter().map(|b| format!("{b:02x}")).collect()
}
/// Numbers arrive both as JSON numbers and as decimal strings.
fn num(value: Option<&Value>) -> Option<i64> {
    match value? {
        Value::Number(n) => n.as_i64().or_else(|| n.as_f64().map(|f| f as i64)),
        Value::String(s) => s
            .parse::<i64>()
            .ok()
            .or_else(|| s.parse::<f64>().ok().map(|f| f as i64)),
        _ => None,
    }
}
pub(crate) fn clean_bearer(raw: &str) -> Option<String> {
    let token = raw.trim();
    let token = token
        .strip_prefix("Bearer ")
        .or_else(|| token.strip_prefix("bearer "))
        .unwrap_or(token)
        .trim();
    (token.len() > 20 && token.len() < 4096 && token.chars().all(|c| c.is_ascii_graphic()))
        .then(|| token.to_string())
}
/// Accepts a bare join token or an `open.spotify.com/socialsession/<token>` link.
pub(crate) fn jam_token(link: &str) -> Option<String> {
    let link = link.trim();
    let candidate = match link.find("socialsession") {
        Some(at) => link[at + "socialsession".len()..].trim_start_matches(['/', ':']),
        None => link,
    };
    let token: String = candidate
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric())
        .collect();
    ((16..=40).contains(&token.len())
        && (token.len() == candidate.len() || link.contains("socialsession")))
    .then_some(token)
}
/// `spotify:track:<base62>` → 32-hex gid used by the metadata service.
fn track_gid(uri: &str) -> Option<String> {
    let id = uri.strip_prefix("spotify:track:")?;
    if id.len() != 22 {
        return None;
    }
    let mut n: u128 = 0;
    for c in id.bytes() {
        let digit = match c {
            b'0'..=b'9' => c - b'0',
            b'a'..=b'z' => c - b'a' + 10,
            b'A'..=b'Z' => c - b'A' + 36,
            _ => return None,
        } as u128;
        n = n.checked_mul(62)?.checked_add(digit)?;
    }
    Some(format!("{n:032x}"))
}
fn track_json(uri: &str, provider: Option<&str>, meta: Option<&Value>) -> Value {
    let artists: Vec<&str> = meta
        .and_then(|m| m.get("artist"))
        .and_then(Value::as_array)
        .map(|a| {
            a.iter()
                .filter_map(|x| x.get("name").and_then(Value::as_str))
                .collect()
        })
        .unwrap_or_default();
    let isrc = meta
        .and_then(|m| m.get("external_id"))
        .and_then(Value::as_array)
        .and_then(|ids| {
            ids.iter()
                .find(|x| x.get("type").and_then(Value::as_str) == Some("isrc"))
        })
        .and_then(|x| x.get("id").and_then(Value::as_str));
    json!({
        "uri": uri,
        "title": meta.and_then(|m| m.get("name")),
        "artists": artists,
        "album": meta.and_then(|m| m.pointer("/album/name")),
        "durationMs": meta.and_then(|m| num(m.get("duration"))),
        "isrc": isrc,
        "provider": provider,
    })
}
fn members_json(session: &Value) -> Value {
    let owner = session
        .get("session_owner_id")
        .and_then(Value::as_str)
        .unwrap_or("");
    let members: Vec<Value> =
        session
            .get("session_members")
            .and_then(Value::as_array)
            .map(|list| {
                list.iter().map(|m| json!({
            "name": m.get("display_name").or_else(|| m.get("username")),
            "imageUrl": m.get("image_url"),
            "isHost": m.get("id").and_then(Value::as_str) == Some(owner),
            "isMe": m.get("is_current_user").and_then(Value::as_bool).unwrap_or(false),
        })).collect()
            })
            .unwrap_or_default();
    Value::Array(members)
}
fn session_over(reason: &str) -> bool {
    ["YOU_LEFT", "DELETED", "ENDED", "KICKED", "REMOVED_YOU"]
        .iter()
        .any(|k| reason.contains(k))
}
/// Dealer payloads are JSON objects, or base64 (optionally gzip) strings of one.
fn decode_payload(payload: &Value) -> Option<Value> {
    match payload {
        Value::Object(_) => Some(payload.clone()),
        Value::String(text) => {
            let raw = base64::engine::general_purpose::STANDARD
                .decode(text)
                .ok()?;
            let bytes = if raw.starts_with(&[0x1f, 0x8b]) {
                let mut out = Vec::new();
                flate2::read::GzDecoder::new(&raw[..])
                    .take(8 * 1024 * 1024)
                    .read_to_end(&mut out)
                    .ok()?;
                out
            } else {
                raw
            };
            serde_json::from_slice(&bytes).ok()
        }
        _ => None,
    }
}

fn playable_uri(uri: &str) -> bool {
    uri.starts_with("spotify:track:") || uri.starts_with("spotify:episode:")
}
/// Raw `next_tracks` indices of the entries that are emitted (playable, first QUEUE_LIMIT).
/// Position `n` in the result is emitted queue index `n`.
fn emitted_indices(raw: &[Value]) -> Vec<usize> {
    raw.iter()
        .enumerate()
        .filter(|(_, t)| {
            t.get("uri")
                .and_then(Value::as_str)
                .is_some_and(playable_uri)
        })
        .map(|(i, _)| i)
        .take(QUEUE_LIMIT)
        .collect()
}
/// `cluster.queue_revision` arrives as a string (or, defensively, a number).
fn revision_of(player: &Value) -> Option<String> {
    match player.get("queue_revision")? {
        Value::String(s) if !s.is_empty() => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

#[derive(Debug, PartialEq)]
enum QueueEdit {
    Move { from: usize, to: usize },
    Insert { uri: String, index: usize },
    Remove { index: usize },
}
/// Marks a ContextTrack as user-queued, the way the official clients do.
fn mark_queued(track: &mut Value) {
    let Some(object) = track.as_object_mut() else {
        return;
    };
    object.insert("provider".into(), json!("queue"));
    let metadata = object.entry("metadata").or_insert_with(|| json!({}));
    if !metadata.is_object() {
        *metadata = json!({});
    }
    metadata["is_queued"] = json!("true");
}
/// Where in the raw list an item must be inserted so that exactly `emitted_index` emitted items
/// precede it. Non-emitted entries keep their place relative to their neighbours: the item goes
/// right before the emitted item currently at that index, or right after the last emitted item
/// when appending (so it stays ahead of trailing delimiters).
fn raw_insert_position(raw: &[Value], emitted_index: usize) -> usize {
    let map = emitted_indices(raw);
    match map.get(emitted_index) {
        Some(&at) => at,
        None => map.last().map_or(0, |&last| last + 1),
    }
}
/// Pure queue transformation. Indices refer to the emitted queue; `None` means out of range.
fn edit_queue(raw: &[Value], edit: &QueueEdit) -> Option<Vec<Value>> {
    let map = emitted_indices(raw);
    let mut next = raw.to_vec();
    match edit {
        QueueEdit::Move { from, to } => {
            if *from >= map.len() || *to >= map.len() {
                return None;
            }
            let mut track = next.remove(map[*from]);
            mark_queued(&mut track);
            let at = raw_insert_position(&next, *to);
            next.insert(at, track);
        }
        QueueEdit::Insert { uri, index } => {
            if *index > map.len() || track_gid(uri).is_none() {
                return None;
            }
            let mut track = json!({"uri": uri});
            mark_queued(&mut track);
            next.insert(raw_insert_position(raw, *index), track);
        }
        QueueEdit::Remove { index } => {
            if *index >= map.len() {
                return None;
            }
            next.remove(map[*index]);
        }
    }
    Some(next)
}
fn set_queue_command(next: Vec<Value>, prev: &[Value], revision: &str) -> Value {
    json!({"endpoint":"set_queue","next_tracks":next,"prev_tracks":prev,"queue_revision":revision})
}
fn index_of(message: &Value, key: &str) -> Option<usize> {
    num(message.get(key)).and_then(|n| usize::try_from(n).ok())
}
fn parse_edit(action: &str, message: &Value) -> Option<QueueEdit> {
    match action {
        "move" => Some(QueueEdit::Move {
            from: index_of(message, "from")?,
            to: index_of(message, "to")?,
        }),
        "insert" => Some(QueueEdit::Insert {
            uri: message.get("uri").and_then(Value::as_str)?.to_string(),
            index: index_of(message, "index")?,
        }),
        "remove" => Some(QueueEdit::Remove {
            index: index_of(message, "index")?,
        }),
        _ => None,
    }
}
fn command_result(action: &str, ok: bool, detail: Value, message: &Value) -> Value {
    let mut result = json!({"type":"commandResult","action":action,"ok":ok,"detail":detail});
    if let Some(id) = message.get("requestId").and_then(Value::as_str) {
        result["requestId"] = json!(id);
    }
    result
}
fn resolved_json(request_id: &str, outcome: Result<&search::Match, ()>) -> Value {
    match outcome {
        Ok(found) => {
            json!({"type":"resolved","requestId":request_id,"uri":found.uri,"title":found.title,"artists":found.artists,"durationMs":found.duration_ms})
        }
        Err(()) => {
            json!({"type":"resolved","requestId":request_id,"uri":null,"title":null,"artists":[],"durationMs":null})
        }
    }
}

struct Jam {
    http: Client,
    bearer: String,
    client_token: String,
    device: String,
    session_id: String,
    /// Largest observed (server clock − local clock); the least-delayed sample is the best estimate.
    clock_offset_ms: Option<i64>,
    meta: HashMap<String, Value>,
    last_state: String,
    /// Raw `next_tracks` / `prev_tracks` / `queue_revision` of the last published Jam state.
    raw_next: Vec<Value>,
    raw_prev: Vec<Value>,
    revision: Option<String>,
    searcher: Option<Arc<search::Searcher>>,
}

impl Jam {
    fn request(&self, method: reqwest::Method, url: &str) -> reqwest::RequestBuilder {
        self.http
            .request(method, url)
            .bearer_auth(&self.bearer)
            .header("client-token", &self.client_token)
            .header("accept", "application/json")
            .header("app-platform", "WebPlayer")
            .header("origin", "https://open.spotify.com")
    }
    async fn load_metadata(&mut self, uris: &[String]) {
        let missing: Vec<(String, String)> = uris
            .iter()
            .filter(|u| !self.meta.contains_key(*u))
            .filter_map(|u| track_gid(u).map(|gid| (u.clone(), gid)))
            .collect();
        for chunk in missing.chunks(META_PARALLEL) {
            let calls = chunk.iter().map(|(uri, gid)| {
                let call = self
                    .request(
                        reqwest::Method::GET,
                        &format!("{SP}/metadata/4/track/{gid}?market=from_token"),
                    )
                    .send();
                async move {
                    let response = call.await.ok()?;
                    if !response.status().is_success() {
                        return None;
                    }
                    Some((uri.clone(), response.json::<Value>().await.ok()?))
                }
            });
            for (uri, meta) in futures_util::future::join_all(calls)
                .await
                .into_iter()
                .flatten()
            {
                self.meta.insert(uri, meta);
            }
        }
    }
    /// Emits the shared player state. Only the Jam's virtual device counts: anything else in the
    /// cluster is the user's own Spotify playback.
    async fn publish(&mut self, cluster: &Value, received_ms: i64) {
        if let Some(server) = num(cluster.get("server_timestamp_ms")) {
            let sample = server - received_ms;
            self.clock_offset_ms =
                Some(self.clock_offset_ms.map_or(sample, |best| best.max(sample)));
        }
        let active = cluster
            .get("active_device_id")
            .and_then(Value::as_str)
            .unwrap_or("");
        if !active.starts_with("social-connect-") {
            return;
        }
        let Some(player) = cluster.get("player_state") else {
            return;
        };
        let current = player
            .pointer("/track/uri")
            .and_then(Value::as_str)
            .map(String::from);
        let raw_next = player
            .get("next_tracks")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let entries: Vec<(String, Option<String>)> = emitted_indices(&raw_next)
            .into_iter()
            .filter_map(|i| {
                let t = &raw_next[i];
                Some((
                    t.get("uri")?.as_str()?.to_string(),
                    t.get("provider").and_then(Value::as_str).map(String::from),
                ))
            })
            .collect();
        self.raw_prev = player
            .get("prev_tracks")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        self.raw_next = raw_next;
        self.revision = revision_of(player);

        let mut wanted: Vec<String> = current.iter().cloned().collect();
        wanted.extend(entries.iter().map(|(uri, _)| uri.clone()));
        let uncached = wanted
            .iter()
            .filter(|u| !self.meta.contains_key(*u) && track_gid(u).is_some())
            .count();
        if uncached > META_EAGER_LIMIT {
            // Show the queue right away with what is cached; the rest follows.
            self.emit_state(player, current.as_deref(), &entries, received_ms);
        }
        self.load_metadata(&wanted).await;
        self.emit_state(player, current.as_deref(), &entries, received_ms);
    }
    fn emit_state(
        &mut self,
        player: &Value,
        current: Option<&str>,
        entries: &[(String, Option<String>)],
        received_ms: i64,
    ) {
        let paused = player
            .get("is_paused")
            .and_then(Value::as_bool)
            .unwrap_or(false)
            || !player
                .get("is_playing")
                .and_then(Value::as_bool)
                .unwrap_or(false);
        let position = num(player.get("position_as_of_timestamp")).unwrap_or(0);
        let offset = self.clock_offset_ms.unwrap_or(0);
        let at_local = num(player.get("timestamp"))
            .map(|t| t - offset)
            .unwrap_or(received_ms);
        let state = json!({
            "type": "state",
            "track": current.map(|uri| track_json(uri, None, self.meta.get(uri))),
            "positionMs": position,
            // Local-clock instant at which `positionMs` was true. Live = positionMs + (now − atLocalMs) while playing.
            "atLocalMs": at_local,
            "paused": paused,
            "durationMs": num(player.get("duration")),
            "queue": entries.iter().map(|(uri, provider)| track_json(uri, provider.as_deref(), self.meta.get(uri))).collect::<Vec<_>>(),
            "queueRevision": self.revision,
            "previousCount": player.get("prev_tracks").and_then(Value::as_array).map_or(0, Vec::len),
            "shuffle": player.pointer("/options/shuffling_context"),
            "clockOffsetMs": offset,
        });
        let text = state.to_string();
        if text != self.last_state {
            self.last_state = text;
            emit(state);
        }
    }
    /// Runs one command and returns the `commandResult` to emit.
    async fn command(&self, action: &str, message: &Value) -> Value {
        let reply = |ok: bool, detail: &str| command_result(action, ok, json!(detail), message);
        let command = match action {
            "pause" => json!({"endpoint":"pause"}),
            "resume" => json!({"endpoint":"resume"}),
            "next" => json!({"endpoint":"skip_next"}),
            "previous" => json!({"endpoint":"skip_prev"}),
            "seek" => match num(message.get("positionMs")) {
                Some(ms) if ms >= 0 => json!({"endpoint":"seek_to","value":ms}),
                _ => return reply(false, "invalid"),
            },
            "add" => match message
                .get("uri")
                .and_then(Value::as_str)
                .filter(|u| track_gid(u).is_some())
            {
                Some(uri) => json!({"endpoint":"add_to_queue","track":{"uri":uri}}),
                None => return reply(false, "invalid"),
            },
            "move" | "insert" | "remove" => {
                let Some(edit) = parse_edit(action, message) else {
                    return reply(false, "invalid");
                };
                let sent = message.get("revision").and_then(Value::as_str);
                let Some(revision) = self
                    .revision
                    .as_deref()
                    .filter(|current| Some(*current) == sent)
                else {
                    return reply(false, "stale");
                };
                let Some(next) = edit_queue(&self.raw_next, &edit) else {
                    return reply(false, "invalid");
                };
                set_queue_command(next, &self.raw_prev, revision)
            }
            _ => return reply(false, "unknown"),
        };
        let url = format!(
            "{SP}/social-connect/v2/sessions/{}/commands/from/hobs_{}",
            self.session_id, self.device
        );
        let body = json!({"command":command,"connection_type":"wlan","intent_id":random_hex(16)});
        let (ok, detail) = match self
            .request(reqwest::Method::POST, &url)
            .json(&body)
            .send()
            .await
        {
            Ok(response) => {
                let ok = response.status().is_success();
                let reply: Value = response.json().await.unwrap_or(Value::Null);
                (
                    ok,
                    reply
                        .get("status")
                        .or_else(|| reply.get("error_type"))
                        .cloned()
                        .unwrap_or(Value::Null),
                )
            }
            Err(_) => (false, json!("network")),
        };
        // HTTP 200 does not mean applied: the service accepts commands it cannot apply. The real
        // outcome arrives as a `notice` (e.g. NO_HOST_ACTIVE_DEVICE) or as a new `state`.
        command_result(action, ok, detail, message)
    }
    /// Handles a `resolve` request without blocking the loop: the lookup runs in its own task and
    /// prints its `resolved` reply when done.
    fn spawn_resolve(&self, message: &Value) {
        let Some(request_id) = message
            .get("requestId")
            .and_then(Value::as_str)
            .filter(|id| id.len() <= 128)
            .map(String::from)
        else {
            return;
        };
        let title = message
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim()
            .to_string();
        let artist = message
            .get("artist")
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim()
            .to_string();
        let Some(searcher) = self
            .searcher
            .clone()
            .filter(|_| !title.is_empty() && title.len() <= 1000 && artist.len() <= 1000)
        else {
            return emit(resolved_json(&request_id, Err(())));
        };
        let query = search::Query {
            title,
            artist,
            album: message
                .get("album")
                .and_then(Value::as_str)
                .map(String::from),
            duration_ms: num(message.get("durationMs"))
                .and_then(|n| u64::try_from(n).ok())
                .filter(|ms| *ms > 0),
        };
        let (bearer, client_token) = (self.bearer.clone(), self.client_token.clone());
        tokio::spawn(async move {
            let outcome = tokio::time::timeout(
                Duration::from_secs(18),
                searcher.resolve(&bearer, &client_token, &query),
            )
            .await;
            match outcome {
                Ok(Ok(found)) => emit(resolved_json(&request_id, Ok(&found))),
                _ => emit(resolved_json(&request_id, Err(()))),
            }
        });
    }
    async fn leave(&self) {
        let url = format!("{SP}/social-connect/v2/sessions/{}/leave", self.session_id);
        let _ = tokio::time::timeout(
            Duration::from_secs(6),
            self.request(reqwest::Method::POST, &url)
                .body("{}")
                .header("content-type", "application/json")
                .send(),
        )
        .await;
    }
}

pub(crate) async fn client_token(http: &Client) -> Option<String> {
    let body = json!({"client_data":{
        "client_version":"1.2.42.432.g3121", "client_id":"d8a5ed958d274c2e8ee717e6a4b0971d",
        "js_sdk_data":{"device_brand":"Apple","device_model":"MacBookPro","os":"Mac OS","os_version":"10.15.7","device_id":random_hex(16),"device_type":"computer"}
    }});
    let response = http
        .post("https://clienttoken.spotify.com/v1/clienttoken")
        .header("accept", "application/json")
        .json(&body)
        .send()
        .await
        .ok()?;
    let data: Value = response.json().await.ok()?;
    data.pointer("/granted_token/token")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .map(String::from)
}

enum Outcome {
    Left,
    Ended,
    Dropped,
    AuthExpired,
}

pub(crate) type Lines = tokio::io::Lines<BufReader<tokio::io::Stdin>>;

/// One dealer connection: subscribe, mirror state, relay commands, until something ends it.
async fn run_connection(jam: &mut Jam, lines: &mut Lines) -> Outcome {
    let url = format!("wss://dealer.spotify.com/?access_token={}", jam.bearer);
    let Ok(Ok((mut socket, _))) = tokio::time::timeout(
        Duration::from_secs(12),
        tokio_tungstenite::connect_async(url),
    )
    .await
    else {
        return Outcome::Dropped;
    };
    let mut ping = tokio::time::interval(Duration::from_secs(25));
    let mut registered = false;
    loop {
        tokio::select! {
            line = lines.next_line() => {
                let Ok(Some(line)) = line else { return Outcome::Left };
                let Ok(message) = serde_json::from_str::<Value>(&line) else { continue };
                match message.get("type").and_then(Value::as_str) {
                    Some("leave") => return Outcome::Left,
                    Some("command") => {
                        let result = jam.command(message.get("action").and_then(Value::as_str).unwrap_or(""), &message).await;
                        emit(result);
                    }
                    Some("resolve") => jam.spawn_resolve(&message),
                    Some("credential") => {
                        if let Some(token) = message.get("credential").and_then(Value::as_str).and_then(clean_bearer) {
                            jam.bearer = token;
                        }
                    }
                    _ => {}
                }
            }
            _ = ping.tick() => {
                if socket.send(Message::Text(r#"{"type":"ping"}"#.into())).await.is_err() {
                    return Outcome::Dropped;
                }
            }
            frame = socket.next() => {
                let received = now_ms();
                let text = match frame {
                    Some(Ok(Message::Text(text))) => text,
                    Some(Ok(Message::Close(_))) | Some(Err(_)) | None => return Outcome::Dropped,
                    Some(Ok(_)) => continue,
                };
                let Ok(message) = serde_json::from_str::<Value>(&text) else { continue };
                if !registered {
                    let Some(connection) = message.pointer("/headers/Spotify-Connection-Id").and_then(Value::as_str) else { continue };
                    let url = format!("{SP}/connect-state/v1/devices/hobs_{}", jam.device);
                    let body = json!({"member_type":"CONNECT_STATE","device":{"device_info":{"capabilities":{"can_be_player":false,"hidden":true,"needs_full_player_state":true}}}});
                    let Ok(response) = jam.request(reqwest::Method::PUT, &url).header("x-spotify-connection-id", connection).json(&body).send().await else { return Outcome::Dropped };
                    match response.status().as_u16() {
                        200..=299 => {}
                        401 | 403 => return Outcome::AuthExpired,
                        _ => return Outcome::Dropped,
                    }
                    registered = true;
                    if let Ok(cluster) = response.json::<Value>().await {
                        jam.publish(&cluster, now_ms()).await;
                    }
                    continue;
                }
                let uri = message.get("uri").and_then(Value::as_str).unwrap_or("");
                let Some(payload) = message.get("payloads").and_then(Value::as_array).and_then(|p| p.first()).and_then(decode_payload) else { continue };
                if uri.contains("connect-state/v1/cluster") {
                    if let Some(cluster) = payload.get("cluster") {
                        jam.publish(cluster, received).await;
                    }
                } else if uri.contains("social-connect") {
                    if let Some(code) = payload.get("userMessage").and_then(Value::as_str) {
                        emit(json!({"type":"notice","code":code}));
                    }
                    if let Some(session) = payload.get("session") {
                        emit(json!({"type":"members","members":members_json(session)}));
                    }
                    if let Some(reason) = payload.get("reason").and_then(Value::as_str) {
                        emit(json!({"type":"session","reason":reason}));
                        if session_over(reason) {
                            emit(json!({"type":"ended","reason":reason}));
                            return Outcome::Ended;
                        }
                    }
                }
            }
        }
    }
}

/// Waits between reconnection attempts without ignoring the host: a renewed credential ends the
/// wait early, and a leave request (or the host going away) is honoured. Returns true to leave.
async fn idle(jam: &mut Jam, lines: &mut Lines, wait: Duration) -> bool {
    let sleep = tokio::time::sleep(wait);
    tokio::pin!(sleep);
    loop {
        tokio::select! {
            _ = &mut sleep => return false,
            line = lines.next_line() => {
                let Ok(Some(line)) = line else { return true };
                let Ok(message) = serde_json::from_str::<Value>(&line) else { continue };
                match message.get("type").and_then(Value::as_str) {
                    Some("leave") => return true,
                    Some("resolve") => jam.spawn_resolve(&message),
                    Some("credential") => {
                        if let Some(token) = message.get("credential").and_then(Value::as_str).and_then(clean_bearer) {
                            jam.bearer = token;
                            return false;
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}

enum StartMode {
    Join { bearer: String, token: String },
    WatchInvites { bearer: String },
}

#[tokio::main]
async fn main() {
    let _ = rustls::crypto::ring::default_provider().install_default();
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    let mode = loop {
        let Ok(Some(line)) = lines.next_line().await else {
            return;
        };
        let Ok(message) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        match message.get("type").and_then(Value::as_str) {
            Some("join") => {
                let bearer = message
                    .get("credential")
                    .and_then(Value::as_str)
                    .and_then(clean_bearer);
                let token = message
                    .get("link")
                    .and_then(Value::as_str)
                    .and_then(jam_token);
                match (bearer, token) {
                    (Some(bearer), Some(token)) => break StartMode::Join { bearer, token },
                    (None, _) => fail("authRequired", false),
                    (_, None) => fail("invalidLink", false),
                }
            }
            Some("watchInvites") => {
                let Some(bearer) = message
                    .get("credential")
                    .and_then(Value::as_str)
                    .and_then(clean_bearer)
                else {
                    return fail("authRequired", false);
                };
                break StartMode::WatchInvites { bearer };
            }
            Some("leave") | Some("stop") => return,
            _ => continue,
        }
    };
    let Ok(http) = Client::builder()
        .user_agent(UA)
        .timeout(Duration::from_secs(15))
        .build()
    else {
        return fail("unavailable", false);
    };
    let Some(client_token) = client_token(&http).await else {
        return fail("network", true);
    };
    let (bearer, token) = match mode {
        StartMode::Join { bearer, token } => (bearer, token),
        StartMode::WatchInvites { bearer } => {
            invites::run(http, bearer, client_token, &mut lines).await;
            return;
        }
    };
    let mut jam = Jam {
        http,
        bearer,
        client_token,
        device: random_hex(20),
        session_id: String::new(),
        clock_offset_ms: None,
        meta: HashMap::new(),
        last_state: String::new(),
        raw_next: Vec::new(),
        raw_prev: Vec::new(),
        revision: None,
        searcher: search::Searcher::new().map(Arc::new),
    };

    let joined = jam
        .request(
            reqwest::Method::POST,
            &format!("{SP}/social-connect/v2/sessions/join/{token}"),
        )
        .header("content-type", "application/json")
        .body("{}")
        .send()
        .await;
    let session: Value = match joined {
        Ok(response) => match response.status().as_u16() {
            200..=299 => response.json().await.unwrap_or(Value::Null),
            401 => return fail("authRequired", false),
            403 => return fail("notAllowed", false),
            404 => return fail("jamNotFound", false),
            429 => return fail("rateLimited", true),
            _ => return fail("rejected", false),
        },
        Err(_) => return fail("network", true),
    };
    let Some(session_id) = session
        .get("session_id")
        .and_then(Value::as_str)
        .filter(|id| id.chars().all(|c| c.is_ascii_alphanumeric()))
    else {
        return fail("unsupported", false);
    };
    jam.session_id = session_id.to_string();
    emit(json!({
        "type": "joined",
        "protocolVersion": 2,
        "members": members_json(&session),
        "canControl": session.get("is_controlling"),
        "queueOnly": session.get("queue_only_mode"),
        "hostDevice": session.pointer("/host_device_info/device_type"),
        "hostActive": session.get("hostActiveDeviceId").and_then(Value::as_str).is_some_and(|d| !d.is_empty()),
    }));

    let mut failures = 0u32;
    loop {
        let started = now_ms();
        match run_connection(&mut jam, &mut lines).await {
            Outcome::Left => {
                jam.leave().await;
                emit(json!({"type":"ended","reason":"LEFT"}));
                return;
            }
            Outcome::Ended => return,
            Outcome::AuthExpired => {
                // Stay in the Jam; the host is expected to send a renewed credential.
                fail("authRequired", true);
            }
            Outcome::Dropped => fail("network", true),
        }
        failures = if now_ms() - started > 60_000 {
            1
        } else {
            failures + 1
        };
        if failures > 6 {
            jam.leave().await;
            emit(json!({"type":"ended","reason":"CONNECTION_LOST"}));
            return;
        }
        if idle(
            &mut jam,
            &mut lines,
            Duration::from_secs(2u64.pow(failures.min(4))),
        )
        .await
        {
            jam.leave().await;
            emit(json!({"type":"ended","reason":"LEFT"}));
            return;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_join_links_and_bare_tokens() {
        let token = "5QaRAjTyChieQ3Z8fdSlqu";
        assert_eq!(
            jam_token(&format!(
                "https://open.spotify.com/socialsession/{token}?si=abc&utm_source=copy-link"
            ))
            .as_deref(),
            Some(token)
        );
        assert_eq!(
            jam_token(&format!("spotify:socialsession:{token}")).as_deref(),
            Some(token)
        );
        assert_eq!(jam_token(token).as_deref(), Some(token));
        assert_eq!(
            jam_token("https://open.spotify.com/track/5QaRAjTyChieQ3Z8fdSlqu"),
            None
        );
        assert_eq!(jam_token("https://spotify.link/abc"), None);
    }

    #[test]
    fn converts_track_ids_to_gids() {
        assert_eq!(
            track_gid("spotify:track:0000000000000000000000").as_deref(),
            Some("00000000000000000000000000000000")
        );
        assert_eq!(
            track_gid("spotify:track:000000000000000000000Z").as_deref(),
            Some("0000000000000000000000000000003d")
        );
        assert_eq!(track_gid("spotify:episode:000000000000000000000Z"), None);
        assert_eq!(track_gid("spotify:track:short"), None);
    }

    #[test]
    fn accepts_numbers_as_strings() {
        assert_eq!(num(Some(&json!("97173"))), Some(97173));
        assert_eq!(num(Some(&json!(1794545200726i64))), Some(1794545200726));
        assert_eq!(num(Some(&json!(null))), None);
    }

    #[test]
    fn rejects_malformed_credentials() {
        assert!(clean_bearer("Bearer BQabcdefghijklmnopqrstuvwxyz").is_some());
        assert!(clean_bearer("short").is_none());
        assert!(clean_bearer("BQabcdefghijklmnop qrstuvwxyz123").is_none());
    }

    #[test]
    fn maps_metadata_and_membership() {
        let meta = json!({"name":"Song","artist":[{"name":"A"},{"name":"B"}],"album":{"name":"LP"},"duration":197266,"external_id":[{"type":"isrc","id":"USX"}]});
        let track = track_json("spotify:track:x", Some("queue"), Some(&meta));
        assert_eq!(track["title"], "Song");
        assert_eq!(track["artists"], json!(["A", "B"]));
        assert_eq!(track["isrc"], "USX");
        assert_eq!(track["durationMs"], 197266);
        let session = json!({"session_owner_id":"h","session_members":[{"id":"h","display_name":"Host"},{"id":"g","display_name":"Me","is_current_user":true}]});
        let members = members_json(&session);
        assert_eq!(members[0]["isHost"], true);
        assert_eq!(members[1]["isMe"], true);
    }

    #[test]
    fn recognises_session_end_reasons_and_payload_encodings() {
        assert!(session_over("YOU_LEFT"));
        assert!(session_over("SESSION_DELETED"));
        assert!(!session_over("SESSION_MEMBER_PAUSE_CHANGED"));
        let encoded = base64::engine::general_purpose::STANDARD.encode(br#"{"reason":"x"}"#);
        assert_eq!(decode_payload(&json!(encoded)).unwrap()["reason"], "x");
        assert_eq!(
            decode_payload(&json!({"reason":"y"})).unwrap()["reason"],
            "y"
        );
    }

    const A: &str = "spotify:track:aaaaaaaaaaaaaaaaaaaaaa";
    const B: &str = "spotify:track:bbbbbbbbbbbbbbbbbbbbbb";
    const C: &str = "spotify:track:cccccccccccccccccccccc";
    const N: &str = "spotify:track:1111111111111111111111";
    fn raw(uris: &[&str]) -> Vec<Value> {
        uris.iter().map(|u| json!({"uri":u,"uid":format!("uid-{u}"),"metadata":{"x":"1"},"provider":"context"})).collect()
    }
    fn uris(list: &[Value]) -> Vec<&str> {
        list.iter().map(|t| t["uri"].as_str().unwrap()).collect()
    }

    #[test]
    fn emitted_indices_skip_delimiters_and_cap() {
        let list = raw(&["spotify:delimiter", A, "spotify:meta:x", B]);
        assert_eq!(emitted_indices(&list), vec![1, 3]);
        let many: Vec<Value> = (0..300).map(|_| json!({"uri":A})).collect();
        assert_eq!(emitted_indices(&many).len(), QUEUE_LIMIT);
    }

    #[test]
    fn moves_forward_and_backward_keeping_the_destination_index() {
        let list = raw(&[A, B, C]);
        let forward = edit_queue(&list, &QueueEdit::Move { from: 0, to: 2 }).unwrap();
        assert_eq!(uris(&forward), vec![B, C, A]);
        let backward = edit_queue(&list, &QueueEdit::Move { from: 2, to: 0 }).unwrap();
        assert_eq!(uris(&backward), vec![C, A, B]);
        // Moved track keeps uid and metadata, gains the queue markers.
        assert_eq!(backward[0]["uid"], format!("uid-{C}"));
        assert_eq!(backward[0]["provider"], "queue");
        assert_eq!(backward[0]["metadata"]["is_queued"], "true");
        assert_eq!(backward[0]["metadata"]["x"], "1");
        // Others untouched.
        assert_eq!(backward[1]["provider"], "context");
        assert_eq!(
            edit_queue(&list, &QueueEdit::Move { from: 1, to: 1 }).map(|l| uris(&l).len()),
            Some(3)
        );
    }

    #[test]
    fn inserts_at_front_middle_and_end() {
        let list = raw(&[A, B]);
        let front = edit_queue(
            &list,
            &QueueEdit::Insert {
                uri: N.into(),
                index: 0,
            },
        )
        .unwrap();
        assert_eq!(uris(&front), vec![N, A, B]);
        assert_eq!(front[0]["provider"], "queue");
        assert_eq!(front[0]["metadata"]["is_queued"], "true");
        let middle = edit_queue(
            &list,
            &QueueEdit::Insert {
                uri: N.into(),
                index: 1,
            },
        )
        .unwrap();
        assert_eq!(uris(&middle), vec![A, N, B]);
        let end = edit_queue(
            &list,
            &QueueEdit::Insert {
                uri: N.into(),
                index: 2,
            },
        )
        .unwrap();
        assert_eq!(uris(&end), vec![A, B, N]);
        let into_empty = edit_queue(
            &[],
            &QueueEdit::Insert {
                uri: N.into(),
                index: 0,
            },
        )
        .unwrap();
        assert_eq!(uris(&into_empty), vec![N]);
    }

    #[test]
    fn removes_and_rejects_out_of_range() {
        let list = raw(&[A, B, C]);
        assert_eq!(
            uris(&edit_queue(&list, &QueueEdit::Remove { index: 1 }).unwrap()),
            vec![A, C]
        );
        assert_eq!(edit_queue(&list, &QueueEdit::Remove { index: 3 }), None);
        assert_eq!(edit_queue(&list, &QueueEdit::Move { from: 3, to: 0 }), None);
        assert_eq!(edit_queue(&list, &QueueEdit::Move { from: 0, to: 3 }), None);
        assert_eq!(
            edit_queue(
                &list,
                &QueueEdit::Insert {
                    uri: N.into(),
                    index: 4
                }
            ),
            None
        );
        assert_eq!(
            edit_queue(
                &list,
                &QueueEdit::Insert {
                    uri: "spotify:episode:x".into(),
                    index: 0
                }
            ),
            None
        );
    }

    #[test]
    fn delimiters_stay_in_place_relative_to_neighbours() {
        let list = raw(&[A, "spotify:delimiter", B, C, "spotify:delimiter"]);
        // Emitted queue is [A, B, C].
        let moved = edit_queue(&list, &QueueEdit::Move { from: 2, to: 0 }).unwrap();
        assert_eq!(
            uris(&moved),
            vec![C, A, "spotify:delimiter", B, "spotify:delimiter"]
        );
        let appended = edit_queue(&list, &QueueEdit::Move { from: 0, to: 2 }).unwrap();
        assert_eq!(
            uris(&appended),
            vec!["spotify:delimiter", B, C, A, "spotify:delimiter"]
        );
        let inserted = edit_queue(
            &list,
            &QueueEdit::Insert {
                uri: N.into(),
                index: 3,
            },
        )
        .unwrap();
        assert_eq!(
            uris(&inserted),
            vec![A, "spotify:delimiter", B, C, N, "spotify:delimiter"]
        );
        let removed = edit_queue(&list, &QueueEdit::Remove { index: 1 }).unwrap();
        assert_eq!(
            uris(&removed),
            vec![A, "spotify:delimiter", C, "spotify:delimiter"]
        );
        assert_eq!(removed[1]["provider"], "context");
    }

    #[test]
    fn builds_set_queue_and_parses_edits() {
        let prev = raw(&[A]);
        let command = set_queue_command(raw(&[B]), &prev, "123");
        assert_eq!(command["endpoint"], "set_queue");
        assert_eq!(command["queue_revision"], "123");
        assert_eq!(command["prev_tracks"], json!(prev));
        assert_eq!(command["next_tracks"][0]["uri"], B);
        assert_eq!(
            parse_edit("move", &json!({"from":2,"to":"0"})),
            Some(QueueEdit::Move { from: 2, to: 0 })
        );
        assert_eq!(
            parse_edit("insert", &json!({"uri":N,"index":1})),
            Some(QueueEdit::Insert {
                uri: N.into(),
                index: 1
            })
        );
        assert_eq!(parse_edit("remove", &json!({"index":-1})), None);
        assert_eq!(parse_edit("move", &json!({"from":1})), None);
        assert_eq!(
            revision_of(&json!({"queue_revision":"9"})).as_deref(),
            Some("9")
        );
        assert_eq!(
            revision_of(&json!({"queue_revision":9})).as_deref(),
            Some("9")
        );
        assert_eq!(revision_of(&json!({})), None);
    }

    #[test]
    fn command_results_echo_request_ids_and_resolve_replies_have_a_fixed_shape() {
        let with_id = command_result("pause", true, json!("ok"), &json!({"requestId":"r1"}));
        assert_eq!(with_id["requestId"], "r1");
        assert!(command_result("pause", true, json!("ok"), &json!({}))
            .get("requestId")
            .is_none());
        let found = search::Match {
            uri: A.into(),
            title: "T".into(),
            artists: vec!["X".into()],
            duration_ms: 1000,
        };
        let hit = resolved_json("q", Ok(&found));
        assert_eq!(hit["type"], "resolved");
        assert_eq!(hit["uri"], A);
        assert_eq!(hit["artists"], json!(["X"]));
        let miss = resolved_json("q", Err(()));
        assert_eq!(miss["uri"], Value::Null);
        assert_eq!(miss["requestId"], "q");
    }
}
