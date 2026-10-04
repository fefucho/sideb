uniffi::setup_scaffolding!();

pub mod blocked;
pub mod cipher;
pub mod db;
pub mod genius;
// pub mod discord;
pub mod http;
// pub mod lastfm;
pub mod local;
pub mod lyrics;
pub mod orchestrator;
pub mod potoken;

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;

pub use genius::{
    GeniusAnnotationRecord, GeniusAnnotationsRecord, GeniusCandidateRecord, GeniusLyricLineRecord,
    GeniusLyricsRecord, GeniusMatchStatusRecord, GeniusMetricsRecord, GeniusPerformanceRecord,
    GeniusResolutionRecord, GeniusSongRecord, GeniusTrackRecord,
};
use innertube::{AudioQuality, Clients, InnerTube, PlaylistSort, METADATA_CLIENT};

/// Runs YouTube's player.js in the native JavaScriptCore process on macOS.
#[uniffi::export(callback_interface)]
pub trait CipherJsRuntime: Send + Sync {
    fn load(&self, script: String) -> bool;
    fn evaluate(&self, expression: String) -> Option<String>;
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum SideBError {
    #[error("Network error: {message}")]
    NetworkError { message: String },
    #[error("Parse error: {message}")]
    ParseError { message: String },
    #[error("Stream resolution error: {message}")]
    StreamError { message: String },
    #[error("Database error: {message}")]
    DbError { message: String },
    #[error("Not found: {message}")]
    NotFound { message: String },
    #[error("Error: {message}")]
    Other { message: String },
}

impl From<innertube::Error> for SideBError {
    fn from(err: innertube::Error) -> Self {
        SideBError::NetworkError {
            message: err.to_string(),
        }
    }
}

impl From<serde_json::Error> for SideBError {
    fn from(err: serde_json::Error) -> Self {
        SideBError::ParseError {
            message: err.to_string(),
        }
    }
}

impl From<orchestrator::ResolveError> for SideBError {
    fn from(err: orchestrator::ResolveError) -> Self {
        SideBError::StreamError {
            message: err.to_string(),
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct StreamPlaybackInfo {
    pub video_id: String,
    pub stream_url: String,
    pub itag: i64,
    pub loudness_db: Option<f64>,
    pub expires_in_seconds: i64,
    pub is_video: bool,
    pub stream_client: String,
    pub title: Option<String>,
    pub artists: Option<String>,
    pub duration: Option<String>,
    pub thumbnail: Option<String>,
    pub headers: std::collections::HashMap<String, String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct LyricLineInfo {
    pub time_ms: Option<u64>,
    pub end_time_ms: Option<u64>,
    pub text: String,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct LibraryToggleRecord {
    pub in_library: bool,
    pub add_token: Option<String>,
    pub remove_token: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct SongItemRecord {
    pub video_id: String,
    pub title: String,
    pub artists: String,
    pub album: Option<String>,
    pub duration: Option<String>,
    pub thumbnail: Option<String>,
    pub artist_id: Option<String>,
    pub album_id: Option<String>,
    pub set_video_id: Option<String>,
    pub is_video: bool,
    pub is_upload: bool,
    pub library: Option<LibraryToggleRecord>,
    pub artist_runs: Vec<HomeArtistRunRecord>,
}

impl From<innertube::SongItem> for SongItemRecord {
    fn from(item: innertube::SongItem) -> Self {
        Self {
            video_id: item.video_id,
            title: item.title,
            artists: item.artists,
            album: item.album,
            duration: item.duration,
            thumbnail: item.thumbnail,
            artist_id: item.artist_id,
            artist_runs: item.artist_runs.into_iter().map(|run| HomeArtistRunRecord { text: run.text, id: run.id }).collect(),
            album_id: item.album_id,
            set_video_id: item.set_video_id,
            is_video: item.is_video,
            is_upload: item.is_upload,
            library: item.library.map(|toggle| LibraryToggleRecord {
                in_library: toggle.in_library,
                add_token: toggle.add_token,
                remove_token: toggle.remove_token,
            }),
        }
    }
}

impl From<innertube::BrowseItem> for SongItemRecord {
    fn from(item: innertube::BrowseItem) -> Self {
        let artists = item.artists.unwrap_or_else(|| item.subtitle.unwrap_or_default());
        let artist_id = item.artist_id.or_else(|| item.artist_runs.iter().find_map(|run| run.id.clone()));
        Self {
            video_id: item.id,
            title: item.title,
            artists,
            album: item.album,
            duration: item.duration,
            thumbnail: item.thumbnail,
            artist_id,
            album_id: item.album_id,
            set_video_id: None,
            is_video: item.is_video,
            is_upload: item.is_upload,
            library: None,
            artist_runs: item.artist_runs.into_iter().map(|run| HomeArtistRunRecord { text: run.text, id: run.id }).collect(),
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct NextResultRecord {
    pub items: Vec<SongItemRecord>,
    pub lyrics_browse_id: Option<String>,
    pub related_browse_id: Option<String>,
    pub automix_playlist_id: Option<String>,
    pub continuation: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct HomeItemRecord {
    pub kind: String,
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub thumbnail: Option<String>,
    pub duration: Option<String>,
    pub artists: Option<String>,
    pub artist_id: Option<String>,
    pub album: Option<String>,
    pub album_id: Option<String>,
    pub artist_runs: Vec<HomeArtistRunRecord>,
    pub explicit: bool,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct HomeArtistRunRecord {
    pub text: String,
    pub id: Option<String>,
}

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum HomeSectionFormatRecord {
    LargeCards,
    CompactSongs,
    Mixed,
}

impl From<innertube::SectionFormat> for HomeSectionFormatRecord {
    fn from(format: innertube::SectionFormat) -> Self {
        match format {
            innertube::SectionFormat::LargeCards => Self::LargeCards,
            innertube::SectionFormat::CompactSongs => Self::CompactSongs,
            innertube::SectionFormat::Mixed => Self::Mixed,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct HomeChipRecord {
    pub title: String,
    pub params: String,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct HomeSectionRecord {
    pub title: String,
    pub format: HomeSectionFormatRecord,
    pub items: Vec<HomeItemRecord>,
    pub more_browse_id: Option<String>,
    pub more_params: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct HomePageRecord {
    pub chips: Vec<HomeChipRecord>,
    pub sections: Vec<HomeSectionRecord>,
    pub continuation: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct LyricsInfo {
    pub provider: String,
    pub is_synced: bool,
    pub lines: Vec<LyricLineInfo>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct AccountInfoRecord {
    pub name: Option<String>,
    pub handle: Option<String>,
    pub email: Option<String>,
    pub thumbnail: Option<String>,
    pub channel_id: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct BrowseCardRecord {
    pub kind: String,
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub thumbnail: Option<String>,
    pub duration: Option<String>,
    #[cfg(feature = "windows-bridge")]
    pub artists: Option<String>,
    #[cfg(feature = "windows-bridge")]
    pub artist_id: Option<String>,
    #[cfg(feature = "windows-bridge")]
    pub album: Option<String>,
    #[cfg(feature = "windows-bridge")]
    pub album_id: Option<String>,
    #[cfg(feature = "windows-bridge")]
    pub is_video: bool,
    #[cfg(feature = "windows-bridge")]
    pub explicit: bool,
    #[cfg(feature = "windows-bridge")]
    pub artist_runs: Vec<HomeArtistRunRecord>,
}

impl From<innertube::BrowseItem> for BrowseCardRecord {
    fn from(item: innertube::BrowseItem) -> Self {
        Self {
            kind: item.kind.to_owned(),
            id: item.id,
            title: item.title,
            subtitle: item.subtitle,
            thumbnail: item.thumbnail,
            duration: item.duration,
            #[cfg(feature = "windows-bridge")]
            artists: item.artists,
            #[cfg(feature = "windows-bridge")]
            artist_id: item.artist_id,
            #[cfg(feature = "windows-bridge")]
            album: item.album,
            #[cfg(feature = "windows-bridge")]
            album_id: item.album_id,
            #[cfg(feature = "windows-bridge")]
            is_video: item.is_video,
            #[cfg(feature = "windows-bridge")]
            explicit: item.explicit,
            #[cfg(feature = "windows-bridge")]
            artist_runs: item
                .artist_runs
                .into_iter()
                .map(|run| HomeArtistRunRecord {
                    text: run.text,
                    id: run.id,
                })
                .collect(),
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct HistoryGroupRecord {
    pub title: String,
    pub items: Vec<SongItemRecord>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct PlaylistDetailRecord {
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub thumbnail: Option<String>,
    pub description: Option<String>,
    pub items: Vec<SongItemRecord>,
    pub continuation: Option<String>,
    pub owned: bool,
    pub in_library: bool,
    pub privacy: Option<String>,
    pub collaborative: bool,
    pub sort: Option<String>,
    pub sort_editable: bool,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct AlbumDetailRecord {
    pub browse_id: String,
    pub title: String,
    pub artist: Option<String>,
    pub artist_id: Option<String>,
    pub subtitle: Option<String>,
    pub second_subtitle: Option<String>,
    pub description: Option<String>,
    pub thumbnail: Option<String>,
    pub playlist_id: Option<String>,
    pub in_library: bool,
    pub items: Vec<SongItemRecord>,
    pub sections: Vec<ArtistCarouselRecord>,
    #[cfg(feature = "windows-bridge")]
    pub artist_runs: Vec<HomeArtistRunRecord>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct ArtistCarouselRecord {
    pub title: String,
    pub items: Vec<BrowseCardRecord>,
    pub more_browse_id: Option<String>,
    pub more_params: Option<String>,
}

impl From<innertube::ArtistCarousel> for ArtistCarouselRecord {
    fn from(c: innertube::ArtistCarousel) -> Self {
        Self {
            title: c.title,
            items: c.items.into_iter().map(BrowseCardRecord::from).collect(),
            more_browse_id: c.more_browse_id,
            more_params: c.more_params,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct ArtistDetailRecord {
    pub channel_id: String,
    pub name: String,
    pub thumbnail: Option<String>,
    pub description: Option<String>,
    pub subscribers: Option<String>,
    pub monthly_listeners: Option<String>,
    pub subscribed: bool,
    pub radio_playlist_id: Option<String>,
    pub top_songs: Vec<SongItemRecord>,
    pub top_songs_id: Option<String>,
    pub sections: Vec<ArtistCarouselRecord>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct SearchResultsRecord {
    /// Every song in the provider's top-result section, in provider order, including a song hero.
    pub top_songs: Vec<SongItemRecord>,
    pub top: Vec<BrowseCardRecord>,
    pub songs: Vec<SongItemRecord>,
    pub albums: Vec<BrowseCardRecord>,
    pub artists: Vec<BrowseCardRecord>,
    pub playlists: Vec<BrowseCardRecord>,
}

fn search_top_songs(items: &[innertube::BrowseItem]) -> Vec<SongItemRecord> {
    items.iter().filter(|item| item.kind == "song").cloned().map(SongItemRecord::from).collect()
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct PlaylistContinuationRecord {
    pub items: Vec<SongItemRecord>,
    pub continuation: Option<String>,
}

#[derive(Clone)]
struct CorePlaybackTracking {
    video_id: String,
    ping: orchestrator::PlaybackPing,
    cpn: String,
}

#[derive(uniffi::Object)]
pub struct SideBCore {
    data_dir: PathBuf,
    db: Arc<db::Db>,
    persist_cookie_in_sqlite: bool,
    it: InnerTube,
    clients: Clients,
    orchestrator: Arc<orchestrator::Orchestrator>,
    potoken: Arc<potoken::PoTokenGenerator>,
    cipher: Arc<cipher::CipherDeobfuscator>,
    current_playback: Arc<Mutex<Option<CorePlaybackTracking>>>,
    genius: Arc<genius::GeniusEngine>,
}

impl SideBCore {
    fn build(data_dir: String, persist_cookie_in_sqlite: bool) -> Result<Arc<Self>, SideBError> {
        let path = PathBuf::from(&data_dir);
        std::fs::create_dir_all(&path).map_err(|e| SideBError::DbError {
            message: format!("Failed to create data directory: {e}"),
        })?;

        let db_path = path.join("sideb.db");
        let db = Arc::new(db::Db::open(&db_path).map_err(|e| SideBError::DbError {
            message: format!("Failed to open database: {e}"),
        })?);

        if !persist_cookie_in_sqlite {
            db.clear_persisted_session_cookies()
                .map_err(|e| SideBError::DbError {
                message: format!("Failed to clear legacy session credentials: {e}"),
            })?;
        }

        let it =
            InnerTube::new(innertube::Session::default(), None).map_err(|e| SideBError::Other {
                message: format!("Failed to create InnerTube: {e}"),
            })?;
        let clients = Clients::bundled();

        let player_config_cache = path.join("player_configs.json");
        let player_config_store = Arc::new(cipher::PlayerConfigStore::new(&player_config_cache));

        let cipher = Arc::new(cipher::CipherDeobfuscator::new(&path, player_config_store));

        let potoken = Arc::new(potoken::PoTokenGenerator::new(db.clone()));

        let orchestrator = Arc::new(orchestrator::Orchestrator::new(
            it.clone(),
            clients.clone(),
            cipher.clone(),
            potoken.clone(),
        ));

        // The Windows host supplies session credentials from its OS credential store.
        // Never rehydrate a legacy SQLite cookie for that construction path.
        if persist_cookie_in_sqlite {
            if let Some(cookie) = db.get_setting("session_cookie") {
                it.set_cookie(Some(cookie));
            }
        }

        // visitor_data is public client state rather than an authentication credential.
        if let Some(vd) = db.get_setting("visitor_data") {
            it.set_visitor_data(Some(vd));
        }

        Ok(Arc::new(SideBCore {
            data_dir: path,
            genius: Arc::new(genius::GeniusEngine::new(db.clone())),
            db,
            persist_cookie_in_sqlite,
            it,
            clients,
            orchestrator,
            potoken,
            cipher,
            current_playback: Arc::new(Mutex::new(None)),
        }))
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl SideBCore {
    #[uniffi::constructor]
    pub fn new(data_dir: String) -> Result<Arc<Self>, SideBError> {
        Self::build(data_dir, true)
    }

    pub fn set_cipher_js_runtime(&self, runtime: Box<dyn CipherJsRuntime>) {
        self.cipher.set_runtime(Arc::from(runtime));
    }

    /// Set session cookie extracted from Swift WKWebView or login flow.
    pub fn set_cookie(&self, cookie: Option<String>) {
        if self.persist_cookie_in_sqlite {
            if let Some(ref c) = cookie {
                self.db.set_setting("session_cookie", c);
            } else {
                self.db.delete_setting("session_cookie");
            }
        }
        self.it.set_cookie(cookie);
    }

    pub fn get_cookie(&self) -> Option<String> {
        self.it.cookie()
    }

    pub fn is_logged_in(&self) -> bool {
        self.it.is_logged_in()
    }

    /// Fetch logged in user account info via InnerTube account_menu.
    pub async fn get_account_info(&self) -> Result<AccountInfoRecord, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let info = self
            .it
            .account_menu(client)
            .await
            .map_err(|e| SideBError::NetworkError {
            message: e.to_string(),
        })?;
        Ok(AccountInfoRecord {
            name: info.name,
            handle: info.handle,
            email: info.email,
            thumbnail: info.thumbnail,
            channel_id: info.channel_id,
        })
    }

    /// Fetch user's saved library playlists.
    pub async fn get_library_playlists(&self) -> Result<Vec<BrowseCardRecord>, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let items =
            self.it
                .library_playlists(client)
                .await
                .map_err(|e| SideBError::NetworkError {
            message: e.to_string(),
        })?;
        Ok(items.into_iter().map(BrowseCardRecord::from).collect())
    }

    /// Fetch user's saved library albums.
    pub async fn get_library_albums(&self) -> Result<Vec<BrowseCardRecord>, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let items = self
            .it
            .library_albums(client)
            .await
            .map_err(|e| SideBError::NetworkError {
            message: e.to_string(),
        })?;
        Ok(items.into_iter().map(BrowseCardRecord::from).collect())
    }

    /// Library Songs is a track shelf with continuation, rather than a card grid.
    pub async fn get_library_songs(&self) -> Result<PlaylistContinuationRecord, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
            message: "Metadata client missing".into(),
        })?;
        let page = self.it.library_songs(client).await?;
        Ok(PlaylistContinuationRecord {
            items: page.items.into_iter().map(SongItemRecord::from).collect(),
            continuation: page.continuation,
        })
    }

    pub async fn get_library_artists(&self) -> Result<Vec<BrowseCardRecord>, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
            message: "Metadata client missing".into(),
        })?;
        let items = self.it.library_artists(client).await?;
        Ok(items.into_iter().map(BrowseCardRecord::from).collect())
    }

    /// Fetch user's playback history grouped by day.
    /// If online and logged in, merges remote YouTube Music history with recent local plays.
    /// If offline or logged out, builds daily groups from the local SQLite history for the last 30 days.
    pub async fn get_history(&self) -> Result<Vec<HistoryGroupRecord>, SideBError> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        // 1. If logged in, attempt remote history from YouTube Music
        let remote_groups_res = if self.is_logged_in() {
            if let Some(client) = self.clients.get(METADATA_CLIENT) {
                self.it.history(client).await.ok()
            } else {
                None
            }
        } else {
            None
        };

        if let Some(remote_groups) = remote_groups_res {
            let mut groups: Vec<HistoryGroupRecord> = remote_groups
                .into_iter()
                .map(|g| HistoryGroupRecord {
                    title: g.title,
                    items: g.items.into_iter().map(SongItemRecord::from).collect(),
                })
                .collect();

            // Merge recent local plays from SQLite (last 4 hours) into the first group ("Today" / "Hoy")
            // so newly played tracks appear with 0ms delay even before Google's videostats ping indexes.
            const MERGE_WINDOW_SECS: i64 = 4 * 3600;
            let recent_local = self.db.recent_plays(now.saturating_sub(MERGE_WINDOW_SECS));
            if !recent_local.is_empty() {
                if groups.is_empty() {
                    groups.push(HistoryGroupRecord {
                        title: "Hoy".into(),
                        items: Vec::new(),
                    });
                }
                let first_group = &mut groups[0];
                for (_played_at, json) in recent_local.into_iter().rev() {
                    if let Some(song_rec) = parse_song_record(&json) {
                        if !first_group
                            .items
                            .iter()
                            .any(|item| item.video_id == song_rec.video_id)
                        {
                            first_group.items.insert(0, song_rec);
                        }
                    }
                }
            }
            return Ok(groups);
        }

        // 2. Offline / logged out fallback: build history groups from SQLite for the last 30 days
        const THIRTY_DAYS_SECS: i64 = 30 * 86400;
        let local_plays = self.db.recent_plays(now.saturating_sub(THIRTY_DAYS_SECS));
        if local_plays.is_empty() {
            return Ok(Vec::new());
        }

        let mut groups: Vec<HistoryGroupRecord> = Vec::new();
        let mut current_day_key: Option<i64> = None;

        for (played_at, json) in local_plays {
            let day_key = played_at / 86400;
            if current_day_key != Some(day_key) {
                current_day_key = Some(day_key);
                let title = format_epoch_day(played_at, now);
                groups.push(HistoryGroupRecord {
                    title,
                    items: Vec::new(),
                });
            }
            if let Some(song_rec) = parse_song_record(&json) {
                if let Some(last_group) = groups.last_mut() {
                    last_group.items.push(song_rec);
                }
            }
        }

        Ok(groups)
    }

    /// Fetch playlist detail and tracks by id (e.g. "LM" for Liked Music, or VL...).
    pub async fn get_playlist(
        &self,
        playlist_id: String,
    ) -> Result<PlaylistDetailRecord, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let browse_id = if playlist_id.starts_with("VL") || playlist_id.starts_with("MPRE") {
            playlist_id.clone()
        } else {
            format!("VL{playlist_id}")
        };
        let page = self
            .it
            .playlist(client, &browse_id, None)
            .await
            .map_err(|e| SideBError::NetworkError {
            message: e.to_string(),
        })?;
        Ok(PlaylistDetailRecord {
            id: playlist_id,
            title: page.title.unwrap_or_else(|| "Playlist".into()),
            subtitle: page.subtitle,
            thumbnail: page.thumbnail,
            description: page.description,
            items: page.items.into_iter().map(SongItemRecord::from).collect(),
            continuation: page.continuation,
            owned: page.owned,
            in_library: page.in_library,
            privacy: page.privacy,
            collaborative: page.collaborative,
            sort: page
                .sort_menu
                .as_ref()
                .and_then(|m| m.selected)
                .map(|s| format!("{s:?}").to_ascii_lowercase()),
            sort_editable: page.sort_menu.as_ref().is_some_and(|m| m.editable),
        })
    }

    /// Fetch album detail and tracks by album browseId (e.g. "MPREb_...").
    pub async fn get_album(&self, browse_id: String) -> Result<AlbumDetailRecord, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let page =
            self.it
                .album(client, &browse_id)
                .await
                .map_err(|e| SideBError::NetworkError {
            message: e.to_string(),
        })?;
        Ok(AlbumDetailRecord {
            browse_id: browse_id.clone(),
            title: page.title.unwrap_or_else(|| "Album".into()),
            artist: page.artist,
            artist_id: page.artist_id,
            subtitle: page.subtitle,
            second_subtitle: page.second_subtitle,
            description: page.description,
            thumbnail: page.thumbnail,
            playlist_id: page.playlist_id,
            in_library: page.in_library,
            items: page.items.into_iter().map(SongItemRecord::from).collect(),
            sections: page
                .sections
                .into_iter()
                .map(ArtistCarouselRecord::from)
                .collect(),
            #[cfg(feature = "windows-bridge")]
            artist_runs: page
                .artist_runs
                .into_iter()
                .map(|run| HomeArtistRunRecord {
                    text: run.text,
                    id: run.id,
                })
                .collect(),
        })
    }

    /// Cards behind an artist carousel's "See all" browse endpoint.
    pub async fn get_browse_grid(
        &self,
        browse_id: String,
        params: Option<String>,
    ) -> Result<Vec<BrowseCardRecord>, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
            message: "Metadata client missing".into(),
        })?;
        let items = self
            .it
            .browse_grid(client, &browse_id, params.as_deref())
            .await?;
        Ok(items.into_iter().map(BrowseCardRecord::from).collect())
    }

    /// Fetch artist detail, top songs, and carousels by browseId (e.g. "UC...").
    pub async fn get_artist(&self, browse_id: String) -> Result<ArtistDetailRecord, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let page =
            self.it
                .artist(client, &browse_id)
                .await
                .map_err(|e| SideBError::NetworkError {
            message: e.to_string(),
        })?;
        Ok(ArtistDetailRecord {
            channel_id: page.channel_id,
            name: page.name.unwrap_or_else(|| "Artista".into()),
            thumbnail: page.thumbnail,
            description: page.description,
            subscribers: page.subscribers,
            monthly_listeners: page.monthly_listeners,
            subscribed: page.subscribed,
            radio_playlist_id: page.radio_playlist_id,
            top_songs: page
                .top_songs
                .into_iter()
                .map(SongItemRecord::from)
                .collect(),
            top_songs_id: page.top_songs_id,
            sections: page
                .sections
                .into_iter()
                .map(ArtistCarouselRecord::from)
                .collect(),
        })
    }

    /// Subscribe or unsubscribe to an artist channel.
    pub async fn subscribe_artist(
        &self,
        channel_id: String,
        subscribe: bool,
    ) -> Result<(), SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        self.it
            .subscribe(client, &channel_id, subscribe)
            .await
            .map_err(|e| SideBError::NetworkError {
            message: e.to_string(),
        })?;
        Ok(())
    }

    /// Like or unlike a playlist / album.
    pub async fn like_playlist(&self, playlist_id: String, like: bool) -> Result<(), SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let target_id = if playlist_id.starts_with("MPRE") {
            match self.it.album(client, &playlist_id).await {
                Ok(page) => page.playlist_id.unwrap_or(playlist_id),
                Err(_) => playlist_id,
            }
        } else {
            playlist_id
        };
        self.it
            .like_playlist(client, &target_id, like)
            .await
            .map_err(|e| SideBError::NetworkError {
            message: e.to_string(),
        })?;
        Ok(())
    }

    /// Apply the library action token supplied with a track row. This is separate from liking.
    pub async fn apply_song_library_action(&self, token: String) -> Result<(), SideBError> {
        if token.is_empty() {
            return Err(SideBError::Other {
                message: "Missing library action".into(),
            });
        }
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
            message: "Metadata client missing".into(),
        })?;
        self.it.feedback(client, &token).await?;
        Ok(())
    }

    /// Create a playlist and return the server's playlist ID.
    pub async fn create_playlist(
        &self,
        title: String,
        description: String,
        privacy: String,
    ) -> Result<String, SideBError> {
        let title = title.trim();
        if title.is_empty() {
            return Err(SideBError::Other {
                message: "Playlist name is required".into(),
            });
        }
        if title.contains(['<', '>']) {
            return Err(SideBError::Other {
                message: "Playlist name cannot contain < or >".into(),
            });
        }
        if !matches!(privacy.as_str(), "PRIVATE" | "UNLISTED" | "PUBLIC") {
            return Err(SideBError::Other {
                message: "Invalid playlist privacy".into(),
            });
        }
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
            message: "Metadata client missing".into(),
        })?;
        self.it
            .create_playlist_with_details(client, title, &description, &privacy)
            .await
            .map_err(Into::into)
    }

    pub async fn edit_playlist_details(
        &self,
        playlist_id: String,
        name: Option<String>,
        description: Option<String>,
        privacy: Option<String>,
    ) -> Result<(), SideBError> {
        let name = name.as_deref().map(str::trim);
        if name.is_some_and(str::is_empty) {
            return Err(SideBError::Other {
                message: "Playlist name is required".into(),
            });
        }
        if name.is_some_and(|value| value.contains(['<', '>'])) {
            return Err(SideBError::Other {
                message: "Playlist name cannot contain < or >".into(),
            });
        }
        if let Some(ref value) = privacy {
            if !matches!(value.as_str(), "PRIVATE" | "UNLISTED" | "PUBLIC") {
                return Err(SideBError::Other {
                    message: "Invalid playlist privacy".into(),
                });
            }
        }
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
            message: "Metadata client missing".into(),
        })?;
        self.it
            .playlist_edit_details(
                client,
                &playlist_id,
                name,
                description.as_deref(),
                privacy.as_deref(),
            )
            .await?;
        Ok(())
    }

    pub async fn set_playlist_sort(
        &self,
        playlist_id: String,
        sort: String,
    ) -> Result<(), SideBError> {
        let selected = match sort.as_str() {
            "default" => PlaylistSort::Default,
            "newest" => PlaylistSort::Newest,
            "oldest" => PlaylistSort::Oldest,
            "title" => PlaylistSort::Title,
            "artist" => PlaylistSort::Artist,
            "album" => PlaylistSort::Album,
            "top" => PlaylistSort::Top,
            _ => {
                return Err(SideBError::Other {
                    message: "Invalid playlist sort".into(),
                })
            }
        };
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
            message: "Metadata client missing".into(),
        })?;
        self.it
            .playlist_set_sort(client, &playlist_id, selected)
            .await?;
        Ok(())
    }

    pub async fn move_playlist_track(
        &self,
        playlist_id: String,
        set_video_id: String,
        successor_set_video_id: Option<String>,
    ) -> Result<(), SideBError> {
        if set_video_id.is_empty()
            || successor_set_video_id.as_deref() == Some(set_video_id.as_str())
        {
            return Err(SideBError::Other {
                message: "Invalid playlist track move".into(),
            });
        }
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
            message: "Metadata client missing".into(),
        })?;
        self.it
            .playlist_move(
                client,
                &playlist_id,
                &set_video_id,
                successor_set_video_id.as_deref(),
            )
            .await?;
        Ok(())
    }

    pub async fn delete_playlist(&self, playlist_id: String) -> Result<(), SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
            message: "Metadata client missing".into(),
        })?;
        self.it.delete_playlist(client, &playlist_id).await?;
        self.db.forget_playlist(&playlist_id);
        Ok(())
    }

    /// Add a track to a user playlist.
    pub async fn add_to_playlist(
        &self,
        playlist_id: String,
        video_id: String,
    ) -> Result<(), SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        self.it
            .playlist_add(client, &playlist_id, &video_id)
            .await
            .map_err(|e| SideBError::NetworkError {
            message: e.to_string(),
        })?;
        self.db.add_playlist_track(&playlist_id, &video_id);
        Ok(())
    }

