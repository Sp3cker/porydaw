# Task 216 brief — a pending reload never drops the tab's view state

**Released** under the user's 2026-09-28 ruling (3): pending-reload A025 retires as
RETIRED-REPRESENTATION under the atomic-reload ruling, with task 176's refusal-predicate
pattern (sprint-3.md status header, lines 79–80).

# Context

Fork `MainWindowRoutingLifecycleTest::readyReloadPreservesTransients`
(`git show fceecd88:src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp`,
lines 61–137) sets up a non-default view on the reopened tab. The seeded members are
pixels per beat ×2, key height ×1.5, both scrolls, an alternate used track, the edit
cursor, the musical-16 grid, triplet feel, and the Event List. The test then calls
`requestSongOpen` and polls the staged `SongTab` at every not-ready event:
`stateDropped |= !sameViewState(view, seeded)`. A025 is its `QVERIFY(!stateDropped)`
(`:133`). The fork's staged binding rebuilt the tab in place, so its intermediate
not-ready states could expose a dropped view.

Swift reloads atomically (`SongTabsController.closeTab` → `ApplicationSession.reloadApproved`
→ `openTab(restoring: ReloadedTab)`). The original `SongTabSession` and its
`DocumentSession` stay live and selectable until `finishReload` swaps in a replacement
built from the `ReloadedTab` capture (`ApplicationSession+Tabs.swift:176-223, 259-261`).
The fork's staged state is therefore unreachable, and ruling (3) retires the row. What
retirement still owes is task 176's shape: an executing refusal predicate. Every
event-loop observation during the pending window must refuse a dropped view member, and
the landed replacement must carry every seeded member. Existing coverage stops short:
- S258/S260 (QML) cover retention of selection and presentation.
- S223–S231 cover members after the reload.
- `runTabReadinessChecks` A063/A065 (`session_view_state.swift`) poll only
  `editorViewState` and the timeline.
- Task 176's S322 polls MIDI, bank and selection.

None polls camera, track, cursor, grid or Event List per event.

Surface: in-place song reload of the selected tab, the path `openSong` on an open,
clean tab drives. It is the same surface as task 176.
Ledger spec: `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt`
A025 (1 PARTIAL → RETIRED-REPRESENTATION).
Verify lane: `swiftcore-projectsession` (catalog `swiftSuite("swiftcore-projectsession",
"projectSession")`, `checkcatalog.cpp:127`, macOS). The execution path is
`runProjectSessionSuite` (`SessionChecks.swift:46`) → `sessionOpenAndRecovery`
(`session_io.swift:325`) → the new scenario. Evidence is written to
`build/debug/proof-evidence/swiftcore-projectsession.json`.
Blocked rows left untouched (lifecycle):
- A004, A010, A031, A043–A045, A056–A059, A073–A075, A083, A087, A090, A096, A097,
  A100, A101, A104 and A105 stay PARTIAL. They are project-store or sidecar
  (`porydawSnapshot`) conjuncts and deleted-Qt-session residuals.
- A042, A055, A072 and A082 stay GAP (fixture guards).
- A080, A085, A086, A088, A089, A094, A095, A098, A099, A102 and A103 stay GAP
  (project-store: view-state store, failed switch, sidecars, reopen readiness), and so
  do A109–A110 (project-store: sidecar bytes, view-state settings).
- A106–A108 stay GAP (window-close harness, owned by the shell-lane close-harness task).

# Exact write set

