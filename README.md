# GRF Tool for macOS

**English** · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Credits](credit.md)

<img src="Assets/grf-app-icon-pixel-wand.png" alt="GRF Tool icon with GRF lettering and a pixel wand" width="160">

A native macOS browser, previewer and editor for Ragnarok Online GRF/GPF archives. Browse resources, search names and text, preview maps and models, extract files, and save edited archives as new copies.

Built with SwiftUI, it reconstructs workflows from **GRF Tool 1.2.0 (`grftool.exe`)**, **GRFBuilder 0.1.30 (`grfbuilder.exe`)** and **SPRViewer (`SPRViewer.exe`)**. It runs locally without Windows, Wine, an account or a server. Original executables, game assets and proprietary SDKs are not bundled. See [Credits](credit.md) for authors, sources and how each reference is used.

## Getting started

Requires **macOS 14 or later**. Building from source also requires Xcode or Command Line Tools with **Swift 6**.

```sh
git clone https://github.com/stanleylaihk/GRF-tool.git
cd GRF-tool
./build-app.sh
open "release/GRF Tool.app"
```

The script builds for the host architecture; Apple Silicon and Intel builds must be produced separately. The app is locally ad-hoc signed, without Developer ID signing or notarization. Use the packaged `.app` for Finder file opening; `swift run GRFToolMac` is also available for development.

1. Choose **Open** or drop a `.grf`/`.gpf` archive into the window.
2. Select a source or folder on the left. The right workspace contains the toolbar/search row, then a file list on the left and a preview on the right.
3. Use **Local File** to preview a standalone resource and browse neighboring files. An opened GRF remains available in the source list.
4. Use **Extract**, or edit through **Manage** and choose **Save GRF As…**.

The top bar does not repeat the archive name. Empty toolbar space can move the window. Controls use a single blue hover highlight. Split dividers adjust pane widths, and the sidebar and preview can be toggled.

## Interface languages

**Settings → Interface Language** offers **English, 繁體中文, 日本語 and 한국어**. Changes apply immediately and are remembered. Switching language preserves the open archive, search and preview; it does not translate filenames, resource contents or change the draft.

Interface language is independent of archive filename encoding and text decoding. Original license text, JSON and unrecognized low-level diagnostics retain their original language.

## Browsing and search

- Folder tree, multiple selection, original paths, file sizes and compressed sizes. Some known Korean folders have English hints without renaming their paths.
- **Filename** searches names/paths immediately and supports `*` and `?`, such as `*.spr`.
- **Content / All** searches run on Enter or **Search**, across the whole active source, including added/replaced draft files. Results show snippets, line numbers and match counts; the preview supports previous/next match navigation.
- Content search has progress and cancellation. Binary files and text files above **16 MiB** are skipped and reported. Folder filtering does not restrict its scope.
- Opening a large archive reads its index with progress/cancellation, rather than loading the entire archive into memory.

## Creating and editing GRFs

- **New GRF / ⌘N** creates an empty archive.
- **Manage** adds files/folders, merges GRFs, replaces, renames and deletes resources. Duplicate paths during merging can keep existing files, replace them or cancel the merge.
- **Pending Changes** counts edited resources and supports undoing an item, the last operation or all changes. Lists and previews reflect the draft immediately.
- **Extract** reads the current draft: replaced resources use the new bytes, and deleted resources are excluded.
- **Save GRF As…** writes a new, standard, unencrypted **GRF 2.0**, then opens it. **Repack As…** rebuilds the index and compressed data, removing unreferenced space; a smaller result is not guaranteed.

Changes stay in a memory-only working copy. The source archive and merged source archives are protected. Leaving an unsaved draft prompts first. Saving is cancellable; failure preserves the draft and existing destination.

Open Settings with **⌘,** to choose **Default (balanced)** or compression **0–9**: 0 stores without compression, 1 is fastest and 9 uses maximum compression. This affects the next save/repack and does not alter existing archives.

## Resource previews

Select an archive entry or open a standalone file. Preserve the local `data` directory structure when resources need companion textures/models. Missing dependencies are reported. Scenes support orbit/zoom and an information/JSON view.

These are example previews; screenshots may show an earlier layout. Game artwork is shown for illustration and is not bundled with the app.

### RSW — 3D map scenes

**RSW 1.2–2.1** combines GND terrain, RSM models and textures, including object position, rotation and scale. Water, effects, full game lighting and animation are not reproduced.

