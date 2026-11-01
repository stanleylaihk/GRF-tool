# GAT / GND previews — 1.3.0

The browser and standalone Preview File support GAT 1.2/1.3 and the common
terrain layout of GND 1.6–1.9. Finder/open/drop resource routing includes both
extensions. Unsupported signatures/versions show an explanation, not text or
invented geometry. Input is capped at 64 MiB, 2,048 cells per axis and 1,000,000
cells total. Counts, table ranges, finite floats and positive geometry scale
are checked before any rendering or export.

The layout was checked against the original loader implementations:

- [BrowEdit GAT loader](https://github.com/Borf/BrowEdit3/blob/master/browedit/components/Gat.cpp)
- [BrowEdit GND loader](https://github.com/Borf/BrowEdit3/blob/master/browedit/components/Gnd.cpp)
- [roBrowser GAT loader and conventional types](https://github.com/vthibault/roBrowser/blob/master/src/Loaders/Altitude.js)
- [roBrowser GND loader](https://github.com/vthibault/roBrowser/blob/master/src/Loaders/Ground.js)

No loader implementation was copied. This Swift reader uses major/minor bytes,
little-endian dimensions/floats, GAT 20-byte cells, GND 40-byte surface records
and 28-byte cells. GND lightmap byte count includes the grid size multiplier.
Names try UTF-8, the selected filename encoding, then visible replacement
characters; original GRF/resource data is never rewritten by previews.

A binary-backed immutable document retains file bytes rather than allocating
an object per cell. Background decoding validates the grid and creates a
one-pixel-per-cell RGBA map. GAT uses the low byte for conventional colors:
0 green (walkable), 1 charcoal (blocked), 3 blue (walkable water), 5 orange
(blocked with ranged attacks passing), other values purple. Raw 32-bit types
are preserved in JSON, including additional 1.3 flags. RSW water levels and
runtime navigation behavior are not inferred.

GND elevation uses the negative mean of the four raw heights, normalized to
the file height range. Light colors mean higher elevation; top-surface index
-1 is charcoal. The UI does not render textures, lighting, walls, water or
scene objects. GND trailing data (including later water extensions) is retained
as additionalDataBase64, not interpreted as geometry or claimed as water preview.

The viewer uses zero-based file coordinates with y=0 at the top; the height
array order is bottom-left, bottom-right, top-left, top-right. This is an
inspector coordinate system, not a conversion to game-world coordinates.
Fit, zoom, direct map clicks and X/Y input all select the same grid cell.
Info lists map statistics and texture names. JSON shows only the summary,
selected cell and its referenced GND surfaces; large grids stay out of the text
view. Full export uses schemaVersion 1 with summary, textures, surfaces, cells,
lightmapDataBase64 and additionalDataBase64. Heights and raw types/indices are
preserved. It is an inspection export, not a round-trip map editor.

JSON export runs on a background task and streams records/49,152-byte base64
chunks through a unique sibling temporary file. Cancellation is checked every
256 records and each base64 chunk. Success atomically publishes the result;
errors/cancellation preserve any existing output. Source URLs are protected in
the save UI; unrelated replacements require native save-panel confirmation.
Leaving the map viewer requests cancellation. This operation never changes GRFs.

Validation on 2026-11-01: 73 tests across 16 suites passed, including synthetic
asymmetric grids, raw flags and unknown types, signed surface indices, GND
lightmap stride, unsupported versions, truncation, excessive counts/dimensions,
non-finite coordinates, JSON payloads and cancellation/output protection.
The supplied RO 私服/data.grf contains 1,428 map resources. Eight selected
GAT/GND maps decoded and rasterized successfully, including four encrypted
with standard GRF header encryption. This is sample coverage, not a claim that
every map or every custom extension was validated. cloud_main content remains
undecodable by the standard archive reader, independently of map support.

Desktop checks: opened a generated GRF with asymmetric GAT/GND fixtures; tested
Preview/Info/JSON, X/Y selection, direct map clicks and export. The selected
(3,2) GAT cell retained heights [23,24,25,26] and raw type 99. A direct center
click selected (2,1), matching row order and pixel colors. A standalone real
GND (pvp_y_2-2.gnd, extracted locally for testing) rendered at 134x150. Its UI
JSON export was independently checked with Python struct parsing: all 20,100
cells, 20,358 surfaces, texture paths, and 951,808 lightmap bytes matched.
No sample game assets were added to the source tree.

The desktop browser also reopened the user's 60,197-entry data.grf and searched
in_sphinx1.gat. Its encrypted 300x300 map preview, zoom and direct selection
worked; selecting the center showed file coordinate (150,150) as walkable.
