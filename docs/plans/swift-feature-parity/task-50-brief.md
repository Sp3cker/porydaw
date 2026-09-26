# Context

Task 50 — ED12 keyboard precedence family. Three ledger families on three surfaces,
so this brief dispatches as 50a/50b/50c (task-51 precedent). 50a: window-tier
shortcut precedence over mounted chrome (`proof.windowtier_keyboard.txt`, 70 GAP +
13 PARTIAL, plus the mounted halves of `proof.localinputtier_text.txt`'s 36
PARTIAL). 50b: the shared-popup cross-menu arbitration rows task 47 parked
(`proof.automationpointmenus.txt` A070/A071, A148–A155, A170–A177, A192–A194, A199,
A201–A204). 50c: pitch-bend overlay key ownership
(`proof.localinputtier_pitchbend.txt`, 36 GAP + 1 PARTIAL). Fork oracle: `git show
fceecd88:src/checks/selectionkey/windowtier_keyboard.cpp`,
`.../localinputtier_pitchbend.cpp`, `src/checks/automation/automationpointmenus.cpp`
(ledger-pinned revisions byte-identical at fceecd88).

1. **AGENTS.md 'Global keyboard shortcut priority' is the spec** (no second
   dispatcher, synthetic forwarding, or focus memory). The mounted shell already
   satisfies its halves: one Repeater of `Qt.WindowShortcut` items over
   `shell.windowActionIds` (`ShellWindow.qml:215-232`); label/Tap/grip/toggle
   activation via `Keys.onShortcutOverride` Enter/Return claims with no Space
   handlers (`AutomationTabs.qml:122-145`, `EditorDrawer.qml:157-259`);
   `tst_ShellWindow.qml` pins S018–S060 (test_c/f/g/h/k).
2. **50a's one production gap is editor-key fall-through from button-like
   chrome.** Fork law: unhandled keys from focused chrome propagate to the view's
   editor routing — toggle/label focus routes arrows to the selected notes
   (A078–A081, A110/A111), Delete removes the lanes-scope selection's points
   (A062–A065), Select All selects notes and clears the time selection
   (A067–A069), Paste writes copied lane points at the edit cursor (A070–A075).
   Swift refuses routing today: `SongTabs.focusOwnsLocalKeys()` treats any focused
   `activeFocusOnTab` item or any item with a `text` property (every Button) as
   owning its keys, so the router at `SongTabs.qml:39-45` declines
   (`SongTabs.qml:13-30`). Window-scope commands (Copy/Solo/Space) are unaffected
   — native shortcut arbitration fires before key delivery.
3. **50b has no arbiter**: `AutomationPage` owns its menu/prompt
   (`AutomationPage.swift:180-183`), `RulerMenuPresenter` its menus
   (`RulerMenuPresenter.swift:54`), `PianoGrid` the division/feel menu
   (`PianoGrid.swift:546-567`); cross-publication dismissal is absent. Fork law:
   one shared popup session — a foreign publication takes over the open menu and
   kills its pending targets (no late prompt, zero writes, cpp:565-615); a menu
   published during another's open survives it and still picks (cpp:630-712); a
   parameter switch invalidates the value prompt but never the foreign menu
   (cpp:735-800); a right-press miss inside an active lanes time selection falls
   through to the shared time menu, Escape dismisses it (cpp:302-336). All three
   owners meet in `DocumentWorkspace` (`DocumentWorkspace.swift:37-99`);
   `RulerMenuPresenter` already holds `grid`/`automation` refs (:71-73); the
   roll's publication entry `openTimeSelection(x:)` exists
   (`EditorSurface.qml:456`), as does grid-menu focus return
   (`EditorSurface.qml:139-159`). Task 47 landed selection-transition retirement
   (`4050d97c`): prompts are spared by selection identity, closed only by
   revision/track/parameter staleness — 50b must not widen that.
