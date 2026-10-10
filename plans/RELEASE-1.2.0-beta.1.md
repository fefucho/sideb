# Side B 1.2.0 — macOS & Windows Feature Parity

- Status: user requests attachment of both verified packages to the existing published release. Windows CI packages recovered and hash-verified; macOS follow-up fixes passed build-0073, with platform selection fix FIX-161 awaiting final numbered build and upload.
- Version: 1.2.0, public build 13, tag v1.2.0-beta.1. GitHub now marks this release published/Latest/non-prerelease, with zero assets before this request. All current and earlier versions remain betas; preserve the user's existing release/tag/flags.
- Scope: current reviewed Apple/Windows integrations and attachment to the existing release. The published tag remains at 9594f47; Windows is built from that CI revision and its sources/core are unchanged by the Mac follow-ups. Mac source revision and package provenance will be recorded. No protected core changes.
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

FIX-159/160 closed queue feedback in build-0073: 582 passing tests, preserving resolved duration after skip/back/restore and Like across rows. Before uploading both platforms, FIX-161 restricts the Mac updater to SideB-macOS.zip, avoiding the Windows portable ZIP regardless of API asset order. A final numbered Mac build is required for this additional correction.

Read-only recheck: release409175343/v1.2.0-beta.1 is already published, Latest and non-prerelease, with no assets. The user explicitly requests adding Mac and Windows to this release. Do not rerun the original draft-only workflow or replace a published tag. Keep version1.2.0/build13; existing1.2.0 installations need a manual refreshed download because updater comparison uses the version, not the local build number.

Windows packages recovered from run38082175075/release-windows artifact11681363325. Diagnostics compiled/sourceChangedDuringBuild false at9594f47, version1.2.0/build13; 280 frontend + 366 native = **646 passing tests**, 14 Rust live ignored, check0/0. Setup/portable checksums verified, and all four portable runtime hashes match BUILD.json. Production core/Windows source diff against this revision is empty (documentation-only differences excluded). No new Windows build, native UI/account/audio acceptance or binary relabeling claimed.

- [x] Recover and verify Windows installer, portable package and runtime hashes.
- [x] Preserve the existing release's tag/version/flags and prepare accurate platform-specific notes.
- [ ] Commit reviewed Mac fixes, build the final Mac package and push its source revision.
- [ ] Upload Mac first for legacy clients, then Windows, checksums and sanitized build provenance; verify GitHub asset digests and Latest API selection.

FIX-162 records the actual delivery result after uploads complete.