    /// Remove a track from a user playlist.
    pub async fn remove_from_playlist(
        &self,
        playlist_id: String,
        video_id: String,
        set_video_id: String,
    ) -> Result<(), SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        self.it
            .playlist_remove(client, &playlist_id, &video_id, &set_video_id)
            .await
            .map_err(|e| SideBError::NetworkError {
                message: e.to_string(),
            })?;
        self.db.remove_playlist_track(&playlist_id, &video_id);
        Ok(())
    }

    /// Fetch continuation tracks for a playlist (typed record).
    pub async fn get_playlist_continuation(
        &self,
        token: String,
    ) -> Result<PlaylistContinuationRecord, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let cont = self
            .it
            .playlist_continuation(client, &token)
            .await
            .map_err(|e| SideBError::NetworkError {
            message: e.to_string(),
        })?;
        Ok(PlaylistContinuationRecord {
            items: cont.items.into_iter().map(SongItemRecord::from).collect(),
            continuation: cont.continuation,
        })
    }

    /// Fetch YouTube Music Home Page with mood chips, sections, and continuation token.
    pub async fn get_home_page(
        &self,
        chip_params: Option<String>,
    ) -> Result<HomePageRecord, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let page = match self.it.home(client, chip_params.as_deref()).await {
            Ok(p) => p,
            Err(innertube::Error::SessionExpired) => {
                self.set_cookie(None);
                self.it.home(client, chip_params.as_deref()).await?
            }
            Err(e) => return Err(e.into()),
        };
        Ok(HomePageRecord {
            chips: page
                .chips
                .into_iter()
                .map(|c| HomeChipRecord {
                    title: c.title,
                    params: c.params,
                })
                .collect(),
            sections: page
                .sections
                .into_iter()
                .map(|s| HomeSectionRecord {
                    title: s.title,
                    format: s.format.into(),
                    items: s
                        .items
                        .into_iter()
                        .map(|i| HomeItemRecord {
                            kind: i.kind.to_string(),
                            id: i.id,
                            title: i.title,
                            subtitle: i.subtitle,
                            thumbnail: i.thumbnail,
                            duration: i.duration,
                            artists: i.artists,
                            artist_id: i.artist_id,
                            album: i.album,
                            album_id: i.album_id,
                            artist_runs: i
                                .artist_runs
                                .into_iter()
                                .map(|run| HomeArtistRunRecord {
                                    text: run.text,
                                    id: run.id,
                                })
                                .collect(),
                            explicit: i.explicit,
                        })
                        .collect(),
                    more_browse_id: s.more_browse_id,
                    more_params: s.more_params,
                })
                .collect(),
            continuation: page.continuation,
        })
    }

    /// Fetch next batch of home shelves via continuation token.
    pub async fn get_home_continuation(&self, token: String) -> Result<HomePageRecord, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let page = self.it.home_continuation(client, &token).await?;
        Ok(HomePageRecord {
            chips: page
                .chips
                .into_iter()
                .map(|c| HomeChipRecord {
                    title: c.title,
                    params: c.params,
                })
                .collect(),
            sections: page
                .sections
                .into_iter()
                .map(|s| HomeSectionRecord {
                    title: s.title,
                    format: s.format.into(),
                    items: s
                        .items
                        .into_iter()
                        .map(|i| HomeItemRecord {
                            kind: i.kind.to_string(),
                            id: i.id,
                            title: i.title,
                            subtitle: i.subtitle,
                            thumbnail: i.thumbnail,
                            duration: i.duration,
                            artists: i.artists,
                            artist_id: i.artist_id,
                            album: i.album,
                            album_id: i.album_id,
                            artist_runs: i
                                .artist_runs
                                .into_iter()
                                .map(|run| HomeArtistRunRecord {
                                    text: run.text,
                                    id: run.id,
                                })
                                .collect(),
                            explicit: i.explicit,
                        })
                        .collect(),
                    more_browse_id: s.more_browse_id,
                    more_params: s.more_params,
                })
                .collect(),
            continuation: page.continuation,
        })
    }

    /// Fetch YouTube Music Home Page as typed sections.
    pub async fn get_home_sections(&self) -> Result<Vec<HomeSectionRecord>, SideBError> {
        let page = self.get_home_page(None).await?;
        Ok(page.sections)
    }

    /// Fetch YouTube Music Home Page as JSON.
    pub async fn get_home_json(&self) -> Result<String, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let page = match self.it.home(client, None).await {
            Ok(p) => p,
            Err(innertube::Error::SessionExpired) => {
                self.set_cookie(None);
                self.it.home(client, None).await?
            }
            Err(e) => return Err(e.into()),
        };
        serde_json::to_string(&page).map_err(Into::into)
    }

    /// Get up next queue / related tracks.
    pub async fn get_next(
        &self,
        video_id: Option<String>,
        playlist_id: Option<String>,
    ) -> Result<NextResultRecord, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let next = self
            .it
            .next(client, video_id.as_deref(), playlist_id.as_deref())
            .await?;
        Ok(NextResultRecord {
            items: next.items.into_iter().map(SongItemRecord::from).collect(),
            lyrics_browse_id: next.lyrics_browse_id,
            related_browse_id: next.related_browse_id,
            automix_playlist_id: next.automix_playlist_id,
            continuation: next.continuation,
        })
    }

    /// Get dynamic radio for a track.
    /// First tries the canonical YouTube Music radio RDAMVM{video_id}.
    /// If empty or only 1 item, falls back to bare /next + automix_playlist_id.
    pub async fn get_radio(&self, video_id: String) -> Result<NextResultRecord, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let radio_playlist_id = format!("RDAMVM{video_id}");
        if let Ok(first) = self
            .it
            .next(client, Some(&video_id), Some(&radio_playlist_id))
            .await
        {
            if first.items.len() > 1 {
                return Ok(NextResultRecord {
                    items: first.items.into_iter().map(SongItemRecord::from).collect(),
                    lyrics_browse_id: first.lyrics_browse_id,
                    related_browse_id: first.related_browse_id,
                    automix_playlist_id: Some(radio_playlist_id),
                    continuation: first.continuation,
                });
            }
        }
        // Fallback: bare next + automix
        let bare = self.it.next(client, Some(&video_id), None).await?;
        if let Some(mix) = bare.automix_playlist_id.as_deref() {
            if let Ok(page) = self.it.next(client, Some(&video_id), Some(mix)).await {
                if page.items.len() > 1 {
                    return Ok(NextResultRecord {
                        items: page.items.into_iter().map(SongItemRecord::from).collect(),
                        lyrics_browse_id: page.lyrics_browse_id,
                        related_browse_id: page.related_browse_id,
                        automix_playlist_id: Some(mix.to_string()),
                        continuation: page.continuation,
                    });
                }
            }
        }
        Ok(NextResultRecord {
            items: bare.items.into_iter().map(SongItemRecord::from).collect(),
            lyrics_browse_id: bare.lyrics_browse_id,
            related_browse_id: bare.related_browse_id,
            automix_playlist_id: bare.automix_playlist_id,
            continuation: bare.continuation,
        })
    }

    /// Extend a radio queue seamlessly using the last played video and the radio playlist seed.
    pub async fn get_radio_continuation(
        &self,
        last_video_id: String,
        radio_seed: Option<String>,
    ) -> Result<NextResultRecord, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let seed = radio_seed.unwrap_or_else(|| format!("RDAMVM{last_video_id}"));
        let next = self
            .it
            .next(client, Some(&last_video_id), Some(&seed))
            .await?;
        Ok(NextResultRecord {
            items: next.items.into_iter().map(SongItemRecord::from).collect(),
            lyrics_browse_id: next.lyrics_browse_id,
            related_browse_id: next.related_browse_id,
            automix_playlist_id: Some(seed),
            continuation: next.continuation,
        })
    }

    /// Fetches genuinely related songs for a track using YouTube Music's dedicated Related page (`MPTR...`).
    /// Returns the songs from the "You might also like" shelf (musically and stylistically similar songs).
    /// Falls back to dynamic radio if the related shelf is unavailable.
    pub async fn get_related_tracks(
        &self,
        video_id: String,
    ) -> Result<Vec<SongItemRecord>, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        
        // 1. Consultar /next para obtener el browseId de Related (MPTRt_...)
        if let Ok(next) = self.it.next(client, Some(&video_id), None).await {
            if let Some(browse_id) = next.related_browse_id {
                if let Ok(page) = self.it.related(client, &browse_id).await {
                    for section in page.sections {
                        let title_lower = section.title.to_lowercase();
                        if title_lower.contains("you might also like")
                            || title_lower.contains("podr")
                            || title_lower.contains("similar")
                            || title_lower.contains("parecid")
                        {
                            let songs: Vec<SongItemRecord> = section
                                .items
                                .into_iter()
                                .filter(|i| i.kind == "song" && i.id != video_id)
                                .map(|i| SongItemRecord {
                                    video_id: i.id,
                                    title: i.title,
                                    artists: i.artists.unwrap_or_else(|| i.subtitle.unwrap_or_default()),
                                    album: i.album,
                                    duration: i.duration,
                                    thumbnail: i.thumbnail,
                                    artist_id: i.artist_id.or_else(|| i.artist_runs.iter().find_map(|r| r.id.clone())),
                                    artist_runs: i.artist_runs.into_iter().map(|run| HomeArtistRunRecord { text: run.text, id: run.id }).collect(),
                                    album_id: i.album_id,
                                    set_video_id: None,
                                    is_video: i.is_video,
                                    is_upload: i.is_upload,
                                    library: None,
                                })
                                .collect();
                            if !songs.is_empty() {
                                return Ok(songs);
                            }
                        }
                    }
                }
            }
        }
        
        // Fallback a radio algorítmica
        let radio = self.get_radio(video_id.clone()).await?;
        let filtered = radio.items.into_iter().filter(|i| i.video_id != video_id).collect();
        Ok(filtered)
    }

    /// Fetches similar artists for a track using YouTube Music's dedicated Related page (`MPTR...`).
    pub async fn get_related_artists(
        &self,
        video_id: String,
    ) -> Result<Vec<BrowseCardRecord>, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        
        if let Ok(next) = self.it.next(client, Some(&video_id), None).await {
            if let Some(browse_id) = next.related_browse_id {
                if let Ok(page) = self.it.related(client, &browse_id).await {
                    for section in page.sections {
                        let title_lower = section.title.to_lowercase();
                        if title_lower.contains("similar artists")
                            || title_lower.contains("artistas similares")
                            || title_lower.contains("fans")
                        {
                            let cards: Vec<BrowseCardRecord> = section
                                .items
                                .into_iter()
                                .map(BrowseCardRecord::from)
                                .collect();
                            if !cards.is_empty() {
                                return Ok(cards);
                            }
                        }
                    }
                }
            }
        }
        Ok(vec![])
    }

    /// Search songs, returning a typed list of SongItemRecord.
    pub async fn search_songs(
        &self,
        query: String,
        record_history: bool,
    ) -> Result<Vec<SongItemRecord>, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let results = self.it.search_songs(client, &query, record_history).await?;
        Ok(results
            .items
            .into_iter()
            .map(SongItemRecord::from)
            .collect())
    }

    /// Search video uploads, returning a typed list of SongItemRecord.
    pub async fn search_videos(&self, query: String) -> Result<Vec<SongItemRecord>, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let results = self.it.search_videos(client, &query).await?;
        Ok(results.items.into_iter().map(SongItemRecord::from).collect())
    }

    /// Search songs, returning a JSON array of SongItem (legacy/compat).
    pub async fn search_songs_json(
        &self,
        query: String,
        record_history: bool,
    ) -> Result<String, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let results = self.it.search_songs(client, &query, record_history).await?;
        serde_json::to_string(&results.items).map_err(Into::into)
    }

    /// Full search across songs, albums, artists, playlists (typed).
    pub async fn search_all(
        &self,
        query: String,
        record_history: bool,
    ) -> Result<SearchResultsRecord, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let results = self.it.search_all(client, &query, record_history).await?;
        Ok(SearchResultsRecord {
            top_songs: search_top_songs(&results.top),
            top: results
                .top
                .into_iter()
                .map(BrowseCardRecord::from)
                .collect(),
            songs: results
                .songs
                .into_iter()
                .map(SongItemRecord::from)
                .collect(),
            albums: results
                .albums
                .into_iter()
                .map(BrowseCardRecord::from)
                .collect(),
            artists: results
                .artists
                .into_iter()
                .map(BrowseCardRecord::from)
                .collect(),
            playlists: results
                .playlists
                .into_iter()
                .map(BrowseCardRecord::from)
                .collect(),
        })
    }

    /// Search cards filtered by category ("albums", "artists", "playlists").
    pub async fn search_cards(
        &self,
        query: String,
        category: String,
    ) -> Result<Vec<BrowseCardRecord>, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let items = self.it.search_cards(client, &query, &category).await?;
        Ok(items.into_iter().map(BrowseCardRecord::from).collect())
    }

    /// Full search across songs, albums, artists, playlists (legacy JSON).
    pub async fn search_all_json(
        &self,
        query: String,
        record_history: bool,
    ) -> Result<String, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let results = self.it.search_all(client, &query, record_history).await?;
        serde_json::to_string(&results).map_err(Into::into)
    }

    /// Album page by browse ID.
    pub async fn get_album_json(&self, browse_id: String) -> Result<String, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let page = self.it.album(client, &browse_id).await?;
        serde_json::to_string(&page).map_err(Into::into)
    }

    /// Artist page by browse ID.
    pub async fn get_artist_json(&self, browse_id: String) -> Result<String, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let page = self.it.artist(client, &browse_id).await?;
        serde_json::to_string(&page).map_err(Into::into)
    }

    /// Playlist page by browse ID.
    pub async fn get_playlist_json(&self, browse_id: String) -> Result<String, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let page = self.it.playlist(client, &browse_id, None).await?;
        serde_json::to_string(&page).map_err(Into::into)
    }

    /// Continue fetching playlist items.
    pub async fn get_playlist_continuation_json(
        &self,
        token: String,
    ) -> Result<String, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let continuation = self.it.playlist_continuation(client, &token).await?;
        serde_json::to_string(&continuation).map_err(Into::into)
    }

    /// History page.
    pub async fn get_history_json(&self) -> Result<String, SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let history = self.it.history(client).await?;
        serde_json::to_string(&history).map_err(Into::into)
    }

    /// Rate song (LIKE, DISLIKE, INDIFFERENT).
    pub async fn rate_song(&self, video_id: String, rating: String) -> Result<(), SideBError> {
        let client = self
            .clients
            .get(METADATA_CLIENT)
            .ok_or_else(|| SideBError::Other {
                message: "Metadata client missing".into(),
            })?;
        let r = match rating.to_uppercase().as_str() {
            "LIKE" => innertube::Rating::Like,
            "DISLIKE" => innertube::Rating::Dislike,
            _ => innertube::Rating::Indifferent,
        };
        self.it.rate(client, &video_id, r).await?;

        // Keep local SQLite playlist_track cache in sync for Liked Music (LM / VLLM)
        match r {
            innertube::Rating::Like => {
                self.db.add_playlist_track("VLLM", &video_id);
                self.db.add_playlist_track("LM", &video_id);
            }
            innertube::Rating::Dislike | innertube::Rating::Indifferent => {
                self.db.remove_playlist_track("VLLM", &video_id);
                self.db.remove_playlist_track("LM", &video_id);
            }
        }

        Ok(())
    }

    /// Register a completed or threshold-crossing playback in watch history and local SQLite.
    pub async fn record_playback(
        &self,
        video_id: String,
        song_json: Option<String>,
        playlist_id: Option<String>,
    ) -> Result<(), SideBError> {
        // 1. Local play history (On Repeat and top plays statistics)
        if let Some(ref json) = song_json {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0);
            const ON_REPEAT_WINDOW_SECS: i64 = 30 * 86400; // 30 days
            self.db
                .record_play(&video_id, json, now, ON_REPEAT_WINDOW_SECS);
        }

        // 2. YouTube Music remote watch-history ping if authenticated
        if self.is_logged_in() {
            let tracking_opt = {
                let tracking = self.current_playback.lock().await;
                tracking.clone()
            };

            if let Some(tracking) = tracking_opt {
                if tracking.video_id == video_id {
                    let client = self
                        .clients
                        .get(&tracking.ping.client)
                        .cloned()
                        .unwrap_or_else(|| self.clients.get(METADATA_CLIENT).cloned().unwrap());
                    let _ = self
                        .it
                        .register_playback(
                            &client,
                            &tracking.ping.url,
                            &tracking.cpn,
                            playlist_id.as_deref(),
                        )
                        .await;
                }
            }
        }

        Ok(())
    }

    /// Resolve a video ID to a validated, high-quality audio stream URL for native AVPlayer.
    pub async fn resolve_stream(
        &self,
        video_id: String,
        is_upload: bool,
    ) -> Result<StreamPlaybackInfo, SideBError> {
        let disabled = HashSet::new();
        let playback = self
            .orchestrator
            .resolve(&video_id, is_upload, AudioQuality::High, &disabled)
            .await?;

        // Cache the watch-history tracking info for record_playback
        if let Some(ref ping) = playback.playback_ping {
            let cpn = innertube::generate_cpn();
            let mut tracking = self.current_playback.lock().await;
            *tracking = Some(CorePlaybackTracking {
                video_id: playback.video_id.clone(),
                ping: ping.clone(),
                cpn,
            });
        }

        // Ensure visitor_data is persisted if newly fetched
        if let Some(vd) = self.it.visitor_data() {
            if self.db.get_setting("visitor_data").as_deref() != Some(&vd) {
                let _ = self.db.set_setting("visitor_data", &vd);
            }
        }

        Ok(StreamPlaybackInfo {
            video_id: playback.video_id,
            stream_url: playback.stream_url,
            itag: playback.itag,
            loudness_db: playback.loudness_db,
            expires_in_seconds: playback.expires_in_seconds,
            is_video: playback.is_video.unwrap_or(false),
            stream_client: playback.stream_client,
            title: playback.title,
            artists: playback.artists,
            duration: playback.duration,
            thumbnail: playback.thumbnail,
            headers: playback.headers,
        })
    }

    /// Fetch synced or plain lyrics (LRCLIB, YouTube timed, etc.).
    pub async fn get_lyrics(
        &self,
        video_id: String,
        title: String,
        artist: String,
        album: Option<String>,
        duration_secs: Option<u64>,
    ) -> Result<Option<LyricsInfo>, SideBError> {
        let ctx = lyrics::LyricsContext {
            db: &self.db,
            it: &self.it,
            clients: &self.clients,
        };
        let req = lyrics::LyricsRequest {
            video_id,
            title,
            artists: artist,
            album,
            duration: duration_secs.map(|d| d as f64),
        };
        let res = lyrics::get_lyrics(&ctx, req).await;
        Ok(res.map(|l| LyricsInfo {
            provider: l.source,
            is_synced: l.synced,
            lines: l
                .lines
                .into_iter()
                .map(|line| LyricLineInfo {
                    time_ms: line.time_ms,
                    end_time_ms: line.end_time_ms,
                    text: line.text,
                })
                .collect(),
        }))
    }

    /// Read-only cache probe used before the delayed background network lookup.
    pub async fn get_genius_cached(
        &self,
        track: GeniusTrackRecord,
    ) -> Option<GeniusResolutionRecord> {
        self.genius.cached(&track)
    }

    pub async fn resolve_genius(
        &self,
        track: GeniusTrackRecord,
        force: bool,
    ) -> Result<GeniusResolutionRecord, SideBError> {
        self.genius.resolve(track, force).await
    }

    pub async fn search_genius(
        &self,
        query: String,
    ) -> Result<Vec<GeniusCandidateRecord>, SideBError> {
        self.genius.search_manual(query).await
    }

    pub async fn choose_genius(
        &self,
        track: GeniusTrackRecord,
        song_id: i64,
    ) -> Result<GeniusResolutionRecord, SideBError> {
        self.genius.choose(track, song_id).await
    }

    pub fn clear_genius_choice(&self, track: GeniusTrackRecord) {
        self.genius.clear_choice(&track);
    }

    pub fn report_genius_miss(
        &self,
        track: GeniusTrackRecord,
        status: GeniusMatchStatusRecord,
        candidate_ids: Vec<i64>,
    ) -> Result<(), SideBError> {
        self.genius.report_miss(&track, status, candidate_ids)
    }

    pub async fn get_genius_annotations(
        &self,
        song_id: i64,
        page: u32,
        force: bool,
    ) -> Result<GeniusAnnotationsRecord, SideBError> {
        self.genius.annotations(song_id, page, force).await
    }

    pub async fn get_genius_cached_annotations(
        &self,
        song_id: i64,
        page: u32,
    ) -> Option<GeniusAnnotationsRecord> {
        self.genius.cached_annotations(song_id, page)
    }

    pub async fn get_genius_lyrics(
        &self,
        song_id: i64,
        song_url: String,
        force: bool,
    ) -> Result<GeniusLyricsRecord, SideBError> {
        self.genius.lyrics(song_id, song_url, force).await
    }

    pub async fn get_genius_cached_lyrics(&self, song_id: i64) -> Option<GeniusLyricsRecord> {
        self.genius.cached_lyrics(song_id)
    }

    pub fn get_genius_metrics(&self) -> GeniusMetricsRecord {
        self.genius.metrics()
    }

    /// Read or write settings in local SQLite database.
    pub fn get_setting(&self, key: String) -> Option<String> {
        self.db.get_setting(&key)
    }

    pub fn set_setting(&self, key: String, value: String) {
        self.db.set_setting(&key, &value);
    }

    /// Pin an item in SQLite for quick access.
    pub fn pin_item(
        &self,
        id: String,
        kind: String,
        title: String,
        subtitle: Option<String>,
        thumbnail: Option<String>,
    ) -> Result<(), SideBError> {
        self.db
            .pin_item(
                &id,
                &kind,
                &title,
                subtitle.as_deref(),
                thumbnail.as_deref(),
            )
            .map_err(|e| SideBError::DbError {
                message: e.to_string(),
            })
    }

    /// Unpin an item from SQLite.
    pub fn unpin_item(&self, id: String) -> Result<(), SideBError> {
        self.db.unpin_item(&id).map_err(|e| SideBError::DbError {
            message: e.to_string(),
        })
    }

    /// Check if an item is pinned in SQLite.
    pub fn is_pinned(&self, id: String) -> bool {
        self.db.is_pinned(&id)
    }

    /// Get all pinned items.
    pub fn get_pinned_items(&self) -> Vec<BrowseCardRecord> {
        self.db
            .get_pinned_items()
            .into_iter()
            .map(|p| BrowseCardRecord {
                kind: p.kind,
                id: p.id,
                title: p.title,
                subtitle: p.subtitle,
                thumbnail: p.thumbnail,
                duration: None,
                #[cfg(feature = "windows-bridge")]
                artists: None,
                #[cfg(feature = "windows-bridge")]
                artist_id: None,
                #[cfg(feature = "windows-bridge")]
                album: None,
                #[cfg(feature = "windows-bridge")]
                album_id: None,
                #[cfg(feature = "windows-bridge")]
                is_video: false,
                #[cfg(feature = "windows-bridge")]
                explicit: false,
                #[cfg(feature = "windows-bridge")]
                artist_runs: Vec::new(),
            })
            .collect()
    }
}

