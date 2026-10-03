# Task 87 brief — window-tier key commands close their roll outcomes

# Context

The mounted ShellWindow keyboard journeys (task-58 lane) already prove the
delivery halves: window Copy fires over label focus, Delete/Paste/Select All
route to the editor, grip/toggle arrows never move notes, prompts return
focus. What stays PARTIAL is the outcome residue those journeys could not
stage: the fork's reserved tick-2400 two-note pair, the two-CC-lane scope,
the full time-selection survival fields, exact undo index/count arithmetic,
paste point values, and the single-key binding strokes. Extend the real mounted
keyboard journeys with a two-note selection, paired with Swift-tier exact
lane/history predicates. Retire only native staging representation inside this
surface; never simulate a grip/label no-op with an idle Swift session.
Freeze: HEAD `e334b318ecf391e3d4fac512c4a613303aff01e3`; oracle `fceecd88`.

1. **Verified census: 50 selected PARTIAL rows (38 to MATCHED, 12 to
   RETIRED-REPRESENTATION), two ledgers**, selected with
   `deno task proof sites selectionkey/proof.windowtier_keyboard.txt
   --status PARTIAL` (54 rows, paged with `--offset 20`/`--offset 40`) and
   `deno task proof sites selectionkey/proof.coreediting.txt --status
   PARTIAL`:
   - `selectionkey/proof.windowtier_keyboard.txt` (**44** of 54):
     - MATCHED via executed Swift/QML predicates (**32**): A010, A014, A017,
      A018, A020, A030, A035, A038, A041, A052, A053, A056, A061, A062,
      A063, A064, A065, A066, A067, A068, A070, A071, A072, A073, A074,
      A075, A076, A077, A078, A108, A113, A116.
     - RETIRED-REPRESENTATION (**12**): A011, A012, A013, A021, A022,
      A024, A027, A031, A042, A105, A106, A107. A011/A021/A105 only check
      optional native fixture-pair construction; A042 only checks four QAction
      pointers; the others stage native band/parameter resolution and traversal.
      Read fork `windowtier_keyboard.cpp` at each named row before retirement.
      Their replacement is the fresh mounted key journey, not a new fixture
      existence assertion. Counter-based no-action clauses and actual retained
      active focus (A010/A014/A018/A066/A077/A108) remain behavior.
     - Not selected, stay PARTIAL (**10**): A047, A048 (prompt text and
      clipboard bytes) and A057 (focus returns to the parameter label
      after prompt Escape) — left for the prompt surface, not assigned to 83 —
      plus A082, A083, A086, A092, A093, A102, A103 (tap-tempo button staging).
   - `selectionkey/proof.coreediting.txt` (**6**, all MATCHED): A013, A033,
     A034, A041, A042, A048.
   - Other selectionkey ledgers (`gesturecommands`, `gesturevelocity`,
     `corearrows`, `localinput*`, `windowtier_lifetime`) are untouched.
2. **Fork laws**, read at `fceecd88:src/checks/selectionkey/`:
   - `windowtier_keyboard.cpp:169-200`: the journey stages a Lanes-scope
     time selection over two CC lanes `{kController, kSecondController}`
     with the volume lane unselected plus a reserved tick-2400 two-note
     pair; `selectionUnchanged()` compares start/end/scope/lanes/tempo and
     an empty note selection.
   - `:244-254`: label Enter/Return activation and its undo index stay
     unchanged while that selection survives (A030/A035/A038).
   - `:291-335`: prompt Escape keeps song bytes and the selection
     (A052/A053/A056); window Copy over label focus keeps it (A061);
     Delete removes both selected lanes' points at the tick, keeps the
     unselected third lane and both notes (A062-A065); Select All selects
     the pair ids and drops the time selection (A067/A068); Paste at the
     committed cursor lands both lanes with exact values 32 and 96, keeps
     the third lane empty and the notes unchanged, and the active parameter
     survives (A070-A076); routed Right then Up move each pair note by one
     snap step resolved by id (A077/A078 context).
   - `:128-168,437-505`: grip arrows, F24 and toggle Enter leave the staged
     pair byte-identical (A011/A017/A020/A105/A113/A116) while native
     traversal/counter guards stage the delivery (A010/A012-A014/A018/
     A106-A108).
   - `coreediting.cpp:120-137`: the staged lane-scoped range's exact
     boundary ticks, scope and empty note selection (A013); `:245-256`: a
     lane-scoped Right nudge moves the point set and translates the
     interval span (A033); `:270-301`: `roll.paste` has a single-key
     binding and lands the copied note clip at the committed cursor tick
     (A034/A041); `:303-327,329-360`: `roll.select_all` has a single-key
     binding and selects primary-track notes from empty and after a ruler
     click (A042/A048).
