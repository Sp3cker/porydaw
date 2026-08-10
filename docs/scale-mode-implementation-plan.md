# Scale Mode Implementation Plan

## Authority and cutover

`scale-mode-spec.md` is the normative behavioral contract for this work.

This plan supersedes:

- The previous v2 contents of this file
- `scale-mode-tasks.md`
- Implementation recommendations in `scale-mode-review.md`

`scale-mode-research.md` remains useful background, but its Ableton pitch-remapping tables are not porydaw's Scale Mode representation.

The implementation must not add Scale Mode fields to `ViewState`, `ViewSidecar`, `SongCfg`, `midi.cfg`, or application settings.

## Definition of done

The feature is complete when:

- New tabs start at C Major and Off.
- Off preserves the current chromatic piano roll.
- Highlight applies the specified lane-only purple tint.
- Fold displays scale pitches plus selected-track exception pitches.
- Fold editing follows the specified diatonic destination rules.
- Root, Scale, and Mode remain independent per open tab.
- Selecting another track performs Fold → Highlight.
- No Scale Mode state is persisted.
- Catalog, document editing, pitch geometry, tab routing, and visual behavior have focused verification.

## Design

### Scale catalog module

Add a small, allocation-free scale module containing:

- An explicit `ScaleId` for each of the 28 catalog entries
- A 12-bit root-relative membership mask per scale
- Display names
- A display-order array of `ScaleId` values
- Root rotation and MIDI-pitch membership
- Next/previous scale-pitch queries
- The pure multi-note diatonic destination resolver

The interface must use `ScaleId`; combo-box positions are presentation data only. Give every ID an explicit value and never reuse a retired value.

Do not add:

- Ableton catalog indices
- A chromatic-input-to-output map
- `fold()` or `foldPC()`
- Map idempotence requirements

Highlight and Fold need membership and ordered scale pitches, not pitch-remapping presets.

### Piano-roll pitch layout module

Put every pitch-to-row and row-to-pitch decision behind one pure pitch-layout interface. The layout owns:

- A sorted fixed-capacity list of visible MIDI pitches
- A reverse lookup from MIDI pitch to visible row or hidden
- Visible row count
- Nearest-visible-pitch lookup with lower-pitch tie breaking
- Scale-pitch versus exception-pitch classification

The maximum remains 128 pitches, so the implementation should use fixed-size storage and rebuild in bounded time without heap allocation.

In Off and Highlight, the layout is the complete chromatic 0–127 sequence. In Fold, it is the union of:

- Every scale pitch in 0–127
- Every exact pitch occupied by the selected track

Piano-roll painting, piano-key painting, note rectangles, hit testing, hover, drawing, drag previews, scrolling, zoom anchoring, and key visibility must all consume this interface. Do not leave a second 128-row coordinate convention beside it.

### Per-tab runtime state

`SongView` owns the transient Root, Scale, and Mode state. Keep it separate from the detached/persisted `ViewState`.

State changes have four effects:

1. Reclassify scale membership whenever Root or Scale changes, even when the visible sequence remains chromatic.
2. Rebuild the visible pitch sequence when Mode, Root, Scale, or selected-track occupancy changes it.
3. Invalidate the cached roll rendering.
4. Notify the active MainWindow controls when required.

Run viewport anchoring only when the visible pitch sequence changes. A Highlight Root or Scale change needs reclassification and repaint, not a Fold-style geometry rebuild.

The source currently has several routes that replace the active editable track. Centralize that transition and route explicit selection, selected-track deletion/remapping, and model fallback through it. Change Fold to Highlight only when the selected track's identity changes; a pure index remap of the same track is not a selection change.

### Generic document pitch-destination edit

The current document move operation applies one semitone delta to every note. Diatonic multi-note movement needs different destination pitches for different source pitches.

Extend the document layer with one generic batch move that accepts:

- The resolved notes
- Their concrete destination pitches
- The common time delta, when a drag also moves in time
- Whether repeated keyboard presses may merge into one undo gesture

The document layer must remain scale-agnostic. The UI resolves the diatonic destinations before calling it.

The batch edit must preserve existing document invariants:

- One undoable command per gesture
- Stable note identities
- Deterministic undo and redo
- Existing overlap resolution against unselected notes
- Existing mutation publication and track remapping
- Mergeable held-key nudges that recompute from the gesture's original notes

Keep the existing uniform-delta path for chromatic moves and multi-track time-range transposition.

### Fixed highlight tint

Define the Highlight source color once as `#b595fc` with 50% paint opacity.

This is a fixed Scale Mode visual constant, not a theme-derived color. Do not add the previous three scale theme roles. Theme roles are required to be opaque, whereas this contract requires a source-over tint.

Composite the tint during lane painting after the ordinary lane background is established and before grid lines, notes, drag previews, and overlays. Keep ghost-note color calculation on the ordinary untinted lane backdrop so Highlight does not change note-face pixels.

