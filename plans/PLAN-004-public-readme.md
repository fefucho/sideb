# Public GitHub README

- Status: public copy and internal-guide migration reviewed; publishing documentation. Optional native screenshots pending.
- Goal: present Side B in plain English, with its origins, features, design, backend and meaningful upstream credits.
- Scope: README, relocation of the internal workflow guide and its links, project artwork, existing license notices and GitHub About metadata. No app/core changes or release-tag changes.
- References: existing README/AGENTS, FIX-088/089/130, apple/Resources/Credits.rtf, platform manifests and source; upstream Limusic and Kaset repositories.

## Steps

- [x] Check repository state, current documentation and upstream credits.
- [x] Preserve the internal guide under .agents and update entry points/links.
- [x] Write a public README with logo, downloads, features, design, backend and acknowledgments.
- [x] Preserve upstream notices and the project's already-declared GPL license.
- [x] Check links, image rendering, tone and scope. GitHub About description/topics updated; documentation publication follows.
- [ ] Add current native screenshots when suitable images are available. Existing QA fixtures/bug reports are not presentation screenshots.

## Verification

Review Markdown/image rendering and relative links. Check descriptions against current source and package requirements; do not advertise upstream features that Side B does not expose. No application build/tests are needed for this documentation-only change. Keep release CI results separate.

## Results

- FIX-154. 97 relative links/anchors checked across the public page, internal guide and active indexes. Icon matches the app asset byte for byte. GitHub's GFM renderer confirms six sections, one requirements table and the icon; internal screenshot/workflow comments do not render.
- GPL text copied from GNU and Kaset MIT notice copied from upstream, retaining its2025 sozercan copyright; manifests already declare GPL-3.0-or-later. No app/core/license-term changes.
- GitHub About now describes both platforms and the artwork/lyrics/Genius focus. Topics: youtube-music, music-player, macos, windows, rust, swiftui, tauri, svelte; API state verified.
- Native screenshot selection remains optional/pending: inspected existing QA/bug images, none appropriate as current public app screenshots. Directory and insertion point prepared without broken image links or published account data.
