# Task 217 brief — the real ShellWindow close keeps clean songs and retires pages before documents

# Context

Ruling (7) of 2026-09-28: build a real ShellWindow close harness in the shell QML lane.
It closes the fork's window-close rows that no Swift check executes. The close path already
exists and is not changed here:

- `ShellWindow.qml` `onClosing` asks `ShellPresenter.beginClose()`. The first close is
  refused while `ApplicationSession.requestCloseAll()` walks every tab and dirty bank
  through the Save/Discard/Cancel gate (`SongTabsController+Close.swift`, plan.md
  "Authorized bank-safety policy").
- `allTabsClosed` then drives `finishClose` → `hostClosing` → scene unload →
  `sceneDestroyed` → `closeReady`. `onCloseReadyChanged` persists session state and
  calls `root.close()` again, and the handshake accepts that close.
- Tab teardown order: `tabWillLeave` parks the workspace, the `SongTab.qml` page's
  `Component.onDestruction` → `pageReleased` → `retire` → `DocumentSession.close()`
  (`ApplicationSession+Tabs.swift`).

Fork oracle (`fceecd88`):

- `MainWindow::closeEvent` (`src/mainwindow.cpp:1361-1400`): with no pending save work
  it accepts at once. Otherwise it ignores the event and runs `promptSaveAll`, and a
  Cancel keeps the window open.
- `tst_hostintegration.cpp:665-703` `projectSwitchAndClosePreserveProjectBoundaries`:
  project fingerprint, re-open the same project, reopen both songs, close, and bytes
  are unchanged.
- `:708-733` `songTabTeardownDestroysQuickWindowBeforeDocument`: the quick window is
  destroyed before the document, and there are exactly two notifications.
- `tst_mainwindowrouting_lifecycle.cpp:347-391` `projectSwitchAndQuitPreserveState`:
  the close is accepted, then `window.close()` waits (30 s) for the accepted close.

Deliberate structural difference: the fork accepts a clean close synchronously. Swift
always refuses the first `closing` event and accepts the close after the walk
(`ShellPresenter.swift:410-447`). The fork's "accepted" is proven as the outcome: with
no prompt and no cancellation, the window hides.

Surface: the application window close (title-bar close, File → Quit through
`onQuitRequested → root.close()`, and a programmatic `Window.close()` all enter the same
`onClosing`). Inventory PJ06 (dirty close/save/discard/cancel).
Ledger spec: `src/checks/host/proof.tst_hostintegration.txt` (A162, A174, A176, A177,
A183–A185) and `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt`
(A106–A108).
Verify lane: `deno task checks:shell --filter shell-tabs-window-close --verbose`, new
entry.
No production or UI change, so there is no visual contract.

# Exact write set

Checks:

- `src/checks/editorqml/tst_ShellTabsWindowClose.qml` (new, extends `ShellTabsSupport`):
  three test functions (Interface contract).
- `src/checks/editorqml/TabsDrawerProbe.swift`: three public methods and one private
  weak stored property (Interface contract). No other edit. **Shared-risk file**: it is
  also consumed by `tst_ShellWindow`, `tst_ShellSongs`, `ShellTabsSupport` and
  `ShellVoicegroupSupport`. If another in-flight task edits it, serialize.
- `src/checks/editorqml/ShellQmlEntries.swift` (**registration file, shared hot
  file**): add one `Entry(name: "shell-tabs-window-close", inputFileName:
  "tst_ShellTabsWindowClose.qml", fixtureFiles: songs("mus_route101",
  "mus_littleroot_test"))` directly after the `shell-tabs-reload` entry. The default
  windowing is offscreen and there are no `testFunctions`.

No edit to `src/checks/CMakeLists.txt`. `shell_qml_tests` reads inputs from
`EditorQmlPaths.testDirectory`, and `tst_ShellWindow.qml`, `tst_ShellTabs.qml` and
`tst_ShellSongs.qml` already run unlisted.
No edit to `ShellQmlTests.swift`: `TabsDrawerProbe` is already registered at :72.

Ledgers (implementer-owned, same commit as the checks):

