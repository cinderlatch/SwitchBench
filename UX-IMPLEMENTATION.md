# SwitchBench 0.6.0 — UX implementation record

The recommendations in UX-AUDIT.md are implemented through the existing seven tools. No tool hub or extra category hierarchy was added.

| Recommendation | Implementation |
| --- | --- |
| Preview before processing | Cancellable preparation reads identities/versions when keys are available, matches updates/add-ons, predicts output names, reports known sizes/savings/part counts/checksum availability, checks name conflicts and space, and snapshots input sizes/timestamps. No full content hash scan is required just to prepare a task. |
| Direct recovery | Each task row carries a reason and specific key, additional-key, destination, separate-name, existing-file, parts-folder or input recovery controls. Detailed helper output remains optional. |
| Batch results | Ready, Working, Saved, Checked, No Change Needed, Needs Attention and Stopped states; per-file completion and aggregate summaries; retry processes only unfinished work. |
| Healthy no-ops | Standard NSPs, already-trimmed XCIs and small files are classified before work as No Change Needed. |
| Shared structure | All seven tools use the same compact file/preparation/destination/action structure and the same selection controls. Update and Combine retain their distinct matching/grouping behavior. |
| Accurate progress | Fixed per-part split arithmetic; overall progress stays monotonic; current file, queue position, phase and elapsed time stay separate. Indeterminate phases remain honest rather than inventing a time estimate. Stop explains unfinished-copy cleanup. |
| Local destinations | Each tool remembers its own folder. Changing one leaves other tasks and completed outputs intact. Explicitly creating another copy chooses a separate name. |
| File-first hierarchy | Valid key configuration is a compact menu; setup expands when missing. Actual game names/versions lead inspection and matching rows. |
| Clear actions/results | Singular/plural operation labels, one primary result per row, technical counts in details and a concise overall footer. Contextual Update/Combine explanation and links stay available. |
| Accessibility/density | System semantic text and accent colors; consistent Return/Escape, File menu and tool shortcuts, labelled controls, keyboard/error focus and accessibility completion announcements. Compact default sizing with window migration. |
| Multi-file checking | Multiple files and folders can be inspected and checked in one task with individual outcomes. |
| Folder imports | Supported/ignored/duplicate summary, bounded scanning, background collection and Stop; cancelled or unsupported replacement selection preserves the previous task. |
| File handoff | Contextual Use File In menu on saved and recent results. File types determine useful next tools; split parts/folders route to Join. |
| Completion feedback | Background Dock badge, cleared on activation. Optional notification opt-in lives in Settings and is never requested during ordinary first use. |
| Reports | Bounded owner-only local reports in Application Support/SwitchBench/Reports; explicit support report export. Reports are separate from game outputs. |
| Recent results | Bounded local history of completed outputs/checks, surviving relaunch; reveal/use actions; clearing history leaves files untouched; missing drives are explained. |
| Human validation | Independent participant protocol supplied in UX-UAT-TASKS.md. Actual human sessions need participants and are not represented as completed agent testing. |

The processing helpers and update-materialization algorithm retain their existing behavior. A new private publication wrapper allows chosen/separate output names and preserves no-overwrite/readback guarantees. Preparation does not guarantee an input or destination cannot change later: execution rechecks input stamps and performs the original processing/integrity checks.

No screen claims that metadata or content checks prove emulator gameplay. Older split files without original checksums retain the more limited container/missing-part validation description. Estimated space and unknown patched output size are labelled as such.

Native validation results and remaining platform/accessibility limits are recorded in QA-UAT.md before release. Independent human use and Android gameplay are not claimed by code or state tests.
