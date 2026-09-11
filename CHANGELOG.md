# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## Added
- There is now buffer space before the start of the song in the piano roll to make it easier to scroll and focus the start of the song. Similarly, there is now much bigger buffer after the end of the song.
- Press `G` with one note selected to edit its channel-wide pitch bend: scroll the graph for a note-scoped BENDR range, hold `Option`/`Alt` for angled lines, reset to zero, and audition from note-on with `Space`. The popup stays open until click-away or `Escape`.
- Insert Time is now selection-aware: with an active time selection it inserts a silent gap the length of the selection immediately (no prompt), honoring the selection's resolved scope, keeping the selection over the new blank span, and committing the edit cursor to the start seam; without a selection it still opens the bars/beats/fractions prompt for a whole-song insertion at the cursor.
- The Edit menu and both time-selection context menus now offer Delete Time (Shift Left) (`edit.delete_time`, no default binding): it removes the active selection's whole span and shifts later scoped content left, clearing the selection and parking the edit cursor at the seam, with no confirmation and one undo step. Context menus show Insert Time / Delete Time (Shift Left) with the registry shortcuts; ordinary Delete, Backspace, and Cut remain contents-only and never shift time.

## Changed
- View menu, drawer toggles, and show/hide announcements now say Automation drawer, Velocity drawer, and Voice-change drawer.
- Remove the test-only automation inverse API and redundant single-lane renderer collection; share Quick visual lookup across affected checks.
- Reuse the timeline's Quick popup session for note automation without a separate native window. The pitch editor owns its note anchoring, resize layout, live-edit dismissal, and click-away routing; the shared session owns hosting and lifetime rather than configurable pitch policies.
- Share prompt appearance and card/button chrome; remove obsolete Event List MIME drag/drop, drawer QAction shims, and the unused QuickWidgets dependency. Consolidate header checks while retaining their distinct behavior coverage.
- Expose selection-keyboard routing checks as independently selectable Qt Test cases with isolated fixtures.
- Run header-model, playhead-guide, and selection-keyboard core checks offscreen while preserving independent cases and fresh fixtures. Remove redundant native checks; make the native pan timing diagnostic opt-in. Anchor native test hosts in the bottom-right screen corner and explicitly stage focus and hover movement instead of relying on preceding cases.
- Consolidate duplicated check coverage: the keymap conflict matrix runs one case per command across all four routed contexts, velocity roll-drag regressions share a staged setup, and vacuous or duplicated selection and cancellation assertions were repaired or removed.
- Route note keyboard commands by selection across timeline drawers, while text editors and keyboard-focused grips and scrollbars retain their local keys.
- Render the main timeline and piano-roll scrollbars in the existing Qt Quick scene, using the shared scrollbar control and the camera's fractional scroll positions.
- Resonance suppression now uses a 150 ms default attack for faster response to ringing and whistles.
- Deleting a nonempty automation CC lane now asks for confirmation in an in-scene Quick form where `Cancel` starts with keyboard focus. Populated default Volume/Bend rows keep their default row and delete only written CC events; the prompt states the written-event count and that the default row remains, and ordinary document Undo restores the deleted events in that retained row.
- The automation node context menu (`Set Value`, `Delete`) now uses the shared in-scene Quick menu: Escape and outside clicks dismiss it, an outside right-press retargets it to another node, and stale or replaced targets can no longer write. `Set Value` opens the inline value prompt, and `Delete` is disabled while the clicked node is only an engine default with no written event at its tick (Set Value still creates one). Aborted opens treat the node hit as consumed to prevent unintended background fallbacks, and newer popups published during open callbacks are protected from displacement.
- Moved the drawer voice-change menu to the shared in-scene Quick menu. Camera moves do not change its target; outside right-click dismisses without retargeting. Hiding or detaching the lane cancels its picker, and stale edits cannot overwrite newer changes or displace another popup.
- Host the timeline, ruler, event list, and editor drawers in one Qt Quick viewport. SongView and drawer layout no longer depend on hidden QWidget spacers; only the SongTab embedding boundary remains widget-based.
- Group the automation parameter selector into two columns of related parameters — Volume/Pan, Modulation/Pitch bend, LFO speed/Bend range, and the two echo lanes — with song-global Tempo closing the grid on its own row. The grouped grid needs less drawer height than the previous single-column list.
- Replace the always-prompt Insert blank time command with selection-aware Insert Time (`edit.insert_time`, `Ctrl+Shift+I`): an active selection inserts immediately while an active but unresolvable selection rejects silently rather than falling through to the whole-song prompt. Remove Time contents was renamed Delete Time (Shift Left) in both context menus but keeps its guarded, silent no-op behavior.

