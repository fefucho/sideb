# Third-party notices

Side B builds on existing open-source work. These credits describe the foundations used by this project; they do not imply endorsement by upstream maintainers.

## Limusic

[Limusic](https://github.com/SimoHypers/limusic), by SimoHypers and contributors, is the source of the Rust backend foundations, including InnerTube, stream handling, SQLite storage, and PoToken work. Its original project is distributed under [GPL-3.0](https://github.com/SimoHypers/limusic/blob/master/LICENSE).

Side B's Rust workspace and Windows package already declare GPL-3.0-or-later. The GPL version3 license text is included in the root [LICENSE](LICENSE).

## Kaset

[Kaset](https://github.com/sozercan/kaset), by sozercan and contributors, provided an essential starting point and design inspiration for the macOS app. Its MIT copyright and permission notice are preserved in [docs/licenses/Kaset-MIT.txt](docs/licenses/Kaset-MIT.txt), copied from the [upstream license](https://github.com/sozercan/kaset/blob/main/LICENSE).

## Optional visual provider: Spotify Canvas

Both apps ship an optional, separable provider package, `extensions/spotify-canvas`, preinstalled but inactive and removable from Settings. It is an independent Rust executable (`sideb-spotify-canvas`, `.exe` on Windows) that talks to the host over JSON/stdio v1. It is MIT-licensed ([extensions/spotify-canvas/LICENSE](extensions/spotify-canvas/LICENSE)) and credits the Wolframe Team research (MIT) and SpotifyScraper (MIT) in [extensions/spotify-canvas/THIRD_PARTY_NOTICES.md](extensions/spotify-canvas/THIRD_PARTY_NOTICES.md), together with a summary of the licenses of the Rust crates compiled into the executable (all permissive: MIT, Apache-2.0, ISC, BSD, Zlib, Unicode-3.0, CDLA-Permissive-2.0). The same LICENSE and notices travel next to the executable inside both packages (`Contents/Resources/VisualProviders/spotify-canvas/` on macOS, `provider/spotify-canvas/` on Windows).

Spotify, Spotify Canvas, their marks and videos belong to their owners and are not licensed by these notices. The provider uses Spotify's unofficial Web Player interfaces, which Spotify's terms may not allow; it is off until the user signs in and enables it. Side B is not affiliated with or endorsed by Spotify.

## Libraries and services

The Windows app bundles [Inter 4.1](https://github.com/rsms/inter/releases/tag/v4.1), by Rasmus Andersson and the Inter Project Authors, under the SIL Open Font License 1.1. The unmodified normal and italic variable WOFF2 files and their [license](windows/static/fonts/inter/LICENSE.txt) are included in the app's local assets; no font download is required at runtime.

Side B also uses RustyPipe, UniFFI, Tauri, Svelte, mpv/libmpv, SQLite, and other dependencies declared in its package manifests and lockfiles. These retain their respective licenses. Windows portable packages include the Vulkan runtime license alongside the runtime.

YouTube Music supplies the catalog and audio; lyric providers and Genius supply their corresponding text and song information. Music, artwork, trademarks, and provider content remain the property of their respective owners.
