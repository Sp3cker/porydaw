# Task 85 brief — automation drawer command/voice routing tail on the mounted drawer

# Context

The mounted Automation and Voice Changes drawer sections already execute
their main edit journeys (tasks 55–57, 79). What remains in this family is the
routing long tail: the range band never leaks into pan/pencil/body/voice
gestures, the voice page's pointer feedback (cursor, marker republication,
Alt-drag history depth) and rendered input are observed, the held-B pencil
survives a real pointer stroke, and the point menu's Delete row renders on a
real menu before any stale rejection. This task proves those journeys on the
mounted drawer surface; it does not re-open task 79's selected-drag rows.

1. **Verified census: 39 open rows** (HEAD `e334b318ecf391e3d4fac512c4a613303aff01e3`).
   - `src/checks/automation/proof.automationrouting.txt` — PARTIAL (**13**):
     A006, A012, A019, A021, A026, A044, A060, A062, A063, A070, A073, A078,
     A079; GAP (**1**): A013.
   - `src/checks/automation/proof.automationvoice.txt` — PARTIAL (**10**):
     A028, A044, A054, A055, A056, A061, A079, A100, A107, A132; GAP (**12**):
     A011, A014, A029, A039, A076, A091, A092, A101, A102, A103, A108, A115.
   - `src/checks/automation/proof.automationactions.txt` — PARTIAL (**1**):
     A034; GAP (**1**): A025.
   - `src/checks/automation/proof.automationpointmenus.txt` — PARTIAL (**1**):
     A131.
   - Dispositions: **35 MATCHED**, **4 RETIRED-REPRESENTATION**:
     automationvoice A092 (`LaneHandle.valid()` native row lookup) and
     A102/A103 (`mouseGrabberItem` identity), plus automationactions A034
     (the old rendered canvas row-list `size() > 1` staging guard). Actual
     pointer, cancellation and held-B outcomes execute on the mounted surface.
2. **Fork laws**, `fceecd88:src/checks/automation/…`:
   - `automationrouting.cpp:44-71` (`middlePanIsolated`): while a middle press
     pans, and again after its release, the band preview contains no lane
     (`:61,71` → A006/A012).
   - `:74-95` (`voicePressIsolated`): the rendered voice-changes input has
     non-empty bounds (`:77` → A013); a left press there leaves the document
     frozen (`:91` → A019) and the edit cursor unchanged (`:94` → A021).
   - `:97-133` (`rightBandPreviewIsolated`): at the right-press moment itself
     no pan is live (`:114` → A026); the band only arms after the drag distance
     (already S018/S019).
   - `:135-193` (`pencilEditTargetsOnlyItsLane`): during the pencil press and
     after its release the band preview stays empty (`:168,192` → A044/A063),
     the cursor never moves (`:189` → A060), and no pan is live (`:191` → A062).
   - `:195-232` (`defaultBodyClickSetsCursorOnly`): a default body press and
     release keep the band preview empty (`:217,231` → A070/A079), the cursor
     stays parked *while the press is held* (`:221` → A073; it parks at release
     per S032), and no pan is live after release (`:230` → A078).
   - `automationvoice.cpp:97-131`: during a horizontal voice drag the markers
     layer republishes (`:102` → A011) and the input shows `SizeHorCursor`
     (`:106` → A014); after release it returns to `ArrowCursor` (`:125` → A029)
     and the band preview is clear (`:124` → A028).
   - `:134-171`: stationary vertical jitter keeps the arrow cursor (`:157` →
     A039) and leaves the band preview clear (`:169` → A044).
   - `:174-221`: an Alt drag commits through fine snap with exactly one
     revision and one undo entry (`:213-215` → A054/A055/A056) and a clear band
     preview (`:220` → A061).
   - `:226-266`: after a collision merge the cursor is the arrow (`:258` →
     A076) and the band preview clear (`:261` → A079).
   - `:286-334` (`voiceEscapeAndUngrabCancel`): the mounted input and its
     marker route exist (`:290,292` → A091/A092); after Escape the band preview
     is clear and the cursor arrow (`:315,316` → A100/A101); the ungrab case
     pins `quickWindow().mouseGrabberItem()` identity (`:322,324` → A102/A103,
     representation) with a clear band preview and arrow cursor after
     (`:329,330` → A107/A108).
   - `:336-381`: during a duplicate-occurrence drag the markers layer
     republishes (`:358` → A115) and the band preview stays clear after
     (`:379` → A132).
   - `automationactions.cpp:92-121` (`actionHeldKeyGestures`): with B held, a
     real pointer press/release on the pan lane keeps the pencil action checked
     (`:119` → A025; the keyboard halves are already S030/S031).
   - `automationactions.cpp:152-156` (`projectionCanvasOrigin`): the rendered
     row list has more than one row (`:156` → A034).
   - `automationpointmenus.cpp:513-530` (`pointMenuStaleDocument…`): before the
     stale slip, the opened point menu's Delete row actually renders with a
     non-null scene center (`:530` → A131).
