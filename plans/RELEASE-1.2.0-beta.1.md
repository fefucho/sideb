# Side B 1.2.0 — macOS & Windows Feature Parity

- Status: delivered under FIX-162; repeated prompt resolved by FIX-163 using numeric tag v1.2.0 on the same release. Published packages remain Mac build-0074 (584 tests) and Windows CI (646 tests); hardened comparison verified in local Mac build-0075 (587 tests) and five real Rust module tests. No new native packages published.
- Version: 1.2.0, public build13, current tag v1.2.0 (original delivery tag v1.2.0-beta.1 retained as a source ref). Same published/Latest/non-prerelease release409175343; six assets. All current and earlier versions remain betas; numeric tag alignment does not change this status.
- Scope: current reviewed Apple/Windows integrations and attachment to the existing release. The published tag remains at 9594f47; Windows is built from that CI revision and its sources/core are unchanged by the Mac follow-ups. Mac package comes from977d436; sanitized per-platform provenance is published in SideB-build-info.json. No protected core changes.
- Authorization: user requested release preparation, compilation on GitHub, beta publication, English release information, and a feature-parity release title.
- References: FIX-132–151, PARIDAD, RELEASE-1.1.8 and official [Xcode 27 runner](https://github.com/actions/runner-images/issues/14404).

## Delivery checklist

- [x] Confirm published v1.1.8 and local build12; select beta1.2.0/build13.
- [x] Prepare English release notes, including platform-specific options and validation limits.
- [x] Align Windows manifests and add a joint Mac/Windows release workflow.
- [x] Check source, version/package regression tests and outgoing commits; exclude local artifacts/secrets. Explicit staged paths reviewed before commit.
- [x] Commit and push the authorized release sources to main, then dispatch the GitHub workflow at that revision.
- [x] Record workflow/build results and attach both verified packages/checksums to the release already published by the user; see final delivery below.

## Original workflow policy and preparation (historical)

Both platforms use the numbered build runner. Mac requires xcode-27/Apple Silicon and native Swift tests. Windows requires MSVC2022, pinned libmpv/Vulkan, tests, standalone ZIP and NSIS setup built from the same executable. The release stays a draft if either platform fails; partial artifacts/logs remain available in Actions. No Latest promotion; this remains a beta. Windows volume/annotation options are platform-specific; feature parity here describes the shared client feature set, not identical native implementations.

The previous local Windows build0012 is compiled with646 passing tests and a verified rounded PE icon, but predates the version bump. Its binaries are not relabeled as this beta. Mac's recent12 Swift regressions passed locally in FIX-156/build-0070; the hosted CI rerun is still required.

## Preparation verification

FIX-152 / PAR-026: six release-validation regressions and real beta preflight passed. Official actionlint1.7.12 passed with the documented xcode-27 label added to its local configuration; shellcheck/pyflakes were unavailable. Tauri CLI supports packaging without rebuilding/binary patching. Cargo metadata --locked confirms the Windows package at1.2.0. Source diffcheck clean; origin/main has no outgoing checkpoint commits. Final commit and workflow links are recorded below when available.

## Hosted build attempts

- Source834395d: [run38081906898](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/actions/runs/38081906898), draft created with requested English title/prerelease flag. Windows failed before compilation: nested legacy PowerShell lacked Get-FileHash; diagnostics artifact11680492662 preserved. The incomplete attempt is stopped before retry; no packages published. FIX-153 corrects shell selection. GitHub did not create the draft's tag automatically, so the pipeline now creates/verifies it explicitly with its workflow token.
- Retry preparation:16 build/release tests passed,1 Mac-only fixture skipped on Windows; actionlint/diffcheck passed. Only this task's unpublished empty beta draft/tag is replaced to point at corrected source; published v1.1.8 remains unchanged.
- Corrected source9594f4721c3e467a5b7f201392febc849079250b: [run38082175075](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/actions/runs/38082175075). Preparation succeeded; both native jobs started. [Current draft](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/releases/tag/untagged-cd71356acef7f50feede) title is **Side B 1.2.0 — macOS & Windows Feature Parity**, isDraft/isPrerelease both true, targetCommitish and actual beta tag both match9594f47. GitHub Latest independently confirmed v1.1.8; this delivery label does not mean the app is stable. Joint publication is automatic only after both build/package/hash jobs pass; otherwise this draft stays unpublished. Diagnostics and final results are available through the run link; no completed native build is claimed while jobs are running.
- Subsequent observation during the public README task: macOS compiled its test targets but XCTest reported10 assertions in existing HomeFeedScrollTests.swift lines125/128/131. They compare floating-point dimensions exactly (e.g.959.9999999999999 vs960); no product regression is inferred solely from these differences. [Mac diagnostics](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/actions/runs/38082175075/artifacts/11681207345) retained. Windows still in verification/build; joint publication is blocked by the Mac result. No test weakening/source edits or release-tag changes were made as part of the README task. User informed; fixing/retrying native CI remains pending.

- Final CI result (2026-10-10): Windows verification/build/package succeeded; macOS failed in one existing geometry test with10 exact floating-point comparison failures, so joint publication was skipped. Draft still has no assets and remains a prerelease. FIX-155 corrects the earlier stability wording: all versions remain beta; title is Side B 1.2.0 — macOS & Windows Feature Parity. Test repair/retry remains pending.

- User will repair/verify the geometry test on the Mac. The display title and English notes were updated on the existing draft and re-read through GitHub: isDraft/isPrerelease both true, zero assets; no publication or retagging. FIX-155 checks:6 release-helper tests passed, actionlint passed, diffcheck clean.

## Local Mac repair and verification — 2026-10-10

FIX-156: fetched main through 6c162f7 without conflicts. The original sources compiled in local build-0069 with 574 passing tests. CI's ten failures are exact comparisons of floating-point dimensions in one existing AppKit test; the production geometry and that test were unchanged by the fetched commits.

Only the three affected test comparisons now use a 0.000001-point tolerance, retaining all eleven widths and hosting/row invariants. Focused release HomeFeedScrollTests: 8 XCTest passed. Numbered build-0070: 182 Rust, 140 XCTest and 252 Swift Testing passed (574 total; 7 live Rust ignored), including the ten metadata and two greeting regressions. Release arm64/SDK 27.0, minimum macOS 15, ad hoc signature, ten artifact hashes and unchanged sources during build verified. Source change is test-only; closure documentation followed the build.

Hosted CI has not rerun this patch. No push, dispatch, tag/draft mutation or publication was performed in this local repair; joint release delivery and native UI/audio acceptance remain pending.

Read-only GitHub recheck: Windows job succeeded and its [release-windows artifact](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/actions/runs/38082175075/artifacts/11681363325) is available (not expired). Joint publication was skipped; the beta draft still has zero assets. Published v1.1.8 has only SideB-macOS.zip, which explains the missing Windows download on Releases.

## Review requested before upload

FIX-157/158 port Windows' artwork/contrast/neutral Genius annotation colors and correct the Mac queue duration/grip alignment. Local build-0071 passed 578 tests (182 Rust, 140 XCTest, 256 Swift Testing), with native isolated renders, 692 ES/EN keys, arm64/SDK 27.0, verified signature/hashes and stable sources. Windows/core unchanged; physical acceptance and hosted CI still pending. No push, draft/tag changes or publication performed during this review.

## Attach packages to the published release — user request 2026-10-10

FIX-159/160 closed queue feedback in build-0073: 582 passing tests, preserving resolved duration after skip/back/restore and Like across rows. FIX-161 then restricts the Mac updater to SideB-macOS.zip, avoiding the Windows portable ZIP regardless of API asset order.

Initial recheck found release409175343/v1.2.0-beta.1 already published, Latest and non-prerelease, with no assets. The user explicitly requested adding Mac and Windows to this release. The original draft-only workflow was not rerun; the published tag and version1.2.0/build13/flags remain unchanged.

Windows packages recovered from run38082175075/release-windows artifact11681363325. Diagnostics compiled/sourceChangedDuringBuild false at9594f47, version1.2.0/build13; 280 frontend + 366 native = **646 passing tests**, 14 Rust live ignored, check0/0. Setup/portable checksums verified, and all four portable runtime hashes match BUILD.json. Production core/Windows source diff against977d436 is empty (documentation-only differences excluded). No new Windows build, native UI/account/audio acceptance or binary relabeling claimed.

Mac source FIX-156–161 committed/pushed as977d436f84d8337fa279775d7887ced803d37c00 before final numbered build. Build-0074 compiled from that clean, stable revision: **584 passing tests** (182 Rust/140 XCTest/262 Swift Testing;7 live Rust ignored), 692 ES/EN keys, arm64/SDK27.0/minimum macOS15. Original app and re-extracted ZIP both pass signature and ten artifact hashes. Signature remains ad hoc, without notarization. Documentation closure follows the build.

- [x] Recover and verify Windows installer, portable package and runtime hashes.
- [x] Preserve the existing release's tag/version/flags and prepare accurate platform-specific notes.
- [x] Commit reviewed Mac fixes, build the final Mac package and push its source revision.
- [x] Upload Mac first for legacy clients, then Windows, checksums and sanitized build provenance; verify GitHub asset digests and Latest API selection.

FIX-162: [published release](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/releases/tag/v1.2.0-beta.1), ID409175343. Six assets are uploaded and each remote size/digest matches staging:

| Asset | SHA-256 |
|---|---|
| SideB-macOS.zip | daa462a66d1ac3fe665a4de5c6f511df809f2a18b04a5e7f22e7bf05302d1f06 |
| SideB-Windows-x64-setup.exe | c39aa062b4ee7c8214169ff646cdbe3c6854227a0670914a9d7f177e50e86dc6 |
| SideB-windows-x64.zip | 0cff7be4d7bd448630136cdcf0286921d54bb0f2afc1dd56f96f77fa4129f48c |
| SideB-macOS-SHA256.txt | 03452ace9fc193d42cc781a4f681ab1d86d7bd42988a55b4b214501d46ff026f |
| SideB-Windows-x64-SHA256.txt | 822ee5eab257d52e48258790d5f86e686849dc63489d173ef0b8a76546324556 |
| SideB-build-info.json | 0e0bfa2d81c70a87bbb0081c9b5ddf8ee38e5aac1e7a7ab5ef1b2d9707e5531e |

Portable Windows bytes match CI exactly; its asset filename uses lowercase windows to preserve ordering alongside the Mac ZIP for legacy clients. The checksum filename entry and sanitized provenance were updated accordingly. Latest returns SideB-macOS.zip as its first ZIP, and the new Mac selects that package explicitly. Published body matches the prepared English notes. Tag and targetCommitish still point to9594f4721c3e467a5b7f201392febc849079250b; draft=false/prerelease=false remain the existing GitHub flags. All app versions remain beta.

## Follow-up noted during initial delivery (resolved by FIX-163 below)

The actual Swift and Rust numeric comparison functions both return true for v1.2.0-beta.1 >1.2.0. This corrects the earlier assumption that the unchanged public version prevents an update prompt: the beta tag can be offered repeatedly after installation. Public notes recommend downloading the refreshed Mac ZIP directly and choosing Skip this version if the prompt returns. Normalize beta tags in both clients in a follow-up; this delivery does not modify version comparison or claim a new Windows build. Future packaging should retain the legacy-compatible ZIP order. Physical UI/account/audible playback acceptance remains pending.

## Repeated update prompt — FIX-163 / 2026-10-10

User reports the repeated installed1.2.0 → remote1.2.0-beta.1 prompt in both clients and supplies a Mac screenshot. FIX-163 compares the numeric bundle/Cargo version before release labels/build metadata, preserving the original release identity for display/skip. Invalid segments are rejected rather than dropped. Rust comparison is a pure production module with direct tests.

To fix already-installed clients without a forced reinstall, align the existing release409175343 to v1.2.0 at the same9594f47 target. Preserve original beta tag as a source ref, all package bytes/asset IDs, publication flags and beta notice. Update current English notes, sanitized provenance and workflow default; keep the original delivery records as history. GitHub's [Update a release API](https://docs.github.com/en/rest/releases/releases#update-a-release) supports changing tag_name at the explicit target revision.

- [x] Reproduce the bug with exact legacy Swift/Rust functions and prove the numeric tag stops it while preserving updates from1.1.8.
- [x] Implement comparison in both shells and regression coverage; five standalone tests of the production Rust module passed.
- [x] Complete Swift/Windows frontend verification and numbered Mac build.
- [x] Apply/recheck the same-release tag correction, unchanged binary digests/flags and Latest behavior.
- [x] Close FIX-163/PAR-026 and record final verification; source changes are saved/pushed with their FIX IDs after the stable build.

Verification prerequisite FIX-164: frontend check0/0 succeeded, but initial frontend suite had278 pass/1 fail/1 native fixture skipped on Mac. Failure was a stale generated Windows translation catalog after FIX-157's four shared keys; regenerate692 keys and replace the historical fixed-count assertion with the existing exact-source check. No native Windows build or new package publication is implied.

Final FIX-163 verification:15 Swift updater tests,5 standalone tests of the production Rust comparison module,6 release-helper tests and real v1.2.0 preflight passed. Numbered Mac build-0075:182 Rust +140 XCTest +265 Swift Testing = **587 passed**;7 live Rust ignored. compiled/sourceChangedDuringBuild false, source10a9a30 plus reviewed local changes, four steps,692 keys, ten artifact hashes, signature and arm64/SDK27.0/minimum15 verified. Documentation closure followed the build. Core/bindings unchanged; no app automatically opened/replaced.

FIX-164 recheck:692 shared keys verified, frontend279 passed/0 failed/1 Windows-only fixture skipped on Mac; check0/0 and frontend build passed. The initial failing attempt is preserved above. Native Windows/Tauri build, installer execution and physical UI/account/audio were not repeated for this correction.

Public unauthenticated Latest now returns v1.2.0 and release409175343 at unchanged9594f47. Original beta ref also remains9594f47. Five binary/checksum assets retain IDs/sizes/digests; only sanitized provenance JSON was replaced to record current/original tags. Notes match release-notes/1.2.0.md, download URLs use the new tag and downloaded provenance matches byte-for-byte. Mac remains first ZIP. Original public Mac/Windows package bytes and their source revisions are unchanged, so current users can dismiss the stale modal and check again without reinstalling. Future binary updates need a higher numeric installed version.

Local verification app: builds/macos/build-0075/Side B.app. Current [release link](https://github.com/fefucho/SIDE-B-CLIENT-NATIVE/releases/tag/v1.2.0); historical links/tags above record the original delivery.