4. **50c is mostly proof.** `PitchBendPopup.qml:65-80` already claims keys while
   open (ShortcutOverride accepts everything except Undo/Redo when no numeric
   field has focus; onPressed routes Escape + `bridge.routeUnclaimedKey` and
   accepts all); numeric `DragInput`s are exempt;
   `PitchBendPresenter.swift:212-230` routes Delete/Enter/Space/Solo. Existing
   coverage (`test_popupSpaceAuditionSoloAndMuteAbsorption`,
   `test_windowUndoReachesOpenPopup`) is partial: exactly-once/still-once,
   clipboard sentinel, playback/mask conjunctions, the one-vertex Delete +
   two-step Undo journey, numeric Copy/BENDR/Space-yield, post-close resumption
   are unproved. Swift has no QAction counts; the count-free equivalents are the
   proof currency — "mask toggles exactly once per press" proves the window
   action did not double-fire, "sentinel text survives" proves window Copy never
   ran.
5. **Ledger state**: windowtier staging rows (band focus, `focusParameter`,
   fixture inserts, binding lookups: A002, A011-12, A021-22, A024, A027, A031,
   A042, A046, A057, A066, A077, A082-83, A085-87, A105-06) close as
   converted-window staging against the journey anchors (S018–S060 precedent);
   A023/A084 RETIRED stand. Automation: A161/A162 close via 50b's takeover
   anchors (their reasons predate the seam); A170-A173's native re-entrancy
   staging has no Swift counterpart — the last-publication-wins predicate covers
   the clause. Pitchbend A003/A005/A012 pin the fork QAction object:
   RETIRED-REPRESENTATION candidates at freeze.

# Exact write set

- **50a**: `src/ui/songview/quick/swiftroll/SongTabs.qml` (ownership law only);
  `src/checks/editorqml/tst_ShellWindow.qml` (new predicates; existing anchor
  messages verbatim). Ledgers: `src/checks/selectionkey/
  proof.windowtier_keyboard.txt`, `proof.localinputtier_text.txt`.
- **50b**: `src/swift/app/drawer/automation/AutomationPage.swift`,
  `AutomationInteraction.swift`, `src/swift/app/timeline/RulerMenuPresenter.swift`,
  `src/swift/app/roll/PianoGrid.swift`, `src/swift/app/DocumentWorkspace.swift`,
  `src/checks/automation/automationpointmenus.swift`,
  `src/checks/automation/AutomationPageChecks.swift`,
  `src/checks/editorqml/tst_ShellGridMenu.qml` (append; task-46 anchors
  verbatim). Ledger: `src/checks/automation/proof.automationpointmenus.txt`.
- **50c**: `src/checks/editorqml/tst_ShellPitchBend.qml`; repair-only, RED-gated:
  `src/swift/app/pitchbend/PitchBendPresenter.swift`,
  `src/ui/songview/quick/PitchBendPopup.qml`. Ledger:
  `src/checks/selectionkey/proof.localinputtier_pitchbend.txt`.

No CMake change. Hot files read-only for task 50: `ShellWindow.qml`,
`ShellPresenter.swift`, `ApplicationSession.swift`, `EditorSurface.qml`. Sizing
exception per subtask (one behavior family, one verification-surface set) — named
for the dispatch table.

# Prerequisites

- 50a: 46 + 51b landed (own the `tst_ShellGridMenu.qml`/`tst_ShellWindow.qml`
  regions built on); 38a landed (consumes `session.timeSelection` /
  `applyTimeSelection` — interface only).
- 50b: 46 + 42 landed (own `tst_ShellGridMenu.qml` / `PianoGrid.swift`); 47
  landed (menu-staleness and sparing clauses consumed unchanged).
- 50c: 41 landed (owns `pitchbend/*`, `PitchBendPopup.qml`). Subtasks are
  mutually disjoint and parallel once prerequisites settle.

# Interface contract

