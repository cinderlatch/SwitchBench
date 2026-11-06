#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/windows
out="$PWD/build/windows"
# Windows 11 supplies the UCRT. Statically link the MinGW support code and zlib.
printf '1 24 "%s/Windows/HelperManifest.xml"\n' "$(cygpath -m "$PWD")" > "$out/helper.rc"
windres "$out/helper.rc" -o "$out/helper-manifest.o"
link_flags="-static -lmbedtls -lmbedx509 -lmbedcrypto ../../build/windows/helper-manifest.o"
make -C Vendor/hactool -j4 EXEEXT=.exe CC=gcc LDFLAGS="$link_flags"
make -C Vendor/hacPack -j4 EXEEXT=.exe CC=gcc LDFLAGS="$link_flags"
cp Vendor/hactool/hactool.exe Vendor/hacPack/hacpack.exe "$out/"
make -C Vendor/zstd-1.5.7/lib -j4 CC=gcc libzstd.a
gcc -O2 -static -shared -o "$out/SwitchBenchNative.dll" Windows/Native.c Sources/NativeCompression.c \
    -IVendor/hactool/mbedtls/include Vendor/hactool/mbedtls/library/libmbedcrypto.a \
    Vendor/zstd-1.5.7/lib/libzstd.a -lz Windows/Native.def

# The packaged license is the one shipped by the actual zlib build.
license=$(pacman -Ql mingw-w64-ucrt-x86_64-zlib | awk '$2 ~ /\/share\/licenses\/.*\/(LICENSE|COPYING)(\.txt)?$/ { print $2; exit }')
if [ -n "$license" ]; then
    cp "$license" "$out/zlib-license.txt"
else
    head -n 30 /ucrt64/include/zlib.h > "$out/zlib-license.txt"
fi
