# Task 1 — Wire format, C decoder, Swift writer, round-trip check

## Context

Swift takes over all per-frame geometry; native code keeps only pixels (plan Decision §2).
This task creates the single definition of the frame contract — C header
`src/render/display_list.h` (Contract §1) — plus its C decoder, the Swift
writer that emits it, and the swiftcore round-trip check that pins the two
together. Consumers: Task 2 (`DisplayList` item decodes with `pd_dl_decode`);
Tasks 4–8 (Swift builders emit through `DisplayListWriter`).

## Exact write set

- `src/render/display_list.h` (new)
- `src/render/display_list.c` (new)
- `src/render/module.modulemap` (new)
- `src/swift/app/timeline/DisplayListWriter.swift` (new)
- `src/swift/app/CMakeLists.txt` (import wiring only)
- `CMakeLists.txt` (`display_list.c` in `porydaw_app` source list)
- `src/checks/CMakeLists.txt` (new check source + any needed module-map flag)
- `src/checks/displaylist/DisplayListChecks.swift` (new)
- `src/checks/checkcatalog.cpp` (`swiftSuite` registration)
- Swift suite dispatch: `src/checks/support/corecheck/core_check.h`,
  `src/checks/support/corecheck/CoreCheckSupport.swift`,
  `src/checks/support/corecheck/tst_swiftcore.h`,
  `src/checks/support/corecheck/tst_swiftcore.cpp`

## Prerequisites

- None (first interface-producing task; Task 2 consumes `pd_dl_decode` and the header).

