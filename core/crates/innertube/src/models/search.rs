//! Provider search surfaces. Display arrays remain ordered and duplicate occurrences survive.
use super::browse::{self, BrowseItem};
use super::metadata::{find_all, runs_text, SongItem};
use serde_json::Value;

#[derive(Clone, Debug, Default)]
pub struct SearchPage {
    pub chips: Vec<SearchChip>,
    pub correction: Option<SearchPageCorrection>,
    pub sections: Vec<SearchSection>,
    pub continuation: Option<String>,
}
#[derive(Clone, Debug)]
pub struct SearchChip {
    pub id: String,
    pub title: String,
    pub params: Option<String>,
    pub selected: bool,
}
#[derive(Clone, Debug)]
pub struct SearchPageCorrection {
    pub query: String,
    pub applied: bool,
    pub params: Option<String>,
    pub original_query: Option<String>,
    pub original_params: Option<String>,
}
#[derive(Clone, Debug, Default)]
pub struct SearchSection {
    pub id: String,
    pub title: String,
    pub layout: String,
    pub items: Vec<BrowseItem>,
    pub songs: Vec<SongItem>,
    /// Index of the unambiguous primary card in `items` for a top card shelf.
    pub primary_item_index: Option<u32>,
    /// Explicit content rows associated with that primary card, in provider order.
    pub related_item_indices: Vec<u32>,
    /// Original card positions, so a hero sharing a video id cannot steal a related row's tokens.
    pub song_item_indices: Vec<usize>,
    pub more_query: Option<String>,
    pub more_params: Option<String>,
    pub more_browse_id: Option<String>,
    pub actions: Vec<SearchAction>,
}
#[derive(Clone, Debug)]
pub struct SearchAction {
    pub title: String,
    pub video_id: Option<String>,
    pub playlist_id: Option<String>,
    pub browse_id: Option<String>,
    pub params: Option<String>,
}
#[derive(Clone, Debug, Default)]
pub struct SearchSuggestionsPage {
    pub entries: Vec<SearchSuggestionEntry>,
}
#[derive(Clone, Debug)]
pub struct SearchTextRun {
    pub text: String,
    pub bold: bool,
}
#[derive(Clone, Debug)]
pub struct SearchSuggestionEntry {
    pub id: String,
    pub kind: String,
    pub query: Option<String>,
    pub runs: Vec<SearchTextRun>,
    pub feedback_token: Option<String>,
    pub card: Option<BrowseItem>,
    pub song: Option<SongItem>,
}
fn string(node: &Value, path: &str) -> Option<String> {
    node.pointer(path)
        .and_then(Value::as_str)
        .map(str::to_owned)
}
fn text(node: &Value) -> Option<String> {
    runs_text(Some(node)).or_else(|| {
        node.get("simpleText")
            .and_then(Value::as_str)
            .map(str::to_owned)
    })
}
fn rows(node: &Value, section: &mut SearchSection) {
    if let Some(array) = node.as_array() {
        for child in array {
            rows(child, section);
        }
        return;
    }
    if let Some(row) = node.get("musicResponsiveListItemRenderer") {
        if let Some(card) = browse::list_item_to_browse_item(row) {
            if card.kind == "song" {
                if let Some(song) = browse::search_song_payload(row) {
                    section.song_item_indices.push(section.items.len());
                    section.songs.push(song);
                }
            }
            section.items.push(card);
        }
    } else if let Some(row) = node.get("musicTwoRowItemRenderer") {
        section.items.extend(browse::parse_two_row_item(row));
    } else if let Some(contents) = node.pointer("/itemSectionRenderer/contents") {
        rows(contents, section);
    }
}
fn section(node: &Value, id: String) -> Option<SearchSection> {
    let (renderer, layout) = [
        ("musicCardShelfRenderer", "top"),
        ("musicShelfRenderer", "list"),
        ("musicCarouselShelfRenderer", "carousel"),
        ("itemSectionRenderer", "list"),
        ("musicShelfContinuation", "list"),
        ("musicPlaylistShelfContinuation", "list"),
    ]
    .into_iter()
    .find_map(|(key, layout)| node.get(key).map(|r| (r, layout)))?;
    let mut result = SearchSection {
        id,
        layout: layout.into(),
        title: renderer
            .get("title")
            .and_then(text)
            .or_else(|| {
                renderer
                    .pointer("/header/musicCarouselShelfBasicHeaderRenderer/title")
                    .and_then(text)
            })
            .or_else(|| {
                renderer
                    .pointer("/header/musicCardShelfHeaderBasicRenderer/title")
                    .and_then(text)
            })
            .unwrap_or_default(),
        ..Default::default()
    };
    if layout == "top" {
        if let Some(title) = renderer
            .pointer("/header/musicCardShelfHeaderBasicRenderer/title")
            .and_then(text)
        {
            result.title = title;
        }
        if let Some(primary) = browse::card_shelf_main(renderer) {
            result.items.push(primary);
            result.primary_item_index = Some(0);
        }
        let related_start = result.items.len();
        if let Some(contents) = renderer.get("contents") {
            rows(contents, &mut result);
        }
        if result.primary_item_index.is_some() {
            result.related_item_indices = (related_start..result.items.len())
                .filter_map(|index| u32::try_from(index).ok())
                .collect();
        }
    } else if let Some(contents) = renderer.get("contents") {
        rows(contents, &mut result);
    }
    // Only explicit section navigation: never artist links embedded in row subtitles.
    let more = renderer.get("bottomEndpoint").or_else(|| renderer.pointer("/bottomButton/buttonRenderer/command"))
        .or_else(|| renderer.pointer("/header/musicCarouselShelfBasicHeaderRenderer/moreContentButton/buttonRenderer/navigationEndpoint"));
    if let Some(endpoint) = more {
        result.more_query = string(endpoint, "/searchEndpoint/query");
        result.more_params = string(endpoint, "/searchEndpoint/params")
            .or_else(|| string(endpoint, "/browseEndpoint/params"));
        result.more_browse_id = string(endpoint, "/browseEndpoint/browseId");
    }
    for button in renderer
        .get("buttons")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let Some(button) = button.get("buttonRenderer") else {
            continue;
        };
        let endpoint = button
            .get("navigationEndpoint")
            .or_else(|| button.get("command"))
            .unwrap_or(&Value::Null);
        let watch = endpoint
            .get("watchEndpoint")
            .or_else(|| endpoint.get("watchPlaylistEndpoint"));
        let action = SearchAction {
            title: button.get("text").and_then(text).unwrap_or_default(),
            video_id: watch.and_then(|w| string(w, "/videoId")),
            playlist_id: watch.and_then(|w| string(w, "/playlistId")),
            browse_id: string(endpoint, "/browseEndpoint/browseId"),
            params: watch
                .and_then(|w| string(w, "/params"))
                .or_else(|| string(endpoint, "/browseEndpoint/params")),
        };
        if action.video_id.is_some() || action.playlist_id.is_some() || action.browse_id.is_some() {
            result.actions.push(action);
        }
    }
    Some(result)
}
pub fn parse_search_page(root: &Value) -> SearchPage {
    // The selected tab owns the display list. Other tabs may contain cached hidden results.
    let tabs = root.pointer("/contents/tabbedSearchResultsRenderer/tabs");
    let selected = tabs
        .and_then(Value::as_array)
        .and_then(|tabs| {
            tabs.iter()
                .find(|t| t.pointer("/tabRenderer/selected").and_then(Value::as_bool) == Some(true))
                .or_else(|| tabs.first())
        })
        .and_then(|tab| tab.pointer("/tabRenderer/content"))
        .unwrap_or(if tabs.is_some() { &Value::Null } else { root });
    let mut page = SearchPage::default();
    let explicit_header = root
        .get("header")
        .or_else(|| root.pointer("/contents/tabbedSearchResultsRenderer/header"));
    let mut chips = find_all(selected, "chipCloudChipRenderer");
    if chips.is_empty() {
        if let Some(header) = explicit_header {
            chips = find_all(header, "chipCloudChipRenderer");
        }
    }
    for (index, chip) in chips.into_iter().enumerate() {
        page.chips.push(SearchChip {
            id: format!("chip-{index}"),
            title: chip.get("text").and_then(text).unwrap_or_default(),
            params: string(chip, "/navigationEndpoint/searchEndpoint/params"),
            selected: chip
                .get("isSelected")
                .and_then(Value::as_bool)
                .unwrap_or(false),
        });
    }
    'correction: for scope in std::iter::once(selected).chain(explicit_header) {
        for (key, applied) in [
            ("showingResultsForRenderer", true),
            ("didYouMeanRenderer", false),
        ] {
            if let Some(correction) = find_all(scope, key).first() {
                let endpoint = correction
                    .get("correctedQueryEndpoint")
                    .or_else(|| correction.get("navigationEndpoint"))
                    .unwrap_or(&Value::Null);
                if let Some(query) = string(endpoint, "/searchEndpoint/query")
                    .or_else(|| correction.get("correctedQuery").and_then(text))
                {
                    page.correction = Some(SearchPageCorrection {
                        query,
                        applied,
                        params: string(endpoint, "/searchEndpoint/params"),
                        original_query: string(
                            correction,
                            "/originalQueryEndpoint/searchEndpoint/query",
                        ),
                        original_params: string(
                            correction,
                            "/originalQueryEndpoint/searchEndpoint/params",
                        ),
                    });
                    break 'correction;
                }
            }
        }
    }
    if let Some(container) = find_all(selected, "sectionListRenderer").first() {
        for (index, node) in container
            .get("contents")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .enumerate()
        {
            if let Some(s) = section(node, format!("section-{index}")) {
                page.sections.push(s);
            }
        }
        page.continuation = browse::continuation_token(container);
    } else {
        for key in ["musicShelfContinuation", "musicPlaylistShelfContinuation"] {
            if let Some(renderer) = root.pointer(&format!("/continuationContents/{key}")) {
                let wrapper = serde_json::json!({key: renderer});
                page.sections
                    .extend(section(&wrapper, "continuation-0".into()));
                page.continuation = browse::continuation_token(renderer);
            }
        }
        for action in root
            .get("onResponseReceivedCommands")
            .or_else(|| root.get("onResponseReceivedActions"))
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            if let Some(items) = action.pointer("/appendContinuationItemsAction/continuationItems")
            {
                let mut s = SearchSection {
                    id: format!("continuation-{}", page.sections.len()),
                    layout: "list".into(),
                    ..Default::default()
                };
                rows(items, &mut s);
                page.continuation = browse::continuation_token(items);
                page.sections.push(s);
            }
        }
    }
    page
}
pub fn parse_search_suggestions_page(root: &Value) -> SearchSuggestionsPage {
    fn collect(node: &Value, out: &mut SearchSuggestionsPage) {
        if let Some(array) = node.as_array() {
            for child in array {
                collect(child, out);
            }
            return;
        }
        for (key, kind) in [
            ("historySuggestionRenderer", "history"),
            ("searchSuggestionRenderer", "text"),
        ] {
            if let Some(renderer) = node.get(key) {
                let runs: Vec<_> = renderer
                    .pointer("/suggestion/runs")
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                    .filter_map(|r| {
                        Some(SearchTextRun {
                            text: r.get("text")?.as_str()?.to_owned(),
                            bold: r.get("bold").and_then(Value::as_bool).unwrap_or(false),
                        })
                    })
                    .collect();
                let query = string(renderer, "/navigationEndpoint/searchEndpoint/query")
                    .or_else(|| renderer.get("suggestion").and_then(text));
                let feedback_token = find_all(renderer, "feedbackEndpoint")
                    .into_iter()
                    .find_map(|e| e.get("feedbackToken").and_then(Value::as_str))
                    .map(str::to_owned);
                out.entries.push(SearchSuggestionEntry {
                    id: format!("suggestion-{}", out.entries.len()),
                    kind: kind.into(),
                    query,
                    runs,
                    feedback_token,
                    card: None,
                    song: None,
                });
                return;
            }
        }
        let mut s = SearchSection::default();
        if node.get("musicResponsiveListItemRenderer").is_some()
            || node.get("musicTwoRowItemRenderer").is_some()
        {
            rows(node, &mut s);
        }
        if let Some(card) = node.get("musicCardShelfRenderer") {
            s.items.extend(browse::card_shelf_main(card));
        }
        if !s.items.is_empty() {
            for card in s.items {
                let song = s
                    .songs
                    .iter()
                    .find(|song| song.video_id == card.id)
                    .cloned();
                out.entries.push(SearchSuggestionEntry {
                    id: format!("suggestion-{}", out.entries.len()),
                    kind: "media".into(),
                    query: None,
                    runs: vec![],
                    feedback_token: None,
                    card: Some(card),
                    song,
                });
            }
            if let Some(contents) = node.pointer("/musicCardShelfRenderer/contents") {
                collect(contents, out);
            }
            return;
        }
        for key in [
            "contents",
            "searchSuggestionsSectionRenderer",
            "itemSectionRenderer",
        ] {
            if let Some(child) = node.get(key) {
                collect(child, out);
            }
        }
    }
    let mut result = SearchSuggestionsPage::default();
    collect(root, &mut result);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    fn row(title: &str) -> Value {
        json!({"musicResponsiveListItemRenderer": {
            "playlistItemData":{"videoId":"same-video", "playlistSetVideoId":title},
            "flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":title}]}}},
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Artist","navigationEndpoint":{"browseEndpoint":{"browseId":"UCartist"}}}]}}}],
            "fixedColumns":[{"musicResponsiveListItemFixedColumnRenderer":{"text":{"runs":[{"text":"3:12"}]}}}]
        }})
    }
    fn top_card(kind: &str, id: &str, title: &str) -> Value {
        let endpoint = if kind == "song" {
            json!({"watchEndpoint":{"videoId":id}})
        } else {
            json!({"browseEndpoint":{"browseId":id}})
        };
        json!({"musicCardShelfRenderer":{
            "title":{"runs":[{"text":title,"navigationEndpoint":endpoint}]},
            "subtitle":{"runs":[{"text":"Artist"}]}
        }})
    }
    #[test]
    fn top_card_roles_are_explicit_and_keep_duplicate_occurrences() {
        let mut artist = top_card("artist", "UCartist", "Artist");
        artist["musicCardShelfRenderer"]["contents"] =
            json!([row("same"), row("related-2"), row("same")]);
        let parsed = parse_search_page(&json!({"sectionListRenderer":{"contents":[artist]}}));
        let section = &parsed.sections[0];
        assert_eq!(section.primary_item_index, Some(0));
        assert_eq!(section.related_item_indices, [1, 2, 3]);
        assert_eq!(
            section
                .items
                .iter()
                .map(|item| item.title.as_str())
                .collect::<Vec<_>>(),
            ["Artist", "same", "related-2", "same"]
        );
        assert_eq!(section.songs.len(), 3);
        assert_eq!(section.song_item_indices, [1, 2, 3]);

        for (kind, id, title) in [("song", "video", "Song"), ("album", "MPREalbum", "Album")] {
            let parsed = parse_search_page(
                &json!({"sectionListRenderer":{"contents":[top_card(kind, id, title)]}}),
            );
            assert_eq!(parsed.sections[0].primary_item_index, Some(0));
            assert!(parsed.sections[0].related_item_indices.is_empty());
        }
    }

    #[test]
    fn missing_or_ambiguous_top_identity_does_not_promote_rows() {
        let root = json!({"sectionListRenderer":{"contents":[
            {"musicShelfRenderer":{"contents":[row("ordinary")]}},
            {"musicCardShelfRenderer":{"contents":[row("unassociated")]}},
            {"musicCardShelfRenderer":{"title":{"runs":[{"text":"Ambiguous"}]},"contents":[row("also-unassociated")]}}
        ]}});
        let page = parse_search_page(&root);
        assert_eq!(page.sections[0].primary_item_index, None);
        assert!(page.sections[0].related_item_indices.is_empty());
        assert_eq!(page.sections[0].items[0].title, "ordinary");
        assert_eq!(page.sections[1].primary_item_index, None);
        assert!(page.sections[1].related_item_indices.is_empty());
        assert_eq!(page.sections[1].items[0].title, "unassociated");
        assert_eq!(page.sections[2].primary_item_index, None);
        assert!(page.sections[2].related_item_indices.is_empty());
    }
    #[test]
    fn ordered_sections_duplicate_occurrences_chips_and_more() {
        let root = json!({"contents":{"sectionListRenderer":{"contents":[
            {"musicShelfRenderer":{"title":{"runs":[{"text":"From your library"}]},"contents":[row("first"),row("second")],"bottomEndpoint":{"searchEndpoint":{"query":"q", "params":"opaque+params"}}}},
            {"musicCarouselShelfRenderer":{"header":{"musicCarouselShelfBasicHeaderRenderer":{"title":{"runs":[{"text":"Listen again"}]}}},"contents":[row("third")]}},
            {"musicShelfRenderer":{"title":{"runs":[{"text":"From your library"}]},"contents":[]}}
        ],"continuations":[{"nextContinuationData":{"continuation":"next"}}]}},
        "chips":[{"chipCloudChipRenderer":{"text":{"runs":[{"text":"All"}]},"isSelected":true}}, {"chipCloudChipRenderer":{"text":{"simpleText":"Songs"},"navigationEndpoint":{"searchEndpoint":{"params":"opaque"}}}}]});
        let page = parse_search_page(&root);
        assert_eq!(
            page.sections
                .iter()
                .map(|s| s.title.as_str())
                .collect::<Vec<_>>(),
            ["From your library", "Listen again", "From your library"]
        );
        assert_ne!(page.sections[0].id, page.sections[2].id);
        assert_eq!(page.sections[0].items.len(), 2);
        assert_eq!(page.sections[0].songs[1].title, "second");
        assert_eq!(page.sections[1].layout, "carousel");
        assert_eq!(
            page.sections[0].more_params.as_deref(),
            Some("opaque+params")
        );
        assert!(page.chips[0].selected);
        assert_eq!(page.chips[0].params, None);
        assert_eq!(page.chips[1].params.as_deref(), Some("opaque"));
        assert_eq!(page.continuation.as_deref(), Some("next"));
    }
    #[test]
    fn selected_tab_owns_chips_and_correction_without_hidden_tab_leakage() {
        let tab = |selected, title: &str, query: &str| {
            json!({"tabRenderer":{"selected":selected,"content":{"sectionListRenderer":{
                "header":{"chipCloudRenderer":{"chips":[{"chipCloudChipRenderer":{"text":{"simpleText":title},"navigationEndpoint":{"searchEndpoint":{"params":title}}}}]}},
                "contents":[{"itemSectionRenderer":{"contents":[{"didYouMeanRenderer":{"navigationEndpoint":{"searchEndpoint":{"query":query}}}}]}}]
            }}}})
        };
        let page = parse_search_page(
            &json!({"contents":{"tabbedSearchResultsRenderer":{"tabs":[tab(false,"hidden-chip","hidden-correction"),tab(true,"visible-chip","visible-correction")]}}}),
        );
        assert_eq!(page.chips.len(), 1);
        assert_eq!(page.chips[0].title, "visible-chip");
        assert_eq!(page.chips[0].params.as_deref(), Some("visible-chip"));
        assert_eq!(page.correction.unwrap().query, "visible-correction");
    }

    #[test]
    fn correction_retains_exact_endpoints() {
        let page = parse_search_page(&json!({"showingResultsForRenderer":{
            "correctedQueryEndpoint":{"searchEndpoint":{"query":"corrected","params":"corrected-params"}},
            "originalQueryEndpoint":{"searchEndpoint":{"query":"literal","params":"literal-params"}}
        }}));
        let correction = page.correction.unwrap();
        assert!(correction.applied);
        assert_eq!(correction.original_query.as_deref(), Some("literal"));
        assert_eq!(
            correction.original_params.as_deref(),
            Some("literal-params")
        );
        assert_eq!(correction.params.as_deref(), Some("corrected-params"));
    }
    #[test]
    fn continuation_variants_keep_rows_and_terminal_empty() {
        let page = parse_search_page(
            &json!({"continuationContents":{"musicShelfContinuation":{"contents":[row("continued")],"continuations":[{"nextContinuationData":{"continuation":"next"}}]}}}),
        );
        assert_eq!(page.sections[0].items[0].title, "continued");
        assert_eq!(page.continuation.as_deref(), Some("next"));
        let page = parse_search_page(
            &json!({"onResponseReceivedCommands":[{"appendContinuationItemsAction":{"continuationItems":[row("append"),{"continuationItemRenderer":{"continuationEndpoint":{"continuationCommand":{"token":"modern"}}}}]}}]}),
        );
        assert_eq!(page.sections[0].items[0].title, "append");
        assert_eq!(page.continuation.as_deref(), Some("modern"));
        assert!(parse_search_page(&json!({})).sections.is_empty());
    }
    #[test]
    fn suggestions_keep_history_runs_tokens_and_interleaved_duplicates() {
        let text = json!({"historySuggestionRenderer":{"suggestion":{"runs":[{"text":"hel","bold":true},{"text":"lo"}]},"navigationEndpoint":{"searchEndpoint":{"query":"hello"}},"serviceEndpoint":{"feedbackEndpoint":{"feedbackToken":"remove-only"}}}});
        let root = json!({"contents":[{"searchSuggestionsSectionRenderer":{"contents":[text.clone(),row("first"),text,row("second")]}}]});
        let page = parse_search_suggestions_page(&root);
        assert_eq!(
            page.entries
                .iter()
                .map(|s| s.kind.as_str())
                .collect::<Vec<_>>(),
            ["history", "media", "history", "media"]
        );
        assert_eq!(
            page.entries[0].feedback_token.as_deref(),
            Some("remove-only")
        );
        assert!(page.entries[0].runs[0].bold);
        assert!(!page.entries[0].runs[1].bold);
        assert_ne!(page.entries[0].id, page.entries[2].id);
        assert_eq!(page.entries[3].song.as_ref().unwrap().title, "second");
    }
    #[test]
    fn suggestions_real_anonymous_fixture_preserves_payload_without_changing_order() {
        let root: Value = serde_json::from_str(include_str!(
            "../../tests/fixtures/search-suggestions-anonymous.json"
        ))
        .unwrap();
        let page = parse_search_suggestions_page(&root);
        assert_eq!(page.entries.len(), 9);
        assert_eq!(
            page.entries[7].song.as_ref().unwrap().album.as_deref(),
            Some("My Beautiful Dark Twisted Fantasy")
        );
    }
}

