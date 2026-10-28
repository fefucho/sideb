//! Typed provider-search contract, additive to the legacy search adapters.
use crate::{BrowseCardRecord, SongItemRecord};
use innertube::models::search as model;
#[derive(Clone, Debug, uniffi::Record)]
pub struct SearchPageRecord {
    pub chips: Vec<SearchChipRecord>,
    pub correction: Option<SearchPageCorrectionRecord>,
    pub sections: Vec<SearchSectionRecord>,
    pub continuation: Option<String>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct SearchChipRecord {
    pub id: String,
    pub title: String,
    pub params: Option<String>,
    pub selected: bool,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct SearchPageCorrectionRecord {
    pub query: String,
    pub applied: bool,
    pub params: Option<String>,
    pub original_query: Option<String>,
    pub original_params: Option<String>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct SearchSectionRecord {
    pub id: String,
    pub title: String,
    pub layout: String,
    pub items: Vec<BrowseCardRecord>,
    pub songs: Vec<SongItemRecord>,
    pub primary_item_index: Option<u32>,
    pub related_item_indices: Vec<u32>,
    pub more_query: Option<String>,
    pub more_params: Option<String>,
    pub more_browse_id: Option<String>,
    pub actions: Vec<SearchActionRecord>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct SearchActionRecord {
    pub title: String,
    pub video_id: Option<String>,
    pub playlist_id: Option<String>,
    pub browse_id: Option<String>,
    pub params: Option<String>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct SearchSuggestionsPageRecord {
    pub entries: Vec<SearchSuggestionEntryRecord>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct SearchSuggestionEntryRecord {
    pub id: String,
    pub kind: String,
    pub query: Option<String>,
    pub runs: Vec<SearchTextRunRecord>,
    pub feedback_token: Option<String>,
    pub card: Option<BrowseCardRecord>,
    pub song: Option<SongItemRecord>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct SearchTextRunRecord {
    pub text: String,
    pub bold: bool,
}
impl From<model::SearchPage> for SearchPageRecord {
    fn from(page: model::SearchPage) -> Self {
        Self {
            chips: page
                .chips
                .into_iter()
                .map(|c| SearchChipRecord {
                    id: c.id,
                    title: c.title,
                    params: c.params,
                    selected: c.selected,
                })
                .collect(),
            correction: page.correction.map(|c| SearchPageCorrectionRecord {
                query: c.query,
                applied: c.applied,
                params: c.params,
                original_query: c.original_query,
                original_params: c.original_params,
            }),
            sections: page
                .sections
                .into_iter()
                .map(|s| {
                    // List rows carry original payloads, including library tokens and credits. Hero and
                    // two-row song cards have no list payload and use the existing card conversion.
                    let mut songs = s
                        .song_item_indices
                        .into_iter()
                        .zip(s.songs)
                        .collect::<std::collections::HashMap<_, _>>();
                    let mut records: Vec<SongItemRecord> = Vec::new();
                    for (position, card) in s.items.iter().enumerate() {
                        if card.kind == "song" {
                            if let Some(song) = songs.remove(&position) {
                                records.push(song.into());
                            } else {
                                records.push(card.clone().into());
                            }
                        }
                    }
                    SearchSectionRecord {
                        id: s.id,
                        title: s.title,
                        layout: s.layout,
                        items: s.items.into_iter().map(Into::into).collect(),
                        songs: records,
                        primary_item_index: s.primary_item_index,
                        related_item_indices: s.related_item_indices,
                        more_query: s.more_query,
                        more_params: s.more_params,
                        more_browse_id: s.more_browse_id,
                        actions: s
                            .actions
                            .into_iter()
                            .map(|a| SearchActionRecord {
                                title: a.title,
                                video_id: a.video_id,
                                playlist_id: a.playlist_id,
                                browse_id: a.browse_id,
                                params: a.params,
                            })
                            .collect(),
                    }
                })
                .collect(),
            continuation: page.continuation,
        }
    }
}
impl From<model::SearchSuggestionsPage> for SearchSuggestionsPageRecord {
    fn from(page: model::SearchSuggestionsPage) -> Self {
        Self {
            entries: page
                .entries
                .into_iter()
                .map(|e| {
                    let song = e.song.map(Into::into).or_else(|| {
                        e.card
                            .as_ref()
                            .filter(|c| c.kind == "song")
                            .cloned()
                            .map(Into::into)
                    });
                    SearchSuggestionEntryRecord {
                        id: e.id,
                        kind: e.kind,
                        query: e.query,
                        runs: e
                            .runs
                            .into_iter()
                            .map(|r| SearchTextRunRecord {
                                text: r.text,
                                bold: r.bold,
                            })
                            .collect(),
                        feedback_token: e.feedback_token,
                        card: e.card.map(Into::into),
                        song,
                    }
                })
                .collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn hero_and_repeated_rows_keep_occurrence_payloads() {
        let row = |name: &str| {
            json!({"musicResponsiveListItemRenderer":{
                "playlistItemData":{"videoId":"same", "playlistSetVideoId":name},
            "menu":{"menuRenderer":{"items":[{"menuServiceItemRenderer":{"serviceEndpoint":{"playlistEditEndpoint":{"actions":[{"setVideoId":name,"action":"ACTION_REMOVE_VIDEO"}]}}}}]}},
                "flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":name}]}}}]
            }})
        };
        let page = model::parse_search_page(
            &json!({"sectionListRenderer":{"contents":[{"musicCardShelfRenderer":{
                "title":{"runs":[{"text":"Hero","navigationEndpoint":{"watchEndpoint":{"videoId":"same"}}}]},
                "contents":[row("first"),row("second")]
            }}]}}),
        );
        let record = SearchPageRecord::from(page);
        assert_eq!(
            record.sections[0]
                .songs
                .iter()
                .map(|s| s.title.as_str())
                .collect::<Vec<_>>(),
            ["Hero", "first", "second"]
        );
        assert_eq!(record.sections[0].primary_item_index, Some(0));
        assert_eq!(record.sections[0].related_item_indices, [1, 2]);
        assert_eq!(
            record.sections[0].songs[1].set_video_id.as_deref(),
            Some("first")
        );
        assert_eq!(
            record.sections[0].songs[2].set_video_id.as_deref(),
            Some("second")
        );
    }
}
