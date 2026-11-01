# RSW, RSM and IMF previews

Select an entry in an archive or use **Preview File** to open a standalone resource.
The Preview tab supports rotation and zoom; Info / JSON shows decoded data and resource references.

- **RSW 1.2–2.1:** object placement overview. Each point represents a model, light, sound or effect. This is not a fully rendered map: GND terrain, RSM geometry, textures and particle effects are not loaded. JSON lists names, types, resources and file coordinates.
- **RSM 1.1–1.4:** static, untextured wireframe with node hierarchy, local transforms and triangle geometry. Textures, keyframe playback and collision volumes are not rendered. Unsupported versions produce an explicit message.
- **IMF 1.01:** layer/frame origins displayed as points (X/Y origin, Z layer), plus frame indices and coordinates in JSON. This does not reconstruct sprite artwork or playback. Unknown trailing data is reported, not interpreted.

Standalone files and archive entries use the chosen filename encoding for embedded resource names. Reads are bounded to 64 MiB with record-count and index validation.

Format references:
- https://ragnarokresearchlab.github.io/file-formats/rsw/
- https://ragnarokresearchlab.github.io/file-formats/imf/
- https://github.com/rdw-archive/RagnarokFileFormats/blob/master/RSM.MD
- https://github.com/vthibault/roBrowser/blob/master/src/Loaders/Model.js (binary layout cross-check; no source copied)

Validation: synthetic triangle, object-placement and IMF fixtures; truncation and malicious count tests. Opt-in real-resource checks use `GRF_SCENE_ARCHIVE=/path/to/data.grf ./test.sh --filter ScenePreviewTests` and read up to 30 entries per format without bundling game assets.

## FNA and GR2 information previews

- **FNA:** decodes a bounded sequence of length-prefixed, NUL-terminated resource names. Displays original paths and JSON. These historical authoring paths are never opened automatically. FNA contains references rather than sprite pixels; use SPR/ACT for image/animation previews. Validated against all 23 FNA entries in the supplied `data.grf`.
- **GR2 (1.4.1):** RO v6 little-endian 32-bit model preview with Wireframe (default) / Textured tabs, embedded RAW and IGC textures, material groups, UVs, initial placement and skinned first-frame pose. Separate action files resolve an unambiguous `3dmob/name_N.gr2` companion from the active draft or local data root. Missing companions are reported; an animation-only file without geometry gets an explanatory empty state. Animation playback and other Granny versions/codecs are not implemented. Info retains section metadata; the stored CRC is not verified. Native Swift Oodle-0 decoding feeds a bundled MIT granny-ro-js reader in system JavaScriptCore. No proprietary SDK, game DLL, game asset, Node.js runtime or network service is bundled.

Additional references:
- https://github.com/Tokeiburu/GRFEditor/blob/main/GRF/FileFormats/Fna.cs (length-prefixed string layout; no source copied)
- https://ragnarokresearchlab.github.io/file-formats/gr2/
- https://github.com/arves100/opengr2 (Oodle-0 compatibility limitation)

## Mixed book text recovery

`data/book/7127.txt` in the supplied archive combines CP950 Traditional Chinese paragraphs and untranslated CP949 Korean paragraphs. Strict UTF-8, CP949 and CP950 decoding each fails over the complete file. Automatic now attempts line-based Big5/CP949 recovery only after all strict candidates fail. It uses valid decoding plus a Hangul proportion heuristic for ambiguous lines, and explicitly warns that ambiguous choices may be incorrect. Strict single-encoding choices remain unchanged. The dedicated Mixed Big5 / Korean menu option allows the same recovery explicitly. Recovery preserves line endings and original bytes on disk; it does not insert replacement characters or edit the source.

Native Oodle-0 port, original-DLL parity results, scope and reproduction steps: [research report](../research/oodle0/README.md).

## GR2 preview verification (1.4.1)

- The 21 GR2 files in the supplied client reconstruct successfully: six base models, 17 embedded textures across those models, and 15 action files with matching base models.
- All 104 tests pass. An authored triangle verifies indices, UV/material binding and raw BGRA-to-RGBA conversion; invalid indices are rejected and unsupported textures retain wireframe geometry with a report.
- GPU snapshots cover wireframe and textured views of all six supplied base models. Unmaterialed skeleton helper meshes remain visible in wireframe and are hidden in textured mode.
- The packaged app was checked with a standalone guardian model and `data/model/3dmob_bone/8_damage.gr2` inside the supplied data.grf, including automatic base-model matching and both display modes.
- Reproduction and pinned upstream source are documented in [the bundled-reader notes](../scripts/granny-preview/README.md). No game assets are redistributed.
