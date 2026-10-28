use crate::{SearchTopCardDto, SongDto};
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SearchPageDto {
    pub chips: Vec<SearchChipDto>,
    pub correction: Option<SearchPageCorrectionDto>,
    pub sections: Vec<SearchSectionDto>,
    pub continuation: Option<String>,
}
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SearchChipDto {
    pub id: String,
    pub title: String,
    pub params: Option<String>,
    pub selected: bool,
}
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SearchPageCorrectionDto {
    pub query: String,
    pub applied: bool,
    pub params: Option<String>,
    pub original_query: Option<String>,
    pub original_params: Option<String>,
}
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SearchActionDto {
    pub title: String,
    pub video_id: Option<String>,
    pub playlist_id: Option<String>,
    pub browse_id: Option<String>,
    pub params: Option<String>,
}
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SearchSectionDto {
    pub id: String,
    pub title: String,
    pub layout: String,
    pub items: Vec<SearchTopCardDto>,
    pub songs: Vec<SongDto>,
    pub primary_item_index: Option<u32>,
    pub related_item_indices: Vec<u32>,
    pub more_query: Option<String>,
    pub more_params: Option<String>,
    pub more_browse_id: Option<String>,
    pub actions: Vec<SearchActionDto>,
}
impl From<sideb_core::SearchPageRecord> for SearchPageDto {
    fn from(r: sideb_core::SearchPageRecord) -> Self {
        Self {
            chips: r
                .chips
                .into_iter()
                .map(|c| SearchChipDto {
                    id: c.id,
                    title: c.title,
                    params: c.params,
                    selected: c.selected,
                })
                .collect(),
            correction: r.correction.map(|c| SearchPageCorrectionDto {
                query: c.query,
                applied: c.applied,
                params: c.params,
                original_query: c.original_query,
                original_params: c.original_params,
            }),
            sections: r
                .sections
                .into_iter()
                .map(|s| SearchSectionDto {
                    id: s.id,
                    title: s.title,
                    layout: s.layout,
                    items: s.items.into_iter().map(Into::into).collect(),
                    songs: s.songs.into_iter().map(Into::into).collect(),
                    primary_item_index: s.primary_item_index,
                    related_item_indices: s.related_item_indices,
                    more_query: s.more_query,
                    more_params: s.more_params,
                    more_browse_id: s.more_browse_id,
                    actions: s
                        .actions
                        .into_iter()
                        .map(|a| SearchActionDto {
                            title: a.title,
                            video_id: a.video_id,
                            playlist_id: a.playlist_id,
                            browse_id: a.browse_id,
                            params: a.params,
                        })
                        .collect(),
                })
                .collect(),
            continuation: r.continuation,
        }
    }
}
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SearchTextRunDto {
    pub text: String,
    pub bold: bool,
}
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SearchSuggestionEntryDto {
    pub id: String,
    pub kind: String,
    pub query: Option<String>,
    pub runs: Vec<SearchTextRunDto>,
    pub feedback_token: Option<String>,
    pub card: Option<SearchTopCardDto>,
    pub song: Option<SongDto>,
}
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SearchSuggestionsPageDto {
    pub entries: Vec<SearchSuggestionEntryDto>,
}
impl From<sideb_core::SearchSuggestionsPageRecord> for SearchSuggestionsPageDto {
    fn from(r: sideb_core::SearchSuggestionsPageRecord) -> Self {
        Self {
            entries: r
                .entries
                .into_iter()
                .map(|e| SearchSuggestionEntryDto {
                    id: e.id,
                    kind: e.kind,
                    query: e.query,
                    runs: e
                        .runs
                        .into_iter()
                        .map(|r| SearchTextRunDto {
                            text: r.text,
                            bold: r.bold,
                        })
                        .collect(),
                    feedback_token: e.feedback_token,
                    card: e.card.map(Into::into),
                    song: e.song.map(Into::into),
                })
                .collect(),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SearchNextDto {
    pub items: Vec<SongDto>,
    pub continuation: Option<String>,
    pub automix_playlist_id: Option<String>,
}
impl From<sideb_core::NextResultRecord> for SearchNextDto {
    fn from(r: sideb_core::NextResultRecord) -> Self {
        Self {
            items: r.items.into_iter().map(Into::into).collect(),
            continuation: r.continuation,
            automix_playlist_id: r.automix_playlist_id,
        }
    }
}
