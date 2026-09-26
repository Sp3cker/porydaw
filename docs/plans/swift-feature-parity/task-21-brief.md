# Context

ED07 slice: the automation point-menu surface — right-click node menu, Set Value
prompt, Delete, focus return, rendered menu rows/accessibility. Spec ledger:
`src/checks/automation/proof.automationpointmenus.txt` (43 GAP, 49 PARTIAL;
91 resolved rows untouched). Classification of all 92 open rows:

- **Behavior, this task (49)**: 15 GAP (A021, A031, A040, A046, A054, A063,
  A068, A104, A105, A115, A128, A131, A188, A209, A225) + 34 PARTIAL (A004,
  A005, A017–A019, A023, A033, A034, A042–A044, A059, A060, A066, A079, A095,
  A101, A103, A106, A107, A112, A113, A117, A126, A127, A132, A133, A142, A182,
  A184–A186, A205, A211). Every GAP row here is a "GAP-retain: focus … is
  QML-owned" or "native rendering" row whose observable fact IS provable in
  the QML drawer lane: the focus route exists in production
  (`AutomationPrompt.takeFocus` → `field.focusInput` + `selectAll`,
  src/ui/songview/quick/drawer/AutomationPrompt.qml:37–45; `focusOrigin` →
  `plot.forceActiveFocus` with `onClosed` wiring, AutomationPage.qml:232–234,
  628–638; the `plotFocused` back-publication AutomationPage.qml:282–288 into
  `AutomationPage.plotFocused`, AutomationPage.swift:123), and the drawer lane
  already drives the rendered route (writeVolumeLanePoints →
  openAutomationNodeMenu → triggerAutomationMenuRow(1) → prompt input,
  tst_EditorDrawer.qml:132–140).
- **Behavior, deferred to follow-up briefs (17)**: A041, A047–A049 (second-track
  prompt-switch staging needs a two-track production fixture); A073, A074,
  A081, A087–A089 (cross-surface invalidation causes — see product-gap note);
  A096 (rendered lane plot body belongs to the automation painting/raster
  surface); A161, A162, A181 (foreign-publication prompt/popup observations);
  A216, A219, A220 (two-point CC lane switch fixture).
- **Blocked (26, leave unchanged)**: A070, A071 — the miss-press fallback
  time-selection menu is the ruler/time-selection surface (ED04; R15/R18), no
  Swift ingress. A148–A155, A170–A177, A192–A194, A199, A201–A204 — the
  foreign ruler-division menu: `openDivisionMenu`/`GridSelection` exist nowhere
  in src/swift (verified by grep; only unrelated `MidiFile` division errors),
  so the blocker is the ruler-division surface (ED04), not this surface.
- **Representation**: no new rows; the existing RETIRED-REPRESENTATION rows
  (A069, A099, A145–A147, A165, A167–A169, A189–A191) stay untouched.

Suspected product gap (deferred slice, not repaired here): the original
retired the active point menu on a view-level selection/context change while
sparing independent prompts (`SongView::contextMenusInvalidated`,
automationcanvas_pointmenu.cpp:52–56 at f3069ef6); Swift invalidates only on
revision/track/parameter change (AutomationPage.swift:447–463), so a
selection-only change elsewhere has no ingress. The follow-up brief stages it
in the shell lane and decides gap vs not-applicable before any repair.

The origin/feature/swift-drawer-reactive `automationpointmenus_gap.swift` lead
is INVALID as spec (row-id-labeled conjunction booleans, refactored API); this
task uses only this tree's executing APIs.

# Exact write set

- `src/checks/editorqml/tst_EditorDrawer.qml` — new test functions (suite's
  descriptive `test_<Name>` convention, not letters): point-menu Delete +
  retarget + miss dismissal with focus facts; Set Value rendered route with
  prompt focus/Escape/accept/undo and parameter-switch invalidation; Tempo
  prompt focus; synthetic-default (projected node) menu with disabled-Delete
  accessibility. Reuse the existing helpers: `writeVolumeLanePoints`,
  `openAutomationNodeMenu`, `clickAutomationMenuRow`,
  `triggerAutomationMenuRow`, `awaitAutomationModal`, `automationLaneNodes`,
  `requestAutomationUndo`, `automationModel()` and the bootstrap read accessors
  (automationMenuOpen/PromptOpen/MenuActions/LaneEventCount/
  ActiveParameterIndex/DocumentRevision).
- `src/checks/editorqml/EditorQmlTests.swift` — only if unavoidable: one
  read-only accessor `automationTempoIndex()` following the existing
  `automationVolumeIndex()` pattern (src/checks/editorqml/EditorQmlTests.swift:997).
