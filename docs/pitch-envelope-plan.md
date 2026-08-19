# Track-Wide Pitch Envelope Editor Plan

## Status and authority

This document records the pitch-envelope design discussed so far and maps it onto the current porydaw implementation. It is a directional implementation plan, not yet a complete normative specification.

The product decisions under **Agreed contract** are authoritative for this feature. The choices under **Open decisions** are intentionally unresolved and must be settled before implementation reaches the affected wave. Implementers must not silently choose a persistence model or endpoint policy.

## Agreed contract

The feature is a track-wide pitch-envelope editor for GBA PSG melodic voices.

- Each track header provides a button that shows or hides the track's pitch-envelope editor.
- The button is available for Square 1, Square 2, and programmable-wave (PSW/Wave) voices.
- Noise and sampled voices are out of scope.
- The editor is an editable vector graph made of points.
- A newly created envelope uses a 100 ms default authoring window. The default is not derived from note duration, tempo-relative note values, or mid2agb clock counts.
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

**Pitch envelope** — a bounded point curve authored through the new editor and realized as track-wide pitch bend.

**Envelope anchor** — the song position at which the envelope's zero-millisecond point begins.

**Authoring window** — the envelope's local horizontal domain. Its default length is 100 ms.

**Playable projection** — the ordinary SMF pitch-bend events (`0xE`) consumed by playback and export.

**Eligible voice** — a voice whose masked CGB type is Square 1, Square 2, or programmable wave.

The repository's “mid2agb clock” is not the envelope's authoring unit. `SongDocument::ticksPerClock()` describes the build grid at 24 or 48 clocks per beat; the product decision here is a 100 ms default instead.

## Current implementation evidence

### Pitch-bend document and playback path

- `DOC_CC_BEND` in `src/core/songdocument.h` is the pseudo-controller for SMF pitch-bend events (`0xE`).
- `SongDocument::writeLanePoints(...)` in `src/core/songdocument.{h,cpp}` replaces a bounded stream of lane points as one undoable edit.
- `MidiTimeline::build(...)` in `src/core/miditimeline.cpp` projects the editable SMF into sample-positioned events.
- `TimelinePlayer` in `src/core/timelineplayer.cpp` dispatches pitch bend to the M4A engine and chases the current value when playback seeks.

The runtime and export vocabulary therefore already support the playable result. The unresolved work is the authoring representation and editor, not a new engine command.

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

A point stored only as an SMF tick cannot remain exactly 100 ms from its anchor after a tempo-map edit. A strict millisecond invariant requires persistent millisecond-domain authoring data and regeneration of the playable projection. A creation-time-only 100 ms default can write ordinary bend points immediately but will subsequently stretch or shrink with tempo changes.

### Sidecars

`src/project/sidecar.h` defines `.porydaw/` as ignored, per-user state that never belongs in the repository. Musical envelope intent must not be stored there. If rich millisecond-domain intent is required, it needs either a tracked song artifact or a verified in-SMF metadata encoding.

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

- The selected engine track and envelope anchor
- The 0–100 ms default graph domain
- Relative-pitch bounds and formatting
- Loading the source curve
- Previewing the playable projection
- Committing one undoable edit
- Restoring focus and handling document/header rebuilds

The first implementation uses points joined by straight lines. Reuse the existing point insertion, drag, deletion, line, cancel, and keyboard mechanics. Do not add Bézier handles.

The vertical axis should display musical relative pitch rather than raw 14-bit MIDI numbers. Conversion through the effective BENDR value belongs outside the shared graph. The exact default vertical range remains an open product choice.

### Track-header toggle

Add a checkable pitch-envelope button to `TrackHeaderRow`.

The button widget publishes intent; it does not own canonical visibility state. Store the state in the `SongView`/per-tab UI model so header reconstruction restores the checked state. The plan does not yet choose whether several tracks may keep editors open simultaneously or whether opening one closes the previous editor.

Eligibility must use a single helper over `ToneData::type`:

```cpp
bool voiceSupportsPitchEnvelope(uint8_t type);
```

The helper accepts masked Square 1, Square 2, and programmable-wave types and rejects Noise, keysplit/drumkit, and sampled voices. UI code and checks must call this helper instead of duplicating type tests.

