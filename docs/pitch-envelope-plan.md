# Track-Wide Pitch Envelope Editor Plan

## Status and authority

This document records the pitch-envelope design discussed so far and maps it onto the current porydaw implementation. The compact normative behavior matrix below is the implementation contract; the remaining sections provide rationale, evidence, and sequencing.

The matrix and its repeated summary under **Agreed contract** are authoritative for this feature. The former **Open decisions** are resolved below, and the historical alternatives are retained only to explain the selected design. Implementers must follow the matrix rather than infer a different persistence model or endpoint policy.

### Normative behavior matrix

| Concern | Selected behavior |
| --- | --- |
| Timing | **Alternative A (selected):** the graph is one fixed local 0–100 ms template. Each commit maps it through the tempo map at every eligible note-on; later tempo edits may stretch or shrink elapsed duration. |
| Authoring scope | The selected track owns one template. No note pick is required; a gesture applies it to every eligible note currently on that track. |
| Endpoints and reset | Each projected interval starts at zero and explicitly resets to zero at 100 ms or the next distinct note-on, whichever comes first. A note-off never clips the interval. |
| Vertical scale | Convert the same relative-pitch template through the `BENDR` active at each eligible note-on. |
| Editor visibility | Only the selected track's envelope editor may be open at a time. |
| Program changes | Show one stable header toggle whenever the selected track contains an eligible note. It remains authorable across cursor and playhead program changes; the effective voice only decides which note-ons receive a projection. |
| Storage and manual lane ownership | Ordinary `DOC_CC_BEND` events are the sole persistence representation. There is no sidecar, persistent template artifact, or generated-versus-manual ownership split; manual edits to that lane remain authoritative. |
| Playback semantics | The bend is track-wide and never polyphonic: every active note on the engine track hears the same bend. |

The matrix deliberately resolves the initially requested strict millisecond timing to creation-time-only behavior because no persistence format was selected.

## Agreed contract

The feature is a track-wide pitch-envelope editor for GBA PSG melodic voices.

- Each track header provides a button that shows or hides the selected track's pitch-envelope editor.
- The editor has one local 0–100 ms template and needs no note selection.
- A completed gesture projects that template onto every eligible note currently on the selected track. Notes added later receive no retroactive projection; edit the envelope again to apply it to them.
- Program changes determine eligibility at each note-on. Any later note-on, eligible or not, clips and resets the preceding projection.
- Noise and sampled voices are out of scope.
- The editor is an editable vector graph made of points.
- The graph editor shares its implementation with the graph widgets in the existing pitch-bend popup.
- Pitch envelopes ultimately drive ordinary track-wide pitch bend. They are not polyphonic per-note expression: every active note on the engine track hears the same bend.

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

**Authoring window** — the template's fixed local horizontal domain: 0–100 ms.

**Playable projection** — ordinary SMF pitch-bend events (`0xE`) written for one eligible note-on, ending at 100 ms or the next note-on.

**Eligible voice** — a voice whose masked CGB type is Square 1, Square 2, or programmable wave.

The repository's “mid2agb clock” is not the envelope's authoring unit. `SongDocument::ticksPerClock()` describes the build grid at 24 or 48 clocks per beat; the product decision here is a 100 ms default instead.

## Current implementation evidence

### Pitch-bend document and playback path

- `DOC_CC_BEND` in `src/core/songdocument.h` is the pseudo-controller for SMF pitch-bend events (`0xE`).
- `SongDocument::writeLanePoints(...)` in `src/core/songdocument.{h,cpp}` replaces a bounded stream of lane points as one undoable edit.
- `MidiTimeline::build(...)` in `src/core/miditimeline.cpp` projects the editable SMF into sample-positioned events.
- `TimelinePlayer` in `src/core/timelineplayer.cpp` dispatches pitch bend to the M4A engine and chases the current value when playback seeks.

The runtime and export vocabulary therefore already support the playable result. The remaining work is the authoring representation and editor implementation, not a new engine command.

### Existing graph implementation

`PitchBendEditor` in `src/ui/pitchbendeditor.{hpp,cpp}` is a popup host. It creates two `PitchBendGraph` children: one for pitch bend and one for modulation. The host loads points from `SongDocument`, routes callbacks, and commits through `SongDocument::writeLanePoints(...)`.

`PitchBendGraph` in `src/ui/pitchbendgraph.{hpp,cpp}` already owns most of the required interaction:

- Point storage and rendering
- Hit testing and selected vertices
- Vertex insertion, dragging, and deletion
- Freehand and angled-line gestures
- Normal and fine sampling
- Axis painting and live-value formatting
- Keyboard commit, cancel, delete, and audition callbacks

It is not reusable unchanged:

- It is `final` and names the two current lanes directly.
- Its public points use absolute `uint64_t` ticks and `SongDocument::LanePointValue`.
- It retains `SongView`, engine-track, bend-range, and unterminated-note state.
- It obtains grid spacing from `SongView`.
- Its canvas dimensions and axis layout are fixed constants.
- Value bounds, labels, formatting, defaults, and snapping are selected through its pitch/modulation lane enum.

The second host makes a shared graph seam real. The implementation should extract or generalize the graph once rather than add a second point editor.

### Track header

`TrackHeaderRow` is currently nested in `src/ui/songview.cpp`. It owns the Mute and Solo `QToolButton`s, paints the track and current instrument, and is rebuilt after document edits. Any pitch-envelope visibility state stored only in a row widget would therefore be lost during normal editing.

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

The normative behavior matrix above closes the former decision gate. Timing, track-level scope, endpoint, vertical-scale, editor-visibility, program-change, and persistence ownership choices are settled; implementation must use selected Alternative A and must not introduce Alternative B's strict millisecond artifact.

### Wave 1 — Shared graph cutover

Use a `task` agent for the C++ extraction. Before modifying exported graph symbols, use LSP references for `PitchBendGraph`, `curvePoints`, `setCurve`, and construction sites.

- Extract the neutral editable-curve behavior.
- Adapt `PitchBendEditor` to the shared graph without changing its observable behavior.
- Keep the existing pitch and modulation graphs working.
- Remove obsolete tick/lane branches from the shared implementation rather than retaining two graph engines.
- Keep files within the repository's 200–400-line target and 600-line ceiling.

Extend `src/checks/pitchbendcheck.cpp` to defend the existing popup contract across the refactor: point creation, dragging, deletion, line/freehand behavior, keyboard handling, reset, commit/cancel, and the two graph instances.

Use a dedicated `reviewer` agent after implementation to inspect interface depth, duplicate coordinate logic, and accidental pitch-popup behavior changes.

### Wave 2 — Header toggle and eligibility

Use a `task` agent for the `SongView`/Qt changes and a `reviewer` agent for the interaction review.

- Add the header button to `TrackHeaderRow` without storing canonical state in the ephemeral row.
- Add one eligibility helper using masked `ToneData::type`.
- Route visibility state through the per-tab `SongView` owner.
- Restore button state after header rebuilds.
- Implement the approved program-change behavior without playhead-driven flicker.
- Add accessible name, tooltip, focus policy, and a clear checked state using existing track-header button conventions.

Do not refactor unrelated header selection, rename, reorder, mute, solo, or voice-picker behavior.

### Wave 3 — Envelope host and 100 ms mapping

Use a `task` agent because this wave crosses UI, timing conversion, note-on resolution, undo, and document behavior.

- Add the envelope host using the shared graph.
- Keep one fixed local 0–100 ms template on the selected track; do not require a note pick.
- Load from a deterministic eligible projection, preferring an unclipped projection and padding unavailable tail with zero.
- Resolve eligible note-ons and active `BENDR` when the graph refreshes, then snapshot those projections for the gesture and map the same semitone template to each.
- Clip every projection at the next distinct note-on, including an ineligible one; never clip at note-off.
- Preserve bends outside individual projection intervals by writing only the disjoint affected ranges.
- Commit one undoable gesture.

Because Alternative A is selected, use `SongDocument::writeLanePointRanges(...)` for one atomic disjoint-range edit; do not add a second envelope store, sidecar, persistent template artifact, or runtime compiler.

Alternative B is unselected; do not hide a strict millisecond persistence artifact or compiler behind UI-only state.

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

## Definition of done

The feature is complete when:

- Eligible track headers expose one stable pitch-envelope toggle that works with no note selection.
- The selected track owns one fixed local 0–100 ms template that projects to every eligible note currently on that track.
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

1. **Timing:** The graph is a fixed 0–100 ms local template. Later tempo-map edits may change a committed projection's elapsed duration.
2. **Scope:** No note pick is required. Each gesture applies the selected track's template to every eligible note currently on that track; notes added later require another edit.
3. **Endpoints:** The local graph's first and last points are mandatory and zero-valued. Each projection resets to zero at 100 ms or the next distinct note-on.
4. **Reset:** Any later note-on, including an ineligible one, clips and resets the prior projection. Note-off does not clip it.
5. **Vertical scale:** Resolve `BENDR` at each eligible note-on to convert the same semitone template.
6. **Editor visibility:** Only the selected track's envelope editor may be open.
7. **Program changes:** A track containing an eligible note remains authorable across cursor and playhead program changes. Voice changes decide projections at note-on only.
8. **Storage and manual lane ownership:** Ordinary `DOC_CC_BEND` events are the sole representation. There is no sidecar, persistent template artifact, or second store; manual edits remain authoritative.
