# Task 1 — Swift grid library in the production build

## Context

Build the single shared Swift source set as an APPLE-only production library
and preserve the standalone acceptance lane. Consumer of Task 2's declared
module-map/header paths; producer of imports/linkage for Tasks 2–4. Read
[plan.md Global Constraints](plan.md) and [spec.md](spec.md). The approved
QtBridge API correction exposes existing QML type registration to a host
that already owns its application/engine; it does not add a second engine.

## Exact write set

- Root `CMakeLists.txt`: APPLE-only Swift enablement/target integration,
  production observer source registration, transitive library linkage.
- `cmake/QtBridge.cmake` (new): shared FetchContent setup, pinned at
  `407714006dd21107b70db6547ce75e43df0c8a75` with existing patch mechanism.
- `src/ui/songview/quick/swift-grid-prototype/CMakeLists.txt`: shared dependency
  include, production source list, standalone dependencies and Swift flags.
- `src/ui/songview/quick/swift-grid-prototype/qtbridge-object-return.patch`
  and `PatchQtBridge.cmake`: preserve existing fixes and add only the approved
  `QmlInstantiable.registerQmlElement()` access change from package to public.

## Prerequisites

Task 2's declared files/module contract, not its implementation. Tasks 1 and
2 write disjoint files concurrently; linked verification waits for both.

## Interface contract

- `swiftgrid` is STATIC and APPLE-only. Both lanes use Swift module name
  `SwiftGrid`; production links through `porydaw_app` so both `porydaw` and
  `porydaw_checks` resolve it without duplicate Swift/native definitions.
- Explicit production Swift list: shared prototype-directory sources except
  `App.swift`, `MathSelftest.swift`, `PolicySelftest.swift`; include Task 2's
  `SgdDocument.swift`. Task 4 later adds `SwiftGridHost.swift` to this list.
  Excluding standalone entry/selftest drivers is the only source divergence;
  fixture/demo setup is not run by production initialization.
- Reuse native audio/curve/font/window-cancel implementations and existing
  module maps. Add the dedicated Task 2 map
  `src/ui/songview/quick/swiftgrid/module.modulemap` via
  `-Xcc -fmodule-map-file=...` and its include directory to BOTH Swift lanes.
  The module is `SwiftGridDocumentFeed`; do not edit the old module maps.
- Compile `swiftgrid/document_feed.cpp` once per binary's build graph and
  link it into both lanes; compile `swift_grid_document_feed.cpp` once in
  production `porydaw_app`. The prototype needs the POD endpoint ABI, not
  another SongDocument/core build. Production resolves native seam and
  observer dependencies against existing engine/core/math objects; never
  copy standalone engine/core lists into production.
- Task 2 owns `src/checks/CMakeLists.txt` and its Swift check target; expose
  Swift module/include/link requirements through `swiftgrid` for that target.
- No QML resource additions until Task 4. No registration call until flag-on
  mount; public dependency API does not itself register or instantiate types.

## Implementation steps

1. Extract shared FetchContent setup preserving revision, patch application
   and existing fixes. Add the approved single access change to the patch
   and its idempotent application checks; do not expose proxy internals or
   introduce alternate wrappers, ExternalProject or BUILD_ALWAYS.
2. Add production target with the prototype's QtBridge/Swift compile settings,
   framework include precedence and explicit shared Swift list. Add Task 2
   module flags/source registrations to both lanes with the ownership above.
3. Resolve native seam dependencies against already-compiled production
   implementations and link through `porydaw_app`; keep standalone targets
   self-contained. No duplicate production core compilation.
4. Preserve NOT APPLE behavior: no Swift/QtBridge configure, source or link
   work evaluates there. Task 4 owns later QML/resource and host-source adds.

## Acceptance predicate

After Tasks 1 and 2 settle, controller runs:
- `deno task build:app` — shared production sources/imports/native symbols.
- `deno task verify --filter selectionkey-core --verbose` — flag-off canary.
- `deno task prototype:swift-grid --build-only` — preserved standalone lane.

Native macOS session and Swift 6.4 from `.swift-version` are prerequisites.
Actual public registration is exercised by Task 4's production mount gate;
Task 1 build alone does not prove that path.

## Task-specific constraints

User approved the registration visibility patch extension on 2026-09-18;
all other QtBridge internals remain untouched. No Swift implementation edits
in this task. An additional access or source fork is a contract defect, not
permission to widen the patch.
