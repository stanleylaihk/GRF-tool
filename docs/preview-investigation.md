# SPR / PAL / ACT preview investigation

## Original symptom and reproducible boundary

The operator could browse the supplied GRF indexes but could not preview SPR,
PAL or ACT. A real-archive Swift test against `cloud_*.grf` reproduced zlib -3
before SpriteDecoder was reached. Initially 39 sampled SPR previews failed.
This was distinct from the missing PAL/ACT UI/decoder functionality.

Three hypotheses were evaluated: additional payload encoding/encryption,
incorrect data offsets, and a nonstandard compression scheme.

## Evidence for cloud archives

Across six operator-supplied cloud archives:

- All 188,720 index entries have flag 1, equal compressed/aligned lengths, and
  lengths divisible by 16.
- Payload ranges are contiguous from byte 46 to the file table; the standard
  GRF +46 data-offset calculation is correct.
- 164 payload samples distributed through the tables failed normal zlib.
- Forcing standard GRF mixed/header DES on the first entry from each archive
  did not yield a valid zlib stream.
- No obvious key entry or extra footer metadata was found.

This supports a custom payload codec/encryption inference, not proof of AES or
any particular cipher. The user does not have a key. The app reports the
unsupported payload clearly; it does not guess keys or claim decryption.

## REA reference behavior

The user-selected SPRViewer.exe was inspected statically through REA:

- `LoadSPR` at 0x4569A4: evidence
  `ev_bbbb53416bb3e96ad38a59dd528e34a8a4eccf90b5b8dee47b3832a1c3d0680c`.
  Checks SP, recognizes 0x200/0x201, builds palettes and handles raw/RLE pixels.
- `SaveFrames` at 0x457124: evidence
  `ev_d12e0763aa1ccdb1acec3f1ddb423df580b320bfcf6457be0eca0e1ab5ad0905`.
  Iterates decoded image frames and writes numbered bitmap files.

The saved `preview-rea-evidence.json` preserves the complete records and
limitations. Static evidence does not establish execution of the Windows app,
and does not establish GRF decryption ability. PAL and ACT previews are new
requested functionality beyond this SPRViewer reference.

## Plain samples and verification

The user subsequently supplied `adata.grf` and `fdata.grf`. Both are standard,
readable GRF 2.0 archives, each with 76 SPR and 88 ACT entries. Their SPR files
use version 2.1; ACT files use version 2.5. They provide genuine preview fixtures
without changing or copying game resources into the source distribution.

The optional integration suite (`GRF_DEMO_DIR`) decodes real sprites and actions,
renders matching companion images, and checks that custom cloud payloads yield
the actionable error instead of an unexplained zlib code. Synthetic tests cover
PAL channels, palette substitution, BMP format and alpha, ACT versions,
transforms and malformed input. No game resources are committed.

Verified result: 35 tests in eight suites passed with `GRF_DEMO_DIR` set.
All 152 SPR files decoded. All 176 ACT files decoded (18,304 actions,
79,696 frames and 79,688 layers); 152 had matching SPR filenames, of which
144 had a drawable action that rendered successfully and eight had no drawable
action. The remaining 24 ACT entries had no matching SPR in that archive.

The BMP regression test caught a platform-specific issue: macOS ImageIO rejects
the V4 RGBA BMP variant. V5 with alpha masks is accepted, so transparent exports
use V5 and opaque indexed exports preserve the 256-color palette. Both variants
are decoded by ImageIO in tests, not merely checked for a BM signature.

Native UI smoke checks showed the standalone eight-frame SPR, all 256 PAL
swatches with color values, and its 104-action ACT. Equipment ACT action zero
was empty; a regression-tested default now chooses the first drawable action
(action 32 in this sample), displaying six 16×16 frames. Save One and Save All
produced decodable BMPs; the six-frame action exported six files, verified with
macOS ImageIO/sips.
The real `fdata.grf` GUI path also passed: 190 entries opened, `*.spr` matched
76 entries, a 26×26 ten-frame SPR displayed, and the corresponding ACT paired
automatically and displayed six composed 27×28 frames from action 32 of 104.
An accessibility snapshot after clicking playback timed out while the animation
was changing; continuous playback timing was therefore not independently
confirmed by that UI snapshot. Frame decoding, composition and timing metadata
are covered by the automated tests.