3. **Current Swift/QML**, verified at the worktree:
   - `src/checks/selectionkey/localinputtier_text.swift:5-9` is the Swift
     owner: `drawerOriginalNumericPromptTransaction` already drives real
     prompts/labels with `page.openPrompt/acceptPrompt`,
     `page.activeParameter` and multi-document peer fixtures
     (`:33-191`); its cppIDs name the windowtier/coreediting surfaces. New
     scenarios extend this entry (private helpers in the same file), so no
     registration file changes.
   - `src/checks/keyboard/KeybindingRegistryChecks.swift:31` runs the
     registry from `src/checks/workspace/SessionChecks.swift:18`;
     `:75-93` pins delivery scopes (`roll.copy` window;
     `roll.paste`/`roll.select_all` editor-routed), `:96-110` pins exact
     stroke sequences (Insert Time Ctrl+Shift+I, pencil B, Delete Time
     unbound), `:112-140` pins `matches`. No predicate yet pins the paste
     or select-all single-key strokes.
   - `AutomationTimeSelection` carries a `.lanes` scope over a
     `Set<AutomationParameter>` with a tempo flag
     (`src/swift/app/drawer/automation/AutomationLaneProjection.swift:214-241`)
     and `PorydawClip` carries `ClipLane`/`ClipLanePoint` payloads
     (`src/swift/app/commands/Clipboard.swift:32-64`), so the two-lane
     scope, copy and paste staging is expressible today.
   - Session publications are observable per domain
     (`src/swift/app/DocumentSession.swift:9-24`: document, selection,
     history, cursor…), matching the fork's counter/emission clauses.
   - `src/checks/editorqml/tst_ShellWindow.qml` owns physical delivery.
     Current reads after task-81 edits locate `test_gMultiNoteArrowSelectionAndHistory`
     at `:1049-1111`, `test_lChromeArrowsAndUnknownKey` at `:1683-1750`,
     and `test_nLabelTimeSelectionCommands` at `:1891-1964`. Reuse the first
     function's real click/Shift-click pair selection in the chrome journeys;
     the old single-note invariants cannot prove both notes survive.

# Exact write set

- `src/checks/selectionkey/localinputtier_text.swift`
- `src/checks/keyboard/KeybindingRegistryChecks.swift`
- `src/checks/editorqml/tst_ShellWindow.qml` — hot; **rebase after 81 lands**
  and after task 83's accepted drawer journey.
- `src/checks/selectionkey/proof.windowtier_keyboard.txt` — the 44 selected
  rows only.
- `src/checks/selectionkey/proof.coreediting.txt` — the 6 selected rows.

No production file, no `tst_ShellDrawerParity.qml` (80 owns now), no
`tst_ShellGridInput.qml` (79 owns now), no rollcheck file (86 owns those
selected rows), no clipboard/automation/voicegroupsave ledger. No CMake,
bridge-registration or fixture changes.

# Prerequisites

The settled sprint-3 §8 split and accepted task 83 precede this task's reuse
of `tst_ShellWindow.qml`; **rebase after 81 lands** first. Consume task 85's
drawer command contract and task 88's selection/clipboard contract before
the final keyboard outcome gate. Existing APIs remain `AutomationPage`,
`AutomationTimeSelection`, `GridClipboard`/`PorydawClip`,
`EditorCommandRouter` (post-81 signature), `PianoGrid.performCommand` and
`KeybindingRegistry.sequences/matches/scope`. Schedule is sprint-3 §9.

# Interface contract

- **Pair outcomes (A017/A020/A065/A067/A068/A075/A078/A113/A116):**
  use a real click/Shift-click two-note selection in the mounted
  chrome tests. Deliver grip arrows, toggle Enter/Return, F24 and routed
  Right/Up with QTest keys to the actual focused item; resolve both note IDs
  and assert exact changed/unchanged fields after each action. The Swift
  lane fixture retains the reserved tick-2400 pair for exact command/history
  outcomes. Never manufacture a no-op by skipping input or calling an
  unrelated session method; do not add a synthetic forwarding API.
- **Selection survival (A030/A038/A052/A053/A056/A061):** stage the
  Lanes-scope selection (two CC lanes, volume unselected, tempo false)
  plus the pair; run label-activation (`openPrompt`/Return), prompt Escape
  and window Copy transactions; after each, assert start/end ticks, scope,
  lane set, tempo flag and empty note selection — each field comparison is
  its own predicate, not one conjunction.
- **Two-lane outcomes (A062/A063/A064/A070-A074):** stage lane points at a
  shared tick on both selected lanes plus one point on the unselected
  volume lane; Delete removes only the two lanes' points; Copy then Paste
  at the committed cursor lands both lanes with exact values 32 and 96 and
  leaves the third lane empty at the paste tick.
- **History/undo clauses (A035):** exact `undoIndex` equality across the
  label activation and prompt Escape transactions (no edit, no new entry).
- **Active parameter (A041/A076):** routed Up moves the id-resolved note by
  exactly one semitone without replacing the selection; the page's
  `activeParameter` survives the Paste command.
- **Binding strokes (coreediting A034/A042/A048):** assert
  `registry.sequences("roll.paste")` and `("roll.select_all")` each resolve
  a single-key stroke equal to the platform standard (Ctrl/Cmd+V,
  Ctrl/Cmd+A) beside the existing scope rows; no stroke table is invented.
