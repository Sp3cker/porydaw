# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## Added
- There is now buffer space before the start of the song in the piano roll to make it easier to scroll and focus the start of the song. Similarly, there is now much bigger buffer after the end of the song.
- Added a Pencil Mode for the automation lanes, toggled with the B key. While it's on, dragging always draws freehand, and holding Shift locks the stroke to a horizontal line. A quick tap of the key toggles the mode; holding it (or drawing while it's held) makes the switch momentary, reverting when the key is released.
- Holding Shift while dragging an automation point now locks the drag to one axis, chosen by the initial drag direction: horizontal keeps the value exact while moving in time, vertical keeps the tick while changing the value. Releasing Shift mid-drag returns to a free drag. Shift+click directly on a point now starts this constrained drag; the Shift line ramp still starts anywhere else in the lane.

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
