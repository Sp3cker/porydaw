# Task 113 brief — real chrome keys and pitch-bend focus keep one command authority

# Context

Complete real ShellWindow key delivery from drawer chrome and parameter labels, then pitch-bend repeat/focus/Undo ownership. Consume 107's production insertion API, 106's local numeric ownership and 110's settled shell save/Undo authority. This task closes remaining modal conjuncts without a second dispatcher.

Verified planning selection: **35 open rows (12 GAP + 23 PARTIAL)**. Counts are the in-flight snapshot, not a post-106 completion claim.

- `src/checks/selectionkey/proof.windowtier_keyboard.txt` — A013, A024, A027, A031, A047, A048, A057, A082, A083, A086, A092, A093, A102, A103, A107.
- `src/checks/selectionkey/proof.localinputtier_pitchbend.txt` — A009, A010, A011, A014, A015, A038, A039.
- `src/checks/pitchbend/proof.curve.txt` — A026.
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_input.txt` — A020, A035, A036, A037, A038, A039, A040, A041, A043, A045, A047, A049.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `c17d966fbf56b1cccb2c1112b7eef84bec1dc7ac`, `a1244957bb05a59d62b8912e053d49b2a6f3d771`, `4ae6619dda9405bf0a3352e4171d9da54ef04f1f`, `5f768e3401d74d5df185a6de5692595351156a9d`. Read each selected original expression through `deno task proof sites` / `show`; the original C++ check paths are absent and must not be recreated.

# Exact write set

- `src/swift/app/commands/EditKeyArbiter.swift`
- `src/swift/app/EditorCommandRouter.swift`
- `src/swift/app/shell/ShellPresenter.swift`
- `src/swift/app/pitchbend/PitchBendPresenter.swift`
- `src/ui/shell/ShellWindow.qml`
- `src/ui/songview/quick/drawer/EditorDrawer.qml`
- `src/ui/songview/quick/PitchBendPopup.qml`
- `src/checks/selectionkey/localinputtier_text.swift`
- `src/checks/rollcheck/pitch_bend.swift`
- `src/checks/workspace/session_edit_routing.swift`
- `src/checks/editorqml/tst_ShellWindow.qml`
- `src/checks/editorqml/tst_ShellPitchBend.qml`
- `src/checks/selectionkey/proof.windowtier_keyboard.txt`
- `src/checks/selectionkey/proof.localinputtier_pitchbend.txt`
- `src/checks/pitchbend/proof.curve.txt`
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_input.txt`

Closed list: production files are conditional repairs only within the interface below; correct owners remain unchanged. Selected ledger rows change with their proving surface, not in a standalone reconciliation.

# Prerequisites

All 99–106 and Group A's checkpoint precede this task. Rebase arbiter/router and shell production over 99/106/110; EditorDrawer over 101/107; localinputtier_text and shellwindow checks over 106/107. Consume openInsertionPrompt(tick:value:) from 107 without writing AutomationPage/AutomationModal. Group B 111 owns AutomationPage.qml; 112 owns PianoGrid/NoteCommands.

# Interface contract

- Keep `EditKeyArbiter.decide`, `EditorCommandRouter.route` and `ShellPresenter.routeEditorKey(key:modifiers:autoRepeat:)` as the single command path. Drawer chrome focus must not steal the registered window commands: A (automation), V (velocity), P (voice changes), Ctrl+Shift+P (polyphony). Deliver those actual sequences from the focused velocity toggle and observe all four drawer sections before/after; input A036–A041/A043/A045/A047/A049 remain real behavior. Input A020/A035 are deleted fixture/toggle-pointer prerequisites only.
- Use actual Tab traversal, not forceActiveFocus, to reach the automation grip and automation toggle (keyboard A013/A107). Parameter labels must be the exact controller 10, controller 1 and Volume/controller 7 identities, with their own focus observations (A024/A027/A031). Preserve the selected controller-lane identities across shared commands.
- Consume 107's insertion API for Volume initial draft `48`, observe exact selected text, and prove actual clipboard `48` by Paste (A047/A048); close/refocus the Volume lane (A057). Preserve real automation-band focus and enabled parameters, unchanged history index/count on Return, and unchanged history count/selection on Space (A083/A086/A092/A093/A102/A103). Retire only A082's reserved-tick insertion fixture guard.
- Pitch-bend A009 must inspect the actual primary track, selected NoteID set and inactive time selection in Swift as well as the mounted opener. A010/A011/A038/A039 retain actual roll focus before/after the popup and the resumed Right edit; retire only obsolete native band-request/QGuiApplication pointer identity, not focus behavior.
- For A014/A015 feed `autoRepeat: true` through the existing production routeEditorKey API with the real popup already open after a mounted G. Assert consumed repeat, unchanged popup identity, no second opener transaction and exactly one initial opening. This is explicit production event-metadata coverage paired with mounted original key delivery, not a claim QML TestCase.keyPress fabricated an OS autorepeat event. Do not add an injection/probe API.
- Curve A026 needs the exact serialized full-song bytes restored by standard Undo. Pair a Swift check through the canonical Undo command boundary, on the same curve transaction/fixture, with actual window Undo delivered to the mounted popup and its restored curve/revision. The mapping names both executing predicates; direct document.undo alone, a saved-file fingerprint or adjacent modal tests do not close it.

# Implementation steps

1. Extend the existing shellwindow chrome/parameter-label journeys with actual Tab traversal, exact CC10/CC1/Volume identities, production insertion draft 48, clipboard Paste and complete Return/Space no-write clauses.
2. Extend the registered Swift localinputtier_text/pitch_bend/session_edit_routing checks for the exact selection, repeat decision and full-byte canonical Undo outcomes; pair these with the actual popup key/focus journeys in tst_ShellPitchBend.
3. Repair only demonstrated routing/focus/tab-chain divergence in the declared owners. No new automation producer, roll producer, event-injection seam or shortcut authority is permitted.
4. Close the three complete keyboard/pitch-bend ledgers and only the twelve selected mainwindow input rows. Preserve all 99 routing mappings and deferred menu rows.

# Acceptance predicate

SessionChecks registers the numeric/roll/edit-routing predicates; shellwindow executes real chrome/label commands and shell-pitch-bend executes modal key/focus/Undo. Explicit repeat-metadata coverage and exact-byte Undo coverage must accompany, not be inferred from, the mounted journeys. Three complete ledgers close; the mainwindow input inventory remains.

Under sprint-3 §12's controller-owned settled-group verification policy, the narrow commands are:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-pitch-bend --verbose
```

The §12 full-shell, full-verify and executed-proof gate also applies; these narrow runs are not a replacement.

# Task-specific constraints

Read sprint-3 §10–§12, including §12 “Evidence and execution contract,” as part of this brief. No AutomationPage/AutomationModal/AutomationPage.qml, PianoGrid, NoteCommands or registration writes. Use 107's production API and existing routeEditorKey metadata; no test-only byte getter, fake popup, synthetic focus surrogate or second key dispatcher.
