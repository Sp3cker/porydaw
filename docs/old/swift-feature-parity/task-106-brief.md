# Task 106 brief — numeric and Event List local keys do not escape

# Context

Complete local input ownership through real numeric prompts and Event List keys, then return shared commands to the correct mounted band. Existing model transactions are not substitutes for typed digits, actual Copy, focus return or resumed Solo.

Verified selection: **43 open rows (nine GAP + 34 PARTIAL)**:

- `src/checks/selectionkey/proof.localinputtier_text.txt` — all 27 PARTIAL. This scoped ledger uses **Original line labels**, not A-identifiers: Original 272, 332, 345, 357, 359, 361, 380, 385, 390, 397, 399, 402, 405, 416, 432, 448, 451, 465, 467, 469, 472, 473, 479, 574, 576, 579, 582. Preserve those identities.
- `src/checks/selectionkey/proof.localinput.txt` — all seven GAP: A001, A002, A003, A005, A006, A008, A009.
- `src/checks/selectionkey/proof.localinputtier_eventlist.txt` — all four: GAP A018/A019; PARTIAL A013/A025.
- `src/checks/drawerpresentation/proof.valueprompt.txt` — all five PARTIAL: A014, A015, A020, A066, A069.

Fork `fceecd88`; matching originals respectively `f3069ef693542bdb63564b80a29773e2f5b2a360`, `996c6446f2cbfaa5b88ed721df4fa831129bd7bc`, `8d10130da34cfa9e1912d22fb11cdd427173e0b2`, `c17d966fbf56b1cccb2c1112b7eef84bec1dc7ac`. All four original C++ paths are absent. The text ledger is scoped to numericPromptOwnsKeys/velocityPromptOwnsKeys; closure deletes that scoped inventory, not a claim that every historical text-surface method was ported.

# Exact write set

- `src/swift/app/commands/EditKeyArbiter.swift` — conditional local Event List command ownership repair.
- `src/swift/app/eventlist/EventListEditing.swift` — conditional real reorder/delete repair.
- `src/swift/app/eventlist/EventListSelection.swift` — conditional row-selection ownership repair.
- `src/ui/shell/ShellWindow.qml` — conditional sole window-shortcut authority/focus ownership repair.
- `src/ui/songview/quick/DragInput.qml` — conditional actual numeric field handling repair.
- `src/ui/songview/quick/VelocityPrompt.qml` — conditional prompt focus lifecycle repair.
- `src/ui/songview/quick/drawer/AutomationPrompt.qml` — conditional prompt focus lifecycle repair.
- `src/ui/songview/quick/EventListPage.qml` — conditional local row-key input repair.
- `src/checks/selectionkey/localinputtier_text.swift`
- `src/checks/eventviews/EventListPageChecks.swift`
- `src/checks/editorqml/tst_ShellWindow.qml`
- `src/checks/editorqml/tst_ShellEventList.qml`
- The four selected proof ledgers above — delete each after full scoped closure.

No AutomationPage/AutomationInteraction, `tst_EditorDrawer.qml`, roll producer, ApplicationSession, ShellTabs, fixture-content or registration writes. Those producer owners belong to other Group B tasks. No new QML test probe or public document-byte/count property is authorized.

# Prerequisites

All 91–98 and Group A's checkpoint precede this task. Rebase localinputtier_text over 95/97, the shell sources/check over 91/95 and then 99. Preserve 99's fresh-tab command targeting, 95's focus-target retirement and 97's key/gesture boundaries. Consume Group A 100's stable automation selection tool behavior without editing its producer; Group B 104 owns automation pointer/pencil behavior and its QML page.

# Interface contract

