# Upstream projects and acknowledgements

SwitchBench is maintained by [cinderlatch](https://github.com/cinderlatch). It began as SwitchPatch, a native Mac solution for applying game updates, and expanded into a general file utility.

## Primary inspiration

SwitchBench's primary inspirations are **[Switch Army Knife (SAK)](https://github.com/dezem/SAK)** by dezem and the SAK project team, and **[Switch Game Merge Utility](https://github.com/LordZeuss/switch-merge-utility)** by LordZeuss.

As a non-developer, I had difficulty getting Switch Game Merge Utility running on my Mac and running SAK in a virtual machine on my Mac. Some of that may have been down to my own inexperience, rather than problems with those tools. I worked with OpenAI Codex to build a native macOS app for these workflows, first called SwitchPatch and later expanded into SwitchBench.

I am grateful for the work those projects made available and the ideas they demonstrated. SwitchBench is a separately written native Mac app; no SAK or Switch Game Merge Utility application code is bundled here.

## Software this project builds upon

SwitchBench builds upon software created by the developers and upstream projects acknowledged below. They did not necessarily participate in SwitchBench’s development, review it, or endorse it. References to an upstream project’s authors or contributors refer to their work on that project, not direct contributions to SwitchBench.

| Project and developers | Role | License / provenance |
| --- | --- | --- |
| [hactool](https://github.com/SciresM/hactool) — SciresM and the hactool project team | NCA inspection, extraction, patch materialization and independent verification | ISC; Vendor/hactool/LICENSE. Modified source included. |
| [hacPack](https://github.com/DarkMatterCore/hacPack) — original author The-4n, DarkMatterCore fork and its upstream project team | Builds program/control/application archives from materialized game content | GPL version 2; Vendor/hacPack/LICENSE and LICENSES. Modified source included. |
| [Mbed TLS](https://github.com/Mbed-TLS/mbedtls) — its upstream authors | Helper cryptography; vendored separately by both engines | Apache-2.0; both mbedtls/apache-2.0.txt files and upstream headers retained. |
| [Zstandard](https://github.com/facebook/zstd/tree/v1.5.7) — Meta/Facebook and the upstream Zstandard team | Bounded native streaming compression decoding | BSD option of upstream dual license; Vendor/zstd-1.5.7/LICENSE and COPYING retained. |

hacPack also acknowledges SciresM, yellows8, Adubbz and SwitchBrew; its ISC notices for hactool-derived and libnx-derived portions are retained in Vendor/hacPack/LICENSES. hactool acknowledges inspiration from ctrtool; its upstream README and embedded notices remain included. Other component-level acknowledgements remain in their original files.

## Additional references and platform support

- [NSZ](https://github.com/nicoboss/nsz) by nicoboss and the NSZ project team: [format reference](https://github.com/nicoboss/nsz/blob/master/docs/formats.md) used while implementing native NCZ restoration. No NSZ Python runtime is included.
- Apple's AppKit, SwiftUI, CommonCrypto, system zlib and SF Symbols support the Mac implementation and icon generation.

The native interface, task orchestration, container handling and NCZ restoration are newly written for SwitchBench, with substantial Codex assistance. See AI_DISCLOSURE.md. Crediting a project does not imply endorsement, affiliation, or that its maintainers reviewed SwitchBench.

## Modifications and source records

Vendor/CHANGES.md documents local helper changes and acquisition dates. Vendor/SOURCE.sha256, hacPack-SOURCE.sha256 and zstd-SOURCE.sha256 record hashes of downloaded upstream archives. The original hactool/hacPack acquisitions used moving master archives; exact upstream commit IDs were not recorded. We preserve that limitation rather than inventing revisions. The complete source used here is vendored and versioned by this repository.