3. **Current Swift/QML state**, verified after the split:
   - `src/swift/app/drawer/automation/AutomationInteraction.swift:512-543`
     routes presses: middle → `panActive` (`:522-526`), right → `band`
     (`:527-537`), left → `pressPlot` (`:538-539`); `:545-570` moves; release
     at `:630-650`; Escape drops band/pan/gesture at `:685-698`. The published
     observables exist: `AutomationPage.swift:152-153` (`bandVisible`,
     `bandRect`), `:231-232` (`hasBand`, `isPanning`), published by
     `AutomationOverlayPublication.swift:21-35`. No predicate today reads them
     in the pan/pencil/body/voice scenarios — that is the routing PARTIAL.
   - `src/swift/app/drawer/voicechanges/VoiceChangesInteraction.swift:97-105`
     captures a marker drag; `:114-147` moves it (Alt fine snap `:125`,
     `cursorKind = 3` `:129`, marker republication `:130-134`); `:149-169`
     releases with a single commit; `cancelDrag()` resets `cursorKind = 0`
     (`:476-483`). `VoiceChangesPage.swift:142` publishes `cursorKind`, `:173`
     the `markers` model, `:204` `dragPreviewTick`.
   - `src/ui/songview/quick/drawer/VoiceChangesPage.qml:423-425` maps
     `cursorKind` case 3 to `Qt.SizeHorCursor`; the mounted plot input is
     `voicePlotInput` (`"voicePlotInput"`), used by
     `src/checks/editorqml/tst_EditorDrawer.qml:2935`. The drawer lane mounts
     every section through settings (`tst_EditorDrawer.qml:400-410,1088`).
   - `src/ui/songview/quick/drawer/AutomationPage.qml:309-330` renders the
     published `valueLabels` rows and `:347-402` the nodes;
     `AutomationParameter.swift:68` fixes the catalog count
     (`controllers.count + 1`). The rendered tab strip is
     `"automationParameterTab" + index` (`tst_ShellDrawerParity.qml:252-257`).
   - The B-hold keyboard halves are executed at
     `src/checks/editorqml/tst_ShellWindow.qml:870-895` (S030/S031); that file
     is task 83's — read-only evidence here, never edited.
   - `src/checks/editorqml/tst_ShellGridMenu.qml:1695-1727` stages a written
     automation node (`stageAutomationMenuPoint`) and `:1729-1750` opens its
     point menu through a real right-press.
   - Task-79 ownership: `automationselection.swift`,
     `tst_automationediting.swift`, `AutomationPageChecks.swift`,
     `AutomationInteraction.swift`, `AutomationEdits.swift`,
     `AutomationSelectionCommands.swift`, `tst_ShellGridInput.qml` and the
     automationselection/tst_automationediting ledgers are 79's. Only the
     conditional `AutomationInteraction.swift` repair is shared after rebase;
     all their selected rows and messages remain untouched.

