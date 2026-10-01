use crate::queue::QueueStateDto;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthStatusDto {
    pub state: String,
    pub name: Option<String>,
    pub email: Option<String>,
    pub thumbnail: Option<String>,
    pub message: Option<String>,
}

impl AuthStatusDto {
    pub(crate) fn guest() -> Self {
        Self {
            state: "guest".into(),
            name: None,
            email: None,
            thumbnail: None,
            message: None,
        }
    }
    pub(crate) fn authorizing() -> Self {
        Self {
            state: "authorizing".into(),
            ..Self::guest()
        }
    }
    pub(crate) fn ready(info: sideb_core::AccountInfoRecord) -> Self {
        Self {
            state: "ready".into(),
            name: info.name,
            email: info.email,
            thumbnail: info.thumbnail,
            message: None,
        }
    }
    pub(crate) fn error(message: &str) -> Self {
        Self {
            state: "error".into(),
            message: Some(message.into()),
            ..Self::guest()
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaybackTrackDto {
    pub video_id: String,
    pub title: String,
    pub artists: String,
    pub thumbnail: Option<String>,
    pub duration: Option<f64>,
    #[serde(default)]
    pub artist_id: Option<String>,
    #[serde(default)]
    pub album_id: Option<String>,
    #[serde(default)]
    pub album: Option<String>,
    #[serde(default)]
    pub artist_runs: Vec<HomeArtistRunDto>,
}

impl PlaybackTrackDto {
    pub(crate) fn enrich_missing_metadata(&mut self, entry: &crate::queue::QueueEntryDto) {
        if self.video_id != entry.video_id {
            return;
        }
        if self.artists.trim().is_empty() && !entry.artists.trim().is_empty() {
            self.artists = entry.artists.clone();
        }
        if self.artist_id.is_none() {
            self.artist_id = entry.artist_id.clone();
        }
        if self.album_id.is_none() {
            self.album_id = entry.album_id.clone();
        }
        if self.album.is_none() {
            self.album = entry.album.clone();
        }
        if self.artist_runs.is_empty() {
            self.artist_runs = entry.artist_runs.clone();
        }
    }
}

#[cfg(test)]
mod playback_track_tests {
    use super::{HomeArtistRunDto, PlaybackTrackDto};
    use crate::queue::QueueEntryDto;

    #[test]
    fn radio_metadata_enrichment_preserves_audio_identity_and_existing_credits() {
        let mut track = PlaybackTrackDto {
            video_id: "seed-video".into(),
            title: "Seed title".into(),
            artists: "Seed artist".into(),
            thumbnail: None,
            duration: Some(123.0),
            artist_id: None,
            album_id: None,
            album: None,
            artist_runs: Vec::new(),
        };
        let entry = QueueEntryDto::with_metadata_and_runs(
            "seed-video".into(),
            "Recommendation title".into(),
            "Recommendation artist".into(),
            Some("thumb".into()),
            Some(456.0),
            Some("UC-artist".into()),
            Some("MPRE-album".into()),
            Some("Album".into()),
            vec![HomeArtistRunDto {
                text: "Artist".into(),
                id: Some("UC-artist".into()),
            }],
        );

        track.enrich_missing_metadata(&entry);

        assert_eq!(track.video_id, "seed-video");
        assert_eq!(track.title, "Seed title");
        assert_eq!(track.duration, Some(123.0));
        assert_eq!(track.artists, "Seed artist");
        assert_eq!(track.album.as_deref(), Some("Album"));
        assert_eq!(track.album_id.as_deref(), Some("MPRE-album"));
        assert_eq!(track.artist_id.as_deref(), Some("UC-artist"));
        assert_eq!(track.artist_runs.len(), 1);
    }

    #[test]
    fn radio_metadata_enrichment_ignores_a_different_current_song() {
        let mut track = PlaybackTrackDto {
            video_id: "currently-playing".into(),
            title: "Title".into(),
            artists: "Artist".into(),
            thumbnail: None,
            duration: None,
            artist_id: None,
            album_id: None,
            album: None,
            artist_runs: Vec::new(),
        };
        let entry = QueueEntryDto::with_metadata_and_runs(
            "radio-seed".into(),
            "Other".into(),
            "Other".into(),
            None,
            None,
            None,
            None,
            Some("Should not copy".into()),
            Vec::new(),
        );

        track.enrich_missing_metadata(&entry);

        assert_eq!(track.album, None);
        assert!(track.artist_runs.is_empty());
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaybackStateDto {
    pub is_playing: bool,
    pub is_loading: bool,
    pub is_ended: bool,
    #[serde(default)]
    pub is_shuffle: bool,
    #[serde(default)]
    pub is_repeat: bool,
    pub position: f64,
    pub duration: f64,
    pub volume: f64,
    pub current_track: Option<PlaybackTrackDto>,
    pub error: Option<String>,
    pub generation: u64,
    pub queue: QueueStateDto,
}

#[cfg(test)]
mod playback_state_tests {
    use super::*;

    #[test]
    fn older_playback_snapshots_default_shuffle_and_repeat_to_false() {
        let dto: PlaybackStateDto = serde_json::from_str(
            r#"{"isPlaying":false,"isLoading":false,"isEnded":false,"position":0.0,"duration":0.0,"volume":100.0,"currentTrack":null,"error":null,"generation":0,"queue":{"items":[],"currentIndex":null,"source":null,"revision":0}}"#,
        ).unwrap();
        assert!(!dto.is_shuffle);
        assert!(!dto.is_repeat);
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaybackProgressDto {
    pub position: f64,
    pub duration: f64,
    pub generation: u64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SongDto {
    pub video_id: String,
    pub title: String,
    pub artists: String,
    pub album: Option<String>,
    pub duration: Option<String>,
    pub thumbnail: Option<String>,
    pub is_video: bool,
    pub artist_id: Option<String>,
    pub album_id: Option<String>,
    pub set_video_id: Option<String>,
    pub library: Option<LibraryToggleDto>,
    #[serde(default)]
    pub artist_runs: Vec<HomeArtistRunDto>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryToggleDto {
    pub in_library: bool,
    pub add_token: Option<String>,
    pub remove_token: Option<String>,
}

impl From<sideb_core::SongItemRecord> for SongDto {
    fn from(r: sideb_core::SongItemRecord) -> Self {
        Self {
            video_id: r.video_id,
            title: r.title,
            artists: r.artists,
            album: r.album,
            duration: r.duration,
            thumbnail: r.thumbnail,
            is_video: r.is_video,
            artist_id: r.artist_id,
            album_id: r.album_id,
            set_video_id: r.set_video_id,
            library: r.library.map(|v| LibraryToggleDto {
                in_library: v.in_library,
                add_token: v.add_token,
                remove_token: v.remove_token,
            }),
            artist_runs: r
                .artist_runs
                .into_iter()
                .map(HomeArtistRunDto::from)
                .collect(),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AlbumCardDto {
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub thumbnail: Option<String>,
}

impl From<sideb_core::BrowseCardRecord> for AlbumCardDto {
    fn from(r: sideb_core::BrowseCardRecord) -> Self {
        Self {
            id: r.id,
            title: r.title,
            subtitle: r.subtitle,
            thumbnail: r.thumbnail,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AlbumDetailDto {
    pub browse_id: String,
    pub title: String,
    pub artist: Option<String>,
    pub subtitle: Option<String>,
    pub second_subtitle: Option<String>,
    pub description: Option<String>,
    pub thumbnail: Option<String>,
    pub items: Vec<SongDto>,
    pub artist_id: Option<String>,
    pub playlist_id: Option<String>,
    pub in_library: bool,
    pub sections: Vec<ArtistCarouselDto>,
    #[serde(default)]
    pub artist_runs: Vec<HomeArtistRunDto>,
}

impl From<sideb_core::AlbumDetailRecord> for AlbumDetailDto {
    fn from(r: sideb_core::AlbumDetailRecord) -> Self {
        Self {
            browse_id: r.browse_id,
            title: r.title,
            artist: r.artist,
            subtitle: r.subtitle,
            second_subtitle: r.second_subtitle,
            description: r.description,
            thumbnail: r.thumbnail,
            items: r.items.into_iter().map(SongDto::from).collect(),
            artist_id: r.artist_id,
            playlist_id: r.playlist_id,
            in_library: r.in_library,
            sections: r
                .sections
                .into_iter()
                .map(ArtistCarouselDto::from)
                .collect(),
            artist_runs: r
                .artist_runs
                .into_iter()
                .map(HomeArtistRunDto::from)
                .collect(),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HomeChipDto {
    pub title: String,
    pub params: String,
}

impl From<sideb_core::HomeChipRecord> for HomeChipDto {
    fn from(c: sideb_core::HomeChipRecord) -> Self {
        Self {
            title: c.title,
            params: c.params,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HomeItemDto {
    pub kind: String,
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub thumbnail: Option<String>,
    pub duration: Option<String>,
    pub artists: Option<String>,
    pub album_id: Option<String>,
    pub artist_id: Option<String>,
    pub album: Option<String>,
    pub artist_runs: Vec<HomeArtistRunDto>,
    pub explicit: bool,
}

impl From<sideb_core::HomeItemRecord> for HomeItemDto {
    fn from(i: sideb_core::HomeItemRecord) -> Self {
        Self {
            kind: i.kind,
            id: i.id,
            title: i.title,
            subtitle: i.subtitle,
            thumbnail: i.thumbnail,
            duration: i.duration,
            artists: i.artists,
            album_id: i.album_id,
            artist_id: i.artist_id,
            album: i.album,
            artist_runs: i
                .artist_runs
                .into_iter()
                .map(HomeArtistRunDto::from)
                .collect(),
            explicit: i.explicit,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HomeSectionDto {
    pub title: String,
    pub format: String,
    pub items: Vec<HomeItemDto>,
    pub more_browse_id: Option<String>,
    pub more_params: Option<String>,
}

impl From<sideb_core::HomeSectionRecord> for HomeSectionDto {
    fn from(s: sideb_core::HomeSectionRecord) -> Self {
        let format_str = match s.format {
            sideb_core::HomeSectionFormatRecord::LargeCards => "largeCards",
            sideb_core::HomeSectionFormatRecord::CompactSongs => "compactSongs",
            sideb_core::HomeSectionFormatRecord::Mixed => "mixed",
        };
        Self {
            title: s.title,
            format: format_str.to_string(),
            items: s.items.into_iter().map(HomeItemDto::from).collect(),
            more_browse_id: s.more_browse_id,
            more_params: s.more_params,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HomePageDto {
    pub chips: Vec<HomeChipDto>,
    pub sections: Vec<HomeSectionDto>,
    pub continuation: Option<String>,
}

impl From<sideb_core::HomePageRecord> for HomePageDto {
    fn from(p: sideb_core::HomePageRecord) -> Self {
        Self {
            chips: p.chips.into_iter().map(HomeChipDto::from).collect(),
            sections: p.sections.into_iter().map(HomeSectionDto::from).collect(),
            continuation: p.continuation,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HomeArtistRunDto {
    pub text: String,
    pub id: Option<String>,
}
impl From<sideb_core::HomeArtistRunRecord> for HomeArtistRunDto {
    fn from(r: sideb_core::HomeArtistRunRecord) -> Self {
        Self {
            text: r.text,
            id: r.id,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BrowseCardDto {
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
    #[serde(default)]
    pub artist_runs: Vec<HomeArtistRunDto>,
}
impl From<sideb_core::BrowseCardRecord> for BrowseCardDto {
    fn from(r: sideb_core::BrowseCardRecord) -> Self {
        Self {
            kind: r.kind,
            id: r.id,
            title: r.title,
            subtitle: r.subtitle,
            thumbnail: r.thumbnail,
            duration: r.duration,
            artists: r.artists,
            artist_id: r.artist_id,
            album: r.album,
            album_id: r.album_id,
            artist_runs: r
                .artist_runs
                .into_iter()
                .map(HomeArtistRunDto::from)
                .collect(),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ArtistCarouselDto {
    pub title: String,
    pub items: Vec<BrowseCardDto>,
    pub more_browse_id: Option<String>,
    pub more_params: Option<String>,
}
impl From<sideb_core::ArtistCarouselRecord> for ArtistCarouselDto {
    fn from(r: sideb_core::ArtistCarouselRecord) -> Self {
        Self {
            title: r.title,
            items: r.items.into_iter().map(BrowseCardDto::from).collect(),
            more_browse_id: r.more_browse_id,
            more_params: r.more_params,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ArtistDetailDto {
    pub channel_id: String,
    pub name: String,
    pub thumbnail: Option<String>,
    pub description: Option<String>,
    pub subscribers: Option<String>,
    pub monthly_listeners: Option<String>,
    pub subscribed: bool,
    pub radio_playlist_id: Option<String>,
    pub top_songs: Vec<SongDto>,
    pub top_songs_id: Option<String>,
    pub sections: Vec<ArtistCarouselDto>,
}
impl From<sideb_core::ArtistDetailRecord> for ArtistDetailDto {
    fn from(r: sideb_core::ArtistDetailRecord) -> Self {
        Self {
            channel_id: r.channel_id,
            name: r.name,
            thumbnail: r.thumbnail,
            description: r.description,
            subscribers: r.subscribers,
            monthly_listeners: r.monthly_listeners,
            subscribed: r.subscribed,
            radio_playlist_id: r.radio_playlist_id,
            top_songs: r.top_songs.into_iter().map(SongDto::from).collect(),
            top_songs_id: r.top_songs_id,
            sections: r
                .sections
                .into_iter()
                .map(ArtistCarouselDto::from)
                .collect(),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaylistDetailDto {
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub thumbnail: Option<String>,
    pub description: Option<String>,
    pub items: Vec<SongDto>,
    pub continuation: Option<String>,
    pub owned: bool,
    pub in_library: bool,
    pub privacy: Option<String>,
    pub collaborative: bool,
    pub sort: Option<String>,
    pub sort_editable: bool,
}
impl From<sideb_core::PlaylistDetailRecord> for PlaylistDetailDto {
    fn from(r: sideb_core::PlaylistDetailRecord) -> Self {
        Self {
            id: r.id,
            title: r.title,
            subtitle: r.subtitle,
            thumbnail: r.thumbnail,
            description: r.description,
            items: r.items.into_iter().map(SongDto::from).collect(),
            continuation: r.continuation,
            owned: r.owned,
            in_library: r.in_library,
            privacy: r.privacy,
            collaborative: r.collaborative,
            sort: r.sort,
            sort_editable: r.sort_editable,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryGroupDto {
    pub title: String,
    pub items: Vec<SongDto>,
}
impl From<sideb_core::HistoryGroupRecord> for HistoryGroupDto {
    fn from(r: sideb_core::HistoryGroupRecord) -> Self {
        Self {
            title: r.title,
            items: r.items.into_iter().map(SongDto::from).collect(),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackendStatusDto {
    pub ready: bool,
    pub status: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandError {
    pub code: String,
    pub message: String,
}

impl CommandError {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaylistContinuationDto {
    pub items: Vec<SongDto>,
    pub continuation: Option<String>,
}
impl From<sideb_core::PlaylistContinuationRecord> for PlaylistContinuationDto {
    fn from(r: sideb_core::PlaylistContinuationRecord) -> Self {
        Self {
            items: r.items.into_iter().map(SongDto::from).collect(),
            continuation: r.continuation,
        }
    }
}
