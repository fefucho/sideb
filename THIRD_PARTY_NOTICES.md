# Third-party notices

Side B builds on existing open-source work. These credits describe the foundations used by this project; they do not imply endorsement by upstream maintainers.

## Limusic

[Limusic](https://github.com/SimoHypers/limusic), by SimoHypers and contributors, is the source of the Rust backend foundations, including InnerTube, stream handling, SQLite storage, and PoToken work. Its original project is distributed under [GPL-3.0](https://github.com/SimoHypers/limusic/blob/master/LICENSE).

Side B's Rust workspace and Windows package already declare GPL-3.0-or-later. The GPL version3 license text is included in the root [LICENSE](LICENSE).

## Kaset

[Kaset](https://github.com/sozercan/kaset), by sozercan and contributors, provided an essential starting point and design inspiration for the macOS app. Its MIT copyright and permission notice are preserved in [docs/licenses/Kaset-MIT.txt](docs/licenses/Kaset-MIT.txt), copied from the [upstream license](https://github.com/sozercan/kaset/blob/main/LICENSE).

## Libraries and services

Side B also uses RustyPipe, UniFFI, Tauri, Svelte, mpv/libmpv, SQLite, and other dependencies declared in its package manifests and lockfiles. These retain their respective licenses. Windows portable packages include the Vulkan runtime license alongside the runtime.

YouTube Music supplies the catalog and audio; lyric providers and Genius supply their corresponding text and song information. Music, artwork, trademarks, and provider content remain the property of their respective owners.
