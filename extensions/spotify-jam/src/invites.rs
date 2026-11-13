//! Live incoming Spotify Jam invitation watcher.
//!
//! Connects to Spotify's dealer WebSocket (without registering a Connect device), listens for
//! `campfire/v1/hierarchy-message-changed` pushes, queries `speechless/v1/retrieve/*` protobuf
//! endpoints for recent Jam links, validates sessions via `social-connect/v2/sessions/info`, and
//! emits `inviteAvailable` / `inviteExpired` JSON lines to stdout.
//!
//! Never print bearer tokens, client tokens, chat IDs, user IDs, or formatted network errors.

use crate::{clean_bearer, emit, fail, jam_token, now_ms, Lines, SP};
use base64::Engine;
use flate2::read::GzDecoder;
use futures_util::{SinkExt, StreamExt};
use reqwest::Client;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::io::Read;
use std::time::Duration;
use tokio_tungstenite::tungstenite::{Error as WsError, Message};

const MAX_INVITE_AGE_SEC: i64 = 12 * 3600;
const PING_INTERVAL: Duration = Duration::from_secs(25);
const RECHECK_INTERVAL: Duration = Duration::from_secs(25);
const RECENT_HIERARCHY_SYNC_LIMIT: usize = 5;
const MAX_GUNZIP_BYTES: u64 = 8 * 1024 * 1024;

#[derive(Debug, Clone, Copy)]
struct AuthExpired;

