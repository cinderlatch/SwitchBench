# Changelog

## Unreleased

- Clarified upstream acknowledgements and named SAK and Switch Game Merge Utility as the primary inspirations, with the maintainer’s Mac/Codex origin story.
- Moved hosted regression testing to Intel macOS and added explicit arm64 cross-compilation/architecture verification after repeated hosted Apple Silicon capacity failures.

## 0.7.0-windows.1 — Windows preview

- Added a native Windows 11 x64 interface with seven tools, previews, progress, and cancellation.
- Ported the shared processing engine and bundled helpers to Windows.
- Added a portable package and Windows build workflow with synthetic checks.

## 0.6.0 — initial public release

Previously developed locally as SwitchPatch, then SwitchBench. Historical version numbers are retained for continuity; earlier private builds are not represented as public releases.

- Seven native tools: Update, Check, Combine, Convert, Split, Join and Shrink.
- Shared task layout, lightweight preparation previews and per-file outcomes.
- Batch checking and bounded, cancellable folder imports.
- Clear no-change states, direct recovery, safe separate names and unfinished-only retry.
- Per-tool save folders, retained session results and persistent recent results.
- Contextual output handoff, keyboard shortcuts and compact configured-key status.
- Monotonic aggregate progress, safe Stop cleanup and optional completion feedback.
- Local bounded reports, explicit export, contrast checks and accessibility labels.
- Existing helper pinning, network-safe publication, newer BKTR layouts and compressed-title handling retained.
- Public documentation, attribution, full modified helper source and Codex disclosure.

See QA-UAT.md for validation evidence and known limits.