![RSW preview of Prontera terrain, models and textures](docs/images/preview-rsw.png)

### RSM — 3D models

**RSM 1.1–1.4** static models have **Wireframe / Textured** tabs, defaulting to wireframe. Keyframe animation playback is not implemented.

![RSM model in textured mode](docs/images/preview-rsm.png)

### GR2 — Granny models

RO's **GR2 v6, little-endian, 32-bit** format supports embedded RAW/IGC textures, material groups, UVs and a skinned static first-frame pose. **Wireframe / Textured** defaults to wireframe. Action files attempt to match an unambiguous base model in the active source or local `data` root; missing companions are reported.

Animation playback and other Granny versions/codecs are not supported. Native Swift Oodle-0 decompression feeds a bundled open-source reader; no proprietary Granny SDK or Windows DLL is required.

![GR2 guardian with embedded textures](docs/images/preview-gr2.png)

### SPR — sprite frames

**SPR 1.0/1.1, 2.0 and 2.1** support transparency, zoom, frame selection and cycling. **Save One / Save All** exports BMP frames. Opaque indexed exports retain 256 colors; transparent exports use alpha BMPs. SPR cycling displays individual images; open the matching ACT for composed actions.

SPR/ACT zoom controls sit beside the preview title: **− percentage +**. Click the percentage to reset to **100%**. File names and sizes are not repeated in a preview footer.

![SPR preview with transparency and frame controls](docs/images/preview-spr.png)

### Palette menu

| Option | Purpose |
| --- | --- |
| **Load PAL File…** | Apply a local `.pal` to the current preview. |
| **Choose PAL from Archive…** | Select a PAL from the current GRF; disabled if none are available. |
| **Reset Palette** | Restore the SPR's embedded palette. |
| **Change Matching SPR…** | Manually change the image companion used by an ACT preview. |

Palette and SPR changes affect the preview only. PAL primarily changes indexed-color images; true-color parts may remain unchanged.

### Other formats

| Format | Preview |
| --- | --- |
| BMP/JPEG and other system-supported images | Image preview. |
| TXT/XML/JSON and other supported text | Encoding selection and search-match navigation; JSON formatting where available. |
| WAV | Audio playback. |
| PAL | 256-color grid, color values and application to SPR/ACT. |
| ACT 1.1, 2.0–2.5 | Automatic same-name SPR matching, actions/directions, timed playback, layered position, mirroring, scale, rotation and tint; manual SPR selection. |
| Lua/LUB | Text source, or Lua 5.1 bytecode functions/constants/instructions. This is disassembly, not original-source recovery. |
| GAT 1.2/1.3 | Walkability, terrain types, coordinates and corner heights. |
| GND 1.6–1.9 | Top-down height view, texture and lighting statistics; open the corresponding RSW for an assembled textured scene. |
| IMF 1.01 | Layer/frame origins and coordinates; no sprite artwork or animation reconstruction. |
| FNA | Referenced paths and JSON information. |
| Other/unsupported decoded resources | Info / Strings / Hex fallback; Hex shows the first 64 KiB. |

GAT/GND provide **Preview / Info / JSON**, fit/zoom, cell selection by clicking or X/Y, and **Export JSON…** for complete cell/surface data. ACT sound events and anchors remain metadata; event audio and multi-part head/body assembly are not implemented.

## Encoding: filenames and contents are separate

If names look correct but text is garbled, change **Text Encoding**. If folder/file names are garbled, change **Archive Filename Encoding**.

### Archive Filename Encoding

Use **More (⋯) → Text / Filename Encoding…**. Changing filename encoding reloads the source and also affects embedded resource-name decoding; it does not rewrite the archive.

| Encoding | Typical use |
| --- | --- |
| **Korean (CP949)** | Default for original Korean RO names. |
| **Unicode (UTF-8)** | Archives created with UTF-8 names. |
| **Traditional Chinese (Big5)** | Archives with Big5 filenames. |
| **Western (Latin-1)** | Known Latin-1 names or inspecting a single-byte interpretation. |

For Korean names with Traditional Chinese descriptions, normally keep **CP949 filenames** and select **CP950/Big5 text**.

### Text Encoding

Choose it above the text preview or in the encoding popover. The preview reports the decoder used. Options are **Automatic, UTF-8, CP949, CP950/Big5, UTF-16, Latin-1** and **Mixed Big5 / Korean (per line)**.

