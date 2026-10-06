# Plan 02 — Meter ownership (lever: cause a + buried c; fixes Q1, helps Q4)

Route: **SDD-track** (core public-symbol surgery near a pinned port; judgment on move bounds).
Seat: `sdd-implementer`. Prerequisite: 01 task 2 (timeline map) lands first and its meter pointer
must cite `Meter.swift` — the win is addressability, which only pays once the map points here.

## Verdict

Meter math is already single-sourced (`signatureBeatTicks`, core) but has no address of its own:
it sits at `PlaybackTimeline.swift:133-177` inside a 674-line playback/tempo/loop/markers file.
Q1 opened PlaybackTimeline (674 lines) for **5 needed lines**; Q4 opened it for the beat-math
slice among tempo slices. The win is **filename addressability, not file count**: Q1 still opens
TimeAxis + RollRulerBuilder + GridGeometry, but the beat-math slice shrinks from a 674-line file
to a ~60-line one, and callers are untouched because everything stays in `PorydawCore`.

## Task 1 — Relocate meter semantics to `core/Meter.swift`

**Context.** One concept (musical meter: signature value, beat-tick math, bar/beat position)
currently reads as "playback projection detail". After the move, `Meter.swift` is the first file
an agent opens for any beat/bar question; `PlaybackTimeline.swift` keeps only playback projection.

**Exact write set**
- Create `src/swift/core/Meter.swift`.
- Edit `src/swift/core/PlaybackTimeline.swift` (delete moved declarations only).
- Edit `src/swift/core/CMakeLists.txt` (add `Meter.swift` to the PorydawCore source list).

**Interface contract — pure move, symbol-identical**
- Move verbatim (names, signatures, doc comments, `public` levels):
  - `PlaybackTimeSignature` (PlaybackTimeline.swift:133-143),
  - `signatureBeatTicks(ticksPerBeat:denominatorPowerOfTwo:)` (:145-149),
  - `MusicalPosition` (:153-177, its init and helpers).
- `Meter.swift` header comment (≤2 lines): meter value, beat-tick math, bar/beat position.
- No new symbols, no renames, no signature changes. Same module → zero caller edits
  (verified callers: TimeAxis.swift:119,144,182,186; PlaybackTimeline.swift:167-170 internal).
- Do NOT touch: `TimeAxis.swift` (pinned port of `src/ui/songview/timeaxis.h/.cpp`; its
  `TimeSigPoint` stays the SMF wire mirror at its input boundary), `DocumentProjectionCache`,
  `ApplicationSession+Ruler`, any QML.

**Implementation steps**
1. Create `Meter.swift`; paste the three declarations; keep `import` set identical to what the
   declarations need (Foundation-free, PorydawCore-internal).
2. Delete lines 133-177 from `PlaybackTimeline.swift`; confirm no internal references broke
   (`MusicalPosition` used by Sequencer-side helpers — same module, resolves identically).
3. Add `Meter.swift` to `src/swift/core/CMakeLists.txt` PorydawCore `add_library` source list.
4. `deno task lsp:swift` (index rebuild after CMake reconfigure — AGENTS.md search discipline).

**Acceptance predicate (implementer-run)**
- `deno task build:checks` (compiles core + all dependents; catches list omission).
- `deno task checks --filter swiftcore` — covers the 18 swiftcore suites incl.
  `swiftcore-playback` (timeline/MusicalPosition consumers) and the rollcheck lattice slots
  (TimeAxis walks `signatureBeatTicks`; `rollcheck/EditorGridLatticeChecks.swift`,
  `rollcheck/static/geometry.swift`). Coverage note: no suite isolates `signatureBeatTicks`
  directly; lattice+playback lanes are the covering surface — full `--filter swiftcore` required,
  not a narrower filter.
- `deno task format --check`.
- Controller spot-check: `grep path=src/swift pattern=signatureBeatTicks` shows definition only
  in `Meter.swift`.

**Task-specific constraints**
- Behavior preservation: bit-exact. The shift clamp `min(pow,31)` and `max(1,…)` semantics are
  load-bearing (C++ parity comment :145) — move the comment with the code.
- Build gate: one new small compile unit in a cold file set (PlaybackTimeline: 6 commits in
  repo history; TimeAxis: 10). No new module/target/edge → build-neutral. If execution wants
  numbers: time `deno task build:app` before/after; expected within noise.
- Comments ≤2 lines (moved multi-line doc comments travel verbatim; new prose follows the rule).

**Read-set effect (estimate, [INFERENCE])**: Q1 stays ~11-12 files, opened 3,390(wc)→~2,720
(PlaybackTimeline leaves the set; `Meter.swift` ~60 lines joins); the range-read is the win.
With 01's map pointing here: beat/bar questions start at 2 small files (Meter + TimeAxis ranges).
Q4 keeps PlaybackTimeline (tempo slices are genuinely there) but beat questions start at `Meter.swift`.

## Non-goals

- No merge of `TimeSigPoint` (document wire mirror) into a core type — that would restate the
  pinned port's input boundary; the parallel is documented in 01's timeline map instead.
- No move of prompt state off `ApplicationSession` (cause d; rejected in OVERVIEW §1).
- The 6/8 dotted-quarter display change is a separate FEATURE (05), not part of this refactor.
