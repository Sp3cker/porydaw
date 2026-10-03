# Context

R16: tab/window cancellation exists in production but is unproven, and ledger rows for the surface carry missing or wrong mappings. The production routes: close-tab mid-gesture (`SongTabs.qml` close button → `SongTabsController.requestClose` → `closeTab` → `DocumentWorkspace.deactivate` → `cancel(reason hidden)`), surface hide (`EditorSurface.onVisibleChanged` → `ApplicationSession.cancelGridInput(2)`), window deactivate (`ShellWindow.onActiveChanged` → `cancelGridInput(3)`), focus loss (`ShellWindow.qml:568-569` → `cancelGridInput(0)`), pointer ungrab (`EditorSurface onCanceled` → `grid.inputCancelled(1)`), and teardown-during-async (`ShellPresenter.beginClose` → `requestCloseAll` walk → `hostClosing` cancel+suspend → `sceneDestroyed` → `acknowledgeGridDetached` → `closeReady`). `DocumentWorkspace.cancel` fans out to rulerMenu.cancelSweep (already proven by R03/task 5 — the pattern to mirror), grid, trackHeaders, voiceChangesPage and drawer. `PianoGrid.inputCancelled` records `lastCancelReason` (0 focusLost, 1 pointerUngrabbed, 2 hidden, 3 windowDeactivated) — the observable evidence anchor. All shell lanes run `windowing=offscreen`; real OS deactivation/ungrab/window-manager close can never fire, so those clauses prove through the same production slots the QML wiring calls, and true-native clauses stay GAP/NATIVE. Read plan.md Global constraints and verification.md.

# Exact write set

- `src/checks/editorqml/tst_ShellTabs.qml`
- `src/checks/editorqml/tst_ShellGridInput.qml`
- `src/checks/swiftrollgated/proof.tabchecks.txt`
- `src/checks/selectionkey/proof.windowtier_lifetime.txt`
- `src/checks/selectionkey/proof.window.txt`

# Prerequisites

None. Existing lanes mount the surface: `shell-tabs` (15 test_* functions; `waitForNative` at line 72 services the native RunLoop — required for every Swift-async observation), `shell-grid-input` (test_escapeCancel, test_ungrabCancel — the established pattern for driving `grid.inputCancelled` directly when QML cannot synthesize the native event), `shellwindow` (close-teardown idiom).

# Interface contract

- No production edits. Cancellation already routes correctly per R03; this task adds executing evidence and repairs mappings. If reading reveals a real defect (e.g. a cancel path that skips `lastCancelReason` or leaves a stuck gesture), STOP and report it as a finding instead of working around it.
- Every new S anchor is a message anchor naming an executed predicate; every row this task closes cites one. Do not extend the tabchecks pattern of `Anchor: function`-only mappings.
- Observable assertions: `grid.lastCancelReason` equals the expected reason code; `noteSummary`/model state is restored after cancel; no document/history write results from cancellation; teardown reaches `acknowledgeGridDetached` and `closeReady`.

# Implementation steps

1. In `tst_ShellTabs.qml`, add a mid-gesture close case: start a band/gesture on a tab's grid, then drive `controller.requestClose` for that tab; assert cancellation (`lastCancelReason == 2` via hidden path through deactivate→cancel), restored model state, and no stuck selection on the surviving tab. Use `waitForNative` for each async settle.
2. Add a hide-mid-gesture case in the shell-grid-input lane (`tst_ShellGridInput.qml` beside test_ungrabCancel): toggle `EditorSurface.visible` to false mid-band (component visibility fires `onVisibleChanged` offscreen; it is not window exposure) and assert `cancelGridInput(2)` effect via `lastCancelReason == 2` + cancelled gesture; then drive the production slots `session.cancelGridInput(3)` and `session.cancelGridInput(0)` for the deactivate and focus-loss causes the offscreen lane cannot synthesize — same contract as the existing ungrab case's direct `inputCancelled(1)` call.
3. Assert teardown ordering in the existing close-walk shape: a close initiated while a gesture is held cancels it before page retirement; `beginClose` veto/dirty-gate behavior is already covered by tests l/m/n — do not re-pin it.
4. Ledger repairs in this commit: in `proof.windowtier_lifetime.txt`, close A045–A048-class rows (close destroys session/page, reopen+reselect) only where the executed mounted case covers the clause; mark truly native-only clauses (real `QApplication.activeWindow`, OS ungrab delivery, window-manager close) as the appropriate NATIVE/RETIRED disposition with a one-line reason rather than leaving them claiming evidence. In `proof.window.txt`, treat A004 (`activeWindow==liveShell`) and A007 (mouse-grab release at teardown) the same way. In `proof.tabchecks.txt`, repair only the cancellation/window rows this task's predicates execute — leave the function-anchor mass and unrelated PARTIALs (A044, A047, A194, A196) for the strict-mappings debt owner; do not mass-edit.

# Acceptance predicate

Each named cancellation cause has an executing predicate observing its distinct effect; closed ledger rows cite message-anchored predicates. Native-impossible clauses carry an honest NATIVE/RETIRED disposition instead of a claim.

Controller-run named checks after the writer freezes:
- `deno task verify:shell --filter shell-tabs --verbose` — mid-gesture close, dirty gates, close walks.
- `deno task verify:shell --filter shell-grid-input --verbose` — hide/deactivate/focus-loss cancel reasons.
- `deno task verify:shell --filter shellwindow --verbose` — close-teardown regression.
- `deno task proof check --executed` and `deno task proof check --strict-mappings`.

# Task-specific constraints

Do not edit `ShellWindow.qml`, `SongTabs.qml`, `EditorSurface.qml`, `SongTabsController.swift`, `ApplicationSession.swift`, `DocumentWorkspace.swift` or `PianoGrid.swift` — the routes exist; missing evidence is the defect. If a route is broken, report the defect instead of patching around it. `mainwindowrouting` lifecycle/native ledgers (Qt MainWindow fixture obligations) are out of scope. Keep the four `windowing=offscreen` limits explicit in ledger reasons.