## Limits

Unknown custom GRF encryption still requires its key and matching codec or an
unencrypted source. ACT preview renders one SPR's layers, not an assembled
multi-file player character. Sounds/anchors are metadata; cross-component
attachment and game event playback are outside this viewer's scope.

Format references used for the new independently written parsers:

- https://ragnarokresearchlab.github.io/file-formats/spr/
- https://ragnarokresearchlab.github.io/file-formats/pal/
- https://ragnarokresearchlab.github.io/file-formats/act/
- https://github.com/MrAntares/roBrowserLegacy/blob/master/src/Loaders/Action.js

## fdata.grf bulk extraction (1.1.3)

Both supplied fdata.grf copies contain 190 indexed resources. All except
`data/etcinfo.txt` decode correctly. Its flags are 1 (unencrypted), and all three
sizes are declared as 30. Independent Python zlib streaming decodes only 29 bytes
(`loadingscreen#\r\n3#\r\n//file en`) from the declared input without reaching stream
end. Consuming the physical gap up to the next indexed payload also fails with
an invalid-distance error. This is not a filename-encoding failure, and there
is no evidence for restoring the missing bytes automatically.

Strict resource reads now identify the failing archive path. Bulk GUI extraction
continues after specifically classified unreadable-resource errors and reports
actual successful counts plus skipped paths/reasons. No partial failed resource
is created. Cancellation, unsafe/duplicate paths, existing files, changed archive
and output write errors still stop the operation. The core's default remains
strict; callers opt into continuing with an extraction report.

Regression coverage includes synthetic checksum corruption followed by a valid
resource, strict vs continuing modes, progress, absence of a partial failed file,
and both supplied fdata.grf copies extracting 189 resources byte-for-byte. All
59 tests pass with the supplied demo directory.

Desktop validation also exercised Extract All on fdata.grf. The final UI shows an
Extraction Report: 189 of 190 extracted, one unreadable file skipped, named as
`data/etcinfo.txt`. Independent Python zlib decoding verified all 189 GUI outputs
byte-for-byte and confirmed the failed resource was absent. No source archive
was modified. Project disk usage was approximately 955 MiB of hidden `.build`
artifacts, dominated by SDKExplicitPrecompiledModules (753 MiB); the application
bundle itself was only a few MiB. Build caches were not removed.

## Independent text content decoding (1.1.4)

TXT/XML/JSON/INI/CSV/LOG/MD/CFG preview now uses TextPreviewDecoder instead of
the archive's filename encoding. Automatic mode recognizes a UTF-16 BOM, then
otherwise tries strict UTF-8, CP949 and Windows CP950. Latin-1 is manual-only;
it is not used as a catch-all automatic decoder. Legacy encodings are ambiguous,
so the preview displays the actual selected decoder and offers an independent
Text Encoding picker. The same preference is available in the Encoding popover.
Changing it re-decodes cached resource bytes without reopening the GRF, changing
folder names or changing extracted bytes. Decode failure retains the picker so
a wrong manual selection can be corrected.

Text display is bounded to 2 MiB with an explicit truncation marker and safe
multibyte-prefix handling. Lua/LUB retain their existing script-specific preview.

All 62 tests passed. New coverage checks UTF-8, UTF-16 BOM, CP949, CP950, explicit
wrong-encoding failure, and bounded UTF-8 text. Local integration tests decode
num2itemdesctable.txt from supplied adata.grf, fdata.grf and RO 私服/data.grf,
including the traditional Chinese description beginning 將紅色的藥草搗碎製成的體力恢復劑.
Korean archive paths remain intact. Desktop observation also confirmed CP950
Chinese text displaying in adata.grf with Automatic selected and an independent
Text Encoding control.
