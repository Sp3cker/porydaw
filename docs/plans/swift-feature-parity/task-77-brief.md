# Task 77 brief — content-space roll scene: one camera transform replaces per-row geometry re-emission (77a static layers, 77b note/overlay layers)

# Context

Window resize and scroll currently re-emit the roll's static geometry row by
row. A 40-step resize sweep (`sample` during `/tmp/resize_sweep.scpt`, profile
`/tmp/sample_resize.txt`) shows 92% of main-thread samples in:
`PianoGrid.configureViewport` (`src/swift/app/roll/PianoGrid.swift:329`) →
`DocumentSession.mutateCamera` → `DocumentWorkspace.cameraDidChange`
(`src/swift/app/DocumentWorkspace.swift:352-353`, unconditional
`grid.refreshCamera()`) → `GridScene.rebuildStatic`
(`src/swift/app/roll/GridScene.swift:379-477`) → `GridScene.sync`
(`GridScene.swift:218-230`, `model[i] =` → one dataChanged per row). Only ~3%
is `rebuildNotes`; notes are tick-derived and edge-culled.

1. **Why guards cannot fix it — the geometry itself is viewport-baked.**
   `rebuildStatic` sizes stripes with `snapshot.viewportWidth`
   (`GridScene.swift:384,399`), time lines with `snapshot.rollHeight`
   (`:385,430`), positions rows with `rowTop(..., scrollY: snapshot.scrollY)`
   (`:390-395`) and lines with `camera.displayX` (`:425`), which subtracts
   scroll (`EditorCamera.swift:223-228`). `PianoGrid.staticInputsChanged`
   (`PianoGrid.swift:1236-1242`) compares the *full* camera snapshot, so every
   scroll/resize step legitimately dirties the static scene: ~300
   `pianoGridRows` writes per width change, `pianoGridTime` per height change,
   ×4 per geometry step (root/trackHeaders/rollPlot width+height handlers all
   call `configureViewport`, `EditorSurface.qml:203-204,257-263,442-447`, plus
   band/status height handlers `:1203,1216`). Coalescing and idempotence were
   tried and failed: each trigger produces distinct geometries, and
   `Qt.callLater` broke synchronous-geometry consumers in the roll lane
   (user-measured; do not retry).
2. **Coordinate-space facts** (`src/swift/app/timeline/EditorCamera.swift`):
   `Snapshot` (`:118-129`) carries `scrollX/scrollY` plus viewport
   `viewportWidth/rollHeight`; despite its name, `contentX(tick:)` (`:223`) is
   viewport-relative (`tick * pixelsPerTick - scrollX`); `displayX` (`:225`)
   dpr-snaps that value. The *unscrolled* content x of a tick is
   `tick * pixelsPerTick`; `minHScroll` is negative pre-run (`-leadPad`,
   `:214-215`); `maxHScroll` is the full song width in px (`:216-218`);
   `maxVScroll = projection.totalHeight - rollHeight` (`:219-221`).
   `PitchProjection.rowTop/rowBottom` (`:54-62`) bake `scrollY` through
   `snappedEdge` (`:85-89`); no scroll-free row API exists yet.
   `PitchProjection` itself is `Equatable`, `TimeAxis` is `Equatable`
   (`src/swift/app/timeline/TimeAxis.swift:67`), so a reduced static key is
   expressible without new identity machinery.
3. **Renderer consumes rects unchanged.** Stripes/lines render through the
   QtBridge `QuickDisplayList` batch (`PianoRollCanvas.qml:13-29,82-98`): the
   C++ `QuickDisplayListItem`
   (`build/_deps/qtbridge-src/Sources/QtBridgeCpp/quickdisplaylistitem.cpp:81-153`)
   reads only the `x/y/width/height/fillColor` roles, never reads its own item
   width/height, applies no culling or scissor of its own, and honors the
   ordinary QQuickItem transform of whatever item hosts it; any model signal
   rebuilds the whole vertex snapshot. Clipping already exists at the QML
   ancestors (`rollPlot` clip, `EditorSurface.qml:442-447`; ruler strips
   `:288,301`; `rollGutterSide` in the same block), and a translated
   scroll container is an established pattern in this surface
   (`TrackHeaderBand.qml` `translatedRows` with `y: -headersModel.scrollY`).