#[cfg(test)]
mod endpoint_payload_tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn top_actions_keep_opaque_watch_playlist_and_browse_params() {
        let page = parse_search_page(
            &json!({"sectionListRenderer":{"contents":[{"musicCardShelfRenderer":{
                "buttons":[
                    {"buttonRenderer":{"text":{"runs":[{"text":"Play"}]},"navigationEndpoint":{"watchEndpoint":{"videoId":"video","playlistId":"queue","params":"play-params"}}}},
                    {"buttonRenderer":{"text":{"simpleText":"Shuffle"},"navigationEndpoint":{"watchPlaylistEndpoint":{"playlistId":"shuffle","params":"shuffle-params"}}}},
                    {"buttonRenderer":{"text":{"simpleText":"Browse"},"navigationEndpoint":{"browseEndpoint":{"browseId":"artist","params":"browse-params"}}}}
                ]
            }}]}}),
        );
        let actions = &page.sections[0].actions;
        assert_eq!(actions.len(), 3);
        assert_eq!(actions[0].video_id.as_deref(), Some("video"));
        assert_eq!(actions[1].playlist_id.as_deref(), Some("shuffle"));
        assert_eq!(actions[1].params.as_deref(), Some("shuffle-params"));
        assert_eq!(actions[2].browse_id.as_deref(), Some("artist"));
    }
}
