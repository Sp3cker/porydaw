# Task 6: Drawer and remaining UI

## Context

Consumes Task 4’s document tick API. Producer for Task 7 (automation / event-list / pitch-bend checks). Contains the two real compile breaks: `std::map` key width and `EventTableModel` tick editing. Named drawer/event-list/pitch-bend checks run after Task 7.

## Exact write set

- `src/ui/editordrawer/drawerpage.h`
- `src/ui/editordrawer/automationpage.h`
- `src/ui/editordrawer/automationpage.cpp`
- `src/ui/editordrawer/automationprojection.h`
- `src/ui/editordrawer/automationprojection.cpp`
- `src/ui/editordrawer/automationcanvas.h`
- `src/ui/editordrawer/automationcanvas.cpp`
- `src/ui/editordrawer/automationcanvas_gesture.cpp`
- `src/ui/editordrawer/automationcanvas_input.cpp`
- `src/ui/editordrawer/automationcanvas_menu.cpp`
- `src/ui/editordrawer/automationcanvas_pointmenu.cpp`
- `src/ui/editordrawer/automationcanvas_deleteprompt.cpp`
- `src/ui/editordrawer/laneselection.h`
- `src/ui/editordrawer/laneselection.cpp`
- `src/ui/editordrawer/cclanes.h`
- `src/ui/editordrawer/cclanes.cpp`
- `src/ui/editordrawer/tempolane.h`
- `src/ui/editordrawer/tempolane.cpp`
- `src/ui/editordrawer/nodelane/nodelane.h`
- `src/ui/editordrawer/nodelane/nodelane.cpp`
- `src/ui/editordrawer/nodelane/gesture.h`
- `src/ui/editordrawer/nodelane/gesture.cpp`
- `src/ui/editordrawer/nodelane/batchcommit.h`
- `src/ui/editordrawer/nodelane/batchcommit.cpp`
- `src/ui/editordrawer/nodelane/pencilgesture.h`
- `src/ui/editordrawer/nodelane/pencilgesture.cpp`
- `src/ui/editordrawer/nodelane/tempoadapter.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea.h`
- `src/ui/editordrawer/velocityarea/velocityarea.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea_interaction.cpp`
- `src/ui/editordrawer/voicechangearea/voicechangearea.h`
- `src/ui/editordrawer/voicechangearea/voicechangearea.cpp`
- `src/ui/editordrawer/voicechangearea/voicechangemenu.cpp`
- `src/ui/pitchbendgraph.hpp`
- `src/ui/pitchbendgraph.cpp`
- `src/ui/pitchbendgraph_render.cpp`
- `src/ui/pitchbendeditor.cpp`
- `src/ui/eventtablemodel.h`
- `src/ui/eventtablemodel.cpp`
- `src/ui/eventtablemodeledit.cpp`
- `src/ui/polyphonypanel.h`
- `src/ui/polyphonypanel.cpp`
- `src/ui/workspaceui.h`
- `src/ui/workspaceui.cpp`
- `src/mainwindow.cpp`
- `src/project/songregistry.cpp`

## Prerequisites

4.

## Interface contract

Positions in this write set are `Tick`: `NodePoint::tick`, `NodePointMove::fromTick`, `AutomationGridCell` begin/end, drawer page / automation page / projection / canvas tick params, `DrawerPageVoiceContext::endTick`, `FrozenNote::tick`, voice-change ticks, `PitchBendGraph::Initial` start/end and `std::map<Tick, int>` keys (and every matching snapshot map in this write set), `EventTableModel::TempoRow::tick` and tick params, `workspaceui` seek/play-from signals, `mainwindow` tick lambdas (sample results of `sampleForTick` stay `uint64_t`), `songregistry` blank-song `endTick`.

`replaceSpan` / `writeLanePoints` “whole song” arguments in this write set are `kNoTick`. `DrawerPageVoiceContext::endTick` default is `kNoTick`. Document `revision` fields stay `uint64_t`.

`EventTableModel::setData` on a tick column (`handleRawTick`, `handleTempoTick`, `handleEndTick`): after converting the edit value to an integer, if it is `> kMaxTick`, return false, no queued edit. Behavioral pin is Task 7 (`edits.cpp`).

`static_assert(sizeof(NodePoint) == 8)`.

Do not edit `velocityaxis.*` (not musical ticks). Do not add `hasLoop*` on `MidiTimeline`.

## Implementation steps

1. Flip positions to `Tick` and tick-domain sentinels to `kNoTick` in the listed files, including pitch-bend map keys.
2. Enforce `setData` tick rejection at `kMaxTick`.
3. Apply the `NodePoint` sizeof assert. Leave revision/sample uint64s.

## Acceptance predicate

Pitch-bend maps compile as `Tick` keys; whole-span replace uses `kNoTick`; event-list tick edits above `kMaxTick` are rejected in source. Named checks: `deno task build:app` (drawer / eventviews / pitch-bend harnesses run in Task 7).

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk: `numeric_limits<uint64_t>::max()` passed into a `Tick` span param truncates to `kNoTick` by accident — rewrite the literals anyway so the grep audit can pass.
