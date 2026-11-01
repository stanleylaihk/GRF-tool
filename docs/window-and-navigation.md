# Window and navigation fixes (1.0.1)

- Dock/Finder reopen is handled by the application delegate. It deminiaturizes
  and brings forward the registered archive window instead of opening a duplicate.
  A closed window clears the registration; the single SwiftUI main scene can be
  opened again using the existing application model.
- Only the main window is registered; open/save panels are not restoration targets.
- The folder sidebar now uses a cached hierarchy and OutlineGroup. Full paths are
  stable selection IDs; each row only labels its own folder name.
- The file table displays and sorts filenames. Full paths remain available for
  hover help, searching, extraction and Copy Paths.

Validation: 40 Swift Testing tests passed, including three window recovery
regressions, two hierarchy tests and the existing real-GRF preview suite.
Native UI checks opened fdata.grf (190 entries), expanded data/sprite, selected
the 16-entry robe folder, and showed a 57×53 five-frame SPR. After minimizing
and reopening the application from Finder, the same folder, selected entry and
preview were retained. The window used the single `main` scene identifier.

## Navigation layout — 1.1.2

The navigation row and NavigationSplitView are separate children of a VStack.
This reserves physical layout space above both columns: toolbar material cannot
cover All Files or the file-list header. A safe-area inset alone was insufficient
because the native split-view controller retained its own content layout.

Navigation controls use plain buttons with icon-above-caption labels. The sidebar
button has an accessibility label and tooltip, but no visible caption. Every icon
area and the custom search input is 32 points high, aligned at the top. Caption
space is reserved below sidebar/search for consistent alignment. The row has
12 points of bottom padding. No native toolbar item labels or button bezels are
used; this removes the automatic Hide Sidebar and Search captions. Encoding still
opens its two existing pickers. Command-F focuses search, and Control-Command-S
toggles the sidebar.

The sidebar retains its hierarchy, native keyboard selection, material background
and macOS 26 soft scroll-edge effect. Window registration only manages recovery;
it no longer forces full-size content or expanded native toolbar display modes.

Desktop validation used the supplied fdata.grf:
- All Files was visibly below the navigation row.
- Selecting sprite showed 164 entries; clicking All Files restored 190.
- Command-F plus bookitem narrowed to one file; Clear search restored 190.
- The icon-only sidebar button hid and restored the column.
- The Encoding button opened both settings.
- Screenshot inspection confirmed borderless buttons, no visible Hide Sidebar or
  Search captions, shared 32-point control areas and bottom spacing.

All 57 existing tests pass. The package remains compatible with macOS 14+;
system material and scroll-edge rendering vary by OS version.
