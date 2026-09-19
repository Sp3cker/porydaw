# Task 1 — Lossless MIDI and musical primitives

## Context

Establish the Qt-free `PorydawCore` representation consumed by document editing
(task 2), XCMD/import (task 3), and playback (task 5). This is a complete codec
and musical-primitives change, not an empty module scaffold. Governing scope:
[plan.md](plan.md#global-constraints), [spec.md](spec.md#canonical-state-and-storage).

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

Modify only build/registration integration in `CMakeLists.txt`,
`src/checks/CMakeLists.txt`, `src/checks/checkcatalog.cpp`, `src/checks/fwd.hpp`.
Read-only oracle: `src/core/{smf,timedefaults,tempo,tracklimits,noteid,m4asemantics,mid2agbtables,velocitymodel}*`,
`src/checks/midi/tst_midismf.{h,cpp}`, `src/checks/keyboard/tst_velocitymodel.cpp`.

## Prerequisites

None. Reuse the verified toolchain and existing Swift check-target build pattern;
QtBridge is not a dependency of `PorydawCore`.

## Interface contract

Implement the storage/types/semantics contracts in spec.md. `VelocityMap` accepts
a resolved `VoiceKind`; native instrument traversal stays outside core and is
verified with the real service in task 6. Preserve all level/range/representative
and duration quantization results. `NoteID` is UInt64 and remains unserialized.

Register prospective harness `swiftcore` with independently selectable QTest
slots `midiCodec` and `musicalSemantics`. Its C++ driver compares production Swift
results with existing C++ codec/semantic results using the checked-in corpus and
existing synthetic file cases. Failure output identifies case and both results.
The adapter is check-only; it supplies no application document API.

## Implementation steps

1. Define the small native value vocabulary and codec before editing algorithms.
   Preserve opaque events, chunk order/EOT, original status and format-0 routing.
2. Implement strict decode and canonical encode; include the existing blank-song
   factory behavior. No file-I/O wrapper or best-effort parser is needed here.
3. Implement existing musical classifications/defaults, velocity levels and
   mid2agb quantization. Do not add new classifications or copied instrument trees.
4. Build `PorydawCore` independently of Qt, using explicit source registration.
   Register the check target using the repo's existing Swift/QTest pattern.
5. Connect callable comparisons to current checks/fixtures; retain existing
   expected behavior rather than adding a second general test framework.

## Acceptance predicate

The Swift codec produces the existing canonical bytes and musical values over
normal project songs and existing foreign-file/error examples. Unknown payloads
survive round trips and invalid files fail completely. Controller commands:

```sh
deno task verify --filter swiftcore --verbose --qt midiCodec musicalSemantics
deno task verify --filter smfcheck --verbose
```

`swiftcore` is new in this task, not a currently available command. The second
command guards the unchanged reference. Existing import/XCMD cases run only on
the reference here; their Swift completion belongs to task 3. Offscreen checks
use runner-staged fixtures; no desktop or external decomp copy is required.

## Task-specific constraints

Do not delete the reference core yet. Do not add C ABI exports to the domain
module for future UI use. Keep musical names/constants together rather than
creating a file per alias or lookup table.
