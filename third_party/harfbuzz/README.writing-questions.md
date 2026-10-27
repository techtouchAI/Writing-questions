# HarfBuzz 10.4.0 — OpenType emission dependency

Unmodified library .h/.hh/.cc sources from src/ and root COPYING from the pinned upstream10.4.0 tag:
https://github.com/harfbuzz/harfbuzz/tree/10.4.0
Source archive SHA256: 0d25a3f74af4e8744700ac19050af5a80ae330378a5802a5cd71e523bb6fda1f

Only the library sources/license are vendored; unrelated tests, WASM examples, sample fonts and generators are omitted. No font assets changed.
Android CMake builds the same amalgamated src/harfbuzz.cc as the Linux test
runtime. PDF emission consumes the existing canonical word origin, font size,
direction and advance; this dependency does NOT reflow or paginate text.
It supplies GSUB glyph IDs and GPOS positions missing from the legacy Amiri
presentation-form path. Font bytes and Unicode extraction remain unchanged.
