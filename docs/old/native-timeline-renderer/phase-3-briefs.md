# Phase 3 — Ruler on the native renderer

Plan: `docs/old/native-timeline-renderer/plan.md` (Contract, blob table, Decision 5, §8 phase 3).
Spec for every pixel: HEAD's `rebuildRuler` (`git show HEAD~0:src/swift/app/roll/GridScene+Rebuild.swift`,
function `rebuildRuler` and `maxRulerBar`) and HEAD `src/ui/songview/quick/swiftroll/EditorRulerBand.qml`.
Prior art: the pre-Swift C++ ruler `/Users/sallegrezza/dev/cProjects/porydaw/src/ui/songview/quick/timerulerquick.cpp`.

The roll blob already carries everything the ruler draws: §1 metrics (`spaceHalf`, `spaceTwo`,
`detailMinPxPerBeat`, `rulerBeatLabelZoomFactor`), §2 fonts (0 ruler, 1 beat, 2 bold, 3 sig),
§3 palette (chromeBackground, separator, rulerPreRollMask, gridLine/rulerTick, primaryText,
rulerDetailText, implicitSignature), §7 timeAxis (segments with numerator/denomPow2/implicit flag,
loop ticks). No blob format change is expected; if one is needed, it must be made in the Swift writer,
the C++ decoder, `src/checks/rollcheck/roll_content_probe.swift` and the plan table together.

## Rulings

- R1 Band 2 = ruler plot strip. `TimelineRenderer { band: 2 }` draws, in viewport space with the
  same camera properties as band 0: chrome background + bottom separator over the plot width,
  pre-roll mask, subdivision ticks, beat ticks, bar marks + caps, bar/beat labels with HEAD's
  overlap skipping (`lastLabelRight`), loop markers (`[`/`]` glyph + 1px line), time-signature marks +
  labels (implicit colour, skip when the label would overrun the next signature). Visible range only;
  never walk the song span.
- R2 Label strings are formatted in C++ exactly as `GridTypography.barLabel`/`beatLabel` and the
  signature `"\(numerator)/\(1 << min(denomPow2, 6))"`; advances via the same `sgf_*` metrics as the
  roll labels; ascent/height from the same font metrics GridTypography uses.
- R3 `maxRulerBar` (beat-label width reserve) is computed per frame from the visible end tick.
- R4 Checks locate loop markers through the existing `noteFace(primitiveName)` accessor extended to
  the names `"loopStartMarker"` / `"loopEndMarker"` on band 2 (same approved check accessor; no new
  API). It returns the marker line rect `{x,y,width,height,fill}` in renderer-local coordinates.
- R5 The gutter chrome (`rulerGutterChrome`: two static rects in the keyboard column) becomes two plain
  QML `Rectangle`s in `EditorRulerBand.qml` sized from existing bindings; they are camera-free.
- R6 Swift retires `rebuildRuler`, `maxRulerBar`, `rulerMarks`, `rulerTextModel`, `rulerChrome`,
  `rulerGutterChrome`, `rulerTextSignatures`, `StaticKey` and `ContentWindow`/`contentWindow`/
  `visibleTicks` when nothing else reads them; `cameraScroll` stays while `grep cameraScroll src/ui`
  is non-empty. `rebuildHover` stays.

## Task 3a — C++ ruler band (sdd-implementer)

Write set: `src/render/*` (+ root `CMakeLists.txt` source list if a new file). Implement R1–R4 in a
new `src/render/ruler_scene.{h,cpp}` following `roll_scene.{h,cpp}` (free phase builders, Frame in,
rects/labels out), wired into `TimelineRenderer` for `band == 2`. Reuse the existing segment walk /
`forEachGridLine` port and label/text node pipeline; no duplication of roll helpers (move shared bits
to a shared header if needed).

## Task 3b — Swift ruler retirement (sdd-implementer)

Write set: `src/swift/app/roll/*`. Implement R6: the ruler no longer rebuilds on camera changes and the
camera-only refresh path does no ruler work. Every content input the ruler draws must already bump
`contentRevision` (loop ticks and time signatures are in §7; verify they are in the content key).

## Task 3c — Ruler QML cutover (sdd-implementer, after 3a+3b)

Write set: `src/ui/songview/quick/swiftroll/EditorRulerBand.qml`. Replace the marks item + text Repeater
+ chrome items with one `TimelineRenderer { band: 2 }` placed in the ruler viewport (not a translated
container), keeping objectName `timelineQuickRulerMarks` on the renderer; R5 gutter rectangles; pin the
`rulerContent` translation away (delete it) if nothing else needs it. Input handlers stay.

## Task 3d — Ruler checks migration (qt-check-fixer, after 3c; split per file group)

Consumers of the retired models/items: `src/checks/editorqml/{ShellGridMenuSupport,ShellNoteVisualsSupport}.qml`,
`tst_EditorDrawerChrome.qml`, `tst_ShellChromeVisuals.qml`, `tst_ShellEventList.qml`,
`tst_ShellGridMenuRulerLifecycle.qml`, `tst_ShellGridMenuRulerMarkers.qml`, `tst_ShellMenusLoop.qml`,
`tst_ShellNoteVisuals.qml`, `tst_ShellNoteVisualsRuler.qml`, `src/checks/rollqml/{tst_SwiftRollPlots,tst_SwiftRollTrackHeaders}.qml`,
`src/checks/nativegraphics/SharedPlayheadChecks.swift`, plus Swift checks reading `ContentWindow`/ruler
models. Marker geometry via R4; painted detail via raster; Swift checks via `RollContentProbe`.
Keep message literals; report every changed message.

## Verification (controller)

`deno task build:checks`; `deno task checks --filter swiftcore --verbose`; `deno task checks:qml-roll --verbose`;
`deno task checks:shell --verbose`; `deno task checks:qml --verbose`; `deno task proof check --executed`.

## Global constraints

Swift 6, QML, C++ only in `src/render/`. No code comments. Geometry from base font px (metrics slots).
No workarounds; report instead. Scoped searches. No commits. Do not run `deno task` commands unless the
dispatch says you may.