4. **Design.** Swift publishes static scene geometry in absolute content
   coordinates — x = dpr-snapped `tick * pixelsPerTick` (origin tick 0, pre-run
   at x<0), y = dpr-snapped `row * keyHeight` (origin row 0) — with extents
   independent of viewport size. QML applies the camera as one translation per
   side, reusing the already-published `cameraScrollX/cameraScrollY/
   devicePixelRatio` (`PianoGrid.swift:104-111`, published by `publishGeometry`
   `:1300-1321`): container `x = -round(scrollX*dpr)/dpr`,
   `y = -round(scrollY*dpr)/dpr`, so snapped content coords plus snapped
   translation both stay on the physical pixel grid. What must still rebuild
   on scroll/zoom — the visible time-line/ruler range and note x-culling — is
   bounded by a provisioned content window whose edges are quantized to
   1024-px chunks and re-derived only when the visible range leaves the window
   minus a one-chunk margin. Pure resize/scroll then emits zero per-row
   updates; window flips (every ~2 viewports of travel) are the only static
   re-emission. No new C++; the vendored renderer is consumed as-is.

# Exact write set

**77a — static layers in content space + camera containers:**

- `src/swift/app/timeline/EditorCamera.swift` — add
  `contentTickX(tick:dpr:) -> Double` (dpr-snapped unscrolled x) and
  `PitchProjection.contentRowTop/contentRowBottom(row:keyHeight:dpr:)`
  (snapped `row * keyHeight`, no scroll). Existing APIs and `Snapshot`
  unchanged.
