# Editor Selection Model Specification

## Status

Approved normative architectural and behavioral contract for the complete EditorSelectionModel cutover. Current application behavior and existing checks serve as regression evidence; if either conflicts with this specification, implementation stops and the discrepancy is explicitly resolved rather than silently changing the specification or behavior.

## Purpose

Porydaw currently keeps editor selection state and its invariants inside `SongView`. The timeline ruler, piano roll, track headers, event list, and editor drawer therefore coordinate through a broad `SongView` interface.

`EditorSelectionModel` extracts the canonical selection state into one concrete module. It provides the seam through which editor surfaces observe and change selection without depending on each other.

This extraction preserves behavior. It does not introduce a new selection feature or change editing semantics.

## Goals

- Establish one canonical owner for editor selection state.
- Preserve the existing relationship between the Primary Track, Track Scope, Note Selection, and Time Selection.
- Keep Note Selection and active Time Selection mutually exclusive.
- Let the ruler, piano roll, track headers, event list, and editor drawer share selection without direct surface-to-surface dependencies.
- Separate canonical selection from transient gestures and visual Selection Projections.
- Give callers and checks a small interface that does not expose `SongView` internals.
- Keep painting and pointer-event processing allocation-free on selection query paths.

## Non-goals

- Changing any selection gesture, shortcut, color, or undo behavior
- Moving song data or undo commands out of `SongDocument`
- Moving clipboard or time-range editing operations into the selection model
- Moving camera, grid, snapping, layout, hit testing, or painting into the selection model
- Reorganizing `src/ui/editordrawer/`
- Creating an abstract selection interface or interchangeable adapters
- Persisting selection in project files or view sidecars
- Sharing selection between open song tabs

## Terminology

- **Primary Track** — the active editable track. A Note Selection is interpreted only on this track.
- **Track Scope** — the non-empty set of engine tracks selected through the track headers. It always contains the Primary Track.
- **Note Selection** — an ordered set of opaque `NoteId` values on the Primary Track.
- **Time Selection** — a half-open musical interval `[startTick, endTick)` with either Track Scope or Lane Scope.
- **Lane Scope** — the explicit automation-lane identities covered by a lane-scoped Time Selection. A lane identity is `(track, controller)`; track `-1` identifies the tempo lane.
- **Selection Projection** — a surface-specific visual interpretation of canonical selection, such as selection rings around notes overlapping a Time Selection.
- **Transient selection preview** — gesture-local state that has not yet become canonical selection, such as the piano roll's note rubber band before release.

## Ownership and seam

```text
SongSession
  └─ owns SongView lifetime
       ├─ owns EditorSelectionModel
       ├─ owns TimeRuler
       ├─ owns PianoRoll / EventListView
       ├─ owns TrackHeaderPanel
       └─ owns EditorDrawer

SongDocument
  └─ owns musical data, document revision, edits, and undo
```

`SongView` remains the Qt composition widget and owns one `EditorSelectionModel` for its lifetime. Its child surfaces may retain non-owning references to that model because they cannot outlive `SongView`.

The selection model may use `NoteId` and `TrackRemap`, but it must not retain a `SongDocument`, `MidiTimeline`, `SongViewModel`, or widget pointer. Callers supply the small pieces of current context needed for reconciliation and scope queries.
Used-track context crosses the seam only as an allocation-free `uint32_t` mask value. Do not introduce a generic context object, and do not give a surface an extra `SongView`, `MidiTimeline`, or `SongDocument` pointer merely to answer model coverage queries.

### Coordination seam: three interfaces

The cutover leaves exactly three selection interfaces; any fourth that merely re-exposes selection is prohibited.

1. **`EditorSelectionModel` — canonical state and invariants.** Owns the four canonical fields, enforces sanitization and mutual exclusion, and exposes the direct state interface: the queries and mutations in "Required model capabilities". Every direct getter, mutator, and coverage query lives here and nowhere else.

2. **Deep `SongView` coordination commands.** `SongView` retains only application-facing commands that perform required non-selection orchestration around a canonical mutation. A retained command is not a forwarding shim: it cancels interactions and popup state *before* the model mutation, delegates the atomic transition or scope mutation to `EditorSelectionModel`, then lets the private notification coordinator apply post-mutation side effects. A `SongView` method that merely calls the model is removed, not retained.

