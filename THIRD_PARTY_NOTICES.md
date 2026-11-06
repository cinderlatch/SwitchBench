# Third-party notices

Preserve the following files when redistributing source. Binary releases also carry upstream notices in SwitchBench.app/Contents/Resources. Source for the modified helpers is in this repository and the matching source release archive.

| Component | License | Retained notice |
| --- | --- | --- |
| hactool | ISC | [LICENSE](Vendor/hactool/LICENSE) |
| hacPack | GPL-2.0 | [LICENSE](Vendor/hacPack/LICENSE), [LICENSES](Vendor/hacPack/LICENSES) |
| hactool/libnx portions in hacPack | ISC | Each original notice in [hacPack/LICENSES](Vendor/hacPack/LICENSES) |
| Mbed TLS in hactool | Apache-2.0 | [License](Vendor/hactool/mbedtls/apache-2.0.txt) and original source headers |
| Mbed TLS in hacPack | Apache-2.0 | [License](Vendor/hacPack/mbedtls/apache-2.0.txt) and original source headers |
| Zstandard 1.5.7 | BSD license selected; upstream GPL option also retained | [LICENSE](Vendor/zstd-1.5.7/LICENSE), [COPYING](Vendor/zstd-1.5.7/COPYING) |

System frameworks and zlib are provided by macOS, not redistributed as standalone libraries here. Apple's symbols are used through system APIs; see COPYRIGHT.md.

The helper processes are distinct executables. Their modified source, makefiles and bundled dependencies are included, rather than relying on a future written source offer. Local changes are listed in [Vendor/CHANGES.md](Vendor/CHANGES.md). Original upstream copyright and license texts remain unchanged.

The vendored Mbed TLS upstream tests include publicly distributed test certificates and private test keys. They are upstream synthetic fixtures, not user credentials, and must never be used as production credentials. Their presence is intentional; no user keysets are included.

## Windows runtime

The portable Windows package includes the Swift 6.3.3 runtime, Foundation, and Dispatch under the Swift project's Apache 2.0 license with its runtime library exception. It includes ICU 76.1 from Unicode and zlib from the MSYS2 UCRT64 toolchain. Their notices accompany the download in Licenses. The helper builds use MinGW-w64 and the Windows UCRT. Microsoft Visual C++ runtime files, where bundled, are distributed from Visual Studio's redistributable directory.
