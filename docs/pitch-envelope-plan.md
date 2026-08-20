# Track-Wide Pitch Envelope Editor Plan

## Status and authority

This document records the pitch-envelope design discussed so far and maps it onto the current porydaw implementation. The compact normative behavior matrix below is the implementation contract; **Where we are** is the living tracker for implementation and later design reversals. The remaining sections provide rationale, evidence, and sequencing.

The matrix, **Agreed contract**, and **Where we are** are authoritative together. If an older paragraph below disagrees with **Where we are** or the matrix, the later decision wins. Implementers must follow those sections rather than infer a different persistence model, endpoint policy, authoring domain, or editor placement.

### Normative behavior matrix

| Concern | Selected behavior |
| --- | --- |
| Timing | **Authoring (agreed, not implemented):** one fixed note-relative tick window `0 … windowTicks` (`windowTicks` not chosen yet). Graph *x* is an offset tick; `eventTick = noteStartTick + offsetTick`. Tempo and time-signature conversions leave the editor. Milliseconds are optional display only. **Playback:** generated 1/64-note samples plus M4A bend quantization. Playback granularity must not constrain pointer placement. **Current code:** still Alternative A's local 0–100 ms template, compiled through the tempo map at each eligible note-on. |
| Authoring scope | The selected track owns one template. No note pick is required; a gesture applies it to every eligible note currently on that track. |
| Endpoints and reset | Each projected interval starts at zero and explicitly resets to zero at the authoring-window end or the next distinct note-on, whichever comes first. A note-off never clips the interval. Current code uses 100 ms as that window end. |
| Vertical scale | Convert the same relative-pitch template through the `BENDR` active at each eligible note-on. |
| Editor visibility | Only the selected track's envelope editor may be open at a time. |
| Editor placement | The host belongs around the track headers. The user opens it with the header P button. The graph fits in the header column (`trackHeaderWidth` = `fontPx(17.5)`). **Rejected:** `EditorDrawer` / velocity-pane overlay. |
| Program changes | Show one stable header toggle whenever the selected track contains an eligible note. It remains authorable across cursor and playhead program changes; the effective voice only decides which note-ons receive a projection. |
| Storage and manual lane ownership | Ordinary `DOC_CC_BEND` events are the sole persistence representation. There is no sidecar, persistent template artifact, or generated-versus-manual ownership split; manual edits to that lane remain authoritative. Explicit user-entered ticks must survive compilation alongside generated 1/64 samples. No custom embedded metadata is required for integer-tick handles. |
| Playback semantics | The bend is track-wide and never polyphonic: every active note on the engine track hears the same bend. |

The matrix originally resolved strict millisecond timing to creation-time-only 100 ms because no persistence format was selected. Tick-native authoring later replaced milliseconds as the editor domain; Alternative A's ordinary-`DOC_CC_BEND` commit path remains.

## Agreed contract

The feature is a track-wide pitch-envelope editor for GBA PSG melodic voices.

- Each track header provides a button that shows or hides the selected track's pitch-envelope editor.
- The editor sits around the track headers. The graph fits in the header column width. It is not part of `EditorDrawer` and does not overlay the velocity pane.
- The agreed authoring domain is a fixed local tick window `0 … windowTicks` (value not chosen). Current code still uses 0–100 ms.
- A completed gesture projects that template onto every eligible note currently on the selected track. Notes added later receive no retroactive projection; edit the envelope again to apply it to them.
- Program changes determine eligibility at each note-on. Any later note-on, eligible or not, clips and resets the preceding projection.
- Noise and sampled voices are out of scope.
- The editor is an editable vector graph made of points.
- The graph editor shares its implementation with the graph widgets in the existing pitch-bend popup (`EditableCurveGraph`).
- Pitch envelopes ultimately drive ordinary track-wide pitch bend. They are not polyphonic per-note expression: every active note on the engine track hears the same bend.

## Where we are (2026-08-20)

### Implemented

