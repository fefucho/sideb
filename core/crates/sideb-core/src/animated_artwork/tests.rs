use super::*;

const ALBUM_HTML: &str = include_str!("tests/fixtures/album.html");

fn request() -> super::super::AnimatedArtworkRequest {
    super::super::AnimatedArtworkRequest {
        video_id: "ytid".into(),
        title: "Blinding Lights".into(),
        artists: "The Weeknd".into(),
        album: Some("After Hours".into()),
        album_id: Some("yt-album".into()),
        duration_secs: Some(200),
        storefront: "us".into(),
        prefer_hevc: true,
    }
}

fn candidate(
    artist: &str,
    album: &str,
    title: &str,
    duration: Option<u64>,
    kind: &str,
) -> Candidate {
    Candidate {
        collection_id: 1499378108,
        artist: artist.into(),
        album: album.into(),
        title: title.into(),
        duration,
        kind: kind.into(),
    }
}

#[test]
fn matching_normalizes_unicode_but_preserves_editions_and_artist_identity() {
    let req = request();
    assert!(album_match(
        &candidate("The Weeknd", "AFTER HOURS", "", None, "collection"),
        &req,
        "After Hours"
    ));
    assert!(album_match(
        &candidate("The Weeknd", "After Hóurs", "", None, "collection"),
        &req,
        "After Hours"
    ));
    assert!(!album_match(
        &candidate("Other Artist", "After Hours", "", None, "collection"),
        &req,
        "After Hours"
    ));
    assert!(!album_match(
        &candidate("The Weeknd", "After Hours (Deluxe)", "", None, "collection"),
        &req,
        "After Hours"
    ));
    assert!(!album_match(
        &candidate("Cover Band", "After Hours", "", None, "collection"),
        &req,
        "After Hours"
    ));
}

#[test]
fn song_fallback_requires_artist_album_title_and_near_duration() {
    let req = request();
    assert!(song_match(
        &candidate(
            "The Weeknd",
            "After Hours",
            "Blinding Lights",
            Some(203),
            "track"
        ),
        &req,
        200
    ));
    assert!(!song_match(
        &candidate(
            "The Weeknd",
            "After Hours",
            "Blinding Lights",
            Some(205),
            "track"
        ),
        &req,
        200
    ));
    assert!(!song_match(
        &candidate(
            "Piano Cover",
            "After Hours",
            "Blinding Lights",
            Some(200),
            "track"
        ),
        &req,
        200
    ));
    assert!(!song_match(
        &candidate(
            "The Weeknd",
            "After Hours (Deluxe)",
            "Blinding Lights",
            Some(200),
            "track"
        ),
        &req,
        200
    ));
    assert!(!song_match(
        &candidate(
            "The Weeknd",
            "After Hours",
            "Blinding Lights",
            Some(200),
            "collection"
        ),
        &req,
        200
    ));
}

#[test]
fn schema_distinguishes_valid_null_from_unknown_and_other_collection() {
    assert!(matches!(
        parse_album_html(ALBUM_HTML.as_bytes(), "1499378108").unwrap(),
        AlbumPayload::Master(_)
    ));
    let null = r#"<script id="serialized-server-data">{"data":[{"data":{"sections":[{"items":[{"id":"1499378108","videoArtwork":null}]}]}}]}</script>"#;
    assert!(matches!(
        parse_album_html(null.as_bytes(), "1499378108").unwrap(),
        AlbumPayload::Absent
    ));
    let wrong = ALBUM_HTML.replace("1499378108", "999");
    assert!(parse_album_html(wrong.as_bytes(), "1499378108").is_err());
    let unknown = r#"<script id="serialized-server-data">{"data":[{"unexpected":true}]}</script>"#;
    assert!(matches!(
        parse_album_html(unknown.as_bytes(), "1499378108"),
        Err(ProviderError::Unsupported(_))
    ));
}

