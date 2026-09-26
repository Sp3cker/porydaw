# Context

Task 51 — piano roll residual behaviors. Spec: the fifteen near-clear roll ledgers
listed below (43 open rows). Classification visited every open row against its pinned
C++ (`git show <Reference>:<Original>`). Result: **9 Behavior** (all proof-only — the
production behavior already exists and names an owner below), **24 Representation**
(retire), **10 Blocked** (3 ledger families stay open). Task 51 edits **no production
file**; it completes proof and retires native-harness representations.

1. **grid_smoke A056–A060 are prototype-only.** The fork app has no read-only roll
   mode (`git grep -i readonly fceecd88 -- src/ui` → file-I/O only). The pinned rows
   drive the retired prototype's `scene.model` API (`readOnly` property,
   `resetDemo`, `makePitchEditor`, `sgd_register_feed` C ABI,
   `grid_smoke.cpp:669-742` @ `18fee935`). Production (`PianoGrid.swift`,
   `DocumentSession`) never had that contract. Retire all five.
2. **Root `proof.rollcheck.txt` A004/A006 pin deleted `SongTab` accessors.**
   `presentationError()`/`isReady()` (`rollcheck.cpp:45,53` @ `a1244957`) have no
   Swift counterpart (`grep src/swift` → none). The Swift open-failure surface this
   guarded is already proven: S047/S050 in `proof.tst_swiftrollgated.txt`
   (`tst_ShellOpenFailure.qml`). Retire.
3. **notevisuals A028/A031 are the only real render gaps.** The thinning law exists
   in production: `GridGeometry.swift:430` `selectionRingPixels` +
   `GridScene.addSelectionRing`/`fittedFrameThickness` (`GridScene.swift:341-360`).
   The check takes the dpr-1 fallback (`tst_ShellNoteVisuals.qml:254`
   `borderRequest > 1 ? 4.0 : 7.0`), so the dpr>1 branch never executes. The lane
   can run dpr 2: relaunch with `QT_SCALE_FACTOR=2` exactly like the shell-polyphony
   profile children (`ShellQmlTests.swift:170-185`, baselines under
   `src/checks/fixtures/visual/macos-dpr2-*`). Port both rows (51a).
4. **swiftbandkeys A105–A107 decline rules are enforced by QML delivery today.**
   `EditorSurface.qml` `gutterInput` (inside `timelineQuickRollGutter`, :332-341)
   accepts `Qt.LeftButton` only → right/middle gutter presses never deliver;
   `rollInput` (`swiftRollInput`, :402) accepts Left|Right|Middle → `Qt.XButton1`
   never delivers. Pinned verdicts (`tst_swiftbandkeys.cpp:555-561` @ `fe1ff4df`):
   `!band.pointerPress(gutterRight|gutterMiddle|plotXButton1)`. Port as mounted
   no-change predicates in `tst_ShellGridInput.qml` (51a).
5. **Shell lifecycle residuals.** `selectionkey/window.cpp` cleanup (:190-210 @
   `0d03b161`) sends a real close on a clean session and demands acceptance without
   a prompt. Swift owner: `ShellWindow.qml:163-172` `beginClose()`/`closeReady`,
   discard prompt `songTabDiscard` (`SongTabs.qml:334,375`). Port into
   `tst_ShellWindow.qml` (51b). `tst_swiftrollgated.cpp:313` reads
   `session.projectOpen`; `ApplicationSession.swift:22` publishes it and
   `tst_ShellOpenFailure.qml:72-78` already reads the session — add the flag
   readback (51b).
6. **clipboard sentinel rows are check-seeded foreign text, not app output.** The
   native check seeds bytes+text itself, then asserts a mid-gesture no-op Copy
   leaves both untouched (`clipboardchecks.cpp:296-324` @ `68209547`). The bytes
   half is MATCHED (S055/S059). Proving the text half requires seeding/reading text
   beside the clip MIME; production `clipboard_host.cpp` deliberately moves only
   `application/x-porydaw-clip` bytes and `GridInputClipProbe.swift` has no text
   path — adding one is new C++ at the boundary. **Blocked** (ruling: no new C++).
   A060 (QQuickView replaced on reload) retires: one mounted `ShellWindow` with
   in-place reload is the accepted design; exposure already S059.
