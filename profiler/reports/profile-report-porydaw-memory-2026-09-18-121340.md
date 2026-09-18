# Memory profile — porydaw note rendering (scroll + zoom)

## Header

- App: `build-profile/porydaw.app/Contents/MacOS/porydaw` (RelWithDebInfo + `QT_QML_DEBUG`)
- Profiler: `qmlprofiler --include memory,creating`
- Trace: `profiler/traces/qmlprofiler-trace-porydaw-memory-2026-09-18-121340.qtd` (2.2 MB)
- Session: ~62 s
- Totals: 30,122 events; Creating 4,014 events / 261.15 ms

| Heap              | Allocs | Bytes     | Peak live | Freed   |
|-------------------|--------|-----------|-----------|---------|
| JS heap pages     | 30     | 3,108,864 | 3,108,864 | 0       |
| Small items       | 25,593 | 3,346,976 | 2,961,248 | 385,728 |
| Large items       | 0      | 0         | 0         | 0       |

## Bottom line

QML-side allocation is startup-dominated and small: ~3 MB JS heap, ~3.3 MB
of small items, zero large items. Every hotspot has a creation count in the
single digits to low hundreds — window setup, not per-frame churn. There is
no evidence that scrolling the piano roll allocates anything on the QML side,
which matches the architecture (note visuals live in C++ scene-graph nodes;
QML text delegates are created once per visible label set and rebound, not
recreated, as the camera moves).

## Hotspots

All 30 hotspots are `Creating`, all one-time setup cost:

- [PianoRollCanvas.qml:4](../../src/ui/songview/quick/PianoRollCanvas.qml#L4) — 35.01 ms; [TimelineCanvas.qml:247](../../src/ui/songview/quick/TimelineCanvas.qml#L247) scene band 35.11 ms; [TimelineCanvas.qml:4](../../src/ui/songview/quick/TimelineCanvas.qml#L4) root 57.10 ms. Building the roll band once. Expected; no action.
- [TimelineCanvas.qml:70](../../src/ui/songview/quick/TimelineCanvas.qml#L70) — `Text` ×118, 0.85 ms total. The band-label delegates (ruler/lane labels). Bounded count, sub-millisecond total. No action.
- [DrawerChromeLayer.qml:168](../../src/ui/songview/quick/DrawerChromeLayer.qml#L168) — `Image` ×12, 1.67 ms. The drawer toggle icons — the same images the rendering profile caught loading twice (first at 1024×1024, then at display size). Creation cost here is trivial; the waste is pixmap memory, covered in the rendering report.
- [HoverHint.qml:17](../../src/ui/songview/quick/HoverHint.qml#L17) — `HoverHandler` ×88, 0.74 ms. One handler per hint delegate; static chrome, not growth. No action unless delegate counts grow unbounded in a future trace.

## Caveats

The parser reports totals, not an allocation timeline, so startup and gesture
traffic cannot be separated rigorously. The read favoring "scroll allocates
nothing" rests on two legs: hotspot counts are all consistent with window
setup, and the C++ paint-node design gives scrolling nothing to allocate.
The session was also short (62 s); the full-profile run is the place to
confirm with frame-correlated data.

## Recommendations

1. **Nothing to fix in QML memory.** No per-frame allocation, no large items, no growth pattern.
2. The one memory fix on the table remains the drawer-chrome double load from the rendering report (gate `source` on known size or cap the provider default).
3. If a future trace ever shows high-count `Creating` on `Text` delegates during scroll, that means the label models are churning row structure per frame instead of rebinding — check `TimelineQuickTextModel::setRecords` diffing first.