#[test]
fn master_selection_keeps_best_square_quality_up_to_1080_60_and_codec_preference() {
    let master = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=1080x1080,FRAME-RATE=60.000,VIDEO-RANGE=SDR,CODECS=\"avc1.640020\"\nhi/60.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=7000000,RESOLUTION=1080x1080,FRAME-RATE=60.000,VIDEO-RANGE=SDR,CODECS=\"hvc1.2\"\nhi/hevc.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=9000000,RESOLUTION=2160x2160,FRAME-RATE=60.000,VIDEO-RANGE=SDR,CODECS=\"hvc1.2\"\nuhd.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=9000000,RESOLUTION=1080x1080,FRAME-RATE=60.000,VIDEO-RANGE=PQ,CODECS=\"hvc1.2\"\nhdr.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=9000000,RESOLUTION=1080x1080,FRAME-RATE=60.001,VIDEO-RANGE=SDR,CODECS=\"hvc1.2\"\nfast.m3u8\n";
    let got = parse_master(
        master,
        Url::parse("https://a1.phobos.apple.com/master.m3u8").unwrap(),
        true,
    )
    .unwrap();
    assert_eq!(got.len(), 2);
    assert_eq!(got[0].codec, "hvc1.2");
    assert_eq!(got[0].width, 1080);
    assert_eq!(got[0].frame_rate, 60.0);
    assert!(got[0].url.ends_with("/hi/hevc.m3u8"));
    assert!(got
        .iter()
        .all(|v| !v.url.contains("uhd") && !v.url.contains("hdr") && !v.url.contains("fast")));
}

#[test]
fn relative_playlist_uris_require_one_unencrypted_complete_resource() {
    let base = Url::parse("https://a1.phobos.apple.com/path/level/index.m3u8").unwrap();
    let single = "#EXTM3U\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-MAP:URI=\"../media/movie.mp4\"\n#EXTINF:2,\n../media/movie.mp4\n#EXTINF:2,\n../media/movie.mp4\n#EXT-X-ENDLIST\n";
    assert_eq!(
        parse_media_playlist(single, &base).unwrap(),
        "https://a1.phobos.apple.com/path/media/movie.mp4"
    );
    let multi = single.replace(
        "../media/movie.mp4\n#EXTINF:2,\n../media/movie.mp4",
        "../media/one.m4s\n#EXTINF:2,\n../media/two.m4s",
    );
    assert!(parse_media_playlist(&multi, &base).is_err());
    let encrypted = single.replace(
        "#EXT-X-PLAYLIST-TYPE:VOD",
        "#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-KEY:METHOD=AES-128,URI=\"key\"",
    );
    assert!(parse_media_playlist(&encrypted, &base).is_err());
    let unfinished = single.replace("#EXT-X-ENDLIST", "");
    assert!(parse_media_playlist(&unfinished, &base).is_err());
}

#[test]
fn rejects_non_apple_or_non_https_resources() {
    assert!(checked_url("https://evilapple.com/a").is_err());
    assert!(checked_url("http://a1.phobos.apple.com/a").is_err());
    assert!(checked_url("https://a1.phobos.apple.com/a").is_ok());
    assert!(checked_url("https://mvod.itunes.apple.com/a").is_ok());
    assert!(checked_url("https://mvod.itunes.apple.com.evil.test/a").is_err());
    assert!(checked_url("https://mvod.itunes.apple.com:8080/a").is_err());
}

#[test]
fn album_search_does_not_require_song_only_fields() {
    let body = br#"{"results":[{"wrapperType":"collection","collectionId":1499378108,"artistName":"The Weeknd","collectionName":"After Hours"}]}"#;
    let candidates = parse_search_response(body).unwrap();
    assert_eq!(candidates.len(), 1);
    assert!(album_match(&candidates[0], &request(), "After Hours"));
    assert_eq!(candidates[0].duration, None);
}

#[test]
fn portable_selection_uses_best_h264_even_when_hevc_is_larger() {
    let master = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=1080x1080,FRAME-RATE=60,CODECS=\"hvc1.2\"\na.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=960x960,FRAME-RATE=30,CODECS=\"avc1.64\"\nb.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1080x1080,FRAME-RATE=NaN,CODECS=\"avc1.64\"\nbad.m3u8\n";
    let got = parse_master(
        master,
        Url::parse("https://mvod.itunes.apple.com/master.m3u8").unwrap(),
        false,
    )
    .unwrap();
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].width, 960);
    assert!(got[0].codec.starts_with("avc1"));
}

