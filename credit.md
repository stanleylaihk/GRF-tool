# Credits

[English README](README.md) · [Traditional Chinese README](README.zh-TW.md) · [Japanese README](README.ja.md) · [Korean README](README.ko.md)

This document is maintained in English only. It records the authors, sources and uses acknowledged by **GRF Tool for macOS 1.5.0**, including the three Windows executables originally supplied as references. The in-app **More (⋯) → Credits & Sources…** window lists the same projects and original tools. A copy of this file is included in the packaged app's Resources directory.

GRF Tool for macOS is maintained at [stanleylaihk/GRF-tool](https://github.com/stanleylaihk/GRF-tool) and distributed under **GPL-2.0-or-later**. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the project license and preserved notices. This overview does not replace those notices or grant rights to third-party programs or game artwork.

## Projects, libraries and research sources

“Reference only” and “development tool” describe how this project uses a source; they are not a claim that all upstream software shares this application's license.

| Project / source | Author / contributors | Use in this project | Inclusion / license notes |
| --- | --- | --- | --- |
| [GRF Tool for macOS](https://github.com/stanleylaihk/GRF-tool) | stanleylaihk and contributors | Native macOS application, archive workspace, previews, interface translations and tests. | GPL-2.0-or-later · this project |
| [OpenKore / grftool](https://github.com/OpenKore/grftool) | Faithful, Hongli Lai, Rasqual and contributors | GRF cryptography implementation; archive and sprite format reference. | GPL-2.0-or-later · code included with preserved notices |
| [Ragnarok Research Lab](https://ragnarokresearchlab.github.io/) | Ragnarok Research Lab authors and contributors | SPR, ACT, PAL, GAT, GND, RSW, RSM, IMF and GR2 format research. | Documentation reference; site retains its own copyright |
| [RagnarokFileFormats](https://github.com/rdw-archive/RagnarokFileFormats) | rdw / Ragnarok Research Lab contributors | Historical format specifications and coordinate research. | Reference only |
| [roBrowser](https://github.com/vthibault/roBrowser) | Vincent Thibault and contributors | RSM / RSW binary layout and scene transform cross-check. | Reference only; no JavaScript renderer bundled |
| [roBrowserLegacy](https://github.com/MrAntares/roBrowserLegacy) | MrAntares and contributors | ACT format behavior reference. | Reference only |
| [GRFEditor](https://github.com/Tokeiburu/GRFEditor) | Tokeiburu and contributors | FNA length-prefixed resource-name layout reference. | Reference only; no application code bundled |
| [granny-ro-js](https://github.com/Stitchuuuu/granny-ro-js) | Stitchuuuu | Native Swift Oodle-0 port and bundled GR2 object, mesh, pose and embedded-texture reader. | MIT · adapted decoder and bundled reader; full notices included |
| [blendergranny](https://github.com/Rasetsuu/blendergranny) | ciupix and contributors / Rasetsuu | Clean-room Python Oodle-0 implementation credited by granny-ro-js. | MIT · full notices included |
| [noclip.website](https://github.com/magcius/noclip.website) | noclip.website contributors | Historical Granny DLL API reference used during decompressor research. | MIT · research reference only |
| [OpenGR2](https://github.com/arves100/opengr2) | arves100 and contributors | GR2 physical format reference and compatibility research. | Reference only |
| [zlib](https://zlib.net) | Jean-loup Gailly and Mark Adler | System compression / decompression library. | zlib license · system library |
| [Apple frameworks](https://developer.apple.com/documentation/) | Apple Inc. | SwiftUI, AppKit, Foundation, SceneKit, JavaScriptCore, Observation, AVFoundation and system image decoding. | System frameworks |
| [esbuild](https://github.com/evanw/esbuild) | Evan Wallace and contributors | Build-time bundling of the checked-in GR2 reader; version 0.25.0 is pinned in the regeneration script. | MIT · development tool; no esbuild executable or Node.js runtime bundled |
| [REA](https://github.com/morluto/rea) | REA contributors | Static inspection of the supplied Windows reference tools and Granny runtime. | Development tool; not bundled |
| [Unicorn](https://github.com/unicorn-engine/unicorn) | Unicorn Engine contributors | Isolated x86 replay for original-DLL / Swift decompressor parity tests. | Development tool; not bundled |

## Original supplied Windows executables

These executables were used as references during reconstruction. They are not wrapped by the macOS app, required at runtime, or redistributed. Attribution is limited to what the supplied records establish; an unknown author is not guessed.

| Supplied tool | Author / attribution | Reference purpose | Distribution / license notes |
| --- | --- | --- | --- |
| [grftool.exe · GRF Tool 1.2.0](https://github.com/OpenKore/grftool) | OpenKore / GRF Tool contributors | Original supplied reference for archive browsing, extraction and previews. | Reference executable only · not redistributed |
| [grfbuilder.exe · GRFBuilder 0.1.30](http://www.grfbuilder.com/) | MagicalTux (identified in supplied README) | Original supplied reference for merging, deletion, compression and repacking. | Reference only; supplied library README states it is not open source |
| SPRViewer.exe | Author not confirmed in supplied records | Original supplied reference for sprite decoding and bitmap frame export. | Reference executable only · not redistributed |

The supplied GRFBuilder library README states that its library is not open source; this project does not treat it as a source-code dependency. The author of the supplied `SPRViewer.exe` has not been confirmed in the records used for this project.

## Included implementations and preserved notices

- **OpenKore/grftool:** the GRF cryptography implementation is included in `Sources/CGRFCrypto/`, with its original copyright/license headers. Archive and sprite behavior were also checked against the upstream source and format documentation. See [the preserved notices and source hashes](THIRD_PARTY_NOTICES.md).
- **granny-ro-js:** the native Swift Oodle-0 decoder is adapted from its MIT implementation. A bundled JavaScript reader reconstructs the GR2 object graph, meshes, skeletons, first-frame poses and embedded RAW/IGC textures using the system JavaScriptCore framework. The pinned revision is `955189e060bf38270cbc3ea8cba610e98c7f62dc`; see [reader/build notes](scripts/granny-preview/README.md).
- **blendergranny:** credited as the clean-room Python origin of the Oodle-0 implementation and related work cited by granny-ro-js. Its MIT attribution is preserved in [third-party notices](THIRD_PARTY_NOTICES.md) and the [reader license record](scripts/granny-preview/LICENSE).
- **Apple frameworks and system zlib:** linked as system dependencies; their source is not copied into this repository.
- **App interface and translations:** the English, Traditional Chinese, Japanese and Korean interface catalogues are maintained in this repository. They do not translate or replace the user's original resource data.

## Development tools

**REA** supported static inspection of the supplied tools and Granny runtime. **Unicorn** supported isolated x86 replay to compare decompression results against the supplied runtime. **esbuild 0.25.0** bundles the checked-in GR2 reader when it is regenerated; its [MIT license](https://github.com/evanw/esbuild/blob/v0.25.0/LICENSE.md) credits Evan Wallace. These development tools are not required by app users. Normal builds do not need Node.js/npm because the reader is already checked in.

The proprietary Granny SDK, Windows DLLs and original EXEs are not bundled. Using a runtime as a research oracle does not mean its binary or proprietary implementation is redistributed.

## Game artwork and test data

Ragnarok Online names and game artwork belong to their respective rights holders. The preview screenshots illustrate locally supplied resources; this project claims no ownership of that artwork. Game client archives and asset payloads are not included in the application. Optional corpus tests require local files and do not add them to the repository.

## Investigation records

These are development records, not a guarantee of identical behavior across all clients:

- [Original GRF Tool inspection](docs/rea-evidence.json)
- [SPRViewer investigation](docs/preview-rea-evidence.json)
- [GRFBuilder comparison](docs/grfbuilder-comparison-evidence.json)
- [Granny runtime observations](docs/granny-runtime-evidence.json)
- [Oodle-0 research and differential checks](research/oodle0/README.md)
- [Scene and GR2 verification](docs/scene-preview.md)

[Project](https://github.com/stanleylaihk/GRF-tool) · [Create an issue](https://github.com/stanleylaihk/GRF-tool/issues/new) · [English README](README.md)
