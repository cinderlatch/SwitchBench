# Troubleshooting

| What you see | Try this |
| --- | --- |
| macOS blocks first launch | Verify the official release and follow the Apple support link in README. The app is locally signed and not notarized. |
| Key file needed | Choose your own emulator's compatible prod.keys. Do not paste key contents into an issue. |
| Additional keys needed | Use the contextual additional-key action with your own title.keys. It is not needed for every file. |
| No matching update | Add the original game and its matching update; similarly named releases can still have different identities. |
| Output already exists | Show Existing File, choose another folder, or Use Separate Name. Existing files are protected. |
| Not enough space | Choose a drive with room for the finished output and temporary work. Estimates may be uncertain for rebuilt/compressed files. |
| A part is missing or changed | Keep all numbered parts and their parts list together; select the correct set. Do not invent or rename a missing part. |
| No Change Needed | Use the original directly; this is not a failure. |
| File can't be read / helper failed | Read the per-file reason. Check file completeness and supported formats; not every error is a key problem. Export a report if needed. |
| Emulator crashes after a successful check | Stored-data integrity cannot prove gameplay compatibility. Check emulator support and whether the original behaves the same, using only your authorized files. |
| Drive disappeared | Reconnect it and read the files again. Recent Results can retain paths to unavailable drives. |

The app reads inputs without changing them. Normal Stop/failure cleanup removes unfinished work. Forced termination or power loss can leave `.switchpatch-*` or `.partial` workspaces; with the app closed, remove only artifacts you have positively identified as unfinished temporary work. Keep your originals and backups.

Review and redact exported reports before posting. See SUPPORT.md for safe reports and SECURITY.md for private vulnerability reporting. Do not upload game content or keys.