#[test]
fn rejects_multiple_initialization_resources_and_master_encryption() {
    let base = Url::parse("https://mvod.itunes.apple.com/a/media.m3u8").unwrap();
    let text = "#EXTM3U\n#EXT-X-MAP:URI=\"other.mp4\"\n#EXT-X-MAP:URI=\"file.mp4\"\n#EXTINF:2,\nfile.mp4\n#EXT-X-ENDLIST\n";
    assert!(parse_media_playlist(text, &base).is_err());
    assert!(parse_master(
        "#EXTM3U\n#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI=\"key\"\n",
        base,
        true
    )
    .is_err());
}

#[tokio::test]
#[ignore = "Public Apple HTTP and media download; opt in with SIDEB_MOTION_PROBE_CACHE"]
async fn live_after_hours_prepares_local_1080_asset() {
    let Ok(cache_dir) = std::env::var("SIDEB_MOTION_PROBE_CACHE") else {
        return;
    };
    let engine = super::super::Engine::new();
    let id = "public-after-hours-probe".to_string();
    let asset = engine
        .prepare(request(), id.clone(), cache_dir)
        .await
        .unwrap()
        .expect("matching public album has motion");
    assert_eq!(asset.width, 1080);
    assert_eq!(asset.height, 1080);
    assert!(asset.frame_rate > 0. && asset.frame_rate <= 60.);
    assert!(std::path::Path::new(&asset.local_path).is_file());
    println!("{}", serde_json::to_string(&asset).unwrap());
    engine.cancel(&id);
}

#[test]
fn matching_rejects_ambiguous_collections_but_allows_duplicate_rows() {
    let req = request();
    let first = candidate(
        "The Weeknd",
        "After Hours",
        "Blinding Lights",
        Some(200),
        "collection",
    );
    let mut other = first.clone();
    other.collection_id += 1;
    assert!(unique_collection(
        vec![first.clone(), other]
            .into_iter()
            .filter(|c| album_match(c, &req, "After Hours"))
    )
    .is_none());
    assert!(unique_collection(
        vec![first.clone(), first.clone()]
            .into_iter()
            .filter(|c| album_match(c, &req, "After Hours"))
    )
    .is_some());
    let mut song = first;
    song.kind = "track".into();
    let mut other = song.clone();
    other.collection_id += 1;
    assert!(unique_collection(
        vec![song.clone(), other]
            .into_iter()
            .filter(|c| song_match(c, &req, 200))
    )
    .is_none());
    assert!(unique_collection(
        vec![song.clone(), song]
            .into_iter()
            .filter(|c| song_match(c, &req, 200))
    )
    .is_some());
}