- `src/checks/automation/automationpointmenus.swift` — extend two existing
  registered functions only: insertion-undo assertions at the end of the
  empty-tick block in `drawerAutomationPromptTransactions`; menu/prompt-closed
  assertions after the stale refusal in
  `drawerAutomationPointMenuDeleteAndStale`'s stale half.

No new files, lanes or registrations: tst_EditorDrawer.qml runs in the DRAWER
lane; automationpointmenus.swift is already compiled and called through
`AutomationPageChecks.runAutomationPageChecks` → `runProjectSessionSuite`
(swiftcore). No production Swift/QML edits. A failing new assertion that
indicates missing production behavior is a BEHAVIOR-GAP: stop, report, do not
patch production in this task.

The implementer does not edit `proof.automationpointmenus.txt`; the controller's
ledger-agent remaps rows afterwards in the same commit.

# Prerequisites

- None blocking: R29's presenter-contract divergence concerns
  `publishedMarkers`/`pickerOpen`/`hoverTick`-style publication contracts; this
  brief's predicates use the already-executing modal APIs (`menuOpen`,
  `promptOpen`, `publishedMenuRows`, `consumeMenuAction`, item focus facts), so
  R29 does not gate it. The lane commands exist in verification.md.
- Coordinate with siblings before editing `tst_EditorDrawer.qml` if another
  active brief claims it; today only this brief does.

# Interface contract

- Focus take (A021, A046, A115, A188, A209): after the Set Value row is really
  clicked, `findChild(page, "automationPromptInput")` exists with
  `activeFocus === true` and `automationModel().plotFocused === false`; message
  e.g. "the value prompt takes active focus from the Set Value pick". A046
  asserts the same fact immediately before the parameter switch.
- Focus return (A031, A040, A054, A063, A068, A128, A225): after every modal
  close cause — row consumed, Escape, miss/outside dismissal, acceptance
  followed by `requestAutomationUndo()` — the plot item
  (`findChild(page, "automationPlot")`) holds `activeFocus` and
  `automationModel().plotFocused === true`; message e.g. "focus returns to the
  automation plot after the modal closes". A054 asserts the plot focus before
  the first right-press.
- Rendered menu route (A004, A005, A017–A019, A033, A034, A043, A044, A059,
  A060, A066, A079, A112, A113, A131, A184–A186): the menu opens from a real
  right-press on the drawn node; a real `clickAutomationMenuRow(deleteNode)`
  /`(setValue)` click commits; `awaitAutomationModal("automationMenu", false)`
  plus `!bootstrap.automationMenuOpen()` after an enabling pick (and the menu
  STAYS open after the disabled Delete click, A107, with
  `automationDocumentRevision()` unchanged); after a miss dismissal the paired
  release opens no new menu or prompt (A066).
- Prompt lifecycle (A023, A117, A211): after acceptance,
  `awaitAutomationModal("automationPrompt", false)` and
  `!bootstrap.automationPromptOpen()`; message "acceptance closes the value
  prompt".
- Synthetic default (A101, A103–A107): right-press the projected node (first
  `automationLaneNodes()` entry with `model.projected === true`, unwritten
  lane): the panel `automationMenuPanel` is realized (A104), the Set Value row
  renders enabled and Delete disabled (A103), the Delete row item (objectName
  `automationMenuRow_2`) has `enabled === false` and
  `Accessible.role === Accessible.MenuItem` (A105 — QuickMenuPanel.qml:113–116
  makes Item.enabled drive the accessible disabled state), and the disabled
  click is a no-op that keeps the menu open (A106/A107).
- Activation rows (A042, A095, A182, A205): tab activation goes through the
  real selector click with `automationActiveParameterIndex()` asserted, as
  `writeVolumeLanePoints`/`openAutomationTabMenu` already do.
- Swiftcore additions: after the duplicate no-op in
  `drawerAutomationPromptTransactions`, one `fixture.undo()` returns the lane
  to its pre-insertion values and snapshot equality (A126, A127); in the stale
  half of `drawerAutomationPointMenuDeleteAndStale`, after the refused Delete
  assert `!stale.page.menuOpen` and `!stale.page.hasPrompt` (A132, A133, A142).
- Scenario-fidelity note: the duplicate-occurrence fixture (A017–A019, A021)
  and the two-track fixture (A042–A044, A046) cannot be staged through
  production input; the predicates prove those clauses on a written node and a
  parameter switch respectively. The duplicate/track semantics stay proven by
  S039–S045/S051. The ledger agent keeps any row PARTIAL it judges
  scenario-material.