- Shared `EditableCurveGraph` in `src/ui/curvegraph/`. Pitch-bend popup and envelope host use it. No second graph engine.
- Header P button on `TrackHeaderRow`. Canonical open-state lives in `SongView` / `PitchEnvelopeUiState`, not in the ephemeral row. Survives header rebuild. Only the selected track may be open.
- `voiceSupportsPitchEnvelope` is the single eligibility helper.
- `PitchEnvelopeHost` exists with: linear painting and `valueAtX()`, interior-point single-click deletion, drag threshold, fixed-zero envelope endpoints, envelope grid, 8 px zero detent, 1/64 persistence independent of the coarse visible grid.
- Expanded pitch-envelope checks. Incremental build and `deno task checks build/porydaw_checks` passed after the drawer overlay.

### Core breakthroughs

1. The two editors already share one graph. Painting and gestures live in `EditableCurveGraph`. Divergence is configuration and host persistence, not duplicated widgets. No fork.
2. Node displacement cause. Current envelope path:
   `pixel → milliseconds → tick → grid-snapped tick → milliseconds → 1/64 resampling → reload generated events as nodes`.
   The click's original position is discarded twice: grid snap and compilation.
3. Custom embedded metadata is not required. Standard MIDI pitch-bend events already exist at arbitrary integer MIDI ticks. Preserve explicit user-entered ticks alongside generated 1/64 samples. Metadata would only be necessary if sparse authored handles must stay distinguishable from generated samples, or if sub-tick persistence is required.
4. Authoring and playback precision are separate:
   - Authoring: any MIDI tick in the envelope window
   - Curve: continuous linear interpolation
   - Playback: generated 1/64 samples and M4A bend quantization
   Machine playback granularity must not constrain pointer placement.
5. The authoring domain should be ticks, not elapsed milliseconds. Fixed note-relative window `0 … windowTicks`. Projection: `eventTick = noteStartTick + offsetTick`. Tempo and time-signature conversions leave editing. Milliseconds become optional display information only.
6. Explicit points must survive compilation. Compilation should union user-entered ticks, 1/64 sampling boundaries, and projection start/reset ticks. Effective-bend deduplication may collapse generated samples but must never remove explicit user ticks.
7. **Superseded:** "Move `PitchEnvelopeHost` into `EditorDrawer` as an overlay over `VelocityArea`." That move was implemented and then rejected. Do not invent a sizing system from the velocity pane.

`windowTicks` is not selected. Tick-native authoring is agreed and not implemented. The host still uses 0–100 ms.

### Placement reversal (EditorDrawer)

The envelope host was moved into `EditorDrawer` as an exclusive overlay on `VelocityArea` (same rect, resize handle, drawer-height rules; opening envelope force-showed the velocity section). Thermo-nuclear review of that overlay:

- Layer inversion: generic `DrawerSections` / `EditorDrawer` depend on `songview::PitchEnvelopeHost`.
- Scattered `envelopeOpen` branches in focus, cancel, arrange, occupied region, and `canvasFor`.
- Dual-state: `EditorViewState.velocity.visible` vs host `m_open`, pumped by `syncLayout()`.
- Nullable guards around an always-present host, plus a silent `setParent` reparent.
- `isOpen()` vs `isHidden()` disagree between focus and canvas routing.

**Decision:** `EditorDrawer` was the wrong place. Next placement work unwinds that overlay and keeps the host around the track headers.

### Header placement and Qt affordances

The graph fits in `trackHeaderWidth` (`fontPx(17.5)`). Do not treat the header column as too narrow.

Open from the header P button. Latch on P (toggle); Esc/P closes. Do not copy `PitchBendEditor`'s `PitchBendCloseController` click-outside dismiss — envelope is track-scoped and longer-lived.

Do not use `Qt::Popup` (sample-picker auto-close + mouse grab) or `QDockWidget` (MainWindow-scoped; envelope is per-tab, per-track).

