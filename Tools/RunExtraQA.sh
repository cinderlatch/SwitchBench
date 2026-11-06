#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$#" -gt 1 ]; then printf 'Usage: bash Tools/RunExtraQA.sh [network-output-folder]\n' >&2; exit 2; fi
if [ "$#" -eq 1 ] && [ ! -d "$1" ]; then printf 'Choose an existing test output folder.\n' >&2; exit 2; fi
mkdir -p build/module-cache
bash Tools/BuildNative.sh
shared=(Sources/Core.swift Sources/Container.swift Sources/CompressedContent.swift Sources/CompressionWriter.swift Sources/Utility.swift Sources/FileOperations.swift Sources/Workflow.swift)
swiftc -swift-version 5 -O -module-cache-path build/module-cache "${shared[@]}" Tests/LargeFileTests.swift build/NativeCompression.o Vendor/zstd-1.5.7/lib/libzstd.a -lz -o build/LargeFileTests
./build/LargeFileTests large-file-validation.json
if [ "$#" -eq 1 ]; then
    fixtures=$(mktemp -d /private/tmp/switchbench-qa-fixtures.XXXXXX)
    trap 'rm -rf "$fixtures"' EXIT
    QA_FIXTURES="$fixtures" bash test.sh
    swiftc -swift-version 5 -O -module-cache-path build/module-cache "${shared[@]}" Tests/NetworkTests.swift build/NativeCompression.o Vendor/zstd-1.5.7/lib/libzstd.a -lz -o build/NetworkTests
    ./build/NetworkTests "$fixtures/Sample Cartridge.xci" "$1"
fi