- `src/checks/workspace/session_io.swift`:
  - Add one `@MainActor private func sessionReloadRetainsViewState(report: CheckReport, projectDir: String)`
    directly after `sessionReloadAtomicBinding`.
  - Add one call line directly after `sessionReloadAtomicBinding(report:projectDir:)`
    in `sessionOpenAndRecovery`.
  - The scenario joins its sibling reload refusal. It is cohesive with the file, so
    there is no new fragment, CMake edit or `SessionChecks.swift` edit.
  - **Shared-risk file**: if another in-flight task edits `session_io.swift`, serialize.
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt`: A025
  only, plus appended S335–S337. **Shared with the close-harness task** (lifecycle
  A106–A108), so serialize: one ledger writer at a time, and the later writer takes the
  next free S IDs.

No production file changes. `ApplicationSession+Tabs.swift` and
`SongTabsController*.swift` are read-only.

# Prerequisites

Task 176 is landed (`78af02d8`). Its scenario, `sessionReloadAtomicBinding`, and
S320–S324 are consumed unchanged, and so is the reload restore path. Read sprint-3 §21
and §29, `session_io.swift:141-261`, and `session_view_state.swift:448-548`, which
shows the seeding API precedent.

# Interface contract

cppID: `mainwindowrouting/MainWindowRoutingLifecycleTest::readyReloadPreservesTransients`.

Harness shape: follow `sessionReloadAtomicBinding`.
- Stage an own project with `stageTestProject(in:
  <parent of projectDir>, projectName: "swiftcore-reload-view-state")`.
- Construct `ApplicationSession()` and call `configurePersistence()`.
- In a `defer`, call `hostClosing()` and `acknowledgeGridDetached()`.
- Use a nested run-loop `until` helper with the same 25 s deadline and 10 ms turns.

Fixture delta:
- Before opening, overwrite `<project>/sound/songs/midi/mus_session_test.mid` with
  `makeMidiFixture()` plus one extra note chunk. The chunk plays channel 1, key 72:
  on at tick 0 with velocity 100, off at tick 24, `endTick: 192`. This gives the song a
  second used track (the fork required `alternateTrack`).
- Open `mus_session_test` through `openProjectAndSong(path:label:)` and
  `mus_session_test2` through `openSong(label:)`, then reselect the first tab. The
  second tab stays so the strip has a sibling, as in the fork's two-song session.

Seeding, through production ingress only (the same calls as
`session_view_state.swift:457-465`):
- `document.mutateCamera`, which in order calls:
  - `setTimeZoom(opened.pixelsPerBeat * 2)`
  - `setKeyHeight(opened.keyHeight * 1.5)`
  - `setHScroll($0.maxHScroll / 2)`
  - `setVScroll($0.maxVScroll / 2)`
- `document.selectedTrack = 1`
- `page.gridPresenter().setEditCursorTick(tick: 48)`
- `openGridMenu(kind: 1)` + `activateGridMenuRow(actionId: 16)`
- `openGridMenu(kind: 2)` + `activateGridMenuRow(actionId: 1)`
- `app.songTabs.setSelectedTabEventsVisible(visible: true)`

Capture `seededCamera = document.camera.snapshot` and the division and triplet values
from `gridPresenter()`.

Three predicates, with these exact message literals:
1. Precondition: `"A025 seeded reload view differs from the opened zoom key height scroll track cursor grid and Event List"`.
   It is true iff all of the following hold:
   - `seededCamera.pixelsPerBeat`, `.keyHeight`, `.scrollX` and `.scrollY` each
     differ from the opened snapshot.
   - `document.document.notes(in: 1)` is non-empty and `document.selectedTrack == 1`.
   - `document.editCursor == 48`.
   - `gridSelectionMenuId == 16` and `tripletGrid`.
   - `page.showsEvents` and `app.songTabs.selectedTabShowsEvents`.

   On failure, no further predicate runs, so the scenario fails closed.
2. Refusal: `"A025 event-loop observations refuse any dropped view member while the reload is pending"`.
   - Call `app.openSong(label: "mus_session_test")`. The on-disk MIDI is unchanged; the
     fork also reloads the same file.
   - Poll `until` the selected page is a ready page other than the original. On every
     turn where `app.songTabs.selectedPage === page` and `!page.isReady`, set `dropped`
     if any of the following differs from its seed: `document.camera.snapshot` vs
     `seededCamera` (whole-snapshot equality), `selectedTrack`, `editCursor`, grid
     division, triplet, `page.showsEvents`, `selectedTabShowsEvents`.
   - Also set `dropped` if any turn sees `tabCount != 2`, or a selected page with a
     different `tabId`.
   - Expect `!dropped && arrived && sawPending`. `sawPending` records at least one
     pending turn, which makes the observation non-vacuous. `page.isReady` becomes
     false synchronously in `reloadApproved`, so the first turn is pending.
3. Landing: `"A025 the ready replacement carries every seeded view member"`. Let
   `replacement = app.selectedDocument` and `landed = app.songTabs.selectedPage`. It
   is true iff all of the following hold:
   - `landed.tabId == page.tabId`, `landed !== page` and `replacement !== document`.
   - `replacement.camera.snapshot`'s `pixelsPerBeat`, `keyHeight`, `scrollX` and
     `scrollY` equal `seededCamera`'s.
   - `selectedTrack == 1` and `editCursor == 48`.
   - `landed.gridPresenter()` has division 16 and triplet feel.
   - `landed.showsEvents` and `selectedTabShowsEvents`.

Compare only against the pre-reload captures and these independent literals. Read no
test-only property.

Ledger:
- Append these entries after S334:
  - `S335 | sessionReloadRetainsViewState | src/checks/workspace/session_io.swift` +
    `Anchor: message "<literal 1>"`
  - S336 for literal 2 and S337 for literal 3, with the same header shape.
- A025 compact form: header,
  `Disposition: RETIRED-REPRESENTATION`,
  `Mapping/reason: Sprint-3 ruling (3) retires the fork's staged not-ready view state as unreachable under atomic reload: the original tab stays live until the complete replacement swaps in; S336 is the executing event-loop refusal of any dropped camera, track, cursor, grid or Event List member while pending, S337 observes the replacement carrying all of them (S335 guards the seed). [S335][S336][S337]`
