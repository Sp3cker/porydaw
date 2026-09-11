# Editing Notes in the Piano Roll

<!-- The heart of the manual. Every gesture gets a short GIF or screenshot.
Remind early: everything here is undoable (Ctrl+Z), and notes audition live
as you draw/drag. -->

## Selecting a track to edit

<!-- TODO: Click a track header; the active track is full-color and
editable, other tracks are ghosted for context. -->

## Drawing notes

<!-- TODO: Click-drag to draw; the snap grid; how the drawn length follows
the grid; live audition while drawing. -->

## Moving and copying notes

<!-- TODO: Drag to move (pitch + time), modifier for fine/unsnapped moves,
duplicate gestures. -->

## Resizing notes

<!-- TODO: Grab an edge to lengthen/shorten; the effective (quantized)
length shown inline — what the GBA will actually play. -->

## Selecting multiple notes

<!-- TODO: Box select, Shift/Ctrl click to add, Ctrl+A, clear selection;
edge-drag and velocity-drag operate on the whole selection. -->

## Velocity

<!-- TODO: What velocity is (link to DAW Basics); the Ctrl/Cmd+vertical-drag
gesture; the quantized effective value shown inline; View → Color Notes by
Velocity for seeing dynamics at a glance (purple = soft, red = loud). -->

## Deleting notes

<!-- TODO: Delete/Backspace, eraser gesture if applicable. -->

## Cut, copy, paste, and range edits

### Time selections and scope
You can create an active, half-open time selection (`[start, end)`) across a span of beats in the timeline ruler, the piano roll canvas, or the automation lanes drawer. Time operations operate strictly on this active selection span and its editing scope.
Covered notes and automation nodes use the normal selection highlight without becoming an explicit note or node selection. Notes are covered when their sounding interval intersects the selection; automation nodes use the selection's half-open tick boundaries.

- **Plain ruler drag**: Selects time on the current primary track only, replacing any previous multi-track scope.
- **Cmd-drag on macOS / Ctrl-drag elsewhere**: Selects the primary track plus every track with a note whose sounding interval intersects the ruler range. Covered ghost notes receive the selection highlight, and their secondary track headers show the normal multi-selection indicator.
- **Track scope**: Existing time selections continue to use the selected track headers as their editing scope.
- **Whole-song scope**: When all used tracks are selected, time operations affect every track across the entire project.
- **Lane-only scope**: When a time selection is made directly within an automation lane in the drawer, time operations apply only to the selected automation lanes, leaving notes and other tracks untouched.

### Time editing commands
**Insert Time** (`Ctrl+Shift+I`, or `Cmd+Shift+I` on macOS) is selection-aware:
- **With an active time selection**: inserts a silent gap exactly the duration of the selection, immediately and without prompting. The selection's resolved scope (track, multi-track, whole-song, or lane-only, as described above) determines what shifts right; notes crossing the start seam are split cleanly so the inserted interval stays completely silent. The time selection remains over the newly created blank space, and the edit cursor is placed at the start seam. An active selection whose scope cannot be resolved rejects the command silently, without opening the prompt.
- **Without a selection**: opens three draggable number fields for bars, beats, and quarter-beat fractions, then inserts that duration across the whole song at the live playhead (or at the edit cursor while stopped).

**Delete Time (Shift Left)** is available from the Edit menu and both time-selection context menus (by default it has no keyboard shortcut). It removes the active time selection's whole time span — contents plus duration — and shifts all later scoped notes and automation left by that amount. Afterward the selection clears and the edit cursor is parked at the start seam. Without an active selection, or with a selection whose scope cannot be resolved, the command does nothing (no prompt, no edit). **No confirmation prompt is shown**; undo (`Ctrl+Z`) restores the previous song in one step. There is also no default destructive keyboard shortcut for it.

When a time selection is active, both right-click context menus (the timeline ruler, and inside an active time selection on the piano roll canvas or in an automation lane) offer the insertion and ripple-removal commands above, alongside:

- **Duplicate time** (`Ctrl+D` default, or `Cmd+D` on macOS): Copies all scoped content within the active time selection and inserts it immediately after the selection span, shifting later scoped content to the right. Automation streams cleanly seed their effective values at the destination seam. After duplicating, the time selection automatically advances to the newly created duplicate region (and the edit cursor commits to its end), allowing rapid repetition by pressing `Ctrl+D` repeatedly. Requires an active time selection.
- **Cut range** / **Copy range** / **Delete range** / ordinary `Delete`, `Backspace`, and Cut: These clear only the **contents** within the selection — the notes, automation points, and tempo markers inside the span are removed, but later events stay put; time never collapses. In contrast, Delete Time (Shift Left) removes the selected **duration** itself and ripples later content left. Ordinary Delete intentionally does not reassign to the rippling command.
- **Paste at edit cursor**: pastes previously copied range data starting at the current edit cursor position.
- **Clear time selection**: Clears the current time selection band.

All time editing operations are undoable as a single command on the undo stack (`Ctrl+Z`).

## Snapping and the grid

<!-- TODO: Choosing the snap resolution; when to turn snapping off;
the song's clock base and why some fine positions round. -->

## Undo and redo

<!-- TODO: One undo stack for everything — notes, automation, song settings,
even instrument edits. Undo history survives switching tabs? (verify). -->
