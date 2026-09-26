# Context

Task 59 — velocity surface: detent laws + timeline projection proof. Close the velocity family
(421 open rows: `src/checks/velocity/` 325 + `src/checks/drawerpresentation/proof.velocity.txt`
96) and delete all nine ledgers. The surface exists and executes: `VelocityPage.swift` +
`src/ui/songview/quick/drawer/VelocityPage.qml` mounted in the drawer lane
(`test_productionVelocityPageMountsAndRenders`, `tst_EditorDrawer.qml:2788`), presenter
predicates under `runVelocityPageChecks` (`VelocityPageChecks.swift:130`, project-session
suite). This is proof completion, not a rebuild: no production law gap identified at freeze —
every PARTIAL cause maps to an existing-but-unused Swift mechanism (Context ¶3).

1. **Census (verified this freeze)**: detentdragging 116 open (112 PARTIAL, 4 GAP),
   detentpainting 68 (66+2), tst_velocityediting 43, velocityroll 28, velocitypainting 25,
   velocityselection 18 (16+2), velocityclicks 17, hitpriority 10, drawer velocity 96
   (73+23). MATCHED/RETIRED rows in each file stay untouched.
2. **Fork detent laws** (`git show f3069ef6…:src/checks/velocity/velocitydetentdragging.cpp`,
   helper `timelineVelocity` at `tst_velocityediting.cpp:438-447` — reacquires
   `m_tab->timeline()` per call and reads the note-on (`type 0x9`) `data1` by noteId):
   context arm per program (`addLanePoint(0, DOC_CC_VOICE, 0, program)` → PSG context,
   `VelocityAxis::Mode::Intrinsic`, detent checkbox → `useDetents()`, `:25-43`); origins
   `kQuietOrigin=33`, `kLaterOrigin=87` (each `QTRY_COMPARE` on timelineVelocity, `:44-47`);
   - **Snap law** `lateUnlockKeepsGestureSnapped` (:12-108): press at level N, move to level
     M holding the `velocity.detent_unlock` modifier only during the move — unlock is sampled
     at press, the gesture stays snapped: square 4→5 ⇒ 44/92, wave 1→2 ⇒ 64/127, noise ⇒
     44/92 (:20-22).
   - **Relative law** `unlockedRelativeKeepsOffsets` (:111-215): press WITH unlock ⇒ raw
     delta applies per-note relative: +7 ⇒ 40/94 for all three programs (:118-120); integral
     window-coordinate derivation comment (:157-165) — the Swift pixel-driven equivalents
     derive the move from the delivered press y + delta.
   - **Ramp law** `unlockedRampInterpolates` (:220-335): unlock+Shift press on the quiet
     node, move to the later node; middle note (tick 36, duration 12, velocity 56) takes the
     interpolated 65; all programs 37/65/93 (:227-229).
   - Per-scenario invariants: preview only for selected notes (loudStacked never), revision/
     `undoStack` depth/`documentChanged`/`edited` all 0 during drag and exactly 1 after
     release, document values frozen during drag, timelineVelocity reads originals during
     drag and expected values after release, selection preserved.
   - Painting: `rulerUnlockKeepsRawVelocity`/`lockedPaintUsesDetents`/
     `unlockedPaintKeepsRawVelocities` (detentpainting.cpp) — Swift page-level twins already
     execute for square/noise (raw 73 → detent 76, `VelocityPaintDetentChecks.swift:158-256`);
     the wave pair exists only at policy level (:204-206).
3. **Swift current state — the three unlocked mechanisms (no production change needed)**:
   - **Timeline projection**: `DocumentSession.timeline` is `public private(set)`, rebuilt
     from `PlaybackTimeline.build(state:sampleRate:)` on every document change
     (`DocumentSession.swift:74`, `:785`); note-on events carry `noteID` with `data1`
     velocity (`PlaybackTimeline.swift:24,264-269`). Check-side helper = reacquire
     `session.timeline`, find `events.first { $0.type == 0x9 && $0.noteID == id }?.data1`.
   - **Publication counts**: `session.onChange: ((SessionChange) -> Void)?`
     (`DocumentSession.swift:128`) publishes domains `[.document, .dirty, .history]` per
     document edit (`:793-800`). The fixture (`drawerVelocityVelocityFixture`,
     `VelocityPageChecks.swift:83-108`) builds its own session; a check-owned counter wraps
     `session.onChange` (chaining any prior closure) — `documentChanged.count()` ≡
     publications containing `.document`, `SongTab::edited` ≡ publications containing
     `.dirty`.
   - **History depth**: `document.history.undoCount` / `.undoIndex` are public
     (`SongHistory.swift:234-236`).
   Existing checks are presenter/policy-level (`Velocity*Checks.swift`,
   `velocitydetentdragging.swift`, `tst_velocityediting.swift`) plus the mounted drawer lane;
   neither ever reads `session.timeline`, counts publications, or reads `undoCount`.