| Option | Qt | Notes |
| --- | --- | --- |
| In-header widget | Child of `TrackHeaderRow` / `TrackHeaderPanel` | Graph uses the header column width. Follows v-scroll and rebuild. |
| Anchored child overlay | `QFrame`/`QWidget` child of `SongView` or `songView->window()`, no special flags | Same host pattern as `PitchBendEditor`, latched on P. Can sit in or beside the header. |
| `Qt::Tool` floater | `Qt::Tool` or `Qt::Tool \| Qt::FramelessWindowHint` | Draggable off the roll. Does not follow the P-row unless wired. Allowed, not required. |
| Lane overlay | Child of `rollPane` / `PianoRoll` | Flush with the header; covers that track's notes. |

### Remaining

- Choose `windowTicks`.
- Tick-native graph domain; stop the millisecond round-trip that discards click position.
- Compilation unions explicit user ticks with 1/64 samples and must not drop explicit ticks.
- Unwind the `EditorDrawer` overlay; put the host around the track headers.
- Size the graph from the header column, not from velocity/`EditorDrawer`.

## Explicit non-goals

Do not add:

- A preset or articulation palette
- A special Square voice type
- Native Square 1 hardware-sweep realization or NR10 parameter search
- MPE, automatic track splitting, or independent pitch for overlapping notes
- Pitch envelopes for Noise or sampled voices
- Bézier editing in the first implementation
- An unrelated reorganization of `SongView`, `SongDocument`, or the automation drawer

Square 1 hardware sweep remains an independent voice parameter. It does not provide the pitch resolution or arbitrary point control required by this editor.

## Terminology

**Pitch envelope** — the selected track's bounded local point template, realized as ordinary track-wide pitch bends.

**Template source** — a deterministic existing eligible projection used to reconstruct the graph, preferring an unclipped projection. It is a display source, not note-scoped authoring state.

**Authoring window** — the template's fixed local horizontal domain. Agreed: `0 … windowTicks` (value not chosen). Current code: 0–100 ms.

**Playable projection** — ordinary SMF pitch-bend events (`0xE`) written for one eligible note-on, ending at the authoring-window end or the next note-on.

**Eligible voice** — a voice whose masked CGB type is Square 1, Square 2, or programmable wave.

The repository's “mid2agb clock” is not the envelope's authoring unit. `SongDocument::ticksPerClock()` describes the build grid at 24 or 48 clocks per beat. Authoring uses MIDI ticks in the local window; playback samples at 1/64-note. Do not design the UI around extended `-X` 48-clock mode.

## Current implementation evidence

### Pitch-bend document and playback path

- `DOC_CC_BEND` in `src/core/songdocument.h` is the pseudo-controller for SMF pitch-bend events (`0xE`).
- `SongDocument::writeLanePoints(...)` in `src/core/songdocument.{h,cpp}` replaces a bounded stream of lane points as one undoable edit.
- `MidiTimeline::build(...)` in `src/core/miditimeline.cpp` projects the editable SMF into sample-positioned events.
- `TimelinePlayer` in `src/core/timelineplayer.cpp` dispatches pitch bend to the M4A engine and chases the current value when playback seeks.

The runtime and export vocabulary therefore already support the playable result. The remaining work is the authoring representation and editor implementation, not a new engine command.

### Existing graph implementation

**Current:** `EditableCurveGraph` in `src/ui/curvegraph/` is the shared widget. `PitchBendEditor` and `PitchEnvelopeHost` both host it. Wave 1 is done.

Historical note (why Wave 1 existed): `PitchBendEditor` originally created two `PitchBendGraph` children with tick/lane-specific state. That file was already above the 600-line ceiling, so the shared behavior was extracted rather than branched. Hosts own conversion between graph coordinates and domain values; the graph owns painting, gestures, selection, keyboard, and preview.

### Track header

**Current:** `TrackHeaderRow` lives in `src/ui/songview/trackheaderrow.{h,cpp}`. It owns Mute, Solo, and the pitch-envelope `QToolButton`. Canonical envelope visibility is `SongView` / `PitchEnvelopeUiState`, not the row. Header rebuild restores the checked state.