# Exact write set

- `src/checks/automation/automationcanvaslayout.swift` — band-preview
  negatives inside `drawerAutomationMiddlePanIsolation` (A006/A012).
- `src/checks/automation/automationcanvasediting.swift` — press-time
  `isPanning` under a right press (A026), body-press band/cursor/isPanning
  clauses beside S029–S032 (A070/A073/A078/A079), and the voice-area press
  isolation with a co-attached `VoiceChangesPage` (A019/A021).
- `src/checks/automation/domain/gesturePointRange.swift` — pencil-stroke
  band/cursor/isPanning clauses beside S020–S028 (A044/A060/A062/A063).
- `src/checks/drawerpresentation/voice_interaction.swift` — band-preview
  negatives after each slot sequence with a co-attached `AutomationPage`
  (A028/A044/A061/A079/A100/A107/A132), Alt-drag revision/history depth beside
  `drawerVoiceAltFineClockLattice` (A054/A055/A056), cursor-kind transitions
  (A014/A029/A039/A076/A101/A108), with A091's input geometry proved mounted.
- `src/checks/drawerpresentation/voice_projection.swift` — drag-time marker
  republication predicates (A011/A115).
- `src/checks/automation/automationactions.swift` — pointer half of the held-B
  pencil latch (A025); do not add a catalog-count copy or non-empty-list check.
