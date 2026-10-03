# Task 84 brief — session restart and close/reopen preserve the right state

# Context

Own the mounted shell's restore-from-preferences, close-one/reopen and in-place
reload journeys. A restart restores the project, ordered songs, selected song
and Songs filters without rewriting the recipe; closing and reopening a song
creates fresh per-song view state, while reloading in place retains it. These
are distinct contracts, not one generic 'reopen retains everything' rule.
Task 83 supplies durable shared drawer preferences; this task consumes them.

Freeze: HEAD `e334b318ecf391e3d4fac512c4a613303aff01e3`; oracle `fceecd88`.
**Rebase after 82 lands** for `DocumentWorkspace.swift`; retain its bank-driven
drum keyboard refresh. Rebase after task 83 for the shared session/codec/check.
No task 79–82 assertion row is selected.

1. **Verified census: 34 open rows (27 GAP, 7 PARTIAL)**, checked with
   `deno task proof sites <ledger> --status GAP|PARTIAL`, including later pages:
   - `workspace/proof.session.txt`: PARTIAL **2** — A002, A005; GAP **18** —
     A003, A004, A006, A008, A018, A019, A020, A021, A022, A026, A029,
     A031, A032, A038, A039, A040, A043, A044.
   - `mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt`: PARTIAL
     **5** — A002, A003, A005, A008, A028; GAP **9** — A006, A009, A013,
     A014, A015, A016, A017, A018, A026.
   - Lifecycle A005 (`QVERIFY(reopened)`) and A008 (`QVERIFY(reopened->timeline())`)
     are native pointer-only observations: retire those two representations
     inside this owning journey, with fork evidence. The readiness, named-tab
     absence, fresh-view and reload-value laws remain behavior. Target: **32
     behavior rows plus 2 RETIRED-REPRESENTATION**, not new pointer tests.
2. **Fork laws**, read at `fceecd88`:
   - `src/checks/workspace/session.cpp`, `restoreProjectOnly`: no recipe and
     vanished project leave the generic title and zero tabs; project-only
     restore shows the project title, an Opened status and no song tab.
   - `closeReopenPreservesSession`: a recipe containing `lastProjectDir` and
     `lastSongLabel` without `lastOpenSongs` opens and reveals that song.
     Close saves geometry, project/song/order and search; the later filtered
     restart restores title, sort and category without rewriting saved settings.
     `deletedRecipeSongIsIgnored` restores the project but no missing-song tab.
     Its geometry law is persistence on close, **not** exact relaunch dimensions.
   - `src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp`,
     `closeAndReopenProjectsGlobalState`: the named closed song disappears,
     the sibling survives, and reopening is ready with canonical fresh view.
     `readyReloadPreservesTransients` retains non-default camera, selected
     track, cursor, grid division/triplet and Event List through reload.
   - `mainwindowroutingfixture.h`, `hasCanonicalFreshViewState` and
     `sameViewState`: fresh means default zoom/key height, cursor zero,
     automatic straight grid, roll not Event List, first used track, and the
     same scroll as a home/reset. Retained reload means every corresponding
     value, not a pointer inequality or a rounded scene summary.
3. **Current state**, verified by reads:
   - `src/swift/app/timeline/EditorViewStateCodec.swift:112-129` loads/saves
     the recipe but loads absent `lastOpenSongs` as `[]`: the legacy
     selected-song-only ingress is missing. `WorkspaceTabRecipe.normalized`
     at `:18-24` already handles missing/duplicate songs and fallback selection.
   - `src/swift/app/ApplicationSession.swift:630-650,734-766,783-867,
     1073-1097` owns startup, serialized project replacement, ready-only tab
     installation and restore-time persistence suppression. It already retains
     reload camera/grid/cursor in `openTab`; do not add staged C++ readiness.
   - `src/swift/app/SongTabsController.swift:135-154,255-259,275-283,338-349`
     owns `ReloadedTab`, recipe strip order, label lookup and close. These
     contracts are reused, not replaced.
   - `src/swift/app/shell/ShellPresenter.swift:446-471,482-509,517-550`
     owns startup, title/status and window/filter persistence. Successful
     project-only open currently refreshes title without publishing Opened
     status (`src/ui/shell/ShellWindow.qml:118-122`).
     Its mounted `shellStatusText` at `ShellWindow.qml:733-746` binds that
     status; the QML journey observes the rendered item, not the presenter alone.
   - `ShellWindow.qml:79-102,193-213` configures and restores at actual mount,
     and persists only after the close gate accepts. `SongListPresenter.swift:
     165-179,191-200` under `src/swift/app/songlist/` owns filter restoration
     and the loaded-song row, including the pending category.
   - `src/checks/editorqml/tst_ShellTabs.qml:90-129` deliberately clears the
     startup recipe in `openShell`; it cannot prove restore ingress.
     `:789-821` closes/reopens two real songs; `:1417-1472` already checks
     reload values, but the selected ledger still cites older partial checks.
     Preserve those meaningful existing messages and extend actual scenarios,
     not a ledger-only re-anchoring pass.