**50a — routing law.** `SongTabs.focusOwnsLocalKeys()` keeps the closeDialog
guard, the `swiftRollInput` fast path, `focus === root` → false, and walk-off-root
`true` (chrome outside the tab area keeps its keys). Within the root subtree,
ownership narrows to modal or text-entry items — discriminator `focus.modal ||
focus.displayText !== undefined` (TextInput/TextField/editable-ComboBox carry
`displayText`; Buttons do not). The `activeFocusOnTab` and blanket
`focus.text !== undefined` clauses are deleted. Unhandled keys from button-like
chrome (parameter tabs, Tap button, drawer grips/toggles, transport controls)
then propagate natively to the existing router at `SongTabs.qml:39-45` through
the same `routeEditorKey`/`routeEventListKey` entry the roll uses — no new
dispatch path, no forwarding, no focus memory. Chrome keeps consuming its own
keys exactly as today. Regression net: every existing text/numeric/Space
ownership anchor in test_c/f/h/i stays green verbatim.

**50a — new message-anchored predicates in `tst_ShellWindow.qml`** (one per fork
clause; journeys stage the automation drawer via the test_k pattern — real
`forceActiveFocus` + real `keyClick`):
- "an unrecognized key changes nothing" (F24; counts/summary/revision unchanged).
- Automation grip (`drawerHandle_automation`): "the automation grip grows by one
  step on Up", "grip Down restores the automation height", "cross-axis grip
  arrows never resize the automation section", "grip arrows never trigger window
  actions", "the automation grip keeps both fixture notes unchanged".
- Drawer toggle (`drawerToggle_automation`): "toggle arrows route to the selected
  notes by one grid step", "toggle Up transposes the selected notes", "Enter
  toggles the focused drawer section", "Return restores the focused drawer
  section", "toggle activation keys never mutate the selected notes" (per-note
  tick/key identity, notes resolved by id).
- Window commands over label focus (lanes time selection staged over two written
  CC lanes + volume; notes selected by id): "window Copy over the focused label
  captures the lane selection", "window Copy never edits the song over label
  focus", "Delete removes only the selected lanes' points", "the unselected lane
  keeps its point", "Select All over label focus selects the notes and clears the
  time selection", "Paste at the edit cursor writes the copied lanes only",
  "label-focus arrows advance the selected notes one grid step", "label-focus Up
  transposes the selected notes", "the active parameter survives label-focus
  commands".
- Prompt text-ownership (value prompt opened through the page's public route on
  the volume lane, draft 48): "the automation prompt selects its draft on Select
  All", "prompt Copy copies the selected text without the window action", "prompt
  Delete clears the draft", "prompt Paste restores the drafted text", "prompt
  Escape closes without a write", "the prompt journey never changes the
  selection" (note + staged time-selection equality — closes the A030/A038/
  A052-56 PARTIAL halves and localinputtier_text's mounted halves).
- Tap button: "Tap keys never change the revision or undo count", "tap Space
  never changes the revision or undo count", "Return never retargets the active
  parameter"; extend the existing Space predicates with staged-selection
  equality (A103). A029/A033 close on S043/S045 plus "a second activation never
  stacks" (one active-parameter change per key).

**50b — arbitration seam (Swift-owned, wired in `DocumentWorkspace`).**
- `AutomationPage` gains `@QtIgnored public var onMenuOpened: (() -> Void)?`
  (fired on menu open edges only — never prompt/confirmation, never close) and
  `@QtIgnored public var onRequestTimeMenu: ((Double, Double) -> Void)?`, fired
  from the band's right-press miss path when an active lanes-scope time selection
  contains the press tick (`AutomationInteraction` decides containment; with a
  menu open the miss still dismisses and swallows the release exactly as
  S088-S090 pin).
- `RulerMenuPresenter` publication sites (`openRulerAtRelease`,
  `openTimeSelection`) close the automation page's open menu (menu only —
  prompts and the lane-delete confirmation spared) and call
  `grid.dismissGridMenu()`.
- `PianoGrid.openGridMenu(kind:)` gains `@QtIgnored public var onGridMenuOpened:
  (() -> Void)?`. `DocumentWorkspace.init` wires: `onGridMenuOpened` → close
  ruler + automation menus; `automationPage.onMenuOpened` → close ruler + grid
  menus; `automationPage.onRequestTimeMenu` → `rulerMenu.openTimeSelection(x)`
  (y kept for the QML position handoff the roll path uses).
