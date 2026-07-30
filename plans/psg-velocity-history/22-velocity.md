# 22 — VelocityPage and VelocityArea

**Agent:** `task`  
**Setup Agent:** `git-operations-runner`  
**Branch:** `task/psg-velocity/velocity`  
**Worktree:** `22-velocity`  
**Base:** `FOUNDATION_SHA` — the coordinator-recorded, approved integration
commit after the 10A → 10B/11 → DOCUMENT_SHA → 10C and 12A/12B/13 → 14A/14B foundation DAG.
`git-operations-runner` creates/verifies the `22-velocity` worktree and `task/psg-velocity/velocity` branch at its exact `FOUNDATION_SHA` base and initializes/verifies submodules before the `task` agent begins. Product tasks (20, 21, 22, and 23) remain parallel only at `FOUNDATION_SHA`.
Start there exactly; do not depend on or absorb packets 20, 21, or 23.

## Exact independent ownership

This packet owns exactly these five paths:

1. `src/ui/velocitypage.h`
2. `src/ui/velocitypage.cpp`
3. `src/ui/velocityarea.h`
4. `src/ui/velocityarea.cpp`
5. `src/rollcheckpsgvelocity.cpp`

The fifth path is the velocity cpp-only focused harness; do not add a harness
header. Packet 05 conditionally registers precisely this complete group with
`PORYDAW_HAS_VELOCITY_PAGE_CHECK` and `porydaw --check-velocity-page <scratch-project> <song-label> [screenshot]`. Once all
five files exist on this branch, that command must compile and be runnable
here; no source/build/dispatch edit or later host integration is needed to
enable it.

Implement the module's `VelocityPage` atop, and consume without editing, the
generic Foundation `EditorPage`, `EditorPageContext`, `EditorPageHost`, and
`EditorViewState` contracts; `NoteId` and `SongDocument` revision/batch
contracts; layout; `PsgVelocityModel`; `VelocityAxis`; and the existing
`TimelineSurface` supplied by the context. It must not create or alter the
shared surface. Packet 30 exclusively owns concrete `SongView`/`MainWindow`
lifecycle wiring, and packet 05 alone owns central registration and dispatch.

The page/area consume shared selection, selected track, timeline transform,
scroll/zoom, edit cursor/playhead, theme, focus, and follow-scroll services.
They emit selection, note-status, view-action, invalidation, and lifecycle
requests through the generic page/context seam. They never create a selection
model, resolve voices, or render directly through host-owned widgets.

## Deliver

- Draw all primary-track notes and consume exact shared `NoteId` selection.
  Request plain track-header clearing through the host. Draw nodes, duration
  stems, selected treatment, watermark, narrow-width clamp, and layout-backed
  hit testing with no hover decoration.
- Render the continuous ruler from the foundation axis: endpoints, five density
  bands, selected/preview extrema, and static-label clicks. Use the foundation
  voice/context result to render intrinsic Square, Noise, and Wave graduations,
  one/two-column layout, labels, exact selected-value substitution, conflict
  fallback, watermark level message, and continuous placement for incompatible
  notes.
- Route every no-selection, playhead-driven velocity voice-context request
  through packet 11's sole static
  `uint64_t EditorPageContext::drawerContextTick(double)` helper and consume
  its returned tick. Do not introduce a velocity-local playhead conversion.
- Implement all page selection, relative-drag, categorical-drag, freehand,
  band, pan, and wheel behavior. Freeze selection, document addresses,
  revision, axis/context, coordinates, and exact starting values; display
  previews only; submit one revision-checked `setNotesVelocities` batch named
  `paint note velocities` at a successful release.
- Keep typed piano-roll `Set velocity…` as the only exact-entry route. Emit the
  first-pressed relative-preview note-status payload and exact continuous or
  intrinsic accessible description; route existing shared edit commands with
  click focus and add no focus targets.
- Own page/area lifecycle and content cache: cancel relative/freehand/band
  previews safely, pause/resume follow-scroll without moving frozen
  coordinates, use update rectangles, and expose module content-build,
  invalidation, and playhead-presentation counters. Routine playhead movement
  remains a host presentation request, not a content rebuild.

## Non-goals