#[derive(Debug, Clone, PartialEq, Eq)]
struct InviteCandidate {
    msg_id: String,
    token: String,
    link: String,
    sender_uid: String,
    sent_at_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ActiveInvite {
    id: String,
    token: String,
    link: String,
    sender_name: Option<String>,
    sender_image_url: Option<String>,
    sent_at_ms: i64,
    participant_count: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct SessionInfo {
    active: bool,
    is_owner: bool,
    owner_name: Option<String>,
    owner_image_url: Option<String>,
    participant_count: usize,
}

#[derive(Debug, Clone, Copy)]
enum FieldValue<'a> {
    Varint(u64),
    Fixed64,
    Bytes(&'a [u8]),
    Fixed32,
}

fn read_varint(data: &[u8], pos: &mut usize) -> Option<u64> {
    let mut out = 0u64;
    let mut shift = 0u32;
    for _ in 0..10 {
        let byte = *data.get(*pos)?;
        *pos += 1;
        if shift == 63 && byte > 0x01 {
            return None;
        }
        out |= u64::from(byte & 0x7f) << shift;
        if byte & 0x80 == 0 {
            return Some(out);
        }
        shift += 7;
    }
    None
}

fn parse_fields(data: &[u8]) -> Option<Vec<(u64, FieldValue<'_>)>> {
    let mut pos = 0usize;
    let mut fields = Vec::new();
    while pos < data.len() {
        let tag = read_varint(data, &mut pos)?;
        let field_num = tag >> 3;
        let wire_type = tag & 0x07;
        if field_num == 0 {
            return None;
        }
        let val = match wire_type {
            0 => FieldValue::Varint(read_varint(data, &mut pos)?),
            1 => {
                if pos.checked_add(8)? > data.len() {
                    return None;
                }
                pos += 8;
                FieldValue::Fixed64
            }
            2 => {
                let len = usize::try_from(read_varint(data, &mut pos)?).ok()?;
                let end = pos.checked_add(len)?;
                let slice = data.get(pos..end)?;
                pos = end;
                FieldValue::Bytes(slice)
            }
            5 => {
                if pos.checked_add(4)? > data.len() {
                    return None;
                }
                pos += 4;
                FieldValue::Fixed32
            }
            _ => return None,
        };
        fields.push((field_num, val));
    }
    Some(fields)
}

fn encode_varint(out: &mut Vec<u8>, mut value: u64) {
    loop {
        let byte = (value & 0x7f) as u8;
        value >>= 7;
        if value == 0 {
            out.push(byte);
            break;
        }
        out.push(byte | 0x80);
    }
}

fn encode_bytes_field(out: &mut Vec<u8>, field_num: u64, bytes: &[u8]) {
    encode_varint(out, (field_num << 3) | 2);
    encode_varint(out, bytes.len() as u64);
    out.extend_from_slice(bytes);
}

#[cfg(test)]
fn encode_varint_field(out: &mut Vec<u8>, field_num: u64, value: u64) {
    encode_varint(out, field_num << 3);
    encode_varint(out, value);
}

fn encode_hierarchy_request(bare_chat_id: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(2 + bare_chat_id.len());
    encode_bytes_field(&mut out, 1, bare_chat_id.as_bytes());
    out
}

fn first_bytes<'a>(fields: &'a [(u64, FieldValue<'a>)], num: u64) -> Option<&'a [u8]> {
    fields.iter().find_map(|(f, v)| match v {
        FieldValue::Bytes(b) if *f == num => Some(*b),
        _ => None,
    })
}

fn first_str<'a>(fields: &'a [(u64, FieldValue<'a>)], num: u64) -> Option<&'a str> {
    std::str::from_utf8(first_bytes(fields, num)?).ok()
}

fn first_varint(fields: &[(u64, FieldValue<'_>)], num: u64) -> Option<u64> {
    fields.iter().find_map(|(f, v)| match v {
        FieldValue::Varint(n) if *f == num => Some(*n),
        _ => None,
    })
}

fn extract_chat_ids_from_str(text: &str, out: &mut Vec<String>) {
    const PREFIX: &str = "spotify:chat:";
    let mut rest = text;
    while let Some(idx) = rest.find(PREFIX) {
        let after = &rest[idx + PREFIX.len()..];
        let id: String = after
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric())
            .collect();
        if id.len() == 22 && !out.contains(&id) {
            out.push(id);
        }
        rest = after;
    }
}

fn collect_chat_ids_from_json(value: &Value, out: &mut Vec<String>) {
    match value {
        Value::String(s) => extract_chat_ids_from_str(s, out),
        Value::Array(items) => {
            for item in items {
                collect_chat_ids_from_json(item, out);
            }
        }
        Value::Object(map) => {
            for v in map.values() {
                collect_chat_ids_from_json(v, out);
            }
        }
        _ => {}
    }
}

fn collect_chat_ids_from_protobuf(bytes: &[u8], out: &mut Vec<String>, depth: usize) -> bool {
    if depth > 16 {
        return false;
    }
    let Some(fields) = parse_fields(bytes) else {
        return false;
    };
    for (_, val) in fields {
        if let FieldValue::Bytes(sub) = val {
            if let Ok(text) = std::str::from_utf8(sub) {
                extract_chat_ids_from_str(text, out);
            }
            collect_chat_ids_from_protobuf(sub, out, depth + 1);
        }
    }
    true
}

fn scan_chat_ids_in_raw_bytes(bytes: &[u8], out: &mut Vec<String>) {
    const PREFIX: &[u8] = b"spotify:chat:";
    let mut pos = 0usize;
    while pos + PREFIX.len() + 22 <= bytes.len() {
        let Some(rel) = bytes[pos..].windows(PREFIX.len()).position(|w| w == PREFIX) else {
            break;
        };
        let start = pos + rel + PREFIX.len();
        if let Some(candidate) = bytes.get(start..start + 22) {
            if candidate.iter().all(|b| b.is_ascii_alphanumeric()) {
                if let Ok(id) = std::str::from_utf8(candidate) {
                    let id = id.to_string();
                    if !out.contains(&id) {
                        out.push(id);
                    }
                }
            }
        }
        pos = start;
    }
}

fn extract_chat_ids_from_payload(payload: &Value) -> Vec<String> {
    let mut out = Vec::new();
    match payload {
        Value::String(text) => {
            if let Ok(raw) = base64::engine::general_purpose::STANDARD.decode(text) {
                let bytes = if raw.starts_with(&[0x1f, 0x8b]) {
                    let mut decoded = Vec::new();
                    if GzDecoder::new(&raw[..])
                        .take(MAX_GUNZIP_BYTES)
                        .read_to_end(&mut decoded)
                        .is_ok()
                    {
                        decoded
                    } else {
                        return out;
                    }
                } else {
                    raw
                };
                if let Ok(json_val) = serde_json::from_slice::<Value>(&bytes) {
                    collect_chat_ids_from_json(&json_val, &mut out);
                } else if !collect_chat_ids_from_protobuf(&bytes, &mut out, 0) || out.is_empty() {
                    scan_chat_ids_in_raw_bytes(&bytes, &mut out);
                }
            } else {
                extract_chat_ids_from_str(text, &mut out);
            }
        }
        Value::Object(_) | Value::Array(_) => collect_chat_ids_from_json(payload, &mut out),
        _ => {}
    }
    out
}

fn extract_socialsession_link(raw: &str) -> Option<(String, String)> {
    if !raw.contains("socialsession") {
        return None;
    }
    let trimmed = raw.trim();
    if !trimmed.contains(char::is_whitespace) {
        let token = jam_token(trimmed)?;
        return Some((token, trimmed.to_string()));
    }
    for segment in trimmed.split_whitespace() {
        if !segment.contains("socialsession") {
            continue;
        }
        let clean = segment.trim_matches(|c: char| {
            matches!(
                c,
                '<' | '>' | '"' | '\'' | '(' | ')' | '[' | ']' | ',' | '.' | '!' | ';'
            )
        });
        if let Some(token) = jam_token(clean) {
            return Some((token, clean.to_string()));
        }
    }
    None
}

fn try_parse_message(fields: &[(u64, FieldValue<'_>)], now_sec: i64) -> Option<InviteCandidate> {
    let header = parse_fields(first_bytes(fields, 1)?)?;
    let msg_uri = first_str(&header, 3)?;
    let msg_id = msg_uri.strip_prefix("spotify:chat-message:")?;
    if msg_id.is_empty() {
        return None;
    }
    if let Some(meta) = first_bytes(&header, 2).and_then(parse_fields) {
        let _subtype = first_varint(&meta, 2)?;
    }

    let sender = parse_fields(first_bytes(fields, 6)?)?;
    let sender_uid = first_str(&sender, 1).unwrap_or("").to_string();
    let ts_outer = parse_fields(first_bytes(&sender, 2)?)?;
    let ts_inner = parse_fields(first_bytes(&ts_outer, 1)?)?;
    let sent_sec = i64::try_from(first_varint(&ts_inner, 1)?).ok()?;
    if sent_sec <= 0 || now_sec - sent_sec > MAX_INVITE_AGE_SEC {
        return None;
    }
    let nanos = first_varint(&ts_inner, 2).unwrap_or(0) as i64;
    let sent_at_ms = sent_sec
        .saturating_mul(1000)
        .saturating_add(nanos / 1_000_000);

    let body = parse_fields(first_bytes(fields, 8)?)?;
    let content = parse_fields(first_bytes(&body, 1)?)?;

    let (token, link) = first_bytes(&content, 2)
        .and_then(parse_fields)
        .and_then(|share| first_str(&share, 1).and_then(extract_socialsession_link))
        .or_else(|| {
            first_bytes(&content, 1)
                .and_then(parse_fields)
                .and_then(|text| first_str(&text, 1).and_then(extract_socialsession_link))
        })?;

    Some(InviteCandidate {
        msg_id: msg_id.to_string(),
        token,
        link,
        sender_uid,
        sent_at_ms,
    })
}

fn walk_messages(bytes: &[u8], now_sec: i64, out: &mut Vec<InviteCandidate>, depth: usize) {
    if depth > 16 {
        return;
    }
    let Some(fields) = parse_fields(bytes) else {
        return;
    };
    if let Some(candidate) = try_parse_message(&fields, now_sec) {
        out.push(candidate);
        return;
    }
    for (_, val) in fields {
        if let FieldValue::Bytes(sub) = val {
            walk_messages(sub, now_sec, out, depth + 1);
        }
    }
}

fn extract_invite_candidates(bytes: &[u8], now_sec: i64) -> Vec<InviteCandidate> {
    let mut out = Vec::new();
    walk_messages(bytes, now_sec, &mut out, 0);
    out
}

fn message_sent_sec(msg_bytes: &[u8]) -> Option<i64> {
    let msg = parse_fields(msg_bytes)?;
    let sender = parse_fields(first_bytes(&msg, 6)?)?;
    let ts_outer = parse_fields(first_bytes(&sender, 2)?)?;
    let ts_inner = parse_fields(first_bytes(&ts_outer, 1)?)?;
    i64::try_from(first_varint(&ts_inner, 1)?).ok()
}

fn extract_recent_chat_ids(bytes: &[u8], now_sec: i64) -> Vec<String> {
    let mut out = Vec::new();
    let Some(top) = parse_fields(bytes) else {
        return out;
    };
    for (field_num, val) in top {
        if field_num != 1 {
            continue;
        }
        let FieldValue::Bytes(wrapper_bytes) = val else {
            continue;
        };
        let Some(wrapper) = parse_fields(wrapper_bytes) else {
            continue;
        };
        let Some(chat_meta) = first_bytes(&wrapper, 1).and_then(parse_fields) else {
            continue;
        };
        let Some(chat_uri) = first_str(&chat_meta, 3) else {
            continue;
        };
        let mut chat_ids = Vec::new();
        extract_chat_ids_from_str(chat_uri, &mut chat_ids);
        let Some(chat_id) = chat_ids.into_iter().next() else {
            continue;
        };
        let is_recent = first_bytes(&wrapper, 2)
            .and_then(message_sent_sec)
            .is_some_and(|sec| sec > 0 && now_sec - sec <= MAX_INVITE_AGE_SEC);
        if is_recent && !out.contains(&chat_id) {
            out.push(chat_id);
            if out.len() >= RECENT_HIERARCHY_SYNC_LIMIT {
                break;
            }
        }
    }
    out
}

fn parse_session_info(session: &Value) -> SessionInfo {
    let active = session
        .get("active")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let is_owner = session
        .get("is_session_owner")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let owner_id = session
        .get("session_owner_id")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty());
    let members = session.get("session_members").and_then(Value::as_array);
    let participant_count = members.map_or(0, Vec::len);
    let owner_member = owner_id.and_then(|oid| {
        members.and_then(|list| {
            list.iter()
                .find(|m| m.get("id").and_then(Value::as_str) == Some(oid))
        })
    });
    let owner_name = owner_member.and_then(|m| {
        m.get("display_name")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .or_else(|| {
                m.get("username")
                    .and_then(Value::as_str)
                    .filter(|s| !s.is_empty())
            })
            .map(String::from)
    });
    let owner_image_url = owner_member.and_then(|m| {
        m.get("image_url")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .map(String::from)
    });
    SessionInfo {
        active,
        is_owner,
        owner_name,
        owner_image_url,
        participant_count,
    }
}

fn invite_available_json(invite: &ActiveInvite) -> Value {
    json!({
        "type": "inviteAvailable",
        "id": invite.id,
        "token": invite.token,
        "link": invite.link,
        "senderName": invite.sender_name,
        "senderImageUrl": invite.sender_image_url,
        "sentAtMs": invite.sent_at_ms,
        "participantCount": invite.participant_count,
    })
}

fn invite_expired_json(id: &str, token: &str) -> Value {
    json!({
        "type": "inviteExpired",
        "id": id,
        "token": token,
    })
}

fn valid_uid_segment(uid: &str) -> bool {
    !uid.is_empty()
        && uid.len() <= 128
        && uid
            .bytes()
            .all(|b| b.is_ascii_graphic() && !matches!(b, b'/' | b'?' | b'#' | b'&'))
}

struct Watcher {
    http: Client,
    bearer: String,
    client_token: String,
    profile_cache: HashMap<String, (Option<String>, Option<String>)>,
    active_invites: HashMap<String, ActiveInvite>,
    dead_tokens: HashSet<String>,
}

impl Watcher {
    fn speechless_request(&self, url: &str) -> reqwest::RequestBuilder {
        self.http
            .post(url)
            .bearer_auth(&self.bearer)
            .header("client-token", &self.client_token)
            .header("app-platform", "WebPlayer")
            .header("origin", "https://open.spotify.com")
            .header("content-type", "application/x-protobuf")
            .header("accept", "application/x-protobuf")
    }

    fn json_get(&self, url: &str) -> reqwest::RequestBuilder {
        self.http
            .get(url)
            .bearer_auth(&self.bearer)
            .header("client-token", &self.client_token)
            .header("app-platform", "WebPlayer")
            .header("origin", "https://open.spotify.com")
            .header("accept", "application/json")
    }

    async fn fetch_profile(
        &mut self,
        sender_uid: &str,
    ) -> Result<(Option<String>, Option<String>), AuthExpired> {
        if !valid_uid_segment(sender_uid) {
            return Ok((None, None));
        }
        if let Some(cached) = self.profile_cache.get(sender_uid) {
            return Ok(cached.clone());
        }
        let url = format!(
            "{SP}/user-profile-view/v3/profile/{sender_uid}?playlist_limit=0&artist_limit=0"
        );
        let Ok(response) = self.json_get(&url).send().await else {
            return Ok((None, None));
        };
        if response.status().as_u16() == 401 {
            return Err(AuthExpired);
        }
        if !response.status().is_success() {
            return Ok((None, None));
        }
        let Ok(data) = response.json::<Value>().await else {
            return Ok((None, None));
        };
        let name = data
            .get("name")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .map(String::from);
        let image_url = data
            .get("image_url")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .map(String::from);
        let pair = (name, image_url);
        self.profile_cache
            .insert(sender_uid.to_string(), pair.clone());
        Ok(pair)
    }

    async fn fetch_session_info(&self, token: &str) -> Result<Option<SessionInfo>, AuthExpired> {
        if !token.chars().all(|c| c.is_ascii_alphanumeric()) {
            return Ok(Some(SessionInfo {
                active: false,
                is_owner: false,
                owner_name: None,
                owner_image_url: None,
                participant_count: 0,
            }));
        }
        let url = format!("{SP}/social-connect/v2/sessions/info/{token}");
        let Ok(response) = self.json_get(&url).send().await else {
            return Ok(None);
        };
        match response.status().as_u16() {
            401 => Err(AuthExpired),
            403 | 404 | 410 => Ok(Some(SessionInfo {
                active: false,
                is_owner: false,
                owner_name: None,
                owner_image_url: None,
                participant_count: 0,
            })),
            200..=299 => Ok(response
                .json::<Value>()
                .await
                .ok()
                .map(|v| parse_session_info(&v))),
            _ => Ok(None),
        }
    }

    fn expire_token(&mut self, token: &str) {
        self.dead_tokens.insert(token.to_string());
        if let Some(removed) = self.active_invites.remove(token) {
            emit(invite_expired_json(&removed.id, &removed.token));
        }
    }

    async fn process_candidates(
        &mut self,
        candidates: Vec<InviteCandidate>,
    ) -> Result<(), AuthExpired> {
        for candidate in candidates {
            if self.dead_tokens.contains(&candidate.token) {
                continue;
            }
            let Some(info) = self.fetch_session_info(&candidate.token).await? else {
                continue;
            };
            if !info.active || info.is_owner {
                self.expire_token(&candidate.token);
                continue;
            }
            let mut sender_name = info.owner_name;
            let mut sender_image_url = info.owner_image_url;
            if (sender_name.is_none() || sender_image_url.is_none())
                && !candidate.sender_uid.is_empty()
            {
                let (prof_name, prof_image) = self.fetch_profile(&candidate.sender_uid).await?;
                sender_name = sender_name.or(prof_name);
                sender_image_url = sender_image_url.or(prof_image);
            }
            let existing = self.active_invites.get(&candidate.token);
            let next = ActiveInvite {
                id: existing
                    .map(|e| e.id.clone())
                    .unwrap_or_else(|| candidate.msg_id.clone()),
                token: candidate.token.clone(),
                link: existing
                    .map(|e| e.link.clone())
                    .unwrap_or_else(|| candidate.link.clone()),
                sender_name,
                sender_image_url,
                sent_at_ms: existing
                    .map(|e| e.sent_at_ms)
                    .unwrap_or(candidate.sent_at_ms),
                participant_count: info.participant_count,
            };
            if existing != Some(&next) {
                emit(invite_available_json(&next));
                self.active_invites.insert(candidate.token, next);
            }
        }
        Ok(())
    }

    async fn recheck_active_invites(&mut self) -> Result<(), AuthExpired> {
        let current: Vec<ActiveInvite> = self.active_invites.values().cloned().collect();
        for invite in current {
            let Some(info) = self.fetch_session_info(&invite.token).await? else {
                continue;
            };
            if !info.active || info.is_owner {
                self.expire_token(&invite.token);
                continue;
            }
            let updated = ActiveInvite {
                id: invite.id.clone(),
                token: invite.token.clone(),
                link: invite.link.clone(),
                sender_name: info.owner_name.or_else(|| invite.sender_name.clone()),
                sender_image_url: info
                    .owner_image_url
                    .or_else(|| invite.sender_image_url.clone()),
                sent_at_ms: invite.sent_at_ms,
                participant_count: info.participant_count,
            };
            if updated != invite {
                emit(invite_available_json(&updated));
                self.active_invites.insert(invite.token, updated);
            }
        }
        Ok(())
    }

    async fn sync_hierarchy(&mut self, bare_chat_id: &str) -> Result<(), AuthExpired> {
        let url = format!("{SP}/speechless/v1/retrieve/hierarchy");
        let body = encode_hierarchy_request(bare_chat_id);
        let Ok(response) = self.speechless_request(&url).body(body).send().await else {
            return Ok(());
        };
        match response.status().as_u16() {
            401 | 403 => return Err(AuthExpired),
            200..=299 => {}
            _ => return Ok(()),
        }
        let Ok(bytes) = response.bytes().await else {
            return Ok(());
        };
        let candidates = extract_invite_candidates(&bytes, now_ms() / 1000);
        self.process_candidates(candidates).await
    }

    async fn sync_from_latest(&mut self) -> Result<(), AuthExpired> {
        let url = format!("{SP}/speechless/v1/retrieve/chats-share-set/latest");
        let Ok(response) = self
            .speechless_request(&url)
            .header("content-length", "0")
            .body(Vec::<u8>::new())
            .send()
            .await
        else {
            return Ok(());
        };
        match response.status().as_u16() {
            401 | 403 => return Err(AuthExpired),
            200..=299 => {}
            _ => return Ok(()),
        }
        let Ok(bytes) = response.bytes().await else {
            return Ok(());
        };
        let now_sec = now_ms() / 1000;
        let candidates = extract_invite_candidates(&bytes, now_sec);
        self.process_candidates(candidates).await?;
        for chat_id in extract_recent_chat_ids(&bytes, now_sec) {
            self.sync_hierarchy(&chat_id).await?;
        }
        Ok(())
    }
}

enum Outcome {
    Stop,
    Dropped,
    AuthExpired,
}

async fn run_connection(watcher: &mut Watcher, lines: &mut Lines) -> Outcome {
    let url = format!("wss://dealer.spotify.com/?access_token={}", watcher.bearer);
    let mut socket = match tokio::time::timeout(
        Duration::from_secs(12),
        tokio_tungstenite::connect_async(url),
    )
    .await
    {
        Ok(Ok((socket, _))) => socket,
        Ok(Err(WsError::Http(resp))) if matches!(resp.status().as_u16(), 401 | 403) => {
            return Outcome::AuthExpired;
        }
        _ => return Outcome::Dropped,
    };

    if watcher.sync_from_latest().await.is_err() {
        return Outcome::AuthExpired;
    }

    let mut ping = tokio::time::interval(PING_INTERVAL);
    ping.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut recheck = tokio::time::interval_at(
        tokio::time::Instant::now() + RECHECK_INTERVAL,
        RECHECK_INTERVAL,
    );
    recheck.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

    loop {
        tokio::select! {
            line = lines.next_line() => {
                let Ok(Some(line)) = line else { return Outcome::Stop };
                let Ok(message) = serde_json::from_str::<Value>(&line) else { continue };
                match message.get("type").and_then(Value::as_str) {
                    Some("leave") | Some("stop") => return Outcome::Stop,
                    Some("credential") => {
                        if let Some(token) = message
                            .get("credential")
                            .and_then(Value::as_str)
                            .and_then(clean_bearer)
                        {
                            watcher.bearer = token;
                        }
                    }
                    _ => {}
                }
            }
            _ = ping.tick() => {
                if socket
                    .send(Message::Text(r#"{"type":"ping"}"#.into()))
                    .await
                    .is_err()
                {
                    return Outcome::Dropped;
                }
            }
            _ = recheck.tick(), if !watcher.active_invites.is_empty() => {
                if watcher.recheck_active_invites().await.is_err() {
                    return Outcome::AuthExpired;
                }
            }
            frame = socket.next() => {
                let text = match frame {
                    Some(Ok(Message::Text(text))) => text,
                    Some(Ok(Message::Close(_))) | Some(Err(_)) | None => return Outcome::Dropped,
                    Some(Ok(_)) => continue,
                };
                let Ok(message) = serde_json::from_str::<Value>(&text) else { continue };
                let uri = message.get("uri").and_then(Value::as_str).unwrap_or("");
                if !uri.contains("campfire/v1/hierarchy-message-changed") {
                    continue;
                }
                let chat_ids = message
                    .get("payloads")
                    .and_then(Value::as_array)
                    .and_then(|p| p.first())
                    .map(extract_chat_ids_from_payload)
                    .unwrap_or_default();
                if chat_ids.is_empty() {
                    if watcher.sync_from_latest().await.is_err() {
                        return Outcome::AuthExpired;
                    }
                } else {
                    for chat_id in chat_ids {
                        if watcher.sync_hierarchy(&chat_id).await.is_err() {
                            return Outcome::AuthExpired;
                        }
                    }
                }
            }
        }
    }
}

async fn wait_for_credential(watcher: &mut Watcher, lines: &mut Lines) -> bool {
    loop {
        let Ok(Some(line)) = lines.next_line().await else {
            return true;
        };
        let Ok(message) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        match message.get("type").and_then(Value::as_str) {
            Some("leave") | Some("stop") => return true,
            Some("credential") => {
                if let Some(token) = message
                    .get("credential")
                    .and_then(Value::as_str)
                    .and_then(clean_bearer)
                {
                    watcher.bearer = token;
                    return false;
                }
            }
            _ => {}
        }
    }
}

async fn wait_backoff(watcher: &mut Watcher, lines: &mut Lines, wait: Duration) -> bool {
    let sleep = tokio::time::sleep(wait);
    tokio::pin!(sleep);
    loop {
        tokio::select! {
            _ = &mut sleep => return false,
            line = lines.next_line() => {
                let Ok(Some(line)) = line else { return true };
                let Ok(message) = serde_json::from_str::<Value>(&line) else { continue };
                match message.get("type").and_then(Value::as_str) {
                    Some("leave") | Some("stop") => return true,
                    Some("credential") => {
                        if let Some(token) = message
                            .get("credential")
                            .and_then(Value::as_str)
                            .and_then(clean_bearer)
                        {
                            watcher.bearer = token;
                            return false;
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}

pub async fn run(http: Client, bearer: String, client_token: String, lines: &mut Lines) {
    let mut watcher = Watcher {
        http,
        bearer,
        client_token,
        profile_cache: HashMap::new(),
        active_invites: HashMap::new(),
        dead_tokens: HashSet::new(),
    };
    let mut failures = 0u32;
    loop {
        let started = now_ms();
        match run_connection(&mut watcher, lines).await {
            Outcome::Stop => return,
            Outcome::AuthExpired => {
                fail("authRequired", true);
                if wait_for_credential(&mut watcher, lines).await {
                    return;
                }
                failures = 0;
            }
            Outcome::Dropped => {
                fail("network", true);
                failures = if now_ms() - started > 60_000 {
                    1
                } else {
                    failures + 1
                };
                let wait = Duration::from_secs(2u64.pow(failures.min(5)));
                if wait_backoff(&mut watcher, lines, wait).await {
                    return;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use flate2::write::GzEncoder;
    use flate2::Compression;
    use std::io::Write;

    fn pb_bytes(field_num: u64, bytes: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        encode_bytes_field(&mut out, field_num, bytes);
        out
    }

    fn pb_str(field_num: u64, text: &str) -> Vec<u8> {
        pb_bytes(field_num, text.as_bytes())
    }

    fn pb_varint(field_num: u64, value: u64) -> Vec<u8> {
        let mut out = Vec::new();
        encode_varint_field(&mut out, field_num, value);
        out
    }

    fn build_message(
        subtype: u64,
        msg_uri: &str,
        sender_uid: &str,
        sent_sec: u64,
        nanos: u64,
        text_body: Option<&str>,
        share_uri: Option<&str>,
    ) -> Vec<u8> {
        let mut header = pb_bytes(2, &pb_varint(2, subtype));
        header.extend(pb_str(3, msg_uri));

        let mut ts_inner = pb_varint(1, sent_sec);
        ts_inner.extend(pb_varint(2, nanos));
        let ts_outer = pb_bytes(1, &ts_inner);
        let mut sender = pb_str(1, sender_uid);
        sender.extend(pb_bytes(2, &ts_outer));

        let mut content = Vec::new();
        if let Some(t) = text_body {
            content.extend(pb_bytes(1, &pb_str(1, t)));
        }
        if let Some(s) = share_uri {
            content.extend(pb_bytes(2, &pb_str(1, s)));
        }
        let body = pb_bytes(1, &content);

        let mut msg = pb_bytes(1, &header);
        msg.extend(pb_bytes(6, &sender));
        msg.extend(pb_bytes(8, &body));
        msg
    }

    #[test]
    fn parses_chats_share_set_protobuf_and_filters_non_jam_messages() {
        let now_sec = 1_700_000_000i64;
        let fresh_ts = (now_sec - 120) as u64;
        let stale_ts = (now_sec - 13 * 3600) as u64;

        let jam_msg = build_message(
            1,
            "spotify:chat-message:msgJam123",
            "senderAlice",
            fresh_ts,
            456_000_000,
            None,
            Some("spotify:socialsession:5QaRAjTyChieQ3Z8fdSlqu?si=xyz123"),
        );
        let text_msg = build_message(
            2,
            "spotify:chat-message:msgText456",
            "senderBob",
            fresh_ts,
            0,
            Some("hola"),
            None,
        );
        let track_msg = build_message(
            5,
            "spotify:chat-message:msgTrack789",
            "senderBob",
            fresh_ts,
            0,
            None,
            Some("spotify:track:4cOdK2wGLETKBW3PvgPWqT"),
        );
        let stale_jam_msg = build_message(
            1,
            "spotify:chat-message:msgOld000",
            "senderOld",
            stale_ts,
            0,
            None,
            Some("https://open.spotify.com/socialsession/AbCdEfGhIjKlMnOpQrStUv"),
        );
        let plain_text_jam_msg = build_message(
            2,
            "spotify:chat-message:msgTextJam",
            "senderCarol",
            fresh_ts,
            0,
            Some("join here https://open.spotify.com/socialsession/XyZ1234567890AbCdEfG?si=1!"),
            None,
        );

        let wrap = |chat_uri: &str, msg: &[u8]| -> Vec<u8> {
            let meta = pb_str(3, chat_uri);
            let mut w = pb_bytes(1, &meta);
            w.extend(pb_bytes(2, msg));
            pb_bytes(1, &w)
        };

        let mut payload = Vec::new();
        payload.extend(wrap("spotify:chat:1111111111111111111111", &jam_msg));
        payload.extend(wrap("spotify:chat:2222222222222222222222", &text_msg));
        payload.extend(wrap("spotify:chat:3333333333333333333333", &track_msg));
        payload.extend(wrap("spotify:chat:4444444444444444444444", &stale_jam_msg));
        payload.extend(wrap(
            "spotify:chat:5555555555555555555555",
            &plain_text_jam_msg,
        ));

        let candidates = extract_invite_candidates(&payload, now_sec);
        assert_eq!(candidates.len(), 2);
        assert_eq!(candidates[0].msg_id, "msgJam123");
        assert_eq!(candidates[0].token, "5QaRAjTyChieQ3Z8fdSlqu");
        assert_eq!(
            candidates[0].link,
            "spotify:socialsession:5QaRAjTyChieQ3Z8fdSlqu?si=xyz123"
        );
        assert_eq!(candidates[0].sender_uid, "senderAlice");
        assert_eq!(candidates[0].sent_at_ms, (fresh_ts as i64) * 1000 + 456);

        assert_eq!(candidates[1].msg_id, "msgTextJam");
        assert_eq!(candidates[1].token, "XyZ1234567890AbCdEfG");
        assert_eq!(
            candidates[1].link,
            "https://open.spotify.com/socialsession/XyZ1234567890AbCdEfG?si=1"
        );
        assert_eq!(candidates[1].sender_uid, "senderCarol");

        let recent_chats = extract_recent_chat_ids(&payload, now_sec);
        assert_eq!(
            recent_chats,
            vec![
                "1111111111111111111111",
                "2222222222222222222222",
                "3333333333333333333333",
                "5555555555555555555555",
            ]
        );
    }

    #[test]
    fn parses_retrieve_hierarchy_repeated_messages_and_encodes_request() {
        let now_sec = 1_700_000_000i64;
        let mut msg_with_read_state = build_message(
            1,
            "spotify:chat-message:hierMsg1",
            "hostUid",
            (now_sec - 30) as u64,
            0,
            None,
            Some("https://open.spotify.com/socialsession/99887766554433221100AA"),
        );
        msg_with_read_state.extend(pb_varint(4, 1));

        let hierarchy = pb_bytes(1, &msg_with_read_state);
        let candidates = extract_invite_candidates(&hierarchy, now_sec);
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].msg_id, "hierMsg1");
        assert_eq!(candidates[0].token, "99887766554433221100AA");

        let req = encode_hierarchy_request("AbCdEfGhIjKlMnOpQrStUv");
        assert_eq!(req[0], 0x0a);
        assert_eq!(req[1], 22);
        assert_eq!(&req[2..], b"AbCdEfGhIjKlMnOpQrStUv");
    }

    #[test]
    fn extracts_chat_ids_from_dealer_hierarchy_message_changed_payloads() {
        let chat_id = "AbCdEfGhIjKlMnOpQrStUv";
        let pb = pb_bytes(2, &pb_str(1, &format!("spotify:chat:{chat_id}")));
        let b64 = base64::engine::general_purpose::STANDARD.encode(&pb);
        assert_eq!(
            extract_chat_ids_from_payload(&json!(b64)),
            vec![chat_id.to_string()]
        );

        let mut gz = GzEncoder::new(Vec::new(), Compression::default());
        gz.write_all(&pb).unwrap();
        let gz_b64 = base64::engine::general_purpose::STANDARD.encode(gz.finish().unwrap());
        assert_eq!(
            extract_chat_ids_from_payload(&json!(gz_b64)),
            vec![chat_id.to_string()]
        );

        let json_payload = json!({"chat_uri": format!("spotify:chat:{chat_id}")});
        assert_eq!(
            extract_chat_ids_from_payload(&json_payload),
            vec![chat_id.to_string()]
        );
    }

    #[test]
    fn parses_session_info_active_inactive_and_owner() {
        let active_guest = json!({
            "active": true,
            "is_session_owner": false,
            "session_owner_id": "owner-1",
            "session_members": [
                {"id": "owner-1", "display_name": "Alice", "image_url": "https://i.scdn.co/a.jpg"},
                {"id": "guest-2", "username": "Bob"}
            ]
        });
        let info = parse_session_info(&active_guest);
        assert_eq!(
            info,
            SessionInfo {
                active: true,
                is_owner: false,
                owner_name: Some("Alice".into()),
                owner_image_url: Some("https://i.scdn.co/a.jpg".into()),
                participant_count: 2,
            }
        );

        let username_fallback = json!({
            "active": true,
            "is_session_owner": false,
            "session_owner_id": "owner-1",
            "session_members": [
                {"id": "owner-1", "username": "alice_user"}
            ]
        });
        let fallback_info = parse_session_info(&username_fallback);
        assert_eq!(fallback_info.owner_name.as_deref(), Some("alice_user"));
        assert_eq!(fallback_info.owner_image_url, None);
        assert_eq!(fallback_info.participant_count, 1);

        let inactive = json!({"active": false, "is_session_owner": false});
        assert!(!parse_session_info(&inactive).active);

        let self_hosted = json!({"active": true, "is_session_owner": true});
        let self_info = parse_session_info(&self_hosted);
        assert!(self_info.active);
        assert!(self_info.is_owner);
    }
}
