# Task 1 — Swift grid library in the production build

## Context

The Swift grid sources currently compile only in the isolated prototype
lane (`tools/swift_grid_prototype.ts` → its own CMake tree). This task
makes the same sources a static library target inside the production
`porydaw` build, APPLE-gated, so Task 4 can link and mount it. Producer of
the target that Task 4 consumes. Behavior-preserving: flag does not exist
yet, nothing in the app changes.

## Exact write set

- `CMakeLists.txt` (root) — APPLE-gated `add_subdirectory`/target for the
  Swift library + link into `porydaw`.
- `cmake/QtBridge.cmake` (new) — the QtBridge ExternalProject block lifted
  verbatim from the prototype CMakeLists (fetch, `qtbridge-object-return.patch`
  application, macro package, `BUILD_ALWAYS TRUE`), as a reusable include.
- `src/ui/songview/quick/swift-grid-prototype/CMakeLists.txt` — replaced
  ExternalProject block with `include(cmake/QtBridge.cmake)`;
  compile settings unchanged.
- `src/ui/songview/quick/swift-grid-prototype/CMakeLists.txt` production
  target section (new): explicit source list per the contract below.

## Prerequisites

None.

## Interface contract

- Target `swiftgrid` (STATIC, `if(APPLE)` only), producing
  `libswiftgrid` + the Swift module for C++ consumption, linked into the
  `porydaw` executable target.
- Source list: every `*.swift` directly under
  `src/ui/songview/quick/swift-grid-prototype/` EXCEPT `App.swift`,
  `MathSelftest.swift`, `PolicySelftest.swift` (app entry + selftest
  drivers stay prototype-lane). This list is the single sanctioned
  divergence; both lanes otherwise share files.
- Native seams compiled in: `native/audio_session.cpp`,
  `native/window_cancel.cpp` (production links the poryaaaa engine
  sources already; `audio_session` resolves against them).
- The prototype's `module.modulemap` and bridging includes are reused
  verbatim for the production target.
- QML: `SwiftRollOverlay.qml` does not exist yet (Task 4); this task
  qrc-embeds nothing new. No resources added.

## Implementation steps

1. Extract the QtBridge ExternalProject into `cmake/QtBridge.cmake`
   without textual change beyond parameterization by build dir; prototype
   lane includes it; `deno task prototype:swift-grid --build-only` stays
   green before touching the root CMakeLists.
2. Add the APPLE-gated `swiftgrid` target to the root build mirroring the
   prototype's Swift compile settings (`Swift_LANGUAGE_VERSION`,
   module map, include paths, framework deps Qml/Quick).
3. Link `swiftgrid` into `porydaw` (APPLE only). macOS linker dead-strips
   unreferenced Swift registrations; that is expected and acceptable.
4. Confirm no MinGW path changes: `if(NOT APPLE)` builds must not
   evaluate any Swift or QtBridge code.

## Acceptance predicate

- `deno task build:app` green on macOS (native session; Swift toolchain
  6.4 per `.swift-version`).
- `deno task verify --filter selectionkey-core --verbose` green
  (production canary — covers "flag-less app unchanged").
- `deno task prototype:swift-grid --build-only` green (lane unaffected).
- Controller runs these after the writer settles (shared tree).

## Task-specific constraints

- The vendored QtBridge patch is lifted as-is; patch elimination is a
  queued separate item, NOT this task.
- No Swift source edits. If a Swift file fails to compile in the
  production target configuration, the divergence is a brief defect —
  escalate; do not fork the file.
