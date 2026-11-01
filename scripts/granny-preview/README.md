# Bundled GR2 preview reader

Source: https://github.com/Stitchuuuu/granny-ro-js
Pinned revision: `955189e060bf38270cbc3ea8cba610e98c7f62dc` (MIT; complete notices in LICENSE and ../../THIRD_PARTY_NOTICES.md).

The checked-in `Sources/GRFCore/Resources/granny-preview.js` is a self-contained, unminified IIFE generated from upstream modules plus entry.js / utf8.js. Normal app builds need no network, npm, Node.js or bundler. JavaScriptCore is provided by macOS. Only the bundled script is evaluated; resource bytes are passed as data, and no file/network/process APIs are exposed.

To regenerate, check out that exact revision and run:

```sh
scripts/granny-preview/build.sh /absolute/path/to/granny-ro-js
```

This development-only step uses esbuild 0.25.0 from npm. Swift validates the GR2 physical header and decompresses sections first. The adapter supplies expanded sections to the upstream object reader, preserving original file bytes for pointer fixups. It extracts material groups and embedded textures, samples time zero, skins vertices by named bone bindings, and applies model placement. An action-file companion contributes base geometry/textures while the selected file contributes the first animation pose.

The app supports RO's v6 32-bit little-endian format and Oodle-0/uncompressed sections, RAW BGRA and IGC embedded textures. Unsupported textures leave usable wire geometry and a report. Limits: 64 MiB expanded section data per input, 128 meshes/textures, 500k output vertices, 1m output triangles, 4096px per texture side and 8m texture pixels overall. The preview is static; it does not play animations.

Tests create an original triangle/RAW texture fixture and reject invalid indices. `GRF_GR2_CORPUS=/path/to/exported-corpus ./test.sh --filter GrannySceneTests` checks all 21 locally supplied GR2s including action-file companions. Set `GRF_GR2_RENDER_DIRECTORY` to render snapshots on a GPU-enabled host. Game assets are not checked into this repository.