## Interface contract

 - `src/render/display_list.h` is the only format definition, exactly the
  Contract §1 text (plan.md:88-133): `PD_DL_MAGIC` (`0x314C4450u`),
  `PD_DL_VERSION` (`1u`), `PdDlHeader` (24 B; arrays follow in order fonts,
  rects, labels, text, each array start 8-byte aligned), `PdDlFont` (24 B:
  id, weight, letterSpacing, familyOffset, familyLength), `PdDlRect` (48 B:
  x, y, w, h in viewport logical px with w,h > 0; id; argb; flags with
  `PD_DL_RECT_OVER = 1u`: paint above this list's labels), `PdDlLabel`
  (64 B: x, y, w, h with text laid out in (w,h); id; textOffset,
  textLength; argb; flags with `PD_DL_LABEL_CLIP = 1u` and
  `PD_DL_LABEL_ALIGN_{LEFT = 0u, RIGHT = 2u, CENTER = 4u, MASK = 6u}`;
  fontId; pixelSize), reserved ids (`PD_DL_ID_NONE = 0`,
  `PD_DL_ID_LOOP_START`, `PD_DL_ID_LOOP_END`), `PdDlView`
  (header/fonts/rects/labels/text pointers), and
  `bool pd_dl_decode(const void *bytes, size_t length, PdDlView *out)`.
 - Paint order is under-rects (record order) → labels (record order) →
  over-rects (record order), where a rect is "over" iff `PD_DL_RECT_OVER`
  is set (plan.md:135-145). Layout is the running build's C ABI
  (in-process, never persisted).
- `pd_dl_decode` validates magic, version, 8-byte alignment of every array
  start, and bounds of every offset/length (including font family and label
  text ranges); returns false on any inconsistency; allocates nothing and
  writes `PdDlView` over the caller's buffer only on success.
- `module.modulemap` declares `module NativeDisplayList`, precedent
  `src/ui/songview/quick/swiftroll/native/module.modulemap:1-4`.
 - `DisplayListWriter` (`src/swift/app/timeline/DisplayListWriter.swift`):
  `struct DisplayListWriter` with `rect(_ r: PdDlRect)`,
  `label(_ l: PdDlLabel, text: String)`, `font(_ f: PdDlFont, family: String)`
  (C structs by value; the writer fills the text offsets/lengths),
  `finish() -> Data`; pads each array to 8 bytes; retains `Data` capacity
  across frames (`removeAll(keepingCapacity:)`); appends imported C struct
  bytes with `withUnsafeBytes(of:)` — the sanctioned C-interop exception to
  the Span/RawSpan buffer rule.
 - Check suite `src/checks/displaylist/DisplayListChecks.swift` registered as
  `swiftSuite("swiftcore-displaylist", "displayList")` beside the existing
  entries in `src/checks/checkcatalog.cpp:107-127`, with matching dispatch:
  next free `PDC_SUITE_*` constant in `core_check.h` (current highest is
  `PDC_SUITE_THEME_COLOR = 33` at
  `src/checks/support/corecheck/core_check.h:39-41`), new `case` in
  `pdcSuiteRun` (`CoreCheckSupport.swift:122-248`), new slot in
  `tst_swiftcore.h:46-47` / `tst_swiftcore.cpp:181-184` following the
  `themeColor` precedent.

## Implementation steps

1. Write the header verbatim from Contract §1 plus the `pd_dl_decode`
   declaration; no Qt includes.
2. Write the decoder: check length ≥ header, magic, version, then walk the
   four sections computing aligned starts; bounds-check every count-derived
   span and every font `familyOffset + familyLength` / label
   `textOffset + textLength` against the text block; `false` on any failure.
3. Add the module map; wire Swift import in `src/swift/app/CMakeLists.txt`
   beside lines 180-194 (add `-Xcc -fmodule-map-file=` pointing at the new
   map and `-Xcc -I${CMAKE_SOURCE_DIR}/src/render` following the
   `SWIFT_GRID_NATIVE_DIR` precedent at lines 190/192).
4. Root `CMakeLists.txt`: add `src/render/display_list.c` to `porydaw_app`
   beside lines 180-201. No `project()` change: C is already enabled
   (`CMakeLists.txt:2` reads `LANGUAGES C CXX`).
5. Write `DisplayListWriter`; run `deno task lsp:swift` after the CMake
   reconfigure and before any rename (Global Constraints).
 6. Write the round-trip check: build one list with ≥2 fonts (one with
   non-ASCII family bytes), ≥3 rects (reserved loop ids plus a max-value u64
   id; at least one rect with `PD_DL_RECT_OVER` set and one without), ≥3
   labels (one with `PD_DL_LABEL_CLIP`, multi-byte UTF-8 text, two labels
   sharing a font with different pixelSize, and alignment bits covering at
   least two of LEFT/RIGHT/CENTER); decode with `pd_dl_decode`; compare
   every field including both flags fields and the alignment bits;
   assert Swift-visible `PD_DL_VERSION` equals the decoded header constant.
   Negative cases (each must return false): truncated buffer, bad magic, bad
   version, misaligned array start, `textOffset + textLength` past the text
   block.
7. Register sources: new Swift file in `src/checks/CMakeLists.txt`
   (precedent `themecolor/ThemeColorChecks.swift` at line 79); add the
   `-fmodule-map-file` for the new map to the `swift_core_check` compile
   options at `src/checks/CMakeLists.txt:319-325` — required, because the
   new check source imports `NativeDisplayList` under that target.

## Acceptance predicate

- `deno task build:checks` covers C/C++/Swift/QML compilation of the new
  header, decoder, writer wiring, and check registration.
- `deno task checks --filter displaylist --verbose` covers the round-trip
  contract (field-by-field equality, `PD_DL_VERSION` match, all five
  negative cases).
- Gap: writer reuse across frames (`keepingCapacity`, no per-frame
  allocation) has no check; verify by inspection only. Performance of the
  writer is gated by Task 0 / Task 4 smoke, not here.

## Task-specific constraints

- `withUnsafeBytes(of:)` is allowed only for appending the imported C
  structs; all other buffer work follows the Span/RawSpan rule.
- ≤2-line comments; no hard-coded pixels in Swift sources; `deno task` only.