3. **Private `SongView` notification coordinator.** `SongView` keeps a private composition observer that maps one consolidated post-invariant model notification to widget refresh, focus, projection rebuild, header sync, and application signals such as `selectedTrackChanged` (see "Notification contract").

Thin pass-throughs remain prohibited: after cutover `SongView` stores no canonical selection state and exposes no selection getters, setters, or coverage queries.

## Canonical state

### Primary Track

The Primary Track is an engine-track index in `[0, 15]`.

A new song chooses its first used track. If no track is used, it uses track `0`, matching current `SongView` behavior.

### Track Scope

Track Scope is represented as a 16-bit subset held in a `uint32_t`. Assignment masks away bits outside tracks `0` through `15`, adds the Primary Track, and repairs an otherwise empty result to the Primary Track alone.

The stored scope therefore always contains the Primary Track and cannot be empty. Operations and Selection Projections resolve it against a caller-provided used-track mask when they require used tracks.

A track-scoped Time Selection stores only that it uses Track Scope. It does not snapshot the current mask. Header Ctrl/Shift changes therefore re-scope an existing Time Selection immediately.

### Note Selection

Note Selection is an insertion-order-preserving sequence of opaque `NoteId` values.

When Note Selection is assigned:

- Unassigned IDs are removed.
- Duplicate IDs are removed, preserving the first occurrence.
- A non-empty result clears an active Time Selection.
- An empty result does not clear a Time Selection.

Mutual exclusion is evaluated after this sanitization. A list containing only unassigned IDs therefore becomes empty and preserves Time Selection.

A `NoteId` is selected only when it resolves to a note on the current Primary Track. Geometry, tick, key, and vector position are never identity substitutes.

After a document rebuild, reconciliation removes IDs that no longer resolve to projected notes on the Primary Track. Reconciliation preserves the order of surviving IDs.

### Time Selection

A Time Selection contains:

- `startTick`
- `endTick`
- scope kind: Tracks or Lanes
- explicit lane identities when the kind is Lanes

It is active exactly when `endTick > startTick`. Its interval is half-open: it contains tick `t` when `startTick <= t && t < endTick`.

When Time Selection is assigned:

- An active result clears Note Selection.
- An inactive result does not clear Note Selection.
- Track scope remains live through the model's current Track Scope.
- Lane scope retains its explicit lane identities.

An active lane-scoped selection must contain at least one lane identity. Assignment removes duplicate lane identities while preserving their first occurrence; an active lane-scoped value with no remaining lanes is canonicalized to an inactive empty Time Selection. Remapping applies the same rule.

### Mutual exclusion

The following state is forbidden:

```text
non-empty Note Selection AND active Time Selection
```

The model establishes this invariant after assignment sanitization and before notifying observers. Callers never need to clear one selection kind before assigning the other.

Track Scope is independent of this exclusivity rule and exists even when neither Note Selection nor Time Selection is active.

## Required model capabilities

The concrete interface must provide these capabilities. Exact C++ spelling may follow repository conventions, but callers must not need additional selection state from `SongView`.

### Queries

- Read the Primary Track.
- Read the stored Track Scope without allocation.
- Resolve Track Scope against a caller-provided used-track mask.
- Read Note Selection by const reference or equivalent non-owning view.
- Test whether a `NoteId` is selected without allocation.
- Read Time Selection by const reference.
- Test whether a track is covered by Time Selection using a caller-provided used-track mask.
- Test whether a lane identity is covered by Time Selection using a caller-provided used-track mask.

### Mutations

- Replace Note Selection.
- Clear Note Selection.
- Replace Time Selection.
- Clear Time Selection.
- Clear both selection kinds.
- Apply a real Primary Track transition.
- Apply Track Scope adjustments from a clicked track, caller-provided used-track mask, and model-owned `enum class TrackScopeAction { Plain, Toggle, Range }`, including atomic Primary Track handoff when required. Header controllers translate `Qt::KeyboardModifiers` into this typed intent; the model does not accept Qt event or modifier types.
- Reconcile Note Selection against caller-provided valid IDs.
- Reset for a song swap.
- Clear Note Selection for a document attachment, including reattachment of the same document.
- Apply a `TrackRemap`.

