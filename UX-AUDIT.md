# SwitchBench 0.5.2 — usability and human-centered design audit

4 November 2026 · Recommendations only; no app implementation changes made during this audit.

## Assessment

SwitchBench has a useful, focused set of tools and a much clearer navigation structure than earlier iterations. Its remaining usability problems mainly concern task preparation, interpreting outcomes, and recovering from problems. Users still need to understand too much about the processing model to confidently answer: Have I chosen the right tool? Are these the right files? What will I get? What happened to each file? What should I do next?

The strongest next iteration would use the current seven tools, one consistent task layout, a clear preview of the intended result, and per-file outcomes with direct recovery. More navigation or a larger feature list would not address those problems.

## Method and limits

Reviewed the installed 0.5.2 native interface, screenshots, accessibility trees, and the implementation of input selection, progress, result reporting, preferences and recovery. Walked through the real Check Files experience with an existing Final Fantasy game: information reading, full content verification and its completed state. This was read only; the original file was unchanged. Removed the audit selection and restored the previously selected Shrink XCI Files tool afterward.

Inspected Update, Combine, Split and Shrink screen layouts directly. Other supported states were assessed from the current implementation and earlier acceptance evidence, rather than all being replayed with commercial game files during this audit. First-launch/no-key behavior, mixed batches and failure paths include code-review findings. These are distinguished below from live observations.

This is an expert evaluation, not independent usability research. No novice participants were observed, no quantitative usability score is claimed, and contrast, complete VoiceOver use, light appearance and alternate display configurations were not fully measured.

## Preserve

- Seven direct, equally weighted sidebar tools; no redundant All Tools page or ambiguous category headings.
- Last-used-tool restoration, with Check Files as a reasonable safe first-launch default.
- Original-file protection, explicit destination choice and no silent replacement of existing files.
- Native file pickers and drag/drop, including non-drag alternatives.
- Automatic game/update matching and contextual requests for additional keys.
- Technical identifiers behind disclosure controls.
- Stop with cleanup, retained tool selections within a session, and retry behavior that preserves completed work.
- Explicit distinction between checking stored data and establishing emulator gameplay compatibility.

Equal navigation importance does not require every screen to contain identical fields. Keys belong only in tools that require them; output-folder controls do not belong in a read-only check.

## Priority recommendations

### 1. Preview the result before processing — high priority

**Evidence:** Most utility inputs are displayed as filenames with little interpretation. Their main eligibility rules run when processing starts. A user can therefore wait for a job to discover a mismatched package, an unnecessary operation, a destination conflict or a missing part. Existing space and collision checks are valuable, but their outcomes are not assembled into a user-facing plan. This is principally a code-review finding.

**Change:** Add lightweight, cancellable preparation immediately after selection. Show what can be established reliably, without performing a full integrity scan or adding a modal confirmation:

- Update: game, selected update/version, pairing status and the new output name.
- Combine: one game, selected update and add-ons; explain that the update remains separate inside the package.
- Convert: source type and resulting NSP filename. Show an estimate/range when compressed output size is uncertain.
- Split: number of parts, maximum part size and destination folder.
- Join: discovered part count, missing parts and whether original checksums are available.
- Shrink: original size, resulting size and expected savings; identify already-trimmed files.
- Check: game identity/version, included content, and whether the content scan has run.

Display known required temporary space alongside available space. Label estimates honestly. Keep the main action available as soon as necessary preparation is complete; do not turn this into another wizard.

**Acceptance:** Before starting, a person can describe the resulting files and destination without reading technical details.

### 2. Make errors recoverable beside the affected file — high priority

**Evidence:** Multi-line failures become a generic message directing people to Details. Utility batches retain successful markers but no equally clear per-file failure explanation. Update rows also send failed users to Details. Most recovery therefore depends on a log. Shared app notices and additional-key flags can also outlive the individual tool/task that caused them. These are code-review findings supported by the earlier acceptance behavior.

**Change:** Each file should show a short reason and a relevant next action. Examples:

- “This update belongs to a different game.” → Remove Update / Choose Another.
- “A file with this name already exists.” → Show Existing File / Choose Folder / Save a Separate Copy.
- “Part 3 is missing.” → Show Parts Folder / Choose Another Part.
- “Not enough space for the new file and temporary work.” → Choose Folder.
- “This game needs additional keys.” → Choose Additional Key File.

Keep full diagnostics available as a secondary action. Do not enable silent replacement as an error-recovery shortcut. Scope notices to their task, and clear resolved notices.

**Acceptance:** Typical input and destination problems are recoverable without opening or interpreting a log.

### 3. Turn the file list into a useful batch-results list — high priority

