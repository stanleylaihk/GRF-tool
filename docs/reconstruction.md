# GRF Tool reconstruction evidence

## Reference target

- Operator-selected reference: `/Users/successslai/Git/REA/grftool-win32-1.2.0/grftool.exe`
- SHA-256: `9e171bec26cc1ead29317153be0ddf9c04e132db8fd0538a96bda1a1dfeb5680`
- PE32, x86, Windows GUI, 1,094,144 bytes.
- The executable was not run. REA analysis is shipped-artifact static evidence.

## REA observations

- Resource inventory: `ev_7b1b95d8c871db9d0c7207b283ea2a445f0363151e1c6fa8f1fcb24fe053c6d7`.
  Complete resource tree with 90 resources; Delphi forms include open archive,
  search (wildcards), extract selected/all, preview toggle, copy, save dialog,
  and filename-encoding settings. REA leaves form payloads opaque; captions and
  events were corroborated by direct string inspection of those payload bytes.
- Import inventory: `ev_db92cdac7bd5aae04eb21ff81e9e8567ead3e9bb74ea3dd387409edd75b2cfa7`.
  The binary imports `grf_callback_open`, `grf_find`, `grf_chunk_get`,
  `grf_index_chunk_get`, `grf_extract`, `grf_free`, and `grf_strerror` from `grf.dll`.
- Embedded extension strings include BMP, TXT, WAV, SPR.
- The operator-provided README explicitly describes preview, browse and extract,
  and explicitly excludes archive additions/deletions.
- `rea-evidence.json` retains complete portable Evidence for imports and resources.

## Corroboration, not identical-source provenance

OpenKore/grftool public source was retrieved from
https://github.com/OpenKore/grftool/archive/refs/heads/master.tar.gz on 2026-11-01.
Its current `win32/Main.pas` corroborates Korean CP949 name handling and previews
for BMP/JPG, TXT/XML, WAV, and SPR. Current source is not asserted to be the exact
source revision of the supplied executable. Additional current-source features
are not automatically part of the 1.2.0 baseline.

## Feature mapping

| Reference behavior | macOS implementation |
| --- | --- |
| Browse GRF/GPF | GRFCore immutable index; SwiftUI folder sidebar and file table |
| Filename/wildcard search | Case-insensitive path/filename search with `*` and `?` |
| BMP/JPG preview | AppKit image decoder |
| TXT/XML preview | Unicode and selected legacy encoding |
| WAV preview | AVAudioPlayer |
| SPR preview | Bounded Swift decoder, indexed/RLE/ABGR frames |
| Extract selected/all | Background extraction, progress and cancellation |
| Unicode/original ANSI output names | Unicode default; raw-byte mode limited to UTF-8-compatible filenames on macOS |
| Copy | Copy selected paths to clipboard |

Native macOS behavior deliberately differs in presentation: folder extraction
preserves archive paths, while the single-file context menu supports Save As.
Folder output conflicts stop extraction rather than overwriting. Save As uses
the native save dialog's overwrite confirmation. No pixel-identical UI
or Windows runtime behavioral equivalence is claimed.

## Verification boundaries

Automated tests use generated archives/sprites, including legacy and encrypted
entries. This verifies declared fixtures, not every historical GRF variant.
20 tests passed in two Swift Testing suites on the development host. Coverage
includes byte-exact nested extraction, empty files, CP949, legacy 0x102, both
standard encrypted v2 data modes, corrupt tables/content, path and symlink
escapes, duplicate outputs, cancellation, and indexed/RLE/truecolor SPR frames.
Native UI smoke checks opened a generated three-file GRF, displayed text and
SPR previews, and filtered the file list with `*.spr`.
The UI Extract All action was also tested while a filter was active: all three
archive entries were exported, and both text payloads matched byte-for-byte.
The original build used generated fixtures only. Subsequent SPR/PAL/ACT work
uses the supplied adata/fdata archives as opt-in integration inputs; see
preview-investigation.md for the newer verification and cloud codec limitation.
Custom encryption and GRF 3.x remain unsupported. ACT-driven animation is now
supported for paired SPR files.
Memory limits and extraction behavior are documented in README.
macOS rejects non-UTF-8 CP949 output filename bytes with EILSEQ, confirmed by a
POSIX open test outside the execution sandbox. Unicode conversion is therefore
required for such filenames; byte-for-byte Windows ANSI output is not portable.