## Implementation sequence

### Wave 1 — Pure scale behavior

Implement the catalog, membership queries, scale-pitch stepping, and collision-free diatonic destination resolver.

The resolver must:

- Operate on distinct source pitches
- Give repeated source pitches one shared destination
- Process upward moves low-to-high and downward moves high-to-low
- Advance through scale pitches to prevent selected-source collapse
- Ignore note time and duration when assigning destinations
- Reject the complete operation when any final pitch is outside 0–127

Add a focused `--scalecheck` harness using the project's existing self-check convention. It should verify:

- All 28 IDs, names, masks, and display order
- C Major as the default
- Root rotation
- First scale pitch above/below an exception pitch
- Multi-degree movement
- C + C# upward in C Major → D + E
- C# + D downward in C Major → B + C
- Repeated-source behavior
- Ordering, uniqueness, and MIDI-boundary rejection

Add the harness to the application's check dispatch and `tools/run_checks.sh`.

### Wave 2 — Generic batch pitch moves

Generalize the document move command or add a sibling command that can apply concrete per-note destination pitches while retaining a common time delta.

Reuse the existing edit-operation construction and overlap resolver. Do not put scale membership in `SongDocument`.

Extend `--editcheck` to prove:

- A batch can move different source pitches by different amounts.
- Note IDs survive the move.
- Undo restores the original MIDI bytes and note identities.
- Redo reproduces the resolved destinations.
- Repeated mergeable nudges remain one undo gesture.
- An inverse merged gesture can become obsolete as today.
- Collisions with unselected notes retain existing trimming/overlap behavior.
- A rejected resolver result creates no document revision or undo entry.

### Wave 3 — Central pitch projection

Introduce the pure pitch-layout module and replace fixed chromatic geometry assumptions.

Move these concerns onto the shared projection:

- Row-edge generation
- Pitch-to-row and row-to-pitch conversion
- `keyRect` and note rectangles
- Y-coordinate hit testing
- Keyboard geometry
- Visible row iteration
- Maximum vertical scroll extent
- Ensure-key-visible behavior
- Initial camera centering
- Cursor-anchored key-height zoom

Keep the current row height. Only the number and identity of rows vary.

Extend `--rollcheck` with projection-level checks:

- Off/Highlight contain 128 rows and preserve current mapping.
- Fold keys are sorted and unique.
- Every scale pitch is present.
- Exact occupied exception pitches are present.
- Hidden pitches have no row.
- Row-to-pitch and pitch-to-row are inverses.
- Nearest-visible anchoring uses the lower pitch on a tie.
- Scroll and zoom remain bounded at the top and bottom.

### Wave 4 — Runtime state and toolbar routing

Add Root, Scale, and Mode to `SongView` as transient runtime state.

Add adjacent Root, Scale, and Mode combos to the transport toolbar:

- Root uses the existing sharp-only pitch names.
- Scale items store stable `ScaleId` values as item data.
- Mode contains Off, Highlight, and Fold.
- All controls remain enabled while a tab is active, including while Mode is Off.
- All controls are disabled when no tab is active.

Synchronize the controls from the active tab without feeding signals back into it. Changes target only the active tab.

Route every active-editable-track replacement through the centralized selected-track transition. This includes explicit selection and fallback after deletion or model updates, but excludes a pure index remap that preserves track identity.

On a real selected-track change:

- Fold becomes Highlight.
- Root and Scale remain unchanged.
- Off and Highlight remain unchanged.
- Returning to a previous track does not restore Fold.

Extend `--check-mainwindow-routing` to cover two tabs with different Root, Scale, and Mode values, selected-track replacement through both direct selection and deletion/fallback, Fold → Highlight, pure index remapping, and preservation of an inactive tab's state.

Do not touch any persistence codec or load/save path.

### Wave 5 — Highlight rendering

Render Highlight through the chromatic pitch layout:

1. Paint the existing lane background.
2. Apply `#b595fc` at 50% over every scale-pitch lane.
3. Paint grid and octave lines.
4. Paint ghost notes, active notes, previews, and overlays as today.

Do not tint:

- Piano keyboard keys
- Note faces
- Selection
- Sounding-key feedback

Extend `--rollcheck` with pixel and behavior checks proving:

- C Major tints the correct pitch classes in every octave.
- Natural and accidental base differences remain visible below the tint.
- Root lanes receive no extra emphasis.
- Keyboard pixels remain unchanged.
- Ghost-note and active-note face pixels remain unchanged.
- Off remains equivalent to the existing rendering.

### Wave 6 — Fold occupancy and geometry

Derive a fixed 128-pitch occupancy set from every note in `SongViewModel` whose track is the selected track. Do not filter by viewport, mute, solo, selection, or playback state.

When folded:

- Iterate visible pitches rather than 0–127 in row and keyboard painting.
- Suppress notes whose pitch has no visible row.
- Keep ghost notes only when the selected-track layout exposes their pitch.
- Retain ordinary natural/accidental styling for every visible row.
- Show all scale pitches even when the selected track has no notes.