fn parse_song_record(json: &str) -> Option<SongItemRecord> {
    if let Ok(item) = serde_json::from_str::<innertube::SongItem>(json) {
        return Some(SongItemRecord::from(item));
    }
    let val: serde_json::Value = serde_json::from_str(json).ok()?;
    let video_id = val.get("video_id")?.as_str()?.to_string();
    let title = val
        .get("title")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    let artists = val
        .get("artists")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    let artist_id = val
        .get("artist_id")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(String::from);
    let album = val
        .get("album")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(String::from);
    let album_id = val
        .get("album_id")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(String::from);
    let duration = val
        .get("duration")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(String::from);
    let thumbnail = val
        .get("thumbnail")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(String::from);
    let set_video_id = val
        .get("set_video_id")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(String::from);
    Some(SongItemRecord {
        video_id,
        title,
        artists,
        artist_id,
        artist_runs: Vec::new(),
        album,
        album_id,
        duration,
        thumbnail,
        set_video_id,
        is_video: false,
        is_upload: false,
        library: None,
    })
}

fn civil_date(epoch_secs: i64) -> (i64, u32, u32) {
    let days = epoch_secs / 86400;
    let z = days + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as u32;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

fn format_epoch_day(played_at: i64, now: i64) -> String {
    let day_diff = (now / 86400) - (played_at / 86400);
    if day_diff == 0 {
        "Hoy".to_string()
    } else if day_diff == 1 {
        "Ayer".to_string()
    } else if day_diff < 7 {
        let dow = ((played_at / 86400) + 4) % 7;
        let days = ["Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"];
        days[dow.rem_euclid(7) as usize].to_string()
    } else {
        let (_y, m, d) = civil_date(played_at);
        let months = [
            "enero", "febrero", "marzo", "abril", "mayo", "junio",
            "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
        ];
        let m_idx = (m.saturating_sub(1) as usize).min(11);
        format!("{d} de {}", months[m_idx])
    }
}

impl SideBCore {
    /// Construct the Windows core with session credentials managed by the host's OS vault.
    /// This path neither restores a cookie from SQLite nor persists cookies passed to `set_cookie`.
    /// It is intentionally outside the UniFFI export; Apple keeps using `new`.
    pub fn new_windows(data_dir: String) -> Result<Arc<Self>, SideBError> {
        Self::build(data_dir, false)
    }

    /// Install or remove a session cookie in memory only.
    ///
    /// The caller is responsible for securely storing the credential and observing rotations.
    pub fn set_cookie_memory(&self, cookie: Option<String>) {
        self.it.set_cookie(cookie);
    }

    /// Validate the active session against YouTube and return only public account metadata.
    pub async fn validate_session(&self) -> Result<AccountInfoRecord, SideBError> {
        if !self.is_logged_in() {
            return Err(SideBError::NetworkError {
                message: "No authenticated session is installed".into(),
            });
        }
        self.get_account_info().await
    }

    /// Wait for an InnerTube response to rotate the cookie jar, then return the current jar to
    /// the trusted Rust host adapter so it can update its OS credential store. Never expose this
    /// method through Tauri commands or frontend events.
    pub async fn wait_for_cookie_rotation(&self) -> Option<String> {
        let changed = self.it.cookie_changed();
        changed.notified().await;
        self.it.cookie()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn browse_item(kind: &'static str, id: &str, title: &str) -> innertube::BrowseItem {
        innertube::BrowseItem {
            kind,
            id: id.into(),
            title: title.into(),
            subtitle: Some("Fallback artist line".into()),
            thumbnail: Some("https://example.test/thumb.jpg".into()),
            duration: Some("3:21".into()),
            artist_runs: vec![innertube::ArtistRun {
                text: "Linked Artist".into(),
                id: Some("UC-linked".into()),
            }],
            play_count: None,
            is_video: true,
            is_upload: true,
            explicit: false,
            artists: Some("Structured Artist".into()),
            artist_id: Some("UC-explicit".into()),
            album: Some("Structured Album".into()),
            album_id: Some("MPRE-album".into()),
        }
    }

    #[test]
    fn browse_song_record_keeps_structured_search_metadata() {
        let record = SongItemRecord::from(browse_item("song", "video-1", "Search song"));
        assert_eq!(record.video_id, "video-1");
        assert_eq!(record.artists, "Structured Artist");
        assert_eq!(record.artist_id.as_deref(), Some("UC-explicit"));
        assert_eq!(record.artist_runs[0].id.as_deref(), Some("UC-linked"));
        assert_eq!(record.album.as_deref(), Some("Structured Album"));
        assert_eq!(record.album_id.as_deref(), Some("MPRE-album"));
        assert_eq!(record.duration.as_deref(), Some("3:21"));
        assert_eq!(record.thumbnail.as_deref(), Some("https://example.test/thumb.jpg"));
        assert!(record.is_video);
        assert!(record.is_upload);
    }

    #[test]
    fn top_search_songs_include_song_hero_and_preserve_provider_order() {
        let items = vec![
            browse_item("song", "hero-song", "Hero song"),
            browse_item("album", "album", "Album"),
            browse_item("song", "second-song", "Second song"),
        ];
        let songs = search_top_songs(&items);
        assert_eq!(
            songs.iter().map(|song| song.video_id.as_str()).collect::<Vec<_>>(),
            ["hero-song", "second-song"]
        );
    }

    #[test]
    fn browse_song_uses_subtitle_and_artist_run_id_as_fallbacks() {
        let mut item = browse_item("song", "video-2", "Search song");
        item.artists = None;
        item.artist_id = None;
        let record = SongItemRecord::from(item);
        assert_eq!(record.artists, "Fallback artist line");
        assert_eq!(record.artist_id.as_deref(), Some("UC-linked"));
    }

    #[test]
    fn song_record_preserves_each_artist_destination() {
        let item: innertube::SongItem = serde_json::from_str(r#"{
            "video_id":"collab", "title":"Song", "artists":"Future & Metro Boomin",
            "artist_id":"UCfuture", "artist_runs":[
                {"text":"Future", "id":"UCfuture"},
                {"text":" & "},
                {"text":"Metro Boomin", "id":"UCmetro"}
            ]
        }"#).unwrap();
        let record = SongItemRecord::from(item);
        assert_eq!(record.artist_runs.len(), 3);
        assert_eq!(record.artist_runs[0].id.as_deref(), Some("UCfuture"));
        assert_eq!(record.artist_runs[1].text, " & ");
        assert!(record.artist_runs[1].id.is_none());
        assert_eq!(record.artist_runs[2].id.as_deref(), Some("UCmetro"));
    }

    #[test]
    fn civil_date_calculation() {
        assert_eq!(civil_date(0), (1970, 1, 1));
        // 2026-09-26 approx 1790441653
        assert_eq!(civil_date(1790441653), (2026, 9, 26));
    }

    #[test]
    fn format_epoch_day_relative() {
        let now = 1790441653; // 2026-09-26 (Saturday)
        assert_eq!(format_epoch_day(now, now), "Hoy");
        assert_eq!(format_epoch_day(now - 86400, now), "Ayer");
        assert_eq!(format_epoch_day(now - 2 * 86400, now), "Jueves");
    }

    #[cfg(feature = "windows-bridge")]
    #[test]
    fn windows_song_record_keeps_album_and_linked_artist_runs() {
        let item = innertube::SongItem {
            video_id: "song-1".into(),
            title: "Track".into(),
            artists: "Artist A & Artist B".into(),
            album: Some("Release".into()),
            album_id: Some("MPRErelease".into()),
            artist_runs: vec![
                innertube::ArtistRun {
                    text: "Artist A".into(),
                    id: Some("UCa".into()),
                },
                innertube::ArtistRun {
                    text: "Artist B".into(),
                    id: Some("UCb".into()),
                },
            ],
            ..Default::default()
        };
        let record = SongItemRecord::from(item);
        assert_eq!(record.album.as_deref(), Some("Release"));
        assert_eq!(record.album_id.as_deref(), Some("MPRErelease"));
        assert_eq!(record.artist_runs.len(), 2);
        assert_eq!(record.artist_runs[1].text, "Artist B");
        assert_eq!(record.artist_runs[1].id.as_deref(), Some("UCb"));
    }

    #[cfg(feature = "windows-bridge")]
    #[test]
    fn windows_browse_card_keeps_linked_artist_and_album_metadata() {
        let card = innertube::BrowseItem {
            kind: "song",
            id: "song-2".into(),
            title: "Track".into(),
            subtitle: Some("Artist ? Album".into()),
            thumbnail: None,
            duration: None,
            artist_runs: vec![innertube::ArtistRun {
                text: "Artist".into(),
                id: Some("UCartist".into()),
            }],
            play_count: None,
            is_video: true,
            is_upload: false,
            explicit: true,
            artists: Some("Artist".into()),
            artist_id: Some("UCartist".into()),
            album: Some("Album".into()),
            album_id: Some("MPREalbum".into()),
        };
        let record = BrowseCardRecord::from(card);
        assert_eq!(record.album.as_deref(), Some("Album"));
        assert_eq!(record.album_id.as_deref(), Some("MPREalbum"));
        assert!(record.is_video);
        assert!(record.explicit);
        assert_eq!(record.artist_runs.len(), 1);
        assert_eq!(record.artist_runs[0].id.as_deref(), Some("UCartist"));
    }

    #[test]
    fn external_session_constructor_does_not_restore_or_persist_cookie() {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let data_dir = std::env::temp_dir().join(format!(
            "sideb-core-external-session-{}-{unique}",
            std::process::id()
        ));
        std::fs::create_dir_all(&data_dir).unwrap();
        let db_path = data_dir.join("sideb.db");
        let db = db::Db::open(&db_path).unwrap();
        db.set_setting("session_cookie", "SAPISID=legacy-fixture-cookie");
        drop(db);

        let core = SideBCore::new_windows(data_dir.to_string_lossy().into_owned()).unwrap();
        assert!(!core.is_logged_in());
        assert_eq!(core.get_cookie(), None);
        assert_eq!(core.db.get_setting("session_cookie"), None);

        core.set_cookie_memory(Some("SAPISID=memory-fixture-cookie".into()));
        assert!(core.is_logged_in());
        assert_eq!(core.db.get_setting("session_cookie"), None);

        core.set_cookie_memory(None);
        assert!(!core.is_logged_in());
        assert_eq!(core.db.get_setting("session_cookie"), None);
        assert!(core
            .db
            .list_accounts()
            .iter()
            .all(|account| account.session_cookie.is_empty()));
        drop(core);
        let _ = std::fs::remove_dir_all(data_dir);
    }

    #[test]
    fn legacy_constructor_still_persists_cookie_for_apple() {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let data_dir = std::env::temp_dir().join(format!(
            "sideb-core-legacy-session-{}-{unique}",
            std::process::id()
        ));
        let core = SideBCore::new(data_dir.to_string_lossy().into_owned()).unwrap();

        core.set_cookie(Some("SAPISID=apple-fixture-cookie".into()));
        assert_eq!(
            core.db.get_setting("session_cookie").as_deref(),
            Some("SAPISID=apple-fixture-cookie")
        );
        drop(core);
        let _ = std::fs::remove_dir_all(data_dir);
    }
}
