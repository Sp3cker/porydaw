# Scale Mode Specification

## Status

Confirmed product specification. This file is normative. `scale-mode-research.md` is supporting research, not a behavioral contract.

## Purpose

Scale Mode gives the piano roll three explicit views of a selected musical key:

- **Off** — the existing chromatic piano roll.
- **Highlight** — the chromatic piano roll with scale-member lanes tinted purple.
- **Fold** — a compact piano roll containing scale pitches and occupied exception pitches from the selected track.

Highlight and Fold affect editing presentation and pitch navigation only. They never rewrite MIDI merely because the mode, root, scale, or selected track changes.

## Non-goals

- Snap or quantize as an independent feature
- MIDI playback filtering or transformation
- Device-level scale awareness
- Per-clip scale overrides
- Microtonal tuning
- Importing an SMF key-signature event
- Persistent state, including `ViewSidecar`, `SongCfg`, `midi.cfg`, or application settings
- User-defined scales

## Terminology

- **Root** — one of the 12 chromatic pitch classes, named with porydaw's existing sharp-only spelling.
- **Scale** — a stable porydaw scale identity and a root-relative set of pitch classes.
- **Scale pitch** — a MIDI pitch whose root-relative pitch class belongs to the selected scale.
- **Exception pitch** — an exact off-scale MIDI pitch occupied by at least one note in the selected track.
- **Visible pitch** — a pitch represented by a row in the current piano-roll layout.
- **Diatonic move** — a vertical note move measured in scale degrees rather than semitones.
- **Selected track** — the active editable track. Notes from other tracks can appear as ghosts but do not affect Fold occupancy.

## Runtime state

Each open song tab owns:

- Root
- Scale
- Mode: Off, Highlight, or Fold

The initial state of a new tab is:

- Root: C
- Scale: Major
- Mode: Off

State lives only for the lifetime of the open tab:

- Switching away from a tab and returning preserves its state.
- Closing and reopening a tab returns to the defaults.
- No Scale Mode state is serialized.

Changing the selected track has mode-dependent behavior:

- Off remains Off.
- Highlight remains Highlight.
- Fold changes to Highlight.
- Returning to the previous track does not restore Fold.
- Root and Scale do not change.

Changing Root or Scale:

- Has no visible effect while Off.
- Repaints Highlight immediately.
- Rebuilds the Fold layout immediately while keeping Fold active.

## Root names

The Root control uses the existing porydaw spelling:

`C, C#, D, D#, E, F, F#, G, G#, A, A#, B`

Enharmonic or flat spelling is outside this feature.

## Scale catalog

Scale identities are explicit, stable porydaw IDs. Combo-box positions and display order are not identities.

Intervals are semitones above the selected Root. A scale contains MIDI pitch `p` when:

`((p % 12) - root + 12) % 12`

is one of its intervals.

| Display order | Stable ID | Display name | Intervals |
|---:|---|---|---|
| 1 | `major` | Major | `0, 2, 4, 5, 7, 9, 11` |
| 2 | `natural_minor` | Natural Minor | `0, 2, 3, 5, 7, 8, 10` |
| 3 | `dorian` | Dorian | `0, 2, 3, 5, 7, 9, 10` |
| 4 | `phrygian` | Phrygian | `0, 1, 3, 5, 7, 8, 10` |
| 5 | `lydian` | Lydian | `0, 2, 4, 6, 7, 9, 11` |
| 6 | `mixolydian` | Mixolydian | `0, 2, 4, 5, 7, 9, 10` |
| 7 | `locrian` | Locrian | `0, 1, 3, 5, 6, 8, 10` |
| 8 | `harmonic_minor` | Harmonic Minor | `0, 2, 3, 5, 7, 8, 11` |
| 9 | `melodic_minor` | Melodic Minor | `0, 2, 3, 5, 7, 9, 11` |
| 10 | `harmonic_major` | Harmonic Major | `0, 2, 4, 5, 7, 8, 11` |
| 11 | `major_pentatonic` | Major Pentatonic | `0, 2, 4, 7, 9` |
| 12 | `minor_pentatonic` | Minor Pentatonic | `0, 3, 5, 7, 10` |
| 13 | `minor_blues` | Minor Blues | `0, 3, 5, 6, 7, 10` |
| 14 | `whole_tone` | Whole Tone | `0, 2, 4, 6, 8, 10` |
| 15 | `half_whole_diminished` | Half-Whole Diminished | `0, 1, 3, 4, 6, 7, 9, 10` |
| 16 | `whole_half_diminished` | Whole-Half Diminished | `0, 2, 3, 5, 6, 8, 9, 11` |
| 17 | `dorian_sharp_4` | Dorian #4 | `0, 2, 3, 6, 7, 9, 10` |
| 18 | `phrygian_dominant` | Phrygian Dominant | `0, 1, 4, 5, 7, 8, 10` |
| 19 | `lydian_augmented` | Lydian Augmented | `0, 2, 4, 6, 8, 9, 11` |
| 20 | `lydian_dominant` | Lydian Dominant | `0, 2, 4, 6, 7, 9, 10` |
| 21 | `altered` | Altered (Super Locrian) | `0, 1, 3, 4, 6, 8, 10` |
| 22 | `eight_tone_spanish` | 8-Tone Spanish | `0, 1, 3, 4, 5, 6, 8, 10` |
| 23 | `bhairav` | Bhairav | `0, 1, 4, 5, 7, 8, 11` |
| 24 | `hungarian_minor` | Hungarian Minor | `0, 2, 3, 6, 7, 8, 11` |
| 25 | `hirajoshi` | Hirajoshi | `0, 2, 3, 7, 8` |
| 26 | `in_sen` | In-Sen | `0, 1, 5, 7, 10` |
| 27 | `iwato` | Iwato | `0, 1, 5, 6, 10` |
| 28 | `kumoi` | Kumoi | `0, 2, 3, 7, 9` |

