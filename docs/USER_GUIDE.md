# User guide

## Choose the task

Use **Update Games** to apply an update into a game copy. Add both the original game and update; matching is automatic. The preview shows the selected version and output name. **Combine Files** instead keeps one game's separate game, update and add-ons together without applying the update.

**Check Files** shows recognized game information first. Choose Check Contents to scan stored game data. Information being readable is different from the contents passing a scan. A passed scan is different from confirmed emulator gameplay.

**Convert to NSP** expands compressed NSZ/XCZ content or copies cartridge content into NSP. **Compress Files** saves smaller NSZ copies of NSP files and XCZ copies of XCI files. It uses your local key file and checks that the compressed game data can be restored. Savings vary by game. Use **Convert to NSP** if your emulator needs an uncompressed copy. Keep the original XCI if you need an exact cartridge dump. **Shrink XCI Files** removes unused trailing cartridge space. **Split Large Files** prepares parts for file-size-limited drives; keep the generated parts list with all parts. **Join Split Files** accepts any part or its folder.

## Work with files

Choose files, choose a folder or drop files into the window. Folder collection reports supported, duplicate and ignored items, can be stopped, and is bounded to 20,000 scanned items/5,000 supported files. Join accepts one set at a time. An unsupported replacement or cancelled selection preserves the current task.

Read the preview before starting. It shows names/versions where available, planned filenames, known sizes, savings/parts and space. A preview is not a full integrity scan. Use your own compatible prod.keys where requested; a separate title-key chooser appears only when needed.

Choose Save to for tools that create files. Each tool remembers its own folder. Your source files stay unchanged; existing outputs are never silently overwritten. Use Separate Name or Choose Folder when a planned output exists.

## Read outcomes

- **Ready:** prepared for processing.
- **Working:** the current file and phase are shown with queue progress and elapsed time.
- **Saved / Checked:** the stated operation and its applicable checks completed.
- **No Change Needed:** healthy input already meets this tool's purpose.
- **Needs Attention:** read the reason and use the recovery button beside it.
- **Stopped:** unfinished work for that file was discarded; completed results remain.

Stop waits for safe cleanup. Retry handles unfinished processing; resolve preparation problems first. Create Another Copy chooses a separate name. Show in Finder reveals a result; Use File In… selects a useful next tool. Recent Results keeps up to 30 completions across launches and explains unavailable drives. Clear List keeps files.

## Controls and help

Command–O chooses files; Command–Shift–O chooses a folder; Command–R shows saved files; Command–Shift–E exports a report. Command–1 through Command–7 select sidebar tools. Command–Control–S toggles the sidebar. Return runs the enabled primary action; Escape stops active work.

Help and About this tool explain formats and constraints. Settings contains keys, optional completion notifications and the local Reports folder. Notifications are off unless enabled. See PRIVACY.md before sharing a report.

## Parts and file-size units

The default split piece size is 4,294,901,760 bytes, below FAT32's 4 GiB limit. Finder's decimal units may display a piece as about 4.29 GB; that does not mean it exceeds the filesystem's binary limit. Never rename/remove individual pieces or the parts list before joining. Older third-party sets without saved checksums have more limited validation.
