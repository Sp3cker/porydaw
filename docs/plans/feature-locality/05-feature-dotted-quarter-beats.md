# Plan 05 — FEATURE: dotted-quarter displayed beats in compound meter

**Shelved by user:** not executed; the user cannot verify compound-meter beat grouping by ear or eye.

**This is a behavior change, not a refactor step.** Approval-gated: the user must accept the
visible change (in 6/8 the ruler, transport and polyphony readouts show 2 numbered beats per
bar instead of 6) before execution. Sequenced after 02 (the policy lives in `core/Meter.swift`).
Route: SDD-track; seat `sdd-implementer`.

## BLOCKING USER DECISIONS (recorded, not decided — answer before execution)

1. **6/4 family (C3)**: gate on numerator only (`numerator >= 6 && numerator % 3 == 0`, so 6/4,
   9/4, 12/4 get dotted-half displayed beats) or keep `denominatorPowerOfTwo >= 3` (denominator
   ≥ 8) excluding 6/4? No musical or fixture evidence justifies the denominator floor as written.
2. **Plot/static grid lines (I5)**: `RollPlotBuilder.swift:243` and `DrawerStaticsContent.swift:70`
   consume `forEachGridLine` ignoring bar/beat — coarser displayed stepping silently recoarsens
   roll plot and drawer grid lines (visible beyond ruler/readouts). Coarsen them with the ruler,
   or exempt them (denominator-based stepping via the pinned walk) with a reason?
3. **C++-parity fixtures (I5)**: `TimeAxis.swift:6-7` pins loop arithmetic to the `timeaxis.cpp`
   oracle ("any cleaner restatement is a defect"). Which fixtures compare against that oracle,
   and which of them now expect grouped displayed values? The fork must be named in the check
   updates, not silently absorbed.

## Context