There is no Chromatic catalog entry. Off mode supplies the unmodified chromatic view. Pelog and Messiaen scales are not included.

## Off mode

Off preserves existing piano-roll behavior exactly:

- 128 chromatic rows
- Existing natural and accidental lane colors
- Existing piano-key rendering
- Existing chromatic drawing, dragging, and transpose behavior

Selecting a Root or Scale while Off updates runtime state but does not alter the roll.

## Highlight mode

Highlight retains all 128 chromatic rows.

For each scale-pitch lane, composite `#b595fc` over the existing lane background at 50% opacity. The source purple and opacity are identical in all three built-in themes and custom themes.

Highlight rules:

- Tint the full lane background.
- Preserve the natural/accidental distinction underneath the tint.
- Use the same tint for every scale degree, including the Root.
- Preserve grid and octave lines.
- Do not tint piano-keyboard keys.
- Do not change normal, ghost, selected, velocity-colored, or sounding note semantics.

## Fold mode

### Visible pitches

Fold uses a sorted, uniform-height sequence containing:

1. Every scale pitch in the MIDI range 0–127.
2. Every exact exception pitch occupied anywhere in the selected track.

An exception is per MIDI pitch, not pitch class. For example, an off-scale C#4 reveals only C#4, not C# in every octave.

Selected-track occupancy includes every note in the complete timeline regardless of:

- Horizontal viewport
- Mute or solo state
- Selection
- Current playback position

Notes from other tracks do not add exception rows. Their ghost notes are visible only when the selected track's Fold layout already contains their exact pitch.

Fold does not crop to the selected track's minimum and maximum notes. All scale pitches from 0 through 127 remain available even when the selected track is empty.

### Fold rendering

- All visible rows retain the existing uniform row height.
- Rows remain ordered by ascending MIDI pitch with hidden gaps removed.
- Scale rows and exception rows use ordinary natural/accidental styling.
- Fold does not apply the purple Highlight tint.
- The piano keyboard contains exactly the visible pitches and uses existing key styling.
- Existing C labels appear only when their C row is visible; Fold adds no new root labels.

### Exception lifecycle

An exception row remains until the selected track no longer contains a note at that pitch.

- During a pointer edit, keep the current layout stable.
- Rebuild after the edit gesture commits.
- Rebuild immediately after an atomic model change such as paste, delete, undo, redo, or another completed note insertion.

### Viewport anchoring

Every Fold-layout rebuild preserves the MIDI pitch nearest the vertical center of the viewport.

- If the anchor remains visible, keep it at the same screen position.
- If it becomes hidden, use the nearest visible pitch.
- Resolve an equal-distance tie toward the lower pitch.
- Clamp only when required by the new scroll extent.
- Do not preserve proportional scrollbar position.

This rule applies when entering or leaving Fold, changing Root or Scale, and adding or removing exception rows.

## Editing behavior

### Unchanged paths

Off and Highlight retain existing chromatic editing behavior.

Fold does not alter pitch during:

- Horizontal note movement
- Resize
- Velocity editing
- Selection
- Time movement

Paste, undo, redo, explicit chromatic time-range transposition, and other completed note insertions may introduce off-scale notes. Fold reveals their exception rows according to the lifecycle rules above.

### Exception-row interaction

An existing exception note can be selected, auditioned, moved in time, resized, deleted, or moved vertically into the scale.

Exception rows do not participate as destinations for ordinary Fold drawing, scale-degree dragging, or scale-degree nudging:

- Drawing in empty time on an exception row does nothing.
- Vertical note dragging skips exception rows.
- Fold-mode scale-degree nudging skips exception rows.
- Clicking its piano key can still audition the exception pitch.

Chromatic operations remain exempt: paste and other note insertion, ±12 octave commands, and multi-track time-range transposition may land off-scale. Their completed edits create or retain the corresponding exception rows.

### Keyboard pitch commands

For an ordinary note selection on the selected track while folded:

- Up moves one scale degree.
- Down moves one scale degree.
- Octave Up remains exactly +12 semitones.
- Octave Down remains exactly -12 semitones.

