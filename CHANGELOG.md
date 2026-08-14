# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## Added
- Added a velocity lane: a resizable pane between the piano roll and the automation lanes showing the selected track's notes as nodes on the timeline — a dot at each note's velocity with a stem across its length — beside a 1–127 value ruler. It is hidden until you turn it on with View → Velocity Lane or the V key, and the setting is remembered. Selected notes are ringed, with their velocities marked on the ruler; the lane pans and zooms with the roll. Dragging a node — or its stem — moves every selected note's velocity together, as one undoable edit applied when you let go; clicking selects (Ctrl adds or removes, empty space clears), and Escape abandons a drag in progress. Painting, ramps, marquee selection, and the PSG detents are not in yet.
- There is now buffer space before the start of the song in the piano roll to make it easier to scroll and focus the start of the song. Similarly, there is now much bigger buffer after the end of the song.
- Added a Pencil Mode for the automation lanes, toggled with the B key. While it's on, dragging always draws freehand, and holding Shift locks the stroke to a horizontal line. A quick tap of the key toggles the mode; holding it (or drawing while it's held) makes the switch momentary, reverting when the key is released.
- Holding Shift while dragging an automation point now locks the drag to one axis, chosen by the initial drag direction: horizontal keeps the value exact while moving in time, vertical keeps the tick while changing the value. Releasing Shift mid-drag returns to a free drag. Shift+click directly on a point now starts this constrained drag; the Shift line ramp still starts anywhere else in the lane.
- The automation lanes' right-drag time selection now selects the points it covers: selected nodes show a highlight ring (already while the band is being swept), and when several are selected, nodes in other lanes dim so the selection reads at a glance. Dragging a selected point moves the whole selection — across lanes — by one shared time/value offset as a single undoable edit, with a live preview and the selection following the move; dragging a point outside the selection still moves just that point. Delete or Backspace removes the selected points in one step, leaving everything outside the range untouched.
- Right-clicking an automation point now opens a small menu (Set value…, Delete) instead of deleting the point outright. The point under the cursor is targeted — with same-tick duplicate points, the one under the cursor's y, not just the nearest in time. Set value… opens the same type-in as double-click, seeded with the targeted point's value (typing a value leaves the tick holding that one value, as value edits always have); Delete removes exactly the targeted point. The targeted point shows a highlight ring while the menu is open, and right-clicking another point moves the menu there in one gesture, like the piano roll's note menu. Right-clicking a voice marker still deletes it directly.
- The automation lanes' readouts are sharper. Hovering directly over a point's dot now rings it, showing that a press will grab that exact point; hovering the Voice row shows the voice in effect at the cursor ("→ 001 name"), hidden right over a marker whose own label already names it; and while dragging (point moves, freehand sweeps, line ramps, pencil strokes), the pending value now renders on a small filled chip that stays inside the lane instead of bare text that could collide with the curve.
- Automation lanes can now be hidden from their gutter menu ("Hide lane"). The lane's events are kept — only the row disappears — and the "+ Add lane" menu gains a "Hidden lanes" section that restores it. Hidden lanes are remembered per song. The "+ Add lane" strip also opens on right-click now, and a lane added without any events now has a working gutter menu.

## Changed
- The automation lanes' arrow tool no longer draws. Clicking empty lane space moves the edit cursor instead of writing a point, and clicking a point deletes it (one undo step) — Shift+click still starts the constrained drag and leaves the point alone. Drawing is the Pencil Mode's job (B), and a pencil click still leaves a single point. Freehand sweeps now need a few pixels of travel before they start, and those pixels aren't drawn, so a click that wobbles in the hand leaves the song untouched. Since the click already removes the point, double-clicking one no longer opens the value type-in: double-click empty lane space to type a new point's value, or use the point menu's Set value… on an existing one.

## Fixed
- With the velocity-drag chord held (Ctrl by default), adjusting one note's velocity and then dragging on a different note no longer nudges both: the second drag switches the selection to the new note and adjusts it alone. Repeating the drag on the same note still nudges the whole bulk selection, and releasing the modifier (or leaving the window) restores the join-and-nudge behavior.
- Improved fidelity of CGB channels
   - Fixed CGB channels' volume envelope emulation.
   - Improved CGB noise channel is now band-limited, which is more accurate to hardware's sound quality.
   - m4a's master volume is now set to 12 instead of 15, which matches the Pokemon games. This fixes the loudness imbalance between directsound and CGB channels.
- UI text now renders unhinted and antialiased. Hinting distorted the bundled typeface on Windows at 100% scale, where it was rendered jagged instead of with its designed letterforms. The bundled fonts' own rendering hints (gasp tables) were corrected to request the same smooth rendering from renderers that consult the font.
- Toggling View → Use System Font no longer restyles the whole window through the theme engine — a repaint hazard on Windows while playback was painting. The font swap now lands directly.
- Fixed bug where the right edge of a note couldn't be grabbed for resizing when two notes were adjacent.
- Edits that change nothing (a move fully absorbed by the tick/key clamps, a velocity write already at its target) no longer push undo entries, and a keyboard move gesture that lands back where it started leaves no undo entry at all.
- Fixed bug where duplicating a track copied every channel's events from its chunk; on imported files that interleave several channels in one chunk, other tracks' notes were duplicated too.
- Moving or resizing notes now re-inserts the original MIDI events instead of rebuilding them, so unmodeled bytes (like a note-off's release velocity) survive those edits.
- Fixed bug where velocity values could visually bleed out of the note box.
- The MIDI event list now stays on the chunk it is showing when tracks are added, deleted, or reordered (including through undo/redo); previously it could silently jump to a different chunk. Deleting the viewed chunk's own track falls back to the selected track's chunk.
- Freehand sweeps and Shift line ramps in the automation lanes now follow the grid across a mid-song time-signature change; previously points past the change kept the old meter's grid spacing and could land off the new grid.
- The Ctrl center-snap in the automation lanes (pan/tune center, zero bend) now derives its magnet window from the UI font size and the lane's height instead of a hard-coded 8 pixels, so it stays proportionate at any font scale and lane size.

## [1.0.0] - 2026-08-01
Initial release.

[Unreleased]: https://github.com/huderlem/porydaw/compare/1.0.0...HEAD
[1.0.0]: https://github.com/huderlem/porydaw/releases/tag/1.0.0