# Exact write set

- `src/swift/app/ApplicationSession.swift`
- `src/swift/app/DocumentWorkspace.swift`
- `src/swift/app/timeline/EditorViewStateCodec.swift`
- `src/swift/app/shell/ShellPresenter.swift`
- `src/swift/app/songlist/SongListPresenter.swift`
- `src/ui/shell/ShellWindow.qml`
- `src/checks/workspace/session_view_state.swift`
- `src/checks/editorqml/tst_ShellTabs.qml`
- `src/checks/workspace/proof.session.txt` — selected rows and their predicates only.
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt` — selected rows and their predicates only.

Only demonstrated divergences justify changes in the existing workspace/filter
owners. No new source file, CMake, native API, fake load delay or test probe.
`SongTabsController.swift`, `DocumentSession.swift`, `EditorCommandRouter.swift`,
`EditorSurface.qml`, `PianoGrid.swift`, `tst_ShellWindow.qml` and
`tst_EditorDrawer.qml` are read-only dependencies.

# Prerequisites

Task 83's shared drawer persistence is accepted before reuse of ApplicationSession,
the codec and session view-state check. **Rebase after 82 lands** for the
workspace change set. Tasks 79–81 contribute no new interface this task requires.
The exact parallel group/hot-file schedule is sprint-3 §9.

# Interface contract

- Preserve `EditorViewStateCodec.loadTabs(store:) -> WorkspaceTabRecipe` and
  `saveTabs(_:store:)`. When the ordered-song key is absent and the selected
  song is nonempty, load the one-song legacy recipe. An explicitly present
  empty ordered list stays empty; do not append the selected song to a valid
  ordered list. Use the existing `normalized(available:)` semantics unchanged.
- Add `ShellPresenter.projectOpenChanged()`: refresh window chrome and, only
  on a successful open project, publish `Opened ` plus its project path into
  the existing status field. Route the current QML project-open handler through
  it once and retain actionRevision publication. Failure keeps the existing
  error path; no startup dialog suppression or new dispatcher.
- Preserve `openStartup()`, `configureSettings(applicationName:)`,
  `persistSessionState(x:y:width:height:maximized:debuggerVisible:)`,
  `ApplicationSession.openSong(label:)`, `requestCloseAll()` and ready-only
  `openTab`. Successful restoration of the saved live project performs no
  preference normalization write and never creates an ignored/missing-song
  phantom tab. Preserve the existing vanished-project failure handling at
  `ApplicationSession.swift:743-751`; its recipe repair is not A029/A032's
  successful-restore invariance scenario.
- Close one tab: assert exact remaining label/order and absent closed label,
  retain sibling content, then reopen and assert real loaded content plus every
  canonical fresh-view field. Shared drawer preferences remain global; cursor,
  camera, selected track, grid and Event List are per-song transients.
- Reload the live song: seed alternate used track, non-default horizontal and
  vertical camera, cursor, musical-16 triplet grid and Event List; observe all
  seeded fields, then all retained values after the genuine replacement is ready.
  Do not introduce a fake not-ready stage to mimic the old C++ implementation.
- Restart by closing/destroying a real ShellWindow and constructing a fresh one
  against the same staged store, without `openProject*` calls on the restored
  shell. Observe exact restored title, tab order and search/sort/category.
  A008's selected loaded-song row belongs to the initial selected-song-only
  restore, before setting `filterme`; do not require a filtered-out song to
  remain selected or visible after the later filtered restart. Snapshot actual
  session/editor preference keys before/after restore in the Swift check using
  the existing staged plist. A018 checks exact saved normal-frame fields, not
  a bare nonempty blob.
- Preserve every existing message verbatim. Each constituent of fresh or retained
  view state and each settings invariant has its own literal anchor. Pointer
  retirement is documented from the two exact fork expressions, not inferred
  from a related green test.

# Implementation steps

1. Add the startup recipe cases before changing production: empty, vanished
   project, project-only, selected-song-only, missing-song list and ordinary
   ordered songs. Drive the real ShellWindow creation path; the legacy recipe
   and successful project status must expose the current gaps.
2. Repair recipe decoding and the existing project-open status ingress. Keep
   async replacement, close gate, restore suppression and explicit-open
   precedence intact; no new readiness flags or guards.
3. Extend close/reopen with named-tab absence, sibling survival and the entire
   canonical fresh state. Extend the existing in-place reload with an alternate
   used track and every fork-seeded field; use real loaded content/scene readiness.
4. Add the complete close/destroy/recreate journey, including font-relative
   window resize, actual Songs search/sort/category controls, saved exact keys
   and unchanged restore snapshot. Existing `openShell` remains an explicit-open
   helper; do not silently change every caller to restore stale preferences.
5. Run the named lanes after the group settles. Map 32 behavior rows only with
   executed clauses and retire the two native pointer rows in this same feature
   change. Leave all sidecar and full live-lane-state rows outside this task.

# Acceptance predicate

Controller-run on the settled built tree, each invocation at most 180 s:

- `deno task verify --filter swiftcore-projectsession --verbose` — recipe
  compatibility, exact persisted-key snapshots, shared-state preservation and
  ready-only document/view outcomes; `build/proof-evidence/swiftcore-projectsession.json`.
- `deno task verify:shell --filter shell-tabs --verbose` — mounted startup,
  close/destroy/recreate, actual Songs controls, title/status, close-one/reopen
  and in-place reload; `build/proof-evidence/shell-tabs.json`.

Registration: `src/checks/workspace/SessionChecks.swift:43`,
`src/checks/checkcatalog.cpp:107-125`, and
`src/checks/editorqml/ShellQmlTests.swift:86-87`. Evidence writer:
`tools/run_checks.ts:426-434`. All shell lanes may also run together in about
40 s with `deno task verify:shell --verbose`; the named filter isolates this
surface. Offscreen QML proves the real mounted lifecycle, not desktop placement.

# Task-specific constraints

Carry sprint-3 §8 Wave constraints and §9 verification policy: **no new C++**;
touched Swift uses Swift 6.4 idioms without avoidable allocation/copy; comments
at most two lines; base-font sizing and no hard-coded pixels; WCAG AA beats
pixel parity. Keyboard priority is unchanged: no second dispatcher, synthetic
forwarding, focus memory or bare Space claim in chrome. Ban `Qt.callLater`
coalescing and idempotence guards; workarounds require user approval. Use one
message-anchored predicate per fork clause, preserve existing messages verbatim,
real fixtures and no test-only seams.

Do not persist per-song camera across a full close: the fork requires fresh
state there and retention only for in-place reload. Cursor commits never seek.
Leave workspace session A024/A042 and lifecycle A004/A010/A031 sidecar snapshots
blocked on the parked project-store boundary. Full live lane fanout/equality
(session A011/A012/A028/A033/A034; lifecycle A007) remains unselected, not
silently retired. Parked areas, deferred menus, savecore A016–A026 and switching
A030–A046 stay untouched; no user policy decision is made here.

# Controller verification

After fresh evidence run `deno task proof check --executed`, then separately:

- `deno task proof sites workspace/proof.session.txt --status GAP`
- `deno task proof sites workspace/proof.session.txt --status PARTIAL`
- `deno task proof sites mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt --status GAP`
- `deno task proof sites mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt --status PARTIAL`

Expected: the selected 32 behavior rows MATCHED and lifecycle A005/A008
RETIRED-REPRESENTATION with exact fork reasons. No ledger deletion; all other
rows keep their dispositions.