The model must not expose mutable references to its stored containers.

## Transition semantics

### Real Primary Track transition

Selecting a different logical track:

1. Changes Primary Track.
2. Collapses Track Scope to that track.
3. Clears Note Selection.
4. Clears Time Selection.

The `selectTrack` / `transitionSelectedTrack` path remains a deep `SongView` coordination command. It cancels interactions and popup state **before** delegating this canonical transition to `EditorSelectionModel` — the post-invariant model notification is too late for pre-mutation cleanup — and the private notification coordinator then applies header sync, focus, scale projection rebuild, refresh, and `selectedTrackChanged`.

### Header scope adjustment

Track-header modifier gestures alter Track Scope without clearing Time Selection:

- Ctrl toggles the clicked track.
- The scope cannot become empty.
- If Ctrl removes the Primary Track, the model assigns the lowest remaining scoped track as Primary Track in the same atomic mutation.
- That handoff clears Note Selection but preserves Time Selection, matching the current save/transition/restore behavior.
- Shift selects the used tracks in the inclusive range between the Primary Track and clicked track.
- Every scope adjustment immediately changes a track-scoped Time Selection's coverage.

`SongView` remains responsible for the existing interaction cancellation, focus, scale-projection, header, and `selectedTrackChanged` side effects of a Primary Track handoff. Interaction and popup cancellation happen before the model mutation, because the post-invariant notification is too late for pre-mutation cleanup. No observer may see the intermediate cleared Time Selection used by the current implementation; the model's atomic handoff replaces that save/transition/restore sequence.

A plain click on a different track performs a real Primary Track transition. A plain click on the current Primary Track collapses Track Scope and clears Note Selection, but preserves Time Selection.

### Song swap

Attaching a different song:

- Resets Primary Track to the first used track, or track `0` when none is used.
- Collapses Track Scope to Primary Track.
- Clears Note Selection.
- Clears Time Selection.

Clipboard, mute/solo, camera, scale, drawer, and playhead resets remain outside this model.

### Document attachment

Every `setDocument` call clears Note Selection, including reattachment of the same pointer. It preserves Time Selection. Only song swap, an applicable track transition, or an explicit selection mutation clears Time Selection.

### Document rebuild

After rebuilding `SongViewModel` from the current document:

- If Primary Track is no longer used, `SongView` chooses its fallback track through a real Primary Track transition.
- Otherwise, the model reconciles Note Selection against valid `NoteId` values projected on Primary Track.
- Tick-addressed Time Selection survives the rebuild.

This applies to edits, undo, and redo.

### Track remap

A `TrackRemap` updates selection atomically before observers read it:

- Primary Track follows its logical track when it survives.
- Track Scope bits follow surviving logical tracks and continue to contain Primary Track.
- If Primary Track is deleted, fallback clamps its old index to `min(oldPrimaryTrack, max(0, newEngineTrackCount - 1))`; the later document rebuild still performs its separate first-used-track fallback when necessary.
- Deleting Primary Track clears a track-scoped Time Selection.
- Lane identities follow remapped tracks.
- Global lane identities such as tempo (`track == -1`) remain unchanged.
- Lane identities whose tracks were deleted are removed.
- A lane-scoped Time Selection is cleared if no lane identities remain.
- Note IDs are retained through remap and reconciled against the rebuilt projection afterward.

`SongView` executes the remap in a fixed order so every selection notification and refresh sees complete external and canonical state:

1. Compute all remapped values into locals — the mapped Primary Track, Track Scope, mute/solo masks, lane identities, and clipboard track/lane addresses — from the caller-provided `TrackRemap`.
2. Commit SongView-owned remapped state (clipboard, mute/solo, and cosmetic `EditorViewState` lane state) without refresh or signals.
3. Invoke the model's notifying `TrackRemap`; the resulting notification runs the private coordinator against the fully committed batch, including selection-driven refreshes and `selectedTrackChanged`.
4. Publish the remaining non-selection application signals — `muteMaskChanged`, `soloMaskChanged`, and any `editorDrawerStateChanged`.

An emitting helper such as `setEditorViewState` must not run before the whole batch is committed, or a refresh can observe half-remapped cosmetic state. No observer sees mixed old/new canonical selection or a refresh against half-remapped view state.