## Fixed
- Retain stationary timeline gutters and velocity axes while panning; draw only populated geometry vertices, and preserve full refreshes when layout or content changes.
- Rebuild piano pitch-row shading and time-grid lines independently during panning, zooming, and grid or scale changes.
- Refresh timeline pixel snapping, text, and cursors when moving between displays with different pixel ratios.
- Avoid rebuilding and reshaping unchanged track-header labels on every playback update; refresh them when the program or header presentation changes instead.
- Batch fitting timeline labels together instead of giving each label a separate clip; retain clipping for overflowing text and lane boundaries.
- Keep tempo curves and nodes visible above the plot header background.
- Wait for the first rendered layout before drawer fixtures snapshot geometry, and activate Pan before Pan prompt scenarios.
- Do not revive a rejected pre-roll hover guide during later timeline synchronization.
- Initialize empty voicegroup fixtures before binding them in host and window lifecycle checks, preventing intermittent invalid-pointer crashes.
- Prevent timeline cancellation from releasing a pitch-bend popup's mouse grab and corrupting undo history during an external document edit.
- Cancel active timeline gestures with Escape without clearing their captured selection; an idle Escape clears the selection.
- Keep automation pencil-hover Delete from overriding selected notes or a scoped time selection.
- Typing in Qt Quick text inputs no longer toggles the automation Pencil tool.
- Double-clicking a tempo or CC automation node now deletes it once without opening an unintended value dialog.
- Keep automation and track-header scrollbar thumbs inside their tracks during dragging, including when the content reaches an endpoint.
- Deleting a default automation lane that has no written CC events (engine-synthesized defaults only) no longer opens a no-op confirmation or counts projected default nodes as written events; it takes the plain empty-lane removal instead.
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
- Reduced low-zoom SongView panning CPU: velocity notes are culled before per-note lookups, circles reuse one-time exact unit-circle points, Quick geometry chunks use packed colors and exact draw counts, low-zoom ruler labels skip measurement/shaping, and keymap modifier lookups are cached with invalidation on mutation.
- Simplified Quick rectangle and triangle color packing to straight-line per-corner operations, removing nested color-comparison branches.
- Disabled rows in the shared Quick menu now expose the correct disabled state to assistive technology while clicks on them remain menu-contained.
- Keep a pressed popup row active when an external document edit cancels timeline gestures. Releasing the row still rejects its stale target rather than overwriting the newer edit.
- Close shared timeline popups when their song surface is hidden or becomes unavailable, and detach the Quick scene before its document and controller objects are destroyed.
- `Space` play/pause no longer appears focus-dependent: persistent Quick chrome does not claim bare `Space`, so the global transport shortcut fires while timeline controls have keyboard focus. Those controls activate with `Enter`/`Return`, pointer input, or accessibility press actions; modal prompts, text entry, and auditioning use keys locally as before.

## [1.0.0] - 2026-08-01
Initial release.

[Unreleased]: https://github.com/huderlem/porydaw/compare/1.0.0...HEAD
[1.0.0]: https://github.com/huderlem/porydaw/releases/tag/1.0.0