- `src/swift/app/roll/GridScene.swift` — `rebuildStatic` publishes
  `pianoGridRows`, `pianoGridTime` (incl. pre-run mask as a content-space rect
  spanning the extent's left edge to x=0), `pianoKeyboardKeys`,
  `pianoKeyboardTextModel`, `rulerMarks`/`rulerTextModel` (incl. the ruler
  pre-run mask moved out of `rulerChrome`), and the `rebuildHover` keyboard
  highlight/separator in content space; adds the chunked provisioned window,
  a recorded static key with early-out before any array allocation, and
  records the window it published.
- `src/swift/app/roll/PianoGrid.swift` — delete
  `staticCameraSnapshot`/`staticInputsChanged`/`recordStaticInputs` snapshot
  comparison (`PianoGrid.swift:80,1236-1251`); `staticSceneDirty` and every
  content-invalidation path that sets it stay verbatim.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — add translated
  containers `plotContent` (inside `rollPlot`), `gutterContent` (inside
  `rollGutterSide`), `rulerContent` (inside the ruler plot strip,
  `EditorSurface.qml:297-330`), each bound to the snapped negative
  `cameraScrollX/cameraScrollY`; pass `plotContent`/`gutterContent` to
  `PianoRollCanvas`.
- `src/ui/songview/quick/PianoRollCanvas.qml` — reparent the 77a layers
  (`timelineQuickPianoGridRows/Time/KeyboardKeys/KeyboardHighlights`,
  keyboard text) to the content sides; note/preview/border/overlay/note-text
  items stay on `plotSide` (viewport space) until 77b; loading text and hover
  chip stay viewport-space permanently.
- `src/checks/rollcheck/EditorGridCameraChecks.swift` — re-express the
  `checkProjection` mark-window predicates (`:215-238`) against content-space
  x plus the provisioned window.

**77b — note/overlay layers in content space + profiles:**

- `src/swift/app/timeline/GridGeometry.swift` — add
  `GridMetrics.noteContentRect/noteContentBox` (content x in, content rows;
  `noteRect/noteBox` at `:399-417` stay for viewport consumers).
- `src/swift/app/roll/GridScene.swift` — `buildNoteFills`,
  `emitNoteSelection`, `emitNoteRemainder` (draw preview, selection band,
  time-selection band, loop glows/edges) in content space: x-cull to the
  provisioned window, drop the y cull (content height is bounded by 128 rows),
  heights become `projection.totalHeight(keyHeight:)`, viewport clamps become
  window/extent clamps; `NoteFillKey` drops the snapshot's scroll/viewport
  fields and keys on zoom/projection/mode inputs plus the window edges.
- `src/swift/app/roll/PianoGrid.swift` — refresh the hover chip when
  `scrollY` changes while `hoverKey >= 0` (one `hoverChipRect` dict write;
  the chip stays viewport-clamped in `bandSide`); hit testing
  (`hitZone`/`hitNote`/`pitch(atY:)`), `projectedNoteBox`,
  `configureViewport`, `publishGeometry` stay verbatim.
- `src/ui/songview/quick/PianoRollCanvas.qml` — move
  `timelineQuickPianoNoteFills/DrawPreviewFill/NoteBordersAndSelection/Overlay`
  and the note-text Repeater onto the content side.
- `src/checks/rollcheck/EditorGridCameraChecks.swift` — re-express the note
  and drag-preview geometry predicates (`:246-265`, `:295-315`) against
  `contentTickX`/`contentRowTop`.
- `src/checks/rollcheck/ruler_loop_menu.swift` — re-express the loop
  glow/edge predicates (`:359-389`) from `y == 0 && height == rollHeight` and
  `[0, width]` clamps to content height and window/extent bounds.
- `src/checks/rollqml/tst_SwiftRollPlots.qml` — adjust the note-delegate
  expected-x helper (`:345-354`) for the container translation, and only if
  the lane is red.

No ledger flips (no behavior-parity rows move; this is a representation
change). No new files, no CMake, no C++, no new bridge properties: scroll
reaches QML only through existing `cameraScrollX/cameraScrollY/
devicePixelRatio`.

# Prerequisites

- Tasks 75/76 landed: the tree carries in-flight edits to
  `EditorSurface.qml` (task 76 grid-menu loader), `PianoGrid.swift`,
  `ruler_loop_menu.swift` and siblings from the ED12 batch. Rebase this
  brief's write set onto the settled files before dispatch; 77's regions
  (viewport plumbing, scene rebuild, loop-glow predicates) are disjoint from
  72's `performCommand`/`stopAudition` and 76's menu loader, but serialize
  same-file edits.
- Before any 77a code lands, capture the before-profiles on the native host:
  the resize baseline already exists (`/tmp/sample_resize.txt` via
  `/tmp/resize_sweep.scpt`); capture a scroll baseline the same way
  (`sample` the running app during a sustained horizontal+vertical scroll
  sweep, e.g. wheel/scrollbar drags across several viewports, saved as
  `/tmp/sample_scroll_before.txt`).

# Interface contract

- `EditorCamera.contentTickX(tick: Double, dpr: Double) -> Double` —
  `(tick * pixelsPerTick * dpr).rounded() / dpr`; equals `displayX(tick: 0…
  origin: 0)` at `scrollX == 0`, so rest-state rendering is bit-identical to
  today.
- `PitchProjection.contentRowTop/contentRowBottom(_:keyHeight:dpr:)` — the
  scroll-free row edges (`rowTop(..., scrollY: 0, ...)` semantics, named).
- `GridScene.rebuildStatic(_ input: GridSceneInput)` — signature unchanged.
  Behavior: derives the provisioned window — left edge
  `chunkFloor(minHScroll)`, right edge
  `chunkCeil(maxHScroll) + ceil(viewportWidth/chunk) + 1` chunks — and, for
  the windowed models (time lines, ruler marks/labels, note x-cull in 77b),
  coverage `scrollX - 1 chunk … scrollX + viewportWidth + 1 chunk`
  (intersected with the content extent, minimum three chunks); re-derives the
  coverage window only when the visible range
  `[scrollX, scrollX + viewportWidth]` exits it minus one chunk. Records a
  static key = `(pixelsPerTick, keyHeight, projection, dpr, baseFontPx,
  keyboardWidth, contentEndTick, metrics.timeAxis, palette identity,
  window edges, extent edges)` and returns before allocating any rect array
  when the key is unchanged. Pure `scrollX`/`scrollY`/`viewportWidth`/
  `rollHeight` changes that stay inside the recorded window publish nothing.
- Container law (QML): exactly one camera authority — `DocumentSession`'s
  `EditorCamera`; the containers translate by the published scroll and
  nothing else duplicates position state. Content-space models render only
  inside translated containers; viewport-space models (ruler chrome
  backgrounds, gutter chrome, loading text, hover chip, `SharedPlayhead` and
  guides, which already consume camera-projected `contentX` in untranslated
  clipped rects) never enter them — moving those in would double-apply
  scroll.
- Preservation (verified consumers): pointer input stays viewport-local
  (`tickAtContentX`, `pitch(atY:)` — no QML-side scroll math on input);
  `TrackHeaderBand` keeps its own `headersModel.scrollY` translation; drawer
  pages, `OtherEventsBand`, `velocityPage`/`voiceChangesPage`/`automationPage`
  keep their own models and refresh paths (out of scope; alignment is
  preserved because they read the same camera); scrollbars keep
  `cameraScrollX/Y` + min/max published values.
- Preservation (checks): behavioral predicates stay verbatim —
  `note_rendering.swift` relations (label-to-face insets, preview-to-label
  boxes) compare model against model and hold in either space;
  `proof.keyboard.txt`/`proof.scale_projection.txt`/`proof.scale_editing.txt`
  pin `PitchProjection.rowTop` scroll formulas, and that API is unchanged;
  `tst_TimelinePan` hover-chip assertions stay verbatim (chip remains
  viewport-space); `tst_ShellGridInput/GridMenu/NoteVisuals/DrawerParity/
  ShellTabs` compute camera-relative input/screen coordinates themselves and
  stay verbatim. Coordinate-pinning internals re-expressed: the
  `EditorGridCameraChecks` and `ruler_loop_menu` predicates named in the
  write set (and the `tst_SwiftRollPlots` helper if red) — same observable
  claims, content-space expressions.

# Implementation steps

1. **77a window + key + content APIs** (`EditorCamera.swift`,
   `GridScene.swift`, `PianoGrid.swift`): add the two content APIs; rewrite
   `rebuildStatic`'s rows/time/keys/keyboard-text/ruler/hover-highlight
   emission in content space with the provisioned window and early-out key;
   delete the snapshot comparison in `PianoGrid`. RED first: a scroll or
   resize step between two `rebuildStatic` calls with no content change must
   leave every `QListModel` untouched (assert via the existing
   `boxesProjected`-style counters or model counts in a scratch check, then
   delete the scratch).
2. **77a containers** (`EditorSurface.qml`, `PianoRollCanvas.qml`): create
   the three translated containers with snapped bindings; reparent the 77a
   layers. Keep `batched: true` and every `objectName` stable (checks locate
   items by `objectName`).
3. **77a checks**: re-express the mark-window predicates in
   `EditorGridCameraChecks.checkProjection`; run the roll lanes — visible
   framing, rasters and journeys must be unchanged.
4. **77b note/overlay content space** (`GridGeometry.swift`,
   `GridScene.swift`, `PianoGrid.swift`, `PianoRollCanvas.qml`): move
   fills/borders/selection rings/preview/overlay/note text to content
   coordinates with window x-culling; reduce `NoteFillKey`; add the
   scroll-while-hover chip refresh. Edge cases: notes extending past the
   content end (extent grows via `recomputeContentEndTick` and the key
   catches it); zoom re-basing `scrollX` (key includes `pixelsPerTick`);
   fold re-clamping `scrollY` (projection change rebuilds, the follow-up
   scroll clamp does not).
5. **77b checks + profiles**: re-express `EditorGridCameraChecks`
   note/drag-preview and `ruler_loop_menu` glow/edge predicates; fix the
   `tst_SwiftRollPlots` helper only if red. Capture after-profiles with the
   same scripts and compare against the 77a-prerequisite baselines.

# Acceptance predicate

- `deno task verify --filter swiftcore --verbose` — re-expressed camera/
  loop-glow predicates + regressions (covers: content-space publication,
  window coverage, no-op publication counts still exact).
- `deno task verify:qml-roll --verbose` — roll journeys/rasters (covers:
  visible framing identical, pan/scroll/zoom/resize behavior, hover chip,
  scrollbar rebase during held thumb).
- `deno task verify:qml --verbose` — editorqml chrome/note/input/tabs lanes
  (covers: camera-relative helpers, tab camera persistence, drawer parity).
- `deno task verify:shell --verbose` — all shell lanes (covers: mounted
  window-tier surfaces sharing the roll).
- `deno task verify:bridge` and `deno task format --check`.
- Native-host profiles (implementer runs, needs desktop macOS + built app):
  `sample` during `/tmp/resize_sweep.scpt` and during the scroll sweep;
  `configureViewport → refreshCamera → rebuildStatic → sync` no longer
  dominates main-thread samples, and pure resize/scroll steps produce no
  per-row model writes. Before/after files recorded in the task report.

# Task-specific constraints

- No new C++ anywhere (renderer is a vendored QtBridge dependency under
  `build/_deps`; it is consumed, not modified). If verification exposes a
  renderer defect (e.g. content-space rects mis-transformed), do not patch
  C++ — stop and report; the fallback is pre-translated publication (status
  quo), which defeats the task and needs re-planning, not improvisation.
- No code comments; Swift 6.4 idioms; skip paths must not allocate (early-out
  before array construction); base-font-derived visual geometry only — the
  1024-px chunk is culling quantization, never a visual size, and is named as
  a constant with that stated meaning.
- No `Qt.callLater`, no coalescing timers, no second position state; one
  camera authority (`DocumentSession.mutateCamera`).
- Float-precision bound (named risk, not a blocker): content x reaches
  `maxHScroll + viewport` ≈ `lengthTicks × pixelsPerTick`; float32 roles and
  the float32 transform matrix wobble by `x × 1.2e-7` (≤0.05 logical px at
  420k px content width; ~0.125 logical px at the pathological max-zoom ×
  very-long-song corner vs `maxPixelsPerBeat = fontPx(b, 160/3)`,
  `GridGeometry.swift:27`). Hairlines stay on the physical grid because both
  content coords and the translation are dpr-snapped; at rest
  (`scrollX == 0`) rendering is bit-identical to today. If the max-zoom
  long-song raster check shows shimmer, apply the designed fallback: publish
  window-relative coords and bind the container to
  `windowOrigin - scrollX` (computed in double precision) — contained to
  `GridScene` publication and two bindings.
- Batch renderer rebuilds its whole vertex snapshot on any model signal, so
  window flips must stay rare (chunk quantization + one-chunk hysteresis);
  scrolling large distances re-emits windowed models once per ~2 viewports,
  strictly better than today's per-step full re-emit.
- Selection band and loop/time-selection overlays re-emit while their inputs
  change; a scroll during an active band gesture re-emits the bounded overlay
  set (~10 rects) — accepted and gesture-scoped.
- 77a and 77b each land with all lanes green (layer split keeps notes
  viewport-space until 77b); both halves in this one brief because they share
  the window/container contract and one verification surface — the file count
  exceeds the triage default and is named as the single-behavior exception.
- Implementers never edit ledgers; none flip here.

# Controller verification

1. After 77b settles: `deno task verify:bridge`, `deno task format --check`,
   then the full lane set above on the shared tree; no lane may regress
   against the pre-77 run.
2. Re-run the profile protocol on the settled tree (native desktop:
   `/tmp/resize_sweep.scpt` + scroll sweep under `sample`); confirm the
   resize/scroll hot path is transform-only and record before/after paths.
3. Visual parity spot-check against the fork reference (`fceecd88`,
   `build-asan/porydaw.app` in the main checkout): roll captures at home
   scroll (must be pixel-identical) and at a non-zero scroll (tolerance ≤1
   physical px on hairlines).
4. Confirm serialization: task 75/76 files show no diff from this task
   beyond the regions named above.

# 77a implementation evidence

77a publishes the static roll, keyboard, and ruler layers in content
coordinates, with the existing camera scroll applied by clipped QML
containers. Static publication now skips before rect allocation while the
recorded content window and inputs remain unchanged. Ruler chrome remains
viewport-local and uses the provisioned extent width.

Review fix 1 widened the provisioned window to two chunk-rounded viewport
widths of padding on each side, retaining the one-chunk eviction margin.
Clipped extent edges do not impose an unreachable margin. This replaces the
initial one-chunk padding, which thrashed at chunk-boundary reversals.
The permanent `contentWindowBoundaryReversal` check proves six 1023↔1025
reversals retain published time marks, monotonic travel provisions no more
often than every two viewports, and a reverse step immediately after
reprovision retains that new window. Its first two predicates failed before
the fix. RED/green evidence is `/tmp/task77a-window-reversal-red.log` and
`/tmp/task77a-window-reversal-green.json`.

Coordinate-only check helpers in `tst_TimelinePan.qml`,
`tst_ShellGridMenu.qml`, `tst_ShellMenus.qml`, and `tst_TextContrast.qml` map
realized content delegates into their viewport before making the original
assertions. These helper adaptations were authorized after the lanes exposed
their old direct-parent coordinate assumptions. Assertion messages remain
unchanged.

The native fixture was `decompproject` / `mus_littleroot_test`, launched from
`build/porydaw.app`. Resize used `/tmp/resize_sweep.scpt` and a 10-second,
1-ms `sample`; scroll used `/tmp/task77a-scroll.swift` (32 alternating
two-axis middle-button drags after the same wheel-zoom preparation) and a
12-second, 1-ms `sample`. Inclusive main-thread sample counts:

| Path | Before | After |
| --- | --- | --- |
| Resize: `configureViewport` | 5,719 / 6,222 (91.92%) | 1,724 / 6,425 (26.83%) |
| Resize: `rebuildStatic` | 5,320 / 6,222 (85.50%) | 1,264 / 6,425 (19.67%) |
| Scroll: `rebuildStatic` | 6,835 / 7,688 (88.90%) | 14 / 8,163 (0.17%) |

Resize sweep elapsed time fell from 9.91 s to 3.99 s. The fixed sampling
interval includes the additional idle time after the faster sweep; occasional
chunk/extent changes still rebuild static models. Profiles are
`/tmp/sample_resize_before_77a.txt`, `/tmp/sample_resize_after_77a_round1.txt`,
`/tmp/sample_scroll_before.txt`, and `/tmp/sample_scroll_after_77a_round1.txt`;
the numeric summary is `/tmp/task77a-round1-profile-summary.json`.

The temporary RED/green checks proved unchanged static model record identities
for in-window resize and two-axis scroll, including mounted keyboard/ruler
text, then were removed. Evidence is `/tmp/task77a-red.log` and
`/tmp/task77a-static-proof.json`.

All named verification lanes passed, including all 26 shell entries.
After the review fix, `swiftcore`, `verify:qml-roll`, `shell-grid-menu`,
and `shell-grid-input` passed again; the native app was rebuilt and profiled.
The repository format gate passed using Xcode's `clang-format` through
`CLANG_FORMAT`; it warns that version 21 differs from CI's version 22.
Explicit changed-file formatting is unsupported by the repository runner for
Swift, QML, and Markdown, so those files have no applicable formatter gate.
The proof reader resolved all 8,088 anchors; no ledger edits were needed.
The separately authorized task-73 follow-up in `tst_ShellEventList.qml` waits
for the pointer toggle's queued visible-page focus landing before explicitly
focusing the toggle; its existing Delete/focus assertions are unchanged.

# 77b implementation evidence

Note fills, previews, borders, selection/time bands, loop overlays, and note
text now publish content coordinates and render under `plotContentSide`.
Notes use the shared provisioned window for horizontal culling and retain all
projected pitch rows. The fill key excludes camera scroll and viewport
dimensions; pan and non-geometric gestures reuse cached note geometry.
The hover chip stays viewport-local and refreshes when its camera or viewport
height changes; unchanged chip geometry is not republished.

Coordinate-only Swift/QML check helpers now map note models and delegates
into the correct space. Mounted checks wait for the camera transform to
render before reading delegate-to-input coordinates. The small-font raster
fixture captures its font through a fresh shell's typography authority
instead of temporarily overriding the mounted grid's viewport font.
Behavioral messages remain unchanged except the authorized retirement of
“a camera move still reprojects the note boxes.” Its replacements verify the
camera-translated viewport position and zero note-box/fill work on an
in-window scroll. No proof anchor references the retired message.

All named gates passed: `build:checks`, `swiftcore`, `verify:qml-roll`,
`verify:qml`, all 26 shell entries as bounded per-entry commands,
`verify:bridge`, and `format --check`. The proof reader resolved all 8,088
anchors without errors or ledger edits. Formatting used Xcode's
`clang-format` 21 and retained the CI-version-22 warning. SourceKit semantic
diagnostics were unavailable because its standard-library load failed;
declaration inspection and the covering builds supplied structural evidence.
Temporary smoke checks proved record identity retention for fills, borders,
overlays and note text across resize/two-axis scroll, stationary-hover chip
movement, and offscreen-pitch note retention, then were removed.
Evidence is `/tmp/task77b-swiftcore-smoke.log` and
`/tmp/task77b-shell-results.json`; final gate logs use `/tmp/task77b-*.log`.

Native profiling used the same fixture and 40-step resize / 32-drag scroll
protocol, with 10-second / 12-second samples at 1 ms. Resize targeted only
the owned PID through System Events. The scroll sweep checked ownership
before every mouse event and aborted on any foreground-PID change. Direct
PID-posted mouse trials delivered no pan events and are excluded; the valid
existing 77a scroll captures supply the before baseline. The owned instances
exited, foreground focus was restored, and the preference plist was restored
exactly. Inclusive main-thread sample counts:

| Path | Before 77 | Before 77b | After 77b |
| --- | --- | --- | --- |
| Resize: `rebuildStatic` | 5,320 / 6,222 (85.50%) | 0 / 6,241 (0.00%) | 1,244 / 5,812 (21.40%) |
| Resize: `rebuildNotes` | 276 / 6,222 (4.44%) | 768 / 6,241 (12.31%) | 9 / 5,812 (0.15%) |
| Scroll: `rebuildStatic` | 6,835 / 7,688 (88.90%) | 14 / 8,163 (0.17%) | 115 / 6,647 (1.73%) |
| Scroll: `rebuildNotes` | 6 / 7,688 (0.08%) | 15 / 8,163 (0.18%) | 29 / 6,647 (0.44%) |

Resize elapsed time was 3.69 s before 77b and 4.66 s after; sampled static
chunk/extent changes vary between sweeps, so these are not a claim of a
77b end-to-end speedup. Roll scene rebuilding no longer dominates either
workload. Profiles are `/tmp/sample_resize_before_77b.txt`,
`/tmp/sample_resize_after_77b.txt`, and
`/tmp/sample_scroll_after_77b_focused.txt`, with the earlier baselines named
above. `/tmp/task77b-profile-summary.json` records the comparison. The home
roll crop `(980,238)-(2370,810)` in `/tmp/task77b-after-home.png` is
pixel-identical to `/tmp/task77a-round1-before-sweep.png`;
`/tmp/task77b-after-scroll.png` records the exercised scrolled surface.

## 77b review fix 1

The focused `EditorGridCameraChecks` regressions first failed for a stationary
hover chip on a height-only shrink and for static records on repeated
1,023/1,025-wide reversals. The chip now considers every effective layout
dependency without adding camera state or rebuilding static models.
Content-window extents retain padded capacity across width-only changes;
the snapped content end invalidates that capacity when the domain changes.
The existing window-eviction margin still controls horizontal reprovisioning.
Both regressions then passed, including bottom-clamp restoration on growth
and static-record identity retention. RED/GREEN logs are
`/tmp/task77b-round1-red.log` and `/tmp/task77b-round1-swiftcore.log`.

The identical 40-step native resize sweep was sampled twice after the fix:

| Path | Initial 77b | Review fix, run 1 | Review fix, run 2 |
| --- | --- | --- | --- |
| Elapsed resize | 4.66 s | 2.13 s | 1.54 s |
| `configureViewport` | 1,382 / 5,812 (23.78%) | 151 / 6,448 (2.34%) | 150 / 6,942 (2.16%) |
| `rebuildStatic` | 1,244 / 5,812 (21.40%) | 1 / 6,448 (0.02%) | 0 / 6,942 (0.00%) |
| `rebuildNotes` | 9 / 5,812 (0.15%) | 12 / 6,448 (0.19%) | 13 / 6,942 (0.19%) |

Profiles are `/tmp/sample_resize_after_77b_round1_1.txt` and
`/tmp/sample_resize_after_77b_round1_2.txt`. The repeated guarded scroll
sweep in `/tmp/sample_scroll_after_77b_round1.txt` sampled static rebuilding
at 71 / 5,667 (1.25%) and note rebuilding at 37 / 5,667 (0.65%).
The owned PID exited normally, focus was restored, and preferences were
restored. `build:checks`, `swiftcore`, both QML suites, all 26 shell entries,
the bridge gate, and proof-anchor resolution passed again; logs use
`/tmp/task77b-round1-*.log` and shell results are
`/tmp/task77b-round1-shell-results.json`. No ledger was edited.
