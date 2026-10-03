# Task 116 brief — MIDI save roundtrips preserve converter output and complete engine mapping

# Context

Complete the existing MIDI load/save consumer contract: converter-equivalent original and rewritten files, every mapped note event, and bounded unterminated-note pairing. This is not Import MIDI UI or WAV export. No wave consumer needs a new interface.

Verified planning selection: **44 open rows (20 GAP + 24 PARTIAL)**. This is the in-flight §13 census, not a completion claim.

- `src/checks/midi/proof.tst_midiroundtrip.txt` — A001, A002, A003, A004, A005, A006, A007, A008, A009, A011, A012, A013, A014, A015, A016, A017, A018, A019, A020, A021, A022.
- `src/checks/midi/proof.tst_midismf.txt` — A196, A197, A198, A225, A226, A227, A259, A260, A261, A265, A272, A273, A294, A295, A299, A300, A301, A352, A355, A357, A359, A361, A363.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `f7a01dba0d8595d9fc4070f1767d69d8d9ed76a8`, `97dc7fea819cb7c4a97a0dac819244ee570e993f`. Read selected expressions with `deno task proof sites` / `show`; deleted C++ check paths are references, never write targets.

# Exact write set

- `src/swift/core/MidiFile.swift`
- `src/swift/core/MidiFile+Codec.swift`
- `src/swift/core/NoteProjection.swift`
- `src/checks/midi/MidiSmfCodecChecks.swift`
- `src/checks/midi/MidiSmfCodecCompare.swift`
- `src/checks/midi/MidiSemanticsChecks.swift`
- `src/checks/midi/MidiSemanticsExpected.swift`
- `src/checks/editcheck/NoteChecks.swift`
- `src/checks/editcheck/EventChecks.swift`
- `src/checks/midi/proof.tst_midiroundtrip.txt`
- `src/checks/midi/proof.tst_midismf.txt`

Closed list: production writes are limited to the interface below. The implementer owns code/check files; the separate ledger writer alone owns the listed proof files after evidence settles, in the same surface change.

# Prerequisites

The 99–114 baseline and reserved in-flight lanes settle before execution. This task is independent of other Group A interfaces; preserve all canonical byte vectors, XCMD semantics and track mapping already covered.

# Interface contract

- Keep MidiFile decode/encode and NoteProjection as the only codec/pairing owners. Preserve opaque events, high data bytes, running-status resets and same-tick order. The fork fceecd88 tst_midismf.cpp::unterminatedNotePairingStaysLinear uses 300000 same-key note-ons and a 10000 ms pairing ceiling; retain that exact workload and timer scope, not an end-to-end build timer or reduced sample.
- Roundtrip A017/A018/A019 compiles both the original staged MIDI and the Swift-written MIDI with the same real staged mid2agb and song flags, normalizes only the existing source/output naming differences, and compares the entire assembly. Compiling only the rewritten bytes cannot close original-versus-saved equality. Keep XCMD fixture compilation and command semantics in the same real path (A022).
- SMF A294/A295 observes every note-on and note-off engine assignment in the 20-chunk fixture: pressure-only chunk owns slot 0; Alpha/Beta own slots 1/2; T5–T17 occupy slots 3–15; DroppedTail contributes no mapped note event. A301 requires exactly 16 analysis tracks. The existing ordinary-controller table must retain exact identities, counts and support values; A352/A355/A357/A359/A361/A363 are the old pointer-presence form around that consumer, not six new setup tests.
- Classify only the deleted QTemporaryDir/QFile/QTest staging, engine lookup guards and pointer-presence forms as representation where the throwing Swift fixture and following behavioral predicate already cover failure. For roundtrip these are A001–A009/A011–A016/A020/A021; for SMF A196–A198/A225–A227/A259–A261/A272/A273/A299/A300/A352/A355/A357/A359/A361/A363. Do not add setup-success assertions, and do not retire converter equality, exact mapped events, controller verdicts or the performance ceiling.
- Expected assembly is produced independently from the original fixture by the external converter; expected event identities and counts come from the fork table, not the Swift codec output. A production defect must be repaired at the codec/pairing owner, never by broadening normalization or skipping a song.

# Implementation steps

1. Extend existing roundtrip comparison to run both converter inputs and retain meaningful failures with complete existing diagnostics.
2. Complete note-off mapping, exact analysis size and the original pairing ceiling in the registered MIDI/semantic suites.
3. Repair only a demonstrated codec/projection divergence; preserve every current consumer signature and fixture byte vector.
4. Have the separate ledger writer close the two inventories after actual converter and pairing execution; do not touch midiexport.

# Acceptance predicate

The MIDI lane executes actual mid2agb original/rewritten comparisons; musicalsemantics proves complete engine mapping; noteedits executes the 300000-note/10000 ms pairing clause; midiimport preserves the complete controller histogram. Both selected ledgers close only after the genuine compile, mapping and performance obligations execute.

The implementer runs these exact covering lanes under §13’s build-lock policy; the controller runs the settled-group full gates:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-midicodec --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-musicalsemantics --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-noteedits --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-midiimport --verbose
```

# Task-specific constraints

No exporter, project-service, fixture, registration or application/QML writes. A converter subprocess is required runtime smoke, not a mock of expected assembly.

Read sprint-3 §13 “Evidence and execution contract” as part of this brief: real input; independent expectations; no setup-only assertions; exact raster colors/positions and executed DPR2 where claimed; no shell dispatcher in editorqml; verbatim existing and unique complete new messages; all exact-content fixture consumers updated; copied-fixture isolation for shared bank leases; implementer-owned locked lanes; separate ledger writer.
