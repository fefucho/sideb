//! Fetching test material from YouTube Music through the app's own
//! `innertube` crate, anonymously. Downloads are cached by video id.
//!
//! Anonymous on purpose: this bench never touches the app's account or its
//! stored cookies. That means the standard 128 kbps AAC stream rather than
//! the subscriber one, which is plenty for judging a transition.

use anyhow::{anyhow, bail, Context, Result};
use innertube::{Clients, InnerTube, Session, METADATA_CLIENT, STREAM_FALLBACK_ORDER};
use std::path::{Path, PathBuf};

pub struct Fetched {
    pub path: PathBuf,
    pub title: String,
}

/// `what` is a video id, a watch URL, or free text to search for.
pub fn fetch(what: &str, cache_dir: &Path) -> Result<Fetched> {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?
        .block_on(fetch_async(what, cache_dir))
}

fn video_id_in(text: &str) -> Option<String> {
    let is_id = |s: &str| s.len() == 11 && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
    if is_id(text) {
        return Some(text.to_owned());
    }
    let after = text.split("v=").nth(1).or_else(|| text.split("youtu.be/").nth(1))?;
    let id: String = after.chars().take(11).collect();
    is_id(&id).then_some(id)
}

async fn fetch_async(what: &str, cache_dir: &Path) -> Result<Fetched> {
    let anonymous = InnerTube::new(Session::default(), None).map_err(|e| anyhow!("{e}"))?;
    let visitor_data = anonymous.fetch_visitor_data().await.ok();
    let it = InnerTube::new(Session { visitor_data, ..Session::default() }, None).map_err(|e| anyhow!("{e}"))?;
    let clients = Clients::bundled();

    let (video_id, mut title) = match video_id_in(what) {
        Some(id) => (id, String::new()),
        None => {
            let client = clients.get(METADATA_CLIENT).context("falta el cliente de metadatos")?;
            let found = it.search_songs(client, what, false).await.map_err(|e| anyhow!("búsqueda: {e}"))?;
            let song = found.items.first().with_context(|| format!("sin resultados para «{what}»"))?;
            (song.video_id.clone(), format!("{} - {}", song.artists, song.title))
        }
    };
    if title.is_empty() {
        title = video_id.clone();
    }

    std::fs::create_dir_all(cache_dir)?;
    let path = cache_dir.join(format!("{video_id}.m4a"));
    if path.exists() {
        return Ok(Fetched { path, title });
    }

    // AAC in MP4 specifically: it is what this bench can decode.
    let mut url = None;
    for key in STREAM_FALLBACK_ORDER {
        let Some(client) = clients.get(key) else { continue };
        let Ok(response) = it.player(client, &video_id, None, None, None).await else { continue };
        if !response.playability_status.is_ok() {
            continue;
        }
        let Some(streams) = response.streaming_data.as_ref() else { continue };
        let best = streams
            .adaptive_formats
            .iter()
            .filter(|f| f.is_audio() && f.is_original() && f.mime_type.contains("mp4a") && f.direct_url().is_some())
            .max_by_key(|f| f.bitrate);
        if let Some(format) = best {
            url = format.direct_url().map(str::to_owned);
            break;
        }
    }
    let url = url.with_context(|| format!("no se pudo resolver un stream AAC para {video_id}"))?;

    // Ranged requests: an unranged GET of a media URL is throttled hard.
    let http = reqwest::Client::new();
    let mut data: Vec<u8> = Vec::new();
    const CHUNK: usize = 1 << 20;
    loop {
        let range = format!("bytes={}-{}", data.len(), data.len() + CHUNK - 1);
        let response = http.get(&url).header("Range", range).send().await?;
        let status = response.status();
        if status.as_u16() == 416 {
            break;
        }
        if !status.is_success() {
            bail!("descarga de {video_id}: HTTP {status}");
        }
        let bytes = response.bytes().await?;
        let got = bytes.len();
        data.extend_from_slice(&bytes);
        if got < CHUNK {
            break;
        }
    }
    if data.is_empty() {
        bail!("descarga vacía para {video_id}");
    }
    std::fs::write(&path, &data)?;
    Ok(Fetched { path, title })
}
