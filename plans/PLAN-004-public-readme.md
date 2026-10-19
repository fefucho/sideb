# Public GitHub README

- Status: public README and About published; six owner-supplied native macOS screenshots/captions published on main and verified on the public page.
- Goal: present Side B in plain English, with its origins, features, design, backend and meaningful upstream credits.
- Scope: README, relocation of the internal workflow guide and its links, project artwork, existing license notices and GitHub About metadata. No app/core changes or release-tag changes.
- References: existing README/AGENTS, FIX-088/089/130, apple/Resources/Credits.rtf, platform manifests and source; upstream Limusic and Kaset repositories.

## Steps

- [x] Check repository state, current documentation and upstream credits.
- [x] Preserve the internal guide under .agents and update entry points/links.
- [x] Write a public README with logo, downloads, features, design, backend and acknowledgments.
- [x] Preserve upstream notices and the project's already-declared GPL license.
- [x] Check links, image rendering, tone and scope; publish the reviewed documentation and About metadata.
- [x] Add the six native macOS screenshots supplied by the owner, with captions, platform labels and full-resolution links.
- [x] Verify the expanded GFM gallery, publish the scoped documentation/images and check the public page and image URLs.

## Verification

Review Markdown/image rendering and relative links. Check descriptions against current source and package requirements; do not advertise upstream features that Side B does not expose. No application build/tests are needed for this documentation-only change. Keep release CI results separate.

## Results

- FIX-154. 97 relative links/anchors checked across the public page, internal guide and active indexes. Icon matches the app asset byte for byte. GitHub's GFM renderer confirms six sections, one requirements table and the icon; internal screenshot/workflow comments do not render.
- GPL text copied from GNU and Kaset MIT notice copied from upstream, retaining its2025 sozercan copyright; manifests already declare GPL-3.0-or-later. No app/core/license-term changes.
- GitHub About now describes both platforms and the artwork/lyrics/Genius focus. Topics: youtube-music, music-player, macos, windows, rust, swiftui, tauri, svelte; API state verified.
- Initial FIX-154 screenshot status: inspected existing QA/bug images, none appropriate as current public app screenshots. Directory and insertion point prepared without broken image links or published account data. The owner-supplied gallery below completes this work later.
- Published in source commit45a47d3 on main. Public GitHub page checked in a background browser: centered rounded icon/header, introduction, features, download table, backend and acknowledgments render; GitHub recognizes the root GPL license. Screenshot evidence saved locally at windows/.cache/release-tools/public-readme.png (ignored). Internal guide compared against the previous README: preserved exactly apart from heading/introduction and relocated links. No app/core edits or new build.

## Screenshot gallery — 2026-10-19

FIX-226 completes the optional screenshot work from FIX-154 at the owner’s request. Six original PNG captures (3248×2122, unchanged bytes) show Home/sidebar, fullscreen/queue, synced lyrics, Genius annotations, album details and Home with the sidebar collapsed. All are explicitly labeled macOS; the README retains its English voice and adds a Screenshots jump link. Source app/core and release 1.2.6 are unaffected. Published in 97fb18db84cdc61ced5353c41354bdb94eafbcb1 on main. Local links and alt text validated; GitHub GFM renders all six images. Public repository page inspected without signing in: six complete images at their original dimensions and all captions/navigation visible. Six image URLs read from the page were downloaded without authentication and compared byte for byte/SHA256 with the supplied captures (23871222 bytes total). Proof and reports are kept locally under builds/documentation/readme-gallery: github-gallery.png, image-verification.json, browser-images.json and public-verification.json. No application build/tests were run or required.
