# Task 2 — VelocityArea and VoiceChangeArea live-read rewrite

## 1. Context

Consumes task 1's `refresh(DrawerScopes)` entry points. Deletes `m_live`,
`refreshLiveState`, and the field-diff classification from both areas; handlers switch on
scopes per plan.md's mapping and read live sources (`m_owner.document().revision()`,
`m_owner.playing()`, `m_owner.playheadTick()`, `m_owner.editCursorTick()`,
`m_camera.scrollX()`). Task 3 performs the same cutover for AutomationPage and migrates the
check fixtures that still call `refreshLiveState`.

## 2. Exact write set

- `src/ui/editordrawer/velocityarea/velocityarea.h`
- `src/ui/editordrawer/velocityarea/velocityarea.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea_interaction.cpp`
- `src/ui/editordrawer/voicechangearea/voicechangearea.h`
- `src/ui/editordrawer/voicechangearea/voicechangearea.cpp`

## 3. Prerequisites

- Task 1: `DrawerScopes`, `SongView::playing()`, scoped `refresh*` fan-out.

## 4. Interface contract

```cpp
// velocityarea.h / voicechangearea.h — replaces refreshLiveState
void refresh(DrawerScopes scopes);            // was task-1 forwarder; now the real handler
void presentPlayhead(double tick);            // signature unchanged
```

Deleted from both classes: `DrawerPageLiveState m_live`, `refreshLiveState`. Deleted from
`drawerpage.h` only in task 3 (automation still uses the struct until then) — this task must
not remove the shared struct.

New private member on each area: `uint64_t m_interactionRevision = 0;` — captured when a
gesture/pan begins (see steps), used by the preserve arms in place of
`m_live.documentRevision == liveState.documentRevision`. Velocity also keeps
`std::optional<bool> m_lastPlaying` (or folds the check into `presentPlayhead`) to detect
the playing-flag toggle that `velocityarea.cpp:140` used to diff.

## 5. Implementation steps

1. `VelocityArea::refresh(DrawerScopes)` — arms in priority order:
   - `Document` → `cancelInteraction()`; if no interaction was active,
     `rebuildVisualState()`; `presentPlayhead(m_owner.playheadTick())`; return.
   - `Content | Selection | Zoom` → if `m_interaction != None &&
     m_interactionRevision == m_owner.document().revision()`: present playhead if the tick
     moved, return (preserves `velocityarea.cpp:129-134`). Else `cancelInteraction()`,
     `rebuildVisualState()` when no interaction was active, `presentPlayhead`.
   - `HorizontalScroll` → keep today's hover-aware retain: resolve the context exactly as
     `velocityarea.cpp:113-121` (hovered note → `contextForNote`, else `currentContext()`);
     if it equals `m_axis.map()`, `presentPlayhead` and return; else fall through to the
     rebuild arm.
   - `Playhead` → if `m_owner.playing()` differs from the last-seen flag, treat as the
     rebuild arm (replaces the `playback.playing` diff); else `presentPlayhead`.
2. `VelocityArea::presentPlayhead` — drop the `m_live.playback.playheadTick` write
   (`velocityarea.cpp:220`); keep `m_diagnostics` updates and the
   `m_lastPresentedPlayheadTick` dedupe; record the playing flag for step 1's toggle check.
3. `VelocityArea::currentContext` (`velocityarea.cpp:318-325`) — read
   `m_owner.playing()`, `m_owner.playheadTick()`, `m_owner.editCursorTick()` live.
4. `velocityarea_interaction.cpp:316-321` pan — request base and post-scroll read both use
   `m_camera.scrollX()`; delete the `m_live` write-back. Capture `m_interactionRevision =
   m_owner.document().revision()` wherever `m_interaction` transitions out of `None`
   (pan start, `beginFrozenGesture`, band/ramp/paint entries).
5. `VelocityArea::songChanged` (`:91-100`) — drop `m_live = {}`; keep the rest.
6. `VoiceChangeArea::refresh(DrawerScopes)` — keep the `m_engineTrack` recapture and
   `trackChanged` computation verbatim (`voicechangearea.cpp:145-147`). Arms:
   - `Document` or `trackChanged` → `cancelInteraction()` + `rebuildVisualState()` +
     `presentPlayhead`.
   - `Content | Zoom` → if `m_interaction == Pan && m_interactionRevision ==
     m_owner.document().revision()`: present playhead if moved, return (preserves
     `:162-167`). Else cancel + rebuild + present.
   - `HorizontalScroll` → `presentPlayhead`, return.
   - `Playhead` → `presentPlayhead`.
7. `VoiceChangeArea::presentPlayhead` (`:217-229`) — gate on `m_owner.playing()`; drop the
   `m_live` write; keep the voice-slot-crossing `requestQuickUpdate` logic.
8. `voicechangearea.cpp:515-520` pan — `m_camera.scrollX()` for base and post-scroll read;
   capture `m_interactionRevision` at pan start.
9. `VoiceChangeArea::songChanged` (`:127-138`) — drop `m_live = {}`; keep the rest.
10. Both `documentChanged()` handlers are unchanged (they already rebuild synchronously).

## 6. Acceptance predicate

- `deno task verify --filter velocity-page --filter velocity-editing --filter
  drawerpresentation --filter timelinepancheck --filter host-adapter --filter
  host-integration --verbose` passes.
  - `host-integration` playhead sweep (`tst_hostintegration.cpp:189-196`) and
    `host-adapter` (`tst_hostadapter.cpp:606-612`) prove `contentBuildCount` stays flat
    under `Playhead`/`HorizontalScroll`-only refreshes — the scroll-frame budget.
  - `timelinepancheck` proves the pan path (live `scrollX` reads) end-to-end.
  - `velocity-page`/`velocity-editing` prove interaction-preserve and rebuild arms.
- `grep -n 'm_live\|refreshLiveState' src/ui/editordrawer/velocityarea
  src/ui/editordrawer/voicechangearea` returns nothing.

## 7. Task-specific constraints

- `HorizontalScroll`-only refresh MUST NOT call `rebuildVisualState` on either area
  (Global Constraints).
- Do not touch `DrawerPageLiveState` in `drawerpage.h` — automation still consumes it.
- `voicechangemenu.cpp` is untouched; its `refreshAllDrawerPages(Content)` call already
  lands through task 1.
