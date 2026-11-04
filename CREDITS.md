# Credits

SwitchBench is maintained by [cinderlatch](https://github.com/cinderlatch). It began as SwitchPatch, a native Mac solution for applying game updates, and expanded into a general file utility.

## Included components

| Project and developers | Role | License / provenance |
| --- | --- | --- |
| [hactool](https://github.com/SciresM/hactool) — SciresM and contributors | NCA inspection, extraction, patch materialization and independent verification | ISC; Vendor/hactool/LICENSE. Modified source included. |
| [hacPack](https://github.com/DarkMatterCore/hacPack) — original author The-4n, DarkMatterCore fork and contributors | Builds program/control/application archives from materialized game content | GPL version 2; Vendor/hacPack/LICENSE and LICENSES. Modified source included. |
| [Mbed TLS](https://github.com/Mbed-TLS/mbedtls) — its authors and contributors | Helper cryptography; vendored separately by both engines | Apache-2.0; both mbedtls/apache-2.0.txt files and upstream headers retained. |
| [Zstandard](https://github.com/facebook/zstd/tree/v1.5.7) — Meta/Facebook and contributors | Bounded native streaming compression decoding | BSD option of upstream dual license; Vendor/zstd-1.5.7/LICENSE and COPYING retained. |

hacPack also acknowledges SciresM, yellows8, Adubbz and SwitchBrew; its ISC notices for hactool-derived and libnx-derived portions are retained in Vendor/hacPack/LICENSES. hactool acknowledges inspiration from ctrtool; its upstream README and embedded notices remain included. Other component-level acknowledgements remain in their original files.

## References and inspiration (not bundled applications)

- [NSZ](https://github.com/nicoboss/nsz) by nicoboss and contributors: [format reference](https://github.com/nicoboss/nsz/blob/master/docs/formats.md) used while implementing native NCZ restoration. No NSZ Python runtime is included.
- [switch-merge-utility](https://github.com/LordZeuss/switch-merge-utility) by LordZeuss: the original workflow inspiration for a Mac alternative. No application code from this project is bundled.
- [Switch Army Knife / SAK](https://github.com/dezem/SAK) by dezem and contributors: inspiration when selecting practical file-utility features. No SAK application code is bundled.
- Apple's AppKit, SwiftUI, CommonCrypto, system zlib and SF Symbols support the Mac implementation and icon generation.

The native interface, task orchestration, container handling and NCZ restoration are newly written for SwitchBench, with substantial Codex assistance. See AI_DISCLOSURE.md. Crediting a project does not imply endorsement, affiliation, or that its maintainers reviewed SwitchBench.

## Modifications and source records

Vendor/CHANGES.md documents local helper changes and acquisition dates. Vendor/SOURCE.sha256, hacPack-SOURCE.sha256 and zstd-SOURCE.sha256 record hashes of downloaded upstream archives. The original hactool/hacPack acquisitions used moving master archives; exact upstream commit IDs were not recorded. We preserve that limitation rather than inventing revisions. The complete source used here is vendored and versioned by this repository.