7. **Menu rows belong to task 46.** clipboard A011 (Copy/Paste/Undo/Redo items
   exist) and gesture A073/A074/A080 (Nudge Right / Delete Notes item exists,
   enabled) pin the mounted menu surface task 46 reshapes. **Blocked-by-task-46**.
8. **Event-list document-count rows belong to task 39.** localinputtier_eventlist
   A013/A025 (reorder/delete preserves exact raw-event counts) and A018/A019
   (protected-note fixture insert/uniqueness) are the same delete-matrix /
   same-tick-reorder family task 39 owns in `proof.edits.txt`. **Blocked-by-task-39**.
9. **header_reconciliation deltas are two small predicates.** A004 lacks only the
   titles/roles reconciliation against the rebuilt timeline; A007 lacks the
   structural fixture's own ordered-records precondition
   (`header_reconciliation.cpp:88,105` @ `0b4c9ea6`). Both extend
   `src/checks/rollcheck/presentation.swift` (51c). The modelReset-count and
   structural-cppID guard clauses are native fixture plumbing — record as
   representation inside the MATCHED reasons.
10. **Native view/grab/exposure/setup rows retire.** QQuickView replacement and
    DeferredDelete nullness (gesture A065/A067), framebuffer pixel diff
    (gesture A011 — face-follow already S051), `isExposed()` (tst_swiftrollgated
    A004/A024), harness mode string/SKIP routing (chromevisuals A004,
    tst_swiftrollgated A001), `mouseGrabberItem` (selectionkey core A001, gesture
    A001), native velocity rig pointers (selectionkey gesture A004 — mounted
    surface is the ED06 drawer-velocity backlog), native loader/action-discovery/
    Quick-surface setup (window A001/A003/A005 — the mounted window-command surface
    is pinned by windowtier_keyboard, task 50), `focusInput` (tst_trackheaders A002),
    `LoadedSong` loader setup (tst_trackheadermodel A040/A044, both
    `QVERIFY2(source, …)` at :179/:207 @ `f3069ef6`).

# Exact write set

- `src/checks/editorqml/tst_ShellGridInput.qml` — 51a decline predicates.
- `src/checks/editorqml/tst_ShellNoteVisuals.qml` — 51a dpr2 small-font leg.
- `src/checks/editorqml/ShellQmlTests.swift` — 51a: one `QT_SCALE_FACTOR=2` child
  spawn for `shell-note-visuals`, mirroring the shell-polyphony block (:170-185).
  Shared runner for every shell lane — smallest possible diff, no entry-table change.
- `src/checks/editorqml/tst_ShellOpenFailure.qml` — 51b projectOpen readback.
- `src/checks/editorqml/tst_ShellWindow.qml` — 51b clean-close predicate.
- `src/checks/rollcheck/presentation.swift` — 51c two reconciliation predicates.
- Ledgers (controller-delegated ledger agent, same commit as each subtask's
  checks): the twelve deletable ledgers below; `proof.clipboardchecks.txt` and
  `proof.gesturechecks.txt` row edits (retirements only); no edit to
  `proof.localinputtier_eventlist.txt`.

No production file is written. Hot files `ShellWindow.qml`,
`ApplicationSession.swift`, `EditorSurface.qml`, `PianoGrid.swift` (and task-45's
`GridPalette.swift`/`GridScene.swift`) are read-only for task 51.

# Prerequisites

- 51b after task 36 settles (it owns the `ShellWindow.qml` region and the
  preferences seeding these lanes read; task 51 writes neither).
- 51a's notevisuals leg after task 45 lands (45 writes `GridPalette.swift`/
  `GridScene.swift` and names `shell-note-visuals` as its lane — same QML check
  file likely extended there; sequencing avoids the collision). 51a's bandkeys leg
  and 51c are parallel-safe at any point.
- No interface deps on tasks 38/40: task 38 (`PianoGrid.swift`, `EditorSurface.qml`,
  `RulerMenuPresenter.swift`, `ApplicationSession.swift`) and task 40 (`pitchbend/*`,
  `PitchBendPopup.qml`) share no file with this write set. If 38 lands first and
  restructures roll input, 51a's decline predicates assert outcomes (no selection,
  cursor, note-summary, revision change) and must still pass unchanged.

