# Scripts and large archive loading (1.0.2)

Lua/LUB previews inspect contents, not extensions: source is shown as text;
Lua 5.1 chunks are parsed into a bounded disassembly with constants, prototypes,
line references and instructions. Scripts are never executed. Other Lua chunk
versions and LuaJIT are explicitly identified and shown as bounded hex previews.
Source decoding prefers UTF-8, then the selected legacy encoding and Big5.
Ambiguous legacy encodings cannot be identified perfectly from bytes alone.

The bytecode layout was checked against primary format/VM sources:
- https://www.lua.org/source/5.1/lundump.c.html
- https://www.lua.org/source/5.1/lopcodes.h.html

Loading now reports actual index-read bytes, compressed-index input consumed,
and index entries parsed. The visual bar allocates ranges to these phases and
then to folder/list preparation; it is not a timer or a claim that all payload
bytes have been read. Reading, decompression and parsing are cancellable.
Index preparation and initial sorting run away from the main actor. Progress
callbacks are throttled, monotonic in the UI and ignored after completion or
when their request identity is stale. Failed/cancelled loads retain the previous
archive. Existing index size and record count limits remain in force.

The bottom status message identifies the archive and current phase; its tooltip
contains the full local path. A fixed-width centered icon precedes each filename.
Folder English labels come from a local glossary and never alter archive paths.

Tests cover source/compiled LUB, CP949/Big5, endian and string-size variants,
malformed chunks and bounded Unicode previews. Loading tests check progress
counts, cancellation in each index phase, a sparse 1.5 GiB archive with a tiny
index, and the supplied real 1.7 GiB data.grf. Game resources are not copied into
the source distribution.

The file list uses a reusable-cell NSTableView with an ID-to-row selection index;
preview updates do not reload all archive rows. Its filename column reserves a
22-point centered icon area. Native text scrolling handles source/disassembly.
Both panes receive bounded sizes from the split view. Context actions remain
available through a native menu.

Validation: 51 tests pass with supplied resources, including the 60,197-file
1.7 GiB archive. Desktop checks observed the bottom loading bar and actual
in-archive `_debugwndinfo.lua` source and `_debugwndinfo.lub` Lua 5.1 disassembly.