Do not edit `EditorDrawer`, automation files, `SongView`, `MainWindow`,
`TimelineSurface`, `PlayheadOverlay`, `VelocityAxis`, `PsgVelocityModel`,
`ViewSidecar`, layout, foundation page/context/view-state headers,
`CMakeLists.txt`, `src/main.cpp`, or `src/editorcheckdispatch.h.in`. Do not add a
velocity context menu, velocity key nudge, tooltip, live region,
mixer-dependent graduation, broad paint culling, or unrelated playback/roll
fix.

## Edge cases

- Duplicate notes remain separately selectable through the opaque IDs; every
  mutation, Undo, Redo, reload, replacement, or revision mismatch cancels the
  gesture before a partial commit.
- DirectSound, missing/invalid/nested/keyless voice contexts and incompatible
  selections remain continuous. Mixed proposals canonicalize each PSG note via
  the foundation model while DirectSound remains exact.
- Returning to an intrinsic origin level restores its exact starting velocity;
  a move to another level uses that level's representative. Typed `95` stays
  exact although Wave displays its `96` class.
- Freehand stamps start nodes only, interpolates every crossed node, and maps
  incompatible notes continuously. Right pending-band suppresses its matching
  context menu and honors stationary plain/Ctrl blank behavior.
- Cancellation clears preview, cursor/grab, and provisional selection without
  MIDI or Undo residue; pan retains its applied scroll. Playhead-only updates
  do not rebuild cached content.

## Focused checks and acceptance

Write only velocity cases in `src/rollcheckpsgvelocity.cpp` for shared
duplicate-note selection and track-header clearing; continuous and intrinsic
drawing, hit testing, ruler clicks, selection/band behavior, mixed context,
exact-origin restoration, freehand interpolation, stale rejection, one-command
Undo, lifecycle, command routing, status payload, accessible text, and no
extra focus targets. Add the module cache counter proof: after warmup, 120
on-screen playhead updates leave both content-build counters unchanged, end at
the requested tick, and each edit/selection/zoom/scroll/resize/theme/document/
voice change invalidates the affected page.
Under **VEL-03**, with no selected note and a continuous-axis voice context,
at negative, below-half, half-tick, and above-half playback inputs, set the
expected query tick by calling `EditorPageContext::drawerContextTick(playhead)`
and assert the context request receives that returned tick. Under **VEL-04**,
repeat that static-helper assertion for intrinsic Square, Noise, and Wave
contexts.
Exercise geometry and hit-test behavior only through `porydaw --check-velocity-page <scratch-project> <song-label> [screenshot]`; no repository-wide
geometry source audit belongs to this packet.

This packet owns **VEL-01**, **VEL-02**, the UI portions of **VEL-03** and
**VEL-04**, **A11Y-01**, velocity portions of **LIFE-01**, **PERF-01**, and
**UX-05...UX-09**. Packet 13 owns the pure model assertions and packet 30
proves host-integrated status/playhead wiring. No full native suite, formatter,
linter, or review gate belongs here.

## Downstream host integration

The four product heads merge normally only after their reviews, producing
`PRODUCT_SHA`. 30C then starts from `PRODUCT_SHA`, owns the generic dynamic
timeline-band API and overlay-only playhead presentation, and undergoes review
against `PRODUCT_SHA..30C_HEAD`; its approved ordinary merge records
`RENDERING_SHA`. 30A then starts from `RENDERING_SHA`, constructs the page/area
through the generic host, and owns SongView lifecycle, exact revisioned
velocity forwarding/no-op/stale results, and dynamic-band requests; its review
is against `RENDERING_SHA..30A_HEAD`, and its approved ordinary merge records
`ADAPTER_SHA`. 30B then starts from `ADAPTER_SHA`, owns public MainWindow A/V
routing and persistence, and undergoes review against `ADAPTER_SHA..30B_HEAD`;
its approved ordinary merge records `HOST_SHA`. This packet does not edit or
preempt any of those host paths.

## Commit handoff

The task agent implements the owned production paths and focused harness, then
makes one ordinary commit on `task/psg-velocity/velocity`; it does not build,
run checks, format, lint, or review. After the parallel product commits, the
coordinator runs `porydaw --check-velocity-page <scratch-project> <song-label> [screenshot]` once on this complete group
before parallel review. Hand off the commit SHA, changed-file list, consumed
model/host interfaces, gesture and cancellation matrices, counter report, and
status/accessibility evidence. Do not use staged-tree transport or modify
integration.