#### Program changes

Track-wide visibility and time-local eligibility are different concerns. A track can contain program changes between eligible and ineligible voices. The current `currentProgram()` follows the playhead during playback, which would make an editing control appear or disappear while the song plays.

Recommended behavior:

- Do not change button visibility merely because playback crosses a program change.
- Resolve edit eligibility at the edit cursor or prospective envelope anchor through `voiceContext(tick)`.
- Keep an already-open editor visible when the cursor enters an ineligible span, but disable point creation there and explain why.
- Existing envelope data remains visible even when the current span is ineligible.

This behavior must be confirmed before the header wave begins.

## Timing and persistence alternatives

This is the principal unresolved design choice.

### Alternative A — 100 ms at creation, raw lane remains authoritative

At envelope creation:

1. Resolve the anchor tick through the tempo map.
2. Add 100 ms in sample/time space.
3. Convert that end position back to an SMF tick.
4. Initialize/edit vector points over that bounded tick interval.
5. Commit ordinary `DOC_CC_BEND` points through `SongDocument::writeLanePoints(...)`.

Consequences:

- No new musical storage format or note identity is required.
- Existing undo, raw-event editing, playback, seeking, save, export, and round-trip behavior remain authoritative.
- The envelope's elapsed duration changes if the tempo map is edited later.
- Reopening the editor reconstructs the curve from ordinary bend points.
- The feature is a focused track-wide automation affordance rather than a second musical data model.

This is the simplest design and is recommended if “100 ms” means the initial drawing window rather than a permanent elapsed-time guarantee.

### Alternative B — 100 ms remains invariant

Persist each envelope as an anchor plus millisecond-domain points. On playback/save/export, compile those points through the current tempo map into ordinary pitch-bend events.

Consequences:

- Tempo changes can preserve an exact 100 ms envelope.
- Authoring intent and playable SMF events become separate representations.
- The implementation needs stable ownership, undo integration, stale-data handling, conflict behavior for manual edits in generated spans, and a tracked persistence format.
- Existing `.porydaw/` sidecars cannot be used.
- A tracked adjacent song file or a verified sequencer-specific SMF meta encoding is required.
- Playback and export must use the same compiler so they cannot disagree.

Do not begin this alternative until the storage artifact and manual-lane interaction are explicitly approved. It is substantially larger than a graph/editor feature.

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

The following endpoint choices remain open:

- Whether start and end points are mandatory
- Whether the default end point is zero
- Whether the final value is allowed to hold after 100 ms
- Whether commit automatically restores zero at the end of the authoring window, at note-off, at the next note-on, or only when the user draws a reset

Because pitch bend is persistent track state, the editor must make any held value visually explicit. It must not silently imply that a curve ends when the engine will continue holding its last value.

## Track-wide and overlap semantics

The playable projection is track-wide. If several notes overlap on the same engine track, every active note receives the same pitch bend. The editor must not label the curve as per-note expression or imply independent note control.

No overlap arbitration is needed for Alternative A because there is only one authoritative lane. Alternative B would require generated/manual ownership and conflict rules before it can be implemented.

## Undo, save, playback, and export

### Alternative A

- Commit each completed graph gesture through the existing lane-edit command path as one undoable operation.
- Preview may update the graph continuously, but it must not create an undo command per mouse move.
- Saving writes the existing SMF pitch-bend events.
- `MidiTimeline::build(...)`, `TimelinePlayer`, WAV export, and mid2agb continue to consume the ordinary events without a new runtime path.
- Event ordering and pitch-bend chase behavior remain the existing `SongDocument`/`MidiTimeline` contract.

### Alternative B

- Envelope mutation and regeneration must be one atomic undoable document operation.
- The compiler must be the only implementation of millisecond-to-tick sampling.
- Timeline playback, WAV rendering, MIDI save, and mid2agb export must receive the same projected event stream.
- Manual edits to a generated range need an explicit detach, reject, or replace policy; silent two-way synchronization is prohibited.

## Implementation sequence

### Decision gate — Timing, endpoint, and visibility contracts

Before production edits, settle every item in **Open decisions** that affects storage or observable behavior.

Use a `task` agent to turn the selected alternatives into a compact normative behavior matrix. Use a `reviewer` agent to check that the matrix neither promises tempo independence from tick-only storage nor implies polyphonic pitch bend.

