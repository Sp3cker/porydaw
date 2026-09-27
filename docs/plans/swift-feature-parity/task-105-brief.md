# Task 105 brief — exact roll lattice and synchronized keyboard context

# Context

Close the camera projection/lattice ledger and the remaining mounted drum-context clauses while exercising the same real roll viewport. The required feature work is visible snapped placement, scratch-draw extent growth and context-sensitive keyboard synchronization, not a recreated native camera wrapper.

Verified selection: **36 open rows (20 GAP + 16 PARTIAL)**:

- `src/checks/rollcheck/static/proof.camera.txt` — all 19 remaining after 93 (three GAP + 16 PARTIAL): A012, A014, A016, A032, A033, A041, A042, A047, A048, A080, A083–A085, A093, A101–A105.
- `src/checks/timelinepan/proof.tst_timelinepan.txt` — all 15 GAP: A028, A034, A035, A037, A055, A071–A073, A077, A079, A081, A083, A084, A086, A090.
- `src/checks/rollcheck/static/proof.geometry.txt` — two GAP: A018, A019.

Fork `fceecd88`; matching camera original `f3069ef693542bdb63564b80a29773e2f5b2a360`, timelinepan `c17d966fbf56b1cccb2c1112b7eef84bec1dc7ac`, geometry `85b97239ce94dc4c4cf5f3f4fb66fc96ff2cf27e`. Task 93 owns camera A092/A094–A098, not A093; its implementer explicitly confirmed A093 remains open and available for this successor. Do not reselect 93's six rows or its geometry A020–A026.

# Exact write set

- `src/swift/app/timeline/GridGeometry.swift` — conditional selected lattice/snap repair.
- `src/swift/app/timeline/TimeAxis.swift` — conditional ceiling walk repair.
- `src/swift/app/roll/PianoGrid.swift` — conditional scratch-draw extent/refresh repair.
- `src/swift/app/roll/GridGesture.swift` — conditional existing double-click draw transition repair.
- `src/swift/app/roll/PianoGrid+SceneSync.swift` — conditional initial-program keyboard synchronization repair.
- `src/swift/app/roll/GridScene+Rebuild.swift` — conditional lattice/keyboard paint repair.
- `src/ui/songview/quick/swiftroll/SwiftRollOverlay.qml` — conditional production roll input/paint repair.
- `src/checks/rollcheck/static/camera.swift`
- `src/checks/rollcheck/static/geometry.swift`
- `src/checks/rollcheck/EditorGridCameraChecks.swift`
- `src/checks/rollcheck/keyboard.swift` — drum context only; preserve 102's keyboard selection predicates.
- `src/checks/rollqml/tst_TimelinePan.qml`
- `src/checks/editorqml/tst_ShellGridInput.qml`
- `src/checks/rollcheck/static/proof.camera.txt` — delete after closure.
- `src/checks/timelinepan/proof.tst_timelinepan.txt` — delete after closure.
- `src/checks/rollcheck/static/proof.geometry.txt` — A018/A019 only.

No ShellWindow, key arbiter, automation/velocity owners, shared playback policy, fixture-content or registration writes. Both fully closing originals were already removed; delete the ledgers, not a guessed source path.

# Prerequisites

All 91–98 and Group A's accepted checkpoint must land first. Rebase over 93's note/ruler raster, 96's hover/camera refresh and 97's drawing/selection changes. Rebase `PianoGrid.swift`, `keyboard.swift` and `tst_ShellGridInput.qml` over 102. Preserve 91's precise fractional playhead policy and task-82 drum-name behavior; consume playback through its existing presenter, not a second transport clock.

# Interface contract

