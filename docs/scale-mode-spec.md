# Scale Mode Specification

## Status

Confirmed product specification. This file is normative. `scale-mode-research.md` is supporting research, not a behavioral contract.

## Purpose

Scale Mode provides two independent piano-roll toggles for a selected musical key:

| Highlight | Fold | Piano-roll layout | Editing behavior |
|---|---|---|---|
| Disabled | Disabled | Existing 128-row chromatic piano roll | Existing chromatic behavior |
| Enabled | Disabled | 128-row chromatic piano roll with scale-member lanes tinted purple | Existing chromatic behavior |
| Disabled | Enabled | Compact piano roll containing only pitches used by the selected track | Fold's diatonic behavior |
| Enabled | Enabled | Compact occupied-pitch piano roll with visible scale-member lanes tinted purple | Fold's diatonic behavior |

Highlight and Fold affect editing presentation and pitch navigation only. They never rewrite MIDI merely because a toggle, root, scale, or selected track changes.

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
- **Occupied pitch** — an exact MIDI pitch occupied by at least one note in the selected track. Occupied pitches are the only rows Fold shows.
- **Visible pitch** — a pitch represented by a row in the current piano-roll layout.
- **Diatonic move** — a vertical note move measured in scale degrees rather than semitones.
- **Selected track** — the active editable track. Notes from other tracks can appear as ghosts but do not affect Fold occupancy.

## Runtime state

Each open song tab owns:

- Root
- Scale
- Highlight enabled
- Fold enabled

The initial state of a new tab is:

- Root: C
- Scale: Major
- Highlight: disabled
- Fold: disabled

State lives only for the lifetime of the open tab:

- Switching away from a tab and returning preserves its state.
- Closing and reopening a tab returns to the defaults.
- No Scale Mode state is serialized.

Changing the selected track preserves both toggle states; Root and Scale also remain unchanged. While Fold is enabled, the layout immediately rebuilds from the incoming selected track's occupied pitches.

Changing Root or Scale:

- Has no visible effect when both toggles are disabled.
- Repaints Highlight immediately when Highlight is enabled.
- Reclassifies Fold editing destinations immediately when Fold is enabled without changing its occupied-pitch layout.

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

There is no Chromatic catalog entry. With Fold disabled, the unmodified chromatic view is used. Pelog and Messiaen scales are not included.

## Neither toggle enabled

With both Highlight and Fold disabled, the piano roll preserves existing behavior exactly:

- 128 chromatic rows
- Existing natural and accidental lane colors
- Existing piano-key rendering
- Existing chromatic drawing, dragging, and transpose behavior

Selecting a Root or Scale updates runtime state but does not alter the roll while both toggles are disabled.

## Highlight toggle

Enabling Highlight applies its tint to every visible scale-pitch lane. With Fold disabled, Highlight retains all 128 chromatic rows. With Fold enabled, it tints only the visible scale-pitch lanes in the occupied-pitch layout.

For each tinted lane, composite `#b595fc` over the existing lane background at 20% opacity (alpha 51). The source purple and opacity are identical in all three built-in themes and custom themes.

Highlight rules:

- Tint the full lane background.
- Preserve the natural/accidental distinction underneath the tint.
- Use the same tint for every scale degree, including the Root.
- Preserve grid and octave lines.
- Do not tint piano-keyboard keys.
- Do not change normal, ghost, selected, velocity-colored, or sounding note semantics.

## Fold toggle

### Visible pitches

When Fold is enabled, it uses a sorted, uniform-height sequence containing every exact MIDI pitch occupied anywhere in the selected track.

Occupancy is per MIDI pitch, not pitch class. For example, a C#4 note reveals only C#4, not C# in every octave. Scale membership does not add rows: an unoccupied scale pitch remains hidden.

Selected-track occupancy includes every note in the complete timeline regardless of:

- Horizontal viewport
- Mute or solo state
- Selection
- Current playback position

