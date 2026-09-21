# Task 1 — Remove automation QSG paint path

## Context

First half of the excision. Deletes the only `rebuildQuickScene`
implementation for automation plus its private `NodeLaneQuickPaint` helper,
and strips the automation band/layers/text models they fed from the dead
`TimelineQuickView`/`TimelineCanvas.qml`/`TimelineQuickScene` surface.
Producer for nothing downstream — task 2 deletes `AutomationCanvas` itself.
Behavior change: none (all touched code is uncompiled).

## Exact write set

Delete:
- `src/ui/songview/quick/automationquick.cpp`
- `src/ui/songview/quick/automationnodelanequick.h`
- `src/ui/songview/quick/automationnodelanequick.cpp`

Edit (remove automation references only):
- `src/ui/editordrawer/automationcanvas.h` — drop the `rebuildQuickScene`
  declaration (~lines 209–210) and the `friend class
  songview::TimelineQuickView;` line (~207) if it exists only for that call;
- `src/ui/songview/quick/timelinequickview.h` — drop
  `syncAutomation(AutomationRefreshSet)`, `requestAutomationUpdate`,
  `m_pendingAutomationRefresh`, and any `AutomationRefreshSet`
  member/include used only by them.
- `src/ui/songview/quick/timelinequickview.cpp` — drop the `syncAutomation`
  implementation and its `flushUpdate` call/pending-refresh exchange.
  Keep the `automationCanvas` context property and `canvas()` input
  bindings — task 2 removes them with the class.
- `src/ui/songview/quick/timelinequickscene.h` — drop the whole automation
  text-model surface, not just the enums: the seven
  `TimelineQuickLayer::Automation*` enum values, the `Automation*TextRole`
  enum values (`AutomationGhostLabel`, `AutomationGhostHover`,
  `AutomationHover`, `AutomationTransient`, `AutomationScaleLabel`), the
  three `setAutomation*TextRecords` declarations, the automation text-model
  `Q_PROPERTY`s, their getters, and the `m_automation*` storage members —
  only where each is referenced solely by the deleted paint path; if a
  text role is shared with a surviving lane, keep it and report the
  exception.
- `src/ui/songview/quick/timelinequickscene.cpp` — drop the matching
  constructor wiring, getter bodies, and setter bodies for the removed
  automation text models.
- `src/ui/songview/quick/TimelineCanvas.qml` — remove the
  `TimelineSceneBand { id: automationBand … }` block including its
  `AutomationTabs` child (dead `canvas: automationCanvas` binding), the
  three root property declarations `automationBandRect` /
  `automationBandVisible` / `automationBandPlotRect`, and their entries in
  the band layout arrays. Keep every other band.
- `src/ui/songview/quick/DrawerChromeLayer.qml` — dead file (only
  `TimelineCanvas.qml` loads it): remove the two automation band
  properties it requires, the `onAutomationBandVisibleChanged` handler,
  and the internal uses that read them (prompt-centering). Leave the rest
  of the chrome contract intact.

## Prerequisites

None. Task 2 consumes the cleaned `timelinequickview`/`automationcanvas.h`
surface.

## Interface contract

- No new symbols. Deletion + reference removal only.
- `TimelineQuickView` keeps compiling-coherent shape for its surviving
  lanes (velocity, voice, ruler, playhead, otherstrip): their
  `rebuildQuickScene` call sites, layer enums, and text models are
  untouched.
- `AutomationCanvas` class still exists after this task (task 2 deletes
  it); its header loses only the paint-path declaration. Known-dangling
  edge, do not repair: `syncAutomation` is removed here while the
  `automationCanvas` context property and `canvas()` input bindings stay
  until task 2 removes the class.

## Implementation steps

1. Delete the three paint-path files.
2. Edit `timelinequickview.{h,cpp}` to remove the automation sync path.
3. Edit `timelinequickscene.{h,cpp}` per the write set; grep each
   candidate symbol for non-automation callers before removing.
4. Edit `automationcanvas.h` to drop the paint-path declaration.
5. Edit `TimelineCanvas.qml` (band block, root property declarations,
   layout-array entries) and `DrawerChromeLayer.qml` (automation props,
   handler, uses); verify no remaining binding references `automationBand`
   or `automationCanvas` in either file.
6. Grep `src/` for `automationquick`, `NodeLaneQuickPaint`,
   `automationBand`, `AutomationGutterChrome`, `AutomationCurves`,
   `AutomationNodes`, `AutomationSelection`, `AutomationLane`,
   `AutomationScaleLabel`, `AutomationGhost` — every hit must be a file
   task 2 owns or a comment you then remove.

## Acceptance predicate

Per plan.md Verification policy (all four commands, run by implementer —
this plan has no SHARED_TREE constraint). Task-specific greps (must be
empty outside task-2-owned files and `proof.*.txt` fixtures):
`grep -rn "automationquick\|NodeLaneQuickPaint\|automationBand" src/ --exclude="proof.*.txt"`
`grep -n "Automation" src/ui/songview/quick/timelinequickscene.h src/ui/songview/quick/timelinequickscene.cpp`
`grep -n "automationCanvas\|automationBand" src/ui/songview/quick/TimelineCanvas.qml src/ui/songview/quick/DrawerChromeLayer.qml`
Plus a QML parse pass over the two edited QML files (they are unbundled —
nothing else parses them): `qmllint src/ui/songview/quick/TimelineCanvas.qml src/ui/songview/quick/DrawerChromeLayer.qml` must report no syntax errors (import warnings on the dead module are acceptable).

## Task-specific constraints

- If a `timelinequickscene.{h,cpp}` symbol turns out to be shared with a
  surviving lane, keep it and name the exception in the result — do not
  rename or split it.
- Do not touch `velocityquick.cpp`, `voicechangequick.cpp`, or any
  velocity/voice layer enum — sibling plan keeps them live.
- Do not delete `AutomationTabs.qml` — the production drawer uses it.