`SongView::currentProgram(int)` resolves the effective program at the playhead while playing and at the edit cursor while stopped. `SongView::voiceContext(uint64_t)` resolves a `ToneData` and the next program-change boundary at an explicit tick. `m4aVoiceTypeName(...)` in `src/ui/m4asemantics.cpp` already masks CGB voice types and distinguishes Square 1, Square 2, Wave, Noise, and Sample.

Eligibility must be derived from the effective `ToneData::type`, including alternate Square/Wave encodings through `VOICE_TYPE_CGB_MASK`; it must not be inferred from translated display text.

### Timing

The editable SMF stores event positions in ticks. `MidiTimeline` exposes a tempo map plus `sampleForTick(...)` and `tickForSample(...)`, so porydaw can project between song position and elapsed time.

An initially requested strict millisecond invariant would require persistent millisecond-domain authoring data and regeneration of the playable projection. Because no tracked persistence format or verified in-SMF metadata encoding was selected, that invariant is deliberately not used: the selected creation-time-only 100 ms window writes ordinary bend points immediately, and later tempo edits may stretch or shrink its elapsed duration.

### Sidecars

`src/project/sidecar.h` defines `.porydaw/` as ignored, per-user state that never belongs in the repository. The selected plan does not store musical envelope intent there or in another strict millisecond-domain artifact. Alternative B would have required either a tracked song artifact or a verified in-SMF metadata encoding.

## Proposed module design

### Shared editable-curve module

Create one shared editable-curve module behind a neutral interface. Both the existing popup and the new envelope editor cross the same seam.

Illustrative interface:

```cpp
struct CurvePoint {
    double x;
    double y;
};

struct CurveSpec {
    double minimumX;
    double maximumX;
    double minimumY;
    double maximumY;
    double defaultY;
    // Axis formatting and snapping policy supplied by the host.
};

class EditableCurveGraph final : public QWidget {
  public:
    void setSpec(CurveSpec spec);
    void setPoints(std::vector<CurvePoint> points);
    const std::vector<CurvePoint> &points() const;
    void setCallbacks(CurveCallbacks callbacks);
};
```

The exact types may change during implementation, but the interface must preserve these properties:

- The graph edits ordered points without knowing `SongDocument`, controller numbers, voice types, or persistence.
- Hosts own conversion between graph coordinates and domain values.
- The graph owns painting, point gestures, selection, keyboard behavior, and gesture preview.
- Snapping and labels are explicit policies, not branches on a growing lane enum.
- The existing pitch/modulation popup retains its present observable behavior through a tick/value adapter.
- The pitch-envelope host uses a local millisecond horizontal domain and a relative-pitch vertical domain.

Do not introduce an inheritance hierarchy. There are two concrete hosts and one shared graph implementation; callbacks and value policies are sufficient.

Because `src/ui/pitchbendgraph.cpp` is already above the repository's 600-line ceiling, do not add the new mode as another branch inside that file. Extract the shared behavior into a focused source/header pair and leave the popup-specific adapter small. File placement should follow the existing `src/ui/editordrawer/` one-concept pattern; moving the existing pitch-bend files into a folder is acceptable only if it reduces the feature's total navigation cost and is done as one clean cutover.

### Pitch-envelope host

Add a host responsible for:

- The selected engine track and deterministic template source
- The fixed 0–100 ms graph domain
- Relative-pitch bounds and formatting
- Loading the template from ordinary bends
- Previewing the playable projections
- Committing one undoable track-wide edit
- Restoring focus and handling document/header rebuilds

The first implementation uses points joined by straight lines. Reuse the existing point insertion, drag, deletion, line, cancel, and keyboard mechanics. Do not add Bézier handles.

The vertical axis should display musical relative pitch rather than raw 14-bit MIDI numbers. Conversion through the effective BENDR value belongs outside the shared graph. Use the active `BENDR` range and continuously adjust the displayed/editable vertical range when that active range changes.

### Track-header toggle

Add a checkable pitch-envelope button to `TrackHeaderRow`.