# Interface contract

- New message-anchored predicates (ledger S rows cite these exact messages):
  - `tst_ShellGridInput.qml`: "a right-button press on the keyboard gutter changes
    nothing", "a middle-button press on the keyboard gutter changes nothing",
    "an extra-button plot press changes nothing". Observables: `editCursorTick`,
    published note summary/selection, active note, revision — all unchanged; no
    context menu opens.
  - `tst_ShellNoteVisuals.qml` (dpr2 child only): "the dpr2 small-font viewport
    exposes a selected note whose border request exceeds one pixel",
    "the dpr2 selected note thins its physical border without vanishing"
    (measured border ≥ 1 and < `max(1, round(dpr))` device pixels, the pinned
    `smallBorder < smallBorderRequest` law).
  - `tst_ShellOpenFailure.qml`: "a successful open sets the project open flag"
    (read after the initial route-101 load; the flag readback mirrors the pinned
    `projectOpen && songOpen` wait).
  - `tst_ShellWindow.qml`: "a clean session closes without the discard prompt"
    (`shell.beginClose()` true, `closeDialog.visible` false throughout,
    `closeReady` transitions true; no document edit precedes the close).
  - `presentation.swift`: "unchanged refresh preserves header titles and roles
    against the rebuilt timeline", "the structural fixture starts with ordered
    records and a trailing add row".
- Preservation: every existing anchor, frozen visual baseline, objectName, and the
  dpr-1 small-font fallback branch stay untouched. `GatedVisualsProbe.swift` needs
  no change (the dpr2 child re-runs the existing small-font path; `shellDpr(image)`
  then reports 2).

# Implementation steps

1. **51a bandkeys**: add the three decline predicates to `tst_ShellGridInput.qml`
   using the lane's existing `mousePress` synthesis; press at the keyboard gutter
   (`timelineQuickRollGutter` bounds) with `Qt.RightButton`/`Qt.MiddleButton`, and
   on the plot with `Qt.XButton1`; pin the unchanged observables; record RED only
   if any decline is actually broken (then fix the production `acceptedButtons` —
   deviation from the no-production-edit rule must be reported, not improvised).
2. **51a notevisuals**: add the `QT_SCALE_FACTOR=2` child spawn for
   `shell-note-visuals` in `ShellQmlTests.swift`; in `tst_ShellNoteVisuals.qml`
   gate the thinning assertions on `Screen.devicePixelRatio === 2` (the existing
   dpr-1 leg keeps its fallback). Save the dpr2 grabbed frame as an artifact.
3. **51b**: extend `tst_ShellOpenFailure.qml` with the `projectOpen` readback;
   add the clean-close test to `tst_ShellWindow.qml` (open clean song, no edits,
   drive `shell.beginClose()`).
4. **51c**: extend `checkHeaderReconciliation` in `presentation.swift` with the
   titles/roles reconciliation (unchanged refresh) and the structural fixture's
   ordered-records precondition.
5. Run the lanes below; report GREEN with predicate messages and file:line.

# Acceptance predicate

- `deno task build:checks`
- 51a: `deno task verify:shell --filter shell-grid-input --verbose`;
  `deno task verify:shell --filter shell-note-visuals --verbose` (must show the
  dpr2 child executing the thinning leg).
- 51b: `deno task verify:shell --filter shell-open-failure --verbose`;
  `deno task verify:shell --filter shellwindow --verbose`.
- 51c: `deno task verify --filter swiftcore --verbose` (projectSession suite runs
  `presentation.swift`).
- Implementers run these; controller runs the shared baseline below.

# Task-specific constraints