- Seam laws (fork parity): last publication owns the surface; a displaced menu's
  captured targets never fire (existing revision/parameter guards carry this —
  do not weaken them); prompts/confirmations are never displaced by a foreign
  menu; automation-side invalidations (selection transition, parameter switch,
  track/document switch) close only automation's own state, never the foreign
  menu; a pick closes the menu, applies exactly one effect, and returns focus
  through the existing EditorSurface paths.
- Presenter predicates (`automationpointmenus.swift`, registered in
  `AutomationPageChecks.swift`): "a miss press inside the selection opens the
  time menu", "the fallback menu offers the time-selection rows", "Escape
  dismisses the fallback menu", "the division menu publishes over the open point
  menu", "the displaced point menu never returns", "the division pick changes
  the grid selection", "the takeover writes nothing", "no prompt surfaces after
  the takeover", "a menu published during another's open displaces it", "the
  surviving menu still picks a denominator", "the parameter switch invalidates
  the prompt beside a foreign menu", "the foreign menu survives the parameter
  switch", "the post-switch pick still changes the grid selection" (each journey
  pinned by revision/undo/snapshot no-write equality).
- Mounted predicates (`tst_ShellGridMenu.qml`, real pointer/key delivery): "the
  published division menu dismisses the open point menu", "the division pick
  returns focus to the publishing control", "the fallback time menu opens from
  the automation band", "Escape closes the band's fallback menu".

**50c — pitch-bend overlay predicates (`tst_ShellPitchBend.qml`)**, real key
delivery on the mounted popup (clipboard text read back by pasting into a probe
`TextInput`; playback observed as session transport state): "delivered G opens
the editor exactly once", "repeat G never reopens the editor" (autorepeat flag),
"graph Solo toggles the track exactly once", "graph Copy leaves the clipboard
sentinel untouched", "graph Mute never toggles playback or the mask", "the drawn
stroke creates one undoable vertex", "Delete removes exactly the selected
vertex", "the first standard Undo restores the deleted vertex", "the second
standard Undo restores the pre-edit document", "the numeric field selects its
value on Select All", "numeric Copy copies the selection without the window
action", "the numeric field keeps its bend range", "numeric Space toggles the
transport twice without editing text", "Escape closes the pitch-bend editor",
"the closed session leaves no document changes", "Solo resumes as a window
command after the popup closes" (mask toggles once per press, twice total).
Repair-only, RED-gated: if numeric Space is consumed by the field, fix the
DragInput validator propagation, never a new key handler; if autorepeat G
reopens, gate `openSelected` on `isOpen`. Undo travels the window shortcut into
the popup (existing accepted design) — same observables as the fork's claimed
Undo.

# Implementation steps

1. **50a** RED: add the predicates with the gate unchanged — the toggle/label
   arrow, Delete/Select All/Paste, and prompt rows must fail. Apply the
   `focusOwnsLocalKeys` narrowing; new predicates GREEN, every existing
   test_c/f/h/i anchor green. A text/numeric regression means fix the
   discriminator (e.g. add `focus.echoMode !== undefined`) — never re-widen to
   `activeFocusOnTab`. Journeys stage: drawer open at height, lanes written
   through the session staging family, notes resolved by id, selection via
   `session.applyTimeSelection`.
2. **50b** RED: presenter predicates against the unwired workspace (takeover and
   fallback fail). Add the seam as contracted; GREEN. Add the mounted journeys;
   38b retirement/enablement anchors and S110-S114/S128-S131 re-run green
   verbatim.
3. **50c** RED per predicate; repair only through the named exceptions; the
   existing thirteen pitch-bend functions are the regression net.
4. Each subtask lands as its own commit with its ledger edits; record RED→GREEN
   only where behavior changed.

# Acceptance predicate

