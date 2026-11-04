# Validation and known limits — 0.6.0

## Recorded local evidence

The pre-publication 0.6.0 regression suite passed **273 checks**: 66 core/integration, 19 BKTR, 14 NACP, 94 utilities, 27 workflow/preparation and 53 UI-state checks. The utility suite includes 1,250 deterministic malformed-container/NCZ mutations; these are included cases, not 1,250 additional independent tests. Separately, 16 primary/supporting-text contrast combinations passed 4.5:1 (minimum measured 7.28:1).

Agent-operated native walkthroughs covered all seven tool screens, ten existing-library read-only content checks, mixed conversion outcomes, three collision-safe separate names, per-tool destination/result retention, synthetic game/update/add-on combination, update version preview, legacy-manifest joining, XCI savings/trim, recent results across relaunch, support-report export and optional-notification default off. Standard/high-contrast light/dark layouts were reviewed without changing global appearance settings.

An **8,589,934,715-byte** synthetic file was split through the UI, stopped with cleanup verified, retried, handed to Join and rejoined. Parts were 4,294,901,760 + 4,294,901,760 + 131,195 bytes. Independently streamed original/joined SHA-256 values matched. A separate actual-size boundary test and disposable mounted-network-volume tests covered conversion, trimming, splitting, joining and readback/publication. Personal file inventories and original test-machine paths are deliberately omitted from this public repository.

The processing suite exercises synthetic NCA rebuilding, original preservation, matching/ownership, content hashes, old/new BKTR tables, compressed title data, invalid keys, malformed/oversized/truncated inputs, missing parts, collisions/competing writers, cancelled work, changed input stamps and scoped UI states. Earlier local builds also received human-reported Android gameplay/version confirmation for several updated files; that is historical feedback, not a new public compatibility certification.

## Limits

- These are automated and agent-operated checks, **not independent human usability research**. A participant protocol is in UX-UAT-TASKS.md.
- No fresh commercial game/update rebuild or Android gameplay was performed for this public packaging pass.
- Content checks do not authenticate Nintendo signatures or establish game boot/playability. Emulator failures can occur with original files too.
- No complete VoiceOver traversal, Reduce Transparency assessment, notification-delivery matrix, independent security audit or all-macOS-version certification has been completed.
- Physical device removal during writes, power failure, actual disk exhaustion and every SMB/filesystem variation are not reproduced. Forced termination can leave temporary files.
- Tests and mutation cases are finite. No claim of all possible inputs/use cases or universal safety is made.
- Apple Silicon is supported; there is no tested Intel build, Apple notarization or signed-update infrastructure.

## Repeatable checks

Run `bash build.sh` then `bash test.sh` from a clean checkout on Apple Silicon. This creates synthetic fixtures and requires no private game/key data. See docs/DEVELOPMENT.md for optional resource-heavy checks. CI now runs native Intel regression tests and separately cross-builds/verifies the arm64 release on an Intel Mac runner. This replaces an Apple Silicon hosted job that twice failed to acquire a runner before any steps ran. It does not claim hosted Apple Silicon execution; only actual green workflow runs count as CI evidence.
