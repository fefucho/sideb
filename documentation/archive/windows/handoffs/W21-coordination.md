> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W21 coordination — 2026-09-30

## Root Home/album/artist (thread 01a0ebab-deea-7152-95d7-cfdae6a6f6f1)

**Shared files ceded now:** `windows/src/routes/+page.svelte`, `windows/src-tauri/src/lib.rs`, `windows/src/lib/types.ts`, Sidebar, PlayerBar. My agents are done there. Preserve Home continuation + album/artist/catalog navigation and callbacks currently integrated in +page. I will make no further edits to those files while account integration proceeds.

- Home now reads continuation, deduplicates using sectionIdentity, prefetches at most 3 pages/12s, guards request identity/session and has an intersection sentinel/manual retry.
- Album/artist/catalog components are integrated with navigation history and scroll restoration. Existing play_song snapshot stays authoritative; new playCollection does one-shot shuffled queue, get_artist_radio uses core.get_next (NOT get_playlist).
- Preserve bridge get_home_continuation/get_artist/get_browse_grid/get_artist_radio and complete DTO fields.
- toggle_album_library/set_artist_subscription already use your account_core/auth_generation/auth_operation pattern.
- Artist and album callbacks: toggleAlbumLibrary/toggleArtistSubscription currently standalone; you may connect them to account controller to keep cache coherent.
- Completed build frontend at 14:42; latest CSS tweaks afterward require final web build.
- Rust cargo build currently running in exec session 92561 (VS2022, SIDEB_MPV_DIR). I will only wait for it, not launch/restart Side B. If your lib.rs changes happen before it finishes, do final build after integration.
- I touched AccountTrackTable and PlaylistDetailView solely to repair missing type contract with optional local types; LibraryView JSX uses AccountTrackTable matching its existing import. Agent finished, no further touches there.
- Check failures now only account/controller.ts missing DTO fields and LibraryView warnings; these are your scope. No diagnostics from Home/album/artist currently.

**My exclusive component edits:** HomeView, HomeShelf, HomeCard, CompactSongCard, home/presentation.ts, detail/AlbumDetailView, DetailHeader, ArtistDetailView, CatalogView, DescriptionModal, TrackTable (except shared compatibility if you require it). TrackTable changed now has optional flush prop for artist alignment and no explicit badge (SongItemRecord has no explicit). Shared TrackTable is otherwise available to you, preserve flush.

Please report via this file when account integration/build/relaunch is ready. I will inspect and test Home/album/artist after you release runtime; no simultaneous relaunch/UI automation. I asked user for permission to message your chat; until their reply I am using this handoff only.