- `src/checks/host/proof.tst_hostintegration.txt`: A162, A174, A176, A177 and
  A183–A185; append S068–S074; add one header line.
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt`: A106–A108;
  append S338–S339; add one header line. **Shared with task 216** (A025 + S335–S337), so
  217 edits it only after 216 lands.

No production files. `ShellWindow.qml`, `ShellPresenter.swift`,
`ApplicationSession+Close.swift`, `ApplicationSession+Tabs.swift` and
`SongTabsController*.swift` are read-only.

# Prerequisites

Task 216 is committed. Its lifecycle-ledger edit (S335–S337, now in the working tree)
must land before this task writes that file. No interface is consumed from 216.
Consumed as-is: the `ShellTabsSupport` helpers `openShell`, `waitForPage`, `tabs`,
`session`, `pages`, `drawNote`, `dialogButton`, `awaitGateButtons` and `cleanup`; the
pinned fixture fingerprints from `tst_ShellWindow.qml:157-160`; and the
`watchPageRemoval` repeater lookup shape from `tst_ShellTabsReload.qml:611-631`.

# Interface contract

`TabsDrawerProbe` (check-side, read-only on production state; precedent:
`liveLaneCosmetics`):

- `projectTreeFingerprint(root: String) -> String`: every regular file under `root`,
  recursively, except the top-level `settings.plist`. That file is the harness
  preference store staged by `ShellQmlTests.swift:60`, not project data. Paths are
  root-relative and sorted. The FNV-1a hash (the same constants as `fileFingerprint`)
  covers each relative path's UTF-8 and then the file's bytes. The result is
  `"<fileCount>:<hex>"`. Returns `""` when any file is unreadable or no file exists
  (fork `directoryFingerprint` returns empty on an unreadable file).
- `watchSelectedDocument() -> Bool`: stores a **weak** reference to
  `(qmlChildren ShellPresenter).session.selectedDocument` in a private
  `weak var watchedDocument: DocumentSession?`. Returns whether one was captured.
- `watchedDocumentReleased() -> Bool`: `watchedDocument.map(\.isClosed) ?? true`. A
  deallocated document counts as released.

`tst_ShellTabsWindowClose.qml` (`ShellTabsSupport { … }`). It declares
`SignalSpy { id: projectReadySpy; signalName: "projectRootChanged" }`. Every mapped
message below is an exact literal and unique in the tree:

1. `test_aProjectSwitchThenWindowCloseKeepsSongBytes` (host
   `projectSwitchAndClosePreserveProjectBoundaries` + lifecycle
   `projectSwitchAndQuitPreserveState`):
   - Unmapped start guards, as in test_x: the route101 and littleroot song paths
     (`fileProbe.songPath`) equal `"471:d31e7c4a0a32a53f"` / `"425:c27d69bdefcd9207"`.
   - `openShell(["mus_route101", "mus_littleroot_test"])`.
   - `tree = fileProbe.projectTreeFingerprint(bootstrap.projectRoot)`, then
     `verify(tree.length > 0, "A162 the staged project tree fingerprints before the switch-and-close journey")`.
   - Project switch: set `projectReadySpy.target = session()` and call
     `session().openProject(bootstrap.projectRoot)` (the fork calls
     `requestProjectOpenAt` directly). Wait natively for
     `projectReadySpy.count === 1 && projectOpen && tabCount === 0 && lastSaveError === ""`.
   - Reopen `mus_route101`, then `mus_littleroot_test` (`openSong`). Wait for tabCount 1
     then 2, and `waitForPage` each new `selectedId`.
   - Verify the unmapped clean precondition `!session().documentDirty`.
   - Before closing, connect `findChild(shell, "songTabCloseDialog").visibleChanged` to
     latch `promptShown`, and connect `session().closeCancelled` to count `cancelled`.
   - Call `shell.close()`.
   - `verify(waitForNative(function() { return shell.shellPresenter.closeReady && !shell.visible }, 30000), "A108 the real window close completes and hides the window within 30 s")`.
   - `verify(!promptShown && cancelled === 0 && !shell.visible, "A174/A106 the clean two-song window close is accepted with no prompt and no cancellation")`.
   - `compare(fileFingerprint(route101), "471:d31e7c4a0a32a53f", "A176 the window close preserves the first song's pinned MIDI bytes")`.
   - `compare(fileFingerprint(littleroot), "425:c27d69bdefcd9207", "A177 the window close preserves the second song's pinned MIDI bytes")`.
   - Unmapped (verification.md filesystem-diff journey rule):
     `compare(projectTreeFingerprint(root), tree, "the switch-and-close journey leaves every staged project file unchanged")`.
   - Disconnect both handlers and clear the spy target.
2. `test_bDirtyWindowCloseCancelKeepsWindowOpen` (fork `closeEvent` ignore + Cancel,
   `mainwindow.cpp:1386-1400`; no ledger row; this is the real prompt through the window
   close):
   - `openShell(["mus_route101"])`, capture the song fingerprint, then `drawNote(id)`.
     Verify the unmapped guard `session().documentDirty`.
   - `shell.close()`. Wait for `tabs().pendingCloseId === id` and verify
     `awaitGateButtons()` with the message "the dirty window close raises the tab's
     Save/Discard/Cancel prompt".
   - Real `mouseClick` on `songTabCancel`. Wait for `cancelled === 1`, then verify
     `shell.visible && sceneActive && !closeReady && tabCount === 1 && documentDirty`
     with "Cancel keeps the window and its dirty tab open". Compare the fingerprint
     unchanged with "Cancel wrote no song bytes".
   - `shell.close()` again. The prompt returns. `mouseClick` on `songTabDiscard`, then
     wait for `closeReady && !shell.visible` with "Discard lets the window close and
     hide". Compare the fingerprint unchanged with "Discard wrote no song bytes".
3. `test_cWindowCloseRetiresPageBeforeDocument` (host
   `songTabTeardownDestroysQuickWindowBeforeDocument`):
   - Call `openShell(["mus_route101", "mus_littleroot_test"])` and remember
     `active = tabs().selectedId`.
   - `fileProbe.children.push(shell.shellPresenter)`. Verify the unmapped guards
     `fileProbe.watchSelectedDocument()` and `!fileProbe.watchedDocumentReleased()`.
   - Find the page repeater under `pages()` (the child exposing `itemRemoved`).
     `order = []`. The handler acts only for item `objectName === "songTab_" + active`.
     If `watchedDocumentReleased()` is already true and `"document"` is absent, it
     pushes `"document"` first. Then it pushes `"page"`.
   - `shell.close()`. Wait natively for `closeReady && !shell.visible` (unmapped: "the
     teardown journey's window close completes"). Then wait for
     `watchedDocumentReleased()`, push `"document"` if absent, and disconnect.
   - `compare(order[0], "page", "A183 the closing tab's page leaves the scene before its document is released")`.
   - `compare(order[1], "document", "A184 the closing tab's document is released after its page")`.
   - `compare(order.length, 2, "A185 the page-then-document teardown reports exactly two events")`.

Row mapping (host: S068–S074; lifecycle: S338–S339). Each S entry is a header plus one
`Anchor:` line:

| Row | Class | Disposition → | S entry (function; anchor message) |
|---|---|---|---|
| host A162 | behavior (fixture readable) | MATCHED | S068 test_a; "A162 …" |
| host A174 | behavior (close accepted) | MATCHED | S069 test_a; "A174/A106 …" |
| host A176 | behavior | MATCHED | S070 test_a; "A176 …" |
| host A177 | behavior | MATCHED | S071 test_a; "A177 …" |
| host A183 | behavior (teardown order) | MATCHED | S072 test_c; "A183 …" |
| host A184 | behavior | MATCHED | S073 test_c; "A184 …" |
| host A185 | behavior | MATCHED | S074 test_c; "A185 …" |
| lifecycle A106 | behavior (close accepted) | MATCHED | S338 test_a; "A174/A106 …" |
| lifecycle A107 | representation | RETIRED-REPRESENTATION | reason below, cites S338/S339 |
| lifecycle A108 | behavior (async close wait) | MATCHED | S339 test_a; "A108 …" |

A107 reason: `Mapping/reason: MainWindow::m_closeAccepted is the fork's private close
re-entry flag (host A175 retired the same flag); the Swift close outcome is the hidden
window after an unprompted, uncancelled walk. [S338][S339]`

Header lines:

- Host: add `Additional QML counterpart: src/checks/editorqml/tst_ShellTabsWindowClose.qml`
  after the `tst_ShellTabsClose.qml` line.
- Lifecycle: add `Additional Swift counterpart: src/checks/editorqml/tst_ShellTabsWindowClose.qml`
  after the `tst_ShellTabs.qml` line.

# Implementation steps

1. `TabsDrawerProbe`: add the three methods and the weak property. Use `FileManager`
   enumeration of regular files and skip symlinks. Nothing is cached.
2. `tst_ShellTabsWindowClose.qml`: add the three tests exactly as contracted. Waits on
   Swift transitions use `waitForNative` (verification.md), and Qt `tryVerify` is used
   only for pure-QML state.
3. `ShellQmlEntries.swift`: add the entry.
4. Run the lane (Acceptance). Every mapped message must pass. If one fails, stop and
   report (see Task-specific constraints).
5. Ledgers:
   - Append S068–S074 after S067 and S338–S339 after S337 with a direct text edit
     (`proof:edit` cannot create entries). Use the form `S068 |
     test_aProjectSwitchThenWindowCloseKeepsSongBytes |
     src/checks/editorqml/tst_ShellTabsWindowClose.qml` + `Anchor: message "<literal>"`.
   - Rewrite each claimed A row to compact form with `deno task proof:edit <ledger> A###
     --before '<Disposition…Original expression block>' --after '<compact block>'
     --apply`. MATCHED rows carry `Mapping: S0xx`. A107 carries the reason above.
   - Add the header lines with `proof:edit <ledger> header`.
   - Code, checks and ledgers go in one commit.

# Acceptance predicate

The real window close:

- hides a clean two-song window after a project switch and reopen, with no prompt and
  no cancel, and leaves both songs' pinned bytes and the whole staged project tree
  unchanged;
- raises the real Save/Discard/Cancel prompt for a dirty tab, where Cancel keeps the
  window open and Discard closes it, writing no bytes;
- removes the closing tab's page before its document is released, in exactly two
  events.

```sh
deno task checks:shell --filter shell-tabs-window-close --verbose
deno task proof check --executed
deno task proof check --strict-mappings
deno task proof show src/checks/host/proof.tst_hostintegration.txt A183
deno task proof show src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt A107
```

- The lane runs all three tests on the production `ShellWindow`, `ShellPresenter`,
  `ApplicationSession` and `SongTabsController`, offscreen.
  `build/debug/proof-evidence/shell-tabs-window-close.json` must carry every mapped
  message.
- `proof check --executed`: 0 errors, and no `not executed` line for host S068–S074 or
  lifecycle S338–S339.
- `--strict-mappings` must not list any site this task edits. Both ledgers stay open,
  so the command's exit status is not the criterion.
- Coverage gaps, named:
  - Offscreen QPA only: no native title-bar or Cmd-Q delivery (standing native-boundary
    exclusion). `shell.close()` enters the same `onClosing` handler.
  - Post-close preference persistence (lifecycle A110, host A179) stays with the
    project-store exclusion.
  - The Save answer through the window close is already proven for banks
    (`tst_ShellTabsBankLifetime` `test_m`) and is not re-pinned.

Untouched rows:

- Host: A004 (PARTIAL, fixture-parity residue), A087/A091 (PARTIAL, WindowDeactivate
  user exclusion), and every closed row including A175/A178/A179 (already retired).
  The host ledger stays open.
- Lifecycle: A025 (task 216); A042, A055, A072, A080, A082, A085, A086, A088, A089,
  A094, A095, A098, A099, A102, A103, A109, A110 (GAP, `swift-project-store`
  exclusion); A105 (PARTIAL). The lifecycle ledger stays open.

# Task-specific constraints

- Real ingress only: `shell.close()` and real `mouseClick` on the mounted gate buttons.
  Never call `beginClose()`, `requestCloseAll()`, `confirmDiscard()` or
  `cancelClose()` directly in these tests.
- No new production property. The probe reads only existing public state
  (`selectedDocument`, `isClosed`, files). No test-only read and no
  `!("prop" in obj)` refusal.
- Independent literals: the pinned fingerprints, not values read back from the app.
  The tree fingerprint compares against its own pre-journey capture, and that is the
  only self-referential comparison.
- Stop and report without weakening a clause or editing production if:
  - `shell.visible` stays true after `closeReady`;
  - the page-then-document order fails;
  - the tree fingerprint changes on a clean close. Name the written file; it could be a
    real data-safety defect.
- Do not edit existing tests or support files. Swift 6.4 and main-actor isolation as in
  the sibling probe methods. Comments ≤2 lines. Workarounds or architectural changes:
  stop and report.