- Preserve `GridGeometry.snapTick`, `nextSubdivisionTickAfter`, `nextSnapTickAfter` (`GridGeometry.swift:277–307`) and production subdivision walking; `checkFractionalGridLattice` (`EditorGridCameraChecks.swift:65–147`) is the existing check owner. Independently enumerate exact membership for 97–98 (empty first candidate), 95–110, seam-crossing 95–130 and 100–110, and nearest snap at 103.5 and 103.5 + stride. Assert tick-ceiling traversal emits at most one high tick and never wraps to a small tick. No duplicated production enumeration as the expectation.
- Extend `checkAffineCameraProjection` (`static/camera.swift:210–236`) across its recorded three fractional zoom/scroll rows, both origins and DPR1/2: snapped inverse recovers each source lattice tick and every next candidate strictly advances. Keep rendered right-edge culling intact. A private C++ `tickRange` return representation is not the Swift renderer's guard interval: retire camera A012/A014/A016 without changing visible coverage just to truncate a helper end value.
- Drive actual double-click scratch drawing at/beyond the old song end. Assert exact drawn note tick/key, strictly larger timeline extent and one undo returning original MIDI bytes. Do not substitute a direct `addNotes` call for the changed ingress.
- Keyboard drum classification uses the track's **initial** program, while the live voice context follows cursor/playhead. `PianoGrid.sceneInput` (`PianoGrid+SceneSync.swift:42–64`) and `GridScene.rebuildKeyboardText` (`GridScene+Rebuild.swift:372–416`) retain that split. Observe initial context 11, later cursor context 0, playhead beyond the program event with context 0, and reset context 11, while each forced real synchronization retains the full pad name. Existing `checkDrumPadLabels` (`keyboard.swift:507–643`) and `test_drumPadNamesFollowInitialProgram` (`tst_TimelinePan.qml:499–645`) already supply the bank, VoiceLanePolicy and real voice plot.
- Retire camera A080/A101 (native fixture creation), A085 (fixture viewport-density prerequisite), A093 (native raster availability prerequisite) alongside the actual image/placement predicates, plus the three private-range rows above. Retire timelinepan A028/A034/A035/A037/A055/A071/A072/A073/A077/A090 as native fixture/program/index prerequisites; no bare existence/count assertions are added to replace them. Exactly **17 representation rows** accompany **19 behavior rows**. Do not retire live context/program outputs or ceiling arithmetic.

# Implementation steps

1. Add the missing numeric boundary/inverse/strict-progress conjuncts to the existing camera and geometry checks, keeping their independent expectations local and using actual production time-axis/grid operations.
2. Extend the existing shell-grid-input double-click journey and `tst_TimelinePan.qml` to prove scratch extent/undo and mounted voice-context transitions. Add complete literal messages to the actual context comparisons; retain existing pad-name/raster behavioral anchors instead of adding setup-only checks.
3. Fix a demonstrated selected divergence only at the listed production seams. RED may be absent because current program/context predicates already contain some missing conjuncts. Preserve task-93's exact raster geometry and 102's keyboard command/history laws.
4. Pin fresh execution, classify the selected rows, delete the two fully closed ledgers and leave geometry's other fallback/ruler obligations open. Do not manufacture an empty pre-song EditorSurface to close them.

# Acceptance predicate

`SessionChecks.swift:21,61,62,68` registers camera/geometry/keyboard checks. `ShellQmlTests.swift:62–63` registers shell-grid-input. `RollQmlTests.swift:25–36,100–102` selects the production roll suite per process; the environment below must select `tst_TimelinePan.qml`, not only the default suite.

On the settled task/group tree the controller runs every command below, serialized. Implementers do not run them while siblings edit. Apply §11 checkpoint/review policy and deduplicate full sweeps at the accepted group boundary, not omit them.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-grid-input --verbose
PORYDAW_ROLL_QML_SUITE=tst_TimelinePan.qml /usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

All commands must finish within 180 seconds after lock acquisition (the wrapper alarms at 175). Fresh execution must classify selected behavioral anchors in `swiftcore-projectsession.json`, `shell-grid-input.json` and the `swiftroll-window` evidence for `tst_TimelinePan.qml`; execute every data row, DPR/palette variant and mounted interaction used to close a row. Full shell and full verify pass, selected rows have no GAP/PARTIAL/NATIVE residue, and executed proof validation resolves all retained anchors. Preserve existing literal messages and add unique complete literals, never interpolated phase anchors. Capture before/after structure, real-surface smoke, source/evidence pins and the task review gate; never invent RED or execution.

# Task-specific constraints

Read sprint-3 §10 “Wave constraints and verification” and §11 “Inherited constraints and verification” as mandatory parts of this brief. They cover unique literal anchors, fixture-consumer boundaries, CFPreferences staging, honest absent RED, Swift 6.4/no new C++, two-line comments, base-font geometry, WCAG AA, keyboard priority, no `Qt.callLater`/idempotence guards/test seams, and approval before workarounds. All §11 exclusions remain unchanged.
Use the existing real staged rich-bank fixture and its loaded names; no fixture MIDI/program edit is authorized. Initial-program classification is intentional, not a stale-context defect. Geometry fallback, all keyboard ledger rows and timelinepan already-closed pan/hover rows remain unchanged.