Q1 (reviewer's 6/8 ruler question) found the split policy: beat *duration* is denominator-unit
math (`signatureBeatTicks`, core), beat *count* is numerator (`TimeAxis` segments). In 6/8 that
yields six eighth-note beats per bar — technically consistent, musically wrong for display:
convention groups compound meters in dotted beats. Today the concept has no owner for that
grouping decision; 02 creates the home.

## Scope decisions (made here; challenge via approval, not in-task)

1. **Displayed enumeration changes; audio does not.** `signatureBeatTicks` (denominator-unit
   duration), `PlaybackTimeline` projection, `Sequencer` scheduling, any metronome/click timing
   keep today's semantics. Only bar/beat *enumeration for display* groups in threes.
2. **Grouping rule (subject to blocking decision 1)**: compound when `numerator >= 6` AND
   `numerator % 3 == 0` (with the denominator ≥ 8 floor only if the user keeps it): displayed
   beat = 3 signature beats, displayed beats/bar = numerator/3 (6/8→2, 9/8→3, 12/8→4, 6/16→2).
   All other meters: identity (today's behavior).
3. **GridSegment stays denominator-based; displayed stepping is a separate accessor.**
   `forEachGridLine` computes displayed beat stepping/numbering internally from
   `Meter.displayedBeats`; `GridSegment.beatTicks/beatsPerBar` keep pinned-port
   denominator-unit values so grid geometry is untouched: `GridGeometry` `adaptiveTicks` ladder
   (:179-182), `gridTicksAt` (:203-206), `beatLineWeight` (:273-277) and `forEachSubdivision`
   (:392) keep today's behavior — snap stays eighth-note in 6/8, subdivision ladders and
   beat-hide thresholds unchanged. Only the ruler/readout path consumes the displayed accessor
   (plus plot/static grid lines iff blocking decision 2 says coarsen).
4. **Readouts follow the ruler**: `MusicalPosition` (TransportBarPresenter.measure :266-269,
   PolyphonyPanelPresenter.formatPosition :347-350) uses the same grouping so "bar:beat" matches
   the ruler. This changes `MusicalPosition` output in compound meters — its only callers are
   these two formatters (verified by grep).

## Exact write set

- `src/swift/core/Meter.swift` (post-02): add
  `static func displayedBeats(numerator: UInt8, denominatorPowerOfTwo: UInt8, ticksPerBeat: UInt32) -> (beatsPerBar: UInt32, beatTicks: UInt32)` —
  pure; identity outside the compound rule.
- `src/swift/document/view/timeline/TimeAxis.swift`: `forEachGridLine` (:127-191) steps beats by
   the displayed policy and numbers them accordingly; add a displayed-beat accessor (e.g.
   `displayedBeatPolicy(at:)`) consumed only by the ruler/readout path. `GridSegment` and the
   ported segment walk keep denominator-unit semantics; bar lines and bar-numbering rollover
   stay at bar boundaries exactly as today (partial-bar rounding unchanged). Documented
   deviation from the `timeaxis.cpp` oracle *for displayed beats only* (blocking decision 3).
- `src/swift/core/PlaybackTimeline.swift`: `MusicalPosition.init` (:158-176) delegates beat
  grouping to `Meter.displayedBeats` (bar math unchanged otherwise).
- Checks (expectations change with the feature — allowed here, unlike refactors):
  `src/checks/rollcheck/EditorGridLatticeChecks.swift`, `rollcheck/ruler_loop_menu_loop.swift`,
  `rollcheck/time_signature_prompt.swift`, `rollcheck/static/geometry.swift`, and any
  transport/polyphony position assertions found by
  `grep path=src/checks pattern=MusicalPosition|measure\(at:`.

## Interface contract

- `TimeAxis.forEachGridLine` visitor signature unchanged `(Tick, isBar, bar, beat)`;
  in 6/8, `beat` now ranges 1...2 and ruler grid lines step by 3 signature-beats.
- `GridSegment.beatTicks/beatsPerBar` keep denominator-based values (scope decision 3);
  displayed stepping is exposed by the separate accessor only. Consumers of `GridSegment`
  (`beatLineWeight`, `adaptiveTicks`, `gridTicksAt`, `forEachSubdivision`) see no change.
  `RollPlotBuilder.swift:243` and `DrawerStaticsContent.swift:70` change only iff blocking
  decision 2 chooses coarsening.
- **QtBridge/QML surface: no member changes**; QML renders label strings and display lists as
  data (`EditorRulerBand.qml` untouched).
- `RollRulerBuilder.swift` expected to need no code change; verify label-collision spacing still
  holds with fewer, wider-spaced labels; assert in checks.

## Preservation contract

- Non-compound meters: bit-identical output (identity branch), so the existing corpus for
  4/4, 3/4, 2/4, 5/8 (numerator 5 not divisible by 3) and 3/8 (numerator < 6) is unaffected.
  Changed meters: 6/8, 9/8, 12/8, 6/16, 12/16; plus 6/4, 9/4, 12/4 if blocking decision 1
  picks the numerator-only gate.
- Playback/audio: zero change (scope decision 1). Per-frame builders stay allocation-free
  (`displayedBeats` is pure arithmetic called at projection build, not per record).
- History/document model: untouched — this is view projection only; no document format impact.

## Acceptance predicate (implementer-run)

- `deno task build:checks`.
- `deno task checks --filter swiftcore` (lattice/ruler/transport slots ride the lane; full
  filter required — suite isolation not verified).
- `deno task checks:qml-roll` and `deno task checks:shell` (ruler band QML expectations).
- `deno task format --check`.
- Manual controller verification (named gap — no check asserts musical convention): open a 6/8
  fixture song; ruler shows beats 1-2 per bar at dotted-quarter spacing; transport readout
  matches; 4/4 song byte-identical rendering (screenshot or proof ledger row per
  proof-ledger-workflow, edited only for the touched surface).

## Risks

- Check-corpus updates are part of the feature surface; do not weaken assertions to pass —
  update expected numbers to the grouped convention only for compound fixtures.
- `GridGeometry` snap modes are out of scope by construction (scope decision 3): denominator-based
  `GridSegment` values feed `adaptiveTicks`/`gridTicksAt`/`beatLineWeight`/`forEachSubdivision`
  unchanged; `rollcheck/static/geometry.swift` must stay green without expectation edits — if it
  does not, the accessor leaked into the pinned path and that is a defect, not a check update.
- Build gate: policy lands in existing cold files (`Meter.swift`, TimeAxis 10 commits) —
  build-neutral; no new targets.
