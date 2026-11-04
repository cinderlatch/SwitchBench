# Development and releases

## Build

Apple Silicon, macOS 13+, Apple's Command Line Tools, Bash, make, a C compiler and Swift are required. Use `bash build.sh` from the repository root. Dependencies are vendored; no Homebrew/Python runtime or dependency download is required. Output: build/SwitchBench.app and SwitchBench-macOS-AppleSilicon.zip. The app uses a stable legacy bundle identifier to preserve existing SwitchPatch preferences.

Run `bash test.sh` after a build. It generates private synthetic fixtures automatically, cleans them normally and compiles C/Swift regression runners. It can also accept explicit helper paths. Tests use synthetic keys, not production keysets. Build before test so the helpers exist.

`bash Tools/BuildCLI.sh` builds developer tools. `bash Tools/MakeAppearancePreviews.sh` builds isolated light/high-contrast QA copies using a compile-time-only appearance hook; production ignores the preview setting.

## Optional disk/network checks

`bash Tools/RunExtraQA.sh` streams a real default-boundary split/join using a sparse synthetic source. Allow about 9 GB free; this writes actual output bytes and can take time. An optional existing-folder argument also exercises a disposable folder on that destination, including network volumes. Use a test destination you control. The test removes its own temporary directory, not existing files.

Independent human testing is described in UX-UAT-TASKS.md. Do not call test output, metadata checks or agent walkthroughs independent gameplay/usability certification.

## Layout and dependencies

Sources contains the Swift app, task preparation/model and native compression wrapper. Tests contains synthetic processing, format and state tests. Tools contains repeatable build/QA scripts. Vendor contains complete helper/dependency source and license notices. See CREDITS.md and Vendor/CHANGES.md before editing a helper. Record additional upstream changes/provenance; never replace notices.

## Public release checklist

1. Update app version/build, CHANGELOG and documentation; run a clean build, regression suite and relevant native walkthroughs.
2. Check Apple Silicon/minimum macOS assumptions and all archive contents. Do not include keys, games, personal paths, private logs, credentials or stale test inventories.
3. Build the app ZIP with the current docs/licenses. Keep full modified helper source in the matching source archive and tagged repository.
4. Commit the tested source and run `bash Tools/PackageRelease.sh`. Create a tag matching the release and attach the app ZIP, corresponding source ZIP and SHA256SUMS from dist/. State signing/notarization and validation limits.
5. Verify download hashes, source correspondence and clean git status. Never overwrite an existing published tag/release silently.

CI builds and tests on an Apple Silicon hosted Mac runner. It does not run private game data, gameplay, the optional large/network suite or independent human UAT. Workflow changes require review. GitHub-generated source archives are convenient, but a curated corresponding-source ZIP accompanies binary releases.