Clipboard track remapping computation remains outside the model.

## Coverage and Selection Projections

### Track coverage

For a track-scoped Time Selection:

```text
covered tracks = Track Scope ∩ used tracks
```

A normal automation lane is covered when its track is covered.

The global tempo lane is covered by Track Scope only when at least one track is used and every used track is covered. A lane-scoped Time Selection covers tempo only when `(-1, DOC_CC_TEMPO)` is explicitly present.

### Note projection

A note is projected as time-selected when:

1. Time Selection is active and track-scoped.
2. The note's track is covered.
3. Its interval overlaps the Time Selection:

```text
note.startTick < selection.endTick
&& selection.startTick < note.endTick
```

This projection includes ghost notes on other covered tracks. It draws the existing selection treatment but does not add those notes to Note Selection.

An explicit Note Selection projects only onto matching `NoteId` values on Primary Track.

### Automation projection

A lane is projected as selected when its lane identity is covered. Automation nodes use the half-open interval rule: a node at `endTick` is not selected.

`AutomationRows` may cache row indices derived from explicit lane identities for layout and painting. That cache is a projection, not canonical selection.

### Range bands

The ruler, piano roll, and automation area derive selection bands and edge handles from the same Time Selection ticks. Each surface owns tick-to-pixel conversion and painting.

## Canonical selection versus interaction state

The model owns selection that other surfaces must observe immediately.

Interaction controllers continue to own transient state such as:

- Pointer-down position
- Drag mode and edge being dragged
- Rubber-band rectangle
- Original values captured for a gesture
- Provisional automation row range
- Audition membership

The piano roll's note rubber band remains provisional until release; it must not populate Note Selection during the drag. Its temporary selection rings remain a painter projection of gesture state.

Ruler and time-range gestures that currently update cross-surface bands live may update Time Selection during the drag. Cancellation must restore or clear the canonical value according to existing behavior.

## Notification contract

The model publishes at most one post-invariant change notification for each public mutation. After input sanitization, a mutation that produces state equal to the current state publishes no notification. Any changed state publishes one notification identifying all affected categories:

- Primary Track
- Track Scope
- Note Selection
- Time Selection

Mutual-exclusion clearing, song reset, Primary Track handoff, and track remap report their complete combined category set. Observers query the completed state after notification; notifications do not carry copied note or lane containers.

Observers must not mutate the model synchronously from a change notification. A response that needs another selection mutation must be scheduled after notification delivery. This prevents reentrant mutation from exposing partial transitions or producing nested notifications.

Selection queries and notifications run on the UI thread. Predicate queries used by painting and pointer movement—selection membership, resolved Track Scope, and track/lane coverage—must not allocate. Non-owning container views are invalidated by the next model mutation.

`SongView` remains the private composition observer: it translates one consolidated post-invariant model notification into its existing targeted widget refresh, focus, and application signals. This is notification coordination, not a selection forwarding interface — after cutover `SongView` stores no canonical selection and exposes no selection pass-through getters or mutators. Extracted surfaces may later subscribe directly, but direct subscription is not required for the first cutover.

## Responsibilities outside the model

| Responsibility | Owner |
|---|---|
| Musical notes, lanes, tempo, and document revisions | `SongDocument` |
| Undoable note and range mutations | `SongDocument` commands |
| Clipboard contents and paste semantics | Range-editing module or temporary `SongView` facade |
| Mouse and keyboard gesture interpretation | Surface interaction controllers |
| Tick/pixel geometry and hit testing | Surface layout modules |
| Painting selection rings, bands, and headers | Surface painters |
| Status text and audition signals | `SongView`/surface coordination |
| Widget refresh and focus | `SongView` and child widgets |
| Per-tab view lifetime | `SongSession` and `SongView` |

## Migration constraints

- Move all four canonical fields together: Primary Track, Track Scope, Note Selection, and Time Selection. Leaving one in `SongView` creates two sources of truth.
- Preserve temporary `SongView` forwarding methods only during the atomic caller migration; remove them once every caller uses the model seam.
- Do not give extracted surfaces a generic context object or a broad replacement for `SongView*`.
- The existing editor drawer remains structurally unchanged. Only replace its selection access path.
- Preserve the two-phase lifecycle: `tracksRemapped` first atomically remaps Primary Track, Track Scope, and lane identities; the following document rebuild then reconciles Note Selection against the rebuilt projection.
- Do not combine this extraction with painting, interaction, camera, grid, or range-editing refactors.

