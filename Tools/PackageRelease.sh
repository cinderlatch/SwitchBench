#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/SwitchBench.app/Contents/Info.plist)
if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
    printf 'Commit the intended release source before packaging.\n' >&2
    exit 1
fi
codesign --verify --deep --strict build/SwitchBench.app
mkdir -p dist
ditto -c -k --keepParent --norsrc --noextattr build/SwitchBench.app "dist/SwitchBench-v${version}-macOS-AppleSilicon.zip"
git archive --format=zip --prefix=SwitchBench-Source/ HEAD > "dist/SwitchBench-v${version}-Source.zip"
(cd dist && shasum -a 256 "SwitchBench-v${version}-macOS-AppleSilicon.zip" "SwitchBench-v${version}-Source.zip" > SHA256SUMS)
printf 'Release files are in dist/. Check source correspondence before publishing.\n'
