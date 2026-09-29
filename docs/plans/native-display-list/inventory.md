# Formula duplication inventory (2026-09-28)

Source: FormulaDupInventory scout, verified against source. Referenced by plan.md.

## 1. Formulas present in both C++ and Swift

| Quantity | C++ symbol and verified source | Swift symbol and verified source | Swift production use |
|---|---|---|---|
| Physical-pixel/DPR snap | `Camera::scrollOriginX/Y`, `contentTickX`, `contentRowEdge`: `src/render/roll_projection.h:33-40` | `EditorCamera.displayX`, `contentTickX`: `src/swift/app/timeline/EditorCamera.swift:231-240`; row snap `PitchProjection.snappedEdge`: `:95-99` | Roll hit-testing `src/swift/app/roll/PianoGrid+SceneSync.swift:245-250`; band intersection `PianoGrid+Gestures.swift:102-107`; camera reveal `EditorCamera.swift:337-352`; drawer automation/voice/velocity callers listed in §3 |
| `scrollOrigin` / snapped scroll | `Camera::scrollOriginX/Y`: `src/render/roll_projection.h:34-35` | No same-named Swift method; equivalent rounding in `EditorCamera.displayX`: `src/swift/app/timeline/EditorCamera.swift:233-240`; velocity `scrollOffsetX`: `src/swift/app/drawer/velocity/VelocityProjection.swift:39-43` | Velocity delegate scroll alignment; roll and drawer x projection |
| Content tick x / display x | `Camera::contentTickX`, `viewX`: `src/render/roll_projection.h:36-37` | `EditorCamera.contentX`, `tickAtContentX`, `displayX`, `contentTickX`: `src/swift/app/timeline/EditorCamera.swift:231-240` | Roll gestures, hit-testing, ruler menu, playhead, pitch-bend, automation, voice, velocity; exact call sites §3 |
| Row top/bottom | `contentRowEdge`, `viewRowTop`, `viewRowBottom`: `src/render/roll_projection.h:38-40` | `PitchProjection.rowTop/rowBottom/contentRowTop/contentRowBottom`: `src/swift/app/timeline/EditorCamera.swift:54-70`; `snappedEdge`: `:95-99` | Hover chip `src/swift/app/roll/GridScene.swift:157-160`; note geometry `src/swift/app/timeline/GridGeometry.swift:403-407`; keyboard/check helpers |
| Note rectangle | `RollProjection::noteBox`: `src/render/roll_projection.h:49-60` | `GridMetrics.noteRect` and `noteBox`: `src/swift/app/timeline/GridGeometry.swift:399-417` | Production hit zone `src/swift/app/roll/PianoGrid+SceneSync.swift:245-250`; band selection `PianoGrid+Gestures.swift:102-107`; `projectedNoteBox` is check-only (`src/checks/rollcheck/selection.swift:8-18`) |
| Note content rectangle | No separately named C++ content-rect function; C++ `noteBox` is the rendered content rectangle: `src/render/roll_projection.h:49-60` | `GridMetrics.noteContentRect`/`noteContentBox`: `src/swift/app/timeline/GridGeometry.swift:419-439` | No production caller found; used by check support `src/checks/rollcheck/note_rendering_support.swift:20-35` |
| Border/ring pixel counts | `Camera::noteBorderPixels`, `selectionRingPixels`: `src/render/roll_projection.h:42-47`; frame fitting `fittedFrameThickness`: `:62-68`; uses `roll_scene.cpp:49-70` | `GridMetrics.noteBorderPixels`, `selectionRingPixels`, `fittedFrameThickness`: `src/swift/app/timeline/GridGeometry.swift:442-455` | Swift copies are not used by production renderer; C++ owns painted borders/rings. Swift copy is check/support-visible only |
| Adaptive grid stride | `gridTicksAt`: `src/render/roll_projection.h:102-120` | `RollGrid.adaptiveTicks`, `gridTicksAt`, `snapTicksAt`: `src/swift/app/timeline/GridGeometry.swift:174-205` | Swift visible/snap grid publication `src/swift/app/roll/PianoGrid+SceneSync.swift:187-188`; gesture snapping `src/swift/app/roll/GridGesture.swift:115-133,167-180`; renderer grid uses C++ |
| Sub-grid visibility | `drawsSubGridIn`: `src/render/roll_projection.h:123-135` | `RollGrid.drawsSubGridIn`: `src/swift/app/timeline/GridGeometry.swift:215-224` | Swift snapping/cell policy; C++ raster grid |
| Subdivision walk | `forEachSubdivision`: `src/render/roll_projection.h:138-165` | `RollGrid.forEachSubdivision`: `src/swift/app/timeline/GridGeometry.swift:309-345` | Swift checks/grid-domain queries; C++ plot/ruler/drawer raster at `src/render/roll_scene.cpp:181-200`, `ruler_scene.cpp:87-90`, `drawer_scene.cpp:48-60` |
| Bar/beat walk | `forEachGridLine`, `forEachNumberedGridLine`: `src/render/roll_projection.h:167-211` | `TimeAxis.forEachGridLine`: `src/swift/app/timeline/TimeAxis.swift:101-155` | C++ ruler labels/ticks `src/render/ruler_scene.cpp:99-188`; Swift ruler menu uses tick conversion and snapping (`RulerMenuPresenter.swift:108-162,324-340`) |
| Key name | `RollProjection::keyName`: `src/render/roll_projection.h:213-220`; cached renderer use `src/render/timeline_renderer.cpp:31-34` | `GridScene.keyName`: `src/swift/app/roll/GridScene.swift:193-195` | Swift hover chip/keyboard and content packing (`RollDrawingContent.swift:260,300`); C++ keyboard/note labels |
| Black-key predicate | `RollProjection::isBlackKey`: `src/render/roll_projection.h:221-227` | `GridScene.isBlackKey`: `src/swift/app/roll/GridScene.swift:189-191` | Swift content packing `src/swift/app/roll/RollDrawingContent.swift:260,300`; C++ keyboard/grid rendering `src/render/timeline_renderer.cpp:471`, `roll_scene.cpp:437` |
| sRGB linearization/luminance | `srgbToLinear`, `relativeLuminance`: `src/render/roll_projection.h:232-247` | `PaletteMath.relativeLuminance` and table: `src/swift/app/timeline/GridPalette.swift:133-141` | Swift palette/theme production; C++ text ink selection |
| Contrast ratio/ink | `contrastRatio`, `contrastingTextColor`, `aaContrastInk`: `src/render/roll_projection.h:249-275` | `PaletteMath.contrastRatio`, `contrastingTextColor`, `aaContrastInk`: `src/swift/app/timeline/GridPalette.swift:144-164`; `noteLabelInk`: `:265-268` | C++ note/velocity label ink `src/render/timeline_renderer.cpp:432-454`; Swift palette/content production and note-label publication |
| Note-name face fit | C++ inline gate in `TimelineRenderer::appendNoteLabels`: `src/render/timeline_renderer.cpp:445-454` | `NoteNameLabels.faceFits`: `src/checks/rollcheck/note_name_labels.swift:21-39` | Swift copy is check-only; production renderer uses C++ |
| Note-name width fit | C++ `note.box.w >= spaceHalf + width + spaceTwo`: `src/render/timeline_renderer.cpp:457-465` | `NoteNameLabels.nameFits`: `src/checks/rollcheck/note_name_labels.swift:41-59` | Swift copy is check-only; production renderer uses C++ |
| Ruler tick/display geometry | C++ `visibleTick`, `viewX`, label reservation/gates: `src/render/ruler_scene.cpp:20-28,60-90,98-188` | Swift camera `displayX`/`tickAtContentX`: `src/swift/app/timeline/EditorCamera.swift:231-240`; Swift time walk `TimeAxis.forEachGridLine`: `src/swift/app/timeline/TimeAxis.swift:101-155` | Swift ruler interaction/menu only; C++ owns ruler raster/layout |
| Keyboard row geometry | C++ `appendKeys`: `src/render/roll_scene.cpp:402-447`; label rows `timeline_renderer.cpp:457-500` | Swift row projections and hover chip: `src/swift/app/roll/GridScene.swift:156-180` | Swift hover chip is production; C++ owns keyboard paint and labels |
| Loop edge/glow geometry | C++ `appendLoop`: `src/render/roll_scene.cpp:348-400` | Swift has only palette/content slots `loopEdge`, `loopGlow`: `src/swift/app/roll/RollDrawingContent.swift:19-20` | No Swift production geometry copy; C++ owns loop raster |
| Drawer tick projection | C++ `DrawerScene::displayX`, grid and section conversion: `src/render/drawer_scene.cpp:10-12,36-66,116-129` | Automation `AutomationProjection.x/contentX`: `src/swift/app/drawer/automation/AutomationProjection.swift:137-152`; voice `xForTick`: `src/swift/app/drawer/voicechanges/VoiceChangesScene.swift:157-168`; velocity stable x: `src/swift/app/drawer/velocity/VelocityProjection.swift:29-43` | Automation/voice/velocity production presenters and hit tests; C++ drawer raster |