- `src/checks/automation/automationpointmenus.swift` — pre-rewrite Delete-row
  rendering anchor beside the existing stale journey (A131's Swift half).
- `src/checks/editorqml/tst_EditorDrawer.qml` — mounted journeys: rendered
  voice input bounds (A013), cursor shapes across drag/jitter/collision/
  escape/ungrab-release, band never visible during those gestures, marker
  draft republication during drags.
- `src/checks/editorqml/tst_ShellGridMenu.qml` — point-menu Delete rendering
  (A131) and physical B-down → pan-lane pointer stroke → B-up (A025).
- `src/checks/automation/proof.automationrouting.txt` — only the 14 selected
  rows and their predicates.
- `src/checks/automation/proof.automationvoice.txt` — only the 22 selected
  rows (19 mapped; A092/A102/A103 retired).
- `src/checks/automation/proof.automationactions.txt` — only A025/A034.
- `src/checks/automation/proof.automationpointmenus.txt` — only A131.
- `src/swift/app/drawer/automation/AutomationInteraction.swift` — selected-law
  repair only; **rebase after 79 lands**.
- `src/swift/app/drawer/voicechanges/VoiceChangesInteraction.swift` — selected
  drag/cancel-law repair only.
- `src/ui/songview/quick/drawer/VoiceChangesPage.qml` — selected mounted cursor
  or cancellation-law repair only.

The three listed production files are conditional on demonstrated divergence;
the write set does not include any other task-79 file. Preserve 79's selected
drag predicates and behavior after rebasing `AutomationInteraction.swift`.
`tst_ShellWindow.qml`,
`tst_ShellDrawerParity.qml`, `tst_ShellGridInput.qml`,
`ShellWindow.qml`, `EditorSurface.qml`, `EditorDrawer*.swift`,
`ApplicationSession.swift`, `DocumentWorkspace.swift` and every task-78
reserved file are unchanged. No CMake or bridge-registration changes.

# Prerequisites

The sprint-3 §8 split/path repair and task 79's settled selected-drag rows
(this task must not regress or re-anchor them). Consumes only existing
interfaces: `AutomationPage.pointerPress/Move/Release`, `bandVisible`,
`isPanning`, `VoiceChangesPage.pointerPress/Move/Release`,
`cursorKind`, `markers`, `dragPreviewTick`, `isPencilMode`. No dependency on a
new interface from tasks 79–84 or 86–88. Group A owns `tst_ShellGridMenu.qml`;
task 86 rebases that file after this task's accepted checkpoint.

Forward pointer: task 87's roll-key gate consumes this task's held-B
drawer-command outcome (`automation.isPencilMode` surviving a pointer stroke)
as its drawer-command contract; it edits `tst_ShellWindow.qml` only after 83
lands, so no file handoff is needed here.

# Interface contract

- No new production API. All new predicates read published state:
  `page.bandVisible`/`page.hasBand` (the Swift band is single-parameter, so
  "the band preview contains the pan lane" is exactly `bandVisible` while the
  pan parameter is active), `page.isPanning`, `page.cursorKind`,
  `session.editCursor`, document/history snapshots, `voicePage.cursorKind`,
  `voicePage.dragPreviewTick`, and the mounted items' `cursorShape`.
- A026 reads `isPanning` between the right press and any move; A073 reads
  `session.editCursor` between body press and release; A060 reads it after the
  pencil release — each with its own literal message, existing messages
  verbatim.
- Voice-journey cursor clauses assert both the published `cursorKind`
  (3 during an armed drag, 0 otherwise) and, on the mounted lane, the input
  item's `cursorShape` (`Qt.SizeHorCursor`/`Qt.ArrowCursor`), one literal per
  fork clause (A014, A029, A039, A076, A101, A108).
- A011/A115 assert the drag republices markers: `dragPreviewTick` follows the
  moved draft and the `markers` model carries the projected draft position
  during the hold, with no document change until release.
- A054/A055/A056 assert the Alt drag's commit advances the revision by
  exactly one and records exactly one undo entry (snapshot +1 revision, +1
  count, +1 index), separate literals from the existing lattice message.
- A091 and A013 use the real mounted `voicePlotInput` bounds in their respective
  Escape and press-isolation journeys, not a presenter-only size surrogate.
  A092's native `LaneHandle` existence guard retires; do not invent another
  route-existence seam.
- A025 requires physical B key-down in the real ShellWindow lane, a genuine
  press/release on the pan lane while B remains held, and observation that the
  pencil stays active and the point commits; B-up restores the temporary latch.
  The Swift `isPencilMode = true` fixture is supplementary, never the proof of
  a held keyboard key. A034 retires its old canvas-list staging representation
  rather than adding a bare `count > 1` or model-to-renderer copy assertion.
- A131: the mounted journey opens the point menu on a written node through a
  real right-press and asserts the Delete row renders (visible delegate whose
  mapped scene position is non-null) before the Swift stale journey's rewrite;
  the stale rejection clauses keep their existing S224/S036 anchors.
- The four named representation rows cite their exact fork expressions and
  fresh mounted replacement journeys. No window-grabber identity, native
  `LaneHandle` or old canvas-list size is reconstructed. Cancellation and
  no-commit outcomes retain S199/S201 and execute in the same verification run.
- Task 79's messages ("selected drag moves the grabbed lane", "one undo
  restores all selected lanes", the prompt messages, and every
  automationselection/tst_automationediting anchor) are preserved verbatim and
  never re-anchored here.

# Implementation steps

1. Add the band/pan/cursor predicates and voice clauses before any production
   repair. The controller records the first execution only after the group
   settles; green existing behavior is honest evidence, not a manufactured RED.
2. Extend the middle-pan, body-click, pencil and band scenarios in place
   (same fixtures, same `cppID` families) to read `bandVisible`/`isPanning`
   at the fork's exact moments, including between press and release.
3. Co-attach a real `AutomationPage` in the voice fixture (same session) and a
   real `VoiceChangesPage` in the automation fixture for the cross-page
   isolation rows; drive the voice page's own pointer route only.
4. Add the mounted drawer journeys in `tst_EditorDrawer.qml`: open the
   sections through settings and drag real markers (commit, jitter, collision,
   Alt and Escape). For ungrab cancellation, close or hide the actual mounted
   host while a drag is held, observe cancellation before fixture destruction,
   then release. Read cursor, band and draft state; do not call `cancelDrag`
   as a substitute or synthesize focus/grab forwarding.
