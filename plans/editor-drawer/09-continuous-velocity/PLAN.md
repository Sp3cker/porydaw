# Task 09 — Add the continuous velocity page

**Blocked by:** Reviewed and integrated Task 08.

**Task-agent worktrees:** `09a-axis-selection`, then
`09b-gestures-status-perf`.

**Task-agent plans:**

- [09A axis and selection](09a-axis-selection/PLAN.md)
- [09B gestures, status, and performance](09b-gestures-status-perf/PLAN.md)

**Target slice:** Specification implementation slice 9.

**Suggested subject:** `Add continuous velocity editing`

## Start rule

Record the accepted Task 08 integration SHA as `LOGICAL_START_SHA`. Task 09A
starts there. After its staged tree passes Review, the coordinator creates a
task-local transport commit with that exact tree. Task 09B starts from that
transport commit. Neither task agent commits.

Before editing, each agent reads the root plan, full specification, repository
instructions, this parent plan, its child plan, and the Review plan in full.

## Contract

Own:

- **VEL-01** and **VEL-02**;
- continuous and mixed-context **VEL-03**;
- continuous **A11Y-01**;
- velocity gestures in **LIFE-01**;
- combined **PERF-01** instrumentation and proof; and
- **UX-05**, **UX-06**, and the velocity portion of **UX-09**.

Intrinsic ruler presentation remains disabled until Task 10.

## What to deliver

### Model and shared state

- A widget-independent continuous `VelocityAxis`.
- One Velocity page using Task 02 exact selection and Task 03 batch mutation.
- Shared selected track, notes, scroll, time zoom, cursor, playhead, grid,
  snap, color, voice context, focus, and edit commands.
- Plain track-header click clears selection even on the primary track.
- Reuse Task 07's one `drawerContextTick` rounding helper for all drawer
  lookups; do not add a second conversion path.
- Continuous fallback for DirectSound, missing or invalid voice context,
  nested key splits, no-key top-level key split, and incompatible selections.
- The sole pure PSG voice-context resolver, representative tables,
  compatibility result, and per-note canonicalizer needed for mixed PSG/PCM
  and incompatible PSG **VEL-03** behavior, without displaying an intrinsic
  axis. This task owns proposal-to-representative conversion. Task 10 consumes
  these APIs to enumerate intrinsic presentation and must not duplicate them.

### Axis and drawing

- Derived plot origin and `Space::Three` vertical inset.
- Specified density sets using named layout thresholds.
- Static label clicks, dynamic extrema, and label hiding only during relative
  drag.
- Duration stems, start nodes, selected stem/ring, track color, watermark, and
  no hover decoration.
- Narrow-width and culling behavior through shared layout values.

### Selection and gestures

- Exact node/stem hit testing.
- Plain/Ctrl left behavior.
- Pending right band, drag threshold, replace/add box behavior, stationary
  plain/Ctrl behavior, context-menu suppression, and blank-space rules.
- Relative continuous drag with one proposed delta.
- Mixed-context per-note PSG canonicalization and exact DirectSound values.
- Freehand stationary stamp, crossed-node interpolation, and duration-stem
  exclusion.
- Middle pan, wheel routing, Escape restore, and complete lifecycle
  termination.
- UI-only previews and one batch commit on release.

### Status, access, and performance

- Existing exact typed entry remains in the piano-roll menu only.
- First-pressed-hit preview announcement only.
- Structured note status with key, stored and effective velocity, raw ticks,
  and effective clocks, rendered as fixed-width monospaced chips in exactly
  one row:

  ```text
  <key> · velocity <stored> → plays <effective> · length <ticks> ticks → <clocks> clocks
  ```

- A normal status message hides that row. It returns only on the next note
  announcement, never when the message timeout alone expires.
- Exact continuous accessible description and no extra focus targets.
- Existing shared edit commands, including note-position nudges and no direct
  velocity keys.
- Velocity content-build, invalidation, and playhead counters.
- Combined 120-update **PERF-01** proof for both drawer pages.
- Follow-scroll pauses during every live drawer gesture and resumes after
  commit or cancel without changing the frozen coordinate system.
- Edit, selection, zoom, scroll, resize, theme, document, and voice-context
  invalidation.
- Both pages remain within the current `TimelineSurface` contract when present.
  Normal painting honors the event update rectangle; `QRegion` is used only
  for disjoint invalid areas, and rejected broad paint culling does not return.

## Non-goals

- No visible intrinsic graduations, detented labels, or volume-level message.
- No velocity-specific context menu, tooltip, keyboard nudge, or live region.
- No second note-selection model.
- No static geometry outside `layout`.

## Method

1. Task 09A adds the pure continuous axis, voice-context canonicalizer,
   drawing, hit testing, shared state, and selection.
2. Task 09B adds preview-only gestures, batch commit, status, access,
   lifecycle, rendering, and performance behavior.
3. Review 09B's delta and then the full Task 09 tree against
   `LOGICAL_START_SHA`.
4. The coordinator synthesizes the exact combined approved tree as one Task 09
   integration commit.

## Required verification

Run focused edit, roll, velocity, tab, session, and performance checks plus:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Prove:

- duplicate-safe selection and selection continuity;
- exact right-band and stationary-click rules;
- one command on release and none on preview/cancel/no-op;
- all lifecycle termination cases restore snapshots;
- fast freehand leaves no crossed node unchanged;
- mixed proposal `65` yields Wave `64`, Square/Noise `68`, and DirectSound
  `65` in one command;
- continuous status and accessible text are exact;
- normal status hides the fixed-width structured row and timeout alone never
  restores it;
- no intrinsic ruler is visible;
- 120 playhead-only updates rebuild neither page;
- edit, selection, zoom, scroll, resize, theme, document, and voice-context
  changes invalidate correctly;
- follow-scroll, `TimelineSurface`, event update-rectangle, limited-`QRegion`,
  and no-broad-culling rules hold; and
- geometry gates pass with aligned visuals and hit regions.

## Oracle review points

Retain the intended drawing and gesture feel while improving exact identity,
atomic revision validation, right-button rules, cancellation, mixed-context
semantics, layout ownership, and performance boundaries.

## Handoff and review

Each child agent stages but does not commit and writes its own handoff. The
combined handoff records `LOGICAL_START_SHA`, 09A transport SHA and approved
tree, 09B staged tree, selection and gesture matrices, mixed-context values,
Undo/revision evidence, exact status and accessibility output, follow-scroll
and rendering evidence, counter fixture/warmup/120 updates/final tick/counters,
geometry gates, screenshots, and all commands and exits.

The Review agent must review each child and the full combined tree, interact
with the page, and inspect document and rendering ownership. Only the
coordinator may synthesize the tree after both child verdicts and the combined
verdict are `APPROVED`.