- **Coreediting staging (A013/A033/A041):** stage the lane-scoped range via
  `AutomationPage.applyTimeSelection` and assert its exact boundary ticks,
  `.lanes` scope, lane set and empty note selection before the command; a
  lane-scoped Right nudge moves the covered points to the snapped
  destination and translates the interval span by the same delta; keyboard
  Paste lands the roll-copied note clip at the committed cursor tick with
  pitch 60.
- **Window exclusion and focus (A010/A014/A018/A066/A077/A108):** connect
  the existing `copyActivatedSpy` and `soloActivatedSpy` to
  `shellShortcut_roll.copy`/`shellShortcut_roll.solo_tracks`
  (`tst_ShellWindow.qml:448-454`). Physical F24 and grip arrows leave those
  activation counts and the document unchanged. The grip/toggle must show
  active focus before their keys; the label retains active focus across Delete
  and Paste before later arrows. Each clause gets its own message.
- **Retirements (12 rows):** native fixture constructors, QAction pointers and
  native resolver/traversal setup retire only with their exact fork expression
  and fresh mounted replacement journey. Do not retire no-action, focus
  retention or command outcomes as if they were pointer representation.
- One literal message anchor per clause; every existing message in both
  ledgers stays verbatim.

# Implementation steps

1. Extend the existing mounted chrome/label journeys with a real two-note
   selection before the keys. Add the exact Swift lane/survival/history
   predicates before ledger edits; record already-green clauses honestly.
2. Complete registry stroke observations through the existing registry and
   actual mounted Paste/Select All delivery. No second key table or dispatcher.
3. Drive selected range Copy/Delete/Paste and note-arrow outcomes through their
   real router/page/clipboard path. Read all lane values, range fields and both
   note IDs after the command; never treat untouched setup data as a no-op proof.
4. After writers settle, execute both lanes and attach anchors to 38 behavior
   rows; retire 12 native staging rows with their exact fork reason and fresh
   mounted evidence. Leave the 10 unselected windowtier rows unchanged.

# Acceptance predicate

Controller-run on a settled built tree, each invocation at most 180 s:

- `deno task verify --filter swiftcore-projectsession --verbose` — pair
  staging, selection-survival fields, two-lane delete/paste values, undo
  arithmetic, routed-arrow outcomes, active-parameter survival, registry
  strokes and coreediting staging;
  `build/proof-evidence/swiftcore-projectsession.json`.

- `deno task verify:shell --filter shellwindow --verbose` — physical keyboard
  priority, pair-note survival and movement, label/grip/toggle/F24 and actual
  Copy/Delete/Paste/Select All smoke; `build/proof-evidence/shellwindow.json`.

Existing mounted S026, S040–S045, S053–S070, S074–S087, S095–S106 and
S113–S119 are reused only after fresh execution with the completed pair
observations. Registration: `src/checks/workspace/SessionChecks.swift:18,86`,
`src/checks/checkcatalog.cpp:107-125`, `src/checks/editorqml/ShellQmlTests.swift:
60-61`; evidence writer `tools/run_checks.ts:426-434`. All shell lanes may run
together with `deno task verify:shell --verbose` (about 40 s); this filter is
the narrow run. No old evidence substitutes for this task's mounted smoke.

# Task-specific constraints

All **sprint-3 §8 Wave constraints and §9 policy** apply: no new C++; touched
Swift uses Swift 6.4 idioms, no avoidable allocation/copy, comments at most two
lines; base-font sizing with no hard-coded pixels, WCAG AA beats pixel parity.
Keep sole window keyboard authority: no second dispatcher, synthetic forwarding,
focus memory or bare Space capture in chrome. One message-anchored predicate
per behavior clause, existing messages verbatim, real fixtures, no test-only
seams; no `Qt.callLater` coalescing or idempotence guards. Workarounds require
user approval; deferred menus, parked areas and savecore A016–A026 stay out.

Retirement is limited to the 12 named staging rows inside this surface,
each with fork evidence and an executed mounted anchor; no row retires to
make a failing predicate disappear — a genuinely failing behavioral clause
is reported, not retired. If two-lane copy/paste or lanes-scope survival
fails, the production fix belongs to the automation-selection or clipboard
owners (task-85/88 borders): stop and request coordination instead of
expanding this write set. No new checks may name pure wiring or text.

# Controller verification

After fresh evidence, run `deno task proof check --executed`, then
separately:

- `deno task proof sites selectionkey/proof.windowtier_keyboard.txt --status PARTIAL`
- `deno task proof sites selectionkey/proof.windowtier_keyboard.txt --status GAP`
- `deno task proof sites selectionkey/proof.coreediting.txt --status PARTIAL`
- `deno task proof sites --area selectionkey --status PARTIAL`

Expected: 38 selected rows MATCHED with per-clause anchors; the 12 named
rows RETIRED-REPRESENTATION with mounted citations; windowtier_keyboard
keeps exactly its 10 unselected PARTIAL rows; coreediting reaches zero open
rows; gesture/localinput/lifetime ledgers unchanged. No ledger deletion.
