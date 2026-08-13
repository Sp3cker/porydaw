# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## Added
- There is now buffer space before the start of the song in the piano roll to make it easier to scroll and focus the start of the song. Similarly, there is now much bigger buffer after the end of the song.
- Added a Pencil Mode for the automation lanes, toggled with the B key. While it's on, dragging always draws freehand, and holding Shift locks the stroke to a horizontal line. A quick tap of the key toggles the mode; holding it (or drawing while it's held) makes the switch momentary, reverting when the key is released.
- Holding Shift while dragging an automation point now locks the drag to one axis, chosen by the initial drag direction: horizontal keeps the value exact while moving in time, vertical keeps the tick while changing the value. Releasing Shift mid-drag returns to a free drag. Shift+click directly on a point now starts this constrained drag; the Shift line ramp still starts anywhere else in the lane.
- The automation lanes' right-drag time selection now selects the points it covers: selected nodes show a highlight ring (already while the band is being swept), and when several are selected, nodes in other lanes dim so the selection reads at a glance. Dragging a selected point moves the whole selection — across lanes — by one shared time/value offset as a single undoable edit, with a live preview and the selection following the move; dragging a point outside the selection still moves just that point. Delete or Backspace removes the selected points in one step, leaving everything outside the range untouched.
- Right-clicking an automation point now opens a small menu (Set value…, Delete) instead of deleting the point outright. The point under the cursor is targeted — with same-tick duplicate points, the one under the cursor's y, not just the nearest in time. Set value… opens the same type-in as double-click, seeded with the targeted point's value (typing a value leaves the tick holding that one value, as value edits always have); Delete removes exactly the targeted point. The targeted point shows a highlight ring while the menu is open, and right-clicking another point moves the menu there in one gesture, like the piano roll's note menu. Right-clicking a voice marker still deletes it directly.
- Automation lanes can now be hidden from their gutter menu ("Hide lane"). The lane's events are kept — only the row disappears — and the "+ Add lane" menu gains a "Hidden lanes" section that restores it. Hidden lanes are remembered per song. The "+ Add lane" strip also opens on right-click now, and a lane added without any events now has a working gutter menu.

## Fixed
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
