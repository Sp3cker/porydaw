# Task 13 — Logic: NoteIdentity file + assertions + certificate + deletion

## Context

`tst_songdocument_logic.cpp` = 24 verbatim `ScaleCheckTest` duplicates
(A001-A024) + 36 `NoteIdentityCheckTest` sites (A025-A060) (spec §5.8).
The scale duplicates are terminal as RETIRED-REPRESENTATION regardless of
any scale decision: the duplicate sites live in an uncompiled file while
the live native coverage remains in the registered `scalecheck` lane
(`proof.tst_scale.txt` keeps its GAP accounting). The noteid work lands
in ONE new `NoteIdentityChecks.swift` (~150-200 lines — the C++ test
class counterpart, cohesive), wired from `runNoteEditsSuite` (1 line);
existing `adoptionAndPairing` in `NoteChecks.swift` stays untouched (its
MATCHED citations remain valid). Disk-staging and non-throwing-
construction sites are RETIRED-REPRESENTATION per the §2.1 hard rules.

## Exact write set

- New: `src/checks/editcheck/NoteIdentityChecks.swift`
- `src/checks/editcheck/NoteChecks.swift` (1 suite-call line in `runNoteEditsSuite`)
- `src/checks/CMakeLists.txt` (1 source line)
- `src/checks/editcheck/proof.tst_songdocument_logic.txt` (rewrite)
- Delete: `src/checks/editcheck/tst_songdocument_logic.cpp`

## Prerequisites

C3 (`NoteChecks.swift` reuse authorized; CMake chain free).

## Interface contract

Entry `noteIdentityContracts(_ report:)` (cppIDs
`noteidcheck/NoteIdentityCheckTest::<method>`), with local fixture
literals:

- `parsedMidiLeavesIdsUnassigned` (A029-A033, A036): decode the
  note-lifecycle fixture; assert chunk count (as constructed), event
  count 3; first two `isNoteOn`, third is note-end; ALL THREE events
  have `noteID == nil`/`!(noteID?.isAssigned ?? false)` — the note-end
  event included (A036).
- A037-A040: `PlaybackTimeline.build(state: SongState(file: decoded, …),
  sampleRate: 48_000)` — assert what production actually guarantees for
  unstamped note-ons (read `PlaybackTimeline.swift` first) and assert
  exactly that.
- `adoptedSmfRemintsForeignIds` (A042-A050): capture assigned,
  pairwise-distinct IDs from the first document; construct a second
  `SongDocument(file: first.state.file, …)`, add one note, and assert
  three assigned, pairwise-distinct IDs in that second document.
  Do not require numeric IDs across two document instances to differ:
  construction restarts `mintAllNoteIDs` at 1 and no public API re-adopts
  MIDI into the SAME document. A046 (fallible same-instance re-adoption)
  and A049 (fresh IDs relative to that instance's previous generation)
  are RETIRED-REPRESENTATION with the §7 no-ingress explanation; A047,
  A048 and A050 assert the surviving three-note cardinality, assignedness
  and intra-document uniqueness.
- `identityDoesNotAffectEqualityOrSerialization` (A051-A055): two events
  stamped `NoteID(1)`/`NoteID(2)`; both assigned and unequal; events
  equal under `==` (production `MidiEvent.==` ignores `noteID`);
  `file.encoded()` equals the unstamped baseline bytes.
- `timelineTransportsOnlyStampedNoteIds` (A056-A060): two stamped
  note-ons (NoteID(1)/(2)) @ 24 + note-off @ 48; build timeline; assert
  both stamped IDs transported to the timeline note-ons and the
  note-off's ID unassigned.

Proof dispositions:
- A001-A024 RETIRED-REPRESENTATION (mapping: verbatim duplicate of
  `tst_scale.cpp` sites inside an uncompiled file; live native coverage
  remains in the registered scalecheck lane per `proof.tst_scale.txt`;
  no Swift parity exists or is planned for this duplicate).
- A025-A027 (temp-file write plumbing), A037/A056 (nullable C++
  `MidiTimeline` construction), A041 (non-throwing
  `adoptSmf`→`SongDocument(file:)` construction — no failure branch),
  and A046/A049 (same-document re-adoption and numeric ID freshness
  across that re-adoption — no Swift ingress): RETIRED-REPRESENTATION
  with the §2.1/§7 proof.
- A028 (`readFile` succeeds): MATCHED via the throwing
  `try MidiFile.decode(<same bytes>)` whose failure branch the do/catch
  actually reports.
- Existing MATCHED remain only where the original observable and
  `cppID` are preserved; new closures require direct executing predicates.

## Implementation steps

1. Read the NoteIdentityCheckTest methods, `adoptionAndPairing`,
   `MidiFile.swift` (==/encoded), and `PlaybackTimeline.swift` (noteID
   transport) before writing.
2. Write `NoteIdentityChecks.swift`; wire the call; append the CMake line.
3. Proof terminalization + certificate (spec §3 with §2.2 revision
   pinning); `Covered native implementation: src/core/noteid.h,
   src/core/miditimeline.cpp :: note ID assignment, adoption reminting,
   timeline transport`; `Registered run path: … NoteChecks.swift ::
   runNoteEditsSuite -> NoteIdentityChecks.swift ::
   noteIdentityContracts, swiftcore suite 4`. Counterparts + SHAs:
   NoteChecks.swift, NoteIdentityChecks.swift.
4. Delete the file.

## Acceptance predicate

- `deno task proof show tst_songdocument_logic` parses; PARTIAL 0, GAP 0
  (MATCHED + RETIRED-REPRESENTATION only).
- Controller: `deno task verify --filter=swiftcore --qt noteEdits` then
  full swiftcore PASS recorded; `deno task lsp:swift`.
- Harness `grep` for `NoteIdentityChecks.swift` in
  `src/checks/CMakeLists.txt`: exactly one source entry.

## Task-specific constraints

- Assert only what production guarantees; where C++ semantics differ,
  assert the Swift contract and note the difference in the mapping line —
  never fabricate parity.
- No dependency on any scale decision: the scale-duplicate mapping cites
  the lane as it stands.
