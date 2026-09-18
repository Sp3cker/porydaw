# Task 2 — `sgd_` document feed seam + revision guard

## Context

Production value delivery from the real document, consumed by Task 3's grid
and Task 4's host. Read [plan.md Global Constraints](plan.md) and
[spec.md §2](spec.md); ABI and ownership are fixed there. No core accessor,
address token, singleton receiver, or compatibility shim is introduced.

## Exact write set

- `src/ui/songview/quick/swiftgrid/document_feed.h` and `document_feed.cpp`
  (new): spec §2 POD ABI, active endpoint registration and per-token set/clear.
- `src/ui/songview/quick/swiftgrid/module.modulemap` (new): Clang module
  `SwiftGridDocumentFeed`, exports `document_feed.h` only; no Qt headers.
- `src/ui/songview/quick/swiftgrid/swift_grid_document_feed.h` and
  `swift_grid_document_feed.cpp` (new): fixed-document QObject observer.
- `src/ui/songview/quick/swift-grid-prototype/SgdDocument.swift` (new):
  public plain-value `SgdDocument` and per-binding `DocumentFeed`.
- `src/checks/swiftdocfeed/` (new): C++ fixture harness plus
  `DocumentFeedCheck.swift` and check-only C declaration header.
- `src/checks/CMakeLists.txt`, `src/checks/checkcatalog.cpp`,
  `src/checks/fwd.hpp`: APPLE-only target and harness registration.

## Prerequisites

Task 1's agreed build interface, not its implementation: dedicated module-map
flags, `swiftgrid` module, production observer registration, and shared ABI
object ownership. Writers may work concurrently; Task 2's linked check runs
only after both settle. Task 1 alone edits root/prototype CMake.

## Interface contract

- Implement spec §2 exactly, including `SwiftGridDocumentFeed` constructor,
  `documentId()`, `delivery()`, `pushSnapshot()`, and destructor order.
- Feed token is minted uniquely for the observer lifetime, constant across
  edits/undo/redo, never derived from `DocumentStateIdentity` or addresses.
- `DocumentFeed` is public and per-instance, created with `documentId: UInt64`;
  it exposes `appliedRevision`, `document`, `onDocument`, `connect() -> Bool`,
  `disconnect()`, and `apply(header:notes:signatures:) -> Bool` as specified. Copied Swift value
  structs and initializer/access needed by consumers are public. No grid
  dependency or registration global in this file; Task 3 owns grid mapping.
- Task 2 owns a check-only STATIC Swift target `swift_doc_feed_check`, compiled
  from `src/checks/swiftdocfeed/DocumentFeedCheck.swift`, importing/linking the
  shared `SwiftGrid` module from target `swiftgrid`. Link it into `porydaw_checks` on APPLE only.
  Export `int32_t sgd_check_swift_guard(void)` solely from that test target;
  zero means all guard scenarios passed. The C++ harness calls it and reports
  failures. Do not add test-only production API or recompile production Swift
  sources into the check target. GUI/main-thread entry is required.

## Implementation steps

1. Add the POD ABI, module map and live token-to-slot routing table. Set/clear
   resolve only the named active endpoint; no singleton active callback,
   cached documents, polling, or hidden initial push. Unregister erases state.
2. Implement observer snapshot assembly from public `SongDocument` APIs named
   in spec §2. Iterate engine tracks in order; copy unsigned document tick and
   duration values faithfully. Copy `DocTimeSig::numerator` and `denomPow2`
   directly into the ABI's UInt8 fields; no denominator expansion,
   normalization, clamping or rejected imported events in the feed. Preserve
   sorted order and coincident-event precedence. Constructor never delivers.
3. Implement the Swift guard and copy accepted arrays before returning.
   Unrelated identities cannot reset revisions; no dictionaries of closed
   documents. Releasing a receiver drops its snapshot and callback state.
4. Stage an existing fixture (selectionkey catalog's `{scratch}` convention;
   `mus_route101`) and assert actual contents/timebase/signatures. Bind capture,
   explicitly push, then mutate/undo/redo through public document APIs; require
   one delivery per emission, stable identity and revision advancing by one.
   Clear/destroy observer before recipient release and prove no later callback.
5. Check the actual Swift receiver via the check-only entry point: first
   revision zero; equal/lower rejected; higher accepted; unrelated identity
   rejected; two identities interleaved without contamination; fresh remount
   identity and independent lifetime. Register the APPLE-only check target
   and catalog entry. A C++ guard implementation is not an acceptable test.

## Acceptance predicate

- `deno task build:app` — production feed symbols/import dependencies link.
- `deno task verify --filter swiftdocfeed --verbose` — real snapshot capture,
  observer lifecycle, and actual Swift guard all pass in the native session.
- Controller runs named commands after Tasks 1 and 2 settle, per plan policy.

## Task-specific constraints

No `SongDocument`/`src/core/**` edits. No root/prototype CMake edits or native
module-map edits: Task 1 consumes this task's dedicated module. Snapshot
counts and value conversions must not silently truncate actual document data.