5. Add the mounted point-menu journey in `tst_ShellGridMenu.qml` reusing
   `stageAutomationMenuPoint`; assert the rendered Delete row and its mapped
   center before closing the menu (the stale slip stays in the Swift lane).
6. Fix a demonstrated selected-law divergence only in the three named
   production owners; **rebase after 79 lands** before changing interaction.
   An out-of-set defect requires controller coordination, not silent expansion.
7. After the group settles, run the three lanes and attach only the executed
   anchors to the selected rows in the same change, via `deno task proof:edit`.

# Acceptance predicate

Controller-run on the settled built tree, separate invocations, each at most
180 s:

- `deno task verify --filter swiftcore-projectsession --verbose` — band/pan/
  pencil/body/voice-press isolation, Alt history depth, cursor-kind
  transitions, marker republication, held-B fixture and stale-menu anchor;
  `build/proof-evidence/swiftcore-projectsession.json`.
- `deno task verify:qml --verbose` — mounted drawer input bounds, real cursor
  shapes, band isolation across gestures and draft marker republication;
  `build/proof-evidence/editorqml-drawer.json`.
- `deno task verify:shell --filter shell-grid-menu --verbose` — rendered
  point-menu Delete row and the physical held-B pointer journey;
  `build/proof-evidence/shell-grid-menu.json`.

The Swift suites dispatch from `src/checks/workspace/SessionChecks.swift:83`
(`runVoiceChangesPageChecks`) and `:84` (`runAutomationPageChecks`), registered
at `src/checks/checkcatalog.cpp:107-125`; the QML lanes are
`src/checks/editorqml/EditorQmlTests.swift:23` and
`src/checks/editorqml/ShellQmlTests.swift:66`; evidence writing is
`tools/run_checks.ts:426-434`. Offscreen drawer rendering proves the mounted
item properties, not physical-screen cursor pixmaps; report that limit.

# Task-specific constraints

All **sprint-3 §8 Wave constraints and §9 policy** are incorporated: Swift 6.4 idioms, no
hot-path temporaries, two-line comments, base-font geometry, WCAG AA over
pixel parity, sole window keyboard authority (the B-hold journeys never add a
dispatcher, synthetic forwarding or focus memory; the mounted spin/field
surfaces never claim bare Space), one message-anchored predicate per fork
clause with existing messages verbatim, real fixtures and no test seams, no
`Qt.callLater` coalescing or idempotence guards, workarounds need user
approval, deferred menu rows and parked areas unchanged. No new C++.

Retire only the four named native representation rows within this surface,
with exact fork evidence and fresh mounted journeys. Do not port
`userGestureActive`/QQuick hit-delivery clauses — those are already retired
rows. Preserve task 79's selected rows, messages and write behavior exactly;
do not grow the write set into `tst_ShellGridInput.qml` or
`automationselection.swift`. Preserve existing messages and forbid new
bare-existence, non-empty-list or copied-projection checks.

# Controller verification

After fresh evidence, run `deno task proof check --executed`, then separately:

- `deno task proof sites automation/proof.automationrouting.txt --status PARTIAL`
- `deno task proof sites automation/proof.automationrouting.txt --status GAP`
- `deno task proof sites automation/proof.automationvoice.txt --status PARTIAL`
- `deno task proof sites automation/proof.automationvoice.txt --status GAP`
- `deno task proof sites automation/proof.automationactions.txt --status PARTIAL`
- `deno task proof sites automation/proof.automationpointmenus.txt --status PARTIAL`

Expected: 14 routing rows, 19 voice rows, A025 and A131 become MATCHED;
A092/A102/A103 and actions A034 become RETIRED-REPRESENTATION. No
other disposition changes and no ledger deletion; task 79's rows in
`proof.automationselection.txt`/`proof.tst_automationediting.txt` are
untouched. Inspect the mounted cursor/band/menu journey on the real drawer,
not only the presenter assertions.
