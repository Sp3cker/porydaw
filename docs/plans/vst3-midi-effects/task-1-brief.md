# Context

Hosted plugins emit off-grid, unpaired, overlapping note events. The engine needs lattice-exact, fixed-point notes: task 7 normalizes offline capture results with the batch form, and task 9 normalizes the live take on Grab. `Arpeggiator.swift` already owns the lattice math privately. Extract it into `EngineNoteLattice` without changing arpeggiator output, and add `EngineNoteNormalizer` with a batch `normalize`. There is no streaming form; live playback pushes raw events. Consumer: tasks 7 and 9. Read plan.md Global Constraints and spec.md "Core" first.

# Exact write set

- src/swift/core/Arpeggiator.swift (edit)
- src/swift/core/EngineNoteLattice.swift (new)
- src/swift/core/EngineNoteNormalizer.swift (new)
- src/checks/editcheck/EngineNoteNormalizerChecks.swift (new; `@MainActor public func runEngineNoteNormalizerChecks(_ report: CheckReport)`)

Registration (controller): the two Core files go into the PorydawCore source list. The check file goes into `swift_core_check_logic`, called from the `PDC_SUITE_NOTE_EDITS` case of `CoreCheckDispatch.swift` after `runArpeggiatorChecks`.

# Prerequisites

None.

# Interface contract

Exactly spec.md "EngineNoteLattice and EngineNoteNormalizer", with these details:

- `normalize(_:track:range:lattice:) throws -> (notes, report)` applies rules 1–9 in order. Counting is exact: each event increments at most one `dropped*` counter. `snappedOnsets`, `adjustedDurations`, `velocityClamped`, `overlapsTrimmed` and `duplicatesSuppressed` count adjustments to surviving notes. `report.notes` equals the output count.
- Batch `normalize` is the only normalizer; the live path uses none.
- `Arpeggiator`'s public API, errors and `ArpeggiatorResult` fields (`quantumTicks`, `quantumClocks`, `gateClocks`, …) are unchanged. Its 65,536 limit reads `EngineNoteNormalizer.noteLimit`.

# Implementation steps

1. In `Arpeggiator.swift`, identify the private timing type's lattice pieces: the gcd quantum, the low-clock `mid2agbEffectiveDuration` fixed-point table, and the nearest-representable duration search with its tie-break. Move them into `EngineNoteLattice`. The timing type stores a lattice and delegates, mapping nil to its existing error. Rate, shuffle, insert, gate, tie and output rules stay arpeggiator-private.
2. `snap` rounds to the nearest lattice point; an exact half goes to the later point. `isOnLattice` is `tick % quantumTicks == 0`. `durationTicks` returns nil when `maximum` is below one quantum.
3. Implement `normalize` with the spec's nine ordered rules (stable sort with offs before ons at equal ticks; pairing by positive `noteID` else FIFO per pitch; snap ties-later; range drop; pitch 0…127 and velocity clamp to 1…127; fixed-point durations; same-onset later-wins; same-pitch overlap trim; `tooManyNotes` above the limit).
4. Checks through the public interface:
   - lattice quantum at PPB 480/normal, 96/extended and 24/extended (coarser than the clocks);
   - snap ties-later; noteID pairing versus FIFO fallback with reused or nil ids; velocity-0 on as off; orphan off; unterminated closing at range end; pre/post-range onset drops;
   - duration fixed points with `exactGate` false and true; too-short drop; same-pitch overlap trim; same-onset later-wins; pitch and velocity bounds; `tooManyNotes`; output order.

# Acceptance predicate

Existing `ArpeggiatorChecks` pass unmodified, proving byte-identical arpeggiator output, and every new normalizer and lattice check passes. NAMED CHECKS (controller):

- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks --filter swiftcore-noteedits`

These cover arpeggiator parity and the new normalizer and lattice behavior.

# Task-specific constraints

Do not edit `ArpeggiatorChecks.swift`, `MidiSemantics.swift` or any `mid2agbEffectiveDuration` caller. No document mutation or app code. The normalizer is pure and allocation-proportional: no per-event string work.