4. **Task-54 boundary (exclusion)**: task 54 owns the rollcheck ledgers
   (`proof.pencil_velocity.txt`, `proof.velocity_prompt.txt`, `proof.pencil.txt`), the pencil
   latch/gutter laws, and the prompt remount; it edits `VelocityPage.qml` (prompt instance
   removal) and `tst_EditorDrawer.qml` (focus/role re-anchors). Task 59 never edits
   rollcheck check files or ledgers. The two drawer rows whose GAP reasons say "roll-surface
   velocity drag owned by roll lane" (A102 `QVERIFY(roll)`, A104 `view.previewVelocity` —
   fork `drawerpresentation/velocity.cpp:534,544`, the roll modifier-drag half of
   `rampAndRollPreview`) are THIS ledger's rows: A102 maps to the roll-grid fixture fact,
   A104 to a roll-drag preview readback in `VelocityRollCoreChecks.swift`
   (`PianoGrid.previewVelocity` exists, `PianoGrid.swift:168`) — closed in Stage B, no
   dependency on task 54's predicates.
5. **Dead-lane adjudication** (19 rows, drawer ledger): fork `drawerpresentation/velocity.cpp`
   no longer builds; its rows pin either quick-scene layer ink (VelocityNodes/Stems/Transient/
   Grid ink at rects), framebuffer `samePixels` captures, or QQuickItem focus policies. The
   mounted `VelocityPage.qml` renders nodes/stems/transients from published model rows
   (`handles`, `transientRects` with colors; `velocityNodeFill` child precedent) — ink rows
   close as model-color + mounted-render pairs; framebuffer-equality and focus-policy rows
   retire as RETIRED-REPRESENTATION (pinned `f3069ef6`).

# Exact write set

- `src/checks/velocity/VelocityPageChecks.swift` — fixture additions: timeline-readback
  helper, chained session-publication counter; `contextSlot` fixture variants.
- `src/checks/velocity/VelocityRollCoreChecks.swift` — projection readbacks, exact staged
  values (±28/±4), publication counts, `undoCount` deltas, roll-drag preview readback.
- `src/checks/velocity/VelocityPaintDetentChecks.swift` — wave page-flow pair; per-program
  page flows (late-unlock/relative/ramp); projection + publication counts on every scenario.
- `src/checks/velocity/VelocityClickSelectionChecks.swift` — published-handle reads,
  pre-click baselines, `undoCount` deltas, projection readbacks.
- `src/checks/velocity/velocitydetentdragging.swift` + `tst_velocityediting.swift` —
  projection/publication/preview-clear extensions per contract.
- `src/checks/drawerpresentation/velocity.swift` — marker-y equality, hover-graduation
  flags, layout-geometry row, replay/rebuild rows named in the mapping.
- `src/checks/editorqml/tst_EditorDrawer.qml` — mounted painted-ink predicates (transient
  fill/edge/empty, node highlight/base/dimmed, stem, past-end grid), page-mount guard
  anchors. Shared file — see Prerequisites.
- Contingent only (edit solely to fix a divergence a new predicate exposes):
  `src/swift/app/drawer/velocity/VelocityPage.swift`, `VelocityInteraction.swift`,
  `src/ui/songview/quick/drawer/VelocityPage.qml`.