- All assertions carry contract-shaped messages (they are the anchors the
  ledger agent cites, as in proof.automationmenus.txt S028–S032); no sleeps —
  `tryVerify`/`tryCompare` polling only.

# Implementation steps

1. Add the drawer-lane tests to `tst_EditorDrawer.qml` in the order above,
   one commit-worthy group per journey (delete/retarget/miss; Set Value focus;
   Tempo; synthetic default). Run the lane after each group.
2. Add the two swiftcore assertion blocks to the existing functions; keep
   entry order in `AutomationPageChecks.swift` untouched.
3. Report each new predicate's verbatim message string, file and line, and the
   rows it is intended to cover — the ledger agent needs exact anchors.
4. Any focus/rendering assertion that fails against current production is a
   BEHAVIOR-GAP: stop and report with file:line evidence; no production edits
   inside this task.

# Acceptance predicate

All 49 in-scope rows have executing message-anchored predicates: 15 GAP and 34
PARTIAL rows proposed MATCHED per the groups above (scenario-material rows may
land PARTIAL per the fidelity note). No deferred/blocked row changes.

Controller-run named checks after the writer freezes:
- `deno task verify:qml --verbose` — new drawer predicates.
- `deno task verify --filter swiftcore --verbose` — extended automation suites.
- `deno task verify:bridge` — declaration guard (runs before each lane anyway).
- `deno task proof check` and `deno task proof check --executed` — after the
  controller-owned ledger handoff for `proof.automationpointmenus.txt`.

# Visual parity

- Counterpart: this surface never had a QWidget — the shipped original renders
  it in Qt Quick at pre-widget-deletion `b28f082758e63ef3cd2868f9205b96acfffb94f5`:
  `git show b28f0827:src/ui/songview/quick/drawer/{AutomationMenu,AutomationPrompt,AutomationPage}.qml`
  plus shared `src/ui/songview/quick/{QuickMenuPanel,PromptCard,PromptButton,DragInput}.qml`;
  row set and enablement from the C++ canvas
  `git show f3069ef6:src/ui/editordrawer/automationcanvas_pointmenu.cpp`
  (rows "Set Value" then "Delete"; Delete disabled on projected nodes). No
  .ui/.qss exists under src/ui at b28f0827 (verified by ls-tree). Manual:
  `docsrc/manual/automation.md`. No screenshots under docs/ for this surface.
- Match status: current `AutomationMenu.qml`/`AutomationPrompt.qml` differ from
  b28f0827 by import renames only; `AutomationPage.qml` drift is the accepted
  ramp-renderer removal (R26) plus the MoveCoalescer input batching — no modal
  visual change. No visible mismatch found.
- Contract to preserve: two-row node menu with QuickMenuPanel geometry already
  font-derived (`rowHeight = round(baseFontPx*1.6)`,
  `menuWidth = min(pageWidth, baseFontPx*18)`, check/arrow insets as font
  fractions, AutomationMenu.qml:19,98–105); colors exclusively from
  `gridPalette` pairs (menuBackground/menuHoverBackground/windowText/
  disabledText/separator) meeting WCAG AA; centered PromptCard (minimum width
  `baseFontPx*18`), DragInput `baseFontPx*16 × baseFontPx*2`, error row,
  Delete/Cancel PromptButton pair with mutually paired minimum widths; focus
  indication = prompt field selects all on open, menu highlights the current
  row. No pixel constants may be introduced.
- Acceptance: this task is check-only — no QML production edit is in the write
  set, so no visual delta is possible; the new tests assert rendered structure
  (panel, rows, enabled, accessible role, focus), never pixels. If a
  BEHAVIOR-GAP repair later touches QML, the controller must capture the real
  drawer surface (drawer-lane raster or native window capture), compare with
  the b28f0827 reference, and list and justify every deviation before merge.

# Task-specific constraints

- No production Swift/QML edits; no new C++; no QWidget resurrection; no
  debug-only accessors on the page — focus facts come from QML items and the
  published `plotFocused` flag.
- The conditional `automationTempoIndex()` bootstrap accessor (if needed) is
  read-only and follows the existing accessor pattern; nothing else may be
  added to EditorQmlTests.swift.
- Do not port the `*_gap.swift` lead from origin/feature/swift-drawer-reactive;
  do not write one boolean reported under many row IDs; do not assert pixel
  geometry; message anchors must describe contracts, not counts.
- Leave A070/A071 and the 24 ruler-division GAP rows unchanged with their
  blockers named; leave the 17 deferred rows unchanged.
- No ledger edits by the implementer; `deno task proof:edit` remapping of
  `proof.automationpointmenus.txt` is the controller's ledger-agent's, in the
  same commit as these checks.
