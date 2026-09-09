# SongView pan performance — 2026-09-04

Investigated the Debug build at `e4a9b9b` on macOS after the
`feature/songview-layout-refactor` merge. 
## Findings and changes

- `timelinequickscene.cpp` generated every dash along an automation selection
  before clipping each primitive. Work grew with the selection's offscreen
  extent, even though the viewport and visible dash count stayed fixed.
  Dash generation now skips complete offscreen periods and stops at the clip
  edge. This preserves the original dash phase. The piano roll's duplicate
  horizontal dash loop now uses the same bounded implementation.
- `automationquick.cpp` and `voicechangequick.cpp` emptied their text models
  before publishing each new frame. This defeated the models' existing keyed
  reconciliation and destroyed/recreated QML delegates on every pan. Each
  refresh now publishes once; invalid or empty content still clears its model.
- `TimelineCanvas.qml` clipped ordinary labels twice and clipped each band
  above its separately clipped gutter and plot. Those redundant clips are
  removed. Custom lane clips remain. `TrackHeaderBand.qml` also dropped an
  identical nested viewport clip.
- Offscreen velocity circles and rings went through trigonometry and triangle
  clipping on every pan. Their bounds now reject offscreen shapes first.
  Fully contained triangles bypass polygon clipping; crossing triangles keep
  the existing clipping path.

The dash loops and text-model resets **predate the layout merge**. These are
reproduced slow-pan defects, not proof that the merge introduced the user's
exact eventual slowdown. Ordinary repeated pans did not show progressive
growth in the runs below. The original sequence remains unconfirmed.

## Regression check

Run `deno task verify --no-windowing-checks --filter timelinepancheck --verbose`.

The current offscreen regression is `TimelinePanTest` in
`src/checks/timelinepan/tst_timelinepan.cpp`. It loads the checked-in Route
101 fixture, uses its offscreen Quick surface, and verifies actual camera
movement, unchanged gutter-model rows, and visible dash geometry against the
former full-walk algorithm, including fractional origins and clip crossings.

For the performance stress case, it compares four beats with 65,536 beats at
640 pixels per beat. This deliberately large selection exposes dependence on
offscreen width; it does not represent a typical song length. The check
permits generous timing slack and reports the raw durations.

Before the fixes: short pan **7 ms**, long pan **424 ms**, with **104 row removals
and 104 insertions** over the probe. Bounding dash generation alone changed
the long pan to **9 ms**, while the label assertion still failed. Retaining
the text records then brought removals and insertions to **zero**.

## Further optimization measurements

Compared saved Debug check binaries with and without the geometry and QML clip
optimizations, after applying the dash and label fixes to both. Both used the
same `mus_lovely` input from `/Users/spencer/dev/hearth-test`, a 1280×800 SongView,
all drawer sections visible, note-name mode enabled, and no audio playback.

A temporary probe sent middle-button pans and captured each completed Quick
frame. Each run contained six batches of 120 pans, alternating 4 and 200 pixels
per beat. Ran baseline/candidate three times in alternating order. There was
no separate timed warmup; initialization and the existing window check preceded
the batches. Values below are mean process CPU seconds per 120-pan batch.

| Zoom | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| 4 pixels/beat | 1.7923 s | 1.0014 s | 44.1% |
| 200 pixels/beat | 1.2667 s | 0.6266 s | 50.5% |

The captured before/after frames were identical across all 4,024,320 pixels.
These measurements include forced frame readback and are not playback CPU
measurements. They establish the combined gain, not the gain of each individual
clip removal. A CPU sample before the optimizations identified velocity circle
tessellation/clipping and QML delegate construction in the pan refresh path.

A separate 30-second run used ordinary event-loop rendering with an 8 ms input
timer, the long selection, and all drawers visible. Its six five-second samples
used 2.320, 2.330, 2.340, 2.330, 2.292, and 2.561 CPU seconds, producing
586, 587, 592, 593, 585, and 561 frames respectively. No stationary gutter rows
were removed or inserted. This does not establish behavior over hours or across
song/tab switching.