**Evidence:** Utility results mainly consist of a global summary, Saved badges, a reveal action and Details. Partial failures are summarized by count; the person must investigate which files need attention. A disabled Saved button is also a weak end state. Code-review finding; native earlier acceptance confirmed successful markers and disabled completed actions.

**Change:** Use plain per-file states: Ready, Working, Saved, No Change Needed, Needs Attention and Stopped. Show an overall summary such as “7 saved · 1 already ready · 1 needs attention.” Offer Retry Unfinished Files, Show Saved Files and Choose New Files. Keep completed result entries available when a person begins another task; a full library manager is unnecessary.

**Acceptance:** In a mixed batch, people can identify every successful output and retry only unfinished items without producing accidental duplicates.

### 4. Treat unnecessary work as a normal outcome — high priority

**Evidence:** Already-standard NSPs, already-trimmed XCIs and files small enough not to require splitting currently throw errors. The explanation is useful, but the batch classifies these benign situations as failures. Code-review finding.

**Change:** Report “No conversion needed — already NSP,” “Already trimmed” or “Already small enough.” Mark the item complete as a skip, separate from both a newly created output and a damaged/unsupported file. Show this in the preparation preview where possible.

**Acceptance:** A batch with healthy files requiring no transformation does not imply those files are broken.

### 5. Use one shared task structure — high priority

**Evidence:** Update Games has numbered cards, Add via a menu, an extra Choose Files button, different spacing, and an Open Save Folder action. Other tools use an unnumbered file list and Show Saved Files after success. The discrepancy was visible in the live screen review.

**Change:** Share a compact structure across tools: purpose → files → preparation/result preview → destination when needed → primary action. Use the same file-selection controls, destination presentation, status area and reveal terminology. Keep Update-specific pairing and Combine-specific content selection within that structure. Avoid numbering routine saved settings as mandatory steps.

Place one obvious Choose Files action inside the empty drop area. After files are selected, use Add Files in the file-list header. A folder choice can be a secondary option where supported.

**Acceptance:** Learning file selection and output behavior in one tool transfers to the others.

### 6. Make progress trustworthy — high priority

**Evidence:** The live content check communicates a phase and Stop, which is useful. Code review also identifies a concrete split-progress problem: checking a part can take its bar to 100%, while saving the next part uses a lower fraction of total work. Other utility phase messages can replace the initial file-position message, obscuring which game is active. Most screens provide no time or transferred-byte context.

**Change:** Keep the current filename, queue position and operation phase visible independently. For example: “File 2 of 9 · FINAL FANTASY II” and “Checking the saved copy · 620 MB of 900 MB.” Use a monotonic overall progress bar, with separate phase progress if helpful. Only show a time estimate after enough stable throughput is available; use an honest activity indicator when a phase cannot be quantified. Explain a stalled/disconnected resource with a recovery action.

Keep Stop visible and explain that unfinished work for the current file is discarded, while completed outputs remain. Show Stopping only during actual cleanup.

Apple’s guidance favors accurate progress and concise descriptions, consistent placement and interruptibility: [Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators).

**Acceptance:** Progress never appears complete while more parts remain, and the person can always identify the active file and phase.

### 7. Keep destination changes local and preserve completed outcomes — high priority

**Evidence:** The save destination is shared across tools. Changing it clears completed markers/results in the active and cached utility states and clears Update statuses. People are not shown the full cross-tool effect. Code-review finding.

**Change:** Treat the destination displayed on a task as that task’s destination. A shared default may initialize it, but changing one task should not silently alter unrelated tasks or erase their successful outcomes. A previous output remains saved even if a new destination is selected. Offer an explicit action to create another copy when appropriate.

**Acceptance:** Changing the conversion folder does not change the meaning or destination of an existing update task, and saved results remain discoverable.

### 8. Put game information ahead of configuration and filenames — medium/high priority

**Evidence:** In the live Check Files screen, the large Key File Ready panel precedes the file, and the long technical filename precedes the actual game name/version. This places successful setup above the person’s main question. Update repeats its key setup as step one even when already complete.

**Change:** Once valid keys are configured, reduce them to a compact status/control or an app setting. Expand key setup only when it is missing or needs attention. Make the game title/version the primary content, with filename, format, size and path secondary. For a missing key, explain what can still be shown and request the key at the relevant point.

No persistent onboarding screen or extra initial navigation is needed.

**Acceptance:** On returning to a configured app, the first prominent content concerns the person’s files and desired result.

### 9. Use action labels and results that match people’s intentions — medium priority

**Evidence:** Action names vary between creating a file, saving copies and checking contents; plural labels can appear for one input. The Check Files success message repeats in the information card and footer and refers to “2 stored items,” which does not explain a user-level outcome. These were visible in the native review.

