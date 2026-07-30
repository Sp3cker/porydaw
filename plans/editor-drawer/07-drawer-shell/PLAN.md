# Task 07 — Add the editor drawer shell and generic saved state

**Blocked by:** Reviewed and integrated Task 06.

**Runtime worktree:** `07-drawer-shell`

**Branch:** `task/editor-drawer/07-drawer-shell`

**Target slice:** Specification implementation slice 7.

**Suggested subject:** `Add the editor drawer shell`

## Start rule

Fast-forward this clean worktree to the accepted Task 06 integration SHA and
record it as `START_SHA`.
Before editing, read the root plan, full specification, repository
instructions, and this plan in full.

## Contract

Own the Editor drawer sections and:

- **DRW-01**, **DRW-02**, and **DRW-03**;
- generic drawer portions of **DRW-04** and **DRW-05**;
- the shared drawer cancellation route in **LIFE-01**;
- automation-side performance counter seams used by **PERF-01**; and
- **UX-01**, **UX-02**, and the generic part of **UX-10**.

## What to deliver

- A bottom overlay that leaves roll and track-header geometry unchanged.
- Named-layout-derived track-header, keyboard, plot, tabs, handle, drawer
  bounds, and narrow-width clamps.
- Text-only, non-focusable Automations and Velocity tabs.
- Exact toggle behavior, tooltips, and status strings.
- One active `A` and `V` route per top-level window, affecting only the active
  song tab.
- Event-list shortcut blocking without changing saved page or visibility.
- Left-button resize with specified bounds and splitter theme roles.
- Focus transfer on page switches and return to main content on close.
- One shared route for page-hide, drawer-hide, and lost-lifecycle gesture
  termination.
- Generic sidecar merge and save for drawer visibility, page, legacy splitter,
  and default row height.
- Restore drawer height from `splitter[1]` only. Keep `splitter[0]` positive
  for compatibility without changing roll size; missing or short arrays use
  the one-fifth default.
- Unknown `drawerPage` falls back to Automations. Missing, malformed,
  unreadable, or unwritable sidecar state fails silently without interrupting
  song editing.
- Unknown root and `view` keys preserved through `QSaveFile`.
- Preserve an uninterpreted valid non-menu lane range such as `91` through the
  generic merge; Task 08A will add typed load, remap, and save behavior.
- Repeated restore replaces state.
- Save on tab close, project switch, song replacement, and app close, not on
  every drag update.
- One shared `drawerContextTick` helper with the specified nonnegative rounding
  semantics, used by the hosted automation page and reserved for velocity.
- The unchanged automation page hosted in the Automations page.
- Test-only automation content-build, invalidation, and playhead-presentation
  seams needed for later combined performance proof.
- A shared gesture/follow-scroll pause route that can resume after commit or
  cancel without replacing a gesture's frozen coordinates.
- Placement inside the current `TimelineSurface` rendering contract when that
  contract exists. Normal widget paint uses the event update rectangle;
  `QRegion` is reserved for separate invalid areas, and no broad playback paint
  culling returns.

The Velocity page may be an inert host placeholder in this task. It must not
claim velocity behavior or create extra focus targets.

## Non-goals

- No automation lane deltas or gesture changes.
- No velocity editor.
- No configurable keymap entries for `A` or `V`.
- No splitter that resizes the underlying roll.
- No sidecar rewrite that drops unknown fields.

## Method

1. Add overlay and focus/lifecycle checks before wiring UI.
2. Add the shell using Task 05 layout values only.
3. Route shortcuts through the active `SongView`.
4. Host the unchanged automation page.
5. Add generic sidecar read/merge/write behavior.
6. Add cancellation, follow-scroll, and performance seams without changing
   edit behavior.
7. Exercise multiple song tabs and event-list transitions.

## Required verification

Cover **DRW-01...DRW-05** in their current scope, drawer **LIFE-01**, and
automation-side PERF counters. Run focused roll, session, tab, event-list, and
keymap checks plus:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Confirm:

- active-tab-only shortcuts and announcements;
- exact tooltips and messages;
- no shortcut effect in event-list mode;
- focus and last-open-height behavior;
- roll geometry unchanged under the overlay;
- `splitter[1]` alone restores height, `splitter[0]` remains positive without
  shrinking the roll, and missing or short splitter arrays use one fifth;
- unknown page falls back to Automations and sidecar read/write failure is
  silent;
- widths below plot origin draw nothing through the gutter;
- view-only actions change neither MIDI, dirty state, nor Undo;
- unknown sidecar fields survive;
- an uninterpreted saved range of `91` survives the generic merge;
- two disjoint restores replace rather than append generic state; and
- every drawer playhead lookup uses the same rounded unsigned context tick;
- playhead-only updates reach presentation without automation rebuild;
- scroll, resize, theme, document, and voice-context changes invalidate the
  hosted automation content;
- follow-scroll pause/resume preserves the frozen coordinate seam; and
- `TimelineSurface`, update-rectangle, limited-`QRegion`, and no-broad-culling
  rules hold.

## Oracle review points

Retain the intended overlay, tabs, resize, focus, and persistence flow. Improve
active-tab routing, state replacement, narrow clamps, cancellation, and
unknown-key merging as required by the spec.

## Handoff and review

Stage but do not commit. Record `START_SHA`, staged tree ID, state transitions,
two-tab evidence, sidecar before/after JSON, MIDI/Undo invariants, focus
evidence, counter output, both-scale screenshots, geometry gates, and all
commands and exits.

The Review agent must perform a UX and ownership review, not only a widget
existence check. Approval gates the coordinator's Task 07 commit.
