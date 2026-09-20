# Task 1 — Lossless MIDI and musical primitives

## Context

Establish the Qt-free `PorydawCore` representation consumed by document editing
(task 2), XCMD/import (task 3), and playback (task 5). This is a complete codec
and musical-primitives change, not an empty module scaffold. Governing scope:
[plan.md](plan.md#global-constraints), [spec.md](spec.md#canonical-state-and-storage).
Execution amendment: this task is already active. Before acceptance, backfill
the [case-by-case coverage ledger](spec.md#case-by-case-coverage-reconciliation)
for work already done; continue the implementation rather than restart it.

## Exact write set

Create:
- `src/swift/core/MusicTypes.swift`
- `src/swift/core/MidiFile.swift`
- `src/swift/core/MidiSemantics.swift`
- `src/swift/core/CMakeLists.txt`
- `src/checks/swiftcore/core_check.h`
- `src/checks/swiftcore/MidiChecks.swift`
- `src/checks/swiftcore/tst_swiftcore.h`
- `src/checks/swiftcore/tst_swiftcore.cpp`
- `docs/plans/swift-core-rewrite/coverage-ledger.json`
- `src/checks/swiftcore/CoreCheckSupport.swift`
- `src/checks/swiftcore/oracle_check.h`
- `src/checks/swiftcore/oracle_check.cpp`
- `src/checks/swiftcore/module.modulemap`

Modify only build/registration integration in `CMakeLists.txt`,
`src/checks/CMakeLists.txt`, `src/checks/checkcatalog.cpp`, `src/checks/fwd.hpp`.
Read-only oracle: `src/core/{smf,timedefaults,tempo,tracklimits,noteid,m4asemantics,mid2agbtables,velocitymodel}*`,
`src/checks/midi/tst_midismf.{h,cpp}`, `src/checks/keyboard/tst_velocitymodel.cpp`.
For the baseline inventory only, also read `src/checks/checkcatalog.cpp` and
the registered check sources covering core, including mixed UI/service cases.

## Prerequisites

None. Reuse the verified toolchain and existing Swift check-target build pattern;
QtBridge is not a dependency of `PorydawCore`.

## Interface contract

Implement the storage/types/semantics contracts in spec.md. `VelocityMap` accepts
a resolved `VoiceKind`; native instrument traversal stays outside core and is
verified with the real service in task 6. Preserve all level/range/representative
and duration quantization results. `NoteID` is UInt64 and remains unserialized.

Keep harness `swiftcore` and selectors `midiCodec` and `musicalSemantics`.
Under [test-language ownership](spec.md#test-language-ownership), `MidiChecks.swift`
owns complete scenarios, direct production calls and assertions. Reduce
`tst_swiftcore.{h,cpp}` to suite invocation and failure reporting; it must not own
the corpus expectation tables, musical loops or comparison decisions.

`CoreCheckSupport.swift` owns bounded suite completion and case/row diagnostics;
`core_check.h` declares only the suite execution/reporting boundary. A failed
Swift assertion must fail the harness with its baseline ID and expected/actual
results. Successful execution identifies the executed rows for reconciliation.
Unknown selectors or no executed selected cases must fail, not return green.

`oracle_check.{h,cpp}` exposes only temporary calls to the old C++ implementation;
`module.modulemap` imports that check-only interface into Swift. Swift compares
its production results with the oracle and with retained expected values.
For every required codec/semantic outcome, keep an oracle-independent expected
result in Swift in addition to the live comparison: explicit canonical byte
vectors and decoded event/order expectations for codec cases; specified
classification/default/quantization/velocity values and boundary invariants for
musical cases. Existing checked-in fixtures and compact expected-value tables
are preferred. Do not derive expected results by calling another production
Swift path or copying the C++ algorithm into a test helper. Preserve every
meaningful case/row; this is not permission to replace exhaustive reference
coverage with a few examples. Annotate the ledger's assertion mapping to
distinguish independent expectations from supplemental differential assertions.
Remove obsolete `pdc_codec_roundtrip`, `pdc_blank_song`, `pdc_semantic_value`
and `pdc_semantic_text` test exports and their C++ callers when these checks
migrate. Do not replace them with another per-operation Swift ABI.

## Implementation steps

1. Define the small native value vocabulary and codec before editing algorithms.
   Preserve opaque events, chunk order/EOT, original status and format-0 routing.
2. Implement strict decode and canonical encode; include the existing blank-song
   factory behavior. No file-I/O wrapper or best-effort parser is needed here.
3. Implement existing musical classifications/defaults, velocity levels and
   mid2agb quantization. Do not add new classifications or copied instrument trees.
4. Build `PorydawCore` independently of Qt and check/oracle modules; compile the
   Swift test bodies as direct Core consumers through explicit CMake registration.
   Preserve runner/selectors where compatible with the governing Core-independence
   rule. Migrate domain drivers to `MidiChecks.swift`, not Core APIs toward C++.
5. Connect the separate native oracle to Swift-owned comparisons. Qualify suite
   selection, diagnostics and failure propagation through the real Deno path;
   no second fixture runner or production domain exports.
6. Freeze the reference revision and build the complete baseline case/row
   inventory under the linked reconciliation contract. Assign later cases to
   their owning task; map and execute every task-1 scenario through production
   Swift, preserving all observable assertions and case-specific failure IDs.

## Acceptance predicate

The Swift codec produces the existing canonical bytes and musical values over
normal project songs and existing foreign-file/error examples. Unknown payloads
survive round trips and invalid files fail completely. Controller commands:

```sh
deno task verify --filter swiftcore --verbose --qt midiCodec musicalSemantics
deno task verify --filter smfcheck --filter velocity-model --verbose
```

`swiftcore` is introduced by this task. The second command guards the unchanged
codec/velocity references. Existing import/XCMD cases run only on the reference
here; their Swift completion belongs to task 3. Offscreen checks
use runner-staged fixtures; no desktop or external decomp copy is required.

Acceptance also requires independent inventory-completeness review and zero
unresolved task-1 rows in coverage-ledger.json. Codec and pure musical/velocity
semantics are due here; importer/XCMD and native voice-kind resolution retain
their explicit later owners. The broad Swift slot names are not a coverage map.
The first command must execute independent expectations as well as parity
comparisons. Acceptance rejects an outcome whose only expectation comes from
`oracle_codec_roundtrip`, `oracle_semantic_value`, `oracle_semantic_text`, or
`oracle_blank_song`. Task 7 removes those calls and reruns the same retained
expectations without a fallback, test mode, or skipped rows.

Qualify the reporting envelope with a disposable deliberately failing assertion
in a selected Swift case: the first command must exit nonzero and identify that
case/row and its expected/actual values. Remove the injected failure and require
a passing run. Unknown-selector rejection is exercised with:

```sh
deno task verify --filter swiftcore --verbose --qt unknownSwiftCoreSuite
```

That command must exit nonzero; its failure is expected probe evidence, not an
unresolved application failure. Record both probes without retaining a permanent
tautological runner test. The C++ shell must contain no task-1 musical assertions
after migration.
The host/reporting smoke must exercise the actual Swift Core calls and ownership
used by these cases. No production access widening, C-shaped result projection,
forced conformance or weakened Swift ownership is acceptable to pass it. If the
envelope cannot host the real design, report the specific test-integration change
needed outside the write set; Core is not the fallback repair location.

## Task-specific constraints

Do not delete the reference core yet. Do not add C ABI exports to the domain
module for future UI use. Keep musical names/constants together rather than
creating a file per alias or lookup table.