## 2. Formulas present only on one side

| C++ only | Swift only |
|---|---|
| Per-frame note/grid culling: `src/render/roll_scene.cpp:181-224,236-258`; ruler visible range: `src/render/ruler_scene.cpp:60-90`; drawer visible range: `src/render/drawer_scene.cpp:36-66`. | Hit zones and note hit precedence: `src/swift/app/roll/PianoGrid+SceneSync.swift:244-286`. |
| C++ fitted font-size memo and per-frame label visibility: `src/render/timeline_renderer.cpp:300-338,430-500`. | Snapping lattice (`lattice`, floor/ceil/nearest, next snap): `src/swift/app/timeline/GridGeometry.swift:257-308`; gesture snapping callers `src/swift/app/roll/GridGesture.swift:115-180`. |
| C++ `noteFace` observable raster lookup: `src/render/timeline_renderer.cpp:206-235`. | Camera clamping/reconciliation and reveal extents: `src/swift/app/timeline/EditorCamera.swift:337-384`. |
| C++ loop glow band raster and alpha ramp: `src/render/roll_scene.cpp:348-400`. | Hover-chip placement and clamping: `src/swift/app/roll/GridScene.swift:146-180`. |
| C++ keyboard label filtering (white keys/octave C/F, drum width): `src/render/timeline_renderer.cpp:457-500`. | Roll hover/playhead/ruler-menu hit conversion via `tickAtContentX`: `src/swift/app/roll/PianoGrid+Gestures.swift:155,289,423-424`; `src/swift/app/timeline/PlayheadGuides.swift:120`; `RulerMenuPresenter.swift:108-162,324-340`. |
| C++ ruler label reservation and numbered-label placement: `src/render/ruler_scene.cpp:98-188`. | Drawer value-axis Y and hit projections: `src/swift/app/drawer/automation/AutomationProjection.swift:167-232`; voice marker hit and label elision `VoiceChangesScene.swift:163-168`, `VoiceChangesProjection.swift:382-384`; velocity Y/hit policy `VelocityProjection.swift:50-88`. |

