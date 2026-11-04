#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/build/module-cache"
export MACOSX_DEPLOYMENT_TARGET=13.0
bash Tools/MakeIcon.sh
bash Tools/BuildNative.sh
make -C Vendor/hactool clean_full > build/engine-clean.log 2>&1
make -C Vendor/hactool -j4 > build/engine-build.log 2>&1
make -C Vendor/hacPack clean_full > build/packer-clean.log 2>&1
make -C Vendor/hacPack -j4 > build/packer-build.log 2>&1
staging=$(mktemp -d /private/tmp/switchpatch-build.XXXXXX)
trap 'rm -rf "$staging"' EXIT
app="$staging/SwitchBench.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 -module-cache-path "$PWD/build/module-cache" Sources/Core.swift Sources/Container.swift Sources/CompressedContent.swift Sources/Utility.swift Sources/FileOperations.swift Sources/Workflow.swift Sources/WorkflowModel.swift Sources/UtilityView.swift Sources/App.swift build/NativeCompression.o Vendor/zstd-1.5.7/lib/libzstd.a -lz -o "$app/Contents/MacOS/SwitchBench" -framework SwiftUI -framework AppKit
cp Vendor/hactool/hactool "$app/Contents/Helpers/hactool"
cp Vendor/hacPack/hacpack "$app/Contents/Helpers/hacpack"
cp Vendor/hacPack/LICENSE "$app/Contents/Resources/hacPack-LICENSE.txt"
cp -R Vendor/hacPack/LICENSES "$app/Contents/Resources/hacPack-LICENSES"
cp Vendor/hactool/LICENSE "$app/Contents/Resources/hactool-LICENSE.txt"
cp Vendor/hactool/mbedtls/apache-2.0.txt "$app/Contents/Resources/mbedTLS-LICENSE.txt"
cp Vendor/zstd-1.5.7/LICENSE "$app/Contents/Resources/Zstandard-LICENSE.txt"
cp Assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp README.md "$app/Contents/Resources/README.md"
cp VALIDATION.md "$app/Contents/Resources/VALIDATION.md"
cp QA-UAT.md "$app/Contents/Resources/QA-UAT.md"
for doc in UX-AUDIT.md UX-IMPLEMENTATION.md UX-UAT-TASKS.md LICENSE COPYRIGHT.md CREDITS.md THIRD_PARTY_NOTICES.md AI_DISCLOSURE.md PRIVACY.md CHANGELOG.md; do cp "$doc" "$app/Contents/Resources/$doc"; done
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SwitchBench</string>
<key>CFBundleIdentifier</key><string>local.switchpatch.mac</string>
<key>CFBundleName</key><string>SwitchBench</string>
<key>CFBundleDisplayName</key><string>SwitchBench</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>CFBundleVersion</key><string>14</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app/Contents/Helpers/hactool"
codesign --force --sign - "$app/Contents/Helpers/hacpack"
xattr -dr com.apple.FinderInfo "$app" 2>/dev/null || true
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
# Replace the generated bundle so resources removed from a release cannot linger.
rm -rf "$PWD/build/SwitchBench.app"
ditto --norsrc --noextattr "$app" "$PWD/build/SwitchBench.app"
codesign --verify --deep --strict "$PWD/build/SwitchBench.app"
ditto -c -k --keepParent --norsrc --noextattr "$app" "$PWD/SwitchBench-macOS-AppleSilicon.zip"
printf 'Built %s\n' "$PWD/SwitchBench-macOS-AppleSilicon.zip"
