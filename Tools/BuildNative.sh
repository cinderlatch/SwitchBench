#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
export MACOSX_DEPLOYMENT_TARGET=13.0
make -C Vendor/zstd-1.5.7/lib -j4 libzstd.a > build/zstd-build.log 2>&1
cc -O2 -mmacosx-version-min=13.0 -c Sources/NativeCompression.c -o build/NativeCompression.o
