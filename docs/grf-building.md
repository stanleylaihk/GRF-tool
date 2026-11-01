# GRF building and editing — 1.2.0

New GRF (toolbar or Command-N) starts an empty draft. The Archive toolbar
popover opens a working copy for Merge GRF / Folder, Delete Selected or Repack.
Import accepts multiple GRF/GPF archives or folders; choosing a folder named
data preserves data/... paths. Empty archives are allowed; empty directories
create no records. Save GRF As / Repack As publishes a separate unencrypted
GRF 2.0 and opens it with the selected output filename encoding.

Merge policies are Keep existing (default), Replace with imported, or Reject
duplicates. Keys are NFC-normalized and case-insensitive. Duplicates inside
any single source reject that source; a failed or cancelled import leaves the
entire draft unchanged. Import filename encoding is independent of output
encoding. Delete stages selected resources; Undo Delete restores the last
deletion. Closing a changed draft requires explicit discard.

Repack decodes all retained resources and rebuilds payload streams and the
index, eliminating unreferenced bytes. It may not reduce size. Corrupt or
unsupported resources abort the build with their path; no implicit skipping
occurs. The supplied fdata/adata data/etcinfo.txt is damaged: replace it with
valid content or explicitly remove it to save those archives.

The independent native Settings window (Command-comma or toolbar Settings)
persists Default (-1) or zlib levels 0–9 in UserDefaults. All write workflows
capture the selected level at Save and use it for both payloads and index.
Settings changes affect subsequent writes only. Level 0 retains zlib framing
without compression; 1 prioritizes speed and 9 prioritizes compression.

The format uses a 46-byte header, little-endian GRF 2.0 records, backslash
encoded names, flags=1, independent zlib streams and a compressed index.
CP949 defaults for game compatibility; UTF-8, Big5 and Latin-1 are selectable.
Names must round-trip losslessly and fit 255 encoded bytes. No Windows DLL.

Folder sources stream in 64 KiB chunks. Archive sources decode one resource
in memory at a time (up to 512 MiB), then compress in 64 KiB chunks; the whole
archive is never loaded. Index compression remains in memory. Expanded and
compressed indexes are bounded by 256 MiB, resource streams by 512 MiB, and
output by 4 GiB. Draft preparation and imports run off the main thread; saves
report byte progress and cancellation. Cancellation is checked between decode
and compression; an individual archive decode is not interrupted midway.

Source files are opened O_NOFOLLOW and checked against staged size and mtime
and descriptor metadata before/after packing. GRF reads additionally validate
the indexed file's device, inode, size and nanosecond mtime. The browser source
and every imported archive remain protected even after removing their entries.
Changing source files requires reopening/reimporting them.

Output is built in a unique sibling temporary file, synchronized and closed,
then published atomically. Non-overwrite callers use RENAME_EXCL. Native save
panels confirm replacing unrelated existing destinations. Errors/cancellation
clean temporary files and preserve any existing output. Source archives are
never selected as output; drafts exist in memory only.

Automated validation: 66 tests in 15 suites, including real demo archives,
merge policies, deletion and exact payload comparison, all compression levels,
reclaiming appended unused space, cancellation, changed sources, atomic output
protection and corrupt-fdata recovery after explicit removal. Existing coverage
includes 1.125 GiB folder packing, encrypted/legacy reads, CP949/Big5, previews,
path and symlink rejection. Windows game-client runtime is not tested.

Desktop verification (2026-11-01): clicked Archive > Merge, selected Replace
with imported, imported a second GRF, deleted a resource, undid and repeated
the deletion, then saved and automatically reopened the result. Independent
Python zlib/table parsing confirmed exactly the expected payloads and level-9
stream headers. Repack with Settings level 0 produced identical resource
content and level-0 headers. SHA-256 confirmed both original sources unchanged.
The Archive > Delete Selected shortcut staged the browser selection correctly;
closing prompted to keep or discard the draft. Settings opened independently
from both browser and editor, persisted across app restart, updated the editor
immediately, and Restore Default worked. The final save panel uses a single
.grf extension. The release app's ad-hoc code signature was verified.