Notes from other tracks do not add rows. Their ghost notes are visible only when the selected track's Fold layout already contains their exact pitch.

An empty selected track has no Fold rows.

### Fold rendering

- All visible rows retain the existing uniform row height.
- Rows remain ordered by ascending MIDI pitch with hidden gaps removed.
- Scale rows and exception rows use ordinary natural/accidental styling beneath any Highlight tint.
- When Highlight is enabled, composite `#b595fc` at 20% opacity (alpha 51) over each visible scale-pitch lane; exception lanes remain untinted.
- The piano keyboard contains exactly the visible pitches and uses existing key styling.
- Existing C labels appear only when their C row is visible; Fold adds no new root labels.

### Exception lifecycle

An occupied row remains until the selected track no longer contains a note at that pitch.

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

This rule applies when enabling or disabling Fold, changing the selected track, and adding or removing occupied rows. Root or Scale changes do not rebuild Fold geometry.

## Editing behavior

### Unchanged paths

With Fold disabled, existing chromatic editing behavior is retained whether Highlight is enabled or disabled.

When Fold is enabled, it does not alter pitch during:

- Horizontal note movement
- Resize
- Velocity editing
- Selection
- Time movement

Paste, undo, redo, explicit chromatic time-range transposition, and other completed note insertions may introduce off-scale notes. When Fold is enabled, it reveals their exception rows according to the lifecycle rules above.

### Exception-row interaction

An existing exception note can be selected, auditioned, moved in time, resized, deleted, or moved vertically into the scale.

Exception rows do not participate as destinations for ordinary Fold drawing, scale-degree dragging, or scale-degree nudging while Fold is enabled:

- Drawing in empty time on an exception row does nothing.
- Vertical note dragging skips exception rows.
- Fold scale-degree nudging skips exception rows.
- Clicking its piano key can still audition the exception pitch.

Chromatic operations remain exempt: paste and other note insertion, ±12 octave commands, and multi-track time-range transposition may land off-scale. Their completed edits create or retain the corresponding exception rows.

### Keyboard pitch commands

For an ordinary note selection on the selected track while Fold is enabled:

- Up moves one scale degree.
- Down moves one scale degree.
- Octave Up remains exactly +12 semitones.
- Octave Down remains exactly -12 semitones.

With Fold disabled, Up/Down remain semitone commands whether Highlight is enabled or disabled. Multi-track time-range transposition remains chromatic regardless of either toggle.

### Scale-degree stepping

Let `S` be the sorted set of selected-scale MIDI pitches in 0–127.

For an in-scale source pitch, a signed displacement of `d` degrees moves by `d` positions in `S`.

For an off-scale source pitch:

- An upward move first enters the lowest scale pitch strictly above it.
- A downward move first enters the highest scale pitch strictly below it.
- Remaining displacement continues by scale degree.

Exception pitches never count as scale-degree steps.

### Multi-note diatonic movement

When Fold is enabled, it moves each distinct selected source pitch to a distinct scale destination. Notes sharing the same source pitch share the same destination, regardless of time.

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

When Fold is enabled, mouse dragging and keyboard scale-degree nudging use the same multi-note transformation.

- Scale rows define the legal destination sequence.
- Exception rows remain visible but do not count as movement steps or destinations.
- Dragging across `N` scale rows applies an `N`-degree displacement.
- If the grabbed note starts off-scale, the first movement enters the nearest scale pitch in the drag direction.
- If the pointer lies over an exception row, resolve toward the next scale pitch in the drag direction.

The Fold layout stays fixed for the duration of the drag and rebuilds after commit.

## Controls

The transport toolbar contains four adjacent controls:

1. Root
2. Scale
3. Highlight toggle button
4. Fold toggle button

Requirements:

- The controls target the active tab only.
- Switching tabs synchronizes all four controls without emitting changes into the incoming tab.
- All four controls are disabled when no tab is active.
- Root, Scale, Highlight, and Fold remain independently available while a tab is active.
- Clicking Highlight changes only Highlight; clicking Fold changes only Fold. Neither click disables or enables the other toggle.
- Scale identities come from combo item data, never from combo indices.
- Scale Mode adds no duplicate View-menu actions.