## Background and resume investigation

A temporary event-loop probe panned at an 8 ms input interval, covered the
SongView for 10 seconds, uncovered it, resized it, hid it for 10 seconds, and
panned again. It used the real Quick window and `mus_lovely`, with all drawer
sections visible and no audio. It counted `frameSwapped` signals and process
CPU time without framebuffer readback during the timed phases.

The command-line check reproduced a sustained drop after the complete sequence.
A representative run went from 607 frames in 5.247 seconds to 265 frames in
15.010 seconds (115.7 to 17.7 FPS). Process CPU rose from 0.451 to 0.917 seconds
per wall second. A resize after show did not fully restore performance in an
earlier run. Removing the cover phase left only a brief stall, followed by
roughly the original frame rate.

A sample of the sustained slow period placed most GUI-thread work in
`TimelineQuickView::flushUpdate`; the render thread mostly waited. Temporary
counters showed fewer refreshes, but each refresh took much longer. This was
not evidence of accumulated QML delegates or an increasing refresh count.

**The desktop was locked.** Computer Use could not inspect or activate the app,
and Qt reported `ApplicationInactive` throughout. Launching the exact same
instrumented binary through a temporary macOS app bundle stayed smooth:
581 frames in 4.996 seconds before the sequence, and 1,774 frames in 15.003
seconds afterward (116.3 and 118.2 FPS). CPU per wall second remained about
0.66–0.68. Therefore the command-line result cannot establish the cause of the
user's slowdown after returning to the foreground app. OS scheduling remains
an unconfirmed explanation; no App Nap or Metal workaround was added.

An experiment coalesced scene rebuilds at Qt frame preparation instead of a
zero-delay timer. It improved the slow command-line run, but changed the timing
assumptions of retained-scene checks. That experiment and its test changes were
removed. The final patch retains only the independently reproduced dash,
text-model, geometry, and QML clip changes above.

The exact foreground return sequence was never re-tested: the desktop was
locked during this investigation, and the Release profiling below ran with
the application inactive. Every temporary artifact from these probes — the
focus logs, CPU samples, traces, capture XML, PNG frames, saved check
binaries, and metrics files — has since been removed; the temporary source
hooks, the temporary benchmark probe, and the app bundle are gone as well.

## Velocity axis text-model retention follow-up

A follow-up review found the velocity axis was the remaining
clear-and-repopulate path: `VelocityArea::rebuildQuickScene` emptied the
velocity text model before publishing each frame, destroying and recreating
its QML labels on every pan. Valid rebuilds now publish once and the model's
keyed reconciliation retains the rows; the invalid-output exits (empty band
bounds or absent band geometry) still clear the model.

An offscreen regression in `VelocityPageTest`
(`src/checks/drawerpresentation/velocity.cpp`) covers it: unchanged rebuilds
and camera-pan rebuilds must keep the axis rows with zero removals and
insertions, and a hide/show cycle must leave the rows correct. Hidden bands
defer publication, so the regression does not require a clear while hidden.
At this 2026-09-04 follow-up, the mouse-safe lane passed 57 offscreen checks,
including `velocity-page`, with 8 WindowSystem skips. That receipt is
historical: the current lane passes 75 entries (74 Qt suites plus the
production-startup process smoke) and skips 9 native entries.

A negative control confirmed the coverage: temporarily reintroducing the old
unconditional clear failed exactly the unchanged-rebuild and panned-rebuild
retention assertions, and restoring the fix returned the check to a pass.

### Native probe attempt (removed, no numbers)

A temporary opt-in probe in `timelinepancheck.cpp` tried to measure
stationary versus panning phases with native middle-drag input. It had a
timing-unit bug (microseconds reported as seconds), and the native input loop
timed out at high zoom. Replacing its repeating timer with a single-shot
timer did not eliminate the timeout. The probe was removed without producing
before/after numbers. Desktop-interacting checks were prohibited at the time,
so no native CPU or FPS before-after gain was verified for the velocity
retention change. Native checks and traces were permitted for the separate
Release pass below; that historical permission does not change the current
migration's mouse-safe verification boundary. A qualitative pan-stall sample placed
GUI-thread time in `TimelineQuickView::flushUpdate` → `syncVelocity` →
`VelocityArea::rebuildQuickScene` QML delegate creation; no percentage
attribution is claimed.