- Keep the actual window shortcut as sole shared-command authority. `EditKeyArbiter.decide` (`EditKeyArbiter.swift:63–125`) retains pointer-gesture precedence, origin rules, Event List Select All/Delete ownership and repeat/availability behavior. Local text consumes its own letters, arrows and text Copy; Space still belongs to transport. Do not install a second shared-command dispatcher on an item.
- Open an automation **insertion** prompt via its real empty-space/menu ingress, not `openPrompt` invoked by a new QML test seam. For Tempo use the exact 140 selected draft and focused field; for the CC insertion route prove focus ingress and return after close. A written-node prompt alone does not close valueprompt A014/A015/A020/A066/A069.
- Type actual digits to obtain exactly `12`, select all and Copy, then use real text paste to observe exactly `12` from the system clipboard. The song clipboard and window Copy activation remain untouched. Up/Down leave the prompt open, selected NoteIDs unchanged and song unedited. S follows the numeric validator's actual text contract and never changes Solo; cancel retains exact song bytes/history. Pair mounted key delivery/unchanged revision+selection with exact Swift transaction bytes at the same semantic boundary, not a saved-file fingerprint or note-only summary as a whole-song oracle.
- Real right-click on a visible selected note opens the note menu; click its Set Velocity row to open the production prompt. Repeat the local-key/no-write contract, cancel, then deliver S to the refocused roll. After both automation and velocity prompts, exactly one window Solo activation toggles the intended track on, and the second toggles it off. Verify the production Qt window is active for the resumed-key journey (localinput A002); the offscreen result is Qt activation evidence, not physical desktop or OS-native menu evidence.
- Event List Alt+Up preserves both visible-row count and the independently counted entire document raw-event population; Delete removes exactly two chosen raw events, with the unrelated selected note unchanged. Use the existing EventList presenter transaction in Swift for the document-wide population and the mounted page for real key delivery. Do not infer whole-document counts from a filtered table.
- Retire text Original 272/416 (native registry prerequisites), 432/448/451 (native fixture surface/coordinate prerequisites), 467/469/472 (native menu model/panel/lookup prerequisites); localinput A001/A003/A005/A006/A008 (native fixture/action observation/grab teardown guards); Event List A018/A019 (reserved-note fixture prerequisites). Exactly **15 representation rows** accompany **28 behavior rows**. Real menu activation, focus, active window, no mutation and resumed commands remain behavior; no setup-only assertions are added to obtain anchors.

# Implementation steps

1. Extend `drawerOriginalNumericPromptTransaction` (`localinputtier_text.swift:6–83`) for exact full-byte/history/selection consequences, retaining the existing original CC10 and velocity fixtures and task-95 lifetime coverage. Add the raw population conjuncts to the existing registered EventListPage checks.
2. Extend `test_cWindowShortcutsAndNumericOwnership` and the label/prompt journey in `tst_ShellWindow.qml` (current entry :592), plus `test_keyboardSelectionStaysOnMountedEventRows` (`tst_ShellEventList.qml:56,143–198`). Drive real menu clicks, digits, Copy/Paste, arrows, Escape and resumed S; use unique literal messages for the missing clauses. Remove touched fake text-owner stand-ins rather than mapping them as production prompt proof.
3. If a selected ownership/focus defect is demonstrated, repair its actual declared owner. `AutomationPrompt.qml:39–58,109–139` and `VelocityPrompt.qml:21–37,78–109,131–147` show the current boundaries. Do not extend their existing delayed focus or `finishing` guards; any changed flow must use deterministic ownership/lifecycle rather than another `Qt.callLater` or idempotence guard. RED may be absent.
4. Refresh selected execution anchors, account for the 15 specified representation rows and delete all four fully closed scoped ledgers. Do not move other local/window/host/menu rows or reopen parked sample/onboarding surfaces.

# Acceptance predicate

`SessionChecks.swift:86` registers the numeric transaction and existing Event List page checks remain in swiftcore-projectsession; `ShellQmlTests.swift:60–61,93–94` registers the mounted shellwindow and shell-event-list lanes. Both native-key ownership and exact independent domain state predicates must execute.

On the settled task/group tree the controller runs every command below, serialized. Implementers do not run them while siblings edit. Apply §11 checkpoint/review policy and deduplicate full sweeps at the accepted group boundary, not omit them.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-event-list --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

All commands must finish within 180 seconds after lock acquisition (the wrapper alarms at 175). Fresh execution must classify selected behavioral anchors in `swiftcore-projectsession.json`, `shellwindow.json` and `shell-event-list.json`; execute every data row, DPR/palette variant and mounted interaction used to close a row. Full shell and full verify pass, selected rows have no GAP/PARTIAL/NATIVE residue, and executed proof validation resolves all retained anchors. Preserve existing literal messages and add unique complete literals, never interpolated phase anchors. Capture before/after structure, real-surface smoke, source/evidence pins and the task review gate; never invent RED or execution.

# Task-specific constraints

Read sprint-3 §10 “Wave constraints and verification” and §11 “Inherited constraints and verification” as mandatory parts of this brief. They cover unique literal anchors, fixture-consumer boundaries, CFPreferences staging, honest absent RED, Swift 6.4/no new C++, two-line comments, base-font geometry, WCAG AA, keyboard priority, no `Qt.callLater`/idempotence guards/test seams, and approval before workarounds. All §11 exclusions remain unchanged.
No additional host claim is authorized. If the actual mounted Qt activation or insertion ingress cannot be observed without a new test seam, stop at the task gate with the exact missing public behavior; never replace it with forced test-item focus or retire the behavior. Native menus and their deferred rows remain out of scope.