## Acceptance criteria

### Catalog

- The catalog contains exactly the 28 specified stable IDs and interval sets.
- Major is the default and contains `0, 2, 4, 5, 7, 9, 11`.
- Combo reordering cannot change a selected scale's identity.
- Every catalog scale contains interval 0 and no interval outside 0–11.

### State and controls

- A new tab starts at C Major with Highlight and Fold both disabled.
- Tabs retain independent Root, Scale, Highlight, and Fold runtime states while open.
- Closing and reopening returns to defaults.
- No Scale Mode field is written to any persistence path.
- A selected-track change preserves both toggle states, Root, and Scale; when Fold is enabled, it rebuilds from the incoming track's occupied pitches.
- Highlight and Fold buttons toggle independently and can be enabled together.

### Toggle combinations

- With both toggles disabled, the roll is pixel-equivalent to the existing chromatic rendering and uses chromatic editing.
- With only Highlight enabled, all 128 chromatic rows remain and only scale-member lanes receive the tint.
- With only Fold enabled, exactly the selected track's occupied rows remain visible without purple tint and Fold editing is diatonic.
- With both toggles enabled, exactly the selected track's occupied rows remain visible, visible scale-member lanes receive the tint, and Fold editing remains diatonic.

### Highlight

- C Major highlights C, D, E, F, G, A, and B lanes in every octave when those lanes are visible.
- The tint is `#b595fc` at 20% over each lane's existing background.
- Piano keys and note fills do not acquire the tint.

### Fold geometry

- Fold contains exactly the MIDI pitches occupied anywhere in the selected track.
- Scale pitches are hidden when the selected track does not use them.
- An empty selected track has no Fold rows.
- Another track's notes do not create rows.
- The final selected-track note at a pitch keeps its row until its edit commits, then the row disappears.
- Key-to-row and row-to-key mappings are inverses for every visible pitch.
- Hidden pitches have no row and cannot be targeted by drawing.
- Camera anchoring follows the center-pitch rule on every layout rebuild.

### Editing

- With Fold enabled, Up/Down moves by scale degree; octave commands remain ±12.
- With Fold disabled, Up/Down remains chromatic whether Highlight is enabled or disabled.
- Multi-track time-range transpose remains chromatic.
- Ordinary Fold drawing, scale-degree dragging, and scale-degree nudging cannot target exception rows; chromatic octave, time-range, paste, and insertion paths may create or retain them.
- C and C# selected together in C Major move upward to D and E.
- Repeated notes at the same source pitch share one destination.
- Out-of-range multi-note movement is entirely rejected.
- One gesture produces one undoable document edit.
- Undo restores every original pitch and the corresponding Fold layout.

### Visual smoke scenario

1. Open two tabs and confirm both start at C Major with Highlight and Fold disabled.
2. Set the first tab to G Dorian and enable Highlight; confirm all 128 rows remain and only scale-member lanes receive the fixed purple tint.
3. Switch tabs and confirm their Root, Scale, Highlight, and Fold states remain independent.
4. In the first tab, select a track containing both in-scale and off-scale notes and enable Fold without disabling Highlight.
5. Confirm that only the selected track's exact occupied pitches remain visible, visible scale-member lanes are tinted, and exception rows remain untinted.
6. Move the final note away from one occupied pitch and confirm its row disappears only after release.
7. Nudge a mixed in-scale/off-scale selection and confirm collision-free diatonic destinations.
8. Change the selected track and confirm both toggles remain enabled and Fold rebuilds with the incoming track's occupied rows.
9. Disable Highlight and confirm Fold remains enabled, the occupied rows remain, and their purple tint is removed.
10. Disable Fold and confirm Highlight remains disabled and the full chromatic layout returns.
11. Close and reopen the tab and confirm C Major with both toggles disabled is restored.