const GRADUATION_CLEAN: &[u8] = include_bytes!("tests/fixtures/graduation-clean.html");
const GRADUATION_EXPLICIT: &[u8] = include_bytes!("tests/fixtures/graduation-explicit.html");
fn graduation_clean() -> AlbumDocument {
    parse_album_document(GRADUATION_CLEAN, "1442845779").unwrap()
}
fn graduation_explicit() -> AlbumDocument {
    parse_album_document(GRADUATION_EXPLICIT, "1451901307").unwrap()
}
fn set_related_id(item: &mut Value, id: &str) {
    item["id"] = format!("other-versions - {id}").into();
    item["contentDescriptor"]["identifiers"]["storeAdamID"] = id.into();
}
#[tokio::test]
async fn official_clean_null_follows_reciprocal_explicit_motion_once() {
    let original = graduation_clean();
    assert!(matches!(original.payload, AlbumPayload::Absent));
    let calls = std::sync::atomic::AtomicUsize::new(0);
    let found = resolve_related_document(&original, |id| {
        calls.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        async move {
            assert_eq!(id, "1451901307");
            Ok(graduation_explicit())
        }
    })
    .await
    .unwrap()
    .unwrap();
    assert_eq!(found.0, "1451901307");
    assert_eq!(calls.load(std::sync::atomic::Ordering::Relaxed), 1);
}
#[tokio::test]
async fn incompatible_related_editions_are_skipped_before_valid_version() {
    let mut original = graduation_clean();
    let mut deluxe = original.related[0].clone();
    set_related_id(&mut deluxe, "99");
    deluxe["titleLinks"][0]["title"] = "Graduation (Deluxe)".into();
    let mut live = deluxe.clone();
    set_related_id(&mut live, "98");
    live["titleLinks"][0]["title"] = "Graduation (Live)".into();
    let mut remaster = deluxe.clone();
    set_related_id(&mut remaster, "97");
    remaster["titleLinks"][0]["title"] = "Graduation (Remastered)".into();
    original.related.splice(0..0, [deluxe, live, remaster]);
    let result = resolve_related_document(&original, |id| async move {
        assert_eq!(id, "1451901307");
        Ok(graduation_explicit())
    })
    .await
    .unwrap();
    assert!(result.is_some());
}
#[tokio::test]
async fn wrong_artist_album_and_reciprocal_artwork_never_become_absence() {
    for change in 0..4 {
        let original = graduation_clean();
        let result = resolve_related_document(&original, |_| async move {
            let mut alternate = graduation_explicit();
            match change {
                0 => alternate.header["subtitleLinks"][0]["title"] = "Other Artist".into(),
                1 => alternate.header["title"] = "Other Album".into(),
                2 => {
                    alternate.related[0]["artwork"]["dictionary"]["url"] =
                        "https://is1-ssl.mzstatic.com/different-cover.jpg".into()
                }
                _ => alternate.related.clear(),
            };
            Ok(alternate)
        })
        .await;
        assert!(result.is_err(), "change={change}");
    }
}
#[tokio::test]
async fn no_alternates_or_known_null_reciprocal_loop_are_bounded_absences() {
    let mut original = graduation_clean();
    original.related.clear();
    let result = resolve_related_document(&original, |_| async { panic!("no network needed") })
        .await
        .unwrap();
    assert!(result.is_none());
    let original = graduation_clean();
    let result = resolve_related_document(&original, |_| async {
        let mut alternate = graduation_explicit();
        alternate.payload = AlbumPayload::Absent;
        Ok(alternate)
    })
    .await
    .unwrap();
    assert!(result.is_none());
}
#[tokio::test]
async fn unknown_or_failed_other_versions_remain_transient_and_valid_later_wins() {
    let original = graduation_clean();
    assert!(
        resolve_related_document(&original, |_| async { Err(unsupported("temporary error")) })
            .await
            .is_err()
    );
    let mut original = graduation_clean();
    let mut first = original.related[0].clone();
    set_related_id(&mut first, "99");
    original.related.insert(0, first);
    let result = resolve_related_document(&original, |id| async move {
        if id == "99" {
            Err(unsupported("temporary error"))
        } else {
            Ok(graduation_explicit())
        }
    })
    .await
    .unwrap();
    assert!(result.is_some());
    let mut original = graduation_clean();
    original
        .related
        .push(serde_json::json!({"unexpected":"schema"}));
    let result = resolve_related_document(&original, |_| async {
        let mut alternate = graduation_explicit();
        alternate.payload = AlbumPayload::Absent;
        Ok(alternate)
    })
    .await;
    assert!(result.is_err());
}
#[tokio::test]
async fn three_version_cap_never_caches_unvisited_fourth_as_absence() {
    let mut original = graduation_clean();
    let template = original.related[0].clone();
    original.related.clear();
    for id in ["1", "2", "3", "1451901307"] {
        let mut item = template.clone();
        set_related_id(&mut item, id);
        original.related.push(item);
    }
    let calls = std::sync::atomic::AtomicUsize::new(0);
    let result = resolve_related_document(&original, |id| {
        calls.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        async move {
            let mut alternate = graduation_explicit();
            alternate.id = id;
            alternate.payload = AlbumPayload::Absent;
            Ok(alternate)
        }
    })
    .await;
    assert!(result.is_err());
    assert_eq!(calls.load(std::sync::atomic::Ordering::Relaxed), 3);
}
#[tokio::test]
#[ignore = "Public Apple HTTP and media download; opt in with SIDEB_MOTION_PROBE_CACHE"]
async fn live_graduation_clean_follows_official_explicit_motion() {
    let Ok(cache_dir) = std::env::var("SIDEB_MOTION_PROBE_CACHE") else {
        return;
    };
    let engine = super::super::Engine::new();
    let mut request = request();
    request.title = "Flashing Lights".into();
    request.artists = "Kanye West".into();
    request.album = Some("Graduation".into());
    request.album_id = Some("yt-graduation".into());
    request.duration_secs = Some(237);
    let asset = engine
        .prepare(request, "public-graduation-probe".into(), cache_dir)
        .await
        .unwrap()
        .expect("official explicit Graduation version exposes motion");
    assert_eq!((asset.width, asset.height), (1080, 1080));
    assert!(std::path::Path::new(&asset.local_path).is_file());
    println!("{}", serde_json::to_string(&asset).unwrap());
    engine.cancel("public-graduation-probe");
}

