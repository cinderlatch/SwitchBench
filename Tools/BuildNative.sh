#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
export MACOSX_DEPLOYMENT_TARGET=13.0
native_arch="${SWITCHBENCH_TARGET_ARCH:-$(uname -m)}"
case "$native_arch" in arm64|x86_64) ;; *) printf 'Unsupported native architecture: %s\n' "$native_arch" >&2; exit 2 ;; esac
# Switching between native Intel tests and the arm64 release must not reuse the wrong archive.
if [ -f Vendor/zstd-1.5.7/lib/libzstd.a ] && ! lipo Vendor/zstd-1.5.7/lib/libzstd.a -verify_arch "$native_arch" 2>/dev/null; then
    make -C Vendor/zstd-1.5.7/lib clean > build/zstd-clean.log 2>&1
fi
make -C Vendor/zstd-1.5.7/lib -j4 CC="clang -arch $native_arch" libzstd.a > build/zstd-build.log 2>&1
clang -arch "$native_arch" -O2 -mmacosx-version-min=13.0 -c Sources/NativeCompression.c -o build/NativeCompression.o
lipo Vendor/zstd-1.5.7/lib/libzstd.a -verify_arch "$native_arch"
lipo build/NativeCompression.o -verify_arch "$native_arch"