## 3. Swift production call sites that project ticks/rows to pixels

| File:line | Formula/call | Production purpose |
|---|---|---|
| `src/swift/app/roll/PianoGrid+SceneSync.swift:245-250` | `displayX` twice → `metrics.noteRect` | Note hit zone and edge/body classification |
| `src/swift/app/roll/PianoGrid+Gestures.swift:102-107` | `displayX` twice → `metrics.noteRect` | Band-selection note intersection |
| `src/swift/app/roll/GridScene.swift:157-160` | `rowTop`/`rowBottom` | Keyboard hover-chip vertical placement |
| `src/swift/app/roll/GridGesture.swift:115-133,167-180` | `tickAtContentX`, grid snap | Draw, move, resize gesture tick mapping |
| `src/swift/app/roll/PianoGrid+Gestures.swift:155,289,423-424` | `tickAtContentX` | Pointer press, time-selection clearing, draw anchoring |
| `src/swift/app/timeline/EditorCamera.swift:232-240` | `contentX`, `tickAtContentX`, `displayX`, `contentTickX` | Shared camera conversion used by production surfaces |
| `src/swift/app/timeline/EditorCamera.swift:337-352` | `displayX`, `contentX` | Tick/range reveal and scrollbar extents |
| `src/swift/app/timeline/PlayheadGuides.swift:120-123` | `tickAtContentX` | Playhead hover tick resolution |
| `src/swift/app/timeline/RulerMenuPresenter.swift:108-110,162-165,324-340` | `tickAtContentX` plus grid snap | Ruler signature, selection, and sweep interactions |
| `src/swift/app/pitchbend/PitchBendPresenter.swift:105-107` | `displayX` twice and pitch row lookup | Pitch-bend note anchor/width |
| `src/swift/app/drawer/automation/AutomationProjection.swift:137-152,245-267` | `x`, `y`, `rawTick`, projected point construction | Automation node/curve projection and pointer mapping |
| `src/swift/app/drawer/automation/AutomationContentPublication.swift:81-82,237-239` | `displayX`, `contentTickX` | Automation published curve/node x coordinates |
| `src/swift/app/drawer/automation/AutomationOverlayPublication.swift:32-35,102-108,154-155` | `projection.x`, `projection.y` | Automation selection band, hover guide, preview label |
| `src/swift/app/drawer/automation/AutomationDrawingContent.swift:93-98,107-109,143-156` | `projection.x`, `projection.y` | Automation native drawer drawing blob rectangles/edges |
| `src/swift/app/drawer/voicechanges/VoiceChangesScene.swift:157-168` | `displayX` | Voice marker x and marker hit test |
| `src/swift/app/drawer/voicechanges/VoiceChangesScene.swift:252-255` | `contentTickX` | Voice marker label projection |
| `src/swift/app/drawer/voicechanges/VoiceChangesProjection.swift:382-384` | injected `displayX` | Voice caption x/elision layout |
| `src/swift/app/drawer/velocity/VelocityProjection.swift:29-43` | `contentTickX`, snapped scroll offset | Scroll-stable velocity handle coordinates and delegate offset |
| `src/swift/app/drawer/velocity/VelocityProjection.swift:50-88` | value-axis Y and handle hit geometry | Velocity handle/stem hit testing |
| `src/swift/app/roll/GridScene.swift:157-160` | `rowTop`/`rowBottom` | Hover chip; no Swift production drawer presenter projects roll rows |
| `src/swift/app/roll/PianoGrid+Support.swift` | No tick/row→pixel projection symbol found in production; `projectedNoteBox` is check-only | — |