#[test]
fn malformed_other_versions_section_cannot_become_a_seven_day_absence() {
    let text = std::str::from_utf8(GRADUATION_CLEAN).unwrap();
    let unknown = text.replace(
        "other-versions - other-versions",
        "other-versions - unsupported-layout",
    );
    assert!(parse_album_document(unknown.as_bytes(), "1442845779").is_err());
    let missing_items = text.replace(
        "\"items\":[{\"id\":\"other-versions",
        "\"unknownItems\":[{\"id\":\"other-versions",
    );
    assert!(parse_album_document(missing_items.as_bytes(), "1442845779").is_err());
}
#[tokio::test]
async fn nested_unvisited_version_is_not_followed_or_cached_as_absent() {
    let original = graduation_clean();
    let calls = std::sync::atomic::AtomicUsize::new(0);
    let result = resolve_related_document(&original, |_| {
        calls.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        async {
            let mut alternate = graduation_explicit();
            alternate.payload = AlbumPayload::Absent;
            let mut nested = alternate.related[0].clone();
            set_related_id(&mut nested, "77");
            alternate.related.push(nested);
            Ok(alternate)
        }
    })
    .await;
    assert!(result.is_err());
    assert_eq!(calls.load(std::sync::atomic::Ordering::Relaxed), 1);
}

#[test]
fn primary_motion_survives_unknown_or_missing_related_section_items() {
    let text = std::str::from_utf8(GRADUATION_EXPLICIT).unwrap();
    let unknown = text.replace(
        "other-versions - other-versions",
        "other-versions - unsupported-layout",
    );
    assert!(matches!(
        parse_album_document(unknown.as_bytes(), "1451901307")
            .unwrap()
            .payload,
        AlbumPayload::Master(_)
    ));
    let missing_items = text.replace(
        "\"items\":[{\"id\":\"other-versions",
        "\"unknownItems\":[{\"id\":\"other-versions",
    );
    assert!(matches!(
        parse_album_document(missing_items.as_bytes(), "1451901307")
            .unwrap()
            .payload,
        AlbumPayload::Master(_)
    ));
    // Related sections may precede the primary header; parse ordering must not affect availability.
    let script = text
        .split_once('>')
        .unwrap()
        .1
        .split_once("</script>")
        .unwrap()
        .0;
    let mut root: Value = serde_json::from_str(script).unwrap();
    root["data"][0]["data"]["sections"]
        .as_array_mut()
        .unwrap()
        .reverse();
    let related = &mut root["data"][0]["data"]["sections"][0];
    related.as_object_mut().unwrap().remove("items");
    let html = format!("<script id=\"serialized-server-data\">{root}</script>");
    assert!(matches!(
        parse_album_document(html.as_bytes(), "1451901307")
            .unwrap()
            .payload,
        AlbumPayload::Master(_)
    ));
}