The button widget publishes intent; it does not own canonical visibility state. Store the state in the `SongView`/per-tab UI model so header reconstruction restores the checked state. Only the selected track's envelope editor may be open at a time; changing track selection closes the previously open editor.

Eligibility must use a single helper over `ToneData::type`:

```cpp
bool voiceSupportsPitchEnvelope(uint8_t type);
```

The helper accepts masked Square 1, Square 2, and programmable-wave types and rejects Noise, keysplit/drumkit, and sampled voices. UI code and checks must call this helper instead of duplicating type tests.

#### Program changes

Track-wide authoring and per-note eligibility are different concerns. A track can contain program changes between eligible and ineligible voices. The current `currentProgram()` follows the playhead during playback, which must not make an editing control appear, disappear, or become disabled.

Selected behavior:

- Show the stable button whenever the selected track contains at least one eligible note.
- Keep the toggle and open editor enabled across cursor and playhead program changes.
- Resolve the effective voice and `BENDR` at each note-on when the graph refreshes; snapshot those eligible projections for the gesture.
- Every later note-on clips the prior projection regardless of eligibility, so the bend resets deterministically.
- Existing bend data remains visible; atomically rewrite only the disjoint projected intervals so every event outside them survives untouched.

This behavior is settled by the normative matrix and must be implemented without playhead-driven flicker.

## Timing and persistence alternatives (historical rationale)

The alternatives below preserve the historical tradeoff. **Alternative A is selected; Alternative B is unselected.** The initially requested strict millisecond invariant is deliberately resolved to creation-time-only behavior because no tracked persistence format or verified in-SMF metadata encoding was selected.

### Alternative A — local template, raw lane remains authoritative (SELECTED)

At envelope commit:

1. Read the fixed local 0–100 ms graph for the selected track.
2. Resolve every eligible note currently on that track, with its voice and `BENDR` at note-on.
3. Convert the template into ordinary bend points for each distinct note-on.
4. Clip each projection at the next distinct note-on, regardless of that later note's eligibility.
5. Commit the combined points through one `SongDocument::writeLanePoints(...)` edit while preserving bends outside each projected interval.

Consequences:

- No new musical storage format, note identity, sidecar, or second template artifact is required.
- Existing undo, raw-event editing, playback, seeking, save, export, and round-trip behavior remain authoritative.
- The template's elapsed duration changes if the tempo map is edited later.
- Reopening the editor reconstructs its template from a deterministic eligible projection, preferring an unclipped one and padding unavailable tail with zero.
- Notes added after a commit require a later envelope edit before they receive a projection.
- The feature is a focused track-wide automation affordance rather than a second musical data model.

Alternative A is the selected design: “100 ms” means the initial drawing window, not a permanent elapsed-time guarantee.

### Alternative B — 100 ms remains invariant (UNSELECTED — historical alternative)

Persist each track template as millisecond-domain points. On playback/save/export, compile them through the current tempo map into ordinary pitch-bend events.

Consequences:

- Tempo changes can preserve an exact 100 ms envelope.
- Authoring intent and playable SMF events become separate representations.
- The implementation needs stable ownership, undo integration, stale-data handling, conflict behavior for manual edits in generated spans, and a tracked persistence format.
- Existing `.porydaw/` sidecars cannot be used.
- A tracked adjacent song file or a verified sequencer-specific SMF meta encoding is required.
- Playback and export must use the same compiler so they cannot disagree.

Alternative B is unselected under this plan and must not be implemented as part of this feature. It is retained only as rationale for the selected creation-time-only behavior; it would require an explicitly approved storage artifact and manual-lane ownership policy.

## Point and endpoint behavior

The initial graph behavior should be deliberately small:

- Ordered vector points
- Click to create a point
- Drag to move a point
- Delete/Backspace to remove a selected interior point
- Straight-line interpolation
- Default graph initialized at zero
- Explicit live pitch readout
- Fine vertical adjustment through the existing modifier convention