Centralize layout replacement in one operation that:

1. Captures the pitch nearest the viewport center and its screen position.
2. Rebuilds the projection.
3. Selects the same pitch or nearest visible pitch.
4. Restores its screen position and clamps to the new extent.
5. Invalidates the roll once.

If a layout-affecting model change arrives during a pointer gesture, mark the layout dirty and flush it after release or cancellation. Atomic edits outside a pointer gesture rebuild immediately.

Extend `--rollcheck` to cover:

- Selected-track occupancy across the complete timeline
- Exact-pitch exception rows
- Other-track ghosts not creating rows
- Exception rows remaining during a held gesture
- Rebuild after move, draw, paste, delete, undo, and redo
- Center-pitch anchoring when entering/leaving Fold, changing scale, and adding/removing exceptions

### Wave 7 — Fold editing

Route ordinary selected-track pitch editing through the pure diatonic resolver.

Keyboard behavior:

- Fold Up/Down requests ±1 scale degree.
- Fold octave commands remain ±12 semitones.
- Off and Highlight keep ±1-semitone Up/Down.
- Multi-track time-range transpose stays chromatic.

Drawing behavior:

- Drawing on a scale row behaves normally.
- Empty drawing on an exception row does nothing.
- Piano-key audition on an exception row remains available.

Drag behavior:

- The grabbed visible source pitch and pointer scale row determine the degree displacement.
- Zero vertical displacement retains an off-scale source pitch.
- On the first nonzero displacement from an off-scale source, enter the nearest scale pitch in the drag direction; only subsequent crossed scale rows add degrees.
- Exception rows do not count as steps or destinations.
- A pointer over an exception row resolves to the next scale pitch in the drag direction.
- Every distinct selected source pitch receives the collision-free destination for that displacement.
- Combined time-and-pitch drags commit through the generic batch document move.
- Preview and committed destinations come from the same resolved mapping.

Horizontal-only movement, resize, velocity editing, and selection remain pitch-neutral.

Extend `--rollcheck` to cover:

- Single-note scale-degree nudging
- Octave nudging
- Off/Highlight chromatic nudging
- Multi-note collision-free examples
- Repeated source pitches
- Off-scale source entry into the scale
- Exception-row drawing rejection
- Exception-row audition
- Drag preview matching the committed edit
- Horizontal-only movement preserving an exception pitch
- Atomic rejection at MIDI boundaries
- Fold layout rebuilding only after a pointer edit commits

## Source areas

| Concern | Source area |
|---|---|
| Catalog and pure diatonic resolver | New `src/porydaw_scale.h/.cpp` |
| Pure visible-pitch projection | New small pitch-layout module under `src/ui/` |
| Generic per-note destination edit | `src/core/songdocument.h/.cpp` |
| Runtime state, painting, geometry, gestures | `src/ui/songview.h/.cpp` |
| Root/Scale/Mode controls and tab synchronization | `src/mainwindow.h/.cpp` |
| Pure scale verification | New `src/scalecheck.cpp`, `src/main.cpp`, `tools/run_checks.sh` |
| Document edit verification | `src/editcheck.cpp` |
| Piano-roll verification | `src/rollcheck.cpp` |
| Tab-routing verification | `src/mainwindowroutingcheck.cpp` |
| Source registration | `CMakeLists.txt` |

Explicitly excluded source areas:

- `src/ui/viewsidecar.*`
- Persisted `SongView::ViewState`
- `SongCfg` and `midi.cfg`
- MIDI playback and device processing

## Verification

Run focused checks while implementing:

1. `--scalecheck`
2. `--editcheck`
3. `--rollcheck`
4. `--check-mainwindow-routing`

Then:

1. Build the normal application and check targets.
2. Run the complete existing `tools/run_checks.sh` once with its normal decomp fixture.
3. Run CTest, including the existing theme and editor-layout checks.
4. Launch the real application and perform the visual smoke scenario from `scale-mode-spec.md`.

The visual smoke must observe:

- Fixed 50% purple lane tint in Highlight
- No keyboard or note-face tint
- Scale plus exception rows in Fold
- Deferred exception-row removal after drag release
- Collision-free diatonic movement
- Fold → Highlight on selected-track change
- Independent open-tab state
- C Major and Off after closing and reopening

## Completion checks

Before declaring the implementation complete, confirm:

- No catalog behavior depends on combo index.
- No Ableton pitch-remapping table remains in the implementation.
- No Scale Mode field enters a persistence path.
- No piano-roll geometry path retains an independent fixed-128-row formula.
- Off behavior remains unchanged.
- All new document edits are undoable and deterministic.
- The feature matches every acceptance criterion in `scale-mode-spec.md`.

After the smoke test proves the behavior, update user-facing documentation and the changelog if required by the release workflow, then remove only scaffolding made obsolete by this implementation.