**Change:** Keep stable sidebar names for now, but test the distinction between Update and Combine with novices. Explain that distinction near the preparation preview and offer a contextual link to the other tool when the selection suggests a mismatch.

Use specific verbs and counts: Create Updated Copy, Create Combined File, Convert 3 Files, Split File, Join Parts and Shrink XCI. Keep “saves a new copy” clear beside operations that could otherwise sound destructive. Do not mechanically pluralize file counts where a tool produces one combined output.

Show the completed check once, prominently. A possible primary message is “No problems found in the checked game data.” Place technical archive counts in details, and make unchecked content or incomplete verification visible. Retain the short explanation that a data check does not test gameplay.

Apple recommends understandable, contextual status and recovery feedback: [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback).

**Acceptance:** People can explain what the action does and what a successful check actually establishes.

### 10. Improve density, hierarchy and accessibility — medium priority

**Evidence:** The screens contain large drop areas and substantial whitespace, while critical differences between tools appear in small secondary text. Update uses more vertical space than the utility screens. The live dark-mode check result uses subdued teal text. No measured contrast failure is claimed. Code shows a Return-key primary-action shortcut for Update but not the utility tools; status accessibility labeling is also inconsistent.

**Change:** Use a compact default window with sensible maximum content width, keep related input/result information together, and reduce nested cards and repeated explanatory copy. Display the output label “Save to” explicitly rather than relying on a folder name. Put important constraints near the affected control; put optional format education behind help.

Provide consistent Return-key behavior for enabled primary actions, discoverable File-menu commands for adding files/revealing results, complete keyboard navigation, helpful labels for removal, and sensible focus after a file is added or an error occurs. Announce major completion/failure transitions accessibly without reading every progress update. Test light/dark appearance, Increase Contrast, Reduce Transparency, keyboard-only use, VoiceOver and smaller laptop windows. Use text plus symbols for status, and measure custom accent colors.

Apple’s relevant guidance: [Color](https://developer.apple.com/design/human-interface-guidelines/color) and [Testing system accessibility features](https://developer.apple.com/documentation/accessibility/testing-system-accessibility-features-in-your-app).

**Acceptance:** The entire core workflow works by keyboard; essential text and states remain legible across tested appearances; screen-reader users receive meaningful results.

## Follow-up improvements after the core changes

- Add multi-file checking, using the same per-file results system. Check Files currently accepts one file at a time even though batch management is a central use case for this utility.
- Consider folder import for appropriate batch tools, with a clear summary of supported, duplicate and ignored files; do not silently recurse into huge locations.
- Offer a contextual “Check this output” or “Use in another tool” action when it removes unnecessary Finder work. Do not introduce another navigation hub.
- Provide unobtrusive background completion feedback and optional notifications for long batches; avoid adding permission prompts to ordinary first use.
- Reduce report clutter: offer a clear export/support-report action or a predictable Reports location. Do not place unexplained diagnostic files beside every successful output by default without testing whether users find that helpful.
- Expose a small amount of recent-result history if actual users frequently lose outputs after relaunch. Validate the need before building a persistent library or dashboard.

## Recommended implementation order

1. Shared task presentation, compact configured-key status, clearer action labels and actionable per-file results; benign skips and context-scoped errors.
2. Preparation previews, accurate aggregate progress and task-local destination behavior that retains completed outcomes.
3. Keyboard/accessibility refinement, multi-file checking and the highest-value follow-up actions from human testing.

Keep the sidebar simple throughout. Avoid another home screen, speculative categories, a dashboard, a mandatory guided tour, and a universal multi-step wizard.

## Human validation plan

Run two short iterative rounds with people who have not used the app, including several with little technical experience and at least one keyboard/assistive-technology user. The first round should test a prototype of the highest-priority changes; the second should test the implemented version.

Use realistic tasks without naming the intended tool in the instruction:

1. Make a copy of a game with its newer update applied.
2. Keep a game, update and add-ons in one package; explain the distinction from task one.
3. Read a game’s version and explain what its integrity result means.
4. Make an NSP from an XCI.
5. Prepare a file for a drive with a 4 GB limit and put the pieces back together.
6. Complete a mixed batch containing a healthy no-op, a wrong input and a valid transformation; identify outputs and recover only unfinished items.
7. Stop a long operation, find what was saved, and start again safely.

Record task completion without coaching, incorrect tool selection, destination mistakes, recovery attempts, interpretation of success, log dependence and confidence. Treat time as diagnostic rather than rewarding fast mistakes. With a seven-person iteration, a proposed target is at least six independently completing each primary task, with everyone understanding that originals remain unchanged and being able to locate outputs. Investigate every failure; this small sample is directional, not proof of universal usability.

A successful redesign should let people understand the next step from the screen they are on, complete typical work without technical logs, and accurately explain the result afterward.