- No production edits; no new C++; no comments; no pixel constants.
- Implementers never edit ledgers; the controller delegates them to the ledger
  agent in each subtask's commit:
  - **51a**: `swiftbandkeys` A105/A106/A107 → MATCHED (three grid-input anchors);
    `chromevisuals` A004 → RETIRED-REPRESENTATION "native harness mode string";
    `notevisuals` A028/A031 → MATCHED (two dpr2 anchors); `grid_smoke`
    A056–A060 → RETIRED-REPRESENTATION "prototype-only read-only contract; the
    fork app has no read-only roll mode (fceecd88 src/ui grep) and the
    scene.model/sgd_* entry points died with the C++ grid prototype";
    `gesturechecks` A011 → RETIRED-REPRESENTATION "native framebuffer pixel diff;
    the face-follow observable is MATCHED by S051".
    Deletable after 51a: `swiftbandkeys`, `chromevisuals`, `notevisuals`,
    `grid_smoke`.
  - **51b**: `tst_swiftrollgated` A001 → RETIRED-REPRESENTATION "QSKIP mode
    routing"; A003 → MATCHED (open-failure anchor); A004/A024 →
    RETIRED-REPRESENTATION "native platform window exposure; the mounted failure
    surface is MATCHED by S050"; `selectionkey/window` A001/A005 →
    RETIRED-REPRESENTATION "native loader/Quick-surface setup", A003 →
    RETIRED-REPRESENTATION "native QWidget action discovery; the mounted
    window-command surface is pinned by windowtier_keyboard (task 50)", A008 →
    MATCHED (clean-close anchor); `selectionkey/core` A001 and
    `selectionkey/gesture` A001 → RETIRED-REPRESENTATION "mouseGrabberItem is not
    QML-visible"; `selectionkey/gesture` A004 → RETIRED-REPRESENTATION "native
    velocity rig surface pointers; mounted surface is the ED06 drawer-velocity
    backlog"; `gesturechecks` A065/A067 → RETIRED-REPRESENTATION "single mounted
    ShellWindow across in-place reload is the accepted design; reload/retirement
    are MATCHED by S058 and the tst_SwiftRoll cleanup".
    Deletable after 51b: `tst_swiftrollgated`, `selectionkey/core`,
    `selectionkey/gesture`, `selectionkey/window` (its two NATIVE rows are already
    closed dispositions per the compact-form rule).
  - **51c**: `header_reconciliation` A004 → MATCHED (S002 + titles/roles anchor;
    record the modelReset-count clause as native signal plumbing), A007 → MATCHED
    (structural-fixture anchor + S001/S012; record the cppID guard as fixture
    plumbing); root `proof.rollcheck.txt` A004/A006 → RETIRED-REPRESENTATION
    "SongTab::presentationError/isReady have no Swift counterpart; the Swift
    open-failure surface is MATCHED by S047/S050"; `tst_trackheaders` A002 →
    RETIRED-REPRESENTATION "native focusInput staging before event synthesis";
    `tst_trackheadermodel` A040/A044 → RETIRED-REPRESENTATION "native
    LoadedSong loader/widget-discovery setup; Swift fixture is typed and
    nonoptional"; `clipboardchecks` A060 → RETIRED-REPRESENTATION "view
    replacement has no counterpart; exposure is MATCHED by S059".
    Deletable after 51c: `header_reconciliation`, `src/checks/proof.rollcheck.txt`,
    `tst_trackheaders`, `tst_trackheadermodel`.
  - **Blocked rows left untouched** (no disposition change):
    `gesturechecks` A073/A074/A080 and `clipboardchecks` A011 — Blocked-by-task-46
    (menu topology owns mounted menu-item existence/enabled state);
    `localinputtier_eventlist` A013/A018/A019/A025 — Blocked-by-task-39 (Event
    List reorder/delete document-count family); `clipboardchecks` A017/A023 —
    Blocked: foreign-text clipboard seeding/readback needs a native path beside
    `pd_clipboard_write`; new C++ at the boundary is ruling-blocked. The
    clip-bytes half is already MATCHED (S055/S059).
- `clipboardchecks` and `gesturechecks` therefore stay (3 open rows each), and
  `localinputtier_eventlist` stays (4 open rows), after task 51.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed`, `deno task proof check --strict-mappings`.
   Twelve ledgers deleted with their commits; `deno task proof sites` on the three
   remaining families shows only the blocked rows open.
2. Ledger step: the mapping above, one subtask commit at a time.
3. Visual step: re-run `deno task verify:shell --filter shell-note-visuals
   --verbose`; inspect the dpr2 artifact — the selected small-font note shows a
   physically thin (1-device-pixel) non-vanishing border at dpr 2.
4. Native smoke (desktop): launch the built app, right/middle-click the piano
   keyboard gutter and press an extra mouse button on the plot — no selection,
   cursor, or menu response; close the app with a clean session — it exits
   without the discard prompt.