Automatic decoding attempts Unicode/CP949/CP950, then line-by-line mixed recovery if strict decoding fails. Mixed recovery is heuristic and warns when used; ambiguous lines can be checked with a single encoding. These options affect preview/search, never original bytes or filenames.

### Import, output and extraction names

- The builder can choose an import encoding independently of output encoding.
- **Output Filenames** in the builder selects the output encoding. Workspace **Save GRF As… / Repack As…** uses the active archive filename encoding: CP949, UTF-8, Big5 or Latin-1. UTF-8 requires client support.
- Names must round-trip losslessly and fit format limits; otherwise saving stops with an error.
- Extraction normally writes Unicode names. Original-byte mode is limited to UTF-8-compatible names; use Unicode if macOS rejects Korean ANSI names.

Encoding changes cannot repair corrupt data, unknown custom encryption or unsupported compression.

## Compatibility and limits

- Reads **GRF 1.0–1.3 and 2.0**, including standard mixed/header DES handling; writes unencrypted **GRF 2.0**. GRF 3.x and unknown custom encryption are unsupported. An index being readable does not prove encrypted contents can be decoded.
- Folder extraction preserves directories and refuses existing-file overwrites. Conflicts stop the operation, retaining completed files. **Extract File As…** uses the system save dialog for confirmed replacement.
- Batch extraction reports undecodable individual resources and skips them; unsafe paths, disk errors and cancellation stop the operation.
- Saving rejects corrupt/unreadable resources instead of silently discarding them. Invalid legacy paths may be browsed but must be corrected before saving. Symlinks, traversal and conflicting paths are rejected.
- General preview: **64 MiB/file**; extraction/writing: **512 MiB/resource**; index: **256 MiB**; GRF output: **4 GiB**.
- Normal text preview: **2 MiB**; Lua text: **512 KiB**; Lua 5.1 bytecode: **16 MiB / 10,000 output lines**. Truncation is marked; extraction retains full bytes.
- SPR decoded data: **256 MiB**. GAT/GND: at most **2,048 cells per side / 1,000,000 cells total**. Assembled scenes have additional resource and geometry limits; see [Workspace](docs/workspace-ui.md).

## Development and verification

```sh
./test.sh
# Optional local fixtures; game resources are not added to the repository.
GRF_DEMO_DIR=/absolute/path/to/grf ./test.sh
```

The v1.5.0 suite contains **108 tests**, covering localization, preference persistence, archive reading/writing, cryptography, encoding, draft undo, search, safe extraction, cancellation and resource parsing. Optional corpus tests need local game files and may return without exercising a corpus when none is supplied. The GR2 investigation validated 21 locally supplied files; see the linked research notes. Compatibility with every game client has not been established.

| Documentation | Contents |
| --- | --- |
| [Workspace](docs/workspace-ui.md) | Layout, editing, pending changes, search, language selection and current preview behavior. |
| [GRF building](docs/grf-building.md) | Output format, compression and writer protections. |
| [Map preview](docs/map-preview.md) | GAT/GND, coordinates and JSON export. |
| [Scenes and models](docs/scene-preview.md) | RSW/RSM/GR2 research and verification. |
| [Reconstruction](docs/reconstruction.md) | Original-tool comparison and evidence boundaries. |
| [Sprite research](docs/preview-investigation.md) | SPR/PAL/ACT investigation. |
| [Oodle-0 research](research/oodle0/README.md) | Native decoder and original-DLL comparison. |
| [Bundled GR2 reader](scripts/granny-preview/README.md) | Pinned upstream revision and optional bundle regeneration. |

Some technical notes are in Traditional Chinese or English. Normal builds need no Node.js/npm: the GR2 reader is checked in. Regenerating that reader is a separate development step using esbuild 0.25.0.

Do not commit personal GRFs/GPFs, game assets, `.build/` or `release/`. `.build/` includes SDK/build caches and does not represent the app's installed size.

## Credits and licensing

**GPL-2.0-or-later**; see [LICENSE](LICENSE), [Credits](credit.md) and [Third-party notices](THIRD_PARTY_NOTICES.md). The in-app **More (⋯) → Credits & Sources…** window lists sources, original tools and licenses.

REA was used during development to inspect the supplied Windows references; the app does not claim identical behavior or a pixel-perfect game renderer. Original binaries are not distributed. Screenshots contain game artwork for illustration; no ownership of that artwork is claimed.

[Project](https://github.com/stanleylaihk/GRF-tool) · [Create an issue](https://github.com/stanleylaihk/GRF-tool/issues/new) · [Credits](credit.md)
