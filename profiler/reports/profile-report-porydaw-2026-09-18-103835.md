# QML logic profile — porydaw note rendering (scroll + zoom)

## Header

- App: `build-profile/porydaw.app/Contents/MacOS/porydaw` (RelWithDebInfo + `QT_QML_DEBUG`)
- Profiler: `/opt/homebrew/opt/qt/bin/qmlprofiler --include javascript,binding,handlingsignal,compiling,creating`
- Trace: `profiler/traces/qmlprofiler-trace-porydaw-2026-09-18-103835.qtd` (5.2 MB)
- Session: ~41 s, exercising piano-roll scroll + zoom on a note-dense song
- Totals: 52,952 events, 110.32 ms of range-event time

| Event type     | Count  | Total ms |
|----------------|--------|----------|
| Compiling      | 26     | 40.76    |
| Creating       | 3,886  | 36.36    |
| Binding        | 22,009 | 20.35    |
| Javascript     | 26,748 | 11.75    |
| HandlingSignal | 283    | 1.10     |

Raw `count` scales with session length and is not a primary metric; total and
average milliseconds decide what matters.

## Bottom line

QML logic is not where note-rendering time goes in this session. 110 ms of
logic time across a 41 s interactive run is noise, and no hotspot touches the
scroll/zoom path. This is expected from the architecture: note fills, borders,
selection, grid rows and keyboard highlights all paint inside C++
`TimelineQuickItem::updatePaintNode` scene-graph nodes
(`PianoNoteFills`, `PianoNoteBordersAndSelection`, … in
`src/ui/songview/quick/timelinequickscene.h`). The QML layer only hosts window
chrome plus `Text` repeaters fed by `TimelineQuickScene` models
(`pianoNoteTextModel`, `pianoKeyboardTextModel`, …). A logic trace therefore
covers labels, chrome and startup — never fill rasterization or scene-graph
sync. If frames still drop while scrolling, the cost is in scene-graph
sync/render, which needs a rendering profile (`scenegraph,animations,painting,
pixmapcache`), not more logic work.

## Hotspots

### 1. Compiling `TimelineCanvas.qml` — 20.33 ms, 2 events (startup, one-time)

[TimelineCanvas.qml:0](../../src/ui/songview/quick/TimelineCanvas.qml#L0)

Whole-file compile of the 732-line canvas, once per window creation. Caveat:
this was measured in a `QT_QML_DEBUG` build, which can bypass the bytecode
cache that `qt_add_qml_module` (URI `Porydaw.Ui`, `RESOURCE_PREFIX /qt/qml`)
emits for release. Treat 20 ms as an upper bound; only re-measure release
startup if startup time actually matters to you.

### 2. Compiling `AutomationTabs.qml` — 11.77 ms, 2 events (startup, one-time)

[AutomationTabs.qml:0](../../src/ui/songview/quick/AutomationTabs.qml#L0)

Same story as (1): one-time cost for the automation parameter tab grid. No
action unless release-startup profiling says otherwise.

### 3. Creating canvas root + tab repeater — ~9 ms total, counts of 2–4 (window creation)

- [TimelineCanvas.qml:4](../../src/ui/songview/quick/TimelineCanvas.qml#L4) — root `Item`, 4.76 ms over 4 creations (1.19 ms each)
- [AutomationTabs.qml:40](../../src/ui/songview/quick/AutomationTabs.qml#L40) — tab `Repeater`, 4.33 ms over 4
- [AutomationTabs.qml:43](../../src/ui/songview/quick/AutomationTabs.qml#L43) — `TabButton` delegates, 1.30 ms over 26

AllCreation counts of 2–4 mean these fire at window open, not during
scroll/zoom. Healthy; no action.

### 4. Binding `appearance <- canvas.parameterAppearance` — 3.28 ms over 30 evals

[AutomationTabs.qml:13](../../src/ui/songview/quick/AutomationTabs.qml#L13)

```qml
readonly property var appearance: canvas.parameterAppearance
```

This is the only binding in the trace worth a look: 0.109 ms average per
evaluation is the highest per-eval binding cost recorded, and 30 evaluations
means the source notified 30 times. If `canvas.parameterAppearance` mints a
fresh JS object on every notify, each new identity re-triggers this binding
plus every downstream consumer (`root.appearance.font`, per-tab bindings at
lines 50–59). If those 30-eval bursts recur during interaction rather than
just startup, stabilize the source: return a persistent object, or split it
into typed properties (`parameterFont`, …) so only what changed notifies. In
this trace the burst happened at startup, so this is optional, not urgent.

### 5. `HoverHint.sync()` — 202 calls, 0.78 ms; `onScopeRefresh` — 88 calls, ~0.5 ms

- [HoverHint.qml:117](../../src/ui/songview/quick/HoverHint.qml#L117) — `sync()`, the single claim path for hover/gesture/session/scope changes
- [HoverHint.qml:49](../../src/ui/songview/quick/HoverHint.qml#L49) — `onScopeRefresh` funnel into `sync()`

~4 µs per call with an early-out when hints or source are missing. Funneling
every trigger through one `sync()` is the right shape. No action.

## What the trace says about scrolling

`Binding` (22,009 evals / 20.35 ms) and `Javascript` (26,748 calls /
11.75 ms) average ~1 µs each across the whole run — the scroll/zoom gesture
left no logic footprint at all. Nothing in the top 30 hotspots maps to
`PianoRollCanvas.qml`, `timelinequickscene` text-model updates, or any
per-frame handler. Either the gesture produced genuinely negligible QML logic
(the C++ layers do the work), or the recorded window under-weighted the
gesture. Either way, the data says: do not optimize QML bindings, signal
handlers, or delegates for note rendering on this evidence.

## Recommendations (in order)

1. **Do nothing to QML logic for note rendering.** The trace exonerates it.
2. **Optional:** stabilize `canvas.parameterAppearance` object identity (see
   hotspot 4) — cheap insurance if tab-grid bindings ever show up in a future
   trace during interaction.
3. **Next measurement, if scrolling still drops frames:** capture a rendering
   profile (`--include scenegraph,animations,painting,pixmapcache`) running the
   identical scroll/zoom gesture, and correlate with `pianoNoteTextModel`
   row-count churn per frame. Each visible label is a scene-graph text node;
   label count, not fill painting, is the most likely QML-adjacent cost.
4. **Keep per-note visuals in the C++ layers.** The current split (fills,
   borders, grid in `updatePaintNode`; only text in QML `Repeater`s with
   `PlainText`/`NativeRendering` delegates) is already the performant shape —
   do not move note visuals into QML delegates.
