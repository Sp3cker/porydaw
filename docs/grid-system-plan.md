# Grid rework: musical spacing through the clock minimum

Status: reviewed implementation plan; no production changes implemented.

## 1. Requirements and architectural assessment

The user requests:

- Cmd+1 narrows the grid; Cmd+2 widens it.
- Cmd+3 toggles straight/triplet.
- Narrowing reaches the real smallest supported grid step, including divisions below 1/32.
- The selected grid controls minimum newly drawn note length and lengthening/shortening snap granularity; future keyboard extension consumes that same step.
- No Auto editing mode. Grid lines still appear/hide with zoom using the existing visual-detail behavior; zoom never changes the selected editing resolution.

**Working assumption: the user edits at 24 PPQN.** This is the design, UI-example and end-to-end acceptance baseline; its minimum is one tick. Other divisions below document existing compatibility facts, not equally important user workflows or a request to build a general timing-system redesign. Keep existing document resolution intact, but do not let exotic-division policy dominate this feature.

Other decisions below are recommendations, not additional user requirements.

**Assessment: keep the shared grid seam; replace the inadequate policy behind it.**

`SongView` already owns one `songview::Grid`, and note, ruler, range and automation editing already consult it. That is a useful module, not an obstacle to grid shortcuts. Its current interface conflates a user-selected fineness floor, camera-dependent spacing, hidden finer snapping and display detail. Merely adding keys to the existing four menu values would preserve the wrong model.

The previous plan overfit the existing menu by stopping at 1/32, then unnecessarily retained an Auto editing mode. Both are removed. Selection distinguishes a musical division from the clock minimum; visual detail remains automatically zoom-dependent without being an editing mode. Do not encode these as sentinel values in `minDenom` or create separate editing grids for individual surfaces.

Keep these responsibilities distinct inside the module:

1. **Selection:** Musical(denominator) or Clock, with straight/triplet feel.
2. **Timing resolution:** which exact musical cells fit this document, and its minimum editable clock step.
3. **Editing spacing:** the selected step used for snapping, the minimum newly drawn duration, and length-editing granularity.
4. **Display detail:** zoom-dependent visibility of bar, beat and subdivision guides, retaining the current visual behavior without controlling editing resolution.

Changing zoom may reveal or hide reference lines. It must not change selected spacing, new-note minimum duration, or lengthening/shortening increments. There is no Auto state, menu entry, default, or hidden compatibility mode.

## 2. Evidence and precision

### Repository facts

- `src/ui/songview/grid.h:22-95`: `Grid` reads `TimeAxis` and `TimeCamera`, owns feel, `m_minDenom`, clock floor and detail thresholds, and provides cell/snap accessors. No per-surface grid state is needed.
- `grid.cpp:21-29`: `normalizeMinDenom` accepts only 4, 8, 16 and 32; anything else becomes Auto. This is a menu/model restriction, not the timing-resolution limit.
- `grid.cpp:83-121`: current grid spacing walks a zoom-dependent ladder. Snap deliberately runs one ladder step finer than visible spacing. Selected denominators cap fineness rather than pinning spacing.
- `grid.cpp:123-126`: `fineGridTicks()` uses the document clock floor when bound. It is not universally one SMF tick.
- `grid.cpp:127-162`: ordinary snapping restarts at time-signature changes and clamps to `seg.next`; fine snapping is on the absolute clock grid. `seg.next` is not the next bar line.
- `grid.cpp:167-189`: `SongView` host setters mutate grid state, synchronize ruler controls and refresh views/drawers.
- `timeruler.cpp:98-183`: division/feel menus are the existing controls; `quick/RulerControls.qml` presents them.
- `src/core/songdocument.cpp:443-447` defines the existing floor:

  ```text
  ticksPerClock = max(1, floor(SMF division / (extendedClocks ? 48 : 24)))
  ```

- `src/ui/newsongwizard.cpp:609-610`: rescaling imports to 24/48 PPQN is optional. `rescaleDivision` at `src/core/midiimport.cpp:277-289` performs the selected rescale; its existence does not imply all documents are normalized.
- `TimeAxis::ticksPerBeat()` supplies document PPQN (`timeaxis.cpp:11`). Signature `beatTicks` is a different quantity and must not define an absolute musical fraction.
- `src/core/smf.h:88`: default division is 24. Document ticks are integers; minimum note duration is one SMF tick. Neither fact alone defines the editable clock-grid floor.
- SMF saving preserves unquantized ticks (`src/core/smf.cpp:266-328`). Compilation floor-scales ticks to driver clocks (`mid2agbtables.cpp:17-33`). This plan does not change export quantization or promise that every integral SMF subdivision survives compilation exactly.

### What the minimum means

| Document | Existing floor | Musical equivalent of that floor |
|---|---:|---|
| 24 PPQN, normal clocks | 1 tick | 1/96 whole note = 1/64 triplet |
| 48 PPQN, extended clocks | 1 tick | 1/192 whole note = 1/128 triplet |
| 48 PPQN, normal clocks | 2 ticks | 1/96 whole note = 1/64 triplet |
| 480 PPQN, normal clocks | 20 ticks | 1/96 whole note |
| 480 PPQN, extended clocks | 10 ticks | 1/192 whole note |

For other divisions, use the actual formula, not a hardcoded 24/48 assumption. For example, at division 100 the existing normal clock floor is four ticks. Call it the existing **clock-grid floor**; do not pretend floor division gives an exact theoretical driver-clock duration for every unnormalized division.

Named musical cells use absolute whole-note fractions:

```text
straight cell = 4 * PPQN / denominator
triplet cell  = 8 * PPQN / (3 * denominator)
```

A named equal-spacing cell is offered only when this result is an integer and at least the clock floor. Do not truncate the fraction and retain its musical label. At 24 PPQN, straight 1/64 is 1.5 ticks: it cannot be an equal integer-tick grid. That does NOT prevent reaching one tick through the explicitly named Clock selection.

### Arithmetic evidence already run

Independent parent and architect probes checked absolute cells, actual clock floors, strict stepping and floor reachability. Parent full-ladder results include:

```text
24 PPQN normal, Clock=1:
  straight: 24 > 12 > 6 > 3 > Clock(1)
  triplet:  16 >  8 > 4 > 2 > Clock(1)

48 PPQN extended, Clock=1:
  straight: 48 > 24 > 12 > 6 > 3 > Clock(1)
  triplet:  32 > 16 >  8 > 4 > 2 > Clock(1)

48 PPQN normal, Clock=2:
  straight: 48 > 24 > 12 > 6 > 3 > Clock(2)
  triplet:  32 > 16 >  8 > 4 > Clock(2)

480 PPQN normal, Clock=20:
  straight includes 1/64=30, then Clock(20)
480 PPQN extended, Clock=10:
  straight includes 1/128=15, then Clock(10)

100 PPQN normal, Clock=4:
  straight: 100 > 50 > 25 > Clock(4)
  triplet: Clock(4) only; no binary triplet fraction is integral
```

The full-precision arithmetic revision exercised 3,840 ladders and 9,372 feel transitions over divisions 1–960, normal and extended: all ladders reached the actual floor without duplicate or reversed steps; Clock remained the floor through feel toggles. These are proposed arithmetic checks, not production behavior verification. Earlier Auto-materialization probes are superseded and are not acceptance evidence for the revised feature.

Equal-valued terminal musical entries are deduplicated into Clock. At 24 PPQN, 1/64T and Clock are the same one-tick spacing, not two keypresses with identical editing resolution.

## 3. Reference behavior versus Porydaw recommendations

### Confirmed Ableton reference

Official Live manual:

