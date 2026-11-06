#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
if [ -z "${QA_FIXTURES:-}" ]; then
    qa_fixtures=$(mktemp -d /private/tmp/switchbench-tests.XXXXXX)
    trap 'rm -rf "$qa_fixtures"' EXIT
    export QA_FIXTURES="$qa_fixtures"
fi
bash Tools/BuildNative.sh
swiftc -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" Sources/Core.swift Sources/Container.swift Sources/CompressedContent.swift Sources/CompressionWriter.swift Sources/Utility.swift Sources/FileOperations.swift Sources/Workflow.swift Tests/CoreTests.swift build/NativeCompression.o Vendor/zstd-1.5.7/lib/libzstd.a -lz -o build/CoreTests
engine_path="${1:-$PWD/Vendor/hactool/hactool}"
packer_path="${2:-$PWD/Vendor/hacPack/hacpack}"
./build/CoreTests "$engine_path" "$packer_path"

# Exercise legacy and current BKTR layouts with synthetic encrypted fixtures.
make -C Vendor/hactool -j4 > build/test-engine-build.log 2>&1
objects=()
for object in Vendor/hactool/*.o; do
    case "$object" in */main.o|*/nca.o) ;; *) objects+=("$object") ;; esac
done
cc -O2 -Wall -Wextra -I Vendor/hactool/mbedtls/include Tests/BKTRTests.c "${objects[@]}" \
    -L Vendor/hactool/mbedtls/library -lmbedtls -lmbedx509 -lmbedcrypto -o build/BKTRTests
./build/BKTRTests

# Validate current compressed title metadata without changing its source bytes.
make -C Vendor/hacPack -j4 > build/test-packer-build.log 2>&1
packer_objects=()
for object in Vendor/hacPack/*.o; do
    case "$object" in */main.o|*/nacp.o) ;; *) packer_objects+=("$object") ;; esac
done
cc -O2 -Wall -Wextra -I Vendor/hacPack/mbedtls/include Tests/NACPTests.c "${packer_objects[@]}" \
    -L Vendor/hacPack/mbedtls/library -lmbedtls -lmbedx509 -lmbedcrypto -lz -o build/NACPTests
./build/NACPTests

swiftc -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" Sources/Core.swift Sources/Container.swift Sources/CompressedContent.swift Sources/CompressionWriter.swift Sources/Utility.swift Sources/FileOperations.swift Sources/Workflow.swift Tests/UtilityTests.swift build/NativeCompression.o Vendor/zstd-1.5.7/lib/libzstd.a -lz -o build/UtilityTests
./build/UtilityTests "$engine_path"

swiftc -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" Sources/Core.swift Sources/Container.swift Sources/CompressedContent.swift Sources/CompressionWriter.swift Sources/Utility.swift Sources/FileOperations.swift Sources/Workflow.swift Tests/WorkflowTests.swift build/NativeCompression.o Vendor/zstd-1.5.7/lib/libzstd.a -lz -o build/WorkflowTests
./build/WorkflowTests "$engine_path" "$QA_FIXTURES" "$packer_path"

swiftc -D QA_TESTING -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" Sources/Core.swift Sources/Container.swift Sources/CompressedContent.swift Sources/CompressionWriter.swift Sources/Utility.swift Sources/FileOperations.swift Sources/Workflow.swift Sources/WorkflowModel.swift Sources/UtilityView.swift Sources/App.swift Tests/UITests.swift build/NativeCompression.o Vendor/zstd-1.5.7/lib/libzstd.a -lz -framework SwiftUI -framework AppKit -o build/UIStateTests
./build/UIStateTests

# Check the shared primary/supporting text palette in four native appearances.
swift -module-cache-path "$PWD/build/module-cache" Tools/CheckContrast.swift contrast-validation.json
