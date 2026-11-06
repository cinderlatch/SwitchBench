#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
bash Tools/BuildNative.sh
shared=(Sources/Core.swift Sources/Container.swift Sources/CompressedContent.swift Sources/CompressionWriter.swift Sources/Utility.swift Sources/FileOperations.swift Sources/Workflow.swift)
for name in PatchCLI UtilityCLI; do
    swiftc -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" "${shared[@]}" "Tools/$name.swift" build/NativeCompression.o Vendor/zstd-1.5.7/lib/libzstd.a -lz -o "build/$name"
done