- 50a: `deno task build:checks`; `deno task verify:shell --filter shellwindow
  --verbose` (new + regression anchors); `deno task verify --filter swiftcore
  --verbose` (localinputtier_text presenter suite unchanged-green).
- 50b: `deno task build:checks`; `deno task verify --filter swiftcore --verbose`
  (automation suite + new predicates); `deno task verify:shell --filter
  shell-grid-menu --verbose`; `deno task verify:qml --verbose` (drawer
  regression).
- 50c: `deno task build:checks`; `deno task verify:shell --filter
  shell-pitch-bend --verbose`; `deno task verify:shell --filter shell-menus
  --verbose` (S009-S012 G-route regression); `deno task verify --filter
  swiftcore --verbose`.
- Offscreen lanes are self-contained (no desktop audio; playback is transport
  state). Implementers run these; AGENTS.md's no-stress rule covers
  human-input flakiness.

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no
  pixel constants; geometry stays base-font multiples; no palette literals.
- No second dispatcher, synthetic forwarding, or focus memory — 50a widens the
  one existing router's reach through native propagation only; 50b arbitrates
  menu state, never keys.
- One message-anchored predicate per fork clause; existing anchor messages
  verbatim. Implementers never edit ledgers; the controller delegates
  per-subtask commits:
  - 50a `windowtier_keyboard`: A010 → the F24 anchor; A011-20 → grip journey
    anchors (staging rows cite the journey function); A105-16 → toggle anchors;
    A024-42, A057, A066, A077 → staging anchors; A045-56 + A030/A038 → prompt
    journey anchors; A046-51, A058-76 → label-command anchors; A078-81 →
    label-arrow anchors; A082-87 → staging; A091-94, A101-03 → tap no-change
    anchors; A029/A033 → S043/S045 + "a second activation never stacks";
    refresh the header commands to 50a's lanes. `localinputtier_text`: flip the
    PARTIALs whose unproved halves the mounted journey executes; leave the rest
    with reasons.
  - 50b `automationpointmenus`: A070/A071 → fallback anchors; A148-55 →
    takeover anchors (A155 → "the division pick returns focus to the publishing
    control", ruler-control deviation recorded); A161/A162 → "no prompt surfaces
    after the takeover" + S038; A170-77 → survival anchors (native re-entrancy
    staging recorded as retired representation inside the reason); A192-94,
    A199, A201-04 → switch/survival anchors.
  - 50c `localinputtier_pitchbend`: A013-16 → exactly-once anchors; A018-21 →
    Solo/Copy/Mute anchors; A022-28 → vertex/Undo anchors (window-Undo routing
    deviation recorded on A025-27); A029-35 → numeric anchors; A036-41 →
    close/resume anchors; A003/A005/A012 → RETIRED-REPRESENTATION (fork QAction
    staging); native focus-window identity rows (A010, A011, A018 focus halves,
    A029, A038, A039) map to mounted equivalents or keep reasons — agent judges
    at freeze.
- Accepted deviations (record, do not code around): Tab-traversal rows close on
  staged focus (the fork's process-global TabFocusAllControls guard has no QML
  counterpart); count clauses re-expressed as exactly-once state observables;
  the foreign-pick focus target is Swift's publishing control, not a
  ruler-division item; popup Undo travels the window shortcut.
- Rows left untouched: all other open rows of the three ledgers; task-46/47/51
  anchors and blocked rows.

# Controller verification

1. Shared baseline after each subtask settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`, `deno task proof check
   --executed`, `deno task proof check --strict-mappings`.
2. Native smoke (desktop), once after all three: focus a drawer toggle and press
   Right/Up with notes selected — the notes move, the drawer does not; ⌘C over a
   focused parameter label copies the lane selection; open the point menu and
   click the grid division control — the point menu yields, the pick changes the
   denominator and focus returns to the control; right-click empty automation
   canvas inside a drag-selected range — the time menu opens, Escape closes it;
   open the pitch-bend editor with G — Solo toggles once, ⌘C leaves the
   clipboard untouched, ⌘Z twice unwinds the curve edit, Space in the numeric
   field starts transport.