- Drop A025's Source context and Original expression bodies.

# Implementation steps

1. Add the scenario and its call line. Keep comments to at most 2 lines, and follow
   Swift 6.4 main-actor isolation as the sibling scenario does.
2. `deno task build:checks`, then run the lane. All three messages must pass. If
   literal 3 fails, the landing path genuinely drops a member: stop and report it. Do
   not weaken the clause or edit production.
3. Append S335–S337 with a direct text edit. `proof:edit` cannot create entries.
4. Edit A025 with `deno task proof:edit src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt A025 --before '<Disposition … Original expression block>' --after '<compact block above>' --apply`.
5. Put the scenario and the ledger change in one commit.

# Acceptance predicate

In the real session, with one reload of the selected tab, the live tab exposes no dropped
view member on any pending event-loop turn. The ready replacement carries all nine
seeded members, and the fork's staged not-ready state is refused, not ported.

```sh
deno task build:checks
deno task checks --filter swiftcore-projectsession --verbose
deno task proof check --executed
deno task proof show src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt A025
```

- The lane covers all three predicates on production `ApplicationSession`,
  `SongTabsController`, `DocumentSession` and `PianoGrid`.
- `proof check --executed` must report 0 errors and no
  `proof.tst_mainwindowrouting_lifecycle.txt S335|S336|S337: not executed` line.
- `proof show` must print `Disposition: RETIRED-REPRESENTATION` citing
  S335/S336/S337.
- Coverage gaps, named:
  - Event List visibility toggles between polls are not observed. The fork's
    `eventListTraffic` spy is a separate, already-closed row; this row is only
    `!stateDropped`.
  - Mounted QML focus retention (`focusWidget`) is representation and already closed.
  - The fixture-root sidecar snapshot (A031) is project-store work and stays PARTIAL.

# Task-specific constraints

- No production or staged-binding API (the ruling's point is its absence).
- Do not change `sessionReloadAtomicBinding` or `runTabReadinessChecks`, or their
  messages.
- Do not touch lifecycle rows other than A025, or S IDs other than S335–S337.
- Do not add input-gate claims. The fork had no input gate beyond readiness, so do not
  invent one.
- If the close-harness task has already appended S entries, renumber to the next free
  IDs and keep the literals.
- Use no `Qt.callLater`, sleeps outside the run-loop helper, or test-only reads.