- Ledgers (controller-delegated ledger agent, this task's commits): flip then delete the
  eight `src/checks/velocity/proof.*.txt` files and
  `src/checks/drawerpresentation/proof.velocity.txt`.

No CMake changes (no new files), no `PianoGrid.swift`, no rollcheck files, no production
Swift planned. Sizing exception: one behavior family's proof completion over 7 check files +
ledgers, two lanes — named for the dispatch table; the Stage A/B split below is the
dispatch seam if the controller prefers two seats.

# Prerequisites

Task 54 settled (owns `VelocityPage.qml` prompt removal and `tst_EditorDrawer.qml`
re-anchors) and the `tst_EditorDrawer.qml` chain settled or checkpointed through task 57
(sprint §5: 55 → 56 → 57 → 59 serial). Nothing consumed from 52/53. Re-snapshot line cites
if 54–57 moved them.

# Interface contract

No production interface changes. New check-side helpers (VelocityPageChecks.swift):
- `drawerVelocityTimelineVelocity(_ session: DocumentSession, _ id: NoteID) -> Int` —
  reacquires `session.timeline` per call, returns `data1` of the first note-on
  (`type == 0x9`) event with matching `noteID`, −1 when absent. Every fork
  `timelineVelocity(...)` clause cites this.
- `drawerVelocityPublicationCounter` — installs a counting closure on the fixture session's
  `onChange` (forwarding to any prior closure); exposes `.document`-domain and `.dirty`
  -domain counts. Fork `documentChanged.count()`/`edited.count()` clauses cite these.
- Depth assertions use `document.history.undoCount`/`undoIndex` directly.

New anchors (message-anchored, one per fork clause; every message cited by an existing
S row or PARTIAL reason stays verbatim — the S inventories in each ledger are the frozen
set; new messages follow them):
- Stage A (swiftcore, `swiftcore/VelocityRollCore::*`, `swiftcore/VelocityPage::*`):
  - "a drag preview holds the timeline projection at the captured velocities",
    "a released drag republishes the staged velocities into the timeline projection",
    "an escaped drag leaves the timeline projection untouched", "undo restores the timeline
    projection", "redo restores the committed timeline projection" — applied per scenario
    (drag/paint/ramp/roll/click/band; originals 100/64/32, expected per law).
  - "a held drag publishes no document change", "one release publishes exactly one document
    change", "a held drag publishes no dirty change", "one release publishes exactly one
    dirty change" (spy counts 0/1 per scenario; the zero-`documentChanged` deferred-paint
    law).
  - "one release grows the undo depth by exactly one", "a cancelled gesture leaves the undo
    depth unchanged" (`undoCount` before/after; supersedes the identity-only corroboration).
  - "the staged preview pins to the fixture literal plus the dragged pixels"
    (100+28/64+28 hold; 100−4/64−4 after reverse), "the committed value equals the pinned
    staged preview".
  - Per-program page flows (square/wave/noise each): "a late unlock keeps the gesture
    snapped to the level bands" (44/92, 64/127, 44/92), "an unlocked press keeps per-note
    offsets under a raw delta" (40/94), "an unlocked ramp interpolates the middle note"
    (37/65/93), "the wave pair presents the intrinsic ruler with the enabled detent
    control", "detents toggle between intrinsic and continuous for every program family".
  - "the roll drag previews the selected note on the roll surface" (drawer A104),
    "the roll grid fixture exposes a real input surface" (A102).
- Stage B (drawer lane, `tst_EditorDrawer.qml`): "the transient band paints its fill and
  edge over the dragged selector", "the transient band empties after the band release",
  "the selected node paints the highlight ink", "the unselected node paints the dimmed ink",
  "an outsider stem paints without a node highlight", "the grid paints the past-end point",
  "toggling detents repaints the ruler and restoring repaints it back" (model-color +
  rendered-child pairs per layer family), "the mounted page publishes a live timeline for
  the staged song" (session.timeline non-empty; drawer A005/A009/A010).
- Preservation: every existing predicate function name and anchor message stays verbatim
  (`drawerVelocityRollCoreDragDefersAndCommits`, `drawerVelocityFrozenGesturePolicy`, the
  S052–S068 / S079 / S081 / S086 / S088 / S091 / S107 / S118 / S128 / S133 / S149 citations
  in PARTIAL reasons); frozen visual baselines unaffected (no geometry moves).

# Implementation steps

Stage A (swiftcore; closes the eight velocity/ ledgers' presenter-level rows):
1. Fixture helpers (contract above); re-run the existing suite green.
2. Extend each existing scenario in place with the projection/publication/depth/exact-staged
   expectations at the fork's assertion points (preview instant, post-release, post-undo,
   post-redo, post-cancel). Expected to pass immediately (proof, not fix); a failure exposes
   a real divergence — fix in the contingent files and record RED→GREEN for that fix only.
3. Add the wave page-flow pair and the per-program flow variants (context ¶2 literals);
   add the roll-drag preview readback to `drawerVelocityRollCoreRollCommit`'s staging phase.
Stage B (drawer lane; closes `proof.velocity.txt`):
4. Mounted painted-ink predicates per the contract; map ink rows to model-color +
   rendered-child pairs; retire framebuffer/focus-policy rows per the mapping.