## 4. Checks asserting parity or reading `noteFace`/`projectedNoteBox`

| Check | File:line | Comparison/read |
|---|---|---|
| Camera physical-pixel parity | `src/checks/rollcheck/static/camera.swift:34-40,232-237` | Swift content/display round-trip and affine DPR snap `((origin+x)*dpr).rounded()/dpr` |
| Main roll projection parity | `src/checks/rollcheck/EditorGridProjectionChecks.swift:97-141` | Swift `projectedNoteBox` is compared with Swift camera `contentTickX - rounded scroll` and `contentRowTop - scrollY + pixel`; pre-roll mask follows projected zero tick |
| Preview projection parity | `src/checks/rollcheck/EditorGridProjectionChecks.swift:168-180` | Preview `projectedNoteBox` compared with expected camera x/y; also verifies projected drag state |
| Projection-driven interaction | `src/checks/rollcheck/EditorGridProjectionChecks.swift:143-154,233-268` | Press selects projected note; band selects projected visible notes; outside projected rows reject input |
| Camera-scroll/native-content parity | `src/checks/rollcheck/note_rendering_economy.swift:110-128` | Native content note box translated to viewport compared with Swift `projectedNoteBox`; camera-only scroll must not republish content |
| `projectedNoteBox` helper and selection reads | `src/checks/rollcheck/selection.swift:8-18,48-51` | Defines helper from `displayX` + `metrics.noteBox`; selection rectangle consumes it |
| Keyboard row projection read | `src/checks/rollcheck/keyboard_parity.swift:119-123` | Finds a visible row by `projectedNoteBox` bounds |
| Fold/scale projected box reads | `src/checks/rollcheck/scale_editing.swift:332-336,424-428` | Uses projected note boxes for folded/scale exception and drag-source geometry |
| Audition row projection reads | `src/checks/rollcheck/selection_audition.swift:216-224` | Uses `projectedNoteBox` to find a visible keyboard row and center |
| Note-name fit parity/support | `src/checks/rollcheck/note_rendering_support.swift:16-35` | Reads content note box and checks `NoteNameLabels.faceFits/nameFits` against production content |
| Note-name labels and ink | `src/checks/rollcheck/note_name_labels.swift:41-75,102-113` | Reads native content/mode/fill/ink/font and directly exercises check-only `NoteNameLabels.labels`, including ghost filtering |
| Border/fitted-frame behavior | `src/checks/rollcheck/note_rendering_borders.swift:107-110` | Reads native note fill/box and checks tiny-note dimensions against fitted border |
| Native note-face bridge helper | `src/checks/editorqml/RollNoteFaces.js:1-9` | Calls `renderer.noteFace("gridNote_" + id)` and validates returned rectangle |
| Ruler loop marker bridge | `src/checks/editorqml/ShellGridMenuSupport.qml:235-245` | Reads `noteFace` for loop markers and absence |
| Ruler marker bridge | `src/checks/editorqml/tst_EditorDrawerChrome.qml:341-343` | Reads `rulerMarks.noteFace(name)` and maps marker x |
| Chrome loop-marker bridge | `src/checks/editorqml/tst_ShellChromeVisuals.qml:221-226` | Reads start/end `noteFace` and visibility |
| Loop-menu marker bridge | `src/checks/editorqml/tst_ShellMenusLoop.qml:24-26,90-96` | Reads start/end `noteFace` positions and absence |

