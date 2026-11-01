# Third-party notices

`Sources/CGRFCrypto/grfcrypt.c`, `include/grfcrypt.h`, and `include/grftypes.h`
are from OpenKore/grftool, retrieved 2026-11-01 from:
https://github.com/OpenKore/grftool

Retrieved source tarball SHA-256:
`9dbb02ff8f8d2161994d0fbf440e0b74d7d59c3da84aae228fe1dcdd16ae45b8`.
Unmodified vendored `grfcrypt.c` SHA-256:
`7bfbe194020719398e91b35352d6c8757761284a87898397c36b0d6e2ff3dcdf`.

Copyright (C) 2004 Faithful, Hongli Lai, and Rasqual, as specified in each file.
The cryptography implementation is GPL-2.0-or-later. The original copyright and
license headers are preserved. This application is distributed under
GPL-2.0-or-later; see LICENSE. No original Windows executable, DLL, or game assets
are included.

GRFCore uses the system zlib library. Swift GRF index parsing and sprite decoding
were implemented for this application, with format behavior checked against
OpenKore/grftool and Ragnarok Research Lab's format documentation:

- https://github.com/OpenKore/grftool/blob/master/lib/grf.c
- https://github.com/OpenKore/grftool/blob/master/lib/sprite.c
- https://ragnarokresearchlab.github.io/file-formats/grf/
- https://ragnarokresearchlab.github.io/file-formats/spr/


## Granny GR2 preview reader and Oodle-0 native decoder

`Sources/GRFCore/Oodle0Decoder.swift` is adapted from the MIT-licensed
`src/GrannyOodle0.js` in granny-ro-js, pinned commit
`955189e060bf38270cbc3ea8cba610e98c7f62dc`:
https://github.com/Stitchuuuu/granny-ro-js

`Sources/GRFCore/Resources/granny-preview.js` also bundles the GR2 type-tree, mesh, skeleton, model, first-pose and texture readers (including IGC arithmetic / wavelet decoding) from the same pinned revision. The app adapter and reproducible bundle build are in `scripts/granny-preview`. The JavaScript runs locally in the system JavaScriptCore framework, with native Swift section decompression.

That implementation credits the MIT-licensed Python decoder in
https://github.com/Rasetsuu/blendergranny. No proprietary SDK source,
Windows runtime, executable, DLL, or game asset is bundled.

MIT License

Copyright (c) 2026 Stitchuuuu <stitchuuuu@icloud.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

----------------------------------------------------------------------

PORTIONS DERIVED FROM Rasetsuu/blendergranny

The Oodle0 decompressor in src/GrannyOodle0.js, the GR2 header / section
table parser in src/GrannyFile.js, and a few helper constants are a
JavaScript port of the clean-room Python implementation in
https://github.com/Rasetsuu/blendergranny (commit on `main` as of
2026-06-28), originally licensed MIT :

  MIT License

  Copyright (c) 2026 ciupix and contributors

  Permission is hereby granted, free of charge, to any person obtaining
  a copy of this software and associated documentation files (the
  "Software"), to deal in the Software without restriction, including
  without limitation the rights to use, copy, modify, merge, publish,
  distribute, sublicense, and/or sell copies of the Software, and to
  permit persons to whom the Software is furnished to do so, subject to
  the following conditions:

  The above copyright notice and this permission notice shall be
  included in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