The endpoint contract is resolved as follows:

- The local graph has mandatory zero-valued start and 100 ms end points.
- Each eligible note-on writes a zero-valued start.
- Each projection explicitly resets to zero at its 100 ms end or the next distinct note-on, whichever comes first.
- A later ineligible note still clips and resets the preceding projection.
- A note-off does not clip a projection.

Because pitch bend is persistent track state, the reset must be explicitly represented in ordinary bend events. It must not silently imply that a curve ends when the engine will continue holding its last value.

## Track-wide projection semantics

The local template projects onto every eligible existing note-on on the selected engine track. Resolve eligibility and `BENDR` at each note-on so equivalent graph values produce equivalent semitone bends even when ranges differ. Same-tick eligible notes produce one projection. The next later note-on clips the prior projection regardless of its voice, and note-off does not clip it.

There is one authoritative ordinary lane. A commit atomically rewrites only the disjoint projected intervals, so all bends outside them survive untouched. Since no second representation exists, later-added notes are not backfilled; a later envelope edit projects the current template onto the then-current eligible notes.

## Undo, save, playback, and export

### Alternative A (SELECTED)

- Commit each completed graph gesture through one atomic multi-range lane-edit command.
- Preview may update the graph continuously, but it must not create an undo command per mouse move.
- Saving writes only the existing SMF pitch-bend events; reopening reconstructs from those events without a sidecar or template artifact.
- `MidiTimeline::build(...)`, `TimelinePlayer`, WAV export, and mid2agb continue to consume the ordinary events without a new runtime path.
- Event ordering and pitch-bend chase behavior remain the existing `SongDocument`/`MidiTimeline` contract.

### Alternative B (UNSELECTED — rationale only)

- Envelope mutation and regeneration must be one atomic undoable document operation.
- The compiler must be the only implementation of millisecond-to-tick sampling.
- Timeline playback, WAV rendering, MIDI save, and mid2agb export must receive the same projected event stream.
- Manual edits to a generated range need an explicit detach, reject, or replace policy; silent two-way synchronization is prohibited.

## Implementation sequence

The matrix and **Where we are** close the former decision gate. Alternative A's ordinary-`DOC_CC_BEND` commit path remains. Do not introduce Alternative B's strict millisecond artifact. Tick-native authoring and header placement are the remaining design/implementation work; do not put the host in `EditorDrawer`.

### Wave 1 — Shared graph cutover — DONE

`EditableCurveGraph` extracted. `PitchBendEditor` adapted. Existing pitch and modulation graphs remain.

### Wave 2 — Header toggle and eligibility — DONE

Header P button, `voiceSupportsPitchEnvelope`, per-tab `PitchEnvelopeUiState`, rebuild-safe checked state, program-change contract without playhead flicker.

### Wave 3 — Envelope host and mapping — PARTIAL

Host exists and commits through `writeLanePointRanges`. Still a 0–100 ms local template. Tick-native `0 … windowTicks` is agreed and not implemented. Compilation still resamples to 1/64 and reloads generated events as nodes, which discards click position and can drop explicit user ticks.

Do not keep the 100 ms graph domain. Do not add a second envelope store, sidecar, persistent template artifact, or runtime compiler.

### Wave 4 — Focused verification and wiring

Use a `task` agent for behavioral checks. Use a `sonic` agent only for mechanical build-list or check-dispatch wiring after test ownership is already defined.

Prefer extending the existing pitch-bend/roll harnesses over creating a second overlapping graph harness. Add a new check entry only if the track-header lifecycle and timing scenarios cannot be expressed cleanly through `pitchbendcheck` and `rollcheck`.

Required checks:

- Square 1, Square 2, and programmable-wave types enable the editor; Noise, sample, keysplit, and missing voices do not.
- The header button toggles the selected track, survives a document-triggered header rebuild, and works with no note selection.
- Cursor and playback program changes do not flicker or disable the track-level editor.
- A new template's local span matches the approved 100 ms contract within one playable-grid step.
- One drawn curve repeats at multiple eligible note-ons, including same-tick notes, with each note-on's active `BENDR` representing the same semitone curve.
- Mixed eligible/ineligible program spans omit ineligible projections; any later note-on clips and resets the preceding projection without note-off clipping.
- A commit preserves ordinary bends outside projected intervals, including gaps.
- Point add, drag, delete, and cancel produce one deterministic commit and one undo/redo step.
- Save and reload reconstruct the graph from ordinary bend events alone.
- Playback seek chases the resulting bend correctly.

After focused checks pass, run the actual application, open an eligible track, toggle the header button, draw and edit an envelope, audition it, save/reload, and observe the same curve and playback. This UI smoke test is required; offscreen widget construction alone is insufficient.

Finally run the applicable incremental build, focused harness, full check sweep when a writable decomp fixture is available, and `tools/format.sh --check` once after all implementation waves.

### Wave 5 — Header placement and tick-native authoring — NEXT

- Unwind `PitchEnvelopeHost` from `EditorDrawer` / `DrawerSections`.
- Place the host around the track headers. The graph fits in `trackHeaderWidth`. Latch on the P button; do not use `Qt::Popup` or `QDockWidget`.
- Switch the graph domain to `0 … windowTicks` once that value is chosen.
- Compile as the union of explicit user ticks, 1/64 sampling boundaries, and start/reset ticks. Never remove explicit user ticks.
- Stop the millisecond round-trip in the pointer path.

## Definition of done

The feature is complete when:

- Eligible track headers expose one stable pitch-envelope toggle that works with no note selection.
- The selected track owns one fixed local tick-window template that projects to every eligible note currently on that track. Current code still uses 0–100 ms until Wave 5.
- The envelope host sits around the track headers and fits the header column. It is not an `EditorDrawer` or velocity overlay.
- Ineligible note-ons receive no projection but still reset an earlier projection; note-off never clips it.
- The existing pitch/modulation popup and the new editor use one shared graph implementation.
- No second curve-editing convention or persistence artifact exists beside the shared module and ordinary bend lane.
- Graph gestures commit as one undoable edit while preserving out-of-interval bends.
- Playback, seeking, save/reload, WAV rendering, and mid2agb export agree on the resulting pitch bend.
- Later-added notes receive a projection only after a later envelope edit.
- Header rebuilds and program changes follow the approved contract.
- Focused checks and an actual UI smoke test cover the changed behavior.
- No palette, special voice type, or native hardware-sweep implementation is added.

## Resolved decisions (formerly Open decisions)

These decisions are normative and require no further product choice:

1. **Timing:** Authoring is a fixed local tick window `0 … windowTicks` (`windowTicks` not chosen). Playback samples at 1/64-note. Current code still uses 0–100 ms. Later tempo-map edits may change a committed projection's elapsed duration until tick-native authoring lands.
2. **Scope:** No note pick is required. Each gesture applies the selected track's template to every eligible note currently on that track; notes added later require another edit.
3. **Endpoints:** The local graph's first and last points are mandatory and zero-valued. Each projection resets to zero at the authoring-window end or the next distinct note-on.
4. **Reset:** Any later note-on, including an ineligible one, clips and resets the prior projection. Note-off does not clip it.
5. **Vertical scale:** Resolve `BENDR` at each eligible note-on to convert the same semitone template.
6. **Editor visibility:** Only the selected track's envelope editor may be open.
7. **Program changes:** A track containing an eligible note remains authorable across cursor and playhead program changes. Voice changes decide projections at note-on only.
8. **Storage and manual lane ownership:** Ordinary `DOC_CC_BEND` events are the sole representation. There is no sidecar, persistent template artifact, or second store; manual edits remain authoritative. Explicit user ticks survive compilation; no custom metadata is required.
9. **Editor placement:** Around the track headers. Graph fits in the header column. `EditorDrawer` / velocity overlay is rejected.
10. **Authoring vs playback:** Pointer placement may use any MIDI tick in the window. Playback quantization must not snap the pointer.