The 65-check totals in the following date-stamped profile section are
historical receipts for the measured branch state, not current suite totals.
They do not establish native performance proof; the current count is 75
passing offscreen entries with 9 native entries skipped by the mouse-safe lane.

## Release profile-driven pass (2026-09-05)

A temporary benchmark probe inside `timelinepancheck.cpp` drove a second,
profile-guided round on a Release build (the probe was removed after
measuring; the targeted check remains). Protocol for every number below:
`fightsong1` from `/Users/spencer/dev/hearth-test` loaded read-only, a real
1280×800 Quick window at device pixel ratio 2, no audio, 360 horizontal
camera updates per phase on an 8 ms timer at 24 px per update, 24 warmups,
and three phases per run — drawers open at 4 pixels per beat (`open-low`),
drawers open at 200 pixels per beat (`open-high`), and drawers closed at
200 pixels per beat (`closed-high`). CPU is process user-plus-system time
from `getrusage`, not wall time. Hover-cleared captures occur before the
warmup and outside the timed regions. Every phase required a nonempty
Other Events band and plot, matching the canonical layout.

### Changes

- `VelocityArea` note rebuilds cull each note with one merged stem-and-node
  extent before the note's displayed-velocity lookup and shape work, with
  loop-invariant widths and radii hoisted out of the note loop.
- Ellipses and rings scale a one-time exact unit-circle point table instead
  of recomputing trigonometry per shape per pan.
- Vertex colors are premultiplied and packed once per distinct primitive
  color, rather than per vertex. Geometry chunks are initialized once;
  shrinking clears only the newly unused suffix.
- In the QWidget implementation measured here, the SongView horizontal
  scrollbar re-asserted `WA_OpaquePaintEvent` after polish and style changes,
  which stylesheet polish cleared for boxed rules. The main window and
  `SongView` stopped repainting the scrollbar strip on every pan. The
  scrollbar still painted itself and the backing-store flush remained:
  paint logs showed 360 scrollbar-only paints per phase, where the baseline
  also painted the main window and `SongView` over the same strip.
  The main timeline and piano-roll scrollbars have since moved into the
  existing Qt Quick scene; the QWidget opacity workaround is removed.
- The time ruler runs its widest-beat-label measurement pass only at zooms
  where beat labels could fit, and builds and measures a beat label only
  after it passes the overlap rejection, so rejected labels are never
  shaped at low zoom. It also guards the grid passes against viewports
  wholly inside the pre-roll, whose tick range would convert negatively to
  `uint64_t`; such viewports now yield an empty grid range without losing
  ruler chrome or markers.
- `keymap::Registry` caches modifier bindings per command id and invalidates
  them through `setModifierBinding`, `resetBinding`, `resetAll`, and
  `restoreOverrides`, avoiding repeated `QSettings` access when bindings
  are queried.

### Measurements (application inactive)

The scrollbar change accidentally removed the Other Events layout spacer.
That invalidated the early active-desktop comparison, and the first
reconstructed inactive baseline inherited the omission. The numbers below
use a rebuilt baseline and final that both retain the spacer and the ruler
range fix. An earlier 5-second `xctrace` profile (17 MB) attributed GUI time to the ruler
rebuild and modifier lookups (`TimeRuler::rebuildQuickScene`,
`keymap::Registry::modifierBinding`), motivating those changes; its
samples span benchmark phases and out-of-timing frame hashing, so its raw
inclusive percentages must not be summed.

Nine baseline/final pairs ran on the rebuilt binaries: six in strict AB/BA
alternation plus three rotation triplets (baseline/final/no-opacity), with
the application inactive at every capture. Mean CPU per phase:

| Phase | Baseline | Final | Difference | Final lower in |
| --- | ---: | ---: | ---: | ---: |
| open-low | 1516.7 ms | 1344.8 ms | 11.3% lower | 9/9 pairs |
| open-high | 915.2 ms | 925.1 ms | 1.1% higher | 5/9 pairs |
| closed-high | 838.1 ms | 849.8 ms | 1.4% higher | 3/9 pairs |

The low-zoom gain is consistent: the final binary used less CPU in all
nine open-low pairs. No high-zoom gain is established — the high-zoom
means end slightly higher, the first six closed-drawer pairs ran higher
while the last three reversed without a source change, and individual
pairs overlap widely. A three-run no-opacity ablation of the scrollbar
change did not isolate a stable CPU effect either way. At that point, the
opacity change was retained because paint logs demonstrated ancestor paints
dropping from 360 to 0 per phase while the scrollbar still painted its 360.
These CPU measurements predate the Qt Quick scrollbar cutover. They are not
FPS measurements and cover one inactive window state; nothing here
establishes active-window behavior, per-pan-position costs, or multi-hour
behavior.

### Capture equivalence

Each phase captures once at its existing pre-timing position, not at every
panned position. All 21 runs matched identical normalized ARGB32 image
hashes across their three pre-timing captures (2560×1572 each), and every
capture ran with the window inactive. The first pair's optional PNG export
failed because its output directory did not exist; the in-memory captures,
hashes, and timings all succeeded, the directory setup was fixed for later
runs, and no timing samples were discarded.

### Status

The full AddressSanitizer/UBSan suite passed all 65 checks on the final
production sources (26.69 s). It exposed a negative ruler
tick-to-`uint64_t` conversion (fixed in production) and two test fixtures
that freed the old timeline before `updateSong` (test-only; production
`SongTab` was already safe). The ordinary Release gate then passed with
the original flags restored and sanitizers off: formatting checked across
the twelve affected C++ files, and `deno task verify --verbose` passed all
65 checks (6.53 s build, 21.06 s checks, 28.25 s total). A complete
low-zoom capture was also inspected to confirm the restored Other Events
row renders.

Temporary benchmark hooks, comparison and ablation binaries, PNGs,
standalone sanitizer logs, and the bounded `.trace`/XML exports were
removed. The permanent `timelinepancheck.cpp` remains 151 lines.

### Post-audit complexity reduction

The subsequent audit cleanup replaces the color-equality ladders with
straight-line packing: four logical corner colors per rectangle and three
per triangle. Repeated rectangle triangle vertices reuse their packed
corner colors. Premultiplication and vertex order are unchanged.

All three grid renderers now resolve raw viewport bounds through
`songview::detail::tickRange`. Its two integer bounds are consumed directly
by the subgrid walker, removing duplicate floating-point conversions.
The resolver rejects non-finite, reversed, and out-of-`uint64_t` bounds,
clips partial pre-roll to tick zero, and preserves fractional truncation.
The ruler continues rendering chrome and markers for empty grid ranges.

The CPU measurements above predate this cleanup; they are not a new
performance measurement of the branch-free color writers. The cleanup
passed all 65 checks under AddressSanitizer and UBSan, including new range
boundary regressions and the existing rendered-color/chunk lifecycle checks.
The restored ordinary Release build also passed all 65 checks (21.14 s),
and formatting passed for all six modified C++ files.

## Validation (2026-09-04, historical)

Passed 18 affected checks: `timelinepancheck`, `rollcheck`, `rollwindowingcheck`,
`trackheaderquickcheck`, `laneselectioncheck`, `host-seams`, `host-adapter`,
`host-integration`, `velocity-model`, `velocity-page`, `editor-drawer`, the three
`editor-layout` sizes, `automation`, `automation-gestures`,
`automation-popup-menus`, and `rendering-playhead`.

Temporary benchmark source hooks were removed. Production and checks were
rebuilt through `deno task`; no audio or project-loading code changed.