Deliverable: an approved amendment to this document or a separate normative specification. No implementation proceeds past this gate with both timing alternatives still open.

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

Use a `task` agent because this wave crosses UI, timing conversion, undo, and document behavior.

- Add the envelope host using the shared graph.
- Anchor new envelopes according to the approved cursor/selection rule.
- Initialize the approved 100 ms point window.
- Convert between local graph time and playable tick positions through one timing function.
- Apply the approved endpoint/hold/reset semantics.
- Commit one undoable gesture.
- Prevent creation in ineligible voice spans while preserving visibility of existing data.

If Alternative A is selected, reuse `SongDocument::writeLanePoints(...)`; do not add a second envelope store or compiler.

If Alternative B is selected, this wave must first implement the approved tracked persistence format and one compiler seam. Do not hide that work behind UI-only state.

Use a `reviewer` agent to compare the audible result, saved events, and displayed curve at constant tempo, across a tempo change, and around a program change.

### Wave 4 — Focused verification and wiring

Use a `task` agent for behavioral checks. Use a `sonic` agent only for mechanical build-list or check-dispatch wiring after test ownership is already defined.

Prefer extending the existing pitch-bend/roll harnesses over creating a second overlapping graph harness. Add a new check entry only if the track-header lifecycle and timing scenarios cannot be expressed cleanly through `pitchbendcheck` and `rollcheck`.

Required checks:

- Square 1, Square 2, and programmable-wave types enable the editor.
- Alternate CGB encodings resolve through the masked type.
- Noise, sample, keysplit, and missing voices do not permit creation.
- The header button toggles the correct track and survives a document-triggered header rebuild.
- Playback does not make the control flicker across a program change.
- A new envelope's initial elapsed span matches the approved 100 ms contract within one playable-grid step.
- Point add, drag, delete, and cancel produce one deterministic commit.
- Undo restores the exact pre-edit SMF bytes/state; redo restores the envelope.
- The final value/reset behavior matches the approved endpoint contract.
- Overlapping notes hear the same track-wide bend.
- Save and reload preserve the approved source representation.
- Playback seek chases the resulting bend correctly.

After focused checks pass, run the actual application, open an eligible track, toggle the header button, draw and edit an envelope, audition it, save/reload, and observe the same curve and playback. This UI smoke test is required; offscreen widget construction alone is insufficient.

Finally run the applicable incremental build, focused harness, full check sweep when a writable decomp fixture is available, and `deno task format:check` once after all implementation waves.

## Definition of done

The feature is complete when:

- Eligible track headers expose one stable pitch-envelope toggle.
- Ineligible voices cannot create pitch envelopes.
- The editor is a point-based vector graph with the agreed 100 ms behavior.
- The existing pitch/modulation popup and the new editor use one shared graph implementation.
- No second curve-editing convention exists beside the shared module.
- Graph gestures commit as one undoable edit.
- Track-wide behavior and held/reset pitch state are visually honest.
- Playback, seeking, save/reload, WAV rendering, and mid2agb export agree on the resulting pitch bend.
- Header rebuilds, program changes, and tempo changes follow the approved contract.
- Focused checks and an actual UI smoke test cover the changed behavior.
- No palette, special voice type, or native hardware-sweep implementation is added.

## Open decisions

These questions must be answered before implementation crosses the decision gate:

1. Does 100 ms describe only the initial window at creation, or must the envelope remain exactly 100 ms after later tempo-map changes?
2. Where is a new envelope anchored: edit cursor, selected note-on, clicked timeline position, or an explicit time selection?
3. Are the first and last points mandatory, and what are their default values?
4. Does the final point hold, or does the editor insert an automatic zero reset? If reset is automatic, when does it occur?
5. What is the default vertical range and snapping unit: semitones, cents, or the track's active BENDR range?
6. Can several track envelope editors remain open, or is there one active editor for the selected track?
7. For tracks with program changes, is the header toggle shown when any eligible span exists, only at an eligible edit cursor, or always shown but disabled contextually?
8. If strict millisecond persistence is selected, which tracked musical storage format owns the envelope intent, and what happens when raw generated bend events are edited manually?