5. Run both lanes; the evidence JSONs (`build/proof-evidence/swiftcore-projectsession.json`,
   the qml lane's) feed the ledger agent.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore-projectsession --verbose` — all velocity predicates
  (projection, publication counts, depth, exact staged values, per-program flows, roll
  preview) plus session-suite regressions.
- `deno task verify:qml --verbose` — drawer lane: existing velocity functions (prompt
  re-anchors from 54 stay green), new ink/mount predicates, full drawer regression.
- Runtime prerequisite: the drawer lane's usual offscreen-capable Qt windowing; no native
  audio (publication counts are session-level, not engine).

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no pixel
  constants (fork literals are check-side fixture values, as in the fork's own data rows).
- One message-anchored predicate per fork clause; ledger-cited messages verbatim.
- Implementers never edit ledgers. Ledger mapping (agent; re-verify at freeze against the
  evidence JSONs; row groups from the freeze-time tag audit):
  - detentdragging: ROWFLOW set (A003–A039, A043, A046, A062–A064, A067, A068, A073,
    A076–A083, A087, A090, A110–A112, A115, A126–A135) → the per-program flow anchors;
    PROJ set (A007, A008, A026–A028, A040–A042, A050, A051, A070–A072, A084–A086,
    A119–A122, A136–A139) → projection anchors; SIG set (A021, A022, A030, A065, A066,
    A074, A113, A114, A124) → publication anchors; DETOG (A002, A006, A045, A049, A089,
    A093) → detent-toggle anchors; CTX (A001, A044, A088) → contextSlot anchors;
    `bounds().contains` preconditions (in the GUARD/OTHER residue: A010, A052, A053 and
    same-shape rows) → `RETIRED-REPRESENTATION` (native `TimelineInputItem::bounds` in the
    retired quick window; sprint §4); SIBLING rows (A011, A094–A096, A123, A140) re-anchor
    to the Stage A anchors they cite.
  - detentpainting: PROJ → projection anchors; SIG → publication anchors; DEPTH (A018,
    A029, A054, A067, A097, A110) → undo-depth anchors; PREV (A070, A071, A112–A114) →
    preview-clear anchors per program; READBACK (A043–A045, A057–A062, A086–A088,
    A100–A105) → published-handle/pre-click-baseline anchors; CTX A001 → contextSlot.
  - tst_velocityediting: PROJ (24 rows, the `:214` group among them) → projection anchors;
    EXACT (13 rows) → pinned-staged-value anchors; SIG (5) → publication anchors.
  - velocityroll: PROJ/SIG/DEPTH/GUARD rows → their scenario anchors; READBACK A010 →
    roll preview readback.
  - velocitypainting: PROJ (13) → projection; SIG (8) → publication; residue (A050, A076,
    A079) → their scenario's extended anchors.
  - velocityselection: DEPTH (A013, A026, A032, A046, A065) → undo-depth; PROJ (A050–A052)
    → projection; SIBLING (A038, A054, A055) → Stage A anchors; residue → extended
    readbacks.
  - velocityclicks: READBACK (11 rows) → handle/baseline anchors; DEPTH (A027, A046) →
    undo-depth; REPR A021 → `RETIRED-REPRESENTATION`.
  - hitpriority: PROJ (9 rows) → projection anchors at the press/release points.
  - drawer velocity: SIBLING (A046–A053, A101, A105–A117) → Stage A anchors (presenter
    twins) or the mounted ink pair where the original observed scene ink; layer-ink rows
    (A041, A056, A062–A067, A071, A089–A091, A095, A097) → ink-pair anchors; framebuffer
    equality (A043, A058, A059, A078) and focus-policy (A029, A030) + native mount/fixture
    guards (A012, A013, A025) → `RETIRED-REPRESENTATION` citing `f3069ef6`; ROLLLANE
    (A102, A104) → the roll fixture/preview anchors; cross-lane residue (camera, keybinding
    A103) → map to the owning lane's executed anchors if one exists at freeze, else
    `RETIRED-REPRESENTATION` with the lane-named reason — flag to the controller, never
    re-open those lanes.
  - After every row is MATCHED/RETIRED, delete all nine proof files in this task's final
    commit (fork C++ check sources already deleted in 67544720).
- WCAG AA beats parity: ink-pair predicates read published palette pairs; a failing pair is
  fixed in the palette role, not the check.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed` (pre-deletion state shows all nine ledgers fully
   closed), then `deno task proof sites --area velocity` and `--area drawerpresentation`
   report no velocity ledger files (drawer.txt/valueprompt.txt remain — other tasks').
2. Visual/native smoke (desktop): open the Velocity drawer page on a PSG-track song; drag a
   node — the bar previews live and commits on release (one undo step); toggle Detents and
   drag — values snap to the level bands per square/wave/noise program; hold the unlock
   modifier and drag — raw values; Shift-drag a ramp across three notes — linear
   interpolation; Escape mid-drag — nothing changes; band-drag — transient band paints and
   clears; play — the edited velocities sound.