- [Keyboard shortcuts, Grid Snapping and Drawing](https://www.ableton.com/en/manual/live-keyboard-shortcuts/): Cmd/Ctrl+1 Narrow Grid, +2 Widen Grid, +3 Triplet Grid.
- [Arrangement View, Using the Editing Grid](https://www.ableton.com/en/manual/arrangement-view/): narrowing doubles density, widening halves it, and triplet toggle changes e.g. eighths to eighth-note triplets. Live distinguishes fixed and zoom-adaptive grids.
- [Editing MIDI, Changing Note Length](https://www.ableton.com/en/manual/editing-midi/): Shift+Left/Right changes selected note lengths according to grid settings.

The Clock terminal, exact-representability restrictions, mode transitions and signature anchoring below are Porydaw recommendations, not claims about Ableton's complete behavior.

### Recommended behavior

| Concern | Decision |
|---|---|
| State | Musical(denominator) or Clock selection, plus feel; one authoritative editing `Grid`; no Auto state |
| Default | Recommend fixed 1/16 straight: six ticks at 24 PPQN. This replaces the old implicit Auto default and is a proposed initial value, not an additional user requirement |
| Musical | Fixed, exact whole-note fraction independent of meter and camera zoom |
| Clock | Existing `ticksPerClock` floor, available in both feels |
| Ladder | Powers-of-two denominators starting at 4; continue while cells are exact and above the floor; append Clock and deduplicate equal floor entries |
| Cmd+1/2 | Adjacent finer/coarser effective spacing; terminal consumed no-op at bounds |
| Newly drawn notes | Existing double-click/release or threshold-crossing draw gestures use one selected cell as their minimum. Longer drawing remains possible; ordinary click/audition behavior does not change |
| Cmd+3, representable counterpart | Preserve denominator and switch feel; canonicalize an equal-floor result to Clock |
| Cmd+3 at Clock | Keep Clock spacing, toggle feel preference; Cmd+2 then widens into that feel's ladder |
| Cmd+3, unavailable counterpart | Toggle feel, then choose the nearest representable cell in the expected direction relative to the previous spacing: finer toward triplet, coarser toward straight. Clock is the fallback when the triplet ladder has no named cell. Show the resulting selection explicitly |
| Labels | Musical values label exact cells; Clock labels the floor with its tick count in a tooltip. Show a musical equivalent only when exact |
| Auto-repeat | Narrow/widen repeat; triplet toggle executes once per physical press, consuming repeats without another toggle |
| Coarse end | Keep quarter-note / quarter-triplet as the initial coarse bound; expanding to half/whole/bar remains a separate recommendation, not needed for the requested finer range |
| Visual detail | Lines appear/hide with zoom as guides. This automatic rendering behavior never changes editing spacing or creates an Auto mode |
| Scope | Timeline surfaces in the current tab; no new Event List editing or application-global shortcut ownership |

Exceptional transitions are explicit. At division 100, switching a musical straight selection to triplet reaches Clock because no exact named triplet cell exists. The ruler announces the changed selection. This is preferable to silently rounding a musical label or retiming the document, but is a proposed policy the user can change before implementation.

The last refinement need not halve spacing: at normal 24 PPQN straight 1/32 is three ticks, followed by Clock at one tick. The musical ladder obeys doubling/halving where representable; the Clock terminal exposes the actual minimum honestly.

## 4. Module design and invariants

### Selection and resolution

Replace `minDenom` vocabulary and state outright; do not retain aliases. Use a selection value expressing Musical with a denominator or Clock, and a single feel state. Remove Auto rather than carrying an unused variant or hidden fallback. Keep representation details private where practical.

The small public interface must cover:

- Read/set the selection and feel, with validation against the current resolution.
- Narrow, widen and toggle feel semantically, returning whether state changed.
- Enumerate available selections for the ruler menu.
- Resolve effective editing spacing and snap positions through the existing grid seam.
- Resolve visible cells separately from editing spacing.

Ladder building, strict-candidate search, counterpart remapping and canonicalization are implementation details, not a collection of exported index helpers. All must have access to the necessary current selection, effective spacing, feel and document resolution; do not specify incomplete helpers that cannot determine a bound or counterpart.

Do not introduce an allocating public vector-returning math interface simply to support menu construction. The ladder is small and bounded by the metrical timebase. Use fixed-capacity internal storage and `std::span` for a non-owning view if a shared list is needed, or compute command transitions directly from the same math. Document span lifetime. Recompute only when timing resolution changes, not on every snap query or pan; labels belong at the UI formatting step, not in per-cell arithmetic.

Normalize restored state when document division or clock configuration changes. Preserve supported selections; canonicalize an equal-floor selection to Clock. If a previously selected musical cell is no longer representable, fall back to Clock while retaining feel and updating the label. Do not retain invalid denominators behind plausible labels. No document content changes.

Before a document is bound, retain positive-stride guarantees and disable document-dependent Clock/menu operations. Do not let an unbound `m_clock == 0` become a zero snap stride. Bind resolution before applying restored explicit state.

### Musical and display responsibilities

Effective editing spacing depends only on selection and timing resolution, never camera scale. Preserve the existing adaptive visual ladder and density thresholds without the old selected-denominator cap. Display guides can therefore be finer or coarser than editing cells; selection does not control guide visibility. Delete the camera-dependent editing branch and hidden one-step-finer snap. The concrete visual/editing oracle is specified in §8.

Concretely, separate the responsibilities currently combined in `gridTicksIn(..., bool snap)`: `snapTicksAt` and snap-position helpers resolve the fixed editing grid; `gridTicksAt`, `gridTicksAtScale` and visible-cell queries remain display calculations (rename for clarity during the caller cutover if needed). `beginDraw` must stop taking its duration from the display query. Rendering and editing can share timebase/feel math without sharing a zoom-derived step.

Existing segmentation remains: positions are anchored at `seg.start` and the upper snap candidate clamps at the next signature change. Ordinary bars do not restart the grid. For example, a 16-tick quarter-triplet grid in 3/4 at PPQN 24 continues from 64 to 80 across the bar at 72 unless that tick also changes signature.

Next-cell advancement must honor the actual signature boundary even when the selected spacing is identical on both sides. Put this operation at the shared Grid seam and use it for page/projection cell advancement; do not retain per-surface spacing-change searches. Normal musical cells clamp and restart; Clock/fine cells retain absolute anchoring. Guarantee strict progress while below the requested limit, clamp to that limit, and avoid overflow. The partial-cell pencil/ramp oracles in §8 exercise both consumers.

Clock mode should use the same absolute anchoring as existing fine snapping, not merely the same spacing. This matters when an unnormalized document places a signature change off the clock grid. At Clock, normal and fine snapping must agree in both spacing and positions; add that boundary case to verification. Musical selections retain signature anchoring.

Fixed-grid rendering must not enumerate every fine cell across a large zoomed-out time range and discard it afterward. Apply detail suppression or stride selection before emission, so line work is bounded by visible detail. Grid state changes must not rebuild unrelated note, velocity or automation content.

### Note creation and length editing

`PianoRoll::beginDraw` currently initializes duration from `gridTicksAt` (`pianoroll_gestures.cpp:260-262`), while `updateDrawDrag`/`drawSpanAt` obtain the snap cell and enforce a minimum (`pianoroll_gestures_active.cpp:92,117-127`). Migrate both to the same selected editing step, never a visible-cell or camera-derived value. Preserve existing creation gestures: double-click on empty space followed by release, or a plain drag crossing the activation threshold. Ordinary empty-space click still auditions; a sub-threshold plain drag creates nothing (`pianoroll_interaction.cpp:49-74`, `pianoroll_gestures.cpp:218-231`).

At 24 PPQN with 1/16 selected, zero-drag double-click creation produces six ticks, and draw-drag cannot create a shorter note, regardless of zoom or visible lines. At Clock, the minimum becomes one tick. Do not add click-to-draw or remembered-length behavior.

Pointer length editing snaps using the selected editing grid. Future keyboard lengthening/shortening requests a duration delta of one full selected cell; it must not derive a different increment from zoom or from the nearest visible guide. Snap-to-next-line and a full-cell duration delta remain distinct operation semantics.

Changing grid size never resizes existing notes, including imported notes shorter than the new-note minimum. Minimum newly drawn length is not a new document-wide duration invariant. The document timing representation stays unchanged.

The future keyboard resize plan still defines which edge moves, off-grid offset handling, minimum-duration clamping for existing notes, and mixed-length selections. Only its shared step source is fixed here; no keyboard resize implementation or contextual Duplicate is added by this grid feature.

## 5. Consumer and caller cutover

All paths below already consult `SongView::grid()`; audit each against explicit Musical and Clock semantics rather than assuming changing one formula is sufficient.

| Consumer | Evidence / operation |
|---|---|
| Note draw initialization | `pianoroll_gestures.cpp:260-262`: currently uses visible-grid initial duration; migrate to selected editing step |
| Note draw continuation | `pianoroll_gestures_active.cpp:92,117-128`: enforce the same selected-step minimum, independent of visible detail |
| Note move | `pianoroll_gestures_active.cpp:21-22`: relative snapped delta; preserve off-grid offsets |
| Pointer resize | `pianoroll_gestures_active.cpp:55-60`: absolute edge snapping |
| Note nudge | `pianoroll_commands.cpp:180-182`: next/previous grid line |
| Range nudge | `rangeedit.cpp:442-444`: interval movement on grid |
| Edit cursor | Roll/ruler interactions: `snapTick` |
| Time selection / edges | Roll/ruler interactions: `snapTick` |
| Markers and signature drag | `timeruler_interaction.cpp:27,77`: existing snap calls migrate with editing semantics |
| Paste anchoring | `rangeedit.cpp:559,628` |
| Automation pencil/cells | `editordrawer/automationprojection.cpp:56-72,128-134`: selected editing cells, independent of rendered guides; `automationcanvas.cpp:667` node hover placement also consults snapping |
| Automation ramp / partial cells | `automationcanvas_gesture.cpp:209,329` uses page advancement; `editordrawer/automationpage.cpp:303-324` and `automationprojection.cpp:75-92` currently detect transitions by comparing spacing. Replace those duplicated searches with the shared signature-aware next-editing-boundary operation; fixed spacing alone cannot detect a signature change |
| Voice change insertion/drag | `voicechangearea.cpp:430,520`, including Alt-fine |
| Pitch-bend popup | `pitchbendgraph.cpp:603-672`: `normalCellTicksAt` feeds event sampling and must use the selected editing step, not `gridTicksAtScale`. Only genuine display queries may use popup pixel scale; Alt sampling retains the clock floor |
| Velocity | No independent horizontal snapping; audit grid rendering, not vertical detents |
| Visible-cell operations | `grid.cpp:45-69`: distinguish genuinely visible cells from the effective editing step |
| Clipboard duration fallback | `pianoroll_commands.cpp:238-239`, `rangeedit.cpp:311-312`: existing zero-duration fallback must use the selected editing step; preserve nonzero copied durations and relative offsets |

Rename/reshape all production and check callers of `minDenom`, `setMinDenom`, `normalizeMinDenom`, `setGridMinDenom` and `ViewState::gridMinDenom`. Use LSP references/rename at implementation time.

Known production sites: `grid.h/.cpp`, `songview.h/.cpp`, `timeruler.h/.cpp`, plus the consumer table above. Current check sites and exact dispositions are in §8; obsolete `viewcheck.cpp`, `tabcheck.cpp`, `mainwindowroutingcheck.cpp` and `pitchbendcheck.cpp` filenames are not implementation targets. Capture/apply remains in-memory per-tab `ViewState`; `SongTab` preserves it across reloads. No new settings keys, sidecars or persistence compatibility aliases.

## 6. Keyboard and refresh integration

### Existing routing seam

Add rebindable Timeline-context commands to `src/ui/keymap.cpp` using the existing PortableText convention:

```text
roll.grid_narrow   Ctrl+1  (Cmd+1 on macOS)
roll.grid_widen    Ctrl+2
roll.grid_triplet  Ctrl+3
```

Add recognition and semantic dispatch in `src/ui/songview/editkeyrouting.cpp`. These are grid-state commands, not selection-target edits. Explicitly require Timeline origin: keymap context metadata alone does not prevent Event List fallback delivery.

Reuse the existing live-gesture guard. Retain protected local-input ownership. Probe a modified chord ignored by QML rename input: if it reaches `TimelineCanvas.qml` root fallback, add the narrow text-editing-state gate at the existing Quick routing seam. Do not create a global event filter or focus framework. Grid commands must not mutate while protected editors own input, including rebound text keys.

Consume triplet auto-repeat without changing feel again. Declining it could deliver a second attempt through root fallback. Do not create window-level actions duplicating physical shortcut ownership.

### Grid-only refresh

`SongView::refreshTimelineViews` currently requests broad Quick/automation refresh (`songview.cpp:973-979`). Refresh only what actually changed: editing-size changes update controls and affected previews; they need not rebuild guide geometry when the guide policy inputs are unchanged. Feel or visual-detail changes may require a targeted grid refresh:

- Existing `PianoRollQuickDirty::Grid` for roll lines when visual inputs changed.
- Selection labels and affected editing previews for a size change; ruler marks only when their visual inputs changed.
- Grid-only velocity, voice-change and automation layers when required; reuse `VelocityArea::rebuildQuickGrid` (`quick/velocityquick.cpp:139-144`) and banded-grid composition.
- No note-fill, velocity-content or automation-curve rebuild merely because grid spacing changed.

Extend existing dirty flags where required rather than adding a second render scheduler. Preserve the existing coalescing timer and retained-layer revision checks. Audit `refreshDrawerPages()` in the host setter path so a subsequent broad refresh does not undo the grid-only work.

Affected render sites: `quick/timelinequickview_pianoroll.cpp:177-250`, `quick/timerulerquick.cpp:140-250`, `quick/timelinequickscene.cpp` banded-grid composition, `quick/{velocity,automation,voicechange}quick.cpp`, and `quick/timelinequickview.h/.cpp` dirty propagation.

## 7. Implementation phases

### A. Grid state, resolution and caller migration

1. Introduce explicit selection and resolution-aware ladder behind `Grid`; remove old floor vocabulary and values.
2. Separate fixed editing spacing from visual detail: remove the Auto editing branch and retain zoom-dependent line visibility as display-only behavior. Migrate click/draw-drag duration initialization and minimum enforcement to the selected step together.
3. Implement floor reachability, canonical Clock selection, feel transitions and revalidation on resolution changes.
4. Migrate the ruler menu/labels, all state capture/apply sites and existing callers together.
5. Apply the fixture and check migration in §8 in the same cutover: replace obsolete editing invariants; migrate independent seed/oracle values and state tests; preserve unrelated behavior. Land the model and note-creation/resize regressions before adding shortcuts so routing work cannot conceal a broken grid model.

### B. Commands and ownership

1. Register commands, bindings and shared dispatch.
2. Add the explicit origin and repeat behavior.
3. Exercise actual Quick delivery from surfaces and root fallback; implement a narrow text gate only if required by the probe.

### C. Grid-only drawing and density safety

1. Add/reuse grid-specific dirty paths through every affected renderer.
2. Remove broad invalidation from grid changes, including secondary drawer refreshes.
3. Exercise Clock at extreme zoom-out and pan; bound work before geometry emission, not after allocating it.

### D. Verification and documentation

1. Run focused and full gates below; resolve failures before handoff.
2. Document three shortcuts, fixed editing size versus zoom-dependent guide visibility, new-note minimum length, Clock and removal of Auto.
3. Extend `docsrc/manual/shortcuts.md` and the grid section of `docsrc/manual/piano-roll.md`; preserve unrelated existing prose/stubs. Update CHANGELOG with deliberate behavior migrations.
4. Remove throwaway probes, format only appropriate touched source files, and leave no obsolete aliases or scaffolding.

## 8. Reviewed check migration and proof

This inventory replaces the old “audit existing checks” instruction. It was proposed by evidence-plan-architect against the migrated Qt Test tree and reviewed against source by the parent. Paths below are relative to `src/checks/`. **Modify** means preserve the named behavior and change its setup/oracle; **replace** means remove the obsolete assertion, not repin it until green. Unlisted, unrelated assertions remain unchanged. New slot names below are proposed, not claims of existing tests.

### Fixture and oracle rules

- Use existing Qt Test classes and fixtures; no new harness, framework, registry layer or production test-only interface. Add declarations/data slots to the corresponding existing test class. Keep test bodies cohesive. `rollcheck/selection.cpp` is already 603 lines: move its existing `selectionMinimumDrawDistance` body into `rollcheck/pencil.cpp` (currently 240 lines) and put the new creation regressions there, rather than growing the selection file. Both are already in the checks build target; no new source or catalog entry is needed.
- In rollcheck shared setup, explicitly select 1/16 straight and assert the document is 24 PPQN as a fixture precondition. This is a test choice, **not** an assertion about the application's proposed default. Use an independent expected step of six ticks and a seed-note duration of twelve ticks (two cells) where tests need a resizable note. Cases needing another grid/duration select/request it explicitly.
- `harness.cpp::findFreeCell` must take/use the requested seed duration; `Cell.dur` must no longer mean a camera-derived visible cell. `makeResizeSeed` supplies the independently chosen expected step, not a snapshot of `snapTicksAt`. Reuse existing placement helpers; do not build another fixture framework.
- Camera/grid queries may locate a usable pixel or unoccupied note position. They must not supply the expected six-tick duration, expected ramp endpoint, or expected snapping increment in the regression intended to verify that query. Use literal musical oracles and assert committed document data.
- Plain press/release on empty roll space auditions; it does not create a note. Preserve the drag activation threshold. Zero-drag creation is the existing **double-click on empty space followed by release**; threshold-crossing drag is the other creation path. Do not change gesture ownership to make the test easier.
- `eventviews/eventview_fixture.cpp:46` makes Basic 24 PPQN and Signatures 48 PPQN. Use Basic plus public document signature edits for the new 24-PPQN case; retain the existing 48-PPQN fixture for focused compatibility. Do not silently apply 24-PPQN expectations to Signatures or introduce a second fixture framework.

### Existing checks: required disposition

| Current file / test or helper | Disposition and required change |
|---|---|
| `eventviews/viewbuckets_grid.cpp::snapLadder` (:143–181) | **Replace** the floor/hidden-finer-snap matrix with `fixedEditingAndAdaptiveGuides`. Preserve the display threshold behavior separately; editing does not follow it. Add `fixedGridCommandLadders` for the semantic command transitions. Oracles below. |
| Same file, `gridLinesSnappable` (:183–211) | **Replace**. Remove “every displayed line is snappable.” Fold the visible-but-not-snappable counterexample into the display/editing test; retain actual signature behavior in `signatureSnapAnchoring`. Do not keep two contradictory tests. |
| `rollcheck/harness.cpp::prepare/findFreeCell/makeResizeSeed` (:32,148–181,212–223) | **Modify setup/oracles** as above. Old quarter floor meant visible 24 ticks but snapping 12; it is not equivalent to fixed quarter. Do not mechanically rename the setter and repin all failures. |
| `rollcheck/selection.cpp::selectionMinimumDrawDistance` (:265–312), moving to `rollcheck/pencil.cpp` | **Move and modify**: preserve below-threshold no-note behavior; replace duration-from-getter assertion with independent six-tick creation expectations. Keep the existing PianoRollTest class; place double-click/release and Clock creation cases in the cohesive pencil module, not the oversized selection file. |
| `rollcheck/resize.cpp::resizeOffGrid/resizeSelection` | **Modify** seed/oracles, preserving grip behavior, grouped editing and undo. Use independent selected-step values; retain off-grid original-edge stickiness. |
| Same file, `resizeMinimum` (:148–209) | **Modify**. Its `duration == snap` assertion only applies to a start on the editing lattice. Check the on-grid minimum separately from the permitted five-tick off-grid result below; preserve its existing narrow-note rendering checks. |
| Same file, `resizeAbutting` (:212–277) | **Modify** to two abutting twelve-tick notes on a six-tick grid. Shrinking one side by six leaves six ticks and leaves its neighbor unchanged. Keeping a one-cell seed and expecting `Cell.dur - snap` would demand a zero-length note under the new contract. Preserve both boundary-side ownership cases and undo. |
| `rollcheck/keyboard.cpp`: `keyboardTranspose`, `keyboardKeepVisible`, `timelineRulerScope`, `timelineOtherEventsStrip`, `timelinePartialSelectionRepaint`, `keyboardTimeSelectionShortcuts`, `timelineDuplicateTime`, `timelineInsertBlankTimeTracks`, `timelineInsertBlankTimeLanes` | **Modify oracle source only** through `makeResizeSeed`, then run all nine. Preserve their existing nudge, range, paste, insertion, selection and undo contracts. This is not permission to implement a new contextual Duplicate or keyboard length-edit command. |
| `rollcheck/identity.cpp::viewStateRoundTrip` (:135–220) | **Modify** the grid portion: remove the old accepted-denominator/Auto normalization domain. Round-trip supported selection and feel and assert effective editing behavior after restoration. Put timing-resolution revalidation in the model test below; preserve unrelated view-state coverage. |
| `rollcheck/static/camera.cpp::tickRangeWalksFractionalLattice/affineCameraProjection` | **Setup migration**: remove explicit Auto state. The first remains a display-lattice traversal test; the second remains a camera/snap projection test with an explicitly selected grid. Do not replace display expectations with editing spacing. Other static geometry/bar grouping tests remain unchanged. |
| `workspace/tabs_lifecycle.cpp`: `verifyFreshView`, `lifecycle`, `reloadRetainsCameraAndFreshOpenResetsIt`; `workspace/tabs_persistence.cpp::persistenceRestoresTabs` | **Modify** grid state vocabulary and lifecycle oracle. Remove exact-zero/default-grid assertions. Capture an independent fresh-session baseline, deliberately choose a different selection/feel, then prove reload preserves it and fresh opening does not inherit it. Do not repin these to a literal proposed default. |
| `mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp` and `mainwindowrouting/mainwindowroutingfixture.h::sameViewState/hasCanonicalFreshViewState` | **Modify** explicit seeds, retained state and fresh-landing comparison. Remove the obsolete `gridMinDenom != 0` guard; compare against the fresh-session baseline, not nonzero-ness or a magic enum value. Preserve focus/readiness/reload assertions. |
| `automation/automationpencil.cpp::pencilStrokeOnEmptyLaneCommitsOnce` and the two `pencilSingleClickOn...AtCellEnd` tests (tempo and pitch bend) | **Modify timing oracles**, retain transaction/endpoint restoration behavior. The current expected ticks come from `point.mapping.cell` (:263–270,304–305), so they can agree with a broken grid. Select six ticks explicitly; assert the independent cell endpoints below, then cover Clock without duplicating the whole suite. |
| `automation/automationparity.cpp::sweepAndRampCommit`; `automation/automationpreviews.cpp::shiftRampPreview` | **Modify explicit grid setup / extend timing assertions** for the selected-step ramp case below. Preserve preview-before-release, one commit and outside-range values. Domain gesture tests using injected tick callbacks are not proof that production grid selection reaches these surfaces. |
| `automation/automationvoice.cpp::voiceAltDragUsesFineSnap` (:172–221) | **Modify** to select a musical grid explicitly before requiring normal and fine positions to differ. Extend actual drag coverage to Clock, where they agree. Getter equality alone does not count as a voice-input test. |
| `pitchbend/curve.cpp::strokeAcrossSignatureBoundaryAlignsToDynamicGrid` (:331–367) | **Replace the dynamic-grid timing oracle** with fixed editing sampling across popup sizes/signatures. Its current `gridTicksAtScale` expectation validates committed lane points, not rendering. Preserve before/after-signature coverage. `altDragCreatesFineGridRamp` keeps its fine-clock/undo contract. |
| `selectionkey/corearrows.cpp`, `coreediting.cpp`, `windowtier_keyboard.cpp` | **Keep existing ownership/operation tests**, with shared state vocabulary migrated where required. Add the grid-specific delivery cases below to the existing core/window tiers; do not treat existing arrow-key tests as proof of Cmd+1/2/3 delivery. |
| `selectionkey/gesturecommands.cpp`, `windowtier_gestures.cpp`, `localinputtier_*.cpp` | **Extend** existing gesture/local-input cases with grid commands; retain their production event delivery. No new global focus harness. |
| `keyboard/keymapregistry.cpp::routedCommandConflicts_data` | **Extend** the existing command inventory for Timeline grid commands: overlap PianoRoll/Velocity/Automation, not EventList. Keep shared registry tests. Do not add redundant rows merely echoing default bindings; prove required chords/rebinding through input delivery. |
| Existing automation actions/ownership/raster, pitch-bend fine editing, host-seam positive-stride checks, other roll/static checks and timeline-pan suites | **Keep unrelated behavior**; run as integration gates. Their continued success does not substitute for the independent editing-step oracles above. Do not add new tests merely because these files consume a grid query for placement. |

### Exact model and input oracles

**Model tier — existing ViewBucketsGridTest, direct production Grid/SongView interface.** Semantic narrow/widen/toggle operations are required by §4; test them here, not through a duplicate event-delivery matrix.

- `fixedGridCommandLadders`: straight ticks **24 → 12 → 6 → 3 → Clock 1**; triplet **16 → 8 → 4 → 2 → Clock 1**. Widen reverses each list; further commands at either bound leave selection unchanged. No duplicate one-tick 1/64T entry. A 1/16 feel toggle gives 6 ↔ 4; toggling at Clock preserves one tick and the feel used on widening. This catches menu-range truncation, reversed commands and terminal aliases.
- `fixedEditingAndAdaptiveGuides`: use the existing font-relative `cell = layout::fontPx(4.0 / 3.0)`. At `pxPerBeat = 4*cell - 1` and `4*cell`, preserve display spacing **12 then 6**. Explicit 1/8 editing remains **12** at both. The visible tick-6 guide in the second view is not an editing snap point. Selecting 1/16 changes editing to **6**, not display detail. At that selection, snap-down(13)=12 and snap-up(13)=18 across zooms. Preserve the old adaptive display ladder/thresholds **without the old selected-denominator cap**; no hidden Auto editing state. This catches either direction of display/editing coupling.
- `signatureSnapAnchoring`: in a 24-PPQN Basic document, set 3/4 at zero and a signature change at tick 85. With quarter-triplet selected, the cell continues **64 → 80** across the ordinary bar at 72; snap-up(84) clamps to **85**, then the next full cell ends at **101**. In the existing 48-PPQN fixture with normal clocks, add a signature at **37**: Clock floor is **2**, and normal/fine snap-down(37)=36, snap-up(37)=38. Do not reset Clock anchoring at the odd signature tick.
- `gridResolutionRevalidation`: preserve a supported selection across rebinding; a straight 1/64 selection valid at 48 PPQN (three ticks) becomes Clock when rebound at 24 PPQN, retaining feel. Canonicalize a 24-PPQN triplet 1/64 state to Clock. Verify unbound queries cannot produce zero strides and document-dependent selection changes are disabled until binding. No exhaustive PPQN matrix or document retiming.

**Qt input tier — existing roll, automation, pitch-bend and selectionkey fixtures.** Deliver events to the production input surface/window; assert notes, lane points, history or visible command state after delivery. Direct handler calls or synthetic QObject delivery are not evidence of native OS input.

- **Creation** (`pencil.cpp`): explicitly selected six ticks at zooms on both sides of the visual threshold; double-click/release creates six ticks, sub-threshold plain drag creates none, threshold-crossing drag creates at least six, and a longer drag creates twelve or more. Assert leftward as well as rightward draw minimum. At Clock the minimum is one tick; choose a sufficiently zoomed view to manipulate a one-tick cell reliably. Retain undo. Do not demand that a fixed pixel drag threshold always spans exactly one cell at every zoom.
- **Move/resize** (`resize.cpp` and existing move coverage): on a clear track, six-tick grid, note start **13**, duration **7**. A pointer delta of six moves it to **19** with duration seven. For resize, express targets as desired grip endpoints (grip + pointer delta), not raw pointer ticks: endpoint **24** produces duration **11**; endpoint **18** produces duration **5**. The original off-grid edge must not jump on a sub-threshold movement. Preserve the two-abutting-note case above. Translate anchors by a multiple of the grid if needed to avoid fixture content; do not derive expected results from the grid implementation.
- **Existing content** (extend the roll grid/creation scenario): seed a one-tick note, then change selected size, feel and zoom without an edit gesture. Note data, document revision and serialized song remain unchanged. This catches accidental enforcement of the new-note minimum on old content.
- **Nudge/paste/range operations** (`keyboard.cpp` and existing selectionkey core editing cases): selected six-tick grid and independent six-tick `snapCell`. Retain next/previous-line semantics for nudge and the original intra-clip offsets/durations for paste. Exercise both six ticks and Clock in the existing scenario, not a new generic command harness. Camera changes must not alter the resulting anchor. Existing duplicate/insert behavior remains in its current tests.
- **Automation pencil** (`automationpencil.cpp`): selected six ticks, paint the cell beginning at **48**; the held tempo/bend value returns at **54**, not at a visible-guide boundary. At Clock it returns at **49**. Exercise two zoom levels and preserve no mutation before release / one undoable commit. Add one partial-cell case: at 24 PPQN with a signature change at **61**, the musical cell starting at **60** ends at **61**, not 66. Expected ticks are literals; existing mapping helpers may choose the input pixel/value only.
- **Ramp** (`automationparity.cpp::sweepAndRampCommit`): explicitly selected six ticks, edit a ramp from **48 to 66**, checking sampling positions **48,54,60,66**, held endpoint/outside values and undo. Add one signature-tail case, not a Cartesian test matrix: with a signature change at **61**, the ramp from **48 to 67** samples **48,54,60,61,67**. This catches page advancement incorrectly looking for a spacing change; the pencil case catches the projection copy of that algorithm. Use non-flat values that expose missing intermediate samples. Preserve preview/commit agreement and no early document mutation. An injected `tick + 1` callback is not grid-integration proof.
- **Voice fine mode** (`automationvoice.cpp`): with a musical six-tick grid, actual normal/Alt drags to a target near an off-lattice tick must produce different expected document positions (for example target 13: normal 12, fine 13). Undo between deliveries. At Clock both deliveries land at 13. Keep real drag activation and grip offsets; do not merely compare two getters.
- **Pitch-bend popup** (`pitchbend/curve.cpp`): select six ticks explicitly; draw across the existing signature change at two popup widths. Interior normal samples follow the selected six-tick lattice, with actual consecutive sample spacing checked where values change, independent of popup pixel scale. Preserve signature clamping/anchors and endpoint values; Alt still uses the clock floor. Popup-size changes may change guides, not generated event resolution.
- **Key delivery** (existing `selectionkey-{core,window}`): Cmd+1/2/3 operate exactly once from band input and chrome/root fallback; model-step assertions detect double delivery. Bound keys are consumed no-ops, not a second fallback attempt. Narrow/widen repeat; triplet autorepeat is consumed without another toggle. Rebind one grid command to an unused chord, demonstrate changed delivery, restore binding and demonstrate original delivery; isolate registry changes with the existing fixture cleanup.
- **Ownership** (existing `selectionkey-gesture/local-input`): grid commands do not mutate during note/range/scrollbar/velocity gestures. Protected QML rename/value inputs and rebound text keys retain local behavior; Event List delivery does not mutate the timeline grid. Use current local-input helpers and actual focus routing, not just a registry context assertion. These are integration regressions against leakage/double execution, not default-binding table tests.

### Native smoke, regression gates and implementation report

Native smoke uses the real application and fixture project: select 1/16 at 24 PPQN, verify six-tick double-click/draw creation while zoom reveals/hides guides; exercise pointer resize, Cmd+1 to Clock and back in both feels, a protected rename and a live drag. Verify labels/menu as smoke, not permanent wording assertions. Keyboard length extension remains deferred.

At minimum zoom on a long song with Clock selected, pan and inspect bounded primitive/CPU work using existing instrumentation. Size-only changes must not rebuild unchanged guide geometry or unrelated content. No large traces, new telemetry framework, or permanent source-text/primitive-count tests. Report explicitly if native OS input or visual verification is unavailable; Qt synthetic delivery is not native evidence.

Use current catalog names, not the obsolete `viewcheck` filter:

```sh
deno task verify --filter view-buckets-grid --verbose
deno task verify --filter rollcheck --verbose
deno task verify --filter selectionkey --verbose
deno task verify --filter keymapcheck --verbose
deno task verify --filter automation-editing --verbose
deno task verify --filter pitch-bend-editing --verbose
deno task verify --filter tabcheck --filter sessioncheck --verbose
deno task verify --filter mainwindow-routing --verbose
deno task verify
```

`verify` builds checks first. Filters are repeatable substrings: `rollcheck` includes `rollcheck-static`; `selectionkey` includes all four tiers. `--qt <slot>` requires exactly one selected Qt Test harness; for example, after its implementation: `deno task verify --filter view-buckets-grid --qt fixedEditingAndAdaptiveGuides`. Confirm selected harnesses actually ran. Register new slots in the existing class, not new catalog entries. The full gate covers the remaining host/drawer/raster/pan suites.

Implementation handoff must name modified/replaced slots, report commands and executed counts/results, identify any intentionally unchanged affected checks, and distinguish Qt event proof from native smoke. Resolve failures; never update an oracle solely to match observed output. This revision changes documentation only: no build, check run or GUI verification is claimed.

### Review decisions

Accepted: current Qt Test paths/filters; removal of the old finer-snap/all-guides-snappable invariants; independent fixture oracles; the abutting-note zero-duration trap; 24-versus-48 fixture precision; actual gesture ownership; and targeted consumer/state coverage.

Rejected or corrected: repinning application-default assertions to 1/16; adding redundant default-binding rows; letting expected durations come from production getters; treating voice getter equality as input proof; and retaining the pitch-bend dynamic-grid oracle as “display-only” when it checks committed events. Ordinary-click-to-draw wording is corrected. Private helper names remain implementation choices; test behavior, destination modules and proof obligations above do not.

## 9. Deliberate migrations and rejected shortcuts

- **Floor → explicit selection:** choosing a musical value no longer merely limits adaptive fineness. Its spacing is fixed, including at zoom-out.
- **Beat-relative → whole-note fraction:** 1/8 means an eighth note in 6/8 as well as 4/4; quarter-triplet becomes a real quarter-triplet.
- **Zoom-coupled editing → fixed editing resolution with adaptive visual detail:** preserve line visibility behavior, but new-note minimum duration and length-editing snaps use the selected grid at every zoom. Delete Auto and the hidden finer-than-displayed editing branch rather than retaining legacy compatibility behavior.
- **Four menu values → resolution-derived ladder plus Clock:** reaches the actual minimum without fake labels, magic denominator values or new per-surface stores.
- **Unsupported restored values → explicit revalidation:** no invalid musical state hidden behind a stale label.

Rejected: stopping at 1/32; labeling a rounded 1.5-tick cell as equal 1/64; silently retiming imported documents; adding window-global shortcut ownership; drawing every sub-pixel clock line; exposing a large helper/index API instead of semantic grid operations.

Cmd+4/5, swing/dotted grids, coarser half/whole/bar choices, the keyboard note-resize operation and contextual Duplicate remain outside this implementation plan. Auto is removed entirely; there is no viewport-based transition into a fixed mode. The proposed default is 1/16 straight. The central requirement is a fixed shared editing step through the real clock minimum, with independently zoom-dependent guide visibility—not preservation of the old menu or editing policy.
