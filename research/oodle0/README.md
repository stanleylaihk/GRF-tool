# Native Oodle-0 port: verified against the supplied RO runtime

Result: a native Swift decoder now decompresses all 43 nonempty Oodle-0
sections in the 21 GR2 files from the supplied `data.grf`. Every decoded byte
matches the original 2002 Granny DLL's decoder under isolated x86 emulation.
The Mac app uses Swift only; it does not load or redistribute the DLL,
require Windows, Wine, Node, or Unicorn at runtime.

## Scope and evidence

The selected DLL is `grf/RO 私服/granny2.dll`, PE32 x86, 230455 bytes,
SHA-256 `befa33fb43f03c6d0b9cbb302bfd7eb7efa2ba8ec682f75f63ac5cd03653570d`.

REA/Hopper static analysis established:

| Entry | Address | Evidence |
| --- | --- | --- |
| `_GrannyDecompressData@28` exported wrapper | `0x100274d0` | `ev_6e91a7382723b28150508ea9e13b6b100665f7b1475d7c7081c949c460acab23` |
| Compression dispatch, mode 0 copy / mode 1 Oodle-0 | `0x100140d0` | `ev_57e547fa69c1f1f433464a5268e23a5e36939b2683fc2fe1e0bb0a32ce9a8746` |
| Six-argument Oodle-0 core | `0x1001d060` | `ev_5103b36574afb327a96fdb02ab4b58e9c9c580e8033a171aa4b13aa9513e47a1` |

Full static Evidence and its limitations are preserved in `rea-evidence.json`.
Decompiler signatures/pseudocode are observations, not original source.
The dispatch's profiling calls are bypassed by entering the codec core directly.

The codec core accepts compressed size, input pointer, stop0, stop1, expanded
size, output pointer. These correspond to the public seven-argument API after
removing the compression-mode selector. GR2 section fields +20/+24 supply
stop0/stop1; the final stop is the expanded byte count. A section begins with
three 12-byte LZ headers, followed by a shared arithmetic bitstream.

## Implementation

- `Sources/GRFCore/Oodle0Decoder.swift`: native 31-bit arithmetic decoder,
  adaptive symbol models with 16-bit counter behavior, three-block LZ77 with
  overlapping back-references.
- `Sources/GRFCore/GrannySectionDecoder.swift`: GR2 v6 section decoding for
  mode 0 (raw) and mode 1 (Oodle-0); returns sections in original index order.
- App GR2 information preview now reports native section-decompression success
  or the exact failure while retaining readable header metadata.

The Swift port adapts the MIT implementation in
[granny-ro-js](https://github.com/Stitchuuuu/granny-ro-js), pinned commit
`955189e060bf38270cbc3ea8cba610e98c7f62dc` (2026-07-13), which credits the MIT
[blendergranny Python decoder](https://github.com/Rasetsuu/blendergranny/blob/main/io_scene_gr2/gr2/decompress/oodle0.py).
Copyright and license notices are included in `THIRD_PARTY_NOTICES.md`.
No leaked SDK source was downloaded or used. Upstream JS comments mention a
leaked SDK as a historical author-side parity oracle; this research instead
validated against the user's supplied DLL machine code.

Earlier claims that no usable Oodle-0 implementation exists were outdated:
OpenGR2 still lacks the codec, but these newer implementations provide it.

## Original-runtime differential verification

`dll_oracle.py` maps only the digest-locked original PE into Unicorn 2.1.4 and
emulates the known decoder core with bounded memory and instruction/time limits.
Two allocation/free callbacks use a private guest heap. It never calls DllMain,
loads Windows imports, or launches the game. Guest code has no OS/filesystem or
network interface. This is controlled CPU replay, not a Windows runtime test.

The original-runtime output covers 50 nonempty sections total (43 compressed,
7 raw), 1687316 decoded bytes across all 21 files. `dll-section-hashes.json`
records original file hashes, section hashes and byte counts;
`corpus-paths.json` maps the research IDs to original archive names. No game
asset bytes or DLL are committed or distributed.

Reproduce with a temporary Python environment containing Unicorn 2.1.4:

```sh
GRF_SCENE_ARCHIVE='/path/to/data.grf' GRF_GRANNY_CORPUS=/tmp/oodle-corpus \
  ./test.sh --filter GrannyResearchCorpusTests
/path/to/python research/oodle0/dll_oracle.py \
  '/path/to/granny2.dll' /tmp/oodle-corpus /tmp/oodle-dll-output
GRF_GRANNY_CORPUS=/tmp/oodle-corpus GRF_OODLE_ORACLE=/tmp/oodle-dll-output \
  ./test.sh --filter Oodle0DecoderTests
```

On this managed Mac, Unicorn needed permission to create executable memory;
its initial restricted invocation stopped with SIGILL, and the same bounded
script succeeded with the required execution permission. This is a research
tool requirement only, not a requirement of the Swift decoder or app.

Verification passed:

- Original DLL vs Swift: 43/43 Oodle-0 sections, exact byte equality.
- GR2 section integration API vs the same original outputs: exact equality.
- Constructed literal-only stream (no game data), malformed sizes/alphabet,
  block boundaries, truncated headers and output/expansion caps.
- Existing full suite: 89 tests passed before the final synthetic/integration
  additions; the final three decoder tests passed after those additions.

## Limits / remaining work

This verifies the supplied 21-file corpus, not every Granny or Oodle variant.
Mode 2 Oodle-1, BitKnit and other Granny versions remain unsupported. Reads
allow at most 32 zero-padding bytes; section output and total decoded GR2
preview size are capped at 64 MiB. There are alphabet, expansion-ratio,
back-reference and work limits. Invalid block boundaries are rejected.

Decompressed sections are still serialized object data. Pointer relocations,
type-tree parsing, mesh/skeleton/animation interpretation and rendering are
separate work. Native decompression success does not yet constitute a 3D
model preview. This port does not implement texture IGC decompression.
