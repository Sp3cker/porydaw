# Rendering profile — porydaw note rendering (scroll + zoom)

## Header

- App: `build-profile/porydaw.app/Contents/MacOS/porydaw` (RelWithDebInfo + `QT_QML_DEBUG`)
- Profiler: `qmlprofiler --include scenegraph,animations,painting,pixmapcache`
- Trace: `profiler/traces/qmlprofiler-trace-porydaw-rendering-2026-09-18-113851.qtd` (20 KB)
- Totals: 130 events, 0.0 ms of range-event time, 0 hotspots
- Pixmap cache: 17 load requests, 17 loaded, 34 removed

## Bottom line

This trace contains **no frame data**: zero scene-graph, painting, or
animation events. The per-frame cost of note rendering during scroll/zoom is
therefore still unmeasured. The most likely cause is session discipline, not
the app: Qt Quick only renders visible windows, so a minimized, fully
occluded, or idle window produces exactly this — a trace with cache traffic
but no frames. A follow-up run with the window frontmost and continuous
gesturing is needed for frame numbers (planned as the full-profile run).

## The one concrete finding: drawer-chrome icons load twice, first at full size

The pixmap-cache section shows every `image://drawerchrome/` icon requested
first at 1024×1024 (~4 MB each: `detent`, `velocity`, `automationOn`,
`voiceChanges` and checked variants) and then again at display size (22×22,
11×11). Removals (34) double loads (17): the full-size entries are cached and
then evicted.

Root cause is a two-sided handshake with a gap:

- QML binds the request size to layout:
  [DrawerChromeLayer.qml:168](../../src/ui/songview/quick/DrawerChromeLayer.qml#L168)
  sets `sourceSize.width/height: width/height`. At component creation those
  are still 0.
- The C++ provider treats "no size" as "full size":
  [drawerchrome.cpp:84](../../src/ui/editordrawer/drawerchrome.cpp#L84)
  (`requestImage`) returns the unscaled image when `requestedSize` is empty
  instead of a display-sized default.

So each toggle/detent icon does one 4 MB load at creation plus one correctly
sized load after layout — roughly 24 MB of transient pixmap traffic for the
drawer chrome on every window open, all evicted afterwards. This is chrome,
not note fills, but it is the largest measured memory traffic in any trace so
far.

Candidate fix (not applied): gate the QML `source` on known size so no
request fires while the size is zero, e.g. only set the `image://…` URL once
`width > 0 && height > 0`; or cap the provider's empty-`requestedSize` path to
a sane default. Either side alone eliminates the double load. Verify with a
memory-profile run: the 1024×1024 entries should disappear.

## Recommendations

1. **Re-run with the window frontmost** and 15–20 s of continuous scroll/zoom
   for scene-graph frame data (folded into the full-profile run).
2. **Fix the drawer-chrome double load** as sketched above — small, isolated,
   and directly supported by this trace.
3. Keep note fills in the C++ paint nodes; nothing here contradicts that.
