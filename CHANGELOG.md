# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## Added
- There is now buffer space before the start of the song in the piano roll to make it easier to scroll and focus the start of the song. Similarly, there is now much bigger buffer after the end of the song.
- Press `G` with one note selected to edit its channel-wide pitch bend: scroll the graph for a note-scoped BENDR range, hold `Option`/`Alt` for angled lines, reset to zero, and audition from note-on with `Space`. The popup stays open until click-away or `Escape`.

## Changed
- Render the main timeline and piano-roll scrollbars in the existing Qt Quick scene, using the shared scrollbar control and the camera's fractional scroll positions.
- Resonance suppression now uses a 150 ms default attack for faster response to ringing and whistles.

## Fixed
- Double-clicking a tempo or CC automation node now deletes it once without opening an unintended value dialog.
- Keep automation and track-header scrollbar thumbs inside their tracks during dragging, including when the content reaches an endpoint.
- Keep velocity notes and PSG level bands aligned with the shared timeline camera during scrolling, zooming, and fractional display scaling.
- Centralized safe grid tick-range conversion across the piano roll, banded grids, and time ruler. Pre-roll, non-finite, reversed, and out-of-range bounds produce empty grids without losing ruler chrome or markers.
- Fixed audible click on transport transitions (pause/stop/play): the output now fades down, cuts, and fades back instead of hard-cutting sounding channels at full amplitude.
- Fixed WAV export bypassing resonance suppression when the transport action was enabled.
- Improved fidelity of CGB channels
   - Fixed CGB channels' volume envelope emulation.
   - Improved CGB noise channel is now band-limited, which is more accurate to hardware's sound quality.
   - m4a's master volume is now set to 12 instead of 15, which matches the Pokemon games. This fixes the loudness imbalance between directsound and CGB channels.
- Fixed bug where the right edge of a note couldn't be grabbed for resizing when two notes were adjacent.
- Fixed bug where velocity values could visually bleed out of the note box.
- Avoid recreating velocity-axis QML labels during panning by retaining unchanged model rows; still clear labels when the axis has no valid geometry.
- Reduced low-zoom SongView panning CPU: velocity notes are culled before per-note lookups, circles reuse one-time exact unit-circle points, Quick geometry chunks use packed colors with incremental clearing, low-zoom ruler labels skip measurement/shaping, and keymap modifier lookups are cached with invalidation on mutation.
- Simplified Quick rectangle and triangle color packing to straight-line per-corner operations, removing nested color-comparison branches.

## [1.0.0] - 2026-08-01
Initial release.

[Unreleased]: https://github.com/huderlem/porydaw/compare/1.0.0...HEAD
[1.0.0]: https://github.com/huderlem/porydaw/releases/tag/1.0.0
