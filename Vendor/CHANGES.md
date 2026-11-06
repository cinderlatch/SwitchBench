# Local changes to hactool

Source: https://github.com/SciresM/hactool, master archive retrieved 2026-11-03.
Archive SHA-256 is recorded in `SOURCE.sha256`.

- `main.c`: `--switchpatch-header <keyset> <0xC00-header-file>` decrypts only an NCA header, returning content type, title ID, declared size and rights ID. No key material is printed.
- `main.c`: `--switchpatch-titlekeys <file>` explicitly selects a private title-key file rather than relying on the user's global configuration. Base-NCA key output is suppressed.
- `nca.c`: allow `--romfs` to target a BKTR section with a supplied base. Existing section output selects the final IVFC data level, producing the materialized RomFS image rather than a raw patch.

Additional later BKTR changes are listed below. The bundled engine retains upstream limitations; unsupported formats are rejected rather than treated as verified.

# hacPack backend added in SwitchPatch 0.2.0

Source: https://github.com/DarkMatterCore/hacPack, master archive retrieved 2026-11-03. Archive SHA-256: `hacPack-SOURCE.sha256`. GPL v2 license and upstream third-party notices retained. This engine is invoked as a separate process; modified source is included.

- `romfs.c`: `romfs_build` accepts an existing materialized RomFS image in addition to a directory. It streams the image into the last IVFC level and applies the same padding as the directory builder, without extracting thousands of files or changing their RomFS layout.
- `ivfc.h`: remove a trailing semicolon from the IVFC block-size macro so it can be used in an arithmetic expression.

The app rebuilds normal program/control/meta NCAs and verifies their hashes with the independent hactool engine. Signature checks are not used to authenticate newly rebuilt archives, because they cannot retain Nintendo signatures.

## 0.3.1: newer compressed title metadata

- hacPack/nacp.c: validate both legacy fixed language entries and bounded raw-deflate compressed title data selected by the 0x3215 format flag. Preserve control.nacp bytes without rewriting or substituting base metadata.
- hacPack/Makefile: link macOS system zlib (-lz).
- Tests/NACPTests.c: synthetic compressed/legacy metadata, preservation, malformed stream, bounds and expansion regressions.

## 0.4.0: native utility layer

- Added unmodified Zstandard 1.5.7 library sources, LICENSE, COPYING and the required top-level Makefile include. Archive SHA-256 is recorded in zstd-SOURCE.sha256. The app links the BSD-licensed static library.
- Sources/NativeCompression.c wraps bounded streaming Zstandard decoding; the Swift layer implements NSP/XCI containers and NSZ/NCZ restoration independently from the documented format, using CommonCrypto for AES-CTR.
- Existing modified hactool/hacPack cryptography and rebuilding code are retained. New conversion/combining tools copy stored content, while the existing update tool still materializes patches and rebuilds normal NCAs.

## Later BKTR validation and public-source notices (3–4 November 2026)

- hactool/nca.c and nca.h: parse and validate newer BKTR metadata/IVFC layout information, bound tables and offsets, check patch metadata integrity, and distinguish subsection coverage for legacy versus metadata-hashed layouts. Invalid metadata/layouts are rejected. The existing materialized final-RomFS output path is retained. Synthetic legacy/current layout regressions are in Tests/BKTRTests.c.
- Public release preparation marks modified helper files with a dated SwitchBench notice. The archived upstream baselines were independently matched against the SHA-256 records before listing differences.
- Files differing from those original archives: hactool/main.c, nca.c, nca.h; hacPack/Makefile, ivfc.h, nacp.c, romfs.c. Local config.mk files select the Mac compiler/link settings. Upstream dependency sources and notices are preserved.
- No exact upstream commit was recorded for the original moving master archives. The checksummed baseline archives and complete vendored release source are the provenance record; no revision is invented.

## Compression output

- hactool/main.c adds a private header probe for NCZ section records. It writes records to a temporary file and prints only status and content size. hactool/nca.c bounds legacy header key-area indices.
- SwitchBench writes independently decodable Zstandard blocks and verifies their restored data. The [NSZ format specification](https://github.com/nicoboss/nsz/blob/master/docs/formats.md) guided the implementation.

## Windows preview

The Windows build uses hacPack’s existing Windows filesystem support and sets its executable suffix explicitly in the Makefile. The build embeds a UTF-8 code page manifest in both processing helpers so Windows filenames can be passed through their existing command-line interfaces.