## Acceptance matrix

| Contract | Required evidence |
|---|---|
| Note IDs are sanitized, deduplicated, retained by identity, and pruned after rebuild | `selectioncheck`; `rollcheck` |
| Note Selection and active Time Selection are mutually exclusive in one atomic transition | `selectioncheck`; `rollcheck`; `rollcheckautomation` |
| Ruler and roll time gestures share one half-open Time Selection | `rollcheck` |
| Track Scope changes re-scope active Time Selection live | `selectioncheck`; `rollcheck` |
| Covered ghost notes receive the time-selection projection without entering Note Selection | `rollcheck` |
| Lane Scope selects only explicit automation lanes and excludes `endTick` | `rollcheckautomation` |
| Tempo coverage retains the all-used-tracks rule | `selectioncheck`; `rollcheckautomation` |
| Velocity drawer and piano roll observe the same Note Selection | `rollcheckpsgvelocity`; `hostcheck` |
| Event list and track headers observe the same Primary Track and Track Scope | `eventviewcheck`; `rollcheck` |
| Song swap, document attachment, rebuild, and track remap preserve the specified lifecycle | `selectioncheck`; `rollcheck`; `mainwindowroutingcheck` |
| Gesture cancellation never commits a provisional selection | `rollcheck`; `hostcheck`; `mainwindowroutingcheck` |
| Range edits, undo/redo, and key commands retain existing behavior | `editcheck`; `rollcheck`; `rollcheckautomation`; `keymapcheck` |
| Pitch-bend popup continues to anchor by selected `NoteId` | `pitchbendcheck` |
| Selection queries allocate no memory in paint and pointer-move paths | Focused code review and existing rendering smoke checks |

### Dispatch map

The acceptance matrix references check families by harness name. Each family resolves through the current CLI dispatch in `src/main.cpp`:

| Check family | Current CLI dispatch |
|---|---|
| `selectioncheck` | `--selectioncheck` (new flag added by this cutover) |
| `rollcheck` | `--rollcheck` |
| `rollcheckautomation` | `--check-automation` |
| `rollcheckpsgvelocity` | `--check-velocity-page` |
| `hostcheck` | `--check-host-adapter`, `--check-host-seams` |
| `eventviewcheck` | `--eventviewcheck` |
| `mainwindowroutingcheck` | `--check-mainwindow-routing`, `--check-host-integration` |
| `editcheck` | `--editcheck` |
| `keymapcheck` | `--keymapcheck` |
| `pitchbendcheck` | embedded in `--rollcheck` through `runPitchBendCheck`; no standalone flag |

`tools/run_checks.sh` is broad regression evidence but does not run every specialized `--check-*` harness (for example `--check-automation`, `--check-velocity-page`, `--check-host-adapter`, `--check-host-seams`, `--check-mainwindow-routing`, `--check-host-integration`). It cannot substitute for the explicit runs named above.

The focused selection check must test the model through its public interface rather than reading private fields or source text.

## Current-source evidence

The extraction must preserve behavior currently implemented by these symbols:

- `SongView::setSelection`, `clearSelection`, `setTimeSelection`, and `clearTimeSelection`
- `SongView::trackSelectionMask`, `trackHeaderClicked`, and `transitionSelectedTrack`
- `SongView::setSong`, `setDocument`, `updateSong`, and `onTracksRemapped`
- `SongView::isSelected`, `timeSelectionCoversTrack`, and `timeSelectionCoversLane`
- The `TimeRuler` and `PianoRoll` implementations in `src/ui/songview.cpp`
- `AutomationPage`, `AutomationRows`, and `AutomationArea` in `src/ui/editordrawer/`
- `VelocityArea` in `src/ui/editordrawer/`
- `EventListView` in `src/ui/eventlistview.*`

Existing behavior checks live under `src/checks/`. They remain the integration contract while the new focused model check defends the extracted interface directly.
