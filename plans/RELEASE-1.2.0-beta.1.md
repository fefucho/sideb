# Side B 1.2.0 Beta — macOS & Windows Feature Parity

- Status: corrected GitHub run compiling both platforms; draft created, release not yet published.
- Version: 1.2.0, public build 13, tag v1.2.0-beta.1, GitHub prerelease; keep stable/Latest at v1.1.8.
- Scope: current reviewed Apple/Windows integrations and joint packaging. No protected core changes.
- Authorization: user requested release preparation, compilation on GitHub, beta publication, English release information, and a feature-parity release title.
- References: FIX-132–151, PARIDAD, RELEASE-1.1.8 and official [Xcode 27 runner](https://github.com/actions/runner-images/issues/14404).

## Delivery checklist

- [x] Confirm published v1.1.8 and local build12; select beta1.2.0/build13.
- [x] Prepare English release notes, including platform-specific options and validation limits.
- [x] Align Windows manifests and add a joint Mac/Windows release workflow.
- [x] Check source, version/package regression tests and outgoing commits; exclude local artifacts/secrets. Explicit staged paths reviewed before commit.
- [x] Commit and push the authorized release sources to main, then dispatch the GitHub workflow at that revision.
- [ ] Record workflow/draft links and build results. Publish only after both packages and their checksums are available.

## Packages and limits

Both platforms use the numbered build runner. Mac requires xcode-27/Apple Silicon and native Swift tests. Windows requires MSVC2022, pinned libmpv/Vulkan, tests, standalone ZIP and NSIS setup built from the same executable. The release stays a draft if either platform fails; partial artifacts/logs remain available in Actions. No stable-channel promotion. Windows volume/annotation options are platform-specific; feature parity here describes the shared client feature set, not identical native implementations.

The previous local Windows build0012 is compiled with646 passing tests and a verified rounded PE icon, but predates the version bump. Its binaries are not relabeled as this beta. Mac's recent12 Swift regressions must execute in CI; no local Mac compilation is claimed.

## Preparation verification

FIX-152 / PAR-026: six release-validation regressions and real beta preflight passed. Official actionlint1.7.12 passed with the documented xcode-27 label added to its local configuration; shellcheck/pyflakes were unavailable. Tauri CLI supports packaging without rebuilding/binary patching. Cargo metadata --locked confirms the Windows package at1.2.0. Source diffcheck clean; origin/main has no outgoing checkpoint commits. Final commit and workflow links are recorded below when available.

## Hosted build attempts

- Source834395d: [run38081906898](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/actions/runs/38081906898), draft created with requested English title/prerelease flag. Windows failed before compilation: nested legacy PowerShell lacked Get-FileHash; diagnostics artifact11680492662 preserved. The incomplete attempt is stopped before retry; no packages published. FIX-153 corrects shell selection. GitHub did not create the draft's tag automatically, so the pipeline now creates/verifies it explicitly with its workflow token.
- Retry preparation:16 build/release tests passed,1 Mac-only fixture skipped on Windows; actionlint/diffcheck passed. Only this task's unpublished empty beta draft/tag is replaced to point at corrected source; stable v1.1.8 remains unchanged.
- Corrected source9594f4721c3e467a5b7f201392febc849079250b: [run38082175075](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/actions/runs/38082175075). Preparation succeeded; both native jobs started. [Current draft](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/releases/tag/untagged-38d582d7872d5cfcc063) title is **Side B 1.2.0 Beta — macOS & Windows Feature Parity**, isDraft/isPrerelease both true, targetCommitish and actual beta tag both match9594f47. Stable Latest independently confirmed v1.1.8. Joint publication is automatic only after both build/package/hash jobs pass; otherwise this draft stays unpublished. Diagnostics and final results are available through the run link; no completed native build is claimed while jobs are running.
