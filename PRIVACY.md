# Privacy and local data

SwitchBench processes files locally. The app contains no analytics, advertising, account system, AI runtime calls, telemetry or automatic upload feature. It does not download games, firmware or keys.

- Key contents are read locally and are not stored in preferences or placed on helper command lines. Temporary private keysets are removed during normal cleanup. A crash, forced termination or power loss can interrupt cleanup.
- Preferences remember the selected key-file path, each tool's save folder, last tool, window setup and notification choice.
- Recent Results remembers up to 30 completed result paths and summaries locally. Clear List removes history entries and keeps files.
- Up to 30 owner-only diagnostic reports are kept at `~/Library/Application Support/SwitchBench/Reports`. They can include file names and paths. Technical reports redact key-shaped long hexadecimal strings, but users must review reports before sharing them.
- Optional macOS notifications require opt-in. The Dock can indicate completed background work.
- Output files and selected network folders are user-controlled. Selecting a network location means reading/writing that location; the app cannot control the server's privacy or backup practices.

Public GitHub issues, uploads and contributions are handled by GitHub under its policies. Nothing is uploaded automatically by SwitchBench. To remove local history, use Clear List. To remove diagnostic reports, use Settings → Show Local Reports and delete the reports you no longer want.