### Surprises

1. `RollProjection::noteBox` computes height as `max(noteMinHeight*pixel, bottom-top-pixel)-pixel`; Swift `noteRect` has the first expression and Swift `noteBox` performs the final `-pixel` (`roll_projection.h:57-60`; `GridGeometry.swift:409-417`).
2. Swift `adaptiveTicks(..., snap: true)` adds a GCD refinement for snapping (`GridGeometry.swift:174-191`); C++ `gridTicksAt` has no snap-specific refinement (`roll_projection.h:102-120`).
3. Swift `TimeAxis.forEachGridLine` streams signature seams (`TimeAxis.swift:101-155`); C++ numbering walks segment storage (`roll_projection.h:167-211`).
4. `NoteNameLabels.swift` is absent from the production timeline directory; the formula copy is check-only at `src/checks/rollcheck/note_name_labels.swift:21-59`.
5. Drawer Swift presenters still project x through the shared camera even though drawer raster geometry is also projected in C++ (`AutomationProjection.swift:137-152`; `drawer_scene.cpp:10-12,116-129`).
6. The requested `projectedNoteBox` is a check helper, not a production `PianoGrid` method (`src/checks/rollcheck/selection.swift:8-18`).
7. The independent checker could not run because its service returned a free-tier quota error; findings are therefore not independently checked.