Off and Highlight keep semitone Up/Down behavior. Multi-track time-range transposition remains chromatic in every mode.

### Scale-degree stepping

Let `S` be the sorted set of selected-scale MIDI pitches in 0–127.

For an in-scale source pitch, a signed displacement of `d` degrees moves by `d` positions in `S`.

For an off-scale source pitch:

- An upward move first enters the lowest scale pitch strictly above it.
- A downward move first enters the highest scale pitch strictly below it.
- Remaining displacement continues by scale degree.

Exception pitches never count as scale-degree steps.

### Multi-note diatonic movement

Fold moves each distinct selected source pitch to a distinct scale destination. Notes sharing the same source pitch share the same destination, regardless of time.

For an upward move:

1. Process distinct source pitches from low to high.
2. Compute the requested scale-degree destination.
3. If that destination is already assigned to a lower source pitch, advance to the next scale pitch until it is distinct.

For a downward move, mirror the procedure from high to low.

Consequences are intentional:

- Exact semitone intervals can change.
- Pitch ordering is preserved.
- Distinct selected source pitches never collapse onto one destination.
- Timing and duration do not affect destination calculation.

Examples in C Major:

- C and C# moved up one degree become D and E.
- C# and D moved down one degree become B and C.

If any requested or collision-adjusted destination falls outside MIDI 0–127, reject the complete pitch operation. Do not clamp or partially move the selection.

Collisions with unselected notes retain porydaw's existing overlap-resolution behavior.

### Mouse dragging

Mouse dragging and keyboard scale-degree nudging use the same multi-note transformation.

- Scale rows define the legal destination sequence.
- Exception rows remain visible but do not count as movement steps or destinations.
- Dragging across `N` scale rows applies an `N`-degree displacement.
- If the grabbed note starts off-scale, the first movement enters the nearest scale pitch in the drag direction.
- If the pointer lies over an exception row, resolve toward the next scale pitch in the drag direction.

The Fold layout stays fixed for the duration of the drag and rebuilds after commit.

## Controls

The transport toolbar contains three adjacent controls:

1. Root
2. Scale
3. Mode: Off, Highlight, Fold

Requirements:

- The controls target the active tab only.
- Switching tabs synchronizes all three controls without emitting changes into the incoming tab.
- All three controls are disabled when no tab is active.
- Root and Scale remain enabled while Mode is Off.
- Scale identities come from combo item data, never from combo indices.
- Scale Mode adds no duplicate View-menu actions.

## Acceptance criteria

### Catalog

- The catalog contains exactly the 28 specified stable IDs and interval sets.
- Major is the default and contains `0, 2, 4, 5, 7, 9, 11`.
- Combo reordering cannot change a selected scale's identity.
- Every catalog scale contains interval 0 and no interval outside 0–11.

### State

- A new tab starts at C Major and Off.
- Tabs retain independent runtime states while open.
- Closing and reopening returns to defaults.
- No Scale Mode field is written to any persistence path.
- A selected-track change performs Fold → Highlight and leaves other modes unchanged.

### Highlight

- C Major highlights C, D, E, F, G, A, and B lanes in every octave.
- The tint is `#b595fc` at 50% over each lane's existing background.
- Piano keys and note fills do not acquire the tint.
- Off is pixel-equivalent to the existing chromatic rendering.

### Fold geometry

- C Major Fold contains every C-major pitch in 0–127.
- A selected-track C#4 note adds exactly the C#4 exception row.
- Another track's C#4 ghost does not create that row.
- The final selected-track C#4 note keeps the row until its edit commits, then the row disappears.
- Key-to-row and row-to-key mappings are inverses for every visible pitch.
- Hidden pitches have no row and cannot be targeted by drawing.
- Camera anchoring follows the center-pitch rule on every layout rebuild.

### Editing

- Fold Up/Down moves by scale degree; octave commands remain ±12.
- Off and Highlight retain chromatic Up/Down.
- Multi-track time-range transpose remains chromatic.
- Ordinary Fold drawing, scale-degree dragging, and scale-degree nudging cannot target exception rows; chromatic octave, time-range, paste, and insertion paths may create or retain them.
- C and C# selected together in C Major move upward to D and E.
- Repeated notes at the same source pitch share one destination.
- Out-of-range multi-note movement is entirely rejected.
- One gesture produces one undoable document edit.
- Undo restores every original pitch and the corresponding Fold layout.

### Visual smoke scenario

1. Open two tabs and confirm both start at C Major and Off.
2. Set the first tab to G Dorian and Highlight; confirm only lanes receive the fixed purple tint.
3. Switch tabs and confirm their states remain independent.
4. In the first tab, select a track containing an off-scale note and enter Fold.
5. Confirm scale rows plus the exact exception row remain visible.
6. Move the exception note into the scale and confirm the row disappears only after release.
7. Nudge a mixed in-scale/off-scale selection and confirm collision-free diatonic destinations.
8. Change the selected track and confirm Fold becomes Highlight.
9. Close and reopen the tab and confirm C Major and Off are restored.
