# Splitting Drumkits and Key Splits

Choose **Tools → Split Studio…** to open Split Studio. It needs an open project
with a song. There is one Split Studio window for the whole app, and it is
bound to the song and voice slot it opened from. The title shows the song and
voice number, with a `•` while the window has changes that have not been saved
to the song.

Press **Cmd+S** on macOS or **Ctrl+S** on Windows/Linux while Split Studio has
focus to save to the song. Press **Cmd+Z** on macOS or **Ctrl+Z** on
Windows/Linux to undo a window edit, and the matching redo shortcut to redo it.
Window undo dies with the window.

## Layout

The sample library sits on the left, the waveform slicer on the top right, and
the key-range editor on the bottom right. Both dividers drag, and Split Studio
remembers the window size and divider positions between sessions.

## Choosing a line

**Line in Voicegroup** lists the song voicegroup's drumkit and keysplit lines.
Empty lines offer **Line N · empty — new kit…**, which creates the kit's
voicegroup file (and its keysplit table, if you save the Keysplit layout) when
you save.
Converting a non-kit voice into a kit is not offered here; do that in the
voicegroup dock instead.

## Drumkit or keysplit

The **Zone layout** buttons, at the top of the zone editor, switch only that
editor; a caption under them explains the selected layout. Both layouts keep
their edits while the window is open, so you can sketch in one and finish in
the other. The layout selected when you save decides what is written to the
song.

Settings the other mode cannot store stay in the zone but their editors show
disabled: pan can only be stored in Drumkit mode. Keysplit mode is always
pitched — the engine pitches each child from the incoming key — so the Pitched
control shows on and disabled there, while your stored per-zone settings are
kept for Drumkit.

## Slicing samples

Each imported source gets its own tab above the waveform and keeps its own
markers, slices, and sample rate. Double-click the waveform or press **M** to
add a marker at the cursor, drag a marker tab to move it, and press **Delete**
or use the tab's context menu to remove it; removing a boundary merges the two
neighboring slices. Drag-select a region and choose **Slice selection** to make
one slice exactly that region. Marker placement is free: there is no beat grid.

Snap to zero crossing is on by default and pulls added or dragged markers to
the nearest sign change within about 3 ms. Each rendered slice also gets a
declick fade baked in: fade-out is on by default and never longer than 4 ms or
half the slice, fade-in is off by default to preserve attacks, and each slice
can override both. Slices are named `<source>_NN` from the first free number
and can be renamed under Sample Studio's naming rules. Each source has its own
target sample rate: the source rate when it is GBA-ready, otherwise the usual
GBA default.

A slice that a key range uses cannot be removed, and a source with a slice in
use cannot be closed. Remove those zones first.

## Mapping keys

Drop a slice (or a library sample) onto a key to create a zone. In Drumkit
mode the zone is one key; in Keysplit mode it extends to the start of the next
zone, or key 127. Zones never overlap: dropping onto an occupied range is
rejected with a status message. Drag a zone's edges to resize it and its body
to move it.

**Place all slices on the keyboard, starting at key** fills consecutive keys
with the source's slices in order — one key per slice in Drumkit, one run per
slice in Keysplit — with a white-keys-only option that skips black keys. The
note name of the start key shows beside it. **Keyboard zoom** widens or narrows
the keys.

The selected zone's strip shows the sample name, the note it plays at, the
pitch toggle, pan (Drumkit only), and attack, decay, sustain and release, each
with a small caption. Zones read from the project whose voices are synth
voices rather than samples (for example Square 1 or Noise) show their voice
type and can only be deleted here.

## Auditioning

Click a slice to hear the rendered slice. Click a key in the zone editor to
hear the unsaved draft through the game audio engine, with the zone's
pitch, pan, and envelope applied. There is no live MIDI input.

## Saving to the song

**Save to Song** writes the kit as one song undo step: the slice `.wav` files
plus their registrations are written immediately, then the kit itself (parent
slot, sub-voices, and the keysplit table in Keysplit mode) is applied. The
song becomes unsaved; write it to disk with the normal song save. Slice files
and registrations stay on disk even if you later undo the song step. A
re-saved slice whose audio changed overwrites its file; slices you renamed
leave the old name behind as an unused file that cleanup can offer to delete.

Kits created in previously empty slots also get their new voicegroup file
skeleton (and new keysplit table, in Keysplit mode) written at save time.

Window edits have their own undo stack, separate from the song's undo history.
**Cmd+Z** on macOS or **Ctrl+Z** on Windows/Linux inside Split Studio undoes a
window edit, never a song edit.

## When the song changes underneath

If the song edits your kit while your draft is clean, Split Studio reloads
silently. If your draft has unsaved changes, a **Changed in the song** bar
offers **Reload** (take the song's version) or **Keep mine** (keep drafting).

Switching the song's voicegroup prompts **Save to Song** / **Discard** / **Cancel** first, but only while Split Studio holds unsaved changes for that song. After switching, Split Studio follows the same slot number in the new voicegroup and shows a `Voicegroup changed to …` bar with a **Switch back to …** button. Switching back never prompts. If a switch fails, the current kit stays and a status line reports the failure. A
non-kit slot in the new voicegroup shows the empty-slot picker state.

## Closing

Closing with unsaved changes — the window close button, **Cmd+W** on macOS or
**Ctrl+W** on Windows/Linux, the song tab close, project close, or quitting
the app — asks **Save to Song** / **Discard** / **Cancel**. Saving suspends the
close until the save settles; Cancel aborts it; Discard proceeds. On quit there
is no abandon path: the app waits for the save. The Split Studio prompt runs
before the song's own save prompt.

## Shared kits

When the kit's voices or table are also used by other voicegroups, Split
Studio shows **used by N**. Copy is the default: saving snapshots the voices
(and table) under fresh names and repoints only your slot. Editing everywhere
instead changes every voicegroup that shares them.

## Cleaning up unused slices

Only files Split Studio made during this app session, which no voicegroup
references, are ever offered for cleanup. Closing the Split Studio window
never offers it. Closing the song tab, closing the project, or quitting offers
a checklist — everything checked — with **Delete** / **Keep**. Delete removes
the `.wav` files and their registrations. A file that gained a reference since
the list was built is kept instead, and a status line names the skipped files.
