# Task 6 — Real project persistence and session

## Context

Connect the completed core to real project files and native instrument-bank
services. Supply the ownership interface consumed by exactly one presenter in
task 8. This is not a port of the workspace UI or a legacy-editor adapter.
See [plan.md](plan.md#global-constraints) and
[spec.md](spec.md#playback-and-native-services).

## Exact write set

Create `src/swift/app/ProjectService.swift`,
`src/swift/app/DocumentSession.swift`, `src/swift/app/CMakeLists.txt`,
`src/project/swift_project_service.h`, `src/project/swift_project_service.cpp`,
`src/swift/app/module.modulemap`, `src/checks/swiftcore/SessionChecks.swift`.
Modify `CMakeLists.txt`, `src/checks/CMakeLists.txt`,
`src/checks/swiftcore/{core_check.h,tst_swiftcore.h,tst_swiftcore.cpp}`.
Read-only dependencies: `src/project/{decompproject.h,voicegroupsource.h,songregistry.h,projectio.cpp}`,
`src/core/songhistory.cpp`, `src/checks/project/save.cpp`,
`src/checks/voicegroup/tst_voicegroupbank.cpp`, `src/checks/voicegroupsave/savecore.cpp`.

## Prerequisites

Tasks 2–5 accepted. `SongDocument`/`SongHistory` provide complete edits/save
identity; `PlaybackTimeline` supplies the immutable projection. Do not define
a second state model to cross the service boundary.

## Interface contract

`ProjectService.open(root:) async throws`, `openSong(label:) async throws -> LoadedSong`,
`save(_ snapshot:) async throws -> SaveReceipt`, and confirmed bank edit/replay
operations wrap existing native project capabilities. `LoadedSong` contains
owned MIDI bytes, song/config/track-budget metadata and an immutable native bank
lease—not a C++ MIDI/document object. `SaveReceipt` identifies the exact saved
snapshot and flags result. The C adapter has one owning service handle and
operation-specific completion functions; returned callback bytes are borrowed
until return and copied once by the Swift wrapper.

The C header declares opaque `PdBankLease` and `pd_bank_lease_release`.
Each successful load/edit result transfers one owned handle to a Swift
`NativeBankLease` reference object (in ProjectService.swift); its deinit releases
the handle. Swift references share that wrapper through ARC. NativeAudio borrows
the handle only during its synchronous bind/update call; AudioEngine copies the
underlying existing `VoicegroupLease`. A C++-only accessor in the same header
returns that lease to native callers; no shared_ptr-bearing type is exposed to
the Clang C importer. The wrapper need not grow a separate C retain API.

One native worker owns `DecompProject`. Reuse its real bank and registry methods;
no custom project parser, instrument model or worker-per-operation. Preserve
existing ordered save stages and error reporting. `ProjectService` implements
the actual `BankHistoryAction` replay/merge behavior using native confirmed
receipts, including blank-slot materialization and scalar merge sealing.

`DocumentSession` owns the document, session-only selection/track scope/camera/
mute/solo state, current bank lease and playback publication. Its `onChange`
callback coordinates selection reconciliation before presentation/playback.
The document callback captures its session weakly; close breaks presenter
callbacks before releasing the session. No document/session ownership cycle.
Expose direct note selection and track selection methods; neither pushes history.
Provide `save() async throws`, `undo() async throws`, `redo() async throws`, and
`close()`. Bank transitions serialize until confirmed; document history operations
remain immediate. Close releases the native worker only after its outstanding
work/owned results have finished, following the existing service lifetime policy.

## Implementation steps

1. Implement the narrow native worker adapter over existing project APIs.
   Native reads may return file bytes; Swift performs every MIDI parse/encode.
2. Implement Swift service result ownership and `DocumentSession` composition.
   A successfully loaded session owns real file/config/voicegroup data. No
   loading placeholders masquerade as successful songs.
3. Implement detached save requests and confirmation: bank stages, MIDI, flags;
   an error remains an error and a newer edit remains dirty after an older save.
4. Complete real confirmed-bank undo/redo on the single Swift history. Exercise
   normal edit/save/undo sequences with the actual native bank service, not
   callback-echo mocks or an unimplemented future-bank entry.
5. Implement `projectSession` and `bankHistory` scenarios/assertions in
   `SessionChecks.swift` using real staged project/save/bank fixtures. Retain C++
   assertions only for genuine native service contracts. Supply an immutable
   playback publication callback for task 7; do not bind the old AudioEngine
   timeline API here. Async Swift checks finish before runner completion.

## Acceptance predicate

A real project song loads into Swift, edits/save/reopen preserve every stream
and flags, failed saves stay dirty, session-only changes do not dirty it, and
confirmed bank/document edits share the existing ordering semantics. Controller:

```sh
deno task verify --filter swiftcore --verbose --qt projectSession bankHistory
deno task verify --filter savecheck --filter vgbankcheck --filter vgsavecheck --verbose
```

The new slots exercise the real service. The reference suites guard current
bank/save behavior but do not prove the Swift path themselves. Native bank
loading and normal file errors are covered; no bank-editor GUI is introduced.
Before task 7, the cumulative core gate also runs:

```sh
deno task verify --filter swiftcore --verbose
```

Review the complete inventory and reference comparisons at this gate. Playback
through the device is task 7's acceptance; the actual grid is task 8's. This
independently checked core is not yet the production app.
This cumulative gate also reconciles all rows due through task 6 under
[the coverage contract](spec.md#case-by-case-coverage-reconciliation).
Only explicitly assigned native-integration and grid rows may remain pending;
they do not authorize deletion of the reference core.

## Task-specific constraints

Do not retain `ProjectWorkspace` as a second application/session owner inside
Swift. Reuse lower-level project services, not its tab/catalog orchestration.
Do not widen `sgd_`, `sgc_` or `sgs_`. The existing native `blankSong` definition
is removed with its remaining old callers in task 7; the new service never uses it.
