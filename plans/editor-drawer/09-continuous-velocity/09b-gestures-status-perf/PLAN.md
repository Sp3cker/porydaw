# Task 09B — Velocity gestures, status, lifecycle, and rendering

**Blocked by:** Reviewed Task 09A and its exact approved tree made available as
the 09B start commit.

**Runtime worktree:** `09b-gestures-status-perf`

**Branch:** `task/editor-drawer/09b-gestures-status-perf`

**Parent slice:** Task 09 continuous velocity.

## Start rule

Create or fast-forward this clean worktree to the reviewed 09A transport commit
and record it as `START_SHA`. Also record the accepted Task 08 integration SHA
as `TASK09_BASE_SHA`.

Before editing, read the root plan, full specification, repository
instructions, parent Task 09 plan, both Task 09 sub-plans, the 09A handoff and
review, and this plan in full. Confirm `START_SHA^{tree}` equals the approved
09A tree. Do not commit.

## Contract

Close Task 09 by owning:

- mutation portions of **VEL-02** and continuous/mixed **VEL-03**;
- continuous **A11Y-01**;
- velocity and shared-selection termination in **LIFE-01**;
- full **PERF-01** instrumentation and proof; and
- remaining **UX-05**, **UX-06**, and velocity **UX-09** behavior.

09A remains the owner of the axis, shared selection, drawing, hit testing, and
pure per-note context canonicalizer. Intrinsic presentation remains disabled.

## What to deliver

### Mutation gestures and Undo

- Freeze the exact selection, note addresses, document revision, axis, voice
  context, coordinates, and starting values at gesture start.
- Relative drag activation at the named Manhattan-distance threshold or level
  change.
- One shared proposed continuous delta, with DirectSound exact and every PSG
  note canonicalized through 09A's pure per-note context seam.
- Freehand stationary stamping, segment interpolation across every crossed
  start node, and duration-stem exclusion.
- Static continuous-label clicks that set the shared selection to that exact
  value.
- UI-only drag and freehand previews followed by one revision-checked
  `SongDocument::setNotesVelocities` batch on release.
- One `paint note velocities` Undo command for a completed change and none for
  preview, cancellation, stale rejection, invalid batches, or no-ops.
- Selection continuity after a successful commit.
- Existing typed `Set velocity...` behavior remains in the piano-roll context
  menu and stores the exact entered value.

### Exact status and accessibility

- Announce only the first pressed hit during relative-drag preview updates.
- No note announcement for selection-only clicks, bands, label clicks, or
  freehand painting.
- Structured note data containing key, stored velocity, effective velocity,
  raw ticks, and effective clocks.
- Exact one-row presentation:

  ```text
  <key> · velocity <stored> → plays <effective> · length <ticks> ticks → <clocks> clocks
  ```

- Fixed-width monospaced chips; a normal status message hides the structured
  row, which returns only on the next note announcement.
- Continuous accessible description exactly `Velocity`, with no node or
  graduation focus targets.
- `Qt::ClickFocus` plus the existing shared Copy, Cut, Paste, Select all,
  Delete, Transpose, and note-position nudge routes.
- No velocity keyboard nudge, tooltip, extra context menu, or live region.

### Lifecycle, follow-scroll, and rendering

- Terminate relative, freehand, pending-band, and committed-selection previews
  on page hide, drawer hide, track or song change, document mutation, Undo,
  Redo, reload, replacement, mouse-grab loss, window deactivation, and Escape.
- Restore staged values and provisional selection snapshots, clear cursor,
  grab, hover, and preview state, and create no MIDI or Undo change.
- End view-only pan capture while keeping the applied scroll position.
- Pause follow-scroll for a live drawer gesture and resume it after commit or
  cancel without changing the frozen coordinate system.
- Keep expensive automation and velocity content out of steady playhead
  updates; the playhead overlay owns routine presentation.
- Invalidate affected content for edit, selection, zoom, scroll, resize,
  theme, document, and voice-context changes.
- If the base uses `TimelineSurface`, keep both pages within that contract.
- Do not restore broad paint culling. Normal widget painting honors the update
  rectangle; use a region only for separate invalid areas.
- Test-only content-build, content-invalidation, and playhead-presentation
  counters for both drawer pages.
- Full **PERF-01** proof: process and discard warmup, issue 120 on-screen
  playhead-only updates, process events after each, prove zero content rebuilds
  and the final presented tick, then prove each named invalidation source.

## Non-goals

- No change to 09A axis ownership, selection model, hit-test rules, or drawing
  geometry except a reviewed fix needed to close an integration finding.
- No visible intrinsic axis, detent, volume-level message, exact-origin
  categorical restoration, or intrinsic accessible text.
- No new static geometry, mixer-dependent graduations, broad paint culling, or
  unrelated playback work.

## Method

1. Add mutation and cancellation regressions against the 09A page.
2. Add preview-only relative and freehand gestures.
3. Connect the single batch commit and exact Undo boundary.
4. Add structured status, access text, and shared command routing.
5. Close every lifecycle and follow-scroll route.
6. Add rendering counters and run the combined page performance proof.
7. Run the delta review, then the full Task 09 combined-tree review.

## Required verification

Run focused edit, roll, velocity, tab, session, lifecycle, rendering, and
performance checks plus:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Prove:

- relative and freehand previews do not mutate the document;
- release makes one atomic command and cancel/no-op/stale paths make none;
- proposal `65` yields Wave `64`, Square/Noise `68`, and DirectSound `65`;
- every lifecycle route restores the right snapshot and clears transient state;
- exact status text, visibility behavior, access text, and command routing;
- 120 playhead-only updates rebuild neither page and end at the final tick;
- every required user or model change records the matching invalidation;
- follow-scroll resumes without moving the frozen gesture frame;
- `TimelineSurface` and update-rectangle rules hold on the current base;
- both geometry scales and the source gate pass; and
- intrinsic presentation remains absent.

## Oracle review points

Keep the oracle's intended continuous editing feel while improving atomic batch
mutation, mixed-note canonicalization, lost-capture cleanup, exact status,
shared command ownership, follow-scroll stability, and playhead-only
presentation. Do not accept build success or subjective smoothness as rendering
evidence.

## Handoff and two review gates

Stage the exact candidate without committing. Record `START_SHA`,
`TASK09_BASE_SHA`, staged tree ID, gesture and lifecycle matrices, batch and
Undo evidence, status/accessibility output, follow-scroll checks, fixture,
warmup, 120 updates, final tick, all counters, geometry gates, screenshots, and
every command and exit.

The Review agent must issue two explicit verdicts bound to the same staged tree:

1. **09B delta review:** inspect `START_SHA` to the staged tree for only 09B's
   owned behavior.
2. **Full Task 09 combined-tree review:** inspect `TASK09_BASE_SHA` to the
   staged tree, reread 09A and 09B evidence, exercise the complete continuous
   page, and check all Task 09 acceptance ownership and oracle improvements.

Any remediation changes the tree and invalidates both verdicts. Rerun the 09B
delta review and the full combined review after every fix.

Only after both verdicts are `APPROVED` may the coordinator synthesize their
combined approved tree. It first creates the clean B transport commit, then
uses its exact tree for the single Task 09 integration commit defined by the
root plan. The committed final tree must equal the tree approved by the full
combined review